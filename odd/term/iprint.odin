package term

import "core:fmt"
import "core:strings"

/*
Prints the message with provided indentation.

This procedure will wrap long messages to a newline, and keep up the indentation.

Note: This procedure has been ported from aocoronel/aoclibs crown_iprint()
*/
iprint :: proc(msg: string, indent: int) {
	width, _ := terminal_size()

	fmt.print(strings.repeat(" ", indent))
	line_pos := indent

	i := 0
	n := len(msg)

	for i < n {
		r := msg[i]

		if r == '\n' {
			fmt.print('\n')
			fmt.print(strings.repeat(" ", indent))
			line_pos = indent
			i += 1
			continue
		}

		if r == ' ' || r == '\t' {
			i += 1
			continue
		}

		start := i
		for i < n && msg[i] != ' ' && msg[i] != '\t' && msg[i] != '\n' {
			i += 1
		}
		word_len := i - start

		if line_pos + word_len > width && line_pos > indent {
			fmt.print('\n')
			fmt.print(strings.repeat(" ", indent))
			line_pos = indent
		}

		fmt.print(msg[start:i])
		line_pos += word_len

		if i < n && line_pos < width {
			fmt.print(' ')
			line_pos += 1
		}
	}
	fmt.print(' ')
}
