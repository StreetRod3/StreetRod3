extends Node3D

const _SIGNATURE := preload("res://assets/locations/city/kings-signature.png")


func _init() -> void:
	name = "RoyalRodsSign"
	var board := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(4.5, 0.85, 0.08)
	board.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.44, 0.07, 0.08)
	material.roughness = 0.9
	board.material_override = material
	add_child(board)

	var title := Label3D.new()
	title.name = "Title"
	title.text = "ROYAL RODS"
	title.font_size = 52
	title.pixel_size = 0.012
	title.modulate = Color(1.0, 0.84, 0.43)
	title.outline_modulate = Color(0.1, 0.07, 0.05)
	title.outline_size = 8
	title.shaded = false
	title.position = Vector3(0, 0, 0.05)
	add_child(title)

	var signature := Sprite3D.new()
	signature.name = "KingsSignature"
	signature.texture = _SIGNATURE
	signature.pixel_size = 3.15 / 610.0
	signature.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	signature.shaded = false
	signature.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	signature.position = Vector3(-1.65, 0.375, 0.1)
	add_child(signature)

	var subtitle := Label3D.new()
	subtitle.name = "Tagline"
	subtitle.text = "SPEED EQUIPMENT  •  AUTO PARTS"
	subtitle.font_size = 32
	subtitle.pixel_size = 0.009
	subtitle.modulate = Color(0.16, 0.11, 0.08)
	subtitle.outline_size = 0
	subtitle.shaded = false
	subtitle.position = Vector3(0, -0.59, 0.05)
	add_child(subtitle)
