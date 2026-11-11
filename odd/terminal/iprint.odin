package odd_terminal

import "core:fmt"
import "core:os"

print :: fmt.fprint

_indent :: #force_inline proc(indent: int, file: ^os.File) -> (pos: int) {
	buff: [32]u8
	for i in 0 ..< 32 do buff[i] = ' '
	print(file, string(buff[:min(indent, 32)]))
	return min(indent, 32)
}

/*
Prints the message with provided indentation.

This procedure will wrap long messages to a newline, and keep up the indentation.

Returns: written bytes

Note: This procedure has been ported from aocoronel/aoclibs crown_iprint()
*/
iprint :: #force_inline proc(msg: string, indentation: int, file := os.stderr) -> int {
	return _iprint(msg, indentation, terminal_height(), file)
}

/*
Prints the message with provided indentation.

This procedure will wrap long messages to a newline, and keep up the indentation.

Returns: written bytes

Note: This procedure was created to allow newlines in strings, without inserting those newlines.
*/
iprint_str :: #force_inline proc(msg: string, indentation: int, file := os.stderr) -> int {
	return _iprint_str(msg, indentation, terminal_height(), file)
}

_iprint :: proc(msg: string, indentation, width: int, file := os.stderr) -> int {
	line_pos := _indent(indentation, file)

	i := 0
	n := len(msg)

	for i < n {
		r := msg[i]

		switch r {
		case '\n':
			print(file, '\n')
			line_pos = _indent(indentation, file)
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
			print(file, '\n')
			line_pos = _indent(indentation, file)
		}

		// If indentation + word is more than what the width can represent, abort
		if line_pos + word_len > width {
			return i
		}

		print(file, msg[start:i])
		line_pos += word_len

		if i < n && line_pos < width {
			print(file, ' ')
			line_pos += 1
		}
	}
	print(file, '\n')
	return i
}

_iprint_str :: proc(msg: string, indentation, width: int, file := os.stderr) -> int {
	line_pos := _indent(indentation, file)

	i := 0
	n := len(msg)

	for i < n {
		r := msg[i]

		switch r {
		case '\n':
			i += 1
			if i < n && msg[i] == '\n' {
				print(file, '\n')
				line_pos = _indent(indentation, file)
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
			print(file, '\n')
			line_pos = _indent(indentation, file)
		}

		if line_pos + word_len > width {
			return i
		}

		print(file, msg[start:i])
		line_pos += word_len

		if i < n && line_pos < width {
			print(file, ' ')
			line_pos += 1
		}
	}
	print(file, '\n')
	return i
}
