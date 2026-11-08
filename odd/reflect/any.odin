package odd_reflect

any_to :: #force_inline proc "contextless" (
	arg: any,
	$T: typeid,
	loc := #caller_location,
) -> (
	T,
	bool,
) {
	return (cast(^T)arg.data)^, arg.id == T
}
