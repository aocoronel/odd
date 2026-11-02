package odd_thread

import "base:runtime"
import "core:log"
import "core:mem"
import "core:sync"

Thread_Allocator :: struct {
	backing:   mem.Allocator,
	barrier:   ^sync.Barrier,
	leader_id: int,
}

/*
Use case: When you want to split threads to do different tasks.

Note: the provided barrier should either be static, global or
allocated using the single_region_thread_allocator.
*/
thread_allocator_init :: proc {
	thread_allocator_init_context,
	thread_allocator_init_explicit,
}

thread_allocator_init_explicit :: #force_inline proc "contextless" (
	allocator: mem.Allocator,
	barrier: ^sync.Barrier,
	thread_count: int,
	leader_id: int = 0,
) -> Thread_Allocator {
	return {allocator, barrier, leader_id}
}

/*
Convenience procedure, if you want to use the thread context.
*/
thread_allocator_init_context :: #force_inline proc "contextless" (
	allocator: mem.Allocator,
) -> Thread_Allocator {
	return {allocator, CONTEXT_STATE.barrier, 0}
}

mrt_allocator :: multi_region_thread_allocator
multi_region_thread_allocator :: #force_inline proc "contextless" (
	ctx: ^Thread_Allocator,
) -> mem.Allocator {
	when THREAD {
		return mem.Allocator{procedure = multi_region_thread_allocator_proc, data = ctx}
	} else {
		return mem.Allocator{procedure = ctx.backing.procedure, data = ctx.backing.data}
	}
}

/*
This procedure may check if the ctx.backing allocator is multi_region_thread_allocator
The is reason is, that it's more likely to be put on the context.allocator, and
if the srt_allocator was in the context, many procedures that are not part of this
framework would cause data races.
*/
srt_allocator :: single_region_thread_allocator
single_region_thread_allocator :: #force_inline proc "contextless" (
	ctx: ^Thread_Allocator,
) -> mem.Allocator {
	when THREAD {
		if ctx.backing.procedure == multi_region_thread_allocator_proc {
			return mem.Allocator {
				procedure = single_region_thread_allocator_proc,
				data = ctx.backing.data,
			}
		}
		return mem.Allocator{procedure = single_region_thread_allocator_proc, data = ctx}
	} else {
		return mem.Allocator{procedure = ctx.backing.procedure, data = ctx.backing.data}
	}
}

// Allocates shared memory, where each thread receives their own unique memory region
multi_region_thread_allocator_proc :: proc(
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
	when THREAD {
		m := (^Thread_Allocator)(allocator_data)
		size := size * m.barrier.thread_count
		rng := range(size)
		result, err := single_region_thread_allocator_proc(
			allocator_data,
			mode,
			size,
			alignment,
			old_memory,
			old_size,
			loc,
		)
		#partial switch mode {
		case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
			return result[rng[0]:rng[1]], err
		case:
			return result, err
		}
	} else {
		m := (^Thread_Allocator)(allocator_data)
		return m.backing.procedure(
			m.backing.data,
			mode,
			size,
			alignment,
			old_memory,
			old_size,
			loc,
		)
	}
}

// Allocates shared memory, where each thread receives the same memory region
single_region_thread_allocator_proc :: proc(
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
	when THREAD {
		@(static) result: []byte
		@(static) err: mem.Allocator_Error
		m := (^Thread_Allocator)(allocator_data)

		// This barrier prevents overwriting result
		// after subsequent calls
		sync.barrier_wait(m.barrier)

		if !is_leader(m.leader_id) {
			// when ODIN_DEBUG {
			// 	log.debugf("waits")
			// }
			sync.barrier_wait(m.barrier)
			return result, err
		}

		#partial switch mode {
		case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
			// when ODIN_DEBUG {
			// 	log.debugf(">>> allocate %d bytes", size)
			// }
			result, err = m.backing.procedure(
				m.backing.data,
				mode,
				size,
				alignment,
				old_memory,
				old_size,
				loc,
			)
			sync.barrier_wait(m.barrier)
			return result, err
		case .Free:
			// when ODIN_DEBUG {
			// 	log.debugf(">>> free")
			// }
			fallthrough
		case:
			result, err = m.backing.procedure(
				m.backing.data,
				mode,
				size,
				alignment,
				old_memory,
				old_size,
				loc,
			)
			sync.barrier_wait(m.barrier)
			return result, err
		}
		result, err = nil, nil
		sync.barrier_wait(m.barrier)
		return result, err
	} else {
		m := (^Thread_Allocator)(allocator_data)
		return m.backing.procedure(
			m.backing.data,
			mode,
			size,
			alignment,
			old_memory,
			old_size,
			loc,
		)
	}
}
