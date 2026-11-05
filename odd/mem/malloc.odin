package odd_mem

import "base:intrinsics"
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
	#any_int size: int,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	ptr: rawptr,
	err: runtime.Allocator_Error,
) #optional_allocator_error {
	data := allocator.procedure(
		allocator.data,
		.Alloc,
		size,
		align_of(u8),
		nil,
		0,
		location = loc,
	) or_return
	return raw_data(data), nil
}

shift :: proc {
	shift_bytes,
	shift_type,
	shift_slice,
	shift_from_slice_to_type,
	shift_from_slice_to_slice,
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

shift_from_slice_to_type :: #force_inline proc "contextless" (
	ptr: []$T,
	$O: typeid,
) -> ^O #no_bounds_check {
	return cast(^O)rawptr(uintptr(raw_data(ptr)) + uintptr(size_of(T) * len(ptr)))
}

shift_from_slice_to_slice :: #force_inline proc "contextless" (
	ptr: []$T,
	$O: typeid,
	length: int,
) -> []O #no_bounds_check {
	return (cast([^]O)rawptr(uintptr(raw_data(ptr)) + uintptr(size_of(T) * len(ptr))))[:length]
}
