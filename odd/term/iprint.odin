package term

import "base:runtime"

print_string :: runtime.print_string
print_rune :: runtime.print_rune

_indent :: #force_inline proc "contextless" (i: int) -> (pos: int) {
	buff: [32]u8
	for i in 0 ..< 32 do buff[i] = ' '
	print_string(string(buff[:i]))
	return i
}

/*
Prints the message with provided indentation.

This procedure will wrap long messages to a newline, and keep up the indentation.

Returns: written bytes

Note: This procedure has been ported from aocoronel/aoclibs crown_iprint()
*/
iprint :: #force_inline proc "contextless" (msg: string, indentation: int) -> int {
	return _iprint(msg, indentation, terminal_height())
}

/*
Prints the message with provided indentation.

This procedure will wrap long messages to a newline, and keep up the indentation.

Returns: written bytes

Note: This procedure was created to allow newlines in strings, without inserting those newlines.
*/
iprint_str :: #force_inline proc "contextless" (msg: string, indentation: int) -> int {
	return _iprint_str(msg, indentation, terminal_height())
}

_iprint :: proc "contextless" (msg: string, indentation, width: int) -> int {
	line_pos := _indent(indentation)

	i := 0
	n := len(msg)

	for i < n {
		r := msg[i]

		switch r {
		case '\n':
			print_rune('\n')
			line_pos = _indent(indentation)
			i += 1
			continue
		case ' ', '\t':
			i += 1
			continue
		}

		start := i
		for i < n && msg[i] != ' ' && msg[i] != '\t' && msg[i] != '\n' {
			i += 1
		}
		word_len := i - start

		if line_pos + word_len > width && line_pos > indentation {
			print_rune('\n')
			line_pos = _indent(indentation)
		}

		// If indentation + word is more than what the width can represent, abort
		if line_pos + word_len > width {
			return i
		}

		print_string(msg[start:i])
		line_pos += word_len

		if i < n && line_pos < width {
			print_rune(' ')
			line_pos += 1
		}
	}
	print_rune('\n')
	return i
}

_iprint_str :: proc "contextless" (msg: string, indentation, width: int) -> int {
	line_pos := _indent(indentation)

	i := 0
	n := len(msg)

	for i < n {
		r := msg[i]

		switch r {
		case '\n':
			i += 1
			if i < n && msg[i] == '\n' {
				print_rune('\n')
				line_pos = _indent(indentation)
				i += 1
			}
			continue
		case ' ', '\t':
			i += 1
			continue
		}

		start := i
		for i < n && msg[i] != ' ' && msg[i] != '\t' && msg[i] != '\n' {
			i += 1
		}
		word_len := i - start

		if line_pos + word_len > width && line_pos > indentation {
			print_rune('\n')
			line_pos = _indent(indentation)
		}

		if line_pos + word_len > width {
			return i
		}

		print_string(msg[start:i])
		line_pos += word_len

		if i < n && line_pos < width {
			print_rune(' ')
			line_pos += 1
		}
	}
	print_rune('\n')
	return i
}
