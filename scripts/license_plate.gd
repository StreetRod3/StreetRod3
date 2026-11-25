extends RefCounted

## License plates: the 1972 California plate (blue, yellow characters, a 1973 year sticker
## on the rear one) printed with a car's number and laid over every surface of the car's
## model whose material is named `plate` (tools/make_blank_plate.py).
##
## The plate and its characters are images drawn by tools/make_plates_1972.py; this script
## copies the characters onto the plate, so the cell sizes and the layout below are that
## tool's numbers too.

const PLATE_MATERIAL := "plate"
const _FRONT := "res://assets/cars/plates/ca-1972-front.png"
const _REAR := "res://assets/cars/plates/ca-1972-rear.png"
const _GLYPH_SHEET := "res://assets/cars/plates/ca-1972-glyphs.png"
const _Shader := preload("res://shaders/license_plate.gdshader")

## The characters in the glyph sheet, in order (make_plates_1972.py GLYPHS).
const GLYPHS := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
## A glyph cell, and how far its die sits inside it (CELL_W, CELL_H, CELL_PAD).
const _CELL := Vector2i(68, 132)
const _CELL_PAD := 6
## The die's width, how far each character moves on, the gap a space leaves, and where the
## tops of the characters sit on the 512 x 256 plate.
const _DIE_W := 56
const _PITCH := 70
const _SPACE := 34
const _TOP := 99
const _PLATE := Vector2i(512, 256)

## A vanity plate: 2 to 6 letters and digits, as California's personalized plates of the
## time, with spaces between them if wanted, up to as wide as a sequential plate.
const VANITY_MIN := 2
const VANITY_MAX := 6
const VANITY_PLACES := 7
## Sequential plates of the time skip I, O and Q, which read as 1 and 0.
const _SERIAL_LETTERS := "ABCDEFGHJKLMNPRSTUVWXYZ"

## Plate materials already made, by number, so cars with the same number share one.
static var _materials: Dictionary[String, ShaderMaterial] = {}
static var _glyph_image: Image = null


## A sequential plate of the time, "123 ABC", the same every time for the same `key`.
static func serial(key: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("plate:" + key)
	var digits := "%03d" % rng.randi_range(0, 999)
	var letters := ""
	for i in 3:
		letters += _SERIAL_LETTERS[rng.randi_range(0, _SERIAL_LETTERS.length() - 1)]
	return digits + " " + letters


## `text` as it would go on a vanity plate: capitals, runs of spaces as one, no space at
## the ends, and only the characters a plate has.
static func normalize(text: String) -> String:
	var out := ""
	for ch in text.to_upper():
		if ch == " ":
			if not out.is_empty() and not out.ends_with(" "):
				out += ch
		elif GLYPHS.contains(ch):
			out += ch
	return out.strip_edges()


## Why `text` (already normalized) can't be a vanity plate, or "" when it can.
static func vanity_problem(text: String) -> String:
	var characters := text.replace(" ", "").length()
	if characters > VANITY_MAX:
		return "A plate holds %d letters and numbers at most." % VANITY_MAX
	if characters < VANITY_MIN:
		return "A plate needs %d letters and numbers at least." % VANITY_MIN
	if text.length() > VANITY_PLACES:
		return "That many spaces won't fit on a plate."
	return ""


## Whether `mesh_instance`'s surface `index` is a plate, by its material's name in the model.
static func is_plate_surface(mesh_instance: MeshInstance3D, index: int) -> bool:
	if mesh_instance.mesh == null:
		return false
	var mat := mesh_instance.mesh.surface_get_material(index)
	return mat != null and String(mat.resource_name).to_lower() == PLATE_MATERIAL


## Puts plates reading `number` on every plate surface under `root`. With `keep` false
## the plate is not kept for the next car with that number (the garage's plate shown
## while it is typed).
static func apply(root: Node, number: String, keep: bool = true) -> void:
	if root == null:
		return
	var mat := material(number, keep)
	if mat == null:
		return
	_apply_under(root, mat, root as Node3D)


static func _apply_under(node: Node, mat: ShaderMaterial, car: Node3D) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				if is_plate_surface(mi, i):
					var own := mat.duplicate() as ShaderMaterial
					own.set_shader_parameter("car_from_mesh", Projection(_car_from_mesh(mi, car)))
					mi.set_surface_override_material(i, own)
	for child in node.get_children():
		_apply_under(child, mat, car)


## A mesh's own coordinates to the car's (the car's nose is +Z), so the shader can tell
## the front plate from the rear.
static func _car_from_mesh(mesh_instance: MeshInstance3D, car: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var node: Node = mesh_instance
	while node != null and node != car:
		if node is Node3D:
			xf = (node as Node3D).transform * xf
		node = node.get_parent()
	return xf


## The world box round each plate showing under `root`, for clicking on them.
static func plate_boxes(root: Node) -> Array[AABB]:
	var boxes: Array[AABB] = []
	_collect_boxes(root, boxes)
	return boxes


static func _collect_boxes(node: Node, boxes: Array[AABB]) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree():
			for i in mi.mesh.get_surface_count():
				if not is_plate_surface(mi, i):
					continue
				var verts: PackedVector3Array = mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
				# A surface can hold both plates (the Challenger's): a box for each end.
				var ends: Dictionary[int, AABB] = {}
				var xf := mi.global_transform
				var center := xf * mi.mesh.get_aabb().get_center()
				for v in verts:
					var w := xf * v
					var key := 1 if (w - center).dot(xf.basis.z) >= 0.0 else -1
					if ends.has(key):
						ends[key] = ends[key].expand(w)
					else:
						ends[key] = AABB(w, Vector3.ZERO)
				for box: AABB in ends.values():
					boxes.append(box)
	for child in node.get_children():
		_collect_boxes(child, boxes)


## The plate material for `number`: the front and rear plates printed with it, kept for
## the next car with that number when `keep` is set. Null when the plate images fail to
## load.
static func material(number: String, keep: bool = true) -> ShaderMaterial:
	if _materials.has(number):
		return _materials[number]
	var front := _printed(_FRONT, number)
	var rear := _printed(_REAR, number)
	if front == null or rear == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = _Shader
	mat.set_shader_parameter("front_tex", front)
	mat.set_shader_parameter("rear_tex", rear)
	if keep:
		_materials[number] = mat
	return mat


## The plate image at `path` with `number` pressed into it, as a texture.
static func _printed(path: String, number: String) -> ImageTexture:
	var plate := _image(path)
	var glyphs := _glyphs()
	if plate == null or glyphs == null:
		return null
	var width := -(_PITCH - _DIE_W)
	for ch in number:
		width += _SPACE if ch == " " else _PITCH
	var x := (_PLATE.x - width) / 2
	for ch in number:
		if ch == " ":
			x += _SPACE
			continue
		var index := GLYPHS.find(ch)
		if index >= 0:
			var cell := Rect2i(Vector2i(index * _CELL.x, 0), _CELL)
			plate.blend_rect(glyphs, cell, Vector2i(x - _CELL_PAD, _TOP - _CELL_PAD))
		x += _PITCH
	plate.generate_mipmaps()
	return ImageTexture.create_from_image(plate)


static func _glyphs() -> Image:
	if _glyph_image == null:
		_glyph_image = _image(_GLYPH_SHEET)
	return _glyph_image


## A copy of the image at `path` as plain RGBA8, or null.
static func _image(path: String) -> Image:
	var tex := load(path) as Texture2D
	if tex == null:
		push_error("License plate image failed to load: %s" % path)
		return null
	var img := tex.get_image()
	if img == null:
		return null
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	if img.has_mipmaps():
		img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	return img
