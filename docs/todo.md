# To do

Ideas that are wanted but not built yet. Bugs go in [bugs.md](bugs.md). Remove an entry when it lands, and record it in `changelog.md`.

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

Engines come in families now (`families` in `parts.register`), and only the Ford flathead is drawn for its era. Its numbers (150 hp, $600) sit well below the Chevy small-blocks on purpose: it is meant to line up against period Chevys that are coming, not against the 265 and up. Still to come:

- **Period Chevys** to match the flathead, each a family with its own stock heads, intake, camshaft, distributor and manifolds, and speed parts like the flathead's finned heads and three two-barrel intake.
- **Chevy inline six, 216 and 235.** The first period Chevy: one family in two variants, the 216 and the 235, the 235 with more performance. `tools/make_235.py` has the model (block, factory exhaust manifold, stock intake and stamped valve cover) and its speed parts: split cast iron headers, the finned aluminum valve cover and the two-carburetor intake. None of it is in the game yet: the parts, their stats and the hood screen's placement are still to do.
- **Real Ford Y-block and small-block.** The 292 and the 302 are stand-ins drawn with the Chevy models, and their speed parts are Ford copies of the Chevy ones with the same stats and looks.
- **Small-block speed parts as models.** The Chevys are drawn from `tools/make_sbc.py`'s model now, with its cast-iron manifolds and headers, but the high-rise, tri-power and dual-quad intakes, the two-barrel carburetor and the chrome air cleaner are still built from primitives in `engine_assembly.gd`. The Ford stand-ins still use the old `engine-v8-*.glb`.
- **Chrysler.** The issue names it as a third make (issue #8); there are no Chrysler cars or engines yet.
- **Studebaker.** The 1950 Studebaker Champion is in, but listed as a GM car on the Chevy 216 and its gearbox until there is material to build its own parts from (the 169.6 ci Champion six, or the Commander's 232 V8, and Studebaker gearboxes and rear ends). No stand-in parts drawn with other makes' models in the meantime.
- **The speed shop**, the only place to buy engine mounts for a swap across makes (`mounts` parts, `"shop": "speed"`).

## Free roam performance

Free roam is slow. Measured on 2026-11-12 at 3bf9541, free roam from the garage under xvfb with the compatibility renderer, so the counts are good but the frame rate is not: 9,517 MeshInstance3D nodes, about 6,700 draw calls and 1.7 to 1.8 million triangles a frame, 447 street-lamp OmniLight3Ds with 443 Area3Ds, and 12,500 nodes in the scene. The per-frame scripts are not the problem: the minimap only redraws when the car moves or turns, the bushes and trees are already MultiMeshes, and the HUD update is small. In order of likely gain:

- **Merge the buildings.** Every window is four separate boxes (`_add_window()` in `cruise.gd`), and every band, bracket and parapet piece is its own MeshInstance3D with its own BoxMesh. Building each building with SurfaceTool into one mesh per material, as `_road_meshes()` already does for the roads, should take the draw calls from about 6,700 to a few hundred with no change to how the city looks.
- **Share materials.** `_add_box()` in `cruise.gd` makes a new StandardMaterial3D on every call, so identical walls cannot batch. Cache them by color, roughness, metal and emission. Merging the buildings needs this to pay off fully.
- **Lighter car models.** Traffic is 24 cars (`_COUNT` in `cruise_traffic.gd`). The SR1 bodies are 0.8 to 1.1 million triangles each (`sr1-c56` 1.09M, the 1932 coupe 850k, the Fairlane 802k) and the Styleline 398k, where the Corvette and F100 are 12k to 19k. Each wheel is 70k and each tire 43k, about 450k a car for the four corners. LODs are already generated on import and the 1.7M is after them. Decimate those models, give traffic a `visibility_range_end` so distant cars drop out, or give traffic a lighter wheel.
- **Street lamps off by day.** All 447 OmniLight3Ds in `street_lamp.gd` are on in daylight. Distance fade is set, which helps. Turning the lights off by day, and drawing the poles and heads as MultiMeshes like the bushes, would cut more.
- **Shadow distance.** The free-roam sun (`_build_world()` in `cruise.gd`) uses the default shadow range, so every building wall in it is drawn again for shadows. The drive-in caps it at 45 m and the gas station at 40 m; something like that would suit free roam.
- **Hide detail at a distance.** Once a building is merged, its window and trim mesh can take a `visibility_range_end` of 80 to 100 m, so far buildings draw as plain blocks.
