package odd_flags

import "core:strconv"
import "core:unicode/utf8"

VALID_BOOL :: `Valid values:
  1, t, T, true, TRUE, True
  0, f, F, false, FALSE, False`

VALID_INT :: `Valid values:
  -1, 1_000, 0xFF, 0b1010, 0o12, 0d10, 0z10`

VALID_UINT :: `Valid values:
  1, 1_000, 0xFF, 0b1010, 0o12, 0d10, 0z10`

VALID_FLOAT :: `Valid values:
  +1.00, -1.00, nan, infinity, inf, 1.00e2, 0h3C00, 0h3F80_0000, 0h3FF0_0000_0000_0000`

VALID_COMPLEX :: `Valid values:
  3+1i, 5+7i`

VALID_QUATERNION :: `Valid values:
  1+2i+3j+4k`

VALID_RUNE :: `Valid values:
  木, a, \t, ☺️`

parse_i128 :: proc() -> (value: i128, ok: bool) {
	input, has_value := get_value()
	if has_value {
		value, ok = strconv.parse_i128(input)
		if !ok do invalid_value("integer", input, VALID_INT)
	} else {
		missing_value()
	}
	return
}

parse_u128 :: proc() -> (value: u128, ok: bool) {
	input, has_value := get_value()
	if has_value {
		value, ok = strconv.parse_u128(input)
		if !ok do invalid_value("natural", input, VALID_UINT)
	} else {
		missing_value()
	}
	return
}

parse_int :: proc() -> (value: int, ok: bool) {
	input, has_value := get_value()
	if has_value {
		value, ok = strconv.parse_int(input)
		if !ok do invalid_value("integer", input, VALID_INT)
	} else {
		missing_value()
	}
	return
}

parse_uint :: proc() -> (value: uint, ok: bool) {
	input, has_value := get_value()
	if has_value {
		value, ok = strconv.parse_uint(input)
		if !ok do invalid_value("natural", input, VALID_UINT)
	} else {
		missing_value()
	}
	return
}

parse_boolean :: proc() -> (value: bool, ok: bool) {
	input, has_value := get_value()
	if has_value {
		value, ok = strconv.parse_bool(input)
		if !ok {
			invalid_value("bool", input, VALID_BOOL)
		}
	}
	return
}

parse_f32 :: proc() -> (value: f32, ok: bool) {
	input, has_value := get_value()
	if has_value {
		value, ok = strconv.parse_f32(input)
		if !ok {
			invalid_value("decimal", input, VALID_FLOAT)
		}
	}
	return
}

parse_f64 :: proc() -> (value: f64, ok: bool) {
	input, has_value := get_value()
	if has_value {
		value, ok = strconv.parse_f64(input)
		if !ok {
			invalid_value("decimal", input, VALID_FLOAT)
		}
	}
	return
}

parse_complex32 :: proc() -> (value: complex32, ok: bool) {
	input, has_value := get_value()
	if has_value {
		value, ok = strconv.parse_complex32(input)
		if !ok {
			invalid_value("complex", input, VALID_COMPLEX)
		}
	}
	return
}

parse_complex64 :: proc() -> (value: complex64, ok: bool) {
	input, has_value := get_value()
	if has_value {
		value, ok = strconv.parse_complex64(input)
		if !ok {
			invalid_value("complex", input, VALID_COMPLEX)
		}
	}
	return
}

parse_complex128 :: proc() -> (value: complex128, ok: bool) {
	input, has_value := get_value()
	if has_value {
		value, ok = strconv.parse_complex128(input)
		if !ok {
			invalid_value("complex", input, VALID_COMPLEX)
		}
	}
	return
}

parse_quaternion64 :: proc() -> (value: quaternion64, ok: bool) {
	input, has_value := get_value()
	if has_value {
		value, ok = strconv.parse_quaternion64(input)
		if !ok {
			invalid_value("quaternion", input, VALID_QUATERNION)
		}
	}
	return
}

parse_quaternion128 :: proc() -> (value: quaternion128, ok: bool) {
	input, has_value := get_value()
	if has_value {
		value, ok = strconv.parse_quaternion128(input)
		if !ok {
			invalid_value("quaternion", input, VALID_QUATERNION)
		}
	}
	return
}

parse_quaternion256 :: proc() -> (value: quaternion256, ok: bool) {
	input, has_value := get_value()
	if has_value {
		value, ok = strconv.parse_quaternion256(input)
		if !ok {
			invalid_value("quaternion", input, VALID_QUATERNION)
		}
	}
	return
}

parse_rune :: proc() -> (value: rune, ok: bool) {
	input, has_value := get_value()
	if has_value {
		if utf8.rune_count_in_string(input) != 1 {
			invalid_value("character", input, VALID_RUNE)
			return 0, false
		}
		return utf8.rune_at_pos(input, 0), true
	}
	return
}
