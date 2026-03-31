package array_ninja

import "base:intrinsics"
import hm "core:container/handle_map"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:reflect"

LAYER_DEFAULT_CAPACITY :: 1000

/*
	Visible also exists,
	Invisible can exists (update will be called)
	Invisible non exists (update will not be called)
*/
ArrayElementState :: enum byte {
	Visible,
	Invisible_Existing,
	Invisible_Nonexisting,
}

ArrayElement :: struct($T: typeid) {
	data_union:   T,
	child_matrix: linalg.Matrix3f32, // matrix for this element, not parent
	id:           PersistentId,
	child_level:  ChildLevel,
	state:        ArrayElementState,
}

ArrayLayerState :: enum byte {
	Dirty,
	Clean,
}

Handle :: hm.Handle64
AnimationHandle :: distinct Handle

Animation :: struct {
	tex:        Texture,
	frames:     []int,
	frame_rate: f32,
	frame_w:    int,
	frame_h:    int,
	handle:     AnimationHandle,
}


/*
Array layer is a "flat union hierachy" based on child_level as child flag

*/
ArrayLayer :: struct($T: typeid) {
	arr:            [dynamic]ArrayElement(T),
	persistent_ids: [dynamic]int,
	state:          ArrayLayerState,
	animations:     hm.Dynamic_Handle_Map(Animation, AnimationHandle),
}


PersistentId :: distinct u32
ChildLevel :: distinct u8

ArrayTransform :: struct {
	x, y:     f32,
	scale:    f32,
	rotation: f32, // in degrees
	origin:   Vec2,
}

Square :: struct {
	w, h:  f32,
	color: Color,
}

Sprite :: struct {
	tex:  Texture,
	tint: Color,
}

AnimatedSprite :: struct {
	animation:     AnimationHandle,
	tint:          Color,
	timer:         f32,
	current_frame: int,
	looped:        bool,
	finished:      bool,
}

layer_create :: proc($T: typeid) -> (new_layer: ^ArrayLayer(T), err: Error) {
	if !intrinsics.type_is_union(T) {
		return nil, MyError.Array_Layer_Data_Type_Must_Be_Union
	}
	layer := new(ArrayLayer(T)) or_return
	new_layer = layer
	defer if err != nil {
		free(new_layer)
		new_layer = nil
	}
	new_layer.state = .Dirty

	hm.dynamic_init(&new_layer.animations, context.allocator)

	return new_layer, nil
}

layer_free :: proc(layer: ^ArrayLayer($T)) {
	hm.dynamic_destroy(&layer.animations)
	delete(layer.arr)
	delete(layer.persistent_ids)
	free(layer)
}

layer_add_element :: proc(
	layer: ^ArrayLayer($T),
	element: T,
	child_level: ChildLevel = 0,
) -> (
	id: PersistentId,
	err: Error,
) {
	layer.state = .Dirty
	append(&layer.arr, ArrayElement(T){id = 2, child_level = 1, data_union = element}) or_return
	arr_index := len(layer.arr) - 1

	append(&layer.persistent_ids, arr_index) or_return
	id = cast(PersistentId)len(layer.persistent_ids) - 1
	element := layer_get_element_by_index(layer, arr_index)
	element.child_level = child_level
	element.id = id
	fmt.printfln("id: %d, value : %v", id, element)
	return id, nil
}

layer_add_sibling_element :: proc(
	layer: ^ArrayLayer($T),
	element: T,
) -> (
	id: PersistentId,
	err: Error,
) {
	child_level: ChildLevel
	arr_len := len(layer.arr)
	if arr_len == 0 {
		child_level = 0
	} else {
		prev_element := layer.arr[arr_len - 1]
		child_level = prev_element.child_level
	}

	return layer_add_element(layer, element, child_level)
}

layer_add_child_element :: proc(
	layer: ^ArrayLayer($T),
	element: T,
) -> (
	id: PersistentId,
	err: Error,
) {
	child_level: ChildLevel
	arr_len := len(layer.arr)
	if arr_len == 0 {
		child_level = 0
	} else {
		prev_element := layer.arr[arr_len - 1]
		child_level = prev_element.child_level + 1
	}

	return layer_add_element(layer, element, child_level)
}

