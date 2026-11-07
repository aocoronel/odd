package odd_thread

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:sync"
import "core:thread"
import "shared:odd/mem"
import "shared:odd/thread/sema"

Task_Proc :: proc(t: ^Task)

Task :: struct {
	fn:   Task_Proc,
	data: []rawptr,
	done: int,
}

/*
In THREAD, all values are available in CONTEXT_POOL, otherwise
only fn and barreir are valid.
*/
Pool :: struct {
	queue:                  [dynamic]^Task,
	threads:                []^thread.Thread,
	mutex, err:             sync.Mutex,
	sema:                   sema.Sema,
	should_die, should_end: bool,
}

Error :: union {
	runtime.Allocator_Error,
	Multicore_Error,
}

Multicore_Error :: enum {
	Ok = 0,
	Too_Many_Args,
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
Returns the thread id from the current context. Not to be confused with
thread.Thread.id.
*/
thread_id :: #force_inline proc "contextless" () -> int {
	return CURRENT_THREAD_ID
}

/*
Returns how many threads make part of the current context
*/
thread_count :: #force_inline proc "contextless" () -> int {
	return CONTEXT_THREAD_COUNT
}

/*
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
Example: assuming 1 thread

  @(static) tasks: int
  sum: int
  for i in next(tasks, 101) {
    sum += i
  }
  assert(sum == 5050)
*/
next :: #force_inline proc "contextless" (tasks: ^int, count: int) -> (int, bool) {
	idx := intrinsics.atomic_add_explicit(tasks, 1, .Seq_Cst)
	return idx, idx < count
}

broadcast :: proc(ptr: ^$T, barrier: ^sync.Barrier, leader_id := 0) -> ^T {
	@(static) result: ^T

	sync.barrier_wait(&barrier)

	if thread_id() == leader_id {
		sync.barrier_wait(&barrier)
		return result
	}

	result = ptr
	sync.barrier_wait(&barrier)
	return ptr
}

/*
Thread procedure initialization
*/
_start :: proc(t: ^thread.Thread) {
	pool := (cast(^Pool)t.data)

	CONTEXT_POOL = pool
	CONTEXT_THREAD_COUNT = len(pool.threads)
	CURRENT_THREAD_ID = t.user_index

	last_generation: sync.Futex

	// when !runtime.ODIN_DISABLE_ASSERT {
	context.assertion_failure_proc = default_assertion_failure_proc
	// }

	for {
		sema.wait(&pool.sema, &last_generation)
		task_index := int(last_generation) - 1

		tasks: int

		{
			sync.guard(&pool.mutex)
			tasks = len(pool.queue)
		}

		if pool.should_end && task_index == tasks do break

		if intrinsics.unlikely(task_index > tasks) {
			last_generation = 0; task_index = 0
			free_all(context.temp_allocator)
		}

		if task_index < tasks {
			task := pool.queue[task_index]
			task.fn(task)
			intrinsics.atomic_add_explicit(&task.done, 1, .Seq_Cst)
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

	{
		sync.guard(&pool.mutex)
		_, err = append(&pool.queue, task)
		if err != nil {free(task); return}
	}

	sema.post(&pool.sema)

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
Waits until all threads finished all tasks. Should be called at main thread.
This will also clear the queue and temp_allocator from all threads.
*/
wait_task :: proc(pool: ^Pool) {
	if pool == nil do return
	last_queue := pool.queue[len(pool.queue) - 1]
	for {
		if last_queue.done >= len(pool.threads) || pool.should_die do break
		thread.yield()
	}

	clear(&pool.queue)
}

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
Starts at least 1 thread to run "fn", if THREAD is true.

You can provide any parameter, within the boundaries of thread.MAX_USER_ARGUMENTS.

Example:

  pool, err := start(foo, "foo", "bar", "baz")
  if err != nil {
    fmt.println(err); return
  }
  join(pool)

You can also start multiple times for different contexts.
*/
@(require_results)
start :: proc(
	args: [thread.MAX_USER_ARGUMENTS]rawptr = nil,
	thread_count: int = -1,
	context_name: string = "thread",
	_context: runtime.Context = context,
	starter: thread.Thread_Proc = _start,
) -> (
	pool: ^Pool,
	err: Error,
) {
	if len(args) > thread.MAX_USER_ARGUMENTS {
		err = .Too_Many_Args; return
	}

	thread_count := os.get_processor_core_count() if thread_count < 1 else thread_count

	pool = auto_cast mem.malloc(size_of(Pool) + (size_of(^thread.Thread) * thread_count)) or_return
	pool.threads = mem.shift(pool, ^thread.Thread, thread_count)

	/*
      Create all threads first, because if any fails, no thread has
      yet started executing, avoid having to terminate them.
    */
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
Joins all threads created by start, and clear their memory.
*/
join :: proc(pool: ^Pool) {
	if pool == nil do return
	pool.should_end = true
	threads := pool.threads
	sema.post(&pool.sema)
	thread.join_multiple(..threads[:])
	allocator := threads[0].creation_allocator
	for t in threads {
		free(t, allocator)
	}
	free(pool, allocator)
}
