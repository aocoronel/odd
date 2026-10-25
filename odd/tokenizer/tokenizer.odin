package tokenizer

import "core:fmt"
import "core:unicode"

Tokenizer :: struct {
	pos:  int,
	buff: string,
	tok:  Token,
}

Token :: struct {
	text: string,
	kind: Token_Kind,
}

Token_Kind :: enum {
	EOF = 0,
	Text, // not alphanumeric
	Integer,
	Comma,
}

scan :: proc(s: ^Tokenizer) -> Token {
	s.pos = skip_whitespace(s.buff, s.pos)
	if s.pos >= len(s.buff) do return {kind = .EOF}
	c := cast(rune)s.buff[s.pos]

	if c == ',' {
		s.pos += 1
		s.tok = {
			text = ",",
			kind = .Comma,
		}
		return s.tok
	}

	_scan :: proc(s: ^Tokenizer, c: rune, kind: Token_Kind, is: proc(r: rune) -> bool) -> Token {
		size: int
		for i in s.pos ..< len(s.buff) {
			c := cast(rune)s.buff[i]
			if !is(c) {
				break
			}
			size += 1
		}
		s.pos += size
		s.tok = {
			text = s.buff[s.pos - size:s.pos],
			kind = kind,
		}
		return s.tok
	}

	if unicode.is_letter(c) do return _scan(s, c, .Text, unicode.is_letter)
	if unicode.is_digit(c) do return _scan(s, c, .Integer, unicode.is_digit)

	fmt.panicf("illegal rune: %c", c)
}

skip_whitespace :: proc(input: string, i: int) -> int {
	i := i
	for i < len(input) && unicode.is_space(rune(input[i])) {
		i += 1
	}
	return i
}
