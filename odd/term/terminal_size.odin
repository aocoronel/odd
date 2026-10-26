package term

terminal_size :: proc "contextless" () -> (width: int, height: int) {
	return _terminal_size()
}

terminal_width :: proc "contextless" () -> int {
	w, _ := _terminal_size()
	return w
}

terminal_height :: proc "contextless" () -> int {
	_, h := _terminal_size()
	return h
}
