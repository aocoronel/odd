package term

import "core:fmt"
import "core:strings"

print :: fmt.print

_indent :: #force_inline proc(i: int) -> (pos: int) {
	print(strings.repeat(" ", i))
	return i
}

/*
Prints the message with provided indentation.

This procedure will wrap long messages to a newline, and keep up the indentation.

Returns: written bytes

Note: This procedure has been ported from aocoronel/aoclibs crown_iprint()
*/
iprint :: #force_inline proc(msg: string, indentation: int) -> int {
	return _iprint(msg, indentation, terminal_height())
}

/*
Prints the message with provided indentation.

This procedure will wrap long messages to a newline, and keep up the indentation.

Returns: written bytes

Note: This procedure was created to allow newlines in strings, without inserting those newlines.
*/
iprint_str :: #force_inline proc(msg: string, indentation: int) -> int {
	return _iprint_str(msg, indentation, terminal_height())
}

_iprint :: proc(msg: string, indentation, width: int) -> int {
	line_pos := _indent(indentation)

	i := 0
	n := len(msg)

	for i < n {
		r := msg[i]

		switch r {
		case '\n':
			print('\n')
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
			print('\n')
			line_pos = _indent(indentation)
		}

		// If indentation + word is more than what the width can represent, abort
		if line_pos + word_len > width {
			return i
		}

		print(msg[start:i])
		line_pos += word_len

		if i < n && line_pos < width {
			print(' ')
			line_pos += 1
		}
	}
	print('\n')
	return i
}

_iprint_str :: proc(msg: string, indentation, width: int) -> int {
	line_pos := _indent(indentation)

	i := 0
	n := len(msg)

	for i < n {
		r := msg[i]

		switch r {
		case '\n':
			i += 1
			if i < n && msg[i] == '\n' {
				print('\n')
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
			print('\n')
			line_pos = _indent(indentation)
		}

		if line_pos + word_len > width {
			return i
		}

		print(msg[start:i])
		line_pos += word_len

		if i < n && line_pos < width {
			print(' ')
			line_pos += 1
		}
	}
	print('\n')
	return i
}
