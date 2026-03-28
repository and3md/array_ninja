package array_ninja

import "core:math"
import k2 "libs/karl2d"

rect_draw :: proc(rect: Rect, color: Color) {
	k2.draw_rect(rect, color)
}

rect_draw_ex :: proc(rect: Rect, rotation: f32, color: Color) {
	k2.draw_rect_ex(rect, {0, 0}, rotation, color)
}

rect_outline_draw :: proc(rect: Rect, color: Color) {
	k2.draw_rect_outline(rect, 1, color)
}

rect_merge :: proc(rect1, rect2: Rect) -> (result: Rect) {
	r1x2 := rect1.x + rect1.w
	r1y2 := rect1.y + rect1.h
	r2x2 := rect2.x + rect2.w
	r2y2 := rect2.y + rect2.h
	result.x = math.min(rect1.x, rect2.x)
	result.y = math.min(rect1.y, rect2.y)

	result.w = math.max(r1x2, r2x2) - result.x
	result.h = math.max(r1y2, r2y2) - result.y
	return
}
