extends RefCounted

## What stands beside a `street` track, from the `scenery` list of its `.trk` file. Street Rod 2
## draws these as sprites and never tests a car against them, so only the trees here have
## collision: their trunks are solid and can be snapped (tree_grove.gd).

const _TRUNK := Color(0.33, 0.2, 0.11, 1)
const _LEAVES := Color(0.2, 0.46, 0.15, 1)
const _GANTRY_STEEL := Color(0.36, 0.24, 0.14, 1)
const _INSULATOR := Color(0.78, 0.78, 0.76, 1)
const _STRIPE := Color(0.92, 0.92, 0.88, 1)
## Street Rod 2 fills its finish line with color 15, which its race palette shows as yellow.
const _FINISH := Color(0.95, 0.85, 0.15, 1)
const _DARK_STREAK := Color(0.03, 0.03, 0.03, 1)
const _SIGN_BLUE := Color(0.03, 0.05, 0.55, 1)
const _SIGN_WHITE := Color(0.95, 0.95, 0.95, 1)

const _PAINT_RISE := 0.03
const _PAINT_THICK := 0.03
## Longest flat piece of paint. On a rise a longer one would cut through the road.
const _PAINT_PIECE := 2.5
const _DASH_WIDTH := 0.22
const _DASH_LENGTH := 5.0
const _DARK_STREAK_WIDTH := 0.5
const _DARK_STREAK_LENGTH := 2.0
const _FINISH_LENGTH := 5.0

## Trees sit a little into the ground, which is sunk under the road's height.
const _TREE_SINK := 0.15
## Poliigon BarkPoplar001 at 1K, from reference/tracks/treebark/. Its roughness map is the
## download's gloss map inverted. One tile covers about this much bark, and `BARK_TINT`
## multiplies its color: white is the photo's own pale grey, and this turns it a mid brown.
const BARK_TILE_M := 1.0
const BARK_TINT := Color(0.74, 0.61, 0.5, 1)
const _BARK := "res://assets/textures/bark/BarkPoplar001_"
## The bark is lit like the leaves (shaders/tree_bark.gdshader): in this many hard bands, the
## full sun warmed by `BARK_WARM` and the part-lit bands cooled toward `BARK_COOL`. The trunk
## darkens by `BARK_CROWN_SHADE` at the top, starting `BARK_CROWN_FROM` of the way up, and by
## `BARK_FOOT_SHADE` at the ground.
const BARK_LIGHT_STEPS := 3.0
const BARK_WARM := Color(1.0, 0.8, 0.55, 1)
const BARK_COOL := Color(0.6, 0.55, 0.9, 1)
const BARK_CROWN_SHADE := 0.6
const BARK_CROWN_FROM := 0.45
const BARK_FOOT_SHADE := 0.3
const _BARK_SHADER := preload("res://shaders/tree_bark.gdshader")
const _TreeGrove := preload("res://scripts/tree_grove.gd")
## Crowns are leaf cards (shaders/tree_leaves.gdshader): this many per square meter of crown
## surface, each this many meters across from its middle, set in about a fifth of the crown's
## radius at most. The leaf shape and the shader come from PixelageGames' 3D pixel art vegetation
## demo (CREDITS.md). The plain crown shapes stay, unseen, to cast the shadows.
const LEAF_CARDS_PER_M2 := 6.0
const LEAF_CARD_HALF_M := 0.45
const LEAF_DEPTH := 0.18
const LEAF_COLOR := Color(0.365, 0.659, 0.176, 1)
const LEAF_LIGHT_STEPS := 5.0
## Share of the scene's ambient light the leaves take, as a crown shades itself; at 1 the night
## races' flat ambient made them glow.
const LEAF_AMBIENT := 0.45
const _LEAF_SHADER := preload("res://shaders/tree_leaves.gdshader")
const _LEAF_ALPHA := "res://assets/textures/leaves/leaf_alpha.png"

static var _leaf_material: ShaderMaterial = null
const _POLE_HEIGHT := 7.5


