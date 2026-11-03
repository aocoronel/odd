package odd_mem

import "base:runtime"

/*
Warning: this procedure is very odd to be in Odin. Here be dragons.

Example:

	state = auto_cast mem.malloc(
			size_of(State) +
			size_of(sync.Barrier) +
			(size_of(^thread.Thread) * thread_count)) or_return

	state.barrier = mem.shift(state, sync.Barrier)
	state.threads = mem.shift(state.barrier, ^thread.Thread, thread_count)

The example above is a real one from odd/thread.
And it's doing a very useful task.

Many times we need to allocate like:

  var1 := new(int) or_return
  defer free(var1)
  var2 := new(int) or_return
  defer free(var2)

If this was C, they would complain the language lacks "defer".
However, paying "defer" here means having two allocation calls,
but they make part of the same context window! The example allocates
three variables under a single pointer and from a single allocation,
and can be later freed with a single:

  free(state)

Essentially a lightweight arena.

I thought it would be useful to comment on it, since I learned it by
writing C, and I never really saw anyone doing this before.
*/
malloc :: #force_inline proc(
	#any_int size: uint,
	allocator := context.allocator,
) -> (
	ptr: rawptr,
	err: runtime.Allocator_Error,
) #optional_allocator_error {
	return rawptr(make([^]u8, size, allocator) or_return), nil
}

shift :: proc {
	shift_bytes,
	shift_type,
	shift_slice,
}

shift_bytes :: #force_inline proc "contextless" (ptr: rawptr, size: int) -> rawptr {
	return rawptr(uintptr(ptr) + uintptr(size))
}

shift_type :: #force_inline proc "contextless" (ptr: ^$T, $O: typeid) -> ^O {
	return cast(^O)rawptr(uintptr(ptr) + uintptr(size_of(T)))
}

shift_slice :: #force_inline proc "contextless" (
	ptr: ^$T,
	$O: typeid,
	length: int,
) -> []O #no_bounds_check {
	return (cast([^]O)rawptr(uintptr(ptr) + uintptr(size_of(T))))[:length]
}
