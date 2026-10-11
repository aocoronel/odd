#+build freebsd
package term

import "core:c"
import "core:sys/freebsd"

_terminal_size :: proc() -> (width: int, height: int) {
	TIOCGWINSZ :: 0x40087468
	STDOUT_FILENO :: 1
	winsize :: struct {
		row, col, xpixel, ypixel: c.short,
	}

	w: winsize

	ok, _ := freebsd.ioctl(STDOUT_FILENO, TIOCGWINSZ, cast(uintptr)&w)

	if ok == -1 || w.col == 0 {
		w.col = 80
	}

	return cast(int)w.cols, cast(int)w.rows
}
