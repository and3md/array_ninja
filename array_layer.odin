package array_ninja

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:reflect"

LAYER_DEFAULT_CAPACITY :: 1000

ArrayElement :: struct($T: typeid) {
	id:          PersistentId,
	child_level: ChildLevel,
	data_union:  T,
}

/*
Array layer is a "flat union hierachy" based on child_level as child flag

*/
ArrayLayer :: struct($T: typeid) {
	arr:            [dynamic]ArrayElement(T),
	persistent_ids: [dynamic]int,
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

	return new_layer, nil
}

layer_free :: proc(layer: ^ArrayLayer($T)) {
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
	append(
		&layer.arr,
		ArrayElement(T){id = 2, child_level = 1, data_union = element},
	) or_return
	arr_index := len(layer.arr) - 1

	append(&layer.persistent_ids, arr_index) or_return
	id = cast(PersistentId)len(layer.persistent_ids) - 1
	element := layer_get_element_by_index(layer, arr_index)
	element.child_level = child_level
	element.id = id
	fmt.printfln("id: %d, value : %v",id, element)
	return id, nil
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

layer_render :: proc(layer: ^ArrayLayer($T)) {
	//child_level_matrix := make([dynamic]linalg.Matrix3f32)
	// Identity Matrix in Odin = Matrix3f32(1.0)
	//append(&child_level_matrix, linalg.Matrix3f32(1.0))
	world_matrix := linalg.Matrix3f32(1.0)
	last_child_level: ChildLevel = 0

	for &element in layer.arr {
		if element.child_level != last_child_level {
			last_child_level = element.child_level
		}

		if reflect.union_variant_typeid(element.data_union) == typeid_of(Square) {
			square := element.data_union.(Square)
			x := world_matrix[2, 0]
			y := world_matrix[2, 1]

			angle := math.atan2(world_matrix[0, 1], world_matrix[0, 0])

			scale_x := linalg.length(linalg.Vector2f32{world_matrix[0, 0], world_matrix[0, 1]})
			scale_y := linalg.length(linalg.Vector2f32{world_matrix[1, 0], world_matrix[1, 1]})

			//fmt.printfln("%f %f - %f rad, scale: %f %f", x, y, angle, scale_x, scale_y)

			rect_draw_ex(Rect{x, y, square.w * scale_x, square.h * scale_y}, angle, square.color)
		}
		if reflect.union_variant_typeid(element.data_union) == typeid_of(ArrayTransform) {
			transform := element.data_union.(ArrayTransform)
			m := linalg.Matrix3f32(1.0)
			// added origin
			m[2, 0] -= transform.origin.x
			m[2, 1] -= transform.origin.y

			// {0,0,1} is axis of rotation
			m =
				m *
				linalg.matrix3_scale_f32({transform.scale, transform.scale, 1.0}) *
				linalg.matrix3_rotate_f32(linalg.to_radians(transform.rotation), {0, 0, 1})

			m[2, 0] += transform.x
			m[2, 1] += transform.y

			world_matrix = world_matrix * m
		}
	}
}

is_union :: proc($T: typeid) -> bool {
	//return intrinsics.type_is_union(T)
	type_info := type_info_of(T)
	return reflect.is_union(type_info)
}
