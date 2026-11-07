package odd_flags

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:strings"
import "shared:odd/encoding"
import "shared:odd/terminal"

Sort_Option :: #type proc(i, j: Option) -> slice.Ordering

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
usage :: proc(
	opts: []Option,
	indent: int = 6,
	compare: Sort_Option = sort_option_by_name,
	file := os.stderr,
) {
	if compare != nil {sort(opts, compare)}
	width := terminal.terminal_width()

	// Edge case, where tty is too small
	if width < 30 do width = 30

	print :: fmt.fprint

	loop: for opt in opts {
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

		print(file, "  ")
		print(file, opt.name)

		if force && len(argtype) > 0 {
			print(file, ':')
			print(file, argtype)
		} else {
			if opt.var != nil {
				dereferenced := reflect.deref(opt.var)
				ti := type_base(dereferenced.id)
				if _, is_bool := ti.variant.(Type_Info_Boolean); !is_bool {
					print(file, ':')
					print_var(ti, argtype, file)
				}
			}
		}

		print(file, '\n')

		if len(help) > 0 {
			terminal._iprint_str(help, indent, width)
		} else {
			print(file, "      Option not documented yet\n")
		}
	}
}

sort_option_by_name :: proc(i, j: Option) -> slice.Ordering {
	return slice.cmp(i.name, j.name)
}

sort :: #force_inline proc(opts: []Option, compare: Sort_Option = sort_option_by_name) {
	slice.sort_by_cmp(opts, compare)
}

print_enum :: proc(i: Type_Info_Enum, file := os.stderr) {
	for name, j in i.names {
		fmt.fprintf(file, "%s", name)
		if j < len(i.names) - 1 {
			fmt.fprint(file, ",")
		}
	}
}

print_var :: proc(ti: ^Type_Info, overwrite: string, file := os.stderr) {
	print :: fmt.fprint
	please_use_help_attr :: #force_inline proc(id: typeid) -> ! {
		panicf("%s: Please, use the help attribute to overwrite the argument usage.", id)
	}
	has_overwrite := len(overwrite) > 0
	switch i in ti.variant {
	case Type_Info_Named:
		print_var(i.base, overwrite, file)
	case Type_Info_Integer:
		if has_overwrite {print(file, overwrite); return}
		if i.signed {
			print(file, "integer")
		} else {
			print(file, "natural")
		}
	case Type_Info_Rune:
		if has_overwrite {print(file, overwrite); return}
		print(file, "character")
	case Type_Info_Float:
		if has_overwrite {print(file, overwrite); return}
		print(file, "decimal")
	case Type_Info_Complex:
		if has_overwrite {print(file, overwrite); return}
		print(file, "complex")
	case Type_Info_Quaternion:
		if has_overwrite {print(file, overwrite); return}
		print(file, "quaternion")
	case Type_Info_String:
		if has_overwrite {print(file, overwrite); return}
		print(file, "text")
	case Type_Info_Boolean:
		print(file, "bool")
	case Type_Info_Array:
		print_var(i.elem, overwrite, file)
		print(file, ".. +")
		print(file, i.count - 1)
	case Type_Info_Dynamic_Array:
		print(file, '[')
		print_var(i.elem, overwrite, file)
		print(file, ']')
		print(file, "..")
	case Type_Info_Fixed_Capacity_Dynamic_Array:
		print(file, '[')
		print_var(i.elem, overwrite, file)
		print(file, ']')
		print(file, "..")
		fmt.fprintf(file, " +%d", i.capacity - 1)
	case Type_Info_Enumerated_Array:
		print(file, '[')
		if has_overwrite {
			print(file, overwrite)
		} else {
			print(file, '(')
			if named, is_named := i.index.variant.(Type_Info_Named); is_named {
				print_enum(named.base.variant.(Type_Info_Enum))
			} else {
				print_enum(i.index.variant.(Type_Info_Enum))
			}
			print(file, ")=")
			print_var(i.elem, "", file)
		}
		print(file, ']')
		print(file, "..")
		fmt.fprintf(file, " +%d", i.count - 1)
	case Type_Info_Enum:
		if has_overwrite {
			print(file, overwrite)
		} else {
			print(file, '(')
			print_enum(i)
			print(file, ')')
		}
	case Type_Info_Struct:
		if has_overwrite {
			print(file, overwrite)
			return
		}
		for j in 0 ..< i.field_count {
			print(file, '(')
			print(file, i.names[j])
			print(file, ':')
			print_var(i.types[j], "", file)
			print(file, ')')
			print(file, ' ')
		}
	case Type_Info_Simd_Vector:
		print_var(i.elem, overwrite, file)
		print(file, ".. +")
		print(file, i.count - 1)
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
		print(file, '[')
		if has_overwrite {
			print(file, overwrite)
		} else {
			#partial switch bit in i.elem.variant {
			case Type_Info_Rune:
				fmt.fprintf(file, "%c..=%c", i.lower, i.upper)
			case Type_Info_Integer:
				fmt.fprintf(file, "%d..=%d", i.lower, i.upper)
			case Type_Info_Enum:
				print_enum(bit)
			case:
				please_use_help_attr(ti.id)
			}
		}
		print(file, ']')
		print(file, "..")
		fmt.fprintf(file, " +%d", backing_size - 1)
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
		if has_overwrite {print(file, overwrite); return}
		please_use_help_attr(ti.id)
	}
}
