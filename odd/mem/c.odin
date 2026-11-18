package odd_mem

import "base:runtime"
import "core:mem"

shift_bytes_unaligned :: #force_inline proc "contextless" (ptr: rawptr, size: int) -> rawptr {
	return rawptr(uintptr(ptr) + uintptr(size))
}

allocate_types :: proc {
	allocate_types2,
	allocate_types3,
	allocate_types4,
}

allocate_types2 :: #force_inline proc(
	$T1, $T2: typeid,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	p1: ^T1,
	p2: ^T2,
	err: runtime.Allocator_Error,
) {
	align1 :: align_of(T1)
	align2 :: align_of(T2)
	max_align := max(align1, align2)

	off1 :: 0
	off2 := mem.align_formula(off1 + size_of(T1), align2)
	total := off2 + size_of(T2)

	data := allocator.procedure(
		allocator.data,
		.Alloc,
		total,
		max_align,
		nil,
		0,
		location = loc,
	) or_return

	base := uintptr(raw_data(data))
	p1 = cast(^T1)rawptr(base + uintptr(off1))
	p2 = cast(^T2)rawptr(base + uintptr(off2))
	return
}

allocate_types3 :: #force_inline proc(
	$T1, $T2, $T3: typeid,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	p1: ^T1,
	p2: ^T2,
	p3: ^T3,
	err: runtime.Allocator_Error,
) {
	align1 :: align_of(T1)
	align2 :: align_of(T2)
	align3 :: align_of(T3)
	max_align := max(align1, align2, align3)

	off1 :: 0
	off2 := mem.align_formula(off1 + size_of(T1), align2)
	off3 := mem.align_formula(off2 + size_of(T2), align3)
	total := off3 + size_of(T3)

	data := allocator.procedure(
		allocator.data,
		.Alloc,
		total,
		max_align,
		nil,
		0,
		location = loc,
	) or_return

	base := uintptr(raw_data(data))
	p1 = cast(^T1)rawptr(base + uintptr(off1))
	p2 = cast(^T2)rawptr(base + uintptr(off2))
	p3 = cast(^T3)rawptr(base + uintptr(off3))
	return
}

allocate_types4 :: #force_inline proc(
	$T1, $T2, $T3, $T4: typeid,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	p1: ^T1,
	p2: ^T2,
	p3: ^T3,
	p4: ^T4,
	err: runtime.Allocator_Error,
) {
	align1 :: align_of(T1)
	align2 :: align_of(T2)
	align3 :: align_of(T3)
	align4 :: align_of(T4)
	max_align := max(align1, align2, align3, align4)

	off1 :: 0
	off2 := mem.align_formula(off1 + size_of(T1), align2)
	off3 := mem.align_formula(off2 + size_of(T2), align3)
	off4 := mem.align_formula(off3 + size_of(T3), align4)
	total := off4 + size_of(T4)

	data := allocator.procedure(
		allocator.data,
		.Alloc,
		total,
		max_align,
		nil,
		0,
		location = loc,
	) or_return

	base := uintptr(raw_data(data))
	p1 = cast(^T1)rawptr(base + uintptr(off1))
	p2 = cast(^T2)rawptr(base + uintptr(off2))
	p3 = cast(^T3)rawptr(base + uintptr(off3))
	p4 = cast(^T4)rawptr(base + uintptr(off4))
	return
}