static func build(track: Node3D, items: Array[Dictionary], road_width: float) -> void:
	var root := Node3D.new()
	root.name = "StreetScenery"
	track.add_child(root)
	var spots: Dictionary = {}
	for item: Dictionary in items:
		var kind := str(item["kind"])
		var list: Array[Vector2] = []
		list.assign(spots.get(kind, list))
		list.append(Vector2(float(item["x"]), float(item["y"])))
		spots[kind] = list
	add_trees(root, _feet_on_track(track, _spots_of(spots, "tree")), _spots_of(spots, "tree"), "tree", track)
	add_trees(root, _feet_on_track(track, _spots_of(spots, "big_tree")), _spots_of(spots, "big_tree"), "big_tree", track)
	add_trees(root, _feet_on_track(track, _spots_of(spots, "bare_tree")), _spots_of(spots, "bare_tree"), "bare_tree", track)
	_build_poles(track, root, _spots_of(spots, "pole"))
	_build_paint(track, root, "Dashes", _spots_of(spots, "dash"), _DASH_WIDTH, _DASH_LENGTH, 0.0, _STRIPE)
	_build_paint(track, root, "Finish", _spots_of(spots, "finish"), road_width, _FINISH_LENGTH, 0.0, _FINISH)
	_build_paint(track, root, "DarkStreaks", _spots_of(spots, "dark_streak"), _DARK_STREAK_WIDTH, _DARK_STREAK_LENGTH, _DARK_STREAK_WIDTH * 0.5, _DARK_STREAK)
	for spot: Vector2 in _spots_of(spots, "gantry"):
		_build_gantry(track, root, spot, road_width)


static func _spots_of(spots: Dictionary, kind: String) -> Array[Vector2]:
	var list: Array[Vector2] = []
	list.assign(spots.get(kind, list))
	return list


static func _ground(track: Node3D, x: float, z: float) -> Vector3:
	return Vector3(x, float(track.surface_height(Vector3(x, 0.0, z))), z)


## The same spot always gives the same number, from 0 to 1, so trees don't all look alike.
static func _spot_random(spot: Vector2, salt: float) -> float:
	return fposmod(sin(spot.x * 12.9898 + spot.y * 78.233 + salt) * 43758.5453, 1.0)


static func _feet_on_track(track: Node3D, spots: Array[Vector2]) -> Array[Vector3]:
	var feet: Array[Vector3] = []
	for spot: Vector2 in spots:
		feet.append(_ground(track, spot.x, spot.y) + Vector3(0.0, -_TREE_SINK, 0.0))
	return feet


## The street drag's trees on flat ground. Each spot is world X and Z.
static func add_flat_trees(root: Node3D, trees: Array[Vector2], big_trees: Array[Vector2], bare_trees: Array[Vector2]) -> void:
	add_trees(root, _flat_feet(trees), trees, "tree")
	add_trees(root, _flat_feet(big_trees), big_trees, "big_tree")
	add_trees(root, _flat_feet(bare_trees), bare_trees, "bare_tree")


static func _flat_feet(spots: Array[Vector2]) -> Array[Vector3]:
	var feet: Array[Vector3] = []
	for spot: Vector2 in spots:
		feet.append(Vector3(spot.x, -_TREE_SINK, spot.y))
	return feet


## The street drag's round trees, larger ones, and sparse ones. `spots` pick each tree's
## size, and `feet` are where they stand. Each kind is a TreeGrove (tree_grove.gd): solid trunks
## that snap in a hard enough hit. `track` is the race track they stand by, if any, so rivals
## steer round a fallen one.
static func add_trees(root: Node3D, feet: Array[Vector3], spots: Array[Vector2], kind: String, track: Node3D = null) -> void:
	if feet.is_empty() or feet.size() != spots.size():
		return
	var height := 5.5
	var trunk_radius := 0.22
	var crown_radius := 2.4
	var bare := false
	if kind == "big_tree":
		height = 7.5
		trunk_radius = 0.34
		crown_radius = 3.3
	elif kind == "bare_tree":
		height = 6.5
		trunk_radius = 0.18
		crown_radius = 1.0
		bare = true
	elif kind != "tree":
		return
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = trunk_radius * 0.7
	trunk_mesh.bottom_radius = trunk_radius
	trunk_mesh.height = height
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	trunk_mesh.material = _bark_material(trunk_radius, height)
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 1.0
	crown_mesh.height = 2.0
	crown_mesh.radial_segments = 10
	crown_mesh.rings = 5
	crown_mesh.material = _material(_LEAVES)
	var crowns := _bare_crowns(height, crown_radius) if bare else _full_crowns(height, crown_radius)
	var leaf_mesh := _leaf_mesh(crowns, kind.hash())
	var plants: Array[Transform3D] = []
	var seeds := PackedFloat32Array()
	for i in spots.size():
		var spot: Vector2 = spots[i]
		var size := lerpf(0.88, 1.15, _spot_random(spot, 1.0))
		var turn := Basis(Vector3.UP, TAU * _spot_random(spot, 2.0)).scaled(Vector3(size, size, size))
		plants.append(Transform3D(turn, feet[i]))
		seeds.append(_spot_random(spot, 5.0))
	var grove := _TreeGrove.new()
	grove.name = "Trees_%s" % kind
	grove.track = track
	root.add_child(grove)
	grove.setup(kind, height, trunk_radius, trunk_mesh, crown_mesh, leaf_mesh, crowns, plants, seeds)


