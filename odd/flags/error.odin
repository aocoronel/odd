package odd_flags

assert_type :: proc(curr, expected: typeid, loc := #caller_location) {
	when ODIN_DEBUG {
		if curr != expected {
			panicf("%s: expected %q, but got %q.", optopt, expected, curr, loc = loc)
		}
	}
}

invalid_value :: #force_inline proc(type, input, suggestion: string, loc := #caller_location) {
	errorf("%s: received an invalid %s: %q. %s", optopt, type, input, suggestion, location = loc)
}

missing_value :: #force_inline proc(loc := #caller_location) {
	errorf("%s: requires a value.", optopt, location = loc)
}

/*
To don't discourage the user, all types that this library is not willing to
support, we leave to the user to implement it.
Things like rawptr is not really doable, but the user may have a use case,
that they can implement with the specificity of their programs.
*/
please_use_custom_proc :: #force_inline proc(id: typeid) -> ! {
	panicf("%s: Please, use a custom procedure to parse %v.", optopt, id)
}

/*
Types that takes any number of arguments, until a certain limit:
enumerated array, fixed capacity dynamic array and bit sets.
*/
too_many_args :: #force_inline proc(max, got: int) -> bool {
	if max < got {
		errorf(
			"%s: too many arguments. Expected a maximum of %d, but exceeded %d.",
			optopt,
			max,
			got - max,
		)
		optind += got
		return false
	}
	return true
}

/*
Types that need a certain amount of arguments. If there is more arguments, we
parse them in the next parse() iteration.
*/
missing_args :: #force_inline proc(max, got: int) -> bool {
	if max > got {
		errorf("%s: %d values are missing.", optopt, max - got)
		optind += got
		return false
	}
	return true
}
