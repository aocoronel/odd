package odd_thread_sema

import "base:intrinsics"
import "core:sync"
import vg "core:sys/valgrind"

/*
Posts and waits to all threads
*/

Sema :: struct {
	generation: sync.Futex,
}

@(synchronizes = .Release)
post :: proc "contextless" (s: ^Sema, count: uint = 1) {
	when ODIN_VALGRIND_SUPPORT {
		vg.helgrind_sem_post_pre(s)
	}

	intrinsics.atomic_add_explicit(&s.generation, sync.Futex(count), .Release)

	sync.futex_broadcast(&s.generation)
}

@(synchronizes = .Acquire)
wait :: proc "contextless" (s: ^Sema, last_generation: ^sync.Futex) {
	for {
		current := intrinsics.atomic_load_explicit(&s.generation, .Acquire)

		if current != last_generation^ {
			when ODIN_VALGRIND_SUPPORT {
				vg.helgrind_sem_wait_post(s)
			}
			last_generation^ += 1
			return
		}

		sync.futex_wait(&s.generation, u32(current))
	}
}
