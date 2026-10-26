#+build windows
package term

import "core:sys/windows"

_terminal_size :: proc "contextless" () -> (width: int, height: int) {
	csi := windows.CONSOLE_SCREEN_BUFFER_INFO
	ok := windows.GetConsoleScreenBufferInfo(windows.GetStdHandle(windows.STD_OUTPUT_HANDLE), &csi)
	cols := csi.srWindow.right - csi.srWindow.left + 1
	rows := csi.srWindow.bottom - csi.srWindow.top + 1
	return cast(int)cols, cast(int)rows
}
