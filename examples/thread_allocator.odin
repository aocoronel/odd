package example
import "core:sync"

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:thread"
import "shared:odd/debug"
import odd "shared:odd/thread"

bar :: proc(t: ^odd.Task) {
	debug.register_backtrace()

	fmt.println(t.data)
	if len(t.data) == 0 do return
	out := (cast(^int)t.data[0])
	fmt.println("out:", out^)
	intrinsics.atomic_add_explicit(out, odd.thread_id(), .Seq_Cst)
}

baz :: proc(t: ^odd.Task) {
	arr := (cast(^[]string)t.data[0])^
	rng := odd.range(len(arr))
	for i in rng[0] ..< rng[1] {
		fmt.println(odd.thread_id(), arr[i])
	}
}

any_to :: proc(arg: any, $T: typeid, loc := #caller_location) -> T {
	if arg.id != T {
		sync.mutex_lock(&odd.CONTEXT_POOL.err)
		fmt.eprintfln("expected type %q, got %q", typeid_of(T), arg.id)
		odd.CONTEXT_POOL.should_die = true
		sync.mutex_lock(&odd.CONTEXT_POOL.err)
	}
	return (cast(^T)arg.data)^
}

thread :: proc() {
	opt := log.Options{.Level, .Terminal_Color, .Thread_Id}
	logger := log.create_console_logger(log.Level.Debug, opt)
	context.logger = logger
	defer log.destroy_console_logger(logger)

	state, err := odd.start()
	if err != nil {
		fmt.println(err)
		return
	}

	odd.add_task(state, bar)

	sum: int
	odd.add_task(state, bar, &sum)

	arr := []string{"foo", "bar", "baz"}
	odd.add_task(state, baz, &arr)

	odd.wait_task(state)

	odd.add_task(state, baz, &arr)

	odd.join(state)

	fmt.println("SUM:", sum)

	fmt.println("End program")
}
