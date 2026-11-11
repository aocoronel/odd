package odd_thread

import "base:intrinsics"
import rt "base:runtime"
import "core:mem"
import "core:mem/virtual"
import "core:os"
import "core:sync"
import "core:thread"

/*
Notes:

The Odin documentation doesn't tell the default ordering for atomic_*.
In the source code, it defaults to LLVMAtomicOrderingSequentiallyConsistent -> Seq_Cst
this is true for all atomic_*

All procedures in this file uses the Pool. If you don't want to use this Pool,
you will still find useful procedures at ./helpers.odin
*/

Pool :: struct {
	// Virtual memory
	queue:            []rawptr,
	// Lock queue interaction
	threads:          []^thread.Thread,
	len:              int,
	// Commands to be done. It's atomic
	commands_pending: int,
	queue_mutex:      sync.Mutex,
	// Broadcasts to all threads. It's atomic
	sema:             sync.Futex,
	// Signals threads to clear their memory
	should_reset:     bool,
	// Signal threads to gracefully stop after
	// completing all remaining commands
	should_end:       bool,
}

Config :: struct {
	args:         [thread.MAX_USER_ARGUMENTS]rawptr,
	context_name: string,
	thread_count: int,
	priority:     thread.Thread_Priority,
	pass_context: bool,
}

DEFAULT_CONFIG :: Config {
	args         = nil,
	thread_count = -1,
	priority     = .Normal,
	context_name = "thread",
	pass_context = true,
}

/*
Waits until all threads finished all commands.

This will also clear the queue and temp_allocator from all threads.

When return "false", a thread failed. You may call terminate(), then destroy()
*/
wait :: proc {
	wait_single,
	wait_multiple,
}

/*
Joins all threads created by init.

When return "false", a thread failed. You may call terminate(), then destroy()
When return "true", you may call destroy()
*/
join :: proc {
	join_single,
	join_multiple,
}

/*
Forcibly terminates all threads.

May be called from the main thread, when pool.should_die is true.
*/
terminate :: proc {
	terminate_single,
	terminate_multiple,
}

/*
Frees pool and thread memory.
*/
destroy :: proc {
	destroy_single,
	destroy_multiple,
}

/*
Appends a command to the queue, also posts it to other threads.
*/
submit :: proc(pool: ^Pool, elem: rawptr) -> rt.Allocator_Error {
	context.allocator = pool.threads[0].creation_allocator
	{
		sync.guard(&pool.queue_mutex)
		if pool.len > len(pool.queue) do return .Out_Of_Memory
		pool.queue[pool.len] = elem
		pool.len += 1
	}
	intrinsics.atomic_add_explicit(&pool.commands_pending, 1, .Release)
	sema_post(&pool.sema)
	return nil
}

/*
Assume context_pool is a ^Pool

Only use inside a thread.
*/
get_context_pool :: #force_inline proc "contextless" () -> ^Pool {
	return (^Pool)(context_pool)
}

/*
Procedures like ensure, panic and unimplemented will use this,
but procedures like os.exit, won't. Call broadcast_error() before the the former

Do not set this in the main thread's context.
*/
default_assertion_failure_proc :: proc(
	prefix, message: string,
	loc: rt.Source_Code_Location,
) -> ! {
	default_assertion_failure_contextless_proc(prefix, message, loc)
	os.exit(1)
}

/*
Creates a pool that can have up to "thread_count" threads

To cleanup, use destroy()
*/
@(require_results)
create_pool :: proc(
	thread_count: int = -1,
	reserve: uint = mem.Gigabyte when size_of(uintptr) == 8 else 128 * mem.Megabyte,
	allocator := context.allocator,
) -> (
	pool: ^Pool,
	err: rt.Allocator_Error,
) {
	context.temp_allocator = allocator
	count := select_thread_count(thread_count)
	pool = new(Pool) or_return
	defer if err != nil do free(pool)
	pool.threads = make([]^thread.Thread, count) or_return
	defer if err != nil do delete(pool.threads)
	memory := virtual.reserve_and_commit(reserve) or_return
	pool.queue = transmute([]rawptr)memory[:reserve / size_of(rawptr)]
	return
}

wait_single :: proc(pool: ^Pool) {
	for {
		if intrinsics.atomic_load_explicit(&pool.commands_pending, .Relaxed) == 0 do break
		intrinsics.cpu_relax()
		thread.yield()
	}
}

wait_multiple :: proc(pools: ..^Pool) {
	for pool in pools do wait(pool)
}

/*
Clears the queue and temp_allocator from all threads.
*/
reset :: proc(pool: ^Pool) {
	pool.should_reset = !pool.should_reset
	pool.len = 0
}

join_single :: proc(pool: ^Pool) {
	pool.should_end = true

	wait(pool)

	sema_post(&pool.sema)

	thread.join_multiple(..pool.threads[:])
}

join_multiple :: proc(pools: ..^Pool) {
	for pool in pools do join_single(pool)
}

terminate_single :: proc(pool: ^Pool, exit_code := 1) {
	for t in pool.threads {
		thread.terminate(t, exit_code)
	}
}

terminate_multiple :: proc(pools: ..^Pool, exit_code := 1) {
	for pool in pools {
		terminate_single(pool, exit_code)
	}
}

destroy_single :: proc(pool: ^Pool) {
	if pool == nil do return
	context.allocator = pool.threads[0].creation_allocator
	for t in pool.threads do free(t)
	virtual.release(raw_data(pool.queue), len(pool.queue))
	delete(pool.threads)
	free(pool)
}

destroy_multiple :: proc(pools: ..^Pool) {
	for pool in pools {
		destroy_single(pool)
	}
}
