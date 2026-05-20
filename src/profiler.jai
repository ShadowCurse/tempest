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

init_prof :: () {
  #if !PROF_ZONES_COUNT return;
  take_thread_id();
  if context.thread_id == 0 then global_freq = get_perf_counter_frequency();
  context.prof_zones = new_array(PROF_ZONES_COUNT, Zone);
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
  // assert(thread_id == null, "% attempted taking multiple thread ids", std.Thread.getCurrentId());
  context.thread_id = atomic_add(*global_last_thread_id, 1);
}

prof_new_frame :: () {
  #if !PROF_ZONES_COUNT return;
  memset(context.prof_zones.data, 0, context.prof_zones.count * size_of(Zone));
}

// Marks the scope to be profiled. Replaced by profiler with
// t := prof_start(%);
// defer prof_end(%, t);
prof_scope :: ($name: string) {}

prof_print :: () {
  #if !PROF_ZONES_COUNT return;

  log("-----------");
  freq:    float64 = cast(float64)global_freq;
  elapsed: float64 = cast(float64)(context.prof_time.end - context.prof_time.start);
  for PROF_ZONES_NAMES {
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
        it.name, it.line,
        zone.hit_count,
        zone.without_children,
        without_children_ms,
        without_children,
        zone.with_children,
        with_children_ms,
        with_children,
      );
    }
  }
  log("-----------");
}

#scope_module

prof_start :: (zone_index: u32) -> ZonePoint {
  parent := context.prof_current_zone;
  context.prof_current_zone = *context.prof_zones[zone_index];
  return .{
    start_time            = get_perf_counter(),
    parent                = parent,
    current               = context.prof_current_zone,
    current_with_children = context.prof_current_zone.with_children,
  };
}

prof_end :: (zone_index: u32, point: ZonePoint) {
  end_time := get_perf_counter();
  elapsed := end_time - point.start_time;
  point.current.hit_count += 1;
  point.current.without_children += elapsed;
  point.current.with_children = point.current_with_children + elapsed;
  if point.parent then point.parent.without_children -= elapsed;
  context.prof_current_zone = point.parent;
}

#scope_file

global_freq:            u64;
global_last_thread_id:  u32;

#add_context Prof_Module :: #this;
#add_context thread_id:         u32;
#add_context prof_time:         Time;
#add_context prof_zones:        []Zone;
#add_context prof_current_zone: *Zone;

#placeholder PROF_ZONES_COUNT;
#placeholder PROF_ZONES_NAMES;

#import,file "allocators.jai";
#import "Basic";
#import "POSIX";
#import "Atomics";
