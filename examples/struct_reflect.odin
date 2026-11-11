package example

import "base:intrinsics"
import "core:reflect"

Struct_Layout :: struct {
	size:         int,
	internal_pad: int,
	trailing_pad: int,
	total_pad:    int,
}

calculate_layout :: proc(fields: #soa[]reflect.Struct_Field) -> Struct_Layout {
	result: Struct_Layout

	offset := 0
	max_align := 1

	for field in fields {
		field_size := int(field.type.size)
		field_align := int(field.type.align)

		if field_align > max_align {
			max_align = field_align
		}

		aligned_offset := (offset + field_align - 1) / field_align * field_align

		result.internal_pad += aligned_offset - offset
		offset = aligned_offset + field_size
	}

	final_size := (offset + max_align - 1) / max_align * max_align

	result.trailing_pad = final_size - offset
	result.total_pad = result.internal_pad + result.trailing_pad
	result.size = final_size

	return result
}

sort_fields_for_layout :: proc(fields: #soa[]reflect.Struct_Field) -> #soa[]reflect.Struct_Field {
	result := make(#soa[]reflect.Struct_Field, len(fields))

	for i in 0 ..< len(fields) {
		result[i] = fields[i]
	}

	for i in 1 ..< len(result) {
		current := result[i]
		j := i

		for j > 0 {
			previous := result[j - 1]

			should_swap :=
				current.type.align > previous.type.align ||
				(current.type.align == previous.type.align &&
						current.type.size > previous.type.size)

			if !should_swap {
				break
			}

			result[j] = previous
			j -= 1
		}

		result[j] = current
	}

	return result
}

print_struct_info :: proc($T: typeid) where intrinsics.type_is_struct(T) {
	fields := reflect.struct_fields_zipped(T)

	struct_size := size_of(T)
	struct_align := align_of(T)

	fmt.printf(
		" %s  --  size: %d         align: %d         pow2: %d\n",
		fmt.tprintf("%v", typeid_of(T)),
		struct_size,
		struct_align,
		math.next_power_of_two(struct_size),
	)
	fmt.println(
		" ─────────────────────────────────────────────────────",
	)
	fmt.println("   offset    size    align    field                  type         ")
	fmt.println()

	is_terminal := terminal.is_terminal(os.stdout)

	printf :: proc(is_terminal: bool, color: string, msg: string, args: ..any) {
		COLOR_RESET :: ansi.CSI + ansi.RESET + ansi.SGR
		if is_terminal { fmt.print(color) }
		fmt.printf(msg, ..args)
		if is_terminal { fmt.print(COLOR_RESET) }
	}

	COLOR_RED :: ansi.CSI + ansi.FG_RED + ansi.SGR
	COLOR_GREEN :: ansi.CSI + ansi.FG_GREEN + ansi.SGR

	has_warn := false

	need_change: [dynamic]string

	for field, i in fields {
		type_name := fmt.tprintf("%v", field.type.id)

		next_field := fields[min(i + 1, len(fields) - 1)]
		warn: bool = next_field.type.align > field.type.align

		if warn {
			has_warn = true
			append(&need_change, field.name)
			printf(
				is_terminal,
				COLOR_RED,
				"- %6d   %6d   %6d   %-20s   %-11s  \n",
				field.offset,
				field.type.size,
				field.type.align,
				field.name,
				type_name,
			)
		} else {
			fmt.printf(
				"  %6d   %6d   %6d   %-20s   %-11s  \n",
				field.offset,
				field.type.size,
				field.type.align,
				field.name,
				type_name,
			)
		}
	}

	fmt.println()

	original := calculate_layout(fields)

	optimized_fields := sort_fields_for_layout(fields)
	optimized := calculate_layout(optimized_fields)

	if optimized.size < original.size || has_warn {
		saved := original.size - optimized.size

		printf(is_terminal, COLOR_GREEN, "+ Optimizable\n")

		fmt.printf("   size:      %d bytes ", optimized.size)
		printf(is_terminal, COLOR_GREEN, "(-%d bytes)\n", saved)
		fmt.printf(
			"   padding:   %d bytes (%.1f%%)\n",
			optimized.total_pad,
			f64(optimized.total_pad) / f64(optimized.size) * 100,
		)
		fmt.println(
			"  ─────────────────────────────────────────────────────",
		)

		offset := 0

		fmt.println("  offset    size    align    field                  type         ")
		fmt.println()

		for field, i in optimized_fields {
			type_name := fmt.tprintf("%v", field.type.id)

			align := field.type.align

			aligned_offset := (offset + align - 1) / align * align
			padding := aligned_offset - offset

			if padding > 0 {
				fmt.printf("  %6d   %6d            _padding_: [%d]u8\n", offset, padding, padding)
			}

			warn: bool
			for f in need_change {
				if field.name == f {
					warn = true
				}
			}

			if warn {
				printf(
					is_terminal,
					COLOR_GREEN,
					"+ %6d   %6d   %6d   %-20s   %-11s  \n",
					aligned_offset,
					field.type.size,
					align,
					field.name,
					type_name,
				)
			} else {
				fmt.printf(
					"  %6d   %6d   %6d   %-20s   %-11s  \n",
					aligned_offset,
					field.type.size,
					align,
					field.name,
					type_name,
				)
			}

			offset = aligned_offset + field.type.size
		}

		final_offset := (offset + struct_align - 1) / struct_align * struct_align
		trailing_padding := final_offset - offset

		if trailing_padding > 0 {
			fmt.printf(
				"* %6d   %6d   %6d   %-20s   %-11s  \n",
				offset,
				trailing_padding,
				1,
				"__padding",
				fmt.tprintf("[%d]u8", trailing_padding),
			)
		}
	}
}
