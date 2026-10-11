package term

terminal_size :: proc() -> (width: int, height: int) {
	return _terminal_size()
}
