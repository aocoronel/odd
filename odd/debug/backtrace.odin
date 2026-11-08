package odd_debug

import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:debug/trace"
import "core:fmt"
import "core:os"
import "core:sync"
import "shared:odd/thread"

/*
Register a signal handler to capture the backtrace of the program.

The backtrace size can be customized with -define:ODIN_TRACE_SIZE.

The backtrace supports both .Odin and .Unix styles.
*/
register_backtrace :: proc() {
	Signals :: enum {
		SIGABRT = libc.SIGABRT,
		SIGFPE  = libc.SIGFPE,
		SIGILL  = libc.SIGILL,
		SIGINT  = libc.SIGINT,
		SIGSEGV = libc.SIGSEGV,
		SIGTERM = libc.SIGTERM,
	}

	handler :: proc "cdecl" (signal: c.int) {
		if thread.context_pool != nil {
			sync.mutex_lock(&thread.context_pool.err)
		}

		SKIP :: 2
		context = runtime.default_context()
		capture := trace.capture(SKIP) // 2 skip the signal handler stack trace
		locations, err := trace.resolve(capture)
		if err != nil {
			fmt.eprintfln("trace error: %v", err)
			os.exit(1)
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
		fmt.eprintfln("caught signal %q", cast(Signals)signal)

		if len(locations) == trace.BACKTRACE_SIZE - SKIP {
			fmt.eprintln("For a larger backtrace, please set '-define:ODIN_TRACE_SIZE'")
		}

		trace.print(locations)
		trace.locations_destroy(locations)

		if thread.context_pool != nil {
			thread.context_pool.should_die = true
		}
		runtime.trap()
	}

	for signal in Signals {
		libc.signal(cast(i32)signal, handler)
	}
}
