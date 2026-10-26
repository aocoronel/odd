package odd_flags

import "base:runtime"
import "core:log"
import "core:mem"
import "core:reflect"
import "core:strings"

get_rtti :: proc(ptr: rawptr, id: typeid) -> bool {
	return _get_rtti(ptr, type_base(id))
}

_get_rtti :: proc(ptr: rawptr, ti: ^Type_Info) -> bool {
	switch i in ti.variant {
	case Type_Info_Named:
		return _get_rtti(ptr, i.base)
	case Type_Info_Integer:
		return get_rtti_integer(ti.id)(ptr, ti.id)
	case Type_Info_Rune:
		return get_rune(ptr, ti.id)
	case Type_Info_Float:
		return get_rtti_float(ti.id)(ptr, ti.id)
	case Type_Info_Complex:
		return get_rtti_complex(ptr, ti.id)
	case Type_Info_Quaternion:
		return get_rtti_quaternion(ptr, ti.id)
	case Type_Info_String:
		return get_rtti_string(ptr, ti.id)
	case Type_Info_Boolean:
		return get_rtti_bool(ti.id)(ptr, ti.id)
	case Type_Info_Array,
	     Type_Info_Dynamic_Array,
	     Type_Info_Fixed_Capacity_Dynamic_Array,
	     Type_Info_Enumerated_Array:
		return get_rtti_array(ptr, ti.id)
	case Type_Info_Enum:
		return get_rtti_enum(ptr, ti.id)
	case Type_Info_Struct:
		return get_rtti_struct(ptr, ti.id)
	case Type_Info_Simd_Vector:
		return get_rtti_simd_vector(ptr, ti.id)
	case Type_Info_Bit_Set:
		return get_rtti_bit_set(ptr, ti.id)
	case Type_Info_Bit_Field,
	     Type_Info_Type_Id,
	     Type_Info_Matrix,
	     Type_Info_Map,
	     Type_Info_Union,
	     Type_Info_Slice,
	     Type_Info_Parameters,
	     Type_Info_Procedure,
	     Type_Info_Pointer,
	     Type_Info_Multi_Pointer,
	     Type_Info_Soa_Pointer:
		please_use_custom_proc(ti.id)
	case Type_Info_Any:
		unimplemented("as far as I know, 'any' should never be passed as a pointer.")
	}
	panic("unreachable")
}

get_rtti_enum :: proc(ptr: rawptr, id: typeid) -> bool {
	value, ok := get_value()
	if ok {
		i, ok := reflect.enum_from_name_any(id, value)
		if ok {
			// Note: taking odin/flags as a reference, there they write by type
			// but I honestly don't see that much big of a deal than to just do
			// this, since: Type_Info_Enum_Value :: distinct i64
			if ptr != nil {(cast(^i64)ptr)^ = cast(i64)i}
			return true
		} else {
			base := type_base(id).variant.(Type_Info_Enum)
			errorf("%s: invalid enum name: %q. Valid names: %s", optopt, value, base.names)
			return false
		}
	} else do missing_value()
	return false
}

get_rtti_bit_set :: proc(ptr: rawptr, id: typeid) -> bool {
	bit := type_base(id).variant.(Type_Info_Bit_Set)

	args_count := args_till_option()
	too_many_args(bit.underlying.size * 8, args_count) or_return

	fn: Get_Proc
	elem_size: int

	#partial switch i in bit.elem.variant {
	case Type_Info_Integer:
		fn = get_rtti_integer(bit.elem.id)
		elem_size = bit.elem.size
	case Type_Info_Rune:
		fn = get_rune
		elem_size = bit.elem.size
	case Type_Info_Named:
		fn = get_rtti_enum
		elem_size = (i.base.variant.(Type_Info_Enum)).base.size
	case Type_Info_Enum:
		fn = get_rtti_enum
		elem_size = i.base.size
	}

	_bit_set :: #force_inline proc(
		ptr: rawptr,
		bit: Type_Info_Bit_Set,
		fn: Get_Proc,
		args_count: int,
		lower, upper: i64,
		$T: typeid,
	) -> bool {
		for i in 0 ..< args_count {
			v: T
			fn(&v, bit.elem.id) or_return

			if v > cast(T)upper || v < cast(T)lower {
				if bit.elem.id == rune {
					errorf(
						"%s: argument %q is out of bounds: [%c..=%c]",
						optopt,
						optarg,
						lower,
						upper,
					)
				} else {
					errorf(
						"%s: argument %q is out of bounds: [%d..=%d]",
						optopt,
						optarg,
						lower,
						upper,
					)
				}
				optind = optind + args_count - i
				return false
			}

			if ptr != nil {
				(cast(^uintptr)ptr)^ |= 1 << (v - cast(T)lower)
			}
		}
		return true
	}

	upper, lower := bit.upper, bit.lower
	if elem_size * 8 > 64 {
		// I'd rather not use very large integers if I can avoid it
		_bit_set(ptr, bit, fn, args_count, lower, upper, u128) or_return
	} else {
		_bit_set(ptr, bit, fn, args_count, lower, upper, u64) or_return
	}

	return true
}

