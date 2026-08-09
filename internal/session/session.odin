package session

import "../config"
import "../win32"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:sys/windows"

// Session records which agent owns which target and how much work is queued,
// so operators can see everything active at a glance. Sessions persist to a
// JSON file in the config dir, which lets `wcu status` list sessions created
// by another process. See ARCHITECTURE.md (Concurrency) and DESIGN.md.

// Record is one agent session at a point in time.
Record :: struct {
	// id is the agent id this session belongs to.
	id:      string,
	// pid is the process holding the session; used to prune dead sessions.
	pid:     u32,
	// target is the claimed window handle, as an opaque numeric id.
	target:  u64,
	// pending is how many frames sit in the agent's arbiter stack.
	pending: int,
	// paused reports whether the agent's stack is paused.
	paused:  bool,
	// started is the unix time (seconds) the session began.
	started: i64,
}

// Registry holds the known sessions and mirrors them to the registry file so
// other processes can read them. It is safe for concurrent use.
Registry :: struct {
	mu:       sync.Mutex,
	sessions: [dynamic]Record,
	// path is the registry file location.
	path:     string,
}

// Error is this package's error type.
Error :: enum {
	// None reports a successful operation.
	None,
	// Not_Found reports that a session or the registry file does not exist.
	Not_Found,
	// Write_Failed reports that the registry file could not be written.
	Write_Failed,
	// Parse_Failed reports that the registry file could not be read or
	// decoded.
	Parse_Failed,
	// Open_Failed reports that the config directory could not be prepared.
	Open_Failed,
}

// open builds a registry at the given registry path (default: the shared
// config path), loading any existing sessions. The path is copied, so the
// caller keeps ownership of the string it passes. A missing registry file is
// fine: it starts empty. Call destroy when done.
open :: proc(path := "", allocator := context.allocator) -> (Registry, Error) {
	registry_path := path
	if registry_path == "" {
		registry_path = config.sessions_path(allocator)
	} else {
		registry_path = strings.clone(registry_path, allocator)
	}
	reg := Registry {
		path = registry_path,
	}
	if err := load(&reg); err == .None || err == .Not_Found {
		return reg, .None
	}
	return reg, .Parse_Failed
}

// destroy frees a registry, its sessions, and its path.
destroy :: proc(r: ^Registry) {
	for rec in r.sessions {
		delete(rec.id)
	}
	delete(r.sessions)
	delete(r.path)
}

// register upserts a session and persists the registry. The id is copied, so
// the caller keeps ownership of the record it passes. A session with an
// existing id is replaced.
register :: proc(r: ^Registry, rec: Record) -> Error {
	sync.guard(&r.mu)
	owned := rec
	owned.id = strings.clone(rec.id)
	for i in 0 ..< len(r.sessions) {
		if r.sessions[i].id == rec.id {
			delete(r.sessions[i].id)
			r.sessions[i] = owned
			return save(r)
		}
	}
	append(&r.sessions, owned)
	return save(r)
}

// unregister removes the session with the given id and persists the registry.
// It returns Not_Found when no such session exists.
unregister :: proc(r: ^Registry, id: string) -> Error {
	sync.guard(&r.mu)
	for i in 0 ..< len(r.sessions) {
		if r.sessions[i].id == id {
			delete(r.sessions[i].id)
			ordered_remove(&r.sessions, i)
			return save(r)
		}
	}
	return .Not_Found
}

// update mutates the session with the given id under the registry lock and
// persists. It returns Not_Found when no such session exists.
update :: proc(r: ^Registry, id: string, mutator: proc(_: ^Record)) -> Error {
	sync.guard(&r.mu)
	for i in 0 ..< len(r.sessions) {
		if r.sessions[i].id == id {
			mutator(&r.sessions[i])
			return save(r)
		}
	}
	return .Not_Found
}

// get returns the session with the given id, if any.
get :: proc(r: ^Registry, id: string) -> (Record, bool) {
	sync.guard(&r.mu)
	for rec in r.sessions {
		if rec.id == id {
			return rec, true
		}
	}
	return {}, false
}

// list returns a copy of all known sessions, allocated with the supplied
// allocator. The caller owns the result.
list :: proc(r: ^Registry, allocator := context.allocator) -> []Record {
	sync.guard(&r.mu)
	out := make([]Record, len(r.sessions), allocator)
	copy(out, r.sessions[:])
	return out
}

// active returns the sessions whose owning process is still running,
// allocated with the supplied allocator. The caller owns the result.
active :: proc(r: ^Registry, allocator := context.allocator) -> []Record {
	recs := list(r, allocator)
	defer delete(recs)
	out := make([dynamic]Record, 0, len(recs), allocator)
	for rec in recs {
		if pid_alive(rec.pid) {
			append(&out, rec)
		}
	}
	return out[:]
}

// pid_alive reports whether the given pid names a live process. A pid of zero
// is never alive.
pid_alive :: proc(pid: u32) -> bool {
	if pid == 0 {
		return false
	}
	handle := win32.OpenProcess(
		windows.PROCESS_QUERY_LIMITED_INFORMATION,
		windows.BOOL(false),
		pid,
	)
	if handle == nil {
		return false
	}
	defer windows.CloseHandle(handle)
	return true
}

// save writes the registry to its file atomically: the new contents go to a
// temp file that is renamed over the real one, so a concurrent reader never
// sees a half-written registry.
save :: proc(r: ^Registry) -> Error {
	if d := os.dir(r.path); d != "." && !os.is_dir(d) {
		if err := os.make_directory(d); err != nil {
			return .Open_Failed
		}
	}
	data, jerr := json.marshal(r.sessions[:])
	if jerr != nil {
		return .Write_Failed
	}
	defer delete(data)
	tmp := fmt.aprintf("%s.tmp", r.path)
	defer delete(tmp)
	if werr := os.write_entire_file(tmp, data); werr != nil {
		return .Write_Failed
	}
	if rerr := os.rename(tmp, r.path); rerr != nil {
		os.remove(tmp)
		return .Write_Failed
	}
	return .None
}

// load reads the registry file into memory. A missing file is Not_Found.
load :: proc(r: ^Registry) -> Error {
	data, err := os.read_entire_file(r.path, context.allocator)
	if err != nil {
		return .Not_Found
	}
	defer delete(data)
	recs: []Record
	if jerr := json.unmarshal(data, &recs); jerr != nil {
		return .Parse_Failed
	}
	for rec in recs {
		append(&r.sessions, rec)
	}
	delete(recs)
	return .None
}

// ordered_remove removes index i from the dynamic, preserving order.
ordered_remove :: proc(arr: ^[dynamic]Record, i: int) {
	for j in i ..< len(arr) - 1 {
		arr[j] = arr[j + 1]
	}
	pop(arr)
}
