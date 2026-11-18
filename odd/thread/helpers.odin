package odd_thread

import "base:intrinsics"
import "core:fmt"
import "core:os"
import "core:sync"
import vg "core:sys/valgrind"
import "core:thread"

Range :: #type [2]int

@(thread_local)
context_thread_id: int
@(thread_local)
context_thread_count: int
@(thread_local)
context_pool: rawptr

next :: proc {
	next_static,
	next_dynamic,
}

/*
Selects at least one thread. Defaults to CPU count.
*/
@(require_results)
select_thread_count :: proc(thread_count: int = -1) -> int {
	return os.get_processor_core_count() if thread_count < 1 else thread_count
}

/*
Dispatch almost equivalent work.

If the task at hand have variadic completion times, prefer next()

Likely, if a thread fails, the work will be partial, unless there is
more threads than work to do.

Only use inside a thread.

Example: assuming 1 thread

  rng := range(101)
  sum: int
  for i in rng[0] ..< rng[1] {
    sum += i
  }
  assert(sum == 5050)
*/
@(require_results)
range :: proc "contextless" (thread_idx: int, count: int) -> Range {
	id, thread_count := thread_idx, context_thread_count
	per_thread, leftover := count / thread_count, count % thread_count
	extra := int(id < leftover)
	begin := per_thread * id + min(id, leftover)
	return {begin, begin + per_thread + extra}
}

/*
Perform work stealing.

"tasks" must be shared between threads.

If a thread fails, other threads can still finish the work.

Only use inside a thread.

Example: assuming 1 thread

  @(static) tasks: int
  sum: int
  for i in next(&tasks, 101) {
    sum += i
  }
  assert(sum == 5050)
*/
@(require_results)
next_static :: #force_inline proc "contextless" (tasks: ^$T, count: T) -> (T, bool) {
	idx := intrinsics.atomic_add_explicit(tasks, 1, .Relaxed)
	return idx, idx < count
}

/*
Perform work stealing.

"tasks" and "count" must be shared between threads.

If a thread fails, other threads can still finish the work.

Only use inside a thread.

Example: assuming 1 thread

  @(static) tasks: int
  work := 100
  sum: int
  for i in next(&tasks, &work) {
    sum += i
    if i == 99 do intrinsics.atomic_add_explicit(&work, 1, .Release)
  }
  assert(sum == 5050)
*/
@(require_results)
@(synchronizes = .Acquire)
next_dynamic :: #force_inline proc "contextless" (tasks: ^$T, count: ^T) -> (T, bool) {
	idx := intrinsics.atomic_add(tasks, 1)
	return idx, idx < intrinsics.atomic_load_explicit(count, .Acquire)
}

/*
Wakes all threads up
*/
@(futex = .Wake)
sema_post :: proc "contextless" (sema: ^sync.Futex) {
	when ODIN_VALGRIND_SUPPORT {
		vg.helgrind_sem_post_pre(sema)
	}
	intrinsics.atomic_add_explicit(sema, 1, .Release)
	sync.futex_broadcast(sema)
}

/*
Waits until new post, where sema != last_gen

Returns a new value for last_gen
*/
@(futex = .Wait)
sema_wait :: proc "contextless" (sema: ^sync.Futex, last_gen: sync.Futex) -> sync.Futex {
	sync.futex_wait(sema, u32(last_gen))
	when ODIN_VALGRIND_SUPPORT {
		vg.helgrind_sem_wait_post(sema)
	}
	return last_gen + 1
}

/*
Initializes the thread pool, with at least one thread

"threads" length is used to create the threads.

"data" is forwarded to thread.Thread.

"config.context_name" will set the thread name. Useful in debuggers.

"config.priority" will set the thread priority.

"config.pass_context" will use the main thread context and pass it to all created
threads. Useful when you want to initialize things like a logger once. Otherwise,
you can pass custom "runner", or use the default context thread.create gives you.

Uses "context.allocator" as the thread creation allocator.

Important:

The usage of "config.args" will fall on how you want to use it. For the sake of
an idea, I like to think of it as implementation dependent on the "runner" you choose.
Useful, to pass shared data like a mutex, barriers... that will be used during the lifetime
of all threads.

This procedure doesn't assume you are using the Pool.
The only goal here is to create the threads and start them.
*/
@(require_results)
init :: proc(
	threads: ^[]^thread.Thread,
	data: rawptr,
	runner: thread.Thread_Proc,
	config := DEFAULT_CONFIG,
) -> (
	ok: bool,
) {
	// Create all threads first, because if any fails, no thread has
	// yet started executing, avoid having to terminate them.
	for i in 0 ..< len(threads) {
		// create() forcefully uses context.allocator
		t := thread.create(runner, config.priority, fmt.tprintf("%s-%d", config.context_name, i))
		// EINVAL, EPERM, EAGAIN
		// Mostly likely to fail, due to OS restrictions into the program
		if t == nil {
			for j in 0 ..< i {
				thread.destroy(threads[j])
			}
			return
		}
		threads[i] = t
	}

	for i in 0 ..< len(threads) {
		t := threads[i]
		t.data = data
		t.user_index = i
		t.user_args = config.args
		t.init_context = context if config.pass_context else nil
		thread.start(t)
	}

	return true
}
