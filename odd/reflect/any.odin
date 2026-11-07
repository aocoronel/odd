package odd_reflect

import "core:fmt"

any_to :: #force_inline proc(arg: any, $T: typeid, loc := #caller_location) -> T {
	if arg.id != T {
		fmt.panicf("expected type %q, got %q", typeid_of(T), arg.id, location = loc)
	}
	return (cast(^T)arg.data)^
}