layer_add_ancestor_element :: proc(
	layer: ^ArrayLayer($T),
	element: T,
) -> (
	id: PersistentId,
	err: Error,
) {
	ancestor_level: ChildLevel
	arr_len := len(layer.arr)
	if arr_len == 0 {
		ancestor_level = 0
	} else {
		prev_element := layer.arr[arr_len - 1]
		ancestor_level = math.max(prev_element.child_level - 1, 0)
	}
	return layer_add_element(layer, element, ancestor_level)
}

/*
Delete element with children
*/
layer_delete_element :: proc(layer: ^ArrayLayer($T), id: PersistentId) {
	index := layer.persistent_ids[id]
	last_index := layer_last_child_index(layer, index)

	layer_delete_elements_range_by_indexes(layer, index, last_index)
}

layer_delete_elements_range_by_indexes :: proc(
	layer: ^ArrayLayer($T),
	start_index, end_index: int,
) {
	layer.state = .Dirty
	for i in 0 ..= end_index - start_index {
		ordered_remove(&layer.arr, start_index)
	}

	if len(layer.arr) > start_index {
		// update persistent id's
		for i in start_index ..< len(layer.arr) {
			element := &layer.arr[i]
			layer.persistent_ids[element.id] = i
		}
	}
}

/*
Detach element with children
*/
layer_detach_element :: proc(
	layer: ^ArrayLayer($T),
	id: PersistentId,
) -> (
	detached_elements: [dynamic]ArrayElement(T),
) {
	index := layer.persistent_ids[id]
	last_index := layer_last_child_index(layer, index)

	detached_elements = make([dynamic]ArrayElement(T), last_index - index + 1)
	copy(detached_elements[:], layer.arr[index:last_index + 1])
	layer_delete_elements_range_by_indexes(layer, index, last_index)
	return detached_elements
}

/*
Gets all parents ids of element with given id
*/
layer_get_parents_ids :: proc(
	layer: ^ArrayLayer($T),
	id: PersistentId,
) -> (
	parents: [dynamic]PersistentId,
) {
	index := layer.persistent_ids[id]
	current_child_level := layer.arr[index].child_level
	if index == 0 || current_child_level == 0 {
		return nil
	}
	i := index - 1
	for i > -1 {
		element := &layer.arr[i]
		if element.child_level < current_child_level {
			current_child_level = element.child_level
			append(&parents, element.id)
			if element.child_level == 0 {
				break
			}
		}
		i -= 1
	}
	return parents
}

/*
Checks all parents visibility to infer the final visibility of an element
*/
layers_element_visible :: proc(layer: ^ArrayLayer($T), id: PersistentId) -> bool {
	index := layer.persistent_ids[id]
	current_child_level := layer.arr[index].child_level
	if layer.arr[index].state != .Visible {
		return false
	}
	if index == 0 || current_child_level == 0 {
		return layer.arr[index].state == .Visible
	}
	i := index - 1
	for i > -1 {
		element := &layer.arr[i]
		if element.child_level < current_child_level {
			// we found a parent of element
			current_child_level = element.child_level
			if element.state != .Visible {
				return false
			}
			if element.child_level == 0 {
				break
			}
		}
		i -= 1
	}
	return true
}

/*
Checks all parents existence to infer the final existence of an element
*/
layers_element_exists :: proc(layer: ^ArrayLayer($T), id: PersistentId) -> bool {
	index := layer.persistent_ids[id]
	current_child_level := layer.arr[index].child_level
	if layer.arr[index].state == .Invisible_Nonexisting {
		return false
	}
	if index == 0 || current_child_level == 0 {
		return layer.arr[index].state == .Visible || layer.arr[index].state == .Invisible_Existing
	}
	i := index - 1
	for i > -1 {
		element := &layer.arr[i]
		if element.child_level < current_child_level {
			// we found a parent of element
			current_child_level = element.child_level
			if element.state == .Invisible_Nonexisting {
				return false
			}
			if element.child_level == 0 {
				break
			}
		}
		i -= 1
	}
	return true
}


/*
Returns last child index of element with given index
*/
layer_last_child_index :: proc(layer: ^ArrayLayer($T), index: int) -> int {
	parent := layer_get_element_by_index(layer, index)
	parent_child_level := parent.child_level
	last_child_index := index

	i := index + 1
	for i < len(layer.arr) {
		element := &layer.arr[i]
		if element.child_level <= parent_child_level {
			break
		} else {
			last_child_index = i
		}
		i += 1
	}
	return last_child_index
}

