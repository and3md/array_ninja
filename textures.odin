package array_ninja

import k2 "libs/karl2d"

tex_load_from_file :: proc(filename: string) -> Texture {
	return k2.load_texture_from_file(filename)
}

tex_load_from_bytes :: proc(bytes: []u8) -> Texture {
	return k2.load_texture_from_bytes(bytes)
}

tex_free :: proc(tex: Texture) {
	k2.destroy_texture(tex)
}

tex_draw :: proc(tex: Texture, pos: Vec2, tint: Color = WHITE) 
{
    k2.draw_texture(tex, pos, tint)
}

// rotation - radians
tex_draw_ex :: proc(tex: Texture, src: Rect, dst: Rect, rotation: f32, tint: Color = WHITE) 
{
	k2.draw_texture_ex(tex, src, dst, {0,0}, rotation, tint)
}