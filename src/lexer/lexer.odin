package lexer

import "core:fmt"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

EOF: string : "EOF"
LPAREN: string : "("
RPAREN: string : ")"
LBRACKET: string : "["
RBRACKET: string : "]"
LBRACE: string : "{"
RBRACE: string : "}"
COMMA: string : ","
DOT: string : "."
SEMICOLON: string : ";"
COLON: string : ":"
QUESTIONMARK: string : ":"
APOSTROPHE: string : "\'"
QUOTE: string : "\""

Token_Kind :: enum {
	EOF,
	Identifier,
	Int,
	Float,
	String,
	Char,
	LParen,
	RParen,
	LBracket,
	RBracket,
	LBrace,
	RBrace,
	Comma,
	Semicolon,
	Dot,
	Colon,
	Question_Mark,
	Apostrophe,
	DoubleDot,
	Ellipsis,
	RArrow,
	Operator,
	Unknown,
}

Num_Base :: enum {
	Decimal,
	Hex,
	Octal,
	Binary,
}

String_Encoding :: enum {
	U8,
	U16,
	U32,
	Wide,
}

Num_Suffix :: enum {
	None,
	U,
	L,
	LL,
	UL,
	ULL,
	F,
	LF,
}

Operator :: enum {
	Eq, // =
	Not, // !
	Lt, // <
	Gt, // >
	Plus, // +
	Minus, // -
	Mul, // *
	Div, // /
	Xor, // ^
	And, // &
	Or, // |
	Modulo, // %
	Mask, // ~
	EqEq, // ==
	NotEq, // !=
	LtEq, // <=
	GtEq, // >=
	PlusEq, // +=
	MinusEq, // -=
	MulEq, // *=
	DivEq, // /=
	XorEq, // ^=
	ShlEq, // <<=
	ShrEq, // >>=
	AndEq, // &=
	OrEq, // |=
	ModuloEq, // %=
	PlusPlus, // ++
	MinusMinus, // --
	AndAnd, // &&
	OrOr, // ||
	Shl, // <<
	Shr, // >>
}

Source_Code_Location :: struct {
	line:     uint,
	column:   uint,
	filename: string,
}

Token_Int :: struct {
	base:   Num_Base,
	suffix: Num_Suffix,
	val:    uint,
}

Token_Float :: struct {
	base:   Num_Base,
	suffix: Num_Suffix,
	val:    f64,
}

Token_String :: struct {
	encode: String_Encoding,
}

Token_Char :: struct {
	encode: String_Encoding,
}

Token_Obj :: union {
	Token_Int,
	Token_Float,
	Token_String,
	Token_Char,
	Operator,
}

Token :: struct {
	loc:  Source_Code_Location,
	kind: Token_Kind,
	text: []u8,
	obj:  Token_Obj,
}

Config :: struct {
	inline_comment: string,
	comment_begin:  string,
	comment_end:    string,
}

Lexer :: struct {
	buff:        []u8,
	pos:         int,
	loc:         Source_Code_Location,
	config:      Config,
	error_count: int,
}

is_eof :: proc(l: ^Lexer) -> bool {
	return l.pos >= len(l.buff)
}

decode :: #force_inline proc(buf: []byte) -> (r: rune, size: int, err: Error) {
	// decode_rune_in_bytes() returns RUNE_ERROR to tell the given result isn't a rune, but it
	// doesn't mean it's not valid
	r, size = utf8.decode_rune_in_bytes(buf)
	if size == 0 {
		return r, size, .Invalid_Character
	}
	return r, size, .None
}

peek :: proc(l: ^Lexer) -> (r: rune, size: int, err: Error) {
	if is_eof(l) {
		return 0, 0, .EOF
	}
	return decode(l.buff[l.pos:])
}

peek2 :: proc(l: ^Lexer) -> (r: rune, size: int, err: Error) {
	if is_eof(l) {
		return 0, 0, .EOF
	}

	_, size = peek(l) or_return
	pos: int = l.pos + size

	if pos >= len(l.buff) {
		return 0, 0, .EOF
	}

	return decode(l.buff[pos:])
}

next_rune :: proc(l: ^Lexer) -> (r: rune, err: Error) {
	size: int = ---
	r, size = peek(l) or_return
	l.pos += size

	switch r {
	case '\n':
		l.loc.line += 1
		l.loc.column = 0
	case:
		l.loc.column += 1
	}

	return r, .None
}

jump :: proc(l: ^Lexer, count: uint) -> (r: rune, err: Error) {
	for i in 0 ..< count {
		r = next_rune(l) or_return
	}
	return
}

is_space :: proc(r: rune) -> bool {
	switch r {
	case ' ', '\t', '\r':
		return true
	}
	return false
}

is_newline :: proc(r: rune) -> bool {
	return r == '\n'
}

skip_whitespace :: proc(l: ^Lexer) -> Error {
	r: rune = ---
	size: int = ---
	for {
		r, size = peek(l) or_return
		if !is_space(r) {
			return .None
		}
		l.pos += size
	}
}

