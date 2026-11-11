package odd_thread_easy

import "base:intrinsics"
import rt "base:runtime"
import "core:sync"
import "core:thread"
import "shared:odd/debug"
import othread "shared:odd/thread"

/*
This implements mostly of what the user would have to implement, both
as convenience, and as an example.
*/

Command_Proc :: proc(t: ^Command, i: int)

Command_Flag :: enum {
	Auto,
}

Command_Flags :: bit_set[Command_Flag;u8]

Command :: struct {
	data:      []rawptr,      // 16
	procedure: Command_Proc,  // 8
	done:      i32,           // 4
	counter:   i32,           // 4
	flags:     Command_Flags, // 1
}

@(private)
Pool :: othread.Pool

/*
Thread runner.

If the user has a custom assertion_failure_proc, don't forget to call broadcast_error(),
then park()
*/
runner :: proc(t: ^thread.Thread) {
	debug.register_backtrace()

	pool := cast(^Pool)t.data
	barrier := cast(^sync.Barrier)t.user_args[0]

	othread.context_pool = pool
	othread.context_thread_count = len(pool.threads)

	if context.assertion_failure_proc == rt.default_assertion_failure_proc {
		context.assertion_failure_proc = othread.default_assertion_failure_proc
	}

	buffer: [1 << 8]rawptr // 2048 bytes

	commands: []rawptr
	command_index: int

	last_gen: sync.Futex

	should_reset: bool

	run :: proc(pool: ^Pool, command: ^Command) {
		// procedure := cast(Command_Proc)command.data[0]
		// command.data = command.data[1:]
		for i in othread.next(&command.counter, cast(i32)len(pool.threads)) {
			command.procedure(command, cast(int)i)

			flags := intrinsics.atomic_load_explicit(&command.flags, .Relaxed)
			if .Auto in flags {
				if intrinsics.atomic_sub_explicit(&command.done, 1, .Relaxed) - 1 == 0 {
					intrinsics.atomic_sub_explicit(&pool.commands_pending, 1, .Acquire)
				}
			}
		}
	}

	for {
		// Only runs on reset(), ideally after all threads finished the work
		// This may break, depending on how the threads are used
		if should_reset != pool.should_reset {
			should_reset = !should_reset
			command_index = 0
			free_all(context.temp_allocator)
		}

		commands_left := pool.len - command_index

		if commands_left == 1 {
			command := pool.queue[command_index]
			command_index += 1
			run(pool, cast(^Command)command)
			continue
		} else if commands_left > 1 {
			count := min(len(buffer), commands_left)
			copy_slice(buffer[:count], pool.queue[command_index:command_index + count])
			commands = buffer[:count]
			command_index += count
			for i in 0 ..< len(commands) {
				run(pool, cast(^Command)commands[i])
			}
			continue
		}

		current := intrinsics.atomic_load_explicit(&pool.sema, .Acquire)

		if current > last_gen {
			last_gen += 1
			continue
		}

		// Wait until all threads are done
		if pool.should_end && commands_left == 0 {
			sync.barrier_wait(barrier)
			break
		}

		othread.sema_wait(&pool.sema, current)
	}
}

finish :: proc "contextless" (command: ^Command) -> bool {
	// Only last thread is allowed to decrease the counter
	if intrinsics.atomic_sub_explicit(&command.done, 1, .Relaxed) - 1 == 0 {
		intrinsics.atomic_sub_explicit(&othread.get_context_pool().commands_pending, 1, .Relaxed)
		return true
	}
	return false
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
	flags := Command_Flags{.Auto},
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
	intrinsics.atomic_store_explicit(&command.done, i32(len(pool.threads)), .Relaxed)
	intrinsics.atomic_store_explicit(&command.flags, flags, .Relaxed)

	othread.submit(pool, command) or_return

	return
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

wait_command :: proc(pool: ^othread.Pool, commands: ..^Command) {
	for command in commands {
		for {
			intrinsics.cpu_relax()
			thread.yield()
			if intrinsics.atomic_load_explicit(&command.done, .Relaxed) == 0 {
				break
			}
		}
	}
}