## Bark for a trunk of this size. The texture goes round a whole number of times so it meets
## itself, and runs up the trunk at the same scale. A cylinder's side takes the top half of its
## UVs, so V is doubled. The bark is matte, so the roughness map isn't used.
static func _bark_material(radius: float, height: float) -> ShaderMaterial:
	var round_m := TAU * radius * 0.85
	var across := maxf(1.0, roundf(round_m / BARK_TILE_M))
	var mat := ShaderMaterial.new()
	mat.shader = _BARK_SHADER
	mat.set_shader_parameter(&"albedo_texture", load(_BARK + "COL_1K.jpg") as Texture2D)
	mat.set_shader_parameter(&"normal_texture", load(_BARK + "NRM_1K.jpg") as Texture2D)
	mat.set_shader_parameter(&"uv_scale", Vector2(across, 2.0 * height * across / round_m))
	mat.set_shader_parameter(&"tint", BARK_TINT)
	mat.set_shader_parameter(&"light_steps", BARK_LIGHT_STEPS)
	mat.set_shader_parameter(&"warm", BARK_WARM)
	mat.set_shader_parameter(&"cool", BARK_COOL)
	mat.set_shader_parameter(&"crown_shade", BARK_CROWN_SHADE)
	mat.set_shader_parameter(&"crown_from", BARK_CROWN_FROM)
	mat.set_shader_parameter(&"foot_shade", BARK_FOOT_SHADE)
	return mat


## Leaf cards over every crown of one kind of tree, in the tree's own space. Each card is four
## vertices at one point with UVs at its corners, which the shader spreads to face the camera;
## UV2.x turns it. Cards are spread evenly over each crown's surface, as many as its area takes,
## and its normal is the crown's there.
static func _leaf_mesh(crowns: Array[Transform3D], seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	var corners: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	var golden := PI * (3.0 - sqrt(5.0))
	for crown: Transform3D in crowns:
		var count := maxi(12, int(_ellipsoid_area(crown.basis.get_scale()) * LEAF_CARDS_PER_M2))
		var to_normal := crown.basis.inverse().transposed()
		for i in count:
			var y := 1.0 - 2.0 * (float(i) + 0.5) / float(count)
			var ring := sqrt(1.0 - y * y)
			var dir := Vector3(cos(golden * i) * ring, y, sin(golden * i) * ring)
			var center := crown * (dir * rng.randf_range(1.0 - LEAF_DEPTH, 1.0))
			var normal := (to_normal * dir).normalized()
			var turn := Vector2(rng.randf() * TAU, 0.0)
			var base := verts.size()
			for corner: Vector2 in corners:
				verts.append(center)
				normals.append(normal)
				uvs.append(corner)
				uv2s.append(turn)
			indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _leaves())
	# The cards spread past the points the mesh is made of.
	mesh.custom_aabb = mesh.get_aabb().grow(LEAF_CARD_HALF_M * 1.5)
	return mesh