skip_newline :: proc(l: ^Lexer, ok: bool) -> Error {
	r: rune = ---
	size: int = ---
	for {
		r, size = peek(l) or_return
		l.pos += size
		if is_newline(r) {
			return .None
		}
	}
}

Error :: enum {
	None = 0,
	EOF,
	Invalid_Character,
	Fail_Expect,
}

expect :: proc(l: ^Lexer, expected: []u8) -> (r: rune, err: Error) {
	loc := l.loc

	r, _ = peek(l) or_return

	if r != rune(expected[0]) {
		// TBD: print fail to compare
		return r, .Fail_Expect
	}

	return next_rune(l)
}

lit :: proc(l: ^Lexer, literal: []u8, kind: Token_Kind) -> (t: Token, err: Error) {
	assert(len(literal) == 1, "literals passed to lexer_lit() should be one byte")

	loc := l.loc

	_, err = expect(l, literal)
	if err != nil {
		// If expect fails because the values don't match, return as unknown
		// else treat it as an actual error
		if err == .Fail_Expect {
			// lexer_error(...)
			return unknown(l)
		} else {
			return
		}
	}

	return Token{loc = loc, kind = kind, text = literal}, .None
}

unknown :: proc(l: ^Lexer) -> (t: Token, err: Error) {
	loc := l.loc

	size: int = ---
	_, size = peek(l) or_return

	return Token{loc = loc, kind = .Unknown, text = l.buff[l.pos - size:l.pos]}, .None
}

is_identifier :: proc(r: rune) -> bool {
	return r == '_' || unicode.is_alpha(r)
}

is_identifier2 :: proc(r: rune) -> bool {
	return r == '_' || unicode.is_alpha(r) || unicode.is_number(r)
}

operator :: proc(l: ^Lexer) -> (t: Token, err: Error) {
	loc := l.loc
	begin := l.pos

	first, fsize := peek(l) or_return
	second, ssize := peek2(l) or_return

	op: Operator = ---
	kind: Token_Kind = .Operator

	switch first {
	case '=':
		l.pos += fsize
		if second == '=' {
			l.pos += ssize
			op = .EqEq
		} else {
			op = .Eq
		}
		break

	case '!':
		l.pos += fsize
		if second == '=' {
			l.pos += ssize
			op = .NotEq
		} else {
			op = .Not
		}
		break

	case '<':
		l.pos += fsize
		if second == '=' {
			l.pos += ssize
			op = .LtEq
		} else if second == '<' {
			l.pos += ssize
			third, tsize := peek(l) or_return
			if third == '=' {
				l.pos += tsize
				op = .ShlEq
			} else {
				op = .Shl
			}
		} else {
			op = .Lt
		}
		break

	case '>':
		l.pos += fsize
		if second == '=' {
			l.pos += ssize
			op = .GtEq
		} else if second == '>' {
			l.pos += ssize
			third, tsize := peek(l) or_return
			if third == '=' {
				l.pos += tsize
				op = .ShrEq
			} else {
				op = .Shr
			}
		} else {
			op = .Gt
		}
		break

	case '+':
		l.pos += fsize
		if second == '=' {
			l.pos += ssize
			op = .PlusEq
		} else if second == '+' {
			l.pos += ssize
			op = .PlusPlus
		} else {
			op = .Plus
		}
		break

	case '-':
		l.pos += fsize
		if second == '=' {
			l.pos += ssize
			op = .MinusEq
		} else if second == '-' {
			l.pos += ssize
			op = .MinusMinus
		} else if second == '>' {
			l.pos += ssize
			kind = .RArrow
		} else {
			op = .Minus
		}
		break

	case '*':
		l.pos += fsize
		if second == '=' {
			l.pos += ssize
			op = .MulEq
		} else {
			op = .Mul
		}
		break

	case '/':
		l.pos += fsize
		if second == '=' {
			l.pos += ssize
			op = .DivEq
		} else {
			op = .Div
		}
		break

	case '^':
		l.pos += fsize
		if second == '=' {
			l.pos += ssize
			op = .XorEq
		} else {
			op = .Xor
		}
		break

	case '&':
		l.pos += fsize
		if second == '&' {
			l.pos += ssize
			op = .AndAnd
		} else if second == '=' {
			l.pos += ssize
			op = .AndEq
		} else {
			op = .And
		}
		break

	case '|':
		l.pos += fsize
		if second == '|' {
			l.pos += ssize
			op = .OrOr
		} else if second == '=' {
			l.pos += ssize
			op = .OrEq
		} else {
			op = .Or
		}
		break

	case '%':
		l.pos += fsize
		if second == '=' {
			l.pos += ssize
			op = .ModuloEq
		} else {
			op = .Modulo
		}
		break

	case '~':
		l.pos += fsize
		op = .Mask
		break
	case:
		return unknown(l)
	}

	return Token{loc = loc, kind = kind, text = l.buff[begin:l.pos], obj = op}, .None
}

