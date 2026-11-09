package odd_debug

import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:debug/trace"
import "core:fmt"
import "core:os"
import "core:sync"
import "shared:odd/thread"

_Signals :: enum {
	SIGABRT = libc.SIGABRT,
	SIGFPE  = libc.SIGFPE,
	SIGILL  = libc.SIGILL,
	SIGINT  = libc.SIGINT,
	SIGSEGV = libc.SIGSEGV,
	SIGTERM = libc.SIGTERM,
}

/*
Register a signal handler to capture the backtrace of the program.

The backtrace size can be customized with -define:ODIN_TRACE_SIZE.

The backtrace supports both .Odin and .Unix styles.
*/
register_backtrace :: proc() {
	when ODIN_DEBUG {
		for signal in _Signals {
			libc.signal(cast(i32)signal, _handler)
		}
	}
}

register_thread_backtrace :: proc() {
	when ODIN_DEBUG {
		for signal in _Signals {
			libc.signal(cast(i32)signal, _thread_handler)
		}
	}
}

_thread_handler :: proc "cdecl" (signal: c.int) {
	if thread.broadcast_error() {
		print_backtrace(signal)
	}

	parker: sync.Parker
	sync.park(&parker) // park forever
}

_handler :: proc "cdecl" (signal: c.int) {
	print_backtrace(signal)
	os.exit(int(signal))
}

print_backtrace :: proc "cdecl" (signal: c.int) {
	SKIP :: 3
	context = runtime.default_context()
	capture := trace.capture(SKIP) // 2 skip the signal handler stack trace
	locations, err := trace.resolve(capture)
	if err != nil {
		fmt.eprintfln("trace error: %v", err)
		return
	}
	location := locations[0]
	runtime.print_string(location.file_path)

	if location.line > 0 {
		when ODIN_ERROR_POS_STYLE == .Default {
			runtime.print_string("(")
			runtime.print_i64(i64(location.line))
			if location.column > 0 {
				runtime.print_string(":")
				runtime.print_i64(i64(location.column))
			}
			runtime.print_string(")")
		} else when ODIN_ERROR_POS_STYLE == .Unix {
			runtime.print_string(":")
			runtime.print_i64(i64(location.line))
			if location.column > 0 {
				runtime.print_string(":")
				runtime.print_i64(i64(location.column))
			}
		} else {
			#panic("unhandled ODIN_ERROR_POS_STYLE")
		}
	}
	runtime.print_string(": ")
	fmt.eprintfln("caught signal %q", cast(_Signals)signal)

	if len(locations) == trace.BACKTRACE_SIZE - SKIP {
		runtime.print_string("For a larger backtrace, please set '-define:ODIN_TRACE_SIZE'")
	}

	trace.print(locations)
	trace.locations_destroy(locations)
}