static func _leaves() -> ShaderMaterial:
	if _leaf_material == null:
		_leaf_material = ShaderMaterial.new()
		_leaf_material.shader = _LEAF_SHADER
		_leaf_material.set_shader_parameter(&"color", LEAF_COLOR)
		_leaf_material.set_shader_parameter(&"alpha", load(_LEAF_ALPHA) as Texture2D)
		_leaf_material.set_shader_parameter(&"card_half_m", LEAF_CARD_HALF_M)
		_leaf_material.set_shader_parameter(&"light_steps", LEAF_LIGHT_STEPS)
		_leaf_material.set_shader_parameter(&"ambient_share", LEAF_AMBIENT)
	return _leaf_material


## Surface area of an ellipsoid with these radii (Knud Thomsen's formula, within about 1%).
static func _ellipsoid_area(radii: Vector3) -> float:
	var p := 1.6075
	var ab := pow(radii.x * radii.y, p)
	var ac := pow(radii.x * radii.z, p)
	var bc := pow(radii.y * radii.z, p)
	return 4.0 * PI * pow((ab + ac + bc) / 3.0, 1.0 / p)


## A wide flat crown and a smaller one off to the side, like Street Rod 2's round trees.
static func _full_crowns(height: float, radius: float) -> Array[Transform3D]:
	return [
		_crown(Vector3(0.0, height * 0.95, 0.0), radius, 0.72),
		_crown(Vector3(radius * 0.9, height * 0.72, 0.0), radius * 0.45, 0.7),
	]


## Small tufts spread over thin air, like Street Rod 2's sparse tree.
static func _bare_crowns(height: float, radius: float) -> Array[Transform3D]:
	return [
		_crown(Vector3(0.0, height * 1.02, 0.0), radius, 0.5),
		_crown(Vector3(radius * 1.7, height * 0.82, 0.3), radius * 0.8, 0.45),
		_crown(Vector3(-radius * 1.8, height * 0.76, -0.2), radius * 0.9, 0.42),
		_crown(Vector3(radius * 0.8, height * 0.6, -radius), radius * 0.6, 0.45),
		_crown(Vector3(-radius * 0.7, height * 0.55, radius), radius * 0.55, 0.45),
	]


static func _crown(center: Vector3, radius: float, flat: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY.scaled(Vector3(radius, radius * flat, radius)), center)


static func _build_poles(track: Node3D, root: Node3D, spots: Array[Vector2]) -> void:
	if spots.is_empty():
		return
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.11
	pole_mesh.bottom_radius = 0.15
	pole_mesh.height = _POLE_HEIGHT
	pole_mesh.radial_segments = 6
	pole_mesh.rings = 1
	pole_mesh.material = _material(_TRUNK)
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(2.0, 0.1, 0.1)
	arm_mesh.material = _material(_TRUNK)
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.1, 0.16, 0.1)
	cap_mesh.material = _material(_INSULATOR)
	var pole_xforms: Array[Transform3D] = []
	var arm_xforms: Array[Transform3D] = []
	var cap_xforms: Array[Transform3D] = []
	for spot: Vector2 in spots:
		var foot := _ground(track, spot.x, spot.y) + Vector3(0.0, -_TREE_SINK, 0.0)
		pole_xforms.append(Transform3D(Basis.IDENTITY, foot + Vector3(0.0, _POLE_HEIGHT * 0.5, 0.0)))
		for arm_y: float in [_POLE_HEIGHT - 0.5, _POLE_HEIGHT - 1.2]:
			arm_xforms.append(Transform3D(Basis.IDENTITY, foot + Vector3(0.0, arm_y, 0.0)))
			for cap_x: float in [-0.85, -0.45, 0.45, 0.85]:
				cap_xforms.append(Transform3D(Basis.IDENTITY, foot + Vector3(cap_x, arm_y + 0.13, 0.0)))
	_add_multimesh(root, "Poles", pole_mesh, pole_xforms, true)
	_add_multimesh(root, "PoleArms", arm_mesh, arm_xforms, true)
	_add_multimesh(root, "PoleCaps", cap_mesh, cap_xforms, false)


