package odd_tokenizer

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

scan :: proc(tkz: ^Tokenizer) -> Token {
	tok, pos := peek(tkz)
	tkz.pos = pos
	return tok
}

peek :: proc(s: ^Tokenizer) -> (Token, int) {
	pos := s.pos
	pos = skip_whitespace(s.buff, pos)
	if pos >= len(s.buff) do return {kind = .EOF}, pos
	c := cast(rune)s.buff[pos]

	if c == ',' {
		pos += 1
		s.tok = {
			text = ",",
			kind = .Comma,
		}
		return s.tok, pos
	}

	_scan :: proc(
		s: ^Tokenizer,
		c: rune,
		kind: Token_Kind,
		pos: int,
		is: proc(r: rune) -> bool,
	) -> (
		Token,
		int,
	) {
		pos := pos
		size: int
		for i in pos ..< len(s.buff) {
			c := cast(rune)s.buff[i]
			if !is(c) {
				break
			}
			size += 1
		}
		pos += size
		s.tok = {
			text = s.buff[pos - size:pos],
			kind = kind,
		}
		return s.tok, pos
	}

	if unicode.is_letter(c) do return _scan(s, c, .Text, pos, unicode.is_letter)
	if unicode.is_digit(c) do return _scan(s, c, .Integer, pos, unicode.is_digit)

	fmt.panicf("illegal rune: %c", c)
}

skip_whitespace :: proc(input: string, i: int) -> int {
	i := i
	for i < len(input) && unicode.is_space(rune(input[i])) {
		i += 1
	}
	return i
}
