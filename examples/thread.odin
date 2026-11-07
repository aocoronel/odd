package example

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:os"
import "shared:odd/thread"

thread :: proc() {
	context.logger = log.create_console_logger(
		log.Level.Debug,
		opt = {.Level, .Terminal_Color, .Thread_Id},
	)
	defer log.destroy_console_logger(context.logger)

	pool, err := thread.init()
	if err != nil {
		log.error(err)
		return
	}

	sum: int
	// &sum is shared data, that all threads can read and write
	// Tasks will use the context.temp_allocator by default, otherwise
	// use destroy_task() to cleanup
	_ = thread.add_task(pool, bar, &sum)

	arr := []string{"foo", "bar", "baz"}
	// thread.add_task(pool, baz, &
	// Wait all tasks to finish, and clear queue
	thread.wait_task(pool)

	// Add more tasks
	thread.add_task(pool, baz, &arr)

	// Recursion + Work stealing
	recursion_example(pool)

	// Wait all tasks to finish, and join threads
	thread.join(pool)

	fmt.println("SUM:", sum) // if 8 threads -> 28
}

bar :: proc(t: ^thread.Task) {
	out := (cast(^int)t.data[0])
	intrinsics.atomic_add_explicit(out, thread.thread_id(), .Seq_Cst)
}

baz :: proc(t: ^thread.Task) {
	arr := (cast(^[]string)t.data[0])^
	// thread.range requires all threads from the context to be present
	// If one thread fails for whatever reason, the work is incomplete
	rng := thread.range(len(arr))
	// All threads wil get here, but not all of them may print this
	for i in rng[0] ..< rng[1] {
		fmt.printfln("baz[%d]: %s", thread.thread_id(), arr[i])
	}
}

recursion_example :: proc(pool: ^thread.Pool) {
	dir := "odd"

	// Has to be ran from root of this project
	if !os.exists(dir) do return

	files, err := os.read_all_directory_by_path(dir, context.allocator)
	if err != nil {
		log.errorf("%s: %s", dir, os.error_string(err))
		return
	}

	rc(pool, files)
}

// A small wrapper to rc_thread, for type safety
rc :: proc(pool: ^thread.Pool, files: []os.File_Info, allocator := context.temp_allocator) {
	context.allocator = allocator
	files_ptr := new([]os.File_Info)
	files_ptr^ = files
	thread.add_task(pool, rc_thread, files_ptr, new(int))
}

// Print all files in directory, recursively
rc_thread :: proc(t: ^thread.Task) {
	files := cast(^[]os.File_Info)t.data[0]
	tasks := cast(^int)t.data[1]

	// thread.range does NOT requires all threads from the context to be present
	// If one thread fails for whatever reason, other threads might still complete this
	// It's a "might", because threads allocate memory to add a new task
	for i in thread.next(tasks, len(files)) {
		f := files[i]
		if f.type == .Directory {
			fs, err := os.read_directory_by_path(f.fullpath, -1, context.temp_allocator)
			if err != nil {
				log.error(os.error_string(err))
				continue
			}
			rc(thread.CONTEXT_POOL, fs)
		} else {
			fmt.println(f.fullpath)
		}
	}
}
