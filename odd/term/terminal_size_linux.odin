#+build linux
package term

import "core:c"
import "core:sys/linux"

_terminal_size :: proc() -> (width: int, height: int) {
	TIOCGWINSZ :: 0x5413
	STDOUT_FILENO :: 1

	winsize :: struct {
		row, col, xpixel, ypixel: c.short,
	}

	w: winsize
	if linux.ioctl(STDOUT_FILENO, TIOCGWINSZ, cast(uintptr)&w) == ~uintptr(0) || w.col == 0 {
		w.col = 80
	}
	return cast(int)w.col, cast(int)w.row
}
