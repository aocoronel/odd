package odd_debug

import "core:log"
import "shared:odd/thread"

when ODIN_DEBUG {
	when thread.THREAD {
		LOGGER_OPT :: log.Options{.Level, .Terminal_Color, .Short_File_Path, .Line, .Thread_Id}
	} else {
		LOGGER_OPT :: log.Options{.Level, .Terminal_Color, .Short_File_Path, .Line}
	}
} else {
	when thread.THREAD {
		LOGGER_OPT :: log.Options{.Level, .Terminal_Color, .Thread_Id}
	} else {
		LOGGER_OPT :: log.Options{.Level, .Terminal_Color}
	}
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