get_rtti_simd_vector :: proc(ptr: rawptr, id: typeid) -> bool {
	ti := type_base(id).variant.(Type_Info_Simd_Vector) or_return

	fn: Get_Proc

	args_count := args_till_option()

	missing_args(ti.count, args_count) or_return

	#partial switch i in ti.elem.variant {
	case Type_Info_Integer:
		fn = get_rtti_integer(ti.elem.id)
	case Type_Info_Float:
		fn = get_rtti_float(ti.elem.id)
	case Type_Info_Boolean:
		fn = get_rtti_bool(ti.elem.id)
	case Type_Info_Rune:
		fn = get_rune
	case:
		// rawptr
		please_use_custom_proc(id)
	}

	if ptr != nil {
		for i in 0 ..< ti.count {
			p := rawptr(uintptr(ptr) + uintptr(ti.elem_size * i))
			ok := fn(p, ti.elem.id)
			if !ok {
				optind = optind + ti.count - i
				return false
			}
		}
	} else {
		for i in 0 ..< ti.count {
			ok := fn(nil, ti.elem.id)
			if !ok {
				optind = optind + ti.count - i
				return false
			}
		}
	}

	return true
}

get_rtti_struct :: proc(ptr: rawptr, id: typeid) -> bool {
	fields := reflect.struct_fields_zipped(id)

	args_count := args_till_option()
	missing_args(len(fields), args_count) or_return

	if ptr != nil {
		for field, i in fields {
			v := cast(rawptr)(cast(uintptr)ptr + field.offset)
			ok := _get_rtti(v, field.type)
			if !ok {
				optind = optind + len(fields) - i
				return false
			}
		}
	} else {
		for field, i in fields {
			ok := _get_rtti(nil, field.type)
			if !ok {
				optind = optind + len(fields) - i
				return false
			}
		}
	}

	return true
}

@(private)
_array_offset :: proc(idx: int, _: ^_Array) -> (int, bool) {
	return idx, true
}

@(private)
_enumerated_array_offset :: proc(idx: int, array: ^_Array) -> (i: int, ok: bool) {
	value, _ := get_value()

	eq := strings.index_rune(value, '=')
	if eq == -1 {
		errorf("%s: missing '=' separator in %q. Expected syntax: key=value", optopt, value)
		return 0, false
	}

	optval = value[:eq]

	#partial switch ti in type_base(array.index.id).variant {
	case Type_Info_Named:
		// assert
		_ = ti.base.variant.(Type_Info_Enum)
		get_rtti_enum(&i, ti.base.id) or_return
	case Type_Info_Enum:
		get_rtti_enum(&i, array.index.id) or_return
	case:
		panic("unreachable")
	}

	optval = value[eq + 1:]

	return i, true
}

/*
This is just so the get_rtti_array doesn't have to be split in two, due to the
enumerated array implementation.

This is exclusive to be used in get_rtti_array
*/
@(private)
_Array :: struct {
	get_offset:       proc(_: int, _: ^_Array) -> (int, bool),
	data:             []byte,
	elem, index:      ^Type_Info,
	count, elem_size: int,
}

@(optimization_mode = "favor_size")
get_array :: proc(
	array: ^_Array,
	get_element: proc(_: rawptr, _: typeid) -> bool,
	$T: typeid,
) -> bool {
	values := transmute([]T)array.data

	get_offset := array.get_offset
	count := array.count

	if array.data != nil {
		for i in 0 ..< count {
			offset := get_offset(i, array) or_return
			get_element(&values[offset], T) or_return
		}
	} else {
		for i in 0 ..< count {
			offset := get_offset(i, array) or_return
			get_element(nil, T) or_return
		}
	}

	return true
}

