extends RefCounted

## Photographed skies. A track picks one by its `sky` (track maker: Sky); everything else, and a
## track whose sky's file is missing, gets the day sky. Each scene keeps its own sunlight, and the
## sky is turned round so the sun in the photo stands where that light comes from. Sources and
## licenses are in reference/skies/ and CREDITS.md; docs/ground-textures.md says how to add one.

const DAY := "day"

## Each sky: its name in the track maker, its panorama, and where its sun is: `sun_u` how far
## across the panorama, 0 to 1, and `sun_up` its height in degrees (kept for matching the light's
## height to it; the light keeps its own height for now). A sun not measured yet is -1, and that
## sky is not turned. tools/prepare_hdri.gd makes a panorama and measures its sun.
##
## A sky can also set the race's light, through `light()`; without these the scene keeps its own:
## `light_height` the sun light's height in degrees (its heading stays), `light_color` and
## `light_energy` for it, `ambient_color` and `ambient_energy`, and `tonemap` ("aces" or
## "filmic") with `exposure`, which a low sun needs or its glow burns out to a white blob, and
## `sky_energy`, how bright the photo itself is drawn, to tame a glow without darkening the scene.
const SKIES := {
	DAY: {
		"name": "Day, partly cloudy",
		"path": "res://assets/skies/kloofendal_48d_partly_cloudy_puresky_4k.hdr",
		"sun_u": 0.5947,
		"sun_up": 48.0,
	},
	"dusk": {
		"name": "Dusk",
		"path": "res://assets/skies/dusk.exr",
		"sun_u": -1.0,
		"sun_up": -1.0,
	},
	"evening-orange": {
		"name": "Cloudy evening, orange",
		"path": "res://assets/skies/evening-orange.exr",
		"sun_u": 0.4999,
		"sun_up": 0.4,
		"light_height": 6.0,
		"light_color": Color(1.0, 0.58, 0.32),
		"light_energy": 0.8,
		"ambient_color": Color(0.42, 0.47, 0.65),
		"ambient_energy": 0.7,
		"tonemap": "filmic",
		"exposure": 1.6,
		"sky_energy": 0.8,
	},
	"sunset-pink": {
		"name": "Hazy sunset, pink and orange",
		"path": "res://assets/skies/sunset-pink.exr",
		"sun_u": 0.4856,
		"sun_up": 4.9,
		# A little higher than the sun itself, so shadows don't run off for hundreds of meters.
		"light_height": 8.0,
		"light_color": Color(1.0, 0.62, 0.4),
		"light_energy": 1.1,
		"ambient_color": Color(0.5, 0.48, 0.62),
		"ambient_energy": 0.75,
		"tonemap": "filmic",
		"exposure": 1.6,
		"sky_energy": 0.55,
	},
	# No sun or moon in the photo, so it isn't turned. The light is race.gd's black night sky's:
	# the scene's 1.1 at its NIGHT_LIGHT_SCALE, and its NIGHT_AMBIENT.
	"night-stars": {
		"name": "Night, stars",
		"path": "res://assets/skies/deep-space-stars.exr",
		"sun_u": -1.0,
		"sun_up": -1.0,
		"light_energy": 0.495,
		"ambient_color": Color(0.78, 0.8, 0.9),
		"ambient_energy": 0.85,
	},
}

static var _skies: Dictionary = {}


## The sky ids, in the track maker's order.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in SKIES:
		out.append(id)
	return out


## Whether the sky `id` has its panorama in the game.
static func has_file(id: String) -> bool:
	return SKIES.has(id) and ResourceLoader.exists(str(SKIES[id]["path"]))


## Puts the sky `id` on `env`, turned so its sun lines up with `sun_basis`, a light in the scene.
## An unknown sky, or one whose file is missing, is the day sky.
static func use(env: Environment, id: String, sun_basis: Basis) -> void:
	if not has_file(id):
		if id != DAY:
			push_warning("Sky `%s` has no panorama in the game yet; using the day sky." % id)
		id = DAY
	if not _skies.has(id):
		var mat := PanoramaSkyMaterial.new()
		mat.panorama = load(str(SKIES[id]["path"])) as Texture2D
		var sky := Sky.new()
		sky.sky_material = mat
		_skies[id] = sky
	env.background_mode = Environment.BG_SKY
	env.sky = _skies[id]
	var sun_u := float(SKIES[id]["sun_u"])
	var turn := 0.0
	if sun_u >= 0.0:
		turn = _yaw_toward(sun_basis) - _panorama_yaw(sun_u)
	env.sky_rotation = Vector3(0.0, turn, 0.0)


## Sets `sun` and `env` for the sky `id`'s light, where its entry asks; call before `use()`, so
## the sky is turned to the light's new heading. A sky whose file is missing is the day sky.
static func light(env: Environment, id: String, sun: DirectionalLight3D) -> void:
	if not has_file(id):
		id = DAY
	var sky: Dictionary = SKIES[id]
	if sky.has("light_height"):
		var heading := _yaw_toward(sun.global_basis)
		var up := deg_to_rad(float(sky["light_height"]))
		var to_sun := Vector3(sin(heading) * cos(up), sin(up), cos(heading) * cos(up))
		sun.global_basis = Basis.looking_at(-to_sun, Vector3.UP)
	if sky.has("light_color"):
		sun.light_color = sky["light_color"]
	if sky.has("light_energy"):
		sun.light_energy = float(sky["light_energy"])
	if sky.has("ambient_color"):
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = sky["ambient_color"]
	if sky.has("ambient_energy"):
		env.ambient_light_energy = float(sky["ambient_energy"])
	match str(sky.get("tonemap", "")):
		"aces":
			env.tonemap_mode = Environment.TONE_MAPPER_ACES
		"filmic":
			env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if sky.has("exposure"):
		env.tonemap_exposure = float(sky["exposure"])
	if sky.has("sky_energy"):
		env.background_energy_multiplier = float(sky["sky_energy"])


## The day sky on `env`.
static func use_day(env: Environment, sun_basis: Basis) -> void:
	use(env, DAY, sun_basis)


## Heading of the direction a light comes from. A light shines along its basis's -Z.
static func _yaw_toward(light_basis: Basis) -> float:
	var to_sun := light_basis.z
	return atan2(to_sun.x, to_sun.z)


## Heading of a point `u` across a panorama, as Godot's sky maps it: the middle is +Z, and the
## panorama runs on toward -X. Turning the sky by `sky_rotation.y` adds that to every heading.
static func _panorama_yaw(u: float) -> float:
	return PI - u * TAU
