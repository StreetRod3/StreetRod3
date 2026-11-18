# To do

Ideas that are wanted but not built yet. Bugs go in [bugs.md](bugs.md). Remove an entry when it lands, and record it in `changelog.md`.

## Track maker for players

The track maker ([track-maker.md](track-maker.md)) is a developer tool, opened from the main menu's ~ prompt, with a solo test drive. Wanted later: rivals on made tracks (how a rival drives a course it has never seen is the hard part), a way in for players and somewhere to race what they make, a 3D preview while editing, and drawing a curve that becomes nodes.

- scenery available on all track types.
- jumps available on all track types.
- Track banking

## Make burnouts do something

Holding gas and brake with the car stopped is mostly for show so far: the rear wheels spin, the engine revs, the tires smoke and mark the road, and the steering swings the back of the car round (`_update_burnout()` in `player_race_car.gd`, `burn()` in `skid_marks.gd`). It gives the launch nothing and costs nothing. Decided on 2026-11-03 to start this way so it would not change the race balance.

- **Warm tires.** A launch bonus in the simulation from a burnout before the green light, fading over the first part of the race, with too long a burnout overheating the tires and costing grip. In the arcade drive it may stay for show, since launches there have no traction limit to improve.
- **Tire wear and fuel.** A burnout should cost rubber and gas. Tires already wear per race (`wear_parts_after_race()`), and they can blow when worn out.
- **Engine.** Holding it at the limit could add to engine wear or overheat a tired motor. For now it holds a steady 5000 rpm, safely under the rev limit, in any gear.
- **Sound.** Tire screech for burnouts, launches, and slides. There is no tire sound in the game yet. The AdLib engine sound takes its rpm from `get_rpm()`, so it already revs.
- **Rivals.** A rival could do a burnout at the line, more of them higher up the ladder, as a show of strength.
- **Reward.** The crowd or the rival could react, or a good burnout could pay a little at the drive-in.
- **A line lock part.** A part to buy that holds only the front brakes, which is what real drag cars use to do this.
- **Look.** The patch of rubber under a stopped tire is a simple dark quad, and it could grow and blend better. Smoke could hang longer in still air and depend on the tires, with more from slicks.

## Removable bumpers on the last two cars

Bumpers can be stripped and put back as in Street Rod 2 on the Studebaker, the 1960 Corvette, the Styleline and the F100. The 1956 Corvette and the Fairlane are left: they are single fused meshes converted from Street Rod 1, so their bumpers have to be cut out of the body, brackets included (they are unbolted from the frame with the bumper, not left hanging), and whatever the bumper hid modeled (`tools/split_bumpers.py` takes a rule per car). The 1932 Ford has none.

## Chopped roofs

Street Rod 2 also chopped roofs for $70. No car here has a roof that can be chopped yet, so it waits for one.

## Time of day

Street Rod 2's three races run at night for now and the other two by day (`_set_night()` in `race.gd`). Time could become a factor in races later.

## Jumps

The stunt track (`assets/tracks/stunt.trk`) is a first test of cars leaving the road. Every stunt has to be one a car can make: nothing that only ends in a crash. Gap jumps are welcome as long as a car can land them, with a landing ramp it reaches at a speed it can get to, and a loop the car can actually drive round would be welcome too. Not built yet:

- **Gap jumps.** The road's height is one value along it, so there are no holes yet. A gap needs the ground in it dropped away below the road, and the takeoff and landing ramps set so the arc from the takeoff clears it.

- **The car in the air.** It keeps its pitch to the way it is flying, with no rotation of its own from the takeoff, no throttle or brake effect, and no suspension stretching out. The wheels keep turning at road speed.
- **Other tracks.** Jumps are off everywhere else. The street drag's rises could throw a fast car if they were on there, which may suit "it can be fun to hit the peaks".
- **Scenery.** The track is bare: no crowd, no signs, nothing beside the road.

## Round the Torq Thrust spokes

The torq wheel's spokes (`tools/make_wheels.py`) have square front edges, where the real wheel's are rounded, which is a big part of its look. Filleting them in SolidCraft 0.30.1 works for one window (78 seconds) but took over half an hour for five and then failed on the second ("the blend is larger than the neighbouring faces"), and patterning one window's fillet round the wheel fails too. A bevel on the exported mesh in Blender, which `tools/sbc_to_glb.py` already drives, could do it instead, or a later SolidCraft.

## Engines for every make and era

