package odd_flags

import "base:runtime"
import "core:fmt"
import "core:log"

Type_Info :: runtime.Type_Info
Type_Info_Named :: runtime.Type_Info_Named
Type_Info_Integer :: runtime.Type_Info_Integer
Type_Info_Rune :: runtime.Type_Info_Rune
Type_Info_Float :: runtime.Type_Info_Float
Type_Info_Complex :: runtime.Type_Info_Complex
Type_Info_Quaternion :: runtime.Type_Info_Quaternion
Type_Info_String :: runtime.Type_Info_String
Type_Info_Boolean :: runtime.Type_Info_Boolean
Type_Info_Any :: runtime.Type_Info_Any
Type_Info_Type_Id :: runtime.Type_Info_Type_Id
Type_Info_Pointer :: runtime.Type_Info_Pointer
Type_Info_Multi_Pointer :: runtime.Type_Info_Multi_Pointer
Type_Info_Procedure :: runtime.Type_Info_Procedure
Type_Info_Array :: runtime.Type_Info_Array
Type_Info_Enumerated_Array :: runtime.Type_Info_Enumerated_Array
Type_Info_Dynamic_Array :: runtime.Type_Info_Dynamic_Array
Type_Info_Slice :: runtime.Type_Info_Slice
Type_Info_Parameters :: runtime.Type_Info_Parameters
Type_Info_Struct :: runtime.Type_Info_Struct
Type_Info_Union :: runtime.Type_Info_Union
Type_Info_Enum :: runtime.Type_Info_Enum
Type_Info_Map :: runtime.Type_Info_Map
Type_Info_Bit_Set :: runtime.Type_Info_Bit_Set
Type_Info_Simd_Vector :: runtime.Type_Info_Simd_Vector
Type_Info_Matrix :: runtime.Type_Info_Matrix
Type_Info_Soa_Pointer :: runtime.Type_Info_Soa_Pointer
Type_Info_Bit_Field :: runtime.Type_Info_Bit_Field
Type_Info_Fixed_Capacity_Dynamic_Array :: runtime.Type_Info_Fixed_Capacity_Dynamic_Array
Type_Info_Enum_Value :: runtime.Type_Info_Enum_Value

panicf :: fmt.panicf
errorf :: log.errorf

/*
Example:
  Use RTTI -> { flag = "v,verbose", help = "Enable verbosity", var = &verbose }
  No RTTI -> { flag = "v,verbose", help = "Enable verbosity", var = &verbose, fn = get_bool }
*/
Option :: struct {
	flag, help: string,
	var:        any,
	fn:         Get_Proc,
}

Result :: enum {
	Ok = 0,
	Error,
	Not_Opt,
	Dash_Dash,
	Help_Request,
}

Get_Proc :: #type proc(ptr: rawptr, id: typeid) -> bool

/*
-flag:value
*/
SEPARATOR :: #config(ODD_FLAGS_SEPARATOR, ':')
