extends RefCounted

## Photographed skies. The day sky is Poly Haven's "Kloofendal 48d Partly Cloudy (Pure Sky)" at 4K
## (CC0, reference/skies/kloofendal_48d_partly_cloudy_puresky). Each scene keeps its own sunlight;
## the sky is turned round so the sun in the photo stands where that light comes from.

const _DAY_PANORAMA := "res://assets/skies/kloofendal_48d_partly_cloudy_puresky_4k.hdr"
## How far across the day panorama the sun is, 0 to 1. It stands 48 degrees up.
const _DAY_SUN_U := 0.5947

static var _day: Sky = null


## Puts the day sky on `env`, turned so its sun lines up with `sun`, a light in the scene.
static func use_day(env: Environment, sun_basis: Basis) -> void:
	if _day == null:
		var mat := PanoramaSkyMaterial.new()
		mat.panorama = load(_DAY_PANORAMA) as Texture2D
		_day = Sky.new()
		_day.sky_material = mat
	env.background_mode = Environment.BG_SKY
	env.sky = _day
	env.sky_rotation = Vector3(0.0, _yaw_toward(sun_basis) - _panorama_yaw(_DAY_SUN_U), 0.0)


## Heading of the direction a light comes from. A light shines along its basis's -Z.
static func _yaw_toward(light_basis: Basis) -> float:
	var to_sun := light_basis.z
	return atan2(to_sun.x, to_sun.z)


## Heading of a point `u` across a panorama, as Godot's sky maps it: the middle is +Z, and the
## panorama runs on toward -X. Turning the sky by `sky_rotation.y` adds that to every heading.
static func _panorama_yaw(u: float) -> float:
	return PI - u * TAU
