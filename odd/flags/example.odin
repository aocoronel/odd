#+ignore

package odd_flags

import "core:log"

main :: proc() {
	Enum :: enum {
		Ok,
		Maybe_Ok,
		Not_Ok,
	}

	// Suggestion: create a struct, so you can pass all the state at once
	Options :: struct {
		simd:            #simd[4]f64,
		verbose:         bool,
		debug:           b8,
		times:           int,
		user:            struct {
			name:    string,
			enabled: bool,
		},
		priority:        bit_set['A' ..= 'Z';[4]u64],
		ok_level:        Enum,
		io:              [2]string,
		vaargs:          [dynamic]cstring,
		files:           [dynamic; 4]string,
		ok_level_string: [Enum]string,
	}

	opts: Options

	Commands :: struct {
		run: [dynamic]string,
	}
	cmds: Commands

	// Don't forget to create a logger. The library depends on it to report errors.
	context.logger = log.create_console_logger(opt = {.Level})
	defer log.destroy_console_logger(context.logger)

	// This makes the API boring, but allows better extensibility
	opt := []Option {
		// short flag is 1 letter
		{name = "v,verbose", var = &opts.verbose, help = `Enables verbosity`},
		{
			name = "square",
			var  = &opts.simd,
			// Help attributes. Affects usage()
			help = `#arg=height width posx posy,force
			A very long help message
			in case it is needed for some reason`,
		},
		// You can set the "fn" field, to skip most RTTI
		{name = "debug", var = &opts.debug, fn = get_bool, help = `Enable debugging info`},
		{name = "times", var = &opts.times, help = `Number of times to repeat`},
		{name = "user", var = &opts.user, help = `Enable/disable user`},
		{name = "priority", var = &opts.priority, help = `Priority level`},
		{name = "ok_level", var = &opts.ok_level, help = `How ok are you?`},
		{name = "io", var = &opts.io, help = `#arg=FILE
        Source file and destination`},
		{name = "vaargs", var = &opts.vaargs, help = "Many files"},
		{name = "files", var = &opts.files, help = `Parse files`},
		{name = "ok_level_string", var = &opts.ok_level_string, help = `Explain how ok are you`},
	}

    cmd := []Option{{"run", "Run a command", &cmds.run, nil}}

	// Initialize the map
	m, ok := init(opt)
	defer delete(m)

	if !ok do return

	// This parses all arguments, independently if they fail or not.
	// If there are errors, it reports the error, and continue parsing the rest.
	// The user can cancel a flag by prefixing it with '/', like --/square.
	// In case of "-/vd", both 'v' and 'd' are cancelled.
	has_err: bool
	for has_args_left() {
		err := parse(m, opt)
		switch err {
		case .Ok:
			continue
		case .Dash_Dash:
		// You can opt-in to stop parsing and collect the rest of the arguments:
		// rest := get_args()[optind:]
		case .Help_Request:
			// Print the help your way, and/or use the convenient usage()
			usage(opt)
			return
		case .Not_Opt:
            // Positional arguments
            // Here is an example of how to use the same odd/flags
            // infrastructure to parse commands
			for c, i in cmd {
				if c.name == optopt {
					call(cmd, cast(u32)i + 1, false)
				}
			}
		// positional arguments
		case .Error:
			has_err = true
		}
	}
	if has_err do return
}
