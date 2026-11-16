extends SceneTree

## Makes a sky panorama for scripts/skies.gd from a downloaded HDRI, and measures its sun:
##   godot --headless --path . --script tools/prepare_hdri.gd -- IN.hdr OUT.exr [WIDTH]
## IN is an equirectangular .hdr or .exr of any size. OUT is written as half-float EXR, scaled
## down to WIDTH across (4096 if left out; never scaled up). It then prints the brightest spot's
## `sun_u` and `sun_up` for the sky's entry in skies.gd. A sky with no clear sun (overcast, or
## the sun below the horizon) prints where its brightest patch is; check that against the photo.

const DEFAULT_WIDTH := 4096
## Pixels at least this fraction of the brightest one's luminance count as the sun.
const SUN_FRACTION := 0.5


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("Usage: godot --headless --path . --script tools/prepare_hdri.gd -- IN.hdr OUT.exr [WIDTH]")
		quit(1)
		return
	var img := Image.load_from_file(args[0])
	if img == null or img.is_empty():
		printerr("Could not read %s" % args[0])
		quit(1)
		return
	print("Read %s: %d x %d" % [args[0], img.get_width(), img.get_height()])
	if img.get_format() != Image.FORMAT_RGBH:
		img.convert(Image.FORMAT_RGBH)
	var width := int(args[2]) if args.size() > 2 else DEFAULT_WIDTH
	# Halving with a bilinear filter averages each 2 x 2 block, so a big panorama comes down without
	# the shimmer one large step would leave.
	while img.get_width() >= width * 2:
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	if img.get_width() > width:
		img.resize(width, width / 2, Image.INTERPOLATE_BILINEAR)
	var err := img.save_exr(args[1], false)
	if err != OK:
		printerr("Could not write %s: %s" % [args[1], error_string(err)])
		quit(1)
		return
	print("Wrote %s: %d x %d" % [args[1], img.get_width(), img.get_height()])
	_print_sun(img)
	quit()


## The sun's place: the middle of the pixels near the brightest one's luminance. Across is averaged
## round the circle, so a sun on the panorama's seam comes out right.
func _print_sun(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var lum := PackedFloat32Array()
	lum.resize(w * h)
	var brightest := 0.0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			lum[y * w + x] = l
			brightest = maxf(brightest, l)
	var across := Vector2.ZERO
	var down := 0.0
	var count := 0.0
	for y in h:
		for x in w:
			if lum[y * w + x] < brightest * SUN_FRACTION:
				continue
			var angle := TAU * (float(x) + 0.5) / float(w)
			across += Vector2(cos(angle), sin(angle))
			down += float(y) + 0.5
			count += 1.0
	var sun_u := fposmod(across.angle(), TAU) / TAU
	var sun_up := 90.0 - down / count / float(h) * 180.0
	print("Brightest luminance %.1f over %d pixels" % [brightest, int(count)])
	print("\"sun_u\": %.4f," % sun_u)
	print("\"sun_up\": %.1f," % sun_up)
