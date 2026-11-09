package odd_thread

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:sync"
import vg "core:sys/valgrind"
import "core:thread"
import "shared:odd/mem"

/*
Notes:

The Odin documentation doesn't tell the default ordering for atomic_*.
In the source code, it defaults to LLVMAtomicOrderingSequentiallyConsistent -> Seq_Cst
this is true for all atomic_*

TBD:

- Extra work on how to handle thread errors? -> always graceful, or termination?
- Should threads be recreated after failure? -> track thread state
- Experiment the library, to find more use cases that may change the implementation
- Should Task_Proc really take a Task, or just the Task.data?
- Maybe make the Task an union?
*/

IS_SUPPORTED :: thread.IS_SUPPORTED
MAX_USER_ARGUMENTS :: thread.MAX_USER_ARGUMENTS

Task_Proc :: proc(t: ^Task)

Task :: struct {
	data: []rawptr,
	fn:   Task_Proc,
	done: int,
}

Pool :: struct {
	// Won't shrink, but memory is reused
	queue:         [dynamic]^Task,
	threads:       []^thread.Thread,
	// Lock queue interaction
	queue_mutex:   sync.Mutex,
	// Locks on thread failure
	err:           sync.Mutex,
	// Tasks to be done. It's atomic
	tasks_pending: int,
	// Broadcasts to all threads. It's atomic
	sema:          sync.Futex,
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
Design decision: These could be all private, to make sure the user
won't touch these variables, but I'm sure you won't write after they
are initialized, right? Great! Otherwise, that's a reason why Rust
always wrap globals around atomics, or alike.

Jokes aside. I'll try very hard to make this API privateless,
so you can reuse parts of this with a custom one.
*/
@(thread_local)
current_thread_id: int
@(thread_local)
context_thread_count: int
@(thread_local)
context_pool: ^Pool

/*
Returns Thread.user_args.

Only use inside a thread.
*/
thread_user_args :: #force_inline proc "contextless" () -> ^[MAX_USER_ARGUMENTS]rawptr {
	return &context_pool.threads[current_thread_id].user_args
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
range :: proc "contextless" (count: int) -> Range {
	id, thread_count := current_thread_id, context_thread_count
	per_thread, leftover := count / thread_count, count % thread_count
	extra := int(id < leftover)
	begin := per_thread * id + min(id, leftover)
	return {begin, begin + per_thread + extra}
}

next :: proc {
	next_static,
	next_dynamic,
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
@(synchronizes = .Seq_Cst)
next_static :: #force_inline proc "contextless" (tasks: ^int, count: int) -> (int, bool) {
	idx := intrinsics.atomic_add(tasks, 1)
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
    if i == 99 do intrinsics.atomic_add(&work, 1)
  }
  assert(sum == 5050)
*/
@(synchronizes = .Acquire)
next_dynamic :: #force_inline proc "contextless" (tasks: ^int, count: ^int) -> (int, bool) {
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
Waits until a new task is posted, or the thread should stop.
*/
@(futex = .Wait)
sema_wait :: proc(
	sema: ^sync.Futex,
	pool: ^Pool,
	last_generation: ^sync.Futex,
	should_reset: ^bool,
) -> ^Task {
	last_gen := last_generation^
	for {
		current := intrinsics.atomic_load_explicit(sema, .Acquire)

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
				vg.helgrind_sem_wait_post(sema)
			}
			last_generation^ = last_gen + 1
			// Lock against queue reallocation
			sync.guard(&pool.queue_mutex)
			return pool.queue[last_gen]
		}

		sync.futex_wait(sema, u32(current))
	}
	unreachable()
}

/*
Thread runner.

If the user has a custom assertion_failure_proc, don't forget to call errlock()

You can replace this with a custom one.
*/
_init :: proc(t: ^thread.Thread) {
	pool := (cast(^Pool)t.data)

	context_pool = pool
	context_thread_count = len(pool.threads)
	current_thread_id = t.user_index

	last_generation: sync.Futex
	should_reset: bool

	if context.assertion_failure_proc == runtime.default_assertion_failure_proc {
		context.assertion_failure_proc = default_assertion_failure_proc
	}

	for {
		task := sema_wait(&pool.sema, pool, &last_generation, &should_reset)

		if task == nil do break

		task.fn(task)

		done := intrinsics.atomic_add_explicit(&task.done, 1, .Relaxed) + 1
		// Only last thread is allowed to decrease the counter
		if done == context_thread_count {
			intrinsics.atomic_sub_explicit(&pool.tasks_pending, 1, .Relaxed)
		}
	}
}