get_rtti_array :: proc(ptr: rawptr, id: typeid) -> bool {
	array: _Array

	args_count := args_till_option()
	final_optind := optind + args_count

	fn :: _array_offset

	slice_dyn_array :: proc(ptr: rawptr, elem_size, elem_align, count: int) -> ([]byte, bool) {
		if !runtime.__dynamic_array_resize(ptr, elem_size, elem_align, count) {
			log.error("%s: failed to reserve memory for the dynamic array", optopt)
			return nil, false
		}
		dyn := cast(^runtime.Raw_Dynamic_Array)ptr
		// Don't forget the shadow header!
		// Spent a few hours to discover this
		dyn_data := rawptr(uintptr(dyn.data))
		return mem.byte_slice(dyn_data, count * elem_size), true
	}

	slice_fixed_dyn_array :: proc(ptr: rawptr, elem_size, capacity: int) -> ([]byte, bool) {
		len := cast(^int)rawptr(uintptr(ptr) + uintptr(capacity * elem_size))
		len^ = capacity
		return mem.byte_slice(ptr, capacity * elem_size), true
	}

	ti := type_base(id)
	#partial switch v in ti.variant {
	case Type_Info_Array:
		missing_args(v.count, args_count) or_return
		data := mem.byte_slice(ptr, v.count * v.elem_size) if ptr != nil else nil
		array = {fn, data, v.elem, nil, v.count, v.elem_size}
	case Type_Info_Dynamic_Array:
		data: []byte
		if ptr != nil {
			ok: bool
			data, ok = slice_dyn_array(ptr, v.elem_size, v.elem.align, args_count)
			if !ok {
				optind = optind + args_count
				return false
			}
		}
		array = {fn, data, v.elem, nil, args_count, v.elem_size}
	case Type_Info_Fixed_Capacity_Dynamic_Array:
		too_many_args(v.capacity, args_count) or_return
		data: []byte
		if ptr != nil {
			data = slice_fixed_dyn_array(ptr, v.elem_size, args_count) or_return
		}
		array = {fn, data, v.elem, nil, args_count, v.elem_size}
	case Type_Info_Enumerated_Array:
		too_many_args(v.count, args_count) or_return
		data := mem.byte_slice(ptr, v.count * v.elem_size) if ptr != nil else nil
		array = {_enumerated_array_offset, data, v.elem, v.index, v.count, v.elem_size}
	case:
		panic("unreachable")
	}

	c32 :: complex32
	c64 :: complex64
	c128 :: complex128

	q64 :: quaternion64
	q128 :: quaternion128
	q256 :: quaternion256

	ok: bool
	switch array.elem.id {
	// odinfmt: disable
    case cstring: ok = get_array(&array, get_cstring, cstring)
    case string:  ok = get_array(&array, get_string, string)
    case uint:    ok = get_array(&array, get_uint, uint)
    case u8:      ok = get_array(&array, get_u8, u8)
    case u16:     ok = get_array(&array, get_u16, u16)
    case u32:     ok = get_array(&array, get_u32, u32)
    case u64:     ok = get_array(&array, get_u64, u64)
    case u128:    ok = get_array(&array, get_u128, u128)
    case u16be:   ok = get_array(&array, get_u16be, u16be)
    case u32be:   ok = get_array(&array, get_u32be, u32be)
    case u64be:   ok = get_array(&array, get_u64be, u64be)
    case u128be:  ok = get_array(&array, get_u128be, u128be)
    case u16le:   ok = get_array(&array, get_u16le, u16le)
    case u32le:   ok = get_array(&array, get_u32le, u32le)
    case u64le:   ok = get_array(&array, get_u64le, u64le)
    case u128le:  ok = get_array(&array, get_u128le, u128le)
    case int:     ok = get_array(&array, get_int, int)
    case i8:      ok = get_array(&array, get_i8, i8)
    case i16:     ok = get_array(&array, get_i16, i16)
    case i32:     ok = get_array(&array, get_i32, i32)
    case i64:     ok = get_array(&array, get_i64, i64)
    case i128:    ok = get_array(&array, get_i128, i128)
    case i16be:   ok = get_array(&array, get_i16be, i16be)
    case i32be:   ok = get_array(&array, get_i32be, i32be)
    case i64be:   ok = get_array(&array, get_i64be, i64be)
    case i128be:  ok = get_array(&array, get_i128be, i128be)
    case i16le:   ok = get_array(&array, get_i16le, i16le)
    case i32le:   ok = get_array(&array, get_i32le, i32le)
    case i64le:   ok = get_array(&array, get_i64le, i64le)
    case i128le:  ok = get_array(&array, get_i128le, i128le)
    case f32:     ok = get_array(&array, get_f32, f32)
    case f64:     ok = get_array(&array, get_f64, f64)
    case f32be:   ok = get_array(&array, get_f32be, f32be)
    case f64be:   ok = get_array(&array, get_f64be, f64be)
    case f32le:   ok = get_array(&array, get_f32le, f32le)
    case f64le:   ok = get_array(&array, get_f64le, f64le)
    case c32:     ok = get_array(&array, get_complex32, complex32)
    case c64:     ok = get_array(&array, get_complex64, complex64)
    case c128:    ok = get_array(&array, get_complex128, complex128)
    case q64:     ok = get_array(&array, get_quaternion64, quaternion64)
    case q128:    ok = get_array(&array, get_quaternion128, quaternion128)
    case q256:    ok = get_array(&array, get_quaternion256, quaternion256)
    case bool:    ok = get_array(&array, get_bool, bool)
    case b8:      ok = get_array(&array, get_b8, b8)
    case b16:     ok = get_array(&array, get_b16, b16)
    case b32:     ok = get_array(&array, get_b32, b32)
    case b64:     ok = get_array(&array, get_b64, b64)
	case: unimplemented("array")
	// odinfmt: enable
	}
	if !ok {
		optind = final_optind
	}
	return ok
}

