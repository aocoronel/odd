package oc

import odd "../src/"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:sync"
import "core:thread"

GLOBAL_BARRIER: ^sync.Barrier

barrier_sync_all :: proc() {
	odd.barrier_wait(GLOBAL_BARRIER)
}

foo :: proc(ctx: ^thread.Thread) {
	count := 20
	odd.set_id(ctx.user_index)
	rng := odd.range(count)
	fmt.printfln("[%d]: begin: %d, end: %d", odd.get_id(), rng.begin, rng.end)
	context.allocator = ctx.creation_allocator
	{
		ptr: ^int
		err: mem.Allocator_Error

		{
			ptr, err := make([]int, 6)
			assert(err == nil)

			{
				assert(len(ptr) == 6)
				ptr[0] = 69
				barrier_sync_all()
				assert(ptr[0] == 69)
				barrier_sync_all()
			}

			delete(ptr)
		}

		ptr1, err1 := new(int)
		assert(err1 == nil)

		ptr1^ = 69

		ptr2, err2 := new(int)
		assert(err2 == nil)

		ptr2^ = 96

		// These assertions are here, because we share the same memory over static variables, which
		// means that theoretically allocating the second time, could overwrite the first allocation
		assert(ptr1^ == 69)
		assert(ptr2^ == 96)

		free(ptr1)
		free(ptr2)
	}
}

main :: proc() {
	odd.set_count(os.get_processor_core_count())

	opt := log.Options{.Level, .Terminal_Color, .Thread_Id}
	context.logger = log.create_console_logger(log.Level.Debug, opt)

	fb: odd.Thread_Allocator
	fb.leader_id = 0

	count := odd.get_count()

	odd.thread_allocator_init(&fb, count, 0, context.allocator)
	allocator := odd.multi_buffer_thread_allocator(&fb)
	GLOBAL_BARRIER = &fb.barrier

	threads: [odd.MAX_THREAD_COUNT]^thread.Thread

	for i in 0 ..< count {
		t := thread.create(foo)
		if t == nil {
			log.panicf("Failed to create threads")
		}
		t.init_context = context
		t.user_index = i
		t.creation_allocator = allocator
		threads[i] = t
		thread.start(threads[i])
	}

	thread.join_multiple(..threads[:count])

	for i in 0 ..< count {
		free(threads[i])
	}

	fmt.println("End program")
}
