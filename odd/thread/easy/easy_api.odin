package odd_thread_easy

import "base:intrinsics"
import rt "base:runtime"
import "core:sync"
import "core:thread"
import "shared:odd/mem"
import odd_thread "shared:odd/thread"

/*
This implements mostly of what the user would have to implement, both
as convenience, and as an example.
*/

Task_Proc :: proc(t: ^Task)

Task :: struct {
	data:      []rawptr,
	procedure: Task_Proc,
	done:      int,
}

/*
Creates and initializes the pool.
*/
@(require_results)
init :: proc(
	args: [thread.MAX_USER_ARGUMENTS]rawptr = nil,
	thread_count: int = -1,
	priority: thread.Thread_Priority = .Normal,
	context_name: string = "thread",
	runner: thread.Thread_Proc = runner,
	pass_context := true,
) -> (
	pool: ^odd_thread.Pool,
	err: rt.Allocator_Error,
) {
	thread_count := odd_thread.select_thread_count(thread_count)

	pool = odd_thread.create_pool(thread_count) or_return
	defer if err != nil {
		free(pool)
	}

	ok := #force_inline odd_thread.init(
		&pool.threads,
		pool,
		runner,
		args,
		priority,
		context_name,
		pass_context,
	)
	if !ok {
		err = .Out_Of_Memory
	}

	return
}

/*
Thread runner.

If the user has a custom assertion_failure_proc, don't forget to call broadcast_error(),
then park()
*/
runner :: proc(t: ^thread.Thread) {
	odd_thread.register_thread_backtrace()

	Pool :: odd_thread.Pool

	pool := (cast(^Pool)t.data)

	odd_thread.context_pool = pool
	odd_thread.context_thread_count = len(pool.threads)
	odd_thread.current_thread_id = t.user_index

	if context.assertion_failure_proc == rt.default_assertion_failure_proc {
		context.assertion_failure_proc = odd_thread.default_assertion_failure_proc
	}

	buffer: [1 << 8]rawptr // 2048 bytes

	tasks: []rawptr
	task_index: int

	should_reset: bool

	// TBD: maybe make the Task an union? Points to think about:
	// - If the thread user_index is not relevant, let threads steal
	// tasks from other threads
	// - Optionally let the user procedure increment the done counter
	// as it becomes a free cleanup marker
	run :: proc(pool: ^Pool, task: ^Task) {
		task.procedure(task)

		done := intrinsics.atomic_add_explicit(&task.done, 1, .Relaxed) + 1
		// Only last thread is allowed to decrease the counter
		if done == odd_thread.context_thread_count {
			intrinsics.atomic_sub_explicit(&pool.tasks_pending, 1, .Relaxed)
			// Signal task done
			intrinsics.atomic_store_explicit(&task.done, -1, .Relaxed)
		}
	}

	die: for {
		for {
			// Wait until all threads are done, or a thread failed
			if pool.should_die ||
			   pool.should_end && intrinsics.atomic_load(&pool.tasks_pending) == 0 {
				break die
			}

			// Only runs on reset(), ideally after all threads finished the work
			// This may break, depending on how the threads are used
			if should_reset != pool.should_reset {
				should_reset = !should_reset
				task_index = 0
				free_all(context.temp_allocator)
			}

			tasks_left :=
				intrinsics.atomic_load_explicit(&pool.tasks_assigned, .Relaxed) - task_index

			if tasks_left == 1 {
				// Skip slice copying, and slice iteration
				// Lock against queue reallocation
				sync.mutex_lock(&pool.queue_mutex)
				task := pool.queue[task_index]
				sync.mutex_unlock(&pool.queue_mutex)
				task_index += 1
				run(pool, cast(^Task)task)
				continue
			} else if tasks_left > 1 {
				count := min(len(buffer), tasks_left)
				// Lock against queue reallocation
				sync.mutex_lock(&pool.queue_mutex)
				copy_slice(buffer[:count], pool.queue[task_index:task_index + count])
				sync.mutex_unlock(&pool.queue_mutex)
				tasks = buffer[:count]
				task_index += count
				break
			}

			current := intrinsics.atomic_load_explicit(&pool.sema, .Acquire)
			odd_thread.sema_wait(&pool.sema, current)
		}

		for i in 0 ..< len(tasks) {
			if pool.should_die do break die
			run(pool, cast(^Task)tasks[i])
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
	pool: ^odd_thread.Pool,
	procedure: Task_Proc,
	data: ..rawptr,
	allocator := context.temp_allocator,
) -> (
	task: ^Task,
	err: rt.Allocator_Error,
) #optional_allocator_error {
	if pool == nil do return

	context.allocator = allocator

	task = cast(^Task)mem.malloc(size_of(Task) + size_of(rawptr) * len(data)) or_return
	args := mem.shift(task, rawptr, len(data))

	for d, i in data do args[i] = d

	task.procedure = procedure
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

	intrinsics.atomic_add_explicit(&pool.tasks_assigned, 1, .Relaxed)
	odd_thread.sema_post(&pool.sema)

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

wait_task :: proc(pool: ^odd_thread.Pool, tasks: ..^Task) {
	for task in tasks {
		for {
			intrinsics.cpu_relax()
			thread.yield()
			if task.done == -1 {
				break
			}
		}
	}
}
