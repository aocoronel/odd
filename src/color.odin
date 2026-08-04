package odd

// Instead of giving an entire color palette, this only provides colors that are used by the TTY.
// The reason is, because each user has their own theme and taste on colors, so why should we force
// them to see a certain shade of green, if we can just let them see the green color they like?

TTY_COLOR :: #config(TTY_COLOR, false)

when TTY_COLOR {
	RESET :: ""
	BOLD :: ""
	UNDERLINE :: ""
	BOLD_UNDERLINE :: ""
	BLACK :: ""
	RED :: ""
	GREEN :: ""
	YELLOW :: ""
	BLUE :: ""
	MAGENTA :: ""
	CYAN :: ""
	WHITE :: ""
	BLACK_BRIGHT :: ""
	RED_BRIGHT :: ""
	GREEN_BRIGHT :: ""
	YELLOW_BRIGHT :: ""
	BLUE_BRIGHT :: ""
	MAGENTA_BRIGHT :: ""
	CYAN_BRIGHT :: ""
	WHITE_BRIGHT :: ""
} else {
	RESET :: "\x1b[0m"
	BOLD :: "\x1b[1m"
	UNDERLINE :: "\x1b[4m"
	BOLD_UNDERLINE :: "\x1b[1;4m"
	BLACK :: "\x1b[30m"
	RED :: "\x1b[31m"
	GREEN :: "\x1b[32m"
	YELLOW :: "\x1b[33m"
	BLUE :: "\x1b[34m"
	MAGENTA :: "\x1b[35m"
	CYAN :: "\x1b[36m"
	WHITE :: "\x1b[37m"
	BLACK_BRIGHT :: "\x1b[90m"
	RED_BRIGHT :: "\x1b[91m"
	GREEN_BRIGHT :: "\x1b[92m"
	YELLOW_BRIGHT :: "\x1b[93m"
	BLUE_BRIGHT :: "\x1b[94m"
	MAGENTA_BRIGHT :: "\x1b[95m"
	CYAN_BRIGHT :: "\x1b[96m"
	WHITE_BRIGHT :: "\x1b[97m"
}
