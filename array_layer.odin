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

layer_create :: proc($T: typeid) -> (new_layer: ^ArrayLayer(T), result: Result) {
	layer, bad_aloc := new(ArrayLayer(T))
	if bad_aloc != nil {
		return nil, {.AllocationError, "Can't allocate an array layer."}
	}
	new_layer = layer
	defer if result.code != .Success {
		free(new_layer)
		new_layer = nil
	}

	return new_layer, result
}

layer_free :: proc(layer: ^ArrayLayer($T)) {
	delete(layer.arr)
	delete(layer.persistent_ids)
	free(layer)
}

	index, alloc_error := append(
layer_add_element :: proc(layer: ^ArrayLayer($T), element: T, child_level : ChildLevel = 0) -> (id: PersistentId) {
		&layer.arr,
		ArrayElement(T){id = 2, child_level = 1, data_union = element},
	)
	if alloc_error != nil {
		return 0
	}

	id = cast(PersistentId)append(&layer.persistent_ids, index)
	element := layer_get_element_by_index(layer, index)
	element.child_level = child_level
	element.id = id
	return id
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

			fmt.printfln("%f %f - %f rad, scale: %f %f", x, y, angle, scale_x, scale_y)

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

check_layer_union_type :: proc($T: typeid) -> Result {
	// is it an union
	type_info := type_info_of(T)

	if !reflect.is_union(type_info) {
		return {.BadType, "Type for array layer must be an union"}
	}

	// check union variants has id of type PersistentId
	base_type := reflect.type_info_base(type_info)

	#partial switch union_type in base_type.variant {
	case reflect.Type_Info_Union:
		for type_from_union in union_type.variants {

			if !reflect.is_struct(type_from_union) {
				return {.BadType, "All types of array layer union must be structs"}
			}

			fields_count := reflect.struct_field_count(type_from_union.id, .Recursive)
			names := reflect.struct_field_names(type_from_union.id)
			types := reflect.struct_field_types(type_from_union.id)
			was_id := false
			was_child_level := false
			for f in 0 ..< fields_count {
				if names[f] == "id" && types[f].id == typeid_of(PersistentId) {
					was_id = true
				}
				if names[f] == "child_level" && types[f].id == typeid_of(ChildLevel) {
					was_child_level = true
				}
				if was_id && was_child_level do break
			}
			if !was_id {
				return {
					.BadType,
					"All structs of array layer union must have id field (type PersistentId)",
				}
			}
			if !was_child_level {
				return {
					.BadType,
					"All structs of array layer union must have child_level field (type ChildLevel)",
				}
			}
		}
	}
	return {.Success, ""}
}
