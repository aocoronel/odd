#+build darwin
package odd_term

import "core:c"
import "core:sys/darwin"

_terminal_size :: proc "contextless" () -> (width: int, height: int) {
	TIOCGWINSZ :: 0x40087468
	STDOUT_FILENO :: 1
	winsize :: struct {
		row, col, xpixel, ypixel: c.short,
	}

	w: winsize
	if darwin.syscall_ioctl(STDOUT_FILENO, TIOCGWINSZ, cast(uintptr)&w) == -1 || w.col == 0 {
		w.col = 80
	}

	return cast(int)w.col, cast(int)w.rows
}
