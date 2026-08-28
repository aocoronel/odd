package example

import "core:fmt"

print :: fmt.println

main :: proc() {
	print("Running pipe()")
	pipe()
	print("Running thread()")
	thread()
}