layer_get_current_index_from_id :: proc(layer: ^ArrayLayer($T), id: PersistentId) -> int {
	return layer.persistent_ids[id]
}

/*
Gets element by index.
Be careful, the returned pointer may change, in the future do not save it for later usage
Only made changes and forget about it. 
*/
layer_get_element_by_id :: proc(layer: ^ArrayLayer($T), id: PersistentId) -> ^ArrayElement(T) {
	return &layer.arr[layer.persistent_ids[id]]
}

/*
Gets element by index.
Be careful, the returned pointer may change, in the future do not save it for later usage
Only made changes and forget about it. 
*/
layer_get_element_by_index :: proc(layer: ^ArrayLayer($T), index: int) -> ^ArrayElement(T) {
	return &layer.arr[index]
}

layer_get_element_global_pos :: proc(layer: ^ArrayLayer($T), id: PersistentId) -> Vec2 {
	mat := &layer.arr[layer.persistent_ids[id]].child_matrix
	fmt.printfln("%#v", mat^)
	return {mat[2, 0], mat[2, 1]}
}

layer_get_element_global_rotation_rad :: proc(layer: ^ArrayLayer($T), id: PersistentId) -> f32 {
	mat := &layer.arr[layer.persistent_ids[id]].child_matrix
	return math.atan2(mat[0, 1], mat[0, 0])
}

layer_get_element_global_scale :: proc(
	layer: ^ArrayLayer($T),
	id: PersistentId,
) -> (
	scale_x, scale_y: f32,
) {
	mat := &layer.arr[layer.persistent_ids[id]].child_matrix
	scale_x = linalg.length(linalg.Vector2f32{mat[0, 0], mat[0, 1]})
	scale_y = linalg.length(linalg.Vector2f32{mat[1, 0], mat[1, 1]})
	return
}

layer_get_element_global_bounding_box :: proc(layer: ^ArrayLayer($T), id: PersistentId) -> Rect {
	element := &layer.arr[layer.persistent_ids[id]]
	mat := &element.child_matrix

	vec1 := linalg.Vector3f32{0, 0, 1}
	world_vec1 := vec1 * mat^

	rect_from_points :: proc(
		mat: ^linalg.Matrix3x3f32,
		world_p1, p2, p3, p4: linalg.Vector3f32,
	) -> Rect {
		world_p2 := p2 * mat^
		world_p3 := p3 * mat^
		world_p4 := p4 * mat^

		min_x := math.min(world_p1.x, world_p2.x, world_p3.x, world_p4.x)
		max_x := math.max(world_p1.x, world_p2.x, world_p3.x, world_p4.x)
		min_y := math.min(world_p1.y, world_p2.y, world_p3.y, world_p4.y)
		max_y := math.max(world_p1.y, world_p2.y, world_p3.y, world_p4.y)
		return {min_x, min_y, max_x - min_x, max_y - min_y}
	}

	when intrinsics.type_is_variant_of(T, Sprite) {
		if reflect.union_variant_typeid(element.data_union) == typeid_of(Sprite) {
			sprite := element.data_union.(Sprite)
			return rect_from_points(
				mat,
				world_vec1,
				{cast(f32)sprite.tex.width, 0, 1},
				{cast(f32)sprite.tex.width, cast(f32)sprite.tex.height, 1},
				{0, cast(f32)sprite.tex.height, 1},
			)
		}
	}

	when intrinsics.type_is_variant_of(T, Square) {
		if reflect.union_variant_typeid(element.data_union) == typeid_of(Square) {
			square := element.data_union.(Square)

			return rect_from_points(
				mat,
				world_vec1,
				{cast(f32)square.w, 0, 1},
				{cast(f32)square.w, cast(f32)square.h, 1},
				{0, cast(f32)square.h, 1},
			)
		}
	}

	return {world_vec1.x, world_vec1.y, 0, 0}
}

