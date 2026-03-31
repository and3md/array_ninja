package array_ninja

import "core:mem"

MyError :: enum byte {
    Array_Layer_Data_Type_Must_Be_Union = 1,
    Animation_Not_Found,
}

Error :: union {
    MyError,
    mem.Allocator_Error
}
