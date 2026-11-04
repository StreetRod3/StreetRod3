# To do

Ideas that are wanted but not built yet. Bugs go in [bugs.md](bugs.md). Remove an entry when it lands, and record it in `changelog.md`.

## Make burnouts do something

Holding gas and brake with the car stopped is only for show so far: the rear wheels spin, the engine revs, and the tires smoke and mark the road (`_update_burnout()` in `player_race_car.gd`, `burn()` in `skid_marks.gd`). It gives the launch nothing and costs nothing. Decided on 2026-11-03 to start this way so it would not change the race balance.

- **Warm tires.** A launch bonus in the simulation from a burnout before the green light, fading over the first part of the race, with too long a burnout overheating the tires and costing grip. In the arcade drive it may stay for show, since launches there have no traction limit to improve.
- **Tire wear and fuel.** A burnout should cost rubber and gas. Tires already wear per race (`wear_parts_after_race()`), and they can blow when worn out.
- **Engine.** Holding it at the limit could add to engine wear or overheat a tired motor. For now it holds a steady 5000 rpm, safely under the rev limit, in any gear.
- **Sound.** Tire screech for burnouts, launches, and slides. There is no tire sound in the game yet. The AdLib engine sound takes its rpm from `get_rpm()`, so it already revs.
- **Rivals.** A rival could do a burnout at the line, more of them higher up the ladder, as a show of strength.
- **Reward.** The crowd or the rival could react, or a good burnout could pay a little at the drive-in.
- **A line lock part.** A part to buy that holds only the front brakes, which is what real drag cars use to do this.
- **Look.** The patch of rubber under a stopped tire is a simple dark quad, and it could grow and blend better. Smoke could hang longer in still air and depend on the tires, with more from slicks.

## Put back Mulholland's left-out boulders

The bake takes a boulder off the road where it would leave less than 3.2 m between it, a sawhorse, and fallen rocks (`keep_road_open()` in `tools/make_sr2_courses.py`). That is 1 or 2 a course, nearly always line 943, and each is recorded in its track's `left_out` list. Sawhorses are the reason: Street Rod 2 drives through them, and here they stop a car. To put the boulders back, a sawhorse could be knocked aside instead of stopping the car, or be made shorter at those spots. Sawhorses should not end up as the only solid thing on the road.

## Time of day

Street Rod 2's three races run at night for now and the other two by day (`_set_night()` in `race.gd`). Time could become a factor in races later.