## Flat pieces laid along the road from each spot, pitched to it. `outward` moves a piece away
## from the road's middle, so a spot on the edge lays it on the shoulder.
static func _build_paint(
	track: Node3D,
	root: Node3D,
	node_name: String,
	spots: Array[Vector2],
	width: float,
	length: float,
	outward: float,
	color: Color
) -> void:
	if spots.is_empty():
		return
	var pieces := maxi(int(ceil(length / _PAINT_PIECE)), 1)
	var piece_length := length / float(pieces)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, _PAINT_THICK, piece_length)
	var mat := _material(color)
	mat.roughness = 0.9
	mesh.material = mat
	var xforms: Array[Transform3D] = []
	for spot: Vector2 in spots:
		var yaw := float(track.closest_sample(Vector3(spot.x, 0.0, spot.y))["yaw"])
		var along := Vector2(sin(yaw), cos(yaw))
		var start := spot + Vector2(cos(yaw), -sin(yaw)) * (signf(spot.x) * outward)
		var turn := Basis(Vector3.UP, yaw)
		for i in pieces:
			var near_at := start + along * (piece_length * float(i))
			var far_at := start + along * (piece_length * float(i + 1))
			var near := _ground(track, near_at.x, near_at.y)
			var far := _ground(track, far_at.x, far_at.y)
			var pitch := turn * Basis(Vector3.RIGHT, -atan2(far.y - near.y, piece_length))
			xforms.append(Transform3D(pitch, (near + far) * 0.5 + Vector3(0.0, _PAINT_RISE, 0.0)))
	_add_multimesh(root, node_name, mesh, xforms, false)


## Street Rod 2's overhead highway sign. The driver comes along +Z and so sees its -Z face, with
## their left at +X: the arrow on the left, the route shield on the right.
static func _build_gantry(track: Node3D, root: Node3D, spot: Vector2, road_width: float) -> void:
	const POST_H := 6.2
	const POST_W := 0.26
	const PANEL := Vector3(5.6, 2.3, 0.1)
	var gantry := Node3D.new()
	gantry.name = "Gantry"
	gantry.position = _ground(track, 0.0, spot.y)
	root.add_child(gantry)
	var steel := _material(_GANTRY_STEEL)
	var post_x := road_width * 0.5 + 0.6
	_add_box(gantry, Vector3(POST_W, POST_H, POST_W), steel, Vector3(post_x, POST_H * 0.5 - _TREE_SINK, 0.0))
	_add_box(gantry, Vector3(POST_W, POST_H, POST_W), steel, Vector3(-post_x, POST_H * 0.5 - _TREE_SINK, 0.0))
	_add_box(gantry, Vector3(post_x * 2.0 + POST_W, POST_W, POST_W), steel, Vector3(0.0, POST_H - _TREE_SINK, 0.0))
	var panel_y := POST_H - _TREE_SINK - 0.6
	var face_z := -PANEL.z * 0.5 - POST_W * 0.5
	_add_box(gantry, PANEL, _material(_SIGN_BLUE), Vector3(0.0, panel_y, face_z))
	var white := _material(_SIGN_WHITE)
	var symbol_z := face_z - PANEL.z * 0.5 - 0.02
	var arrow_x := 1.45
	_add_box(gantry, Vector3(0.5, 0.95, 0.03), white, Vector3(arrow_x, panel_y - 0.45, symbol_z))
	_add_prism(gantry, Vector3(1.3, 0.85, 0.03), white, Vector3(arrow_x, panel_y + 0.45, symbol_z), false)
	var shield_x := -1.45
	_add_box(gantry, Vector3(1.2, 1.0, 0.03), white, Vector3(shield_x, panel_y + 0.2, symbol_z))
	_add_prism(gantry, Vector3(1.2, 0.5, 0.03), white, Vector3(shield_x, panel_y - 0.55, symbol_z), true)
	var route := Label3D.new()
	route.text = "69"
	route.font_size = 96
	route.pixel_size = 0.009
	route.outline_size = 0
	route.modulate = Color.BLACK
	route.shaded = false
	route.double_sided = false
	route.rotation.y = PI
	route.position = Vector3(shield_x, panel_y + 0.05, symbol_z - 0.02)
	gantry.add_child(route)


static func _add_box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = pos
	parent.add_child(mi)


static func _add_prism(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, point_down: bool) -> void:
	var prism := PrismMesh.new()
	prism.size = size
	prism.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = prism
	mi.position = pos
	if point_down:
		mi.rotation.z = PI
	parent.add_child(mi)


static func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat


static func _add_multimesh(
	root: Node3D,
	node_name: String,
	mesh: Mesh,
	xforms: Array[Transform3D],
	shadows: bool
) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
