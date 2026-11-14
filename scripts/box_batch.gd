extends RefCounted

## Plain scenery pieces (boxes and round posts) merged into one mesh that draws in a single
## call. Each piece keeps its own color, roughness, metal and glow on its vertices, read by
## `shaders/scenery_box.gdshader`, so it looks the same as one with its own StandardMaterial3D.

const _SHADER := preload("res://shaders/scenery_box.gdshader")

static var _material: ShaderMaterial

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _looks := PackedVector2Array()
var _glows := PackedFloat32Array()
var _index := PackedInt32Array()

## Color, roughness, metallic, glow (color times energy, linear) of the pieces added next.
var _color := Color.WHITE
var _look := Vector2(1.0, 0.0)
var _glow := Color.BLACK


## The one material every batch draws with.
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = _SHADER
	return _material


func is_empty() -> bool:
	return _index.is_empty()


## The look of the pieces that follow, as a StandardMaterial3D would give it.
func set_look(albedo: Color, roughness: float, metallic: float, emission: Color = Color.BLACK, energy: float = 0.0) -> void:
	_color = albedo.srgb_to_linear()
	_look = Vector2(roughness, metallic)
	_glow = emission.srgb_to_linear() * energy if energy > 0.0 else Color.BLACK


## The look of a flat StandardMaterial3D. Textures are not carried over.
func set_look_from(mat: Material) -> void:
	var std := mat as BaseMaterial3D
	if std == null:
		set_look(Color.WHITE, 1.0, 0.0)
		return
	var energy := std.emission_energy_multiplier if std.emission_enabled else 0.0
	set_look(std.albedo_color, std.roughness, std.metallic, std.emission, energy)


## A box of `size` centered on `xform`'s origin.
func add_box(size: Vector3, xform: Transform3D) -> void:
	var half := size * 0.5
	var turn := xform.basis.orthonormalized()
	for face in 6:
		var axis := face >> 1
		var sign := 1.0 if (face & 1) == 0 else -1.0
		var n := Vector3.ZERO
		n[axis] = sign
		# u x v = n and the corners run clockwise seen from outside, Godot's front face.
		var v := Vector3.UP if axis != 1 else Vector3(0.0, 0.0, -sign)
		var u := v.cross(n)
		var hn := absf(half[axis])
		var hu := absf(u.dot(half))
		var hv := absf(v.dot(half))
		var base := _verts.size()
		var corners: Array[Vector2] = [Vector2(-1.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, -1.0), Vector2(-1.0, -1.0)]
		var normal := turn * n
		for c: Vector2 in corners:
			_vertex(xform * (n * hn + u * hu * c.x + v * hv * c.y), normal)
		_quad(base)


## A round post, `bottom` at its foot, tapering to `top`, standing on `xform`'s origin.
func add_post(bottom: float, top: float, height: float, sides: int, xform: Transform3D) -> void:
	var turn := xform.basis.orthonormalized()
	var slope := (bottom - top) / height
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := Vector3(sin(a0), 0.0, cos(a0))
		var d1 := Vector3(sin(a1), 0.0, cos(a1))
		var base := _verts.size()
		_vertex(xform * (d0 * top + Vector3.UP * height), turn * (d0 + Vector3.UP * slope).normalized())
		_vertex(xform * (d1 * top + Vector3.UP * height), turn * (d1 + Vector3.UP * slope).normalized())
		_vertex(xform * (d1 * bottom), turn * (d1 + Vector3.UP * slope).normalized())
		_vertex(xform * (d0 * bottom), turn * (d0 + Vector3.UP * slope).normalized())
		_quad(base)
	var cap := _verts.size()
	for i in sides:
		var a := TAU * float(i) / float(sides)
		_vertex(xform * (Vector3(sin(a), 0.0, cos(a)) * top + Vector3.UP * height), turn * Vector3.UP)
	for i in range(1, sides - 1):
		_index.append(cap)
		_index.append(cap + i + 1)
		_index.append(cap + i)


## The batch as a mesh with the shared material, or null when nothing was added.
func commit() -> ArrayMesh:
	if is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _looks
	arrays[Mesh.ARRAY_CUSTOM0] = _glows
	arrays[Mesh.ARRAY_INDEX] = _index
	var mesh := ArrayMesh.new()
	var custom := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, custom)
	mesh.surface_set_material(0, material())
	return mesh


func _vertex(at: Vector3, normal: Vector3) -> void:
	_verts.append(at)
	_normals.append(normal)
	_colors.append(_color)
	_looks.append(_look)
	_glows.append(_glow.r)
	_glows.append(_glow.g)
	_glows.append(_glow.b)
	_glows.append(1.0)


func _quad(base: int) -> void:
	_index.append(base)
	_index.append(base + 1)
	_index.append(base + 2)
	_index.append(base)
	_index.append(base + 2)
	_index.append(base + 3)
