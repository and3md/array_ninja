package array_ninja

import k2 "libs/karl2d"

Engine :: struct {}


engine_init :: proc(
	screen_width: int,
	screen_height: int,
	window_title: string,
	window_mode: Window_Mode = Window_Mode.Windowed,
) {

	k2.init(screen_width, screen_height, window_title, k2.Init_Options{window_mode = window_mode})
}

engine_shutdown :: proc() {
	k2.shutdown()
}

engine_update :: proc() -> bool {
	return k2.update()
}

engine_clear_screen :: proc(color: Color) {
	k2.clear(color)
}

engine_present :: proc() {
	k2.present()
}

engine_delta_time :: proc() -> f32 {
	return k2.get_frame_time()
}