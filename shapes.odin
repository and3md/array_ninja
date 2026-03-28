package array_ninja


import k2 "libs/karl2d"

rect_draw :: proc(rect: Rect, color: Color) {
	k2.draw_rect(rect, color)
}

rect_draw_ex :: proc(rect: Rect, rotation: f32, color: Color) {
	k2.draw_rect_ex(rect, {0,0}, rotation, color)
}

rect_outline_draw :: proc(rect: Rect, color: Color) {
	k2.draw_rect_outline(rect, 1, color)
}
