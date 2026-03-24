package array_ninja

import "core:mem"

ResultCode :: enum {
    Success =0, 
    AllocationError,
    BadType,
}

Result :: struct  {
    code: ResultCode,
    description: string,
}

MyError :: enum byte {
    None = 0,
    Array_Layer_Data_Type_Must_Be_Union = 1,
}

Error :: union {
    MyError,
    mem.Allocator_Error
}
