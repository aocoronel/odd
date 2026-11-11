package example
import "core:sync"
import "shared:odd/debug"

import "base:intrinsics"
import "core:fmt"
import "core:os"
import "core:thread"
import othread "shared:odd/thread"
import ethread "shared:odd/thread/easy"

Data :: struct {
	strings:          []string,
	toggle1, toggle2: bool,
}

_thread :: proc() {
	{
		t1 := thread.create(_foo)
		if t1 == nil do return

		t2 := thread.create(_bar)
		if t2 == nil do return

		data: Data

		t1.data = &data
		t2.data = &data

		thread.start(t1)
		thread.start(t2)

		for data.toggle1 == false {
			thread.yield()
		}
		thread.yield()

		data.toggle2 = true

		thread.join(t1)
		thread.join(t2)

		fmt.println(data.strings)
	}
}

_foo :: proc(t: ^thread.Thread) {
	data := (cast(^Data)t.data)
	memory := make([]string, 50)
	data.strings = memory
	data.toggle1 = true

	thread.terminate(t, 1)
}

_bar :: proc(t: ^thread.Thread) {
	data := (cast(^Data)t.data)
	for data.toggle2 == false {
		thread.yield()
	}

	data.strings[0] = "foo"
}

thread :: proc() {
	debug.register_backtrace()
	// Initializing pools
	// It's verbose, indeed. But you have many choices, and that's the point,
	// since threadding isn't a recipe, like many other computer science problems
	pool, pool2: ^othread.Pool
	defer othread.destroy(pool, pool2)

	{
		err: os.Error
		pool, err = othread.create_pool()
		if err != nil { return }
		pool2, err = othread.create_pool()
		if err != nil { return }
	}

	b1 := new(sync.Barrier)
	b2 := new(sync.Barrier)
	sync.barrier_init(b1, 8)
	sync.barrier_init(b2, 8)

	// The main thread context is passed to the threads
	if !othread.init(
		&pool.threads,
		pool,
		ethread.runner,
		config = {
			args = {b1, nil, nil, nil, nil, nil, nil, nil},
			pass_context = false,
			context_name = "pool1",
		},
	) { return }

	if !othread.init(
		&pool2.threads,
		pool2,
		ethread.runner,
		config = {
			args = {b2, nil, nil, nil, nil, nil, nil, nil},
			pass_context = false,
			context_name = "pool2",
		},
	) { return }

	{
		// &sum is shared data, that all threads can read and write
		sum: int

		// Commands will use the context.temp_allocator by default, otherwise
		// use destroy_command() to cleanup
		//
		// Commands are executed as soon as they are submited
		_ = ethread.add_command(pool, bar, &sum)

		// Main thread waits on the "pool"
		othread.wait(pool)

		// Calculate the sum in the main thread, so we can compare
		expected_sum: int
		for i in 0 ..< os.get_processor_core_count() {
			expected_sum += i
		}
		assert(sum == expected_sum)
	}

	{
		// baz will print all the elements from the array once
		// If your machine has >3 threads, ideally only three
		// threads will actually print, but all threads are
		// still going to run this command
		arr := []string{"foo", "bar", "baz"}
		ethread.add_command(pool, baz, &arr)

		// While the main thread added the "baz" command to the "pool"
		// We also add the "foo" command to the "pool2", and this one
		// will add tasks to the "pool", while "baz" may still be running
		// Commands will be executed in the order they were submited, so
		// "foo" will only run after "baz", but it doesn't mean the main
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

	// Here the reset() usage is fine, because all pools are waiting
	// Otherwise, it would be a catastrophe
	// othread.reset(pool2)
	// othread.reset(pool)

	// Recursion + user granular work stealing
	{
		dir := "odd"

		// Has to be ran from root of this project
		if !os.exists(dir) do return

		if files, err := os.read_all_directory_by_path(dir, context.allocator); err != nil {
			return
		} else {
			rc(pool, files)
		}
	}

	// Wait all commands to finish, and join threads.
	// The pool cannot be reused
	othread.join(pool2, pool)
}

foo :: proc(t: ^ethread.Command, _: int) {
	pool := (cast(^othread.Pool)t.data[0])
	arr := make([]string, 3)
	arr[0] = "foo-foo"; arr[1] = "foo-bar"; arr[2] = "foo-baz"
	a := new([]string)
	a^ = arr
	// Each thread will add a command, so the array will be printed
	// many times
	ethread.add_command(pool, baz, a)
}

bar :: proc(t: ^ethread.Command, i: int) {
	out := (cast(^int)t.data[0])
	intrinsics.atomic_add_explicit(out, i, .Relaxed)
}

baz :: proc(t: ^ethread.Command, idx: int) {
	arr := (cast(^[]string)t.data[0])^
	rng := othread.range(idx, len(arr))
	// All threads wil get here, but not all of them may print this
	for i in rng[0] ..< rng[1] {
		fmt.printfln("baz[%d]: %s", i, arr[i])
	}
}

// A small wrapper to rc_thread, for type safety
rc :: proc(pool: ^othread.Pool, files: []os.File_Info, allocator := context.temp_allocator) {
	context.allocator = allocator
	files_ptr := new([]os.File_Info)
	files_ptr^ = files
	ethread.add_command(pool, rc_thread, files_ptr, new(int))
}

// Print all files in directory, recursively
rc_thread :: proc(t: ^ethread.Command, _: int) {
	files := cast(^[]os.File_Info)t.data[0]
	commands := cast(^int)t.data[1]

	name, _ := thread.get_name()

	for i in othread.next(commands, len(files)) {
		f := files[i]
		if f.type == .Directory {
			fs, err := os.read_directory_by_path(f.fullpath, -1, context.temp_allocator)
			if err != nil {
				continue
			}
			rc(othread.get_context_pool(), fs)
		} else {
			fmt.println(name, f.fullpath)
		}
	}
}