char :: proc(l: ^Lexer, encode: String_Encoding) -> (t: Token, err: Error) {
	loc := l.loc

	if '\'' == l.buff[l.pos] {
		next_rune(l)
	} else {
		assert(('\'' == l.buff[l.pos - 1]), "expected position to be at start of character")
	}

	begin := l.pos
	c := Token_Char{encode}

	for !is_eof(l) {
		r := next_rune(l) or_return

		if r == '\\' {
			_ = next_rune(l) or_return
		} else if r == '\'' {

			return Token{loc = loc, kind = .Char, text = l.buff[begin:l.pos], obj = c}, .None
		}
	}

	fmt.panicf("unterminated char literal")
}

str :: proc(l: ^Lexer, encode: String_Encoding) -> (t: Token, err: Error) {
	loc := l.loc
	expect(l, transmute([]u8)QUOTE)

	begin := l.pos
	s := Token_String{encode}

	for !is_eof(l) {
		r := next_rune(l) or_return

		if r == '\\' {
			if !is_eof(l) {
				next_rune(l)
			}
		} else if r == '"' {
			return Token{loc = loc, kind = .String, text = l.buff[begin:l.pos], obj = s}, .None
		}
	}

	fmt.panicf("unterminated string")
}

identifier :: proc(l: ^Lexer) -> (t: Token, err: Error) {
	loc := l.loc
	begin := l.pos

	block: {
		encoding: String_Encoding = ---

		r, rsize := peek(l) or_return

		switch r {
		case 'L':
			encoding = .Wide
		case 'u':
			encoding = .U16
		case 'U':
			encoding = .U32
		case:
			break block
		}

		quote, qsize := peek2(l) or_return

		if quote == '\'' {
			l.pos += rsize
			return char(l, encoding)
		} else if quote == '"' {
			l.pos += rsize
			return str(l, encoding)
		}
	}

	for !is_eof(l) {
		r, size := peek(l) or_return
		if is_identifier2(r) {
			l.pos += size
			continue
		}
		break
	}
	return Token{loc = loc, kind = .Identifier, text = l.buff[begin:l.pos]}, .None
}

next :: proc(l: ^Lexer) -> (t: Token, err: Error) {
	skip_whitespace(l)


	if is_eof(l) {
		return Token{kind = .EOF, text = transmute([]u8)EOF}, .EOF
	}

	r, _ := peek(l) or_return

	switch r {
	case '(':
		return lit(l, transmute([]u8)LPAREN, .LParen)
	case ')':
		return lit(l, transmute([]u8)RPAREN, .RParen)
	case '[':
		return lit(l, transmute([]u8)LBRACKET, .LBracket)
	case ']':
		return lit(l, transmute([]u8)RBRACKET, .RBracket)
	case '{':
		return lit(l, transmute([]u8)LBRACE, .LBrace)
	case '}':
		return lit(l, transmute([]u8)RBRACE, .RBrace)
	case ',':
		return lit(l, transmute([]u8)COMMA, .Comma)
	case ';':
		return lit(l, transmute([]u8)SEMICOLON, .Semicolon)
	case ':':
		return lit(l, transmute([]u8)COLON, .Colon)
	case '?':
		return lit(l, transmute([]u8)QUESTIONMARK, .Question_Mark)
	case '.':
		loc := l.loc
		r, size := peek2(l) or_return
		begin := size
		if r == '.' {
			l.pos += size
			r, size = peek2(l) or_return
			if r == '.' {
				l.pos += size
				return Token{kind = .Ellipsis, text = l.buff[begin:l.pos], loc = loc}, .None
			} else {
				return Token{kind = .DoubleDot, text = l.buff[begin:l.pos], loc = loc}, .None
			}
		}

		return lit(l, transmute([]u8)DOT, .Dot)
	case '\'':
		return lit(l, transmute([]u8)APOSTROPHE, .Apostrophe)
	case '"':
		return str(l, .U8)
	case:
		if is_identifier(r) {
			return identifier(l)
		}
		if unicode.is_number(r) {
			unimplemented()
			// return number(l)
		}
		// if (lexer_is_comment(l, l->settings.inline_comment)) {
		// 	lexer_skip_newline(l);
		// 	return lexer_next(l, out);
		// }
		// if (lexer_is_comment(l, l->settings.comment_begin)) {
		// 	lexer_comment(l);
		// 	return lexer_next(l, out);
		// }

		return operator(l)
	}

	unimplemented()
}

main :: proc() {

	sb: strings.Builder
	strings.builder_init(&sb)
	defer strings.builder_destroy(&sb)
	strings.write_string(&sb, "my testing ジ code\nmain :: proc(t: int) -> bool;")
	fmt.println(strings.to_string(sb))

	l := Lexer {
		buff   = sb.buf[:],
		config = {},
	}

	for {
		c, err := next(&l)
		if err == .EOF {
			break
		}
		fmt.print(c)
	}

	fmt.printfln("\nReport:\n" + "Last line: %d\n" + "Last column: %d", l.loc.line, l.loc.column)
	// token, ok := next(&l)
}