get_rtti_integer :: proc(id: typeid) -> Get_Proc {
	switch id {
	// odinfmt: disable
	case uint:   return get_uint
	case u8:     return get_u8
	case u16:    return get_u16
	case u32:    return get_u32
	case u64:    return get_u64
	case u128:   return get_u128
	case int:    return get_int
	case i8:     return get_i8
	case i16:    return get_i16
	case i32:    return get_i32
	case i64:    return get_i64
	case i128:   return get_i128
	case u16be:  return get_u16be
	case u32be:  return get_u32be
	case u64be:  return get_u64be
	case u128be: return get_u128be
	case i16be:  return get_i16be
	case i32be:  return get_i32be
	case i64be:  return get_i64be
	case i128be: return get_i128be
	case u16le:  return get_u16le
	case u32le:  return get_u32le
	case u64le:  return get_u64le
	case u128le: return get_u128le
	case i16le:  return get_i16le
	case i32le:  return get_i32le
	case i64le:  return get_i64le
	case i128le: return get_i128le
	// odinfmt: enable
	}
	panic("unreachable")
}

get_rtti_float :: proc(id: typeid) -> Get_Proc {
	switch id {
	// odinfmt: disable
	case f32:   return get_f32
	case f64:   return get_f64
	case f32le: return get_f32le
	case f64le: return get_f64le
	case f32be: return get_f32be
	case f64be: return get_f64be
	// odinfmt: enable
	}
	panic("unreachable")
}

get_rtti_complex :: proc(ptr: rawptr, id: typeid) -> bool {
	switch id {
	// odinfmt: disable
	case complex32:  return get_complex32(ptr, id)
	case complex64:  return get_complex64(ptr, id)
	case complex128: return get_complex128(ptr, id)
	// odinfmt: enable
	}
	panic("unreachable")
}

get_rtti_quaternion :: proc(ptr: rawptr, id: typeid) -> bool {
	switch id {
	// odinfmt: disable
	case quaternion64:  return get_quaternion64(ptr, id)
	case quaternion128: return get_quaternion128(ptr, id)
	case quaternion256: return get_quaternion256(ptr, id)
	// odinfmt: enable
	}
	panic("unreachable")
}

get_rtti_bool :: proc(id: typeid) -> Get_Proc {
	switch id {
	// odinfmt: disable
	case bool: return get_bool
	case b8:   return get_b8
	case b16:  return get_b16
	case b32:  return get_b32
	case b64:  return get_b64
	// odinfmt: enable
	}
	panic("unreachable")
}

get_rtti_string :: proc(ptr: rawptr, id: typeid) -> bool {
	switch id {
	// odinfmt: disable
	case string:    return get_string(ptr, id)
	case cstring:   return get_cstring(ptr, id)
	case string16:  unimplemented("UTF-16")
    case cstring16: unimplemented("UTF-16")
	// odinfmt: enable
	}
	panic("unreachable")
}
