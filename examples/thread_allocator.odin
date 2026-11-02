package example

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:thread"
import "shared:odd/debug"
import odd "shared:odd/thread"

foo :: proc(args: []any) {
	debug.register_backtrace()

	fmt.println(args) // ["foo", 1, 2, 3]

	rng := odd.range(20)
	log.infof("[%d]: begin: %d, end: %d", odd.thread_id(), rng[0], rng[1])

	mrt_alloc := odd.thread_allocator_init(context.allocator)
	mrt := odd.multi_region_thread_allocator(&mrt_alloc)

	context.allocator = mrt

	// Not recommended to put this on context.allocator
	// It's fine to use the mrt allocator to initialize the srt allocator
	// But we could just have used the mrt_alloc, instead
	srt_alloc := odd.thread_allocator_init(context.allocator)
	srt := odd.single_region_thread_allocator(&srt_alloc)

	{
		{
			ptr, err := make([]int, 6)
			assert(err == nil)
			defer delete(ptr)

			{
				assert(len(ptr) == 6)
				ptr[0] = 69
				assert(ptr[0] == 69)
			}
		}

		ptr1, err1 := new(int)
		defer free(ptr1)
		assert(err1 == nil)

		ptr1^ = 69

		ptr2, err2 := new(int)
		defer free(ptr2)
		assert(err2 == nil)

		ptr2^ = 96

		// Threads are synchronized between allocations
		assert(ptr1^ == 69)
		assert(ptr2^ == 96)
	}


	{
		rng_sum := new(int)
		defer free(rng_sum)
		dyn_sum := new(int)
		defer free(dyn_sum)

		rng := odd.range(101)
		for i in rng[0] ..< rng[1] {
			rng_sum^ += i
		}

		@(static) tasks: int
		for i in odd.next(&tasks, 101) {
			dyn_sum^ += i
		}

		odd.wait()
		if odd.is_leader() {
			_buf := (cast([^]int)rng_sum)[:odd.thread_count()]
			rng_reduce: int
			for i in _buf {
				rng_reduce += i
			}
			_buf = (cast([^]int)dyn_sum)[:odd.thread_count()]
			dyn_reduce: int
			for i in _buf {
				dyn_reduce += i
			}
			fmt.println("Range sum:", rng_reduce)
			fmt.println("Dynamic sum:", dyn_reduce)
			assert(dyn_reduce == rng_reduce && dyn_reduce == 5050)
		}
	}

	// Set to true, to check backtrace
	when false {
		#no_bounds_check {
			str := "hello!"
			unsafe_arr := transmute([]u8)str
			unsafe_arr[0] = 'b'
		}
	}

	return
}

thread :: proc() {
	opt := log.Options{.Level, .Terminal_Color, .Thread_Id}
	logger := log.create_console_logger(log.Level.Debug, opt)
	context.logger = logger
	defer log.destroy_console_logger(logger)

	state, err := odd.start(foo, "foo", 1, 2, 3)
	if err != nil {
		fmt.println(err)
		return
	}
	odd.join(state)

	fmt.println("End program")
}