layer_get_element_with_children_global_bounding_box :: proc(
	layer: ^ArrayLayer($T),
	id: PersistentId,
) -> Rect {
	parent_index := layer.persistent_ids[id]
	parent := &layer.arr[parent_index]
	rect := layer_get_element_global_bounding_box(layer, id)

	i := parent_index + 1
	for i < len(layer.arr) {
		element := &layer.arr[i]
		if element.child_level <= parent.child_level {
			break
		}
		fmt.printfln("rect przed: %v", rect)
		fmt.printfln(
			"rect do dodania: %v",
			layer_get_element_global_bounding_box(layer, element.id),
		)
		rect = rect_merge(rect, layer_get_element_global_bounding_box(layer, element.id))
		fmt.printfln("rect po: %v", rect)
		i += 1
	}
	return rect
}


layer_draw_element_global_bounding_box :: proc(layer: ^ArrayLayer($T), id: PersistentId) {
	rect := layer_get_element_global_bounding_box(layer, id)
	rect_outline_draw(rect, YELLOW)
}

layer_update_transforms :: proc(layer: ^ArrayLayer($T)) {
	if layer.state == .Clean do return
	child_level_matrix := make([dynamic]linalg.Matrix3f32)
	defer delete(child_level_matrix)
	// Identity Matrix in Odin = Matrix3f32(1.0)
	// child level 0 has always identity matrix
	append(&child_level_matrix, linalg.Matrix3f32(1.0))

	for &element in layer.arr {
		// transform support
		if reflect.union_variant_typeid(element.data_union) == typeid_of(ArrayTransform) {
			transform := element.data_union.(ArrayTransform)

			m := linalg.Matrix3f32(1.0)
			// added origin
			m[2, 0] -= transform.origin.x
			m[2, 1] -= transform.origin.y

			// {0,0,-1} is axis of rotation
			m =
				m *
				linalg.matrix3_rotate_f32(linalg.to_radians(transform.rotation), {0, 0, -1}) *
				linalg.matrix3_scale_f32({transform.scale, transform.scale, 1.0})

			m[2, 0] += transform.x + transform.origin.x
			m[2, 1] += transform.y + transform.origin.y

			element.child_matrix = m * child_level_matrix[element.child_level]
			// transform always adds matrix for its child_level + 1
			// every element gets matrix for his child level
			if cast(int)element.child_level + 1 >= len(child_level_matrix) {
				append(&child_level_matrix, element.child_matrix)
			} else {
				child_level_matrix[element.child_level + 1] = element.child_matrix
			}
		} else {
			element.child_matrix = child_level_matrix[element.child_level]
			if cast(int)element.child_level + 1 >= len(child_level_matrix) {
				append(&child_level_matrix, element.child_matrix)
			} else {
				child_level_matrix[element.child_level + 1] = element.child_matrix
			}
		}
	}
	layer.state = .Clean
}

layer_render :: proc(layer: ^ArrayLayer($T)) {
	for &element in layer.arr {

		// check user union type has type Sprite
		when intrinsics.type_is_variant_of(T, Sprite) {
			if reflect.union_variant_typeid(element.data_union) == typeid_of(Sprite) {
				sprite := element.data_union.(Sprite)
				x, y, angle, scale_x, scale_y := decompose_matrix(&element.child_matrix)
				tex_draw_ex(
					sprite.tex,
					{0, 0, cast(f32)sprite.tex.width, cast(f32)sprite.tex.height},
					Rect {
						x,
						y,
						cast(f32)sprite.tex.width * scale_x,
						cast(f32)sprite.tex.height * scale_y,
					},
					angle,
					sprite.tint,
				)
			}
		}

		when intrinsics.type_is_variant_of(T, Square) {
			if reflect.union_variant_typeid(element.data_union) == typeid_of(Square) {
				square := element.data_union.(Square)
				x, y, angle, scale_x, scale_y := decompose_matrix(&element.child_matrix)
				rect_draw_ex(
					Rect{x, y, square.w * scale_x, square.h * scale_y},
					angle,
					square.color,
				)
				continue
			}
		}
	}
}

