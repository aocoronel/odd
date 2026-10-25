package odd_flags

import "base:runtime"
import "core:reflect"
import "core:strings"

optind: int = 1 // current option index (skip program)
optopt: string // current option
optarg: string // current argument
optval: string // -flag value

args__ := runtime.args__

/*
os.get_args allocates
*/
get_args :: proc "contextless" () -> []cstring {
	return args__
}

has_args_left :: #force_inline proc "contextless" () -> bool {
	return optind < len(get_args())
}

get_arg :: #force_inline proc "contextless" (i: int) -> (string, bool) #optional_ok {
	if !has_args_left() do return "", false
	return string(args__[i]), true
}

next_arg :: proc "contextless" () -> (arg: string, ok: bool) #no_bounds_check #optional_ok {
	arg = get_arg(optind) or_return
	optopt = arg
	optind += 1
	optarg = get_arg(optind)
	return arg, true
}

get_value :: proc "contextless" () -> (string, bool) {
	arg: string
	if len(optval) == 0 {
		if is_next_option() do return "", false
		optarg = get_arg(optind)
		arg = optarg
		optind += 1
		return arg, true
	}
	arg = optval
	optarg = arg
	optval = ""
	return arg, true
}

is_option :: #force_inline proc "contextless" (arg: string) -> bool {
	if len(arg) == 0 do return true
	return arg[0] == '-'
}

is_option_raw :: #force_inline proc "contextless" (arg: cstring) -> bool {
	if arg == nil do return true
	return (cast([^]u8)arg)[0] == '-'
}

is_next_option :: #force_inline proc "contextless" () -> bool {
	return is_option(optarg)
}

parse :: proc(m: map[string]int, opt: []Option) -> (err: Result) {

	shift :: #force_inline proc "contextless" (arg: string) -> (string, Result) #no_bounds_check {
		return arg[1:], cast(Result)(len(arg[1:]) == 0)
	}

	args, ok := next_arg()
	if !ok do return .Ok

	if args[0] != '-' do return .Not_Opt

	args = shift(args) or_return

	if args[0] != '-' { 	// short
		ignore: bool
		if args[0] == '/' {
			ignore = true
			args = shift(args) or_return
		}
		should_loop := true
		for should_loop {
			if len(args) > 1 && args[1] == SEPARATOR {
				should_loop = false
				optval = args[2:]
			} else {
				optval = ""
			}
			optopt = args[0:1]

			entry := m[optopt]
			if entry == 0 {
				errorf("%s: option does not exist", optopt)
				return .Error
			}
			if entry == -1 do return .Help_Request
			if !call(opt, entry, ignore) do return .Error
			args = shift(args) or_break
		}
	} else { 	// long
		args, err = shift(args)
		if err == .Error do return .Dash_Dash

		ignore: bool
		if args[0] == '/' {
			ignore = true
			args = shift(args) or_return
		}

		idx := strings.index_rune(args, SEPARATOR)
		if idx == -1 {
			optval = ""
		} else {
			optval = args[idx + 1:]
			args = args[:idx]
		}
		optopt = args

		entry := m[args]
		if entry == 0 {
			errorf("%s: option does not exist", optopt)
			return .Error
		}
		if entry == -1 do return .Help_Request
		if !call(opt, entry, ignore) do return .Error
	}

	return .Ok
}

call :: proc(opt: []Option, entry: int, ignore: bool) -> bool {
	idx := entry - 1
	fn := opt[idx].fn
	var := opt[idx].var

	if var == nil {
		errorf("%s: variable is not set", opt[idx].flag)
		return false
	}

	ti := type_base(var.id)
	#partial switch info in ti.variant {
	case runtime.Type_Info_Pointer:
	case:
		errorf("%s: variable must be a pointer, got: %v", opt[idx].flag, var.id)
		return false
	}

	dereferenced := reflect.deref(var)
	ptr, _ := reflect.as_pointer(var)

	if ignore do ptr = nil

	ok: bool
	if fn != nil {
		ok = fn(ptr, dereferenced.id)
	} else {
		ok = get_rtti(ptr, dereferenced.id)
	}

	return ok
}

init :: proc(opts: []Option) -> (m: map[string]int, ok: bool) {
	ok = true

	for opt, i in opts {
		long: string

		if len(opt.flag) > 2 && opt.flag[1] == ',' {
			long = opt.flag[2:]
			m[opt.flag[0:1]] = i + 1
		} else {
			long = opt.flag[:]
		}

		m[long] = i + 1

		// TBD: define NO_RTTI
		when false {
			if opt.fn == nil {
				errorf("%s: flag doesn't have a set function.", long)
				ok = false
			}
		}
	}

	// builtin
	m["h"] = -1
	m["help"] = -1

	return m, ok
}
