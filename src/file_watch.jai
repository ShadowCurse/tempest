WatchedFile :: struct {
  wd:   s32;
  path: string;
}

FileWatcher :: struct {
  fd:    s32;
  files: [..]WatchedFile ;
};

init :: (watcher: *FileWatcher) -> bool {
  fd := inotify_init(O_NONBLOCK);
  if fd < 0 {
    log_error("Cannot init FileWatcher: %", fd);
    return false;
  } else {
    watcher.* = .{ fd = fd };
    return true;
  }
}

add_file :: (watcher: *FileWatcher, path: string) -> bool {
  wd := inotify_add_watch(watcher, path);
  if wd != -1 {
    array_add(*watcher.files, .{ wd, copy_string(path) });
    return true;
  } else {
    log_error("Could not watch file %: %", path, errno());
    return false;
  }
}

has_event :: (watcher: *FileWatcher) -> string {
  if watcher.fd != 0 {
    // just enough bytes for a single event
    buff: [(size_of(inotify_event) + 256) / 4]u32 = ---;
    n := read(watcher.fd, buff.data, cast(u64)buff.count * 4);
    if n == -1 && errno() != EAGAIN {
      log_error("Could not read events from file watcher: % errno: %", n, errno());
      return {};
    }
    if n <= 0 return {};
    event := cast(*inotify_event)buff.data;
    for *it: watcher.files if it.wd == event.wd {
      new_wd := inotify_add_watch(watcher, it.path);
      if new_wd != -1 {
        it.wd = new_wd;
        return it.path;
      } else {
        log_error("Could not watch file %: %", it.path, errno());
        array_unordered_remove_by_index(*watcher.files, it_index);
        return {};
      }
    }
  }
  return {};
}

#scope_file

inotify_add_watch :: (watcher: *FileWatcher, path: string) -> s32 {
  c_path := temp_c_string(path);
  flags := IN_MODIFY | IN_CLOSE_WRITE;
  return inotify_add_watch(watcher.fd, c_path, xx flags);
}

#import "Linux";
#import "POSIX";
#import "Basic";
