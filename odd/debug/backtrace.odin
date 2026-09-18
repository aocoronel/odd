package debug

import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:debug/trace"
import "core:fmt"
import "core:os"

register_back_trace :: proc() {
	Signals :: enum {
		SIGABRT = 6,
		SIGFPE  = 8,
		SIGILL  = 4,
		SIGINT  = 2,
		SIGSEGV = 11,
		SIGTERM = 15,
	}

	SKIP :: 2

	libc.signal(
		libc.SIGSEGV,
		proc "cdecl" (signal: c.int) {
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
			os.exit(1)
		},
	)
}
