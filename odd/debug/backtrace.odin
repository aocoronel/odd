package odd_debug

import rt "base:runtime"
import "core:c"
import "core:c/libc"
import "core:debug/trace"
import "core:os"

// Hand picked signals that matters most
Signals :: enum {
	SIGABRT = libc.SIGABRT,
	SIGFPE  = libc.SIGFPE,
	SIGILL  = libc.SIGILL,
	SIGINT  = libc.SIGINT,
	SIGSEGV = libc.SIGSEGV,
	SIGTERM = libc.SIGTERM,
}

@(rodata)
signals_name := #sparse[Signals]string {
	.SIGABRT = "abort signal",
	.SIGFPE  = "erroneous arithmetic operation",
	.SIGILL  = "illegal instruction",
	.SIGINT  = "interruption signal",
	.SIGSEGV = "segmentation fault",
	.SIGTERM = "termination signal",
}

/*
Register a signal handler to capture the backtrace of the program.

The backtrace size can be customized with -define:ODIN_TRACE_SIZE.

The backtrace supports both .Odin and .Unix styles.
*/
register_backtrace :: proc() {
	when ODIN_DEBUG {
		for signal in Signals {
			libc.signal(cast(i32)signal, _handler)
		}
	}
}

_handler :: proc "cdecl" (signal: c.int) {
	print_backtrace(signal)
	os.exit(int(signal))
}

print_backtrace :: proc "cdecl" (signal: c.int) {
	SKIP :: 3
	context = rt.default_context()
	capture := trace.capture(SKIP) // 3 skip the signal handler stack trace
	locations, err := trace.resolve(capture)
	if err != nil {
		rt.print_string("trace error: ")
		rt.print_string(trace.resolve_err_string(err))
		rt.print_byte('\n')
		return
	}
	location := locations[0]
	rt.print_string(location.file_path)

	if location.line > 0 {
		when ODIN_ERROR_POS_STYLE == .Default {
			rt.print_string("(")
			rt.print_i64(i64(location.line))
			if location.column > 0 {
				rt.print_string(":")
				rt.print_i64(i64(location.column))
			}
			rt.print_string(")")
		} else when ODIN_ERROR_POS_STYLE == .Unix {
			rt.print_string(":")
			rt.print_i64(i64(location.line))
			if location.column > 0 {
				rt.print_string(":")
				rt.print_i64(i64(location.column))
			}
		} else {
			#panic("unhandled ODIN_ERROR_POS_STYLE")
		}
	}
	rt.print_string(": ")
	rt.print_string("caught signal: ")
	rt.print_string(signals_name[cast(Signals)signal])
	rt.print_byte('\n')

	if len(locations) == trace.BACKTRACE_SIZE - SKIP {
		rt.print_string("For a larger backtrace, please set '-define:ODIN_TRACE_SIZE'")
	}

	trace.print(locations)
	trace.locations_destroy(locations)
}
