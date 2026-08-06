package odd

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:sync"

// Thread Allocator
//
// Differently from mem.Mutex_Allocator, which just puts a mutex between allocator calls, this one
// performs a single call per thread group, allocating enough memory for all threads and dispatching
// the different regions of the same buffer to each thread.
//
// Inspired by:
// https://www.dgtlgrove.com/p/multi-core-by-default
// https://codeberg.org/aocoronel/aoclibs/src/branch/main/src/thread.c
// https://github.com/aocoronel/multicore

THREAD :: #config(THREAD, false)

// Assume modern computers can't go more than 64 CPUs
MAX_THREAD_COUNT :: #config(MAX_THREAD_COUNT, 64)

@(thread_local)
@(private)
ID: int

@(private)
COUNT: int

Thread_Allocator :: struct {
	backing:      mem.Allocator,
	barrier:      sync.Barrier,
	thread_count: int,
	leader_id:    int,
}

Range :: struct {
	begin, end: int,
}

get_id :: proc() -> int {
	when THREAD {
		return ID
	} else {
		return 0
	}
}

barrier_wait :: proc(barrier: ^sync.Barrier) {
	when THREAD {
		sync.barrier_wait(barrier)
	}
}

get_count :: proc() -> int {
	when THREAD {
		return COUNT
	} else {
		return 1
	}
}

set_id :: proc(id: int) {
	when THREAD {
		ID = id
	}
}

set_count :: proc(count: int) {
	when THREAD {
		COUNT = count
	}
}

range :: proc(count: int) -> Range {
	when THREAD {
		id := get_id()
		thread_count := get_count()
		values_per_thread := count / thread_count
		leftover_values_count := count % thread_count
		thread_has_leftover: bool = id < leftover_values_count
		leftovers_before_this_thread_idx := thread_has_leftover ? id : leftover_values_count
		thread_first_value_idx := values_per_thread * id + leftovers_before_this_thread_idx
		thread_opl_value_idx :=
			thread_first_value_idx + values_per_thread + int(thread_has_leftover)
		return Range{thread_first_value_idx, thread_opl_value_idx}
	} else {
		return Range{0, count}
	}
}

is_leader :: proc(ctx: ^Thread_Allocator) -> bool {
	when THREAD {
		return ctx.leader_id == get_id()
	} else {
		return true
	}
}

thread_init :: proc(
	ctx: ^Thread_Allocator,
	thread_count, leader_id: int,
	allocator: mem.Allocator,
) {
	ctx.backing = allocator
	ctx.thread_count = thread_count
	ctx.leader_id = leader_id
	sync.barrier_init(&ctx.barrier, thread_count)
}

multi_buffer_thread_allocator :: proc(ctx: ^Thread_Allocator) -> mem.Allocator {
	when THREAD {
		return mem.Allocator{procedure = multi_buffer_thread_allocator_proc, data = ctx}
	} else {
		return mem.Allocator{procedure = ctx.backing.procedure, data = ctx.backing.data}
	}
}

single_buffer_thread_allocator :: proc(ctx: ^Thread_Allocator) -> mem.Allocator {
	when THREAD {
		return mem.Allocator{procedure = single_buffer_thread_allocator_proc, data = ctx}
	} else {
		return mem.Allocator{procedure = ctx.backing.procedure, data = ctx.backing.data}
	}
}

// Allocates shared memory, where each thread receives their own unique memory region
multi_buffer_thread_allocator_proc :: proc(
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
	m := (^Thread_Allocator)(allocator_data)
	size := size * m.thread_count
	rng := range(size)
	result, err := single_buffer_thread_allocator_proc(
		allocator_data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		loc,
	)
	#partial switch mode {
	case .Alloc:
		fallthrough
	case .Alloc_Non_Zeroed:
		fallthrough
	case .Resize:
		fallthrough
	case .Resize_Non_Zeroed:
		return result[rng.begin:rng.end], err
	case:
		return result, err
	}
}

// Allocates shared memory, where each thread receives the same memory region
single_buffer_thread_allocator_proc :: proc(
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
	@(static) result: []byte
	@(static) err: mem.Allocator_Error
	m := (^Thread_Allocator)(allocator_data)

	id := get_id()

	sync.barrier_wait(&m.barrier)

	if !is_leader(m) {
		when ODIN_DEBUG {
			log.debugf(">> [%d] wait", id)
		}
		sync.barrier_wait(&m.barrier)
		ptr := result
		return ptr, err
	}

	#partial switch mode {
	case .Alloc:
		fallthrough
	case .Alloc_Non_Zeroed:
		fallthrough
	case .Resize:
		fallthrough
	case .Resize_Non_Zeroed:
		when ODIN_DEBUG {
			log.debugf("[ALLOC][%d][%d bytes]", id, size)
		}
		result, err = m.backing.procedure(
			m.backing.data,
			mode,
			size,
			alignment,
			old_memory,
			old_size,
			loc,
		)
		sync.barrier_wait(&m.barrier)
		ptr := result
		return ptr, err
	case:
		when ODIN_DEBUG {
			log.debugf("[FREE][%d]", id)
		}
		result, err = m.backing.procedure(
			m.backing.data,
			mode,
			size,
			alignment,
			old_memory,
			old_size,
			loc,
		)
		sync.barrier_wait(&m.barrier)
		ptr := result
		return ptr, err
	}
	result, err = nil, nil
	sync.barrier_wait(&m.barrier)
	ptr := result
	return ptr, err
}
