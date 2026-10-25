package term

terminal_size :: proc() -> (width: int, height: int) {
	return _terminal_size()
}

terminal_width :: proc() -> int {
	w, _ := _terminal_size()
	return w
}

terminal_height :: proc() -> int {
	_, h := _terminal_size()
	return h
}
