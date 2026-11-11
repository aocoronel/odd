package odd_thread

import "base:intrinsics"
import rt "base:runtime"
import "core:c"
import "core:c/libc"
import "core:sync"
import "core:thread"
import "shared:odd/debug"
import "shared:odd/mem"

/*
Notes:

The Odin documentation doesn't tell the default ordering for atomic_*.
In the source code, it defaults to LLVMAtomicOrderingSequentiallyConsistent -> Seq_Cst
this is true for all atomic_*

All procedures in this file uses the Pool. If you don't want to use this Pool,
you will still find useful procedures at ./helpers.odin
*/

Pool :: struct {
	// Won't shrink, but memory is reused
	queue:                         [dynamic]rawptr,
	threads:                       []^thread.Thread,
	// Lock queue interaction
	queue_mutex:                   sync.Mutex,
	// Tasks to be done. It's atomic
	tasks_assigned, tasks_pending: int,
	// Broadcasts to all threads. It's atomic
	sema:                          sync.Futex,
	// Signals threads to clear their memory
	should_reset:                  bool,
	// A thread has an error
	should_die:                    bool,
	// Signal threads to gracefully stop after
	// completing all remaining tasks
	should_end:                    bool,
}

wait :: proc {
	wait_single,
	wait_multiple,
}

reset :: proc {
	reset_single,
	reset_multiple,
}

join :: proc {
	join_single,
	join_multiple,
}

terminate :: proc {
	terminate_single,
	terminate_multiple,
}

destroy :: proc {
	destroy_single,
	destroy_multiple,
}

/*
Assume context_pool is a ^Pool

Only use inside a thread.
*/
get_context_pool :: #force_inline proc "contextless" () -> ^Pool {
	return (^Pool)(context_pool)
}

/*
Broadcast that a thread has an error. This should only be called in
an irrecoverable error.

Only use inside a thread.

Example:

  file, err := open("file.txt")
  if err != nil {
    log.error(err)
    broadcast_error()
    return
  }
*/
broadcast_error :: #force_inline proc "contextless" () -> bool {
	return !intrinsics.atomic_exchange_explicit(&get_context_pool().should_die, true, .Relaxed)
}

/*
Register a signal handler to capture the backtrace of the program,
only inside of a thread.

The backtrace size can be customized with -define:ODIN_TRACE_SIZE.

The backtrace supports both .Odin and .Unix styles.
*/
register_thread_backtrace :: proc() {
	when ODIN_DEBUG {
		for signal in debug.Signals {
			libc.signal(cast(i32)signal, _thread_handler)
		}
	}
}

_thread_handler :: proc "cdecl" (signal: c.int) {
	if broadcast_error() {
		debug.print_backtrace(signal)
	}

	parker: sync.Parker
	sync.park(&parker) // park forever
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
	if !broadcast_error() {
		parker: sync.Parker
		sync.park(&parker)
	}
	default_assertion_failure_contextless_proc(prefix, message, loc)
	parker: sync.Parker
	sync.park(&parker)
	rt.trap()
}

/*
Creates a pool that can have up to "thread_count" threads

To free the pool, free() is enough
*/
create_pool :: proc(
	thread_count: int,
	allocator := context.allocator,
) -> (
	pool: ^Pool,
	err: rt.Allocator_Error,
) {
	pool = auto_cast mem.malloc(
		size_of(Pool) + (size_of(^thread.Thread) * thread_count),
		allocator,
	) or_return
	pool.threads = mem.shift(pool, ^thread.Thread, thread_count)
	return
}

/*
Waits until all threads finished all tasks.

Can be used from any thread.

When return "false", a thread failed. You may call terminate(), then destroy()
*/
wait_single :: proc(pool: ^Pool) -> bool {
	for {
		if intrinsics.atomic_load_explicit(&pool.tasks_pending, .Relaxed) == 0 do break
		if pool.should_die do return false
		intrinsics.cpu_relax()
		thread.yield()
	}

	return true
}

/*
Waits until all threads finished all tasks.

Can be used from any thread.

Respects pool order.

When return "false", a thread failed. You may call terminate(), then destroy()
*/
wait_multiple :: proc(pools: ..^Pool) -> bool {
	for pool in pools do wait(pool) or_return
	return true
}

/*
Clears the queue and temp_allocator from all threads.
*/
reset_single :: proc(pool: ^Pool) {
	pool.should_reset = !pool.should_reset
	pool.tasks_assigned = 0
	clear(&pool.queue)
}

/*
Clears the queue and temp_allocator from all threads in all pools from all pools.

Respects pool order.
*/
reset_multiple :: proc(pools: ..^Pool) {
	for pool in pools do reset_single(pool)
}

/*
Waits until all threads finished all tasks.

This will also clear the queue and temp_allocator from all threads.

When return "false", a thread failed. You may call terminate(), then destroy()
*/
wait_and_reset :: proc(pool: ^Pool) -> bool {
	wait(pool) or_return
	reset(pool)
	return true
}

/*
Waits until all threads finished all tasks from all pools.

This will also clear the queue and temp_allocator from all threads.

Respects pool order.

When return "false", a thread failed. You may call terminate(), then destroy()
*/
wait_and_reset_multiple :: proc(pools: ..^Pool) -> bool {
	wait(..pools) or_return
	reset(..pools)
	return true
}

/*
Joins all threads created by init, and frees their memory.

When return "false", a thread failed. You may call terminate(), then destroy()
*/
join_single :: proc(pool: ^Pool) -> bool {
	pool.should_end = true

	wait(pool) or_return

	sema_post(&pool.sema)

	thread.join_multiple(..pool.threads[:])
	destroy(pool)

	return true
}

/*
Joins all threads created by init, and frees their memory.

Respects pool order.

When return "false", a thread failed. You may call terminate(), then destroy()
*/
join_multiple :: proc(pools: ..^Pool) -> bool {
	for pool in pools do join_single(pool)
	return true
}

/*
Forcibly terminates all threads.

May be called from the main thread, when pool.should_die is true.
*/
terminate_single :: proc(pool: ^Pool, exit_code := 1) {
	for t, i in pool.threads {
		thread.terminate(t, exit_code)
	}
}

/*
Forcibly terminates all threads from all pools.

Respects pool order.

May be called from the main thread, when pool.should_die is true.
*/
terminate_multiple :: proc(pools: ..^Pool, exit_code := 1) {
	for pool in pools {
		terminate_single(pool, exit_code)
	}
}

/*
Frees pool and thread memory.
*/
destroy_single :: proc(pool: ^Pool) {
	context.allocator = pool.threads[0].creation_allocator
	for t in pool.threads do free(t)
	free(pool)
}

/*
Frees pool and thread memory from all pools.

Respects pool order.
*/
destroy_multiple :: proc(pools: ..^Pool) {
	for pool in pools {
		destroy_single(pool)
	}
}
