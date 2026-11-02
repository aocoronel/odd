package odd_thread

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:sync"
import "core:thread"
import "shared:odd/mem"

THREAD :: #config(THREAD, false)

/*
In THREAD, all values are available in CONTEXT_STATE, otherwise
only fn and barreir are valid.
*/
State :: struct {
	threads:    []^thread.Thread,
	barrier:    ^sync.Barrier,
	mutex, err: ^sync.Mutex,
	fn:         proc(args: []any),
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
CONTEXT_STATE: ^State

/*
Returns the thread id from the current context. Not to be confused with
thread.Thread.id.
*/
thread_id :: #force_inline proc "contextless" () -> int {
	when THREAD {
		return CURRENT_THREAD_ID
	} else {
		return 0
	}
}

/*
Returns how many threads make part of the current context
*/
thread_count :: #force_inline proc "contextless" () -> int {
	when THREAD {
		return CONTEXT_THREAD_COUNT
	} else {
		return 1
	}
}

/*
Waits on all threads from current context
*/
wait :: #force_inline proc "contextless" () {
	when THREAD {
		sync.barrier_wait(CONTEXT_STATE.barrier)
	}
}

/*
These are convenience wrappers around sync.mutex_*
*/
@(deferred_none = unlock)
@(synchronizes = .Acquire)
guard :: #force_inline proc "contextless" () -> bool {
	when THREAD {
		sync.mutex_lock(CONTEXT_STATE.mutex)
		return true
	} else {
		return true
	}
}

lock :: #force_inline proc "contextless" () {
	when THREAD {
		sync.mutex_lock(CONTEXT_STATE.mutex)
	}
}

unlock :: #force_inline proc "contextless" () {
	when THREAD {
		sync.mutex_unlock(CONTEXT_STATE.mutex)
	}
}

try_lock :: #force_inline proc "contextless" () -> bool {
	when THREAD {
		return sync.mutex_try_lock(CONTEXT_STATE.mutex)
	} else {
		return true
	}
}

when THREAD {
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
} else {
	range :: #force_inline proc "contextless" (count: int) -> Range {
		return Range{0, count}
	}
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
	when THREAD {
		idx := intrinsics.atomic_add_explicit(tasks, 1, .Seq_Cst)
		return idx, idx < count
	} else {
		tasks^ += 1
		return tasks^, tasks^ < count
	}
}

/*
Define a custom leader_id, only when you plan to split your threads,
after they have started with start()

Further synchronization has to be done manually, and you cannot rely
on the thread context anymore.
*/
is_leader :: #force_inline proc "contextless" (leader_idx := 0) -> bool {
	when THREAD {
		return leader_idx == thread_id()
	} else {
		return true
	}
}

/*
Thread procedure initialization
*/
_start :: proc(t: ^thread.Thread) {
	user_args := t.user_args
	data := (cast(^State)t.data)

	fn := data.fn

	CONTEXT_STATE = data
	CONTEXT_THREAD_COUNT = data.barrier.thread_count
	CURRENT_THREAD_ID = t.user_index

	// Digest user_args, so fn has typeid
	user_arguments: [thread.MAX_USER_ARGUMENTS]any
	i: int
	for arg in user_args {
		if arg == nil do break
		user_arguments[i] = (cast(^any)arg)^
		i += 1
	}

	// Wait all threads to finish preparation.
	wait()

	fn(user_arguments[:i])
}

terminate_all :: proc(err := 1) -> ! {
	when THREAD {
		sync.mutex_lock(CONTEXT_STATE.err)
	}
	_terminate_all(err)
}

/*
Calling this without locking CONTEXT_STATE.err may cause deadlocks!
*/
_terminate_all :: #force_inline proc(err := 1) -> ! {
	when THREAD {
		if CONTEXT_STATE == nil do os.exit(err)
		threads := CONTEXT_STATE.threads
		current_thread := thread_id()
		for t, i in threads {
			if t == nil || i == current_thread do continue
			thread.terminate(t, err)
		}
		thread.terminate(threads[current_thread], err)
		panic("unreachable")
	} else {
		os.exit(err)
	}
}

/*
Starts at least 1 thread to run "fn", if THREAD is true.

You can provide any parameter, within the boundaries of thread.MAX_USER_ARGUMENTS.

Example:

  state, err := start(foo, "foo", "bar", "baz")
  if err != nil {
    fmt.println(err); return
  }
  join(state)

You can also start multiple times for different contexts.
*/
start :: proc(
	fn: proc(_: []any),
	args: ..any,
	thread_count: int = -1,
	context_name: string = "thread",
	allocator := context.allocator,
) -> (
	state: ^State,
	err: Error,
) {
	if len(args) > thread.MAX_USER_ARGUMENTS {
		err = .Too_Many_Args; return
	}

	user_arguments: [thread.MAX_USER_ARGUMENTS]rawptr
	for &arg, i in args {
		user_arguments[i] = &arg
	}

	when THREAD {
		thread_count := os.get_processor_core_count() if thread_count < 1 else thread_count

		state = auto_cast mem.malloc(
			size_of(State) +
			size_of(sync.Barrier) +
			size_of(sync.Mutex) +
			size_of(sync.Mutex) +
			(size_of(^thread.Thread) * thread_count),
		) or_return
		state.barrier = mem.shift(state, sync.Barrier)
		state.mutex = mem.shift(state.barrier, sync.Mutex)
		state.err = mem.shift(state.mutex, sync.Mutex)
		state.threads = mem.shift(state.err, ^thread.Thread, thread_count)

		sync.barrier_init(state.barrier, thread_count)
		state.fn = fn

		/*
          Create all threads first, because if any fails, no thread has
          yet started executing, avoid having to terminate them.
        */
		for i in 0 ..< thread_count {
			// create() uses context.allocator
			t := thread.create(_start, name = fmt.tprintf("%s-%d", context_name, i))
			if t == nil {
				for j in 0 ..< i {
					thread.destroy(state.threads[j])
				}
				free(state)
				err = .Creation_Failed; return
			}
			state.threads[i] = t
		}

		for i in 0 ..< thread_count {
			t := state.threads[i]
			t.data = state
			t.user_index = i
			t.user_args = user_arguments
			t.init_context = context
			thread.start(t)
		}
	} else {
		t: thread.Thread
		barrier := sync.Barrier {
			thread_count = 1,
		}
		_state := State {
			fn      = fn,
			barrier = &barrier,
		}
		t.data = rawptr(&_state)
		t.user_index = 0
		t.user_args = user_arguments
		t.init_context = context
		_start(&t)
	}

	return
}

/*
Joins all threads created by start, and clear their memory.
*/
join :: proc(state: ^State) {
	when THREAD {
		if state == nil do return
		threads := state.threads
		thread.join_multiple(..threads[:])
		allocator := threads[0].creation_allocator
		for t in threads {
			free(t, allocator)
		}
		free(state, allocator)
	}
}
