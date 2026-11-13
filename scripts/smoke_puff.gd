extends RefCounted

## The look shared by every smoke particle: a soft, ragged cloud instead of a square, each one
## turned at random and slowly rolling so no two puffs look alike. The particles' own color
## (their color ramp) tints it, so tire smoke and damage smoke can share one material.

## Width and height of the puff texture, in pixels.
const _SIZE := 128
## How far the noise pushes the puff's edge in or out, as a share of its radius.
const _RAGGED := 0.75
## Darkest the thin parts of a puff get, against 1 for its thickest.
const _THIN := 0.45

static var _mesh: QuadMesh = null


## A quad for `CPUParticles3D.mesh` that draws one puff, facing the camera.
static func mesh() -> QuadMesh:
	if _mesh == null:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		# Without this a particle's size is ignored. One not in use has none, and it would be
		# drawn full size and black at the emitter.
		mat.billboard_keep_scale = true
		mat.albedo_texture = _texture()
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_mesh = QuadMesh.new()
		_mesh.material = mat
	return _mesh


## Each puff starts at a random angle and rolls a little as it rises.
static func spin(particles: CPUParticles3D) -> void:
	particles.angle_min = 0.0
	particles.angle_max = 360.0
	particles.angular_velocity_min = -40.0
	particles.angular_velocity_max = 40.0


## Gives each puff a slightly different shade, between `dark` and `light`.
static func vary(particles: CPUParticles3D, dark: Color, light: Color) -> void:
	var shades := Gradient.new()
	shades.set_color(0, dark)
	shades.set_color(1, light)
	particles.color_initial_ramp = shades


## White cloud with lumpy edges and thinner patches inside, made from noise once and kept.
static func _texture() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.028
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var lumps := noise.get_image(_SIZE, _SIZE)
	var pixels := PackedByteArray()
	pixels.resize(_SIZE * _SIZE * 4)
	var half := _SIZE * 0.5
	for y in _SIZE:
		for x in _SIZE:
			var r := Vector2((x + 0.5 - half) / half, (y + 0.5 - half) / half).length()
			var n := lumps.get_pixel(x, y).r
			var edge := r + (n - 0.5) * _RAGGED
			var alpha := 1.0 - smoothstep(0.3, 0.92, edge)
			# Nothing may reach the square's own edge, or the corners show.
			alpha *= 1.0 - smoothstep(0.82, 1.0, r)
			alpha *= lerpf(_THIN, 1.0, n)
			# A little darker towards the rim and in the thin patches, so it reads as a volume.
			var shade := lerpf(0.78, 1.0, sqrt(maxf(1.0 - r * r, 0.0))) * lerpf(0.88, 1.0, n)
			var at := (y * _SIZE + x) * 4
			var grey := int(shade * 255.0)
			pixels[at] = grey
			pixels[at + 1] = grey
			pixels[at + 2] = grey
			pixels[at + 3] = int(clampf(alpha, 0.0, 1.0) * 255.0)
	var image := Image.create_from_data(_SIZE, _SIZE, false, Image.FORMAT_RGBA8, pixels)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
