#+feature using-stmt

package example

import "core:fmt"
import "core:log"
import "core:mem"
import "shared:odd/pipe"

sh :: pipe.run_command
Pipe :: pipe.Pipe

pipe :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	p: Pipe
	using p

	defer pipe.destroy(&p)

	if sh({"ls"}) do sh({"ls"})

	if sh({"echo", ".emacs.d"}, &p) {
		if sh({"ls", stdout}, &p) {
			fmt.println(stdout)
		}
	}
}