Engines come in families now (`families` in `parts.register`), and the Ford flathead and the Chevy Stovebolt (216 and 235, the Styleline's stock engine) are drawn for their era. The flathead's numbers (150 hp, $600) sit well below the Chevy small-blocks on purpose: it lines up against period Chevys like the Stovebolt, not against the 265 and up. Still to come:

- **More period Chevys** to match the flathead, each a family with its own stock heads, intake, camshaft, distributor and manifolds, and speed parts like the flathead's finned heads and three two-barrel intake.
- **Real Ford Y-block and small-block.** The 292 and the 302 are stand-ins drawn with the Chevy models, and their speed parts are Ford copies of the Chevy ones with the same stats and looks.
- **Small-block speed parts as models.** The Chevys are drawn from `tools/make_sbc.py`'s model now, with its cast-iron manifolds and headers, but the high-rise, tri-power and dual-quad intakes, the two-barrel carburetor and the chrome air cleaner are still built from primitives in `engine_assembly.gd`. The Ford stand-ins still use the old `engine-v8-*.glb`.
- **Chrysler.** The issue names it as a third make (issue #8); there are no Chrysler cars or engines yet.
- **Studebaker.** The 1950 Studebaker Champion is in, but listed as a GM car on the Chevy 216 and its gearbox until there is material to build its own parts from (the 169.6 ci Champion six, or the Commander's 232 V8, and Studebaker gearboxes and rear ends). No stand-in parts drawn with other makes' models in the meantime.
- **The speed shop**, the only place to buy engine mounts for a swap across makes (`mounts` parts, `"shop": "speed"`).

## Ground depth

The grass and asphalt got stronger normal maps, their occlusion maps and large-scale patches on branch ground-depth (2026-11-17; settings in `scripts/ground_material.gd`, see [ground-textures.md](ground-textures.md)). Left:

- **Mulholland's dirt and gravel.** Wanted. Only the grass part of `shaders/vertex_ground.gdshader` has the new treatment, so the hillsides and the verge are as flat as the grass was. Give the dirt and gravel the same: a normal strength each (the shader sets one `NORMAL_MAP_DEPTH` for the blend, now mixed by the grass share, so weight it by all three), occlusion (the dirt's `AO_2K` is in `reference/tracks/dirt/` and needs copying to `assets/textures/dirt/`; the gravel's is already in the red channel of its ARM map), and large-scale patches from `ground_macro()` in `shaders/ground_common.gdshaderinc`. Do the same for `gravel()`, Mulholland's gravel stretches, which is still a StandardMaterial3D, so it matches the verge, as was done for the grass.
- **Parallax from the height maps.** Real depth when looking along the ground, which is how the road is seen from the car, at some GPU cost. A StandardMaterial3D can't use a height map with triplanar mapping, which every ground material uses, so it goes in the ground shaders: `shaders/ground_surface.gdshaderinc` for the grass and asphalt, and `vertex_ground.gdshader` for Mulholland. The ground is near flat, so offsetting only the top-down sample (the one taken in the world's XZ) is probably enough. Height maps: the asphalt's `DISP_2K` and the grass's `Displacement.tiff` are in `reference/tracks/` and not copied yet; the dirt's `HEIGHT_2K` and the gravel's `disp_2k` are already in `assets/textures/`. Check the cost on the Compatibility renderer, as the web build uses it.

## Free roam performance

Measured on 2026-11-14 on branch city-performance, free roam from the garage with the Corvette 1960 under xvfb with Vulkan on lavapipe and a fixed random seed, so the counts are good but the frame rate is not. Before: about 8,400 draw calls, 2.2 million triangles, 9,800 MeshInstance3D nodes and 12,900 nodes. After: about 830 draw calls, 1.6 million triangles, 930 MeshInstance3D nodes and 4,200 nodes. Done there: the scenery buildings merged into one mesh per 40 m square with their look on the vertices (`box_batch.gd`), the street lamps drawn as one MultiMesh until one is hit, the bushes split into 40 m squares with one MultiMesh each, materials shared between the places' boxes, traffic not drawn past 150 m, and the sun's shadows capped at 60 m. Left, in order of likely gain:

- **Lighter car models.** Traffic is 24 cars (`_COUNT` in `cruise_traffic.gd`). The SR1 bodies are 0.8 to 1.1 million triangles each (`sr1-c56` 1.03M, the 1932 coupe 819k, the Fairlane 752k) and the Styleline 387k, where the Corvette and F100 are 12k to 19k. Each wheel is 70k and each tire 43k, about 450k a car for the four corners. LODs are already generated on import. With traffic hidden the frame drops from 1.6 to 1.0 million triangles. Decimate those models, or give traffic a lighter wheel.
- **Reduce Tire polycount**
- **The places.** The garage, drive-in, gas station and Royal Rods are still built of separate boxes, now with shared materials. They are few, and the garage doors move, so they were not merged.
