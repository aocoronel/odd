package odd_thread

import "base:intrinsics"
import rt "base:runtime"
import "core:math"
import "core:mem"
import "core:mem/virtual"
import "core:sync"
import "core:thread"

/*
Notes:

The Odin documentation doesn't tell the default ordering for atomic_*.
In the source code, it defaults to LLVMAtomicOrderingSequentiallyConsistent -> Seq_Cst
this is true for all atomic_*

All procedures in this file uses the Pool. If you don't want to use this Pool,
you will still find useful procedures at ./helpers.odin

TBD:

- Pool has 8 bytes missing, that could have something useful
*/

Pool :: struct {
	// Virtual memory. See create_pool()
	queue:            []rawptr,
	threads:          []^thread.Thread,
	// Commands in the queue. It's atomic
	len:              int,
	// Commands to be done. It's atomic
	commands_pending: int,
	// Lock queue append in submit()
	queue_mutex:      sync.Mutex,
	// Broadcasts to all threads. It's atomic
	sema:             sync.Futex,
	// 8 bytes missing for a 64 byte struct
}

Config :: struct {
	args:         [thread.MAX_USER_ARGUMENTS]rawptr,
	context_name: string,
	priority:     thread.Thread_Priority,
	pass_context: bool,
}

DEFAULT_CONFIG :: Config {
	args         = nil,
	priority     = .Normal,
	context_name = "thread",
	pass_context = true,
}

/*
Waits until all threads finished all commands.
*/
wait :: proc {
	wait_single,
	wait_multiple,
}

/*
Joins all threads created by init.
*/
join :: proc {
	join_single,
	join_multiple,
}

/*
Forcibly terminates all threads.
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
Appends a command to the queue, also broadcasts it.

Worst case scenario (OOM): The default pool size is 1GB which can
store a very large amount of rawptrs, making it unlikely to happen.
Just for the sake of that edge case, when OOM it becomes a ring.

Purposefully, we don't check if writing to the queue is allowed,
since we assume there consumers >= producers, plus resetting
This may be changed.
*/
submit :: proc "contextless" (pool: ^Pool, elem: rawptr) {
	{
		sync.guard(&pool.queue_mutex)
		idx := get_queue(pool, pool.len)
		pool.queue[idx] = elem
		intrinsics.atomic_add_explicit(&pool.len, 1, .Release)
	}
	intrinsics.atomic_add_explicit(&pool.commands_pending, 1, .Relaxed)
	sema_post(&pool.sema)
}

/*
Gets a valid queue index, that matches queue wrapping
*/
get_queue :: #force_inline proc "contextless" (pool: ^Pool, i: int) -> int {
	return i & (len(pool.queue) - 1)
}

/*
Sends a stop sentinel, gracefully quitting the threads.
*/
stop :: #force_inline proc "contextless" (pool: ^Pool) {
	submit(pool, nil)
}

/*
Assume context_pool is a ^Pool

Only use inside a thread.
*/
get_context_pool :: #force_inline proc "contextless" () -> ^Pool {
	return (^Pool)(context_pool)
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
	assert(math.is_power_of_two(int(reserve)))
	context.allocator = allocator
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
		if intrinsics.atomic_load_explicit(&pool.commands_pending, .Acquire) == 0 do break
		intrinsics.cpu_relax()
	}
}

wait_multiple :: proc(pools: ..^Pool) {
	for pool in pools do wait(pool)
}

join_single :: proc(pool: ^Pool) {
	wait(pool)
	stop(pool)
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
