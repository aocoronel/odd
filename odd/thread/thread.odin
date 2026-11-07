package odd_thread

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:sync"
import vg "core:sys/valgrind"
import "core:thread"
import "shared:odd/mem"

Task_Proc :: proc(t: ^Task)

Task :: struct {
	fn:   Task_Proc,
	data: []rawptr,
	done: int,
}

Pool :: struct {
	// Won't shrink, but memory is reused
	queue:         [dynamic]^Task,
	threads:       []^thread.Thread,
	sema:          sync.Futex,
	// Lock queue interaction
	mutex:         sync.Mutex,
	// Locks on thread failure
	err:           sync.Mutex,
	tasks_pending: int,
	// Signals threads to clear their memory
	should_reset:  bool,
	// A thread has an error
	should_die:    bool,
	// Signal threads to gracefully stop after
	// completing all remaining tasks
	should_end:    bool,
}

Error :: union {
	runtime.Allocator_Error,
	Multicore_Error,
}

Multicore_Error :: enum {
	Ok = 0,
	Creation_Failed, // EINVAL, EPERM, EAGAIN
}

Range :: #type [2]int

/*
These could be all private, but I'm sure you won't write after
they are initialized, right? Great! Otherwise, that's a reason
why Rust always wrap globals around atomics.
Another thing, if you are looking for shorter ways to access these variables see:
  thread_id() and thread_count()

Jokes aside. I'll try very hard to make this API privateless,
so you can reuse parts of this with a custom one.
*/
@(thread_local)
CURRENT_THREAD_ID: int
@(thread_local)
CONTEXT_THREAD_COUNT: int
@(thread_local)
CONTEXT_POOL: ^Pool

/*
Returns the thread id from the current context.
Not to be confused with core:thread Thread.id.
Associate to the user_index Odin nomenclature
*/
thread_id :: #force_inline proc "contextless" () -> int {
	return CURRENT_THREAD_ID
}

/*
Returns how many threads make part of the current context.
*/
thread_count :: #force_inline proc "contextless" () -> int {
	return CONTEXT_THREAD_COUNT
}

/*
Dispatch almost equivalent work. If the task at hand have variadic
completion times, prefer next()

Example: assuming 1 thread

  rng := range(101)
  sum: int
  for i in rng[0] ..< rng[1] {
    sum += i
  }
  assert(sum == 5050)
*/
range :: proc "contextless" (count: int) -> Range {
	id, thread_count := thread_id(), thread_count()
	per_thread, leftover := count / thread_count, count % thread_count
	extra := int(id < leftover)
	begin := per_thread * id + min(id, leftover)
	return {begin, begin + per_thread + extra}
}

/*
Perform work stealing.

"tasks" must be shared between threads.

Example: assuming 1 thread

  @(static) tasks: int
  sum: int
  for i in next(&tasks, 101) {
    sum += i
  }
  assert(sum == 5050)
*/
next :: #force_inline proc "contextless" (tasks: ^int, count: int) -> (int, bool) {
	idx := intrinsics.atomic_add_explicit(tasks, 1, .Seq_Cst)
	return idx, idx < count
}

/*
Wakes all threads up, and post a new task
*/
@(synchronizes = .Release)
sema_post :: proc(pool: ^Pool, task: ^Task) -> runtime.Allocator_Error {
	when ODIN_VALGRIND_SUPPORT {
		vg.helgrind_sem_post_pre(&pool.sema)
	}

	{
		sync.guard(&pool.mutex)
		append(&pool.queue, task) or_return
	}

	intrinsics.atomic_add_explicit(&pool.sema, 1, .Release)
	sync.futex_broadcast(&pool.sema)

	return nil
}

/*
Waits until a new task is posted, or the thread should stop.
*/
@(synchronizes = .Acquire)
sema_wait :: proc(pool: ^Pool, last_generation: ^sync.Futex, should_reset: ^bool) -> ^Task {
	last_gen := last_generation^
	for {
		current := intrinsics.atomic_load_explicit(&pool.sema, .Acquire)

		// Wait until all threads are done
		if intrinsics.unlikely(
			pool.should_end && intrinsics.atomic_load(&pool.tasks_pending) == 0,
		) {
			return nil
		}

		// Only runs on wait_task
		if intrinsics.unlikely(should_reset^ != pool.should_reset) {
			should_reset^ = !should_reset^
			last_gen = 0
			free_all(context.temp_allocator)
		}

		if current > last_gen {
			when ODIN_VALGRIND_SUPPORT {
				vg.helgrind_sem_wait_post(&pool.sema)
			}
			last_generation^ = last_gen + 1
			// Lock against reallocation
			sync.guard(&pool.mutex)
			return pool.queue[last_gen]
		}

		sync.futex_wait(&pool.sema, u32(current))
	}
	unreachable()
}

