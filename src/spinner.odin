package odd

@(rodata)
SPINNER_SYMBOLS := []string{"⠁", "⠈", "⠐", "⠠", "⢀", "⡀", "⠄", "⠂"}

spinner :: proc() -> string {
	@(static) counter: int = 0
	ret := SPINNER_SYMBOLS[counter]
	counter = (counter + 1) % len(SPINNER_SYMBOLS)
	return ret
}
