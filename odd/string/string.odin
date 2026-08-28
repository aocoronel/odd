package string

import "core:strings"
import "core:testing"

skip_whitespace_forward :: proc(s: []byte) -> uint {
	start: uint = 0

	for start < len(s) && strings.is_space(rune(s[start])) {
		start += 1
	}

	return start
}

skip_whitespace_backward :: proc(s: []byte) -> uint {
	end: uint = len(s)

	for end > 0 && strings.is_space(rune(s[end - 1])) {
		end -= 1
	}

	return end
}

trim :: proc(s: []byte) -> []byte {
	start := skip_whitespace_forward(s)

	if start == len(s) {
		return nil
	}

	end := skip_whitespace_backward(s)

	return s[start:end]
}

// Returns the line contents in "word", and next lines to "rest"
// The slice returned to "word" is exclusive from the newline delimiter
next_line :: proc(s: []byte) -> (word: []byte, rest: []byte) {
	newline := strings.index_byte(string(s), '\n')
	if newline == -1 {
		return
	}

	word = s[0:newline]
	rest = s[newline + 1:]

	return
}

next_word :: proc(s: []byte) -> (word: []byte, rest: []byte) {
	start := skip_whitespace_forward(s)

	if start == len(s) {
		return nil, nil
	}

	end := start

	for end < len(s) && !strings.is_space(rune(s[end])) {
		end += 1
	}

	word = s[start:end]
	rest = s[end:]
	return
}

substring_end :: proc(s: []byte) -> (length: uint, ok: bool) {
	if len(s) == 0 || s[0] != '"' {
		return 0, false
	}

	for i: uint = 1; i < uint(len(s)); i += 1 {
		if s[i] == '\\' {
			if i + 1 < uint(len(s)) {
				i += 1
			}
		} else if s[i] == '"' {
			return i + 1, true
		}
	}

	return 0, false
}

parse_word :: proc(s: []byte) -> (word: []byte, rest: []byte) {
	start := skip_whitespace_forward(s)

	if start == len(s) {
		return
	}

	is_string := s[start] == '"'

	if is_string {
		string_end, ok := substring_end(s[start:])
		if !ok {
			return nil, nil
		}
		assert(s[string_end] == '"')
		word = s[start:start + string_end]
		rest = s[start + string_end:]
		return
	} else {
		// fallback to what next_word() do
		end := start
		for end < len(s) && !strings.is_space(rune(s[end])) {
			end += 1
		}

		word = s[start:end]
		rest = s[end:]
		return
	}
}

@(test)
next_word_test :: proc(t: ^testing.T) {
	data: strings.Builder
	defer strings.builder_destroy(&data)
	strings.write_string(&data, "hello, world")

	word, rest: []byte
	rest = data.buf[:]

	i := 0
	for word, rest = next_word(rest); rest != nil; word, rest = next_word(rest) {
		if i == 0 {
			assert(strings.compare("hello,", string(word)) == 0)
		} else if i == 1 {
			assert(strings.compare("world", string(word)) == 0)
		}
		assert(i < 2)
		i += 1
	}
}

@(test)
parse_word_test :: proc(t: ^testing.T) {
	data: strings.Builder
	defer strings.builder_destroy(&data)
	strings.write_string(&data, "hello, \"world \'e\'\" !")

	word, rest: []byte
	rest = data.buf[:]

	i := 0
	for word, rest = parse_word(rest); rest != nil; word, rest = parse_word(rest) {
		if i == 0 {
			assert(strings.compare("hello,", string(word)) == 0)
		} else if i == 1 {
			assert(strings.compare("\"world \'e\'\"", string(word)) == 0)

		} else if i == 2 {
			assert(strings.compare("!", string(word)) == 0)
		}
		assert(i < 3)
		i += 1
	}
}

@(test)
next_line_test :: proc(t: ^testing.T) {
	data: strings.Builder
	defer strings.builder_destroy(&data)
	strings.write_string(&data, "hello, \"world \'e\'\" !\nhi\n")

	word, rest: []byte
	rest = data.buf[:]

	word, rest = next_line(rest)
	assert(strings.compare("hello, \"world \'e\'\" !", string(word)) == 0)

	word, rest = next_line(rest)
	assert(strings.compare("hi", string(word)) == 0)

	word, rest = next_line(rest)
	assert(rest == nil)
}