/*
Thread procedure initialization.
*/
_init :: proc(t: ^thread.Thread) {
	pool := (cast(^Pool)t.data)

	CONTEXT_POOL = pool
	CONTEXT_THREAD_COUNT = len(pool.threads)
	CURRENT_THREAD_ID = t.user_index

	last_generation: sync.Futex
	should_reset := false

	when !ODIN_DISABLE_ASSERT {
		context.assertion_failure_proc = default_assertion_failure_proc
	}

	for {
		task := sema_wait(pool, &last_generation, &should_reset)

		if task == nil do break

		task.fn(task)

		done := intrinsics.atomic_add_explicit(&task.done, 1, .Seq_Cst) + 1
		// Only last thread is allowed to decrease the counter
		if done == thread_count() {
			intrinsics.atomic_sub_explicit(&pool.tasks_pending, 1, .Seq_Cst)
		}
	}
}

/*
Tasks can be added from within other threads.
*/
add_task :: proc(
	pool: ^Pool,
	fn: Task_Proc,
	data: ..rawptr,
	allocator := context.temp_allocator,
) -> (
	task: ^Task,
	err: runtime.Allocator_Error,
) #optional_allocator_error {
	if pool == nil do return

	context.allocator = allocator

	task = cast(^Task)mem.malloc(size_of(Task) + size_of(rawptr) * len(data)) or_return
	args := mem.shift(task, rawptr, len(data))

	for d, i in data do args[i] = d

	task.fn = fn
	task.data = args

	intrinsics.atomic_add_explicit(&pool.tasks_pending, 1, .Seq_Cst)

	if err = sema_post(pool, task); err != nil {
		free(task)
		return nil, err
	}

	return
}

/*
Destroys the task created by add_task.

If tasks are created in threads in recursion, use a temp_allocator, instead.
*/
destroy_task :: proc(task: ^Task) {
	if task == nil do return
	free(task)
}

/*
Waits until all threads finished all tasks.

Should be called at main thread.

This will also clear the queue and temp_allocator from all threads.
*/
wait_task :: proc(pool: ^Pool) -> bool {
	if pool == nil do return false
	for {
		if intrinsics.atomic_load(&pool.tasks_pending) == 0 do break
		if pool.should_die do return false
		thread.yield()
	}

	pool.should_reset = !pool.should_reset
	pool.sema = 0
	clear(&pool.queue)

	return true
}

// TBD: destroy
terminate :: proc(pool: ^Pool, error_code := 1) {
	if pool == nil do return

	threads := pool.threads
	current_thread := thread_id()
	for t, i in threads {
		if t == nil || i == current_thread do continue
		thread.terminate(t, error_code)
	}
	thread.terminate(threads[current_thread], error_code)
}

// TBD: always support thread failure
default_assertion_failure_proc :: proc(
	prefix, message: string,
	loc: runtime.Source_Code_Location,
) -> ! {
	if CONTEXT_POOL != nil {
		CONTEXT_POOL.should_die = true
		sync.mutex_lock(&CONTEXT_POOL.err)
	}
	runtime.default_assertion_contextless_failure_proc(prefix, message, loc)
}

/*
TBD

You can also start multiple times for different contexts.
*/
@(require_results)
init :: proc(
	args: [thread.MAX_USER_ARGUMENTS]rawptr = nil,
	thread_count: int = -1,
	context_name: string = "thread",
	pass_context: bool = true,
	starter: thread.Thread_Proc = _init,
) -> (
	pool: ^Pool,
	err: Error,
) {
	thread_count := os.get_processor_core_count() if thread_count < 1 else thread_count

	pool = auto_cast mem.malloc(size_of(Pool) + (size_of(^thread.Thread) * thread_count)) or_return
	pool.threads = mem.shift(pool, ^thread.Thread, thread_count)

	// Create all threads first, because if any fails, no thread has
	// yet started executing, avoid having to terminate them.
	for i in 0 ..< thread_count {
		// create() uses context.allocator
		t := thread.create(starter, name = fmt.tprintf("%s-%d", context_name, i))
		if t == nil {
			for j in 0 ..< i {
				thread.destroy(pool.threads[j])
			}
			free(pool)
			err = .Creation_Failed; return
		}
		pool.threads[i] = t
	}

	_context: Maybe(runtime.Context) = context if pass_context else nil

	for i in 0 ..< thread_count {
		t := pool.threads[i]
		t.data = pool
		t.user_index = i
		t.user_args = args
		t.init_context = _context
		thread.start(t)
	}

	return
}

/*
Joins all threads created by init, and clear their memory.
*/
join :: proc(pool: ^Pool) {
	if pool == nil do return
	pool.should_end = true

	for intrinsics.atomic_load(&pool.tasks_pending) != 0 {
		thread.yield()
	}

	intrinsics.atomic_add_explicit(&pool.sema, 1, .Release)
	sync.futex_broadcast(&pool.sema)

	threads := pool.threads
	thread.join_multiple(..threads[:])
	allocator := threads[0].creation_allocator

	for t in threads {
		free(t, allocator)
	}
	free(pool, allocator)
}
