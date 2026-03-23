package array_ninja

import "core:math"

is_zero :: proc(value: f32) -> bool {
    return math.abs(value) < math.F32_EPSILON
}