/*
Adds a new task to the queue.

Only at the main thread. You may free the Task using destroy_task, if
you prefer to don't use the temp_allocator.

Can be called from any thread.
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

	intrinsics.atomic_add_explicit(&pool.tasks_pending, 1, .Relaxed)

	{
		context.allocator = pool.threads[0].creation_allocator
		sync.guard(&pool.queue_mutex)
		_, err = append(&pool.queue, task)
	}

	if err != nil {
		free(task)
		return nil, err
	}

	sema_post(&pool.sema)

	return
}

/*
Destroys the task created by add_task.

If tasks are created in threads in recursion, use a temp_allocator, instead.
Threads that create a task also should run that task, which makes
"defer destroy_task" not an option.
*/
destroy_task :: proc(task: ^Task, allocator := context.temp_allocator) {
	if task == nil do return
	free(task, allocator)
}

/*
Waits until all threads finished all tasks.

This will also clear the queue and temp_allocator from all threads.

Only use inside the main thread.

When return "false", a thread failed. You may call terminate(), then destroy(),
even when the pool is invalid.
*/
wait_task :: proc(pool: ^Pool) -> bool {
	if pool == nil do return false
	for {
		if intrinsics.atomic_load_explicit(&pool.tasks_pending, .Relaxed) == 0 do break
		if pool.should_die do return false
		intrinsics.cpu_relax()
		thread.yield()
	}

	pool.should_reset = !pool.should_reset
	pool.sema = 0
	clear(&pool.queue)

	return true
}

/*
Forcibly terminates all threads.

May be called from the main thread, when pool.should_die is true.
*/
terminate :: proc(pool: ^Pool, error_code := 1) {
	if pool == nil do return
	for t, i in pool.threads {
		thread.terminate(t, error_code)
	}
}

/*
Locks the error mutex.

Can be called from any thread.
*/
errlock :: proc "contextless" () {
	if context_pool != nil {
		if sync.mutex_try_lock(&context_pool.err) do context_pool.should_die = true
	}
}

/*
Procedures like ensure, panic and unimplemented will use this,
but procedures like os.exit, won't. Call errlock() before the the former

Do not set this in the main thread's context.
*/
default_assertion_failure_proc :: proc(
	prefix, message: string,
	loc: runtime.Source_Code_Location,
) -> ! {
	// Let only one thread print error
	sync.mutex_lock(&context_pool.err)
	// Odin's runtime.default_assertion_contextless_failure_proc:
	when ODIN_OS == .Freestanding {
		// Do nothing
	} else {
		when ODIN_OS != .Orca && !ODIN_DISABLE_ASSERT {
			runtime.print_caller_location(loc)
			runtime.print_string(" ")
		}
		runtime.print_string(prefix)
		if len(message) > 0 {
			runtime.print_string(": ")
			runtime.print_string(message)
		}

		when ODIN_OS == .Orca {
			assert_fail(
				cstring(raw_data(loc.file_path)),
				cstring(raw_data(loc.procedure)),
				loc.line,
				"",
				cstring(raw_data(orca_stderr_buffer[:orca_stderr_buffer_idx])),
			)
		} else {
			runtime.print_byte('\n')
		}
	}
	when runtime.ODIN_CODEPAGE_MAGIC {
		SetConsoleOutputCP(old_console_codepage)
	}
	// Have time to print error, then to broadcast failure
	context_pool.should_die = true
	intrinsics.trap()
}

/*
Initializes the thread pool.

"args" will be available to all threads from the context.

"thread_count" by default will be set to the machine's CPU count, but you
may raise it further.

"pass_context" will use the main thread context and pass it to all created
threads. Useful when you want to initialize things like a logger once. Otherwise,
you can pass custom "runner", or use the default context thread.create gives you.

Uses context.allocator as the thread creation allocator.

You can also start multiple times for different contexts.
*/
@(require_results)
init :: proc(
	args: [MAX_USER_ARGUMENTS]rawptr = nil,
	thread_count: int = -1,
	priority: thread.Thread_Priority = .Normal,
	context_name: string = "thread",
	pass_context: bool = true,
	runner: thread.Thread_Proc = _init,
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
		t := thread.create(runner, priority, fmt.tprintf("%s-%d", context_name, i))
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
Joins all threads created by init, and frees their memory.

When return "false", a thread failed. You may call terminate(), then destroy()
*/
join :: proc(pool: ^Pool) -> bool {
	if pool == nil do return false
	pool.should_end = true

	for intrinsics.atomic_load_explicit(&pool.tasks_pending, .Relaxed) != 0 {
		if pool.should_die do return false
		intrinsics.cpu_relax()
		thread.yield()
	}

	sema_post(&pool.sema)

	thread.join_multiple(..pool.threads[:])
	destroy(pool)

	return true
}

/*
Frees pool and thread memory.
*/
destroy :: proc(pool: ^Pool) {
	context.allocator = pool.threads[0].creation_allocator
	for t in pool.threads do free(t)
	free(pool)
}