log_transform_hierarchy :: proc(layer: ^ArrayLayer($T)) {
	fmt.printfln("------------------------------------------------------------------------")
	fmt.printfln("Transform hierarchy log:")
	for &element in layer.arr {
		when intrinsics.type_is_variant_of(T, ArrayTransform) {
			if reflect.union_variant_typeid(element.data_union) == typeid_of(ArrayTransform) {
				transform := element.data_union.(ArrayTransform)
				x, y, angle, scale_x, scale_y := decompose_matrix(&element.child_matrix)
				fmt.printfln(
					"%*s% 3d - %s - %f, %f rot: %f , scale: %f",
					element.child_level * 2,
					"",
					element.child_level,
					"Transform",
					transform.x,
					transform.y,
					transform.rotation,
					transform.scale,
				)
				fmt.printfln(
					"%*s    - Global: %f, %f rot: %f , scale: %f",
					element.child_level * 2,
					"",
					x,
					y,
					math.to_degrees(angle),
					scale_x,
				)
			}
		}
	}
	fmt.printfln("------------------------------------------------------------------------")
}

log_full_hierarchy :: proc(layer: ^ArrayLayer($T)) {
	fmt.printfln("------------------------------------------------------------------------")
	fmt.printfln("Full hierarchy log:")
	for &element in layer.arr {
		x, y, angle, scale_x, scale_y := decompose_matrix(&element.child_matrix)
		when intrinsics.type_is_variant_of(T, ArrayTransform) {
			if reflect.union_variant_typeid(element.data_union) == typeid_of(ArrayTransform) {
				transform := element.data_union.(ArrayTransform)
				fmt.printfln(
					"%*s% 3d - %s - %f, %f rot: %f , scale: %f",
					element.child_level * 2,
					"",
					element.child_level,
					"Transform",
					transform.x,
					transform.y,
					transform.rotation,
					transform.scale,
				)
			}
		}
		when intrinsics.type_is_variant_of(T, Sprite) {
			if reflect.union_variant_typeid(element.data_union) == typeid_of(Sprite) {
				sprite := element.data_union.(Sprite)
				fmt.printfln(
					"%*s% 3d - %s - w: %d, h: %d  tint: %v",
					element.child_level * 2,
					"",
					element.child_level,
					"Sprite",
					sprite.tex.width,
					sprite.tex.height,
					sprite.tint,
				)
			}
		}

		when intrinsics.type_is_variant_of(T, Square) {
			if reflect.union_variant_typeid(element.data_union) == typeid_of(Square) {
				square := element.data_union.(Square)
				fmt.printfln(
					"%*s% 3d - %s - w: %f, h: %f color: %v",
					element.child_level * 2,
					"",
					element.child_level,
					"Square",
					square.w,
					square.h,
					square.color,
				)
			}
		}

		// Global data for all elements
		fmt.printfln(
			"%*s    - Global: %f, %f rot: %f , scale: %f",
			element.child_level * 2,
			"",
			x,
			y,
			math.to_degrees(angle),
			scale_x,
		)
	}
	fmt.printfln("------------------------------------------------------------------------")
}

decompose_matrix :: proc(mat: ^linalg.Matrix3f32) -> (x, y, angle, scale_x, scale_y: f32) {
	x = mat[2, 0]
	y = mat[2, 1]

	angle = math.atan2(mat[0, 1], mat[0, 0])

	scale_x = linalg.length(linalg.Vector2f32{mat[0, 0], mat[0, 1]})
	scale_y = linalg.length(linalg.Vector2f32{mat[1, 0], mat[1, 1]})
	//fmt.printfln("%f %f - %f rad, scale: %f %f", x, y, angle, scale_x, scale_y)
	return
}

is_union :: proc($T: typeid) -> bool {
	//return intrinsics.type_is_union(T)
	type_info := type_info_of(T)
	return reflect.is_union(type_info)
}

add_animation :: proc(
	layer: ^ArrayLayer($T),
	tex: Texture,
	frames: []int,
	frame_w, frame_h: int,
	frame_rate: f32 = 30,
) -> (
	anim_handle: AnimationHandle,
) {
	anim_handle = hm.dynamic_add(
		&layer.animations,
		Animation {
			tex = tex,
			frames = frames,
			frame_rate = frame_rate,
			frame_h = frame_h,
			frame_w = frame_w,
		},
	)
	return
}

get_animation :: proc(
	layer: ^ArrayLayer($T),
	anim_handle: AnimationHandle,
) -> (
	anim: ^Animation,
	err: Error,
) {
	ok: bool
	anim, ok = hm.dynamic_get(&layer.animations, anim_handle)
	if ok {
		return anim, nil
	} else {
		return nil, .Animation_Not_Found
	}
}
