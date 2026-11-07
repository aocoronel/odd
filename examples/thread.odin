package example

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:thread"
import odd "shared:odd/thread"

thread :: proc() {
	context.logger = log.create_console_logger(
		log.Level.Debug,
		opt = {.Level, .Terminal_Color, .Thread_Id},
	)
	defer log.destroy_console_logger(context.logger)

	state, err := odd.start()
	if err != nil {
		log.error(err)
		return
	}

	sum: int
	// &sum is shared data, that all threads can read and write
	// Tasks will use the context.temp_allocator by default, otherwise
	// use destroy_task() to cleanup
	_ = odd.add_task(state, bar, &sum)

	arr := []string{"foo", "bar", "baz"}
	odd.add_task(state, baz, &arr)

	// Wait all tasks to finish, and clear queue
	odd.wait_task(state)

	// Add more tasks
	odd.add_task(state, baz, &arr)

	// Wait all tasks to finish, and join threads
	odd.join(state)

	fmt.println("SUM:", sum) // if 8 threads -> 28
}

bar :: proc(t: ^odd.Task) {
	out := (cast(^int)t.data[0])
	intrinsics.atomic_add_explicit(out, odd.thread_id(), .Seq_Cst)
}

baz :: proc(t: ^odd.Task) {
	arr := (cast(^[]string)t.data[0])^
	rng := odd.range(len(arr))
	// All threads will get hear, but if there is more threads than
	// len(arr), only a few threads will actually run this
	for i in rng[0] ..< rng[1] {
		fmt.println(odd.thread_id(), arr[i])
	}
}
