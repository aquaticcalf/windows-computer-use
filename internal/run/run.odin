package run

import "../win32"
import "core:os"
import "core:strings"
import "core:sys/windows"

// Shell command execution with stdout/stderr capture. Only the CLI calls this
// through an approval gate; the module itself does not decide who may run.
// See ARCHITECTURE.md (Actions: run) and DESIGN.md.

// Result captures the outcome of one shell command.
Result :: struct {
	// Stdout is the child's captured stdout, or "" when none.
	Stdout:    string,
	// Stderr is the child's captured stderr, or "" when none.
	Stderr:    string,
	// Exit_Code is the process exit code, meaningful only when Started.
	Exit_Code: u32,
	// Started reports whether the process was created at all.
	Started:   bool,
	// Timed_Out reports that the process was still running when the caller's
	// timeout elapsed and had to be terminated.
	Timed_Out: bool,
}

// destroy frees the strings inside a result.
destroy :: proc(r: ^Result) {
	delete(r.Stdout)
	delete(r.Stderr)
}

// run_command starts the given command line with its standard output and
// error piped back, waits up to timeout_ms, and returns the captured output.
// The caller owns the returned strings and frees them with destroy.
run_command :: proc(
	command: string,
	timeout_ms: u32 = 30_000,
	allocator := context.allocator,
) -> Result {
	cmd_wide: [1024]u16
	cmd_ptr := windows.utf8_to_wstring_buf(cmd_wide[:], command)

	out_read, out_write: windows.HANDLE
	err_read, err_write: windows.HANDLE
	in_read, in_write: windows.HANDLE
	sec_attr := windows.SECURITY_ATTRIBUTES {
		nLength              = size_of(windows.SECURITY_ATTRIBUTES),
		lpSecurityDescriptor = nil,
		bInheritHandle       = windows.BOOL(true),
	}
	if !windows.CreatePipe(&out_read, &out_write, &sec_attr, 0) ||
	   !windows.CreatePipe(&err_read, &err_write, &sec_attr, 0) ||
	   !windows.CreatePipe(&in_read, &in_write, &sec_attr, 0) {
		return Result{Started = false}
	}
	// The child inherits the write ends; the parent keeps the read ends and
	// must clear inheritance on them so the child cannot hold them open (which
	// would make read_pipe wait forever).
	windows.SetHandleInformation(out_read, 0x00000001, 0)
	windows.SetHandleInformation(err_read, 0x00000001, 0)
	windows.SetHandleInformation(in_write, 0x00000001, 0)

	startup := windows.STARTUPINFOW {
		cb         = size_of(windows.STARTUPINFOW),
		dwFlags    = windows.STARTF_USESTDHANDLES,
		hStdInput  = in_read,
		hStdOutput = out_write,
		hStdError  = err_write,
	}
	proc_info: windows.PROCESS_INFORMATION
	created := windows.CreateProcessW(
		nil,
		cmd_ptr,
		nil,
		nil,
		windows.BOOL(true),
		win32.CREATE_NO_WINDOW,
		nil,
		nil,
		&startup,
		&proc_info,
	)
	windows.CloseHandle(out_write)
	windows.CloseHandle(err_write)
	windows.CloseHandle(in_read)
	windows.CloseHandle(in_write)
	if !created {
		windows.CloseHandle(out_read)
		windows.CloseHandle(err_read)
		return Result{Started = false}
	}
	defer windows.CloseHandle(proc_info.hThread)

	// Wait for the process first so the timeout applies even if the child
	// keeps its output pipe open; then read whatever it produced.
	wait := windows.WaitForSingleObject(proc_info.hProcess, timeout_ms)
	timed_out := wait != 0

	if timed_out {
		windows.TerminateProcess(proc_info.hProcess, 1)
	}

	stdout := read_pipe(out_read, allocator)
	stderr := read_pipe(err_read, allocator)
	windows.CloseHandle(out_read)
	windows.CloseHandle(err_read)

	exit_code: u32 = 1
	windows.GetExitCodeProcess(proc_info.hProcess, &exit_code)
	if timed_out {
		exit_code = 1
	}
	windows.CloseHandle(proc_info.hProcess)

	return Result {
		Stdout = stdout,
		Stderr = stderr,
		Exit_Code = exit_code,
		Started = true,
		Timed_Out = timed_out,
	}
}

// read_pipe drains a pipe handle to EOF and returns its contents.
read_pipe :: proc(handle: windows.HANDLE, allocator := context.allocator) -> string {
	builder := strings.builder_make(allocator)
	buf: [4096]u8
	for {
		read: windows.DWORD
		ok := windows.ReadFile(handle, &buf[0], u32(len(buf)), &read, nil)
		if !ok || read == 0 {
			break
		}
		strings.write_bytes(&builder, buf[:read])
	}
	return strings.to_string(builder)
}

// approved reports whether the WCU_ALLOW_RUN gate permits shell execution.
approved :: proc(allocator := context.allocator) -> bool {
	value, found := os.lookup_env_alloc("WCU_ALLOW_RUN", allocator)
	if found {
		defer delete(value, allocator)
	}
	return found && value == "1"
}

// set_approved_for_test enables or disables the gate for tests.
set_approved_for_test :: proc(enabled: bool) {
	if enabled {
		os.set_env("WCU_ALLOW_RUN", "1")
	} else {
		os.unset_env("WCU_ALLOW_RUN")
	}
}
