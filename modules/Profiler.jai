get_perf_counter :: rdtc;

rdtc :: inline () -> u64 {
  high: u64 = ---;
  low:  u64 = ---;
  #asm {
    low  === a;
    high === d;
    rdtsc high, low;
  }
  return (high << 32) | low;
}

get_perf_counter_frequency :: tsc_freq;

tsc_freq :: inline () -> u64 {
  s := get_perf_counter();

  t: timespec = .{ tv_sec = 0, tv_nsec = 1000_000 };
  clock_nanosleep(.MONOTONIC, 0, *t, null);

  e := get_perf_counter();
  return (e - s) * 1000;
}

Time :: struct {
  start: u64;
  end:   u64;
}

ZoneInfo :: struct {
  name: string;
  line: u64;
}

ZonePoint :: struct {
  start_time:            u64;
  parent:                *Zone;
  current:               *Zone;
  current_with_children: u64;
}

Zone :: struct {
  without_children: u64;
  with_children:    u64;
  hit_count:        u64;
  // align size to 32 bytes so the cache line is divided into
  // whole number of Measurements
  _:                u64;
};

ZoneNode :: struct {
  zone_index:  u32;
  parent:      u32;
  first_child: u32;
  last_child:  u32;
  next:        u32;
  dt:          u64;
}

init_prof :: () {
  #if !PROF_ZONES_COUNT return;
  take_thread_id();
  if context.thread_id == 0 then global_freq = get_perf_counter_frequency();
  context.prof_zones = NewArray(PROF_ZONES_COUNT, Zone);

  // ~3MB
  context.prof_graph_array = NewArray(100000, ZoneNode);
  // 0 is the root
  context.prof_graph_array_last = 1;
  context.prof_graph_current    = 0;
}

deinit_prof :: () {
  #if !PROF_ZONES_COUNT return;
  free(context.prof_zones.data);
}

// note(sc): called once per thread
prof_record_thread_start :: () {
  #if !PROF_ZONES_COUNT return;
  context.prof_time.start = get_perf_counter();
}

prof_record_thread_end :: () {
  #if !PROF_ZONES_COUNT return;
  context.prof_time.end = get_perf_counter();
}

take_thread_id :: () {
  #if !PROF_ZONES_COUNT return;
  context.thread_id = atomic_add(*global_last_thread_id, 1);
}

prof_new_frame :: () {
  #if !PROF_ZONES_COUNT return;
  memset(context.prof_zones.data, 0, context.prof_zones.count * size_of(Zone));

  context.prof_graph_array_last = 1;
  context.prof_graph_current    = 0;
}

// Marks the scope to be profiled. Replaced by profiler with
// t := prof_start(%);
// defer prof_end(%, t);
prof_scope :: ($name: string) {}

prof_print :: () {
  #if !PROF_ZONES_COUNT return;

  freq:    float64 = cast(float64)global_freq;
  elapsed: float64 = cast(float64)(context.prof_time.end - context.prof_time.start);
  name_buf: [PROF_ZONE_LONGEST_NAME_LEN]u8;
  for PROF_ZONES_INFOS {
    memset(*name_buf, #char " ", name_buf.count);
    memcpy(*name_buf, it.name.data, it.name.count);

    zone := *context.prof_zones[it_index];
    if zone.hit_count != 0 {
      without_children_ms := cast(float64)zone.without_children / freq * 1000.0;
      without_children    := cast(float64)zone.without_children / elapsed * 100.0;
      with_children_ms    := cast(float64)zone.with_children / freq * 1000.0;
      with_children       := cast(float64)zone.with_children / elapsed * 100.0;
      log(#string,\% DONE
t: % | %:% | hit: % | exclusive: % cycles | % ms | %\% | inclusive: % cycles | % ms | %\%,
DONE,
        context.thread_id,
        cast(string)name_buf,
        formatInt(it.line,               minimum_digits = 6, padding = #char " "),
        formatInt(zone.hit_count,        minimum_digits = 3, padding = #char " "),
        formatInt(zone.without_children, minimum_digits = 9, padding = #char " "),
        formatFloat(without_children_ms, width = 2, trailing_width = 2),
        formatFloat(without_children,    width = 2, trailing_width = 2),
        formatInt(zone.with_children,    minimum_digits = 9, padding = #char " "),
        formatFloat(with_children_ms,    width = 2, trailing_width = 2),
        formatFloat(with_children,       width = 2, trailing_width = 2),
      );
    }
  }
  log("-----------");
  print_node :: (current_node_idx: u32, padding: u32) {
    current := *context.prof_graph_array[current_node_idx];
    for 0..padding print(" ");
    log("%:%: %", PROF_ZONES_INFOS[current.zone_index].name, PROF_ZONES_INFOS[current.zone_index].line, current.dt);
    if current.first_child {
     print_node(current.first_child, padding + 1);
    }
    if current.next {
      print_node(current.next, padding);
    }
  }
  print_node(0, 0);
  log("-----------");
}

#scope_module

prof_start :: (zone_index: u32) -> ZonePoint {
  current_counter := get_perf_counter();

  current_node_idx := context.prof_graph_current;
  new_node_idx     := context.prof_graph_array_last;
  current          := *context.prof_graph_array[current_node_idx];
  new_node         := *context.prof_graph_array[new_node_idx];
  new_node.* = .{
    zone_index = zone_index,
    parent     = current_node_idx,
  };
  new_node.dt -= current_counter;

  if current.last_child {
    current_last_child := *context.prof_graph_array[current.last_child];
    current_last_child.next = new_node_idx;
  }

  current.last_child         = new_node_idx;
  if !current.first_child then current.first_child = new_node_idx;
  context.prof_graph_current = new_node_idx;
  context.prof_graph_array_last += 1;


  parent := context.prof_current_zone;
  context.prof_current_zone = *context.prof_zones[zone_index];
  return .{
    start_time            = current_counter,
    parent                = parent,
    current               = context.prof_current_zone,
    current_with_children = context.prof_current_zone.with_children,
  };
}

prof_end :: (zone_index: u32, point: ZonePoint) {
  current_counter := get_perf_counter();

  current := *context.prof_graph_array[context.prof_graph_current];
  current.dt += current_counter;
  context.prof_graph_current = current.parent;

  end_time := current_counter;
  elapsed  := end_time - point.start_time;
  point.current.hit_count += 1;
  point.current.without_children += elapsed;
  point.current.with_children = point.current_with_children + elapsed;
  if point.parent then point.parent.without_children -= elapsed;
  context.prof_current_zone = point.parent;
}

prof_zone :: (zone_index: u32) #expand {
  __prof_zone_time := context.Prof_Module.prof_start(zone_index);
  `defer context.Prof_Module.prof_end(zone_index, __prof_zone_time);
}

#scope_file

global_freq:            u64;
global_last_thread_id:  u32;

#add_context Prof_Module :: #this;
#add_context thread_id:             u32;
#add_context prof_time:             Time;
#add_context prof_zones:            []Zone;
#add_context prof_current_zone:     *Zone;
// TODO: use fixed_slice
#add_context prof_graph_array:      []ZoneNode;
#add_context prof_graph_array_last: u32;
#add_context prof_graph_current:    u32;

#placeholder PROF_ZONES_COUNT;
#placeholder PROF_ZONES_INFOS;
PROF_ZONE_LONGEST_NAME_LEN :: #run -> s64 {
  longest := 0;
  for PROF_ZONES_INFOS if longest < it.name.count then longest = it.name.count;
  return longest;
};

// #import,file "allocators.jai";
#import "Basic";
#import "POSIX";
#import "Atomics";
