package array_ninja

ResultCode :: enum {
    Success =0, 
    AllocationError,
    BadType,
}

Result :: struct  {
    code: ResultCode,
    description: string,
}

