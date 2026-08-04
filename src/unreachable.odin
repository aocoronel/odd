package odd

import "base:runtime"
import "core:fmt"

tprintf :: fmt.tprintf

unreachable :: proc(fmt: string, args: ..any, loc := #caller_location) -> ! {
	p := context.assertion_failure_proc
	if p == nil {
		p = runtime.default_assertion_failure_proc
	}
	message := tprintf(fmt, ..args)
	p("unreachable", message, loc)
}
