package odd_flags

import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:slice"
import "core:strings"
import "shared:odd/encoding"
import "shared:odd/term"

/*
Prints option usage for all supported types.

To print more details, do it manually.

The goal of the generated argument usage is to be obvious to the end user.

What the symbology means:

[]: Optional argument, else required argument
(): List (enum), or separator mark (struct)
[].. +%d: Up to N arguments
.. +%d: Needs N arguments
..: any number of arguments
[X..=Y]: inclusive range of valid arguments
()=: enumerated array "enum=argument" assignment

Attributes:

Option.help first line is special. If it starts with '#', it denotes an attribute.
Multiple attributes can be separated by comma: "#hidden,arg=VALUE".

The "hidden" attribute omits all details.

The "arg" attribute takes a value: "arg=VALUE". It overwrites the type name.
Combine with "force" attribute, to fully replace the usage.
This can be used for unsupported types.
*/
usage :: proc(opts: []Option) {
	print_enum :: proc(i: Type_Info_Enum) {
		for name, j in i.names {
			fmt.printf("%s", name)
			if j < len(i.names) - 1 {
				fmt.print(",")
			}
		}
	}

	please_use_help_attr :: #force_inline proc(id: typeid) -> ! {
		panicf("%s: Please, use the help attribute to overwrite the argument usage.", id)
	}

	print :: proc(ti: ^Type_Info, overwrite: string) {
		has_overwrite := len(overwrite) > 0
		switch i in ti.variant {
		case Type_Info_Named:
			print(i.base, overwrite)
		case Type_Info_Integer:
			if has_overwrite {fmt.print(overwrite); return}
			if i.signed {
				fmt.print("integer")
			} else {
				fmt.print("natural")
			}
		case Type_Info_Rune:
			if has_overwrite {fmt.print(overwrite); return}
			fmt.print("character")
		case Type_Info_Float:
			if has_overwrite {fmt.print(overwrite); return}
			fmt.print("decimal")
		case Type_Info_Complex:
			if has_overwrite {fmt.print(overwrite); return}
			fmt.print("complex")
		case Type_Info_Quaternion:
			if has_overwrite {fmt.print(overwrite); return}
			fmt.print("quaternion")
		case Type_Info_String:
			if has_overwrite {fmt.print(overwrite); return}
			fmt.print("text")
		case Type_Info_Boolean:
			fmt.print("bool")
		case Type_Info_Array:
			print(i.elem, overwrite)
			fmt.print(".. +")
			fmt.print(i.count - 1)
		case Type_Info_Dynamic_Array:
			fmt.print('[')
			print(i.elem, overwrite)
			fmt.print(']')
			fmt.print("..")
		case Type_Info_Fixed_Capacity_Dynamic_Array:
			fmt.print('[')
			print(i.elem, overwrite)
			fmt.print(']')
			fmt.print("..")
			fmt.printf(" +%d", i.capacity - 1)
		case Type_Info_Enumerated_Array:
			fmt.print('[')
			if has_overwrite {
				fmt.print(overwrite)
			} else {
				fmt.print('(')
				if named, is_named := i.index.variant.(Type_Info_Named); is_named {
					print_enum(named.base.variant.(Type_Info_Enum))
				} else {
					print_enum(i.index.variant.(Type_Info_Enum))
				}
				fmt.print(")=")
				print(i.elem, "")
			}
			fmt.print(']')
			fmt.print("..")
			fmt.printf(" +%d", i.count - 1)
		case Type_Info_Enum:
			if has_overwrite {
				fmt.print(overwrite)
			} else {
				fmt.print('(')
				print_enum(i)
				fmt.print(')')
			}
		case Type_Info_Struct:
			if has_overwrite {
				fmt.print(overwrite)
				return
			}
			for j in 0 ..< i.field_count {
				fmt.print('(')
				fmt.print(i.names[j])
				fmt.print(':')
				print(i.types[j], "")
				fmt.print(')')
				fmt.print(' ')
			}
		case Type_Info_Simd_Vector:
			print(i.elem, overwrite)
			fmt.print(".. +")
			fmt.print(i.count - 1)
		case Type_Info_Bit_Set:
			backing_size: int
			#partial switch bit in i.underlying.variant {
			case Type_Info_Integer, Type_Info_Rune:
				backing_size = i.underlying.size
			case Type_Info_Named:
				_ = bit.base.variant.(Type_Info_Enum)
				backing_size = bit.base.size
			case Type_Info_Enum:
				backing_size = bit.base.size
			case Type_Info_Array:
				backing_size = bit.count * bit.elem_size
			case:
				please_use_help_attr(ti.id)
			}
			fmt.print('[')
			if has_overwrite {
				fmt.print(overwrite)
			} else {
				#partial switch bit in i.elem.variant {
				case Type_Info_Rune:
					fmt.printf("%c..=%c", i.lower, i.upper)
				case Type_Info_Integer:
					fmt.printf("%d..=%d", i.lower, i.upper)
				case Type_Info_Enum:
					print_enum(bit)
				case:
					please_use_help_attr(ti.id)
				}
			}
			fmt.print(']')
			fmt.print("..")
			fmt.printf(" +%d", backing_size - 1)
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
		     Type_Info_Soa_Pointer,
		     Type_Info_Any:
			if has_overwrite {fmt.print(overwrite); return}
			please_use_help_attr(ti.id)
		}
	}

	sort_flags :: proc(i, j: Option) -> slice.Ordering {
		return slice.cmp(i.flag, j.flag)
	}

	slice.sort_by_cmp(opts, sort_flags)

	width := term.terminal_width()
	fmt.println("Options:")
	loop: for opt in opts {
		if opt.var == nil do continue

		argtype: string
		force: bool
		help := opt.help
		if len(help) > 0 && help[0] == '#' {
			pos := help[1:]
			idx := strings.index_rune(pos, '\n')
			if idx != -1 {
				help = pos[idx + 1:]
				pos = pos[:idx]
			} else {
				help = ""
			}
			for {
				value: string
				csv, comma, is_end := encoding.csv(pos)
				eq := strings.index_rune(csv, '=')
				if eq != -1 {
					value = csv[eq + 1:]
					csv = csv[:eq]
				}
				switch csv {
				case "arg":
					argtype = value
				case "force":
					force = true
				case "hidden":
					continue loop
				}
				if is_end {break}
				pos = pos[comma + 1:]
			}
		}

		fmt.print(' ')
		fmt.print(' ')
		fmt.print(opt.flag)

		dereferenced := reflect.deref(opt.var)
		ti := type_base(dereferenced.id)

		if force && len(argtype) > 0 {
			fmt.print(':')
			fmt.print(argtype)
		} else {
			if _, is_bool := ti.variant.(Type_Info_Boolean); !is_bool {
				fmt.print(':')
				print(ti, argtype)
			}
		}

		fmt.print('\n')

		if len(help) > 0 {
			term._iprint_str(help, 6, width)
		} else {
			fmt.print("      Option not documented yet\n")
		}
	}
}
