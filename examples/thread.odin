package example

import "base:intrinsics"
import "core:fmt"
import "core:os"
import "core:thread"
import "core:time"
import "shared:odd/debug"
import othread "shared:odd/thread"
import ethread "shared:odd/thread/easy"

/*
This shows how to use the thread/easy API

This has many comments, because the library actually does very little for you.
*/
thread :: proc() {
	debug.register_backtrace()

	start, end: time.Time

	pool, pool2: ^othread.Pool
	defer othread.destroy(pool, pool2)

	start = time.now()
	{
		err: os.Error
		// The main thread context is passed to the threads
		pool, err = ethread.init(8, context_name = "pool1")
		if err != nil { return }
		pool2, err = ethread.init(8, context_name = "pool2")
		if err != nil { return }
	}
	end = time.now()
	fmt.println("Initialization took:", time.diff(start, end))

	start = time.now()
	{
		// &sum is shared data, that all threads can read and write
		sum: int

		// add_command will use the context.temp_allocator by default, otherwise
		// use destroy_command() to cleanup
		//
		// Commands are executed as soon as they are submited
		// All threads will attempt to run the command
		// Fast threads will steal the command from another thread
		_ = ethread.add_command(pool, bar, &sum)

		// Main thread waits on the "pool"
		// This blocks
		othread.wait(pool)

		assert(intrinsics.atomic_load(&sum) == 28)
	}
	end = time.now()
	fmt.println("bar() took:", time.diff(start, end))

	start = time.now()
	{
		// baz will print all the elements from the array once
		arr := []string{"foo", "bar", "baz"}
		ethread.add_command(pool, baz, &arr)

		// While the main thread added the "baz" command to the "pool"
		// We also add the "foo" command to the "pool2", and this one
		// will add tasks to the "pool", while "baz" may still be running
		// Commands will be executed in the order they were submited, so
		// "foo" commands will only run after "baz", but it doesn't mean the main
		// thread is waiting
		ethread.add_command(pool2, foo, pool)

		// Now the main thread is waiting. Here we wait on the "pool2",
		// then on "pool"
		// Alternatively, each add_command returns the command itself, which
		// we can wait specifically in a command to finish with wait_command()
		// The ordering is important, and only the user knows the right ordering
		// The wrong order will deadlock.
		othread.wait(pool2, pool)
	}
	end = time.now()
	fmt.println("baz and foo() took:", time.diff(start, end))

	// Here the reset() usage is fine, because all pools are waiting
	// Another fine use, is if a pool doesn't depend on another pool,
	// then we can just add the reset command at any point
	start = time.now()
	ethread.reset(pool2)
	ethread.reset(pool)
	end = time.now()
	fmt.println("reset() took:", time.diff(start, end))

	// Recursion + user granular work stealing
	{
		dir := "odd"

		// Has to be ran from root of this project
		if !os.exists(dir) {
			othread.join(pool2, pool)
			return
		}

		if files, err := os.read_all_directory_by_path(dir, context.allocator); err != nil {
			return
		} else {
			start = time.now()
			rc(pool, files, pool2)
		}
		othread.wait(pool2, pool)
	}
	end = time.now()
	fmt.println("Recursion took:", time.diff(start, end))

	// Wait all commands to finish, and join threads.
	// The pool cannot be reused
	othread.join(pool2, pool)
}

foo :: proc(args: []rawptr) {
	pool := (cast(^othread.Pool)args[0])
	arr := make([]string, 3)
	arr[0] = "foo-foo"; arr[1] = "foo-bar"; arr[2] = "foo-baz"
	a := new([]string)
	a^ = arr
	// Each thread will add a command, so the array will be printed
	// many times
	ethread.add_command(pool, baz, a)
}

bar :: proc(args: []rawptr) {
	out := (cast(^int)args[0])
	intrinsics.atomic_add_explicit(out, context.user_index, .Relaxed)
}

baz :: proc(args: []rawptr) {
	arr := (cast(^[]string)args[0])^
	rng := othread.range(context.user_index, len(arr))
	// Not all threads will print this
	for i in rng[0] ..< rng[1] {
		fmt.printfln("baz[%d]: %s", i, arr[i])
	}
}

// A small wrapper to rc_thread, for type safety
rc :: proc(
	pool: ^othread.Pool,
	files: []os.File_Info,
	pool2: ^othread.Pool,
	allocator := context.temp_allocator,
) {
	context.allocator = allocator
	files_ptr := new([]os.File_Info)
	files_ptr^ = files
	ethread.add_command(pool, rc_thread, files_ptr, new(int), pool2)
}

// Print all files in directory, recursively
rc_thread :: proc(args: []rawptr) {
	files := cast(^[]os.File_Info)args[0]
	commands := cast(^int)args[1]
	pool := cast(^othread.Pool)args[2]

	name, _ := thread.get_name()

	for i in othread.next(commands, len(files)) {
		f := files[i]
		if f.type == .Directory {
			fs, err := os.read_directory_by_path(f.fullpath, -1, context.temp_allocator)
			if err != nil {
				continue
			}
			// This is unnecessary, and only to show that commands can be added
			// to different pools
			is_odd := (i % 2) > 0
			if is_odd {
				rc(pool, fs, pool)
			} else {
				rc(othread.get_context_pool(), fs, pool)
			}
		} else {
			fmt.println(name, f.fullpath)
		}
	}
}

// Unfortunately, the example above isn't faster than this:
_thread :: proc() {
	dir := "odd"

	// Has to be ran from root of this project
	if !os.exists(dir) {
		return
	}

	start, end: time.Time
	if files, err := os.read_all_directory_by_path(dir, context.allocator); err != nil {
		return
	} else {
		start = time.now()
		_rc(files)
	}
	end = time.now()
	fmt.println("Recursion took:", time.diff(start, end))
}

_rc :: proc(files: []os.File_Info) {
	for i in 0 ..< len(files) {
		f := files[i]
		if f.type == .Directory {
			fs, err := os.read_directory_by_path(f.fullpath, -1, context.temp_allocator)
			if err != nil {
				continue
			}
			_rc(fs)
		} else {
			fmt.println(f.fullpath)
		}
	}
}
