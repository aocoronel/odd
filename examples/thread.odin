package example

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:os"
import odin_thread "core:thread"
import thread "shared:odd/thread"
import easy_thread "shared:odd/thread/easy"

thread :: proc() {
	context.logger = log.create_console_logger(
		log.Level.Debug,
		opt = {.Level, .Terminal_Color, .Thread_Id, .Short_File_Path, .Line},
	)
	defer log.destroy_console_logger(context.logger)

	pool, err := easy_thread.init(context_name = "pool1")
	if err != nil {
		log.error(err)
		return
	}

	pool2, err2 := easy_thread.init(context_name = "pool2")
	if err2 != nil {
		log.error(err2)
		return
	}

	sum: int
	// &sum is shared data, that all threads can read and write
	// Tasks will use the context.temp_allocator by default, otherwise
	// use destroy_task() to cleanup
	_ = easy_thread.add_task(pool, bar, &sum)

	arr := []string{"foo", "bar", "baz"}
	easy_thread.add_task(pool, baz, &arr)

	easy_thread.add_task(pool2, foo, pool)

	// Wait all tasks to finish, and clear queue
	thread.wait(pool2, pool)
	thread.reset(pool2, pool)

	// Add more tasks
	easy_thread.add_task(pool, baz, &arr)

	// Recursion + Work stealing
	recursion_example(pool)

	// Wait all tasks to finish, and join threads

	thread.join(pool2, pool)

	s_sum: int
	for i in 0 ..< os.get_processor_core_count() {
		s_sum += i
	}
	fmt.println("SUM:", sum)
	assert(sum == s_sum)
}

foo :: proc(t: ^easy_thread.Task) {
	pool := (cast(^thread.Pool)t.data[0])
	arr := make([]string, 3)
	arr[0] = "foo-foo"; arr[1] = "foo-bar"; arr[2] = "foo-baz"
	a := new([]string)
	a^ = arr
	// Each thread will add a task
	easy_thread.add_task(pool, baz, a)
}

bar :: proc(t: ^easy_thread.Task) {
	out := (cast(^int)t.data[0])
	intrinsics.atomic_add_explicit(out, thread.current_thread_id, .Relaxed)
}

baz :: proc(t: ^easy_thread.Task) {
	arr := (cast(^[]string)t.data[0])^
	// thread.range requires all threads from the context to be present
	// If one thread fails for whatever reason, the work is incomplete
	rng := thread.range(len(arr))
	// All threads wil get here, but not all of them may print this
	for i in rng[0] ..< rng[1] {
		fmt.printfln("baz[%d]: %s", thread.current_thread_id, arr[i])
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
	easy_thread.add_task(pool, rc_thread, files_ptr, new(int))
}

// Print all files in directory, recursively
rc_thread :: proc(t: ^easy_thread.Task) {
	files := cast(^[]os.File_Info)t.data[0]
	tasks := cast(^int)t.data[1]

	name, _ := odin_thread.get_name()

	// thread.next does NOT requires all threads from the context to be present
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
			rc(thread.get_context_pool(), fs)
		} else {
			fmt.println(name, f.fullpath)
		}
	}
}
