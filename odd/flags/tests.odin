package odd_flags

import "core:testing"
import "shared:odd/debug"

T :: testing.T

@(test)
_test :: proc(_: ^T) {
	debug.register_back_trace()
	Enum :: enum {
		Ok,
		Not_Ok,
	}

	Struct :: struct {
		name:  string,
		array: [2]f32,
	}

	simd_floats: #simd[2]f64
	simd_integers: #simd[2]u64
	simd_runes: #simd[2]rune
	simd_booleans: #simd[2]bool

	primitive_floats: f64
	primitive_integers: u64
	primitive_runes: rune
	primitive_booleans: bool
	primitive_cstrings: cstring
	primitive_strings: string
	primitive_complex: complex32
	primitive_quaternion: quaternion64

	array: [2]string

	// The only type that allocates
	dynamic_array: [dynamic]string
	defer delete(dynamic_array)

	fixed_dynamic_array: [dynamic; 2]string
	enumerated_array: [Enum]string

	enums: Enum
	structs: Struct

	bitsets_enum: bit_set[Enum;u32]
	bitsets_rune: bit_set['A' ..= 'Z']
	bitsets_integer: bit_set[0 ..= 15;[2]u8]

	flags := []Option {
		{"simd-floats", "", &simd_floats, nil},
		{"simd-integers", "", &simd_integers, nil},
		{"simd-runes", "", &simd_runes, nil},
		{"simd-booleans", "", &simd_booleans, nil},
		{"primitive-floats", "", &primitive_floats, nil},
		{"primitive-integers", "", &primitive_integers, nil},
		{"primitive-runes", "", &primitive_runes, nil},
		{"primitive-booleans", "", &primitive_booleans, nil},
		{"primitive-cstrings", "", &primitive_cstrings, nil},
		{"primitive-strings", "", &primitive_strings, nil},
		{"primitive-complex", "", &primitive_complex, nil},
		{"primitive-quaternion", "", &primitive_quaternion, nil},
		{"array", "", &array, nil},
		{"dynamic-array", "", &dynamic_array, nil},
		{"fixed_dynamic_array", "", &fixed_dynamic_array, nil},
		{"enumerated-array", "", &enumerated_array, nil},
		{"enums", "", &enums, nil},
		{"structs", "", &structs, nil},
		{"bitsets-enum", "", &bitsets_enum, nil},
		{"bitsets-rune", "", &bitsets_rune, nil},
		{"bitsets-integer", "", &bitsets_integer, nil},
	}

	m, _ := init(flags)
	defer delete(m)

    // odinfmt: disable
	args__ = {
        nil, // program name
        // SIMD
        "--/simd-floats", "2.0", "127.69",
        "--/simd-integers", "23", "520",
        "--/simd-runes", "A", "木",
        "--/simd-booleans", "false", "1",
        // Primitives
        "--/primitive-floats",	"2.0",
        "--/primitive-integers", "23",
        "--/primitive-runes", "A",
        "--/primitive-booleans", "False",
        "--/primitive-cstrings", "Hello there",
        "--/primitive-strings", "Hello there",
        "--/primitive-complex", "3+1i",
        "--/primitive-quaternion", "1+2i+3j+4k",
        // Arrays
        "--/array", "Hello World", "World Hello",
        "--/dynamic-array", "Hello World", "World Hello",
        "--/fixed_dynamic_array", "Hello World", "World Hello",
        "--/enumerated-array", "Not_Ok=Hello World", "Ok=World Hello",
        // Enum
        "--/enums", "Ok",
        // Struct
        "--/structs", "name", "2.32", "1.09",
        // Bit set
        "--/bitsets-enum", "Ok", "Not_Ok",
        "--/bitsets-rune", "A", "Z",
        "--/bitsets-integer", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15",
	}
    // odinfmt: enable

	for has_args_left() {
		result := parse(m, flags)
		assert(result == .Ok)
	}

	assert(simd_floats == {})
	assert(simd_integers == {})
	assert(simd_runes == {})
	assert(simd_booleans == {})

	assert(primitive_floats == {})
	assert(primitive_integers == {})
	assert(primitive_runes == {})
	assert(primitive_booleans == {})
	assert(primitive_strings == {})
	assert(primitive_cstrings == {})
	assert(primitive_complex == {})
	assert(primitive_quaternion == {})

	assert(array == {})
	assert(len(dynamic_array) == 0)
	assert(len(fixed_dynamic_array) == 0)
	assert(enumerated_array == {})

	assert(enums == {})

	assert(structs.name == {})
	assert(structs.array == {})

	assert(bitsets_enum == {})
	assert(bitsets_rune == {})
	assert(bitsets_integer == {})

    // odinfmt: disable
	args__ = {
        nil, // program name
        // SIMD
        "--simd-floats", "2.0", "127.69",
        "--simd-integers", "23", "520",
        "--simd-runes", "A", "木",
        "--simd-booleans", "false", "1",
        // Primitives
        "--primitive-floats",	"2.0",
        "--primitive-integers", "23",
        "--primitive-runes", "A",
        "--primitive-booleans", "False",
        "--primitive-cstrings", "Hello there",
        "--primitive-strings", "Hello there",
        "--primitive-complex", "3+1i",
        "--primitive-quaternion", "1+2i+3j+4k",
        // Arrays
        "--array", "Hello World", "World Hello",
        "--dynamic-array", "Hello World", "World Hello",
        "--fixed_dynamic_array", "Hello World", "World Hello",
        "--enumerated-array", "Not_Ok=Hello World", "Ok=World Hello",
        // Enum
        "--enums", "Ok",
        // Struct
        "--structs", "name", "2.32", "1.09",
        // Bit set
        "--bitsets-enum", "Ok", "Not_Ok",
        "--bitsets-rune", "A", "Z",
        "--bitsets-integer", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15",
	}
    // odinfmt: enable

	optind = 1
	for has_args_left() {
		result := parse(m, flags)
		assert(result == .Ok)
	}

	assert(simd_floats == {2.0, 127.69})
	assert(simd_integers == {23, 520})
	assert(simd_runes == {'A', '木'})
	assert(simd_booleans == {false, true})

	assert(primitive_floats == 2.0)
	assert(primitive_integers == 23)
	assert(primitive_runes == 'A')
	assert(primitive_booleans == false)
	assert(primitive_strings == "Hello there")
	assert(primitive_cstrings == "Hello there")
	assert(primitive_complex == 3 + 1i)
	assert(primitive_quaternion == 1 + 2i + 3j + 4k)

	assert(array == {"Hello World", "World Hello"})
	assert(dynamic_array[0] == "Hello World")
	assert(dynamic_array[1] == "World Hello")
	assert(fixed_dynamic_array[0] == "Hello World")
	assert(fixed_dynamic_array[1] == "World Hello")
	assert(enumerated_array == {.Not_Ok = "Hello World", .Ok = "World Hello"})

	assert(enums == .Ok)

	assert(structs.name == "name")
	assert(structs.array == {2.32, 1.09})

	assert(bitsets_enum == {.Ok, .Not_Ok})
	assert(bitsets_rune == {'A', 'Z'})
	// Filling all the bits
	assert(bitsets_integer == {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15})

	args__ = nil
}
