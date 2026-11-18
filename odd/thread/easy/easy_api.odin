package odd_thread_easy

// import "core:fmt"
// import "core:time"

import "base:intrinsics"
import rt "base:runtime"
import "core:mem"
import "core:sync"
import "core:thread"
import "shared:odd/debug"
import othread "shared:odd/thread"

/*
This implements mostly of what the user would have to implement, both
as convenience, and as an example.
*/

Command_Proc :: proc(args: []rawptr)

Command :: struct {
	data:      []rawptr,     // 16
	procedure: Command_Proc, // 8
	done:      i32,          // 4
	counter:   i32,          // 4
}

@(private)
Pool :: othread.Pool

@(thread_local)
cursor: int

init :: proc(
	thread_count := -1,
	priority: thread.Thread_Priority = .Normal,
	context_name := "thread",
	pass_context := true,
	reserve: uint = mem.Gigabyte when size_of(uintptr) == 8 else 128 * mem.Megabyte,
	allocator := context.allocator,
) -> (
	pool: ^Pool,
	err: rt.Allocator_Error,
) {
	context.allocator = allocator

	b := new(sync.Barrier) or_return
	defer if err != nil do free(b)

	count := othread.select_thread_count(thread_count)

	sync.barrier_init(b, count)

	pool = othread.create_pool(count, reserve) or_return

	if !othread.init(
		&pool.threads,
		pool,
		runner,
		config = {{b, nil, nil, nil, nil, nil, nil, nil}, context_name, priority, pass_context},
	) { return }
	return
}

/*
Thread runner.
*/
runner :: proc(t: ^thread.Thread) {
	// start, end: time.Time
	// start = time.now()
	when ODIN_DEBUG {
		debug.register_backtrace()
	}

	pool := cast(^Pool)t.data
	barrier := cast(^sync.Barrier)t.user_args[0]

	othread.context_thread_id = t.user_index
	othread.context_pool = pool
	othread.context_thread_count = len(pool.threads)

	last_gen: sync.Futex

	die: for {
		last_gen = othread.sema_wait(&pool.sema, last_gen)

		pool_len := intrinsics.atomic_load_explicit(&pool.len, .Acquire)

		commands_left := pool_len - cursor

		for _ in 0 ..< commands_left {
			idx := othread.get_queue(pool, cursor)
			command := cast(^Command)pool.queue[idx]

			cursor += 1

			if command == nil do break die

			context.user_ptr = command

			for i in othread.next(&command.counter, cast(i32)len(pool.threads)) {
				context.user_index = int(i)
				command.procedure(command.data)
			}

			last_out := intrinsics.atomic_sub_explicit(&command.done, 1, .Acq_Rel) - 1 == 0
			if last_out {
				intrinsics.atomic_sub_explicit(&pool.commands_pending, 1, .Release)
			}
		}
	}
	sync.barrier_wait(barrier)
	// end = time.now()
	// fmt.println("Thread", t.user_index, "took:", time.diff(start, end))
}

/*
Adds a new command to the queue.

Only at the main thread. You may free the Command using destroy_command, if
you prefer to don't use the temp_allocator.

Can be called from any thread.
*/
add_command :: proc(
	pool: ^Pool,
	procedure: Command_Proc,
	data: ..rawptr,
	allocator := context.temp_allocator,
) -> (
	command: ^Command,
	err: rt.Allocator_Error,
) #optional_allocator_error {
	context.allocator = allocator

	command = new(Command) or_return
	defer if err != nil do free(command)
	args := make([]rawptr, len(data)) or_return
	defer if err != nil do delete(args)

	copy_slice(args[:], data[:])

	command.procedure = procedure
	command.data = args
	intrinsics.atomic_store_explicit(&command.done, i32(len(pool.threads)), .Relaxed) // to surpress warning

	othread.submit(pool, command)

	return
}

/*
Clears the queue and temp_allocator from all threads.

Only call in main, or a thread from a diferent pool
*/
reset :: proc(pool: ^Pool) {
	barrier: sync.Barrier
	sync.barrier_init(&barrier, len(pool.threads) + 1)
	command := add_command(pool, _reset, &barrier)
	sync.barrier_wait(&barrier)
	intrinsics.atomic_store_explicit(&pool.len, 0, .Relaxed)
	sync.barrier_wait(&barrier)
	wait_command(command)
}

_reset :: proc(args: []rawptr) {
	barrier := cast(^sync.Barrier)args[0]
	sync.barrier_wait(barrier)
	free_all(context.temp_allocator)
	cursor = 0
	sync.barrier_wait(barrier)
}

/*
Destroys the command created by add_command.

If commands are created in threads in recursion, use a temp_allocator, instead.
Threads that create a command also should run that command, which makes
"defer destroy_command" not an option.
*/
destroy_command :: proc(command: ^Command, allocator := context.temp_allocator) {
	if command == nil do return
	free(command, allocator)
}

/*
Waits until a command is completed
*/
wait_command :: proc {
	wait_command_single,
	wait_command_multiple,
}

wait_command_single :: proc "contextless" (command: ^Command) {
	for {
		if intrinsics.atomic_load_explicit(&command.done, .Acquire) == 0 do break
		intrinsics.cpu_relax()
	}
}

wait_command_multiple :: proc "contextless" (commands: ..^Command) {
	for command in commands {
		#force_inline wait_command_single(command)
	}
}
