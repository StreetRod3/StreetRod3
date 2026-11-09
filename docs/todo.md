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
- **Real Ford Y-block and small-block.** The 292 and the 302 are stand-ins drawn with the Chevy models, and their speed parts are Ford copies of the Chevy ones with the same stats and looks.
- **The L79 small-block in the game.** `tools/l79_to_glb.py` turns the L79 327 STEP assembly into `assets/parts/engine-sbc-l79.glb`: the real block, heads, valve covers, intake, Holley 4160, distributor, coil, generator, water pump, fan, cast manifolds, starter, '65 Nova pan and the rest, at real size. The hood screen still draws the old `engine-v8-*.glb` and builds the alternator, belt and air cleaner in code; using it means new small-block constants in `engine_assembly.gd` (bores, plugs, carb pad, distributor, belt plane) as the flathead got. `tools/make_sbc.py`'s headers, air cleaner, alternator and fan (the parts of that model the user liked) could become part models beside it.
- **Chrysler.** The issue names it as a third make (issue #8); there are no Chrysler cars or engines yet.
- **The speed shop**, the only place to buy engine mounts for a swap across makes (`mounts` parts, `"shop": "speed"`).
