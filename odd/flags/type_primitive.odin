package odd_flags

import "base:runtime"

args_till_option :: proc "contextless" () -> int {
	args := get_args()
	for i in optind ..< len(args) {
		if is_option_raw(args[i]) {
			return i - optind
		}
	}
	return len(args) - optind
}

type_base :: proc(id: typeid) -> ^runtime.Type_Info {
	return runtime.type_info_base(type_info_of(id))
}

get_bool :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, bool)
	ptr := cast(^bool)ptr; value, ok := parse_boolean()
	if ptr != nil {ptr^ = value if ok else !ptr^}
	return true
}

get_b8 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, b8)
	ptr := cast(^b8)ptr; value, ok := parse_boolean()
	if ptr != nil {ptr^ = b8(value) if ok else !ptr^}
	return true
}

get_b16 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, b16)
	ptr := cast(^b16)ptr; value, ok := parse_boolean()
	if ptr != nil {ptr^ = b16(value) if ok else !ptr^}
	return true
}

get_b32 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, b32)
	ptr := cast(^b32)ptr; value, ok := parse_boolean()
	if ptr != nil {ptr^ = b32(value) if ok else !ptr^}
	return true
}

get_b64 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, b64)
	ptr := cast(^b64)ptr; value, ok := parse_boolean()
	if ptr != nil {ptr^ = b64(value) if ok else !ptr^}
	return true
}

get_int :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, int)
	value := parse_int() or_return
	if ptr != nil {(cast(^int)ptr)^ = value}
	return true
}

get_uint :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, uint)
	value := parse_uint() or_return
	if ptr != nil {(cast(^uint)ptr)^ = value}
	return true
}

get_i8 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, i8)
	ptr := cast(^i8)ptr; value := parse_int() or_return
	if ptr != nil {ptr^ = cast(i8)clamp(value, cast(int)min(i8), cast(int)max(i8))}
	return true
}

get_i16 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, i16)
	ptr := cast(^i16)ptr; value := parse_int() or_return
	if ptr != nil {ptr^ = cast(i16)clamp(value, cast(int)min(i16), cast(int)max(i16))}
	return true
}

get_i32 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, i32)
	ptr := cast(^i32)ptr; value := parse_int() or_return
	if ptr != nil {ptr^ = cast(i32)clamp(value, cast(int)min(i32), cast(int)max(i32))}
	return true
}

get_i64 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, i64)
	ptr := cast(^i64)ptr; value := parse_int() or_return
	if ptr != nil {ptr^ = cast(i64)clamp(value, cast(int)min(i64), cast(int)max(i64))}
	return true
}

get_i128 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, i128)
	value := parse_i128() or_return
	if ptr != nil {(cast(^i128)ptr)^ = value}
	return true
}

get_i16be :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, i16be)
	ptr := cast(^i16be)ptr; value := parse_int() or_return
	if ptr != nil {ptr^ = cast(i16be)clamp(value, cast(int)min(i16be), cast(int)max(i16be))}
	return true
}

get_i32be :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, i32be)
	ptr := cast(^i32be)ptr; value := parse_int() or_return
	if ptr != nil {ptr^ = cast(i32be)clamp(value, cast(int)min(i32be), cast(int)max(i32be))}
	return true
}

get_i64be :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, i64be)
	ptr := cast(^i64be)ptr; value := parse_int() or_return
	if ptr != nil {ptr^ = cast(i64be)clamp(value, cast(int)min(i64be), cast(int)max(i64be))}
	return true
}

get_i128be :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, i128be)
	value := parse_i128() or_return
	if ptr != nil {(cast(^i128be)ptr)^ = cast(i128be)value}
	return true
}

get_i16le :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, i16le)
	ptr := cast(^i16le)ptr; value := parse_int() or_return
	if ptr != nil {ptr^ = cast(i16le)clamp(value, cast(int)min(i16le), cast(int)max(i16le))}
	return true
}

get_i32le :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, i32le)
	ptr := cast(^i32le)ptr; value := parse_int() or_return
	if ptr != nil {ptr^ = cast(i32le)clamp(value, cast(int)min(i32le), cast(int)max(i32le))}
	return true
}

get_i64le :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, i64le)
	ptr := cast(^i64le)ptr; value := parse_int() or_return
	if ptr != nil {ptr^ = cast(i64le)clamp(value, cast(int)min(i64le), cast(int)max(i64le))}
	return true
}

get_i128le :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, i128le)
	value := parse_i128() or_return
	if ptr != nil {(cast(^i128le)ptr)^ = cast(i128le)value}
	return true
}

get_u8 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, u8)
	ptr := cast(^u8)ptr; value := parse_uint() or_return
	if ptr != nil {ptr^ = cast(u8)min(value, cast(uint)max(u8))}
	return true
}

get_u16 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, u16)
	ptr := cast(^u16)ptr; value := parse_uint() or_return
	if ptr != nil {ptr^ = cast(u16)min(value, cast(uint)max(u16))}
	return true
}

