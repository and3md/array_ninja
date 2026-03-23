package array_ninja

import k2 "libs/karl2d"

font_load_from_file :: proc(filename: string) -> Font {
	return k2.load_font_from_file(filename)
}

font_load_from_bytes :: proc(bytes: []u8) -> Font {
	return k2.load_font_from_bytes(bytes)
}

font_free :: proc(font: Font) {
	k2.destroy_font(font)
}

text_draw :: proc(font: Font, text: string, pos: Vec2, font_size: f32, color: Color = WHITE) 
{
    k2.draw_text_ex(font, text, pos, font_size, color)
}

