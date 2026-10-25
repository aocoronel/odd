package odd_encoding

import "core:strings"

/*
Parses a string containing comma separated values (CSV): "tag1,tag2"
*/
csv :: proc(s: string) -> (string, int, bool) {
	comma := strings.index_rune(s, ',')
	if comma == -1 {
		return strings.trim(s, " "), comma, true
	} else {
		return strings.trim(s[:comma], " "), comma, false
	}
}
