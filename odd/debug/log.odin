package odd_debug

import "core:log"

when ODIN_DEBUG {
	LOGGER_OPT :: log.Options{.Level, .Terminal_Color, .Short_File_Path, .Line}
} else {
	LOGGER_OPT :: log.Options{.Level, .Terminal_Color}
}

short_level_header :: #force_inline proc() {
	log.Level_Headers = {
		0 ..< 10 = "debug: ",
		10 ..< 20 = "info: ",
		20 ..< 30 = "warning: ",
		30 ..< 40 = "error: ",
		40 ..< 50 = "fatal: ",
	}
}
