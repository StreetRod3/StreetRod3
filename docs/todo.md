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

The stunt track (`assets/tracks/stunt.trk`) is a first test of cars leaving the road. Not built yet:

- **Gap jumps.** The road's height is one value along it, so there are no holes. A gap needs a face a car can hit when it comes up short, which is a wall rather than a road to climb.
- **The car in the air.** It keeps its pitch to the way it is flying, with no rotation of its own from the takeoff, no throttle or brake effect, and no suspension stretching out. The wheels keep turning at road speed.
- **The rival.** Only its height flies; it keeps driving its line, and can speed up, in the air.
- **Other tracks.** Jumps are off everywhere else. The street drag's rises could throw a fast car if they were on there, which may suit "it can be fun to hit the peaks".
- **Scenery.** The track is bare: no crowd, no signs, nothing beside the road.
