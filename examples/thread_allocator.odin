package oc

import "core:fmt"
import "core:mem"
import "core:log"
import "core:os"
import "core:sync"
import "core:thread"
import odd "../src/"

foo :: proc(ctx: ^thread.Thread) {
	count := 20
	odd.ID = ctx.user_index
	rng := odd.range(count)
	fmt.printfln("[%d]: begin: %d, end: %d", odd.get_id(), rng.begin, rng.end)
	{
		ptr: ^int
		err: mem.Allocator_Error

		{
			ptr, err := make([]int, 6, ctx.creation_allocator)
			assert(err == nil)

			{
				m := (^odd.Thread_Allocator)(ctx.creation_allocator.data)
				barrier := &m.barrier

				assert(len(ptr) == 6)
				ptr[0] = 69
				sync.barrier_wait(barrier)
				assert(ptr[0] == 69)
				sync.barrier_wait(barrier)
			}

			delete(ptr, ctx.creation_allocator)
		}

		ptr1, err1 := new(int, ctx.creation_allocator)
		assert(err1 == nil)

		ptr1^ = 69

		ptr2, err2 := new(int, ctx.creation_allocator)
		assert(err2 == nil)

		ptr2^ = 96

		// These assertions are here, because we share the same memory over static variables, which
		// means that theoretically allocating the second time, could overwrite the first allocation
		assert(ptr1^ == 69)
		assert(ptr2^ == 96)

		free(ptr1, ctx.creation_allocator)
		free(ptr2, ctx.creation_allocator)
	}
}

main :: proc() {
	odd.set_count(os.get_processor_core_count())

	opt := log.Options{.Level, .Terminal_Color}
	context.logger = log.create_console_logger(log.Level.Debug, opt)

	fb: odd.Thread_Allocator
	fb.leader_id = 0

	count := odd.get_count()

	odd.thread_init(&fb, count, 0, context.allocator)
	allocator := odd.multi_buffer_thread_allocator(&fb)

	threads := make([dynamic]^thread.Thread, 0, count)
	defer delete(threads)

	for i in 0 ..< count {
		if t := thread.create(foo); t != nil {
			t.init_context = context
			t.user_index = i
			t.creation_allocator = allocator
			append(&threads, t)
			thread.start(threads[i])
		}
	}

	thread.join_multiple(..threads[:])

	fmt.println("End program")
}