get_u32 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, u32)
	ptr := cast(^u32)ptr; value := parse_uint() or_return
	if ptr != nil {ptr^ = cast(u32)min(value, cast(uint)max(u32))}
	return true
}

get_u64 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, u64)
	ptr := cast(^u64)ptr; value := parse_uint() or_return
	if ptr != nil {ptr^ = cast(u64)min(value, cast(uint)max(u64))}
	return true
}

get_u128 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, u128)
	value := parse_u128() or_return
	if ptr != nil {(cast(^u128)ptr)^ = value}
	return true
}

get_u16be :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, u16be)
	ptr := cast(^u16be)ptr; value := parse_uint() or_return
	if ptr != nil {ptr^ = cast(u16be)min(value, cast(uint)max(u16be))}
	return true
}

get_u32be :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, u32be)
	ptr := cast(^u32be)ptr; value := parse_uint() or_return
	if ptr != nil {ptr^ = cast(u32be)min(value, cast(uint)max(u32be))}
	return true
}

get_u64be :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, u64be)
	ptr := cast(^u64be)ptr; value := parse_uint() or_return
	if ptr != nil {ptr^ = cast(u64be)min(value, cast(uint)max(u64be))}
	return true
}

get_u128be :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, u128be)
	value := parse_u128() or_return
	if ptr != nil {(cast(^u128be)ptr)^ = cast(u128be)value}
	return true
}

get_u16le :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, u16le)
	ptr := cast(^u16le)ptr; value := parse_uint() or_return
	if ptr != nil {ptr^ = cast(u16le)min(value, cast(uint)max(u16le))}
	return true
}

get_u32le :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, u32le)
	ptr := cast(^u32le)ptr; value := parse_uint() or_return
	if ptr != nil {ptr^ = cast(u32le)min(value, cast(uint)max(u32le))}
	return true
}

get_u64le :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, u64le)
	ptr := cast(^u64le)ptr; value := parse_uint() or_return
	if ptr != nil {ptr^ = cast(u64le)min(value, cast(uint)max(u64le))}
	return true
}

get_u128le :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, u128le)
	value := parse_u128() or_return
	if ptr != nil {(cast(^u128le)ptr)^ = cast(u128le)value}
	return true
}

get_cstring :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, cstring)
	value, ok := get_value()
	if ok {
		if ptr != nil {(cast(^cstring)ptr)^ = cstring(raw_data(value))}
	} else {
		missing_value()
	}
	return ok
}

get_string :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, string)
	value, ok := get_value()
	if ok {
		if ptr != nil {(cast(^string)ptr)^ = value}
	} else {
		missing_value()
	}
	return ok
}

get_rune :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, rune)
	value := parse_rune() or_return
	if ptr != nil {(cast(^rune)ptr)^ = value}
	return true
}

get_f32 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, f32)
	value := parse_f32() or_return
	if ptr != nil {(cast(^f32)ptr)^ = value}
	return true
}

get_f64 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, f64)
	value := parse_f64() or_return
	if ptr != nil {(cast(^f64)ptr)^ = value}
	return true
}

get_f32le :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, f32le)
	value := parse_f32() or_return
	if ptr != nil {(cast(^f32le)ptr)^ = cast(f32le)value}
	return true
}

get_f64le :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, f64le)
	value := parse_f64() or_return
	if ptr != nil {(cast(^f64le)ptr)^ = cast(f64le)value}
	return true
}

get_f32be :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, f32be)
	value := parse_f32() or_return
	if ptr != nil {(cast(^f32be)ptr)^ = cast(f32be)value}
	return true
}

get_f64be :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, f64be)
	value := parse_f64() or_return
	if ptr != nil {(cast(^f64be)ptr)^ = cast(f64be)value}
	return true
}

get_complex32 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, complex32)
	value := parse_complex32() or_return
	if ptr != nil {(cast(^complex32)ptr)^ = value}
	return true
}

get_complex64 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, complex64)
	value := parse_complex64() or_return
	if ptr != nil {(cast(^complex64)ptr)^ = value}
	return true
}

get_complex128 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, complex128)
	value := parse_complex128() or_return
	if ptr != nil {(cast(^complex128)ptr)^ = value}
	return true
}

get_quaternion64 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, quaternion64)
	value := parse_quaternion64() or_return
	if ptr != nil {(cast(^quaternion64)ptr)^ = value}
	return true
}

get_quaternion128 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, quaternion128)
	value := parse_quaternion128() or_return
	if ptr != nil {(cast(^quaternion128)ptr)^ = value}
	return true
}

get_quaternion256 :: proc(ptr: rawptr, id: typeid) -> bool {
	assert_type(id, quaternion256)
	value := parse_quaternion256() or_return
	if ptr != nil {(cast(^quaternion256)ptr)^ = value}
	return true
}
