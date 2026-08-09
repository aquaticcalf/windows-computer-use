package config

import "core:os"
import "core:path/filepath"

// Config resolves where wcu keeps its mutable data. wcu stores data in a dot
// directory next to the executable, so a self-contained install carries its
// data with it. See ARCHITECTURE.md and DESIGN.md.

// DIR_NAME is the config directory name, placed next to the executable.
DIR_NAME :: ".wcu"

// SESSIONS_FILE is the session registry file inside the config dir.
SESSIONS_FILE :: "sessions.json"

// dir returns wcu's config directory: $WCU_CONFIG_DIR when set, else a .wcu
// directory next to the executable when that location is writable, else
// %LOCALAPPDATA%\wcu. The returned string is allocated with the supplied
// allocator and owned by the caller.
dir :: proc(allocator := context.allocator) -> string {
	if override := os.get_env("WCU_CONFIG_DIR", allocator); override != "" {
		return override
	}
	if exe_dir, err := os.get_executable_directory(allocator); err == nil {
		candidate, _ := filepath.join([]string{exe_dir, DIR_NAME}, allocator)
		if os.is_dir(candidate) || os.make_directory(candidate) == nil {
			delete(exe_dir, allocator)
			return candidate
		}
		delete(candidate, allocator)
		delete(exe_dir, allocator)
	}
	local := os.get_env("LOCALAPPDATA", allocator)
	defer delete(local)
	path, _ := filepath.join([]string{local, "wcu"}, allocator)
	return path
}

// sessions_path returns the full path to the session registry file,
// allocated with the supplied allocator and owned by the caller.
sessions_path :: proc(allocator := context.allocator) -> string {
	d := dir(allocator)
	defer delete(d)
	path, _ := filepath.join([]string{d, SESSIONS_FILE}, allocator)
	return path
}

// ensure_dir creates the config directory (and its parents) when missing and
// reports whether the directory exists afterwards.
ensure_dir :: proc() -> bool {
	d := dir()
	defer delete(d)
	if os.is_dir(d) {
		return true
	}
	return os.make_directory(d) == nil
}
