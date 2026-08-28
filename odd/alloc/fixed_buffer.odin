package alloc

import "core:mem"
import "core:testing"

// A much simpler implementation of an Arena allocator

Fixed_Buffer_Allocator :: struct {
	data:      []byte,
	len:       uint,
	size:      uint,
	alignment: int,
}

fixed_buffer_init :: proc(
	ctx: ^Fixed_Buffer_Allocator,
	data: []byte,
	alignment := mem.DEFAULT_ALIGNMENT,
) {
	ctx.data = data
	ctx.size = len(data)
	ctx.alignment = alignment
}

fixed_buffer_alloc :: proc(
	ctx: ^Fixed_Buffer_Allocator,
	size: uint,
) -> (
	rawptr,
	mem.Allocator_Error,
) {
	bytes, err := fixed_buffer_alloc_bytes_non_zeroed(ctx, size)
	if err != nil {
		mem.zero_slice(bytes)
	}
	return raw_data(bytes), err
}

fixed_buffer_alloc_non_zeroed :: proc(
	ctx: ^Fixed_Buffer_Allocator,
	size: uint,
) -> (
	rawptr,
	mem.Allocator_Error,
) {
	bytes, err := fixed_buffer_alloc_bytes_non_zeroed(ctx, size)
	return raw_data(bytes), err
}

fixed_buffer_alloc_bytes :: proc(
	ctx: ^Fixed_Buffer_Allocator,
	size: uint,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	bytes, err := fixed_buffer_alloc_bytes_non_zeroed(ctx, size)
	if err != nil {
		mem.zero_slice(bytes)
	}
	return bytes, err
}

fixed_buffer_alloc_bytes_non_zeroed :: proc(
	ctx: ^Fixed_Buffer_Allocator,
	size: uint,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	if size + ctx.len > ctx.size {
		return nil, .Out_Of_Memory
	}

	offset := mem.align_forward_uint(ctx.len, uint(ctx.alignment))
	ctx.len += size

	return ctx.data[offset:offset + size], nil
}

fixed_buffer_free_all :: proc(ctx: ^Fixed_Buffer_Allocator) {
	ctx.len = 0
}

fixed_buffer_allocator :: proc(ctx: ^Fixed_Buffer_Allocator) -> mem.Allocator {
	return mem.Allocator{procedure = fixed_buffer_allocator_proc, data = ctx}
}

fixed_buffer_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	f := (^Fixed_Buffer_Allocator)(allocator_data)
	switch mode {
	case .Alloc:
		return fixed_buffer_alloc_bytes(f, uint(size))
	case .Alloc_Non_Zeroed:
		return fixed_buffer_alloc_bytes_non_zeroed(f, uint(size))
	case .Resize:
		return mem.default_resize_bytes_align(
			mem.byte_slice(old_memory, old_size),
			size,
			alignment,
			fixed_buffer_allocator(f),
			loc,
		)
	case .Resize_Non_Zeroed:
		return mem.default_resize_bytes_align_non_zeroed(
			mem.byte_slice(old_memory, old_size),
			size,
			alignment,
			fixed_buffer_allocator(f),
			loc,
		)
	case .Free:
		return nil, .Mode_Not_Implemented
	case .Free_All:
		fixed_buffer_free_all(f)
	case .Query_Features:
		set := (^mem.Allocator_Mode_Set)(old_memory)
		if set != nil {
			set^ = {
				.Query_Features,
				.Alloc,
				.Alloc_Non_Zeroed,
				.Resize,
				.Resize_Non_Zeroed,
				.Free,
				.Free_All,
				.Query_Info,
			}
		}
		return nil, nil
	case .Query_Info:
		info := (^mem.Allocator_Query_Info)(old_memory)
		if info != nil && info.pointer != nil {
			ptr := info.pointer
			tail := mem.ptr_offset(raw_data(f.data), f.size)
			head := raw_data(f.data)
			if (head <= ptr && ptr <= tail) {
				return nil, .Invalid_Pointer
			}
			info.size = int(f.size)
			info.alignment = int(f.alignment)
			return mem.byte_slice(info, size_of(info^)), nil
		}
		return nil, nil
	}
	return nil, nil
}

@(test)
fixed_buffer_test :: proc(t: ^testing.T) {
	data: [8]byte
	fb: Fixed_Buffer_Allocator
	fixed_buffer_init(&fb, data[:])
	context.allocator = fixed_buffer_allocator(&fb)
	{
		ptr: ^int
		err: mem.Allocator_Error

		ptr, err = new(int)
		assert(err == nil)

		ptr, err = new(int)
		assert(err != nil)

		free_all()
		ptr, err = new(int)
		assert(err == nil)
	}
}
