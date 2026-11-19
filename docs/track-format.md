# Track file format (`.trk`)

Race courses are stored as JSON graphs. The file extension is `.trk`. Street Rod 3 currently loads `res://assets/tracks/track1.trk` for the road race, `res://assets/tracks/street_drag.trk` for the street drag, `res://assets/tracks/mulholland_0.trk` to `mulholland_9.trk` for Mulholland drive, `res://assets/tracks/aqueduct.trk` for the Aqueduct race, and `res://assets/tracks/stunt.trk` for the stunt track. The developers' track maker ([track-maker.md](track-maker.md)) draws and edits these files and test-drives them.

The drag strip in `scenes/race.tscn` is still a separate, hardcoded layout. It does not use this format yet.

## Coordinates

`x` and `y` are planar meters in a top-down map.

| Track | Godot world |
| --- | --- |
| `x` | `X` (right) |
| `y` | `Z` (forward when yaw is 0) |
| `z` | `Y` (height). Omitted means `0`. |

A road from `(0, 0)` to `(0, 100)` runs along world `+Z`. A road from `(0, 0)` to `(100, 0)` runs along world `+X`. Height rises along world `+Y`.

## Root object

```json
{
  "name": "Track 1",
  "nodes": [ ... ],
  "roads": [ ... ],
  "pois": [ ... ]
}
```

| Field | Required | Default | Description |
| --- | --- | --- | --- |
| `name` | no | `""` | Display name. Unused by gameplay so far. |
| `nodes` | yes | — | Street vertices. |
| `roads` | yes | — | Directed edges between street nodes. |
| `pois` | no | none | Points of interest. Each one is its own node, attached to a street node. |
| `buildings` | no | none | Scenery boxes. They are not part of the road graph. |
| `style` | no | `"circuit"` | `circuit` builds curbs, barriers, narrow-road signs, and a checkered finish gantry. Its grass runs out from each side of the road at the road's height, sloping where another part of the course passes at another height to meet that road's grass halfway, and a car off the road drives on that same grass. `street` builds none of those. It uses the `scenery` list instead, greener grass, a gravel shoulder down each side, and pavement that runs back behind the start. `mountain` is Mulholland: no grass grid, hillsides and drops from each node's `left` and `right`, a guard rail, and truss bridges. `aqueduct` is a concrete channel with sloped banks, always the same width: a car is on the road anywhere out to the tops of its sides, whatever the roads' `width` (Street Rod 2's 11.73 m puts the edges just there). |
| `jumps` | no | `false` | Cars can leave the road. Where it drops away faster than a car can fall, at a lip or over a crest taken fast, the car flies until it lands. Only on a `circuit` track for now. It also keeps the grass flat under the road, so a car that leaves a ramp's side drops to the grass, builds the ramps' sides down to it as walls a car on the grass runs into, paints yellow and black bands up to each lip, and leaves out the curbs. Off on every other track, so their rises and dips drive as they did. |
| `auto_bank` | no | `false` | Every corner banks into its turn by how tight it is, in place of the nodes' own `bank`, which are kept but not used. See [Banking](#banking). |
| `loop` | no | `false` | The course comes back round to its start, which is also the finish line. The last node needs a road back to the start, and no node is a `finish`. The road runs round once with no pavement behind the start or past the finish, and the race counts laps by how far the car has gone round, so backing over the line doesn't count. The last road may come into the start at any angle: the race turns it onto the start straight round a corner set back behind the line, so the lap joins up and the cars still start on the straight. Only test drives use loops so far; a rival can't race one yet. |
| `sky` | no | `"day"` | The photographed sky over the course in races and test drives: `day`, `dusk`, `evening-orange`, `sunset-pink` or `night-stars`, from `scripts/skies.gd`. A sky whose file isn't in the game yet, or an unknown name, is the day sky. Street Rod 2's cruise races are at night: a course for one that leaves this out, or says `day`, gets their plain black sky, and any other sky replaces it (the street drag says `night-stars`). |
| `laps` | no | `1` | Times round a `loop`. The race shows the lap and, at the end of a test drive, the best lap. |
| `scenery` | no | none | What stands on and beside a `street`, `mountain`, or `aqueduct` track. See [Scenery](#scenery). |
| `terrain` | no | none | Painted ground: the ground's height wherever it has been painted, on any style. See [Painted ground](#painted-ground). |
| `left_out` | no | none | Things baked from Street Rod 2 but not put on the track, with where they were and why. The game does not read this. No track has one at the moment. |

Unknown root fields are ignored. A race course can leave `pois` out.

## Nodes

```json
{ "id": 1, "x": 0, "y": 0, "type": "start" }
```

| Field | Required | Default | Description |
| --- | --- | --- | --- |
| `id` | yes | — | Unique integer. |
| `x` | yes | — | Planar X in meters. |
| `y` | yes | — | Planar Y in meters (world Z). |
| `z` | no | `0` | Height in meters (world Y). Leave it out to stay on the ground. |
| `type` | no | `"regular"` | `start`, `finish`, or `regular`. |
| `left`, `right` | no | `0` | On a `mountain` track, the full height of a hillside (above 0) or drop (below 0) on the driver's left or right, in meters. It runs straight from node to node. On an `aqueduct` track, how high the channel's side stands on that side, in meters, up to 8; 0, or anything up to Street Rod 2's 1.51, is Street Rod 2's side. See [Raised Aqueduct sides](#raised-aqueduct-sides). |
| `rail` | no | `false` | On a `mountain` track, a guard rail on the driver's right from this node to the next. |
| `sharp` | no | `false` | The road's grade changes here at once, instead of rounding through the node. Two sharp nodes together make a straight ramp. A sharp node where the road then falls away more steeply than it came up is a lip. |
| `bank` | no | `0` | How far the road leans across at this node, in degrees, up to 45 either way. Above 0 the driver's left edge is higher, which leans into a bend to the right; below 0 the right edge is higher. See [Banking](#banking). |

### Node types

| Type | Meaning |
| --- | --- |
| `start` | Race spawn / path origin. If omitted, the first node is used. Extra starts are ignored after the first. |
| `finish` | Race end. The path stops when it first reaches a finish node after leaving start. If omitted, the last node is used. |
| `regular` | Intermediate waypoint. The default; the field can be omitted. |

## Roads

```json
{ "from": 1, "to": 2, "width": 8, "type": "narrow-left", "surface": "wet" }
```

Roads are **directed**. `from` and `to` must name existing nodes and must differ.

| Field | Required | Default | Description |
| --- | --- | --- | --- |
| `from` | yes | — | Start node id. |
| `to` | yes | — | End node id. |
| `width` | no | `8` | Full road width in meters (not half-width). |
| `type` | no | `"regular"` | Width / shoulder variant. |
| `surface` | no | `"regular"` | Surface material. |

### Road types

A narrow side loses **one third of the full road width** from that edge. Left / right are from the driver’s view traveling `from` → `to`.

| Type | Pavement | Barriers |
| --- | --- | --- |
| `regular` | Full width. Default; can be omitted. | No |
| `narrow` | Same as `narrow-both`. | No |
| `narrow-left` | Left edge moves in by `width/3`. | No |
| `narrow-right` | Right edge moves in by `width/3`. | No |
| `narrow-both` | Both edges move in by `width/3` (remaining width is `width/3`). | No |
| `narrow-obstacle` | Same as `narrow-both-obstacle`. | Yes |
| `narrow-left-obstacle` | Same cut as `narrow-left`. | Construction barriers on the closed left strip |
| `narrow-right-obstacle` | Same cut as `narrow-right`. | Construction barriers on the closed right strip |
| `narrow-both-obstacle` | Same cut as `narrow-both`. | Barriers on both closed strips |
| `bridge` | `width` as given, on a `mountain` track | Truss sides that stop a car |
| `gravel` | Full width, gray, handled like grass. A rival holds to 59 mph over it. | No |

Hitting a `-obstacle` barrier sets the car’s speed to **0** immediately.

### Surfaces

| Surface | Meaning | Used in gameplay today |
| --- | --- | --- |
| `regular` | Default asphalt. Can be omitted. | Parsed only |
| `dry` | Dry asphalt. | Parsed only |
| `wet` | Wet / rain. | Parsed only |
| `icy` | Ice / low grip. | Parsed only |

Surface is stored on path samples for later physics and visuals. It does not change grip yet.

## Race path

The loader walks directed roads from the start node, taking the first unused outgoing road at each node, and stops when it reaches a finish node (after at least one hop).

A closing road from finish back to start is allowed and is **not** followed, unless the track is a `loop`. On a loop the walk goes round to the start again and stops there, and fails unless it gets back to the start through at least two other nodes.

If the walk cannot leave start, loading fails.

## Banking

A node's `bank` tilts the road across, on any style. The road's low edge stays at the node's height and the other edge rises, so a 14 m road banked 25° is 6.5 m higher on its outside. On the Aqueduct the whole channel tilts, its sides included, about the tops of its sides.

| Where | What the bank does |
| --- | --- |
| Round a corner | The node's bank holds all the way round its curve, from where the curve begins to where it ends. |
| With `auto_bank` | Each corner leans into its turn as steeply as a car at 108 km/h needs to go round it with no grip, up to 30°, from the curve the race makes there (`TrackFile.auto_bank_deg()`). A 90° corner on long roads gets 30°, a 45° one about 25°, a gentle 20° bend about 11°. The start and finish of a course that isn't a loop, and any node on a straight, stay flat. |
| Between nodes | It eases from one node's bank to the next over the straight between their curves, so a car turns in on a road already banked. Past the finish it holds. |
| Beside the raised edge | On a `circuit`, the grass starts at the edge and falls 1 m for every 2 m out back to the ground, or by the halfway line to the next part of the course. On a `jumps` track it does the same from the flat grass there, and only a ramp's own height over the grass is a wall. On a `street` the gravel shoulder and then the grass fall the same way. On a `mountain` the verge stays at the edge's height and the hillside or drop rises or falls from there, then goes over to the far ground as it always does. On the `aqueduct` the concrete past a raised top falls the same 1 in 2. |
| Jumps | A ramp can be banked, and its lip bands tilt with it. A car leaves a banked lip leaning with the road and, in the air, eases to the lean of the ground under it, so it comes down square to where it lands. On a jump track the lean and the bank's pull are read from the ground the car is on, the road or the grass, so a car beside a ramp's side doesn't read the drop as a lean. |
| What stands on it | Curbs, barriers, signs and lip bands sit on the banked road, and on Mulholland the walls, guard rail and truss bridges stand on the raised edge. The circuit's finish line leans with the road, and its gantry stands as much higher as the raised edge. Scenery placed by height (trees, posts, rocks) stands on the ground where it is. The Street Rod 2 pieces made for one straight, flat course (the street drag's overhead sign, the Aqueduct's seams, drains and gutter) don't follow a bank. |
| Cars | They lean with the road. Both driving models feel it: the bank pulls a car toward its low side, which takes it round on its own at the bank's own speed, and turning toward the low side presses the tires harder, so they hold more. With both, a banked corner can be taken much faster than a flat one, as on a real banked track. The sums are in `scripts/road_bank.gd`. On a circuit or street they go by the ground's slope, the raised edge's grass included; on Mulholland and the Aqueduct by the road's bank alone, since their hillsides are walls and the Aqueduct's sides already push a car back down. A raised Aqueduct side counts as a bank too (see [Raised Aqueduct sides](#raised-aqueduct-sides)). |

## Raised Aqueduct sides

On an `aqueduct` track a node's `left` and `right` can stand that side of the channel higher than Street Rod 2's 1.51 m, while the floor stays flat and as wide. A raised side is a corner's high outside wall, for riding round it.

| What | How |
| --- | --- |
| Shape | Street Rod 2's side is a straight slope 1.78 m across. A higher side reaches 1.25 m farther out for each meter higher, and curves up from the floor like a bowl, flat at the bottom and steepest at its top, about 58°. It goes over from the straight slope to the bowl between 1.51 m and 3 m, so a side only a little higher is only a little curved. A 5 m side reaches 6.1 m out past the floor. |
| Along the course | As a bank does: a node's sides hold all round its corner and ease to the next node's over the straight between. Past the finish they hold. |
| Past the top | The yellow line runs along the top, and the concrete falls back from there 1 m for every 2 m out to Street Rod 2's height, as it does beside a banked top. The wall that keeps a car in the channel stands at the top. |
| With a bank | The bank tilts the channel about Street Rod 2's tops as before, and a wider bowl goes on tilting the same way, so it stands higher still on the bank's high side. |
| Cars | A car is on the road all the way to a raised side's top. Street Rod 2's sides push a car back to the floor. A raised side pushes less the more it curves, and not at all from 3 m up. Instead its slope counts as a bank (`race_track.gd`'s `bank_slope()`), so a car can run up it and be held round the corner. |
| What doesn't follow | Street Rod 2's seams and drains are drawn for its own sides, so on a raised side they don't follow it. |

## Painted ground

`terrain` holds ground painted in the track maker, so a course can climb a mountain or run down a holler between ridges rather than over flat ground. It works on every style. A track without it builds exactly as before.

```json
"terrain": [
  {"x": 0, "y": 0, "h": "eJzt..."},
  {"x": 1, "y": 0, "h": "eJzt..."}
]
```

| What | How |
| --- | --- |
| The grid | Heights on a square grid 4 m apart, in track meters, kept in chunks of 32 by 32 points (128 m a side). A chunk's `x` and `y` are its place counted in chunks, so chunk 1, 0 starts at track x 128, y 0. |
| `h` | The chunk's 1024 heights row by row along x, each a whole number of centimeters as a 32-bit little-endian integer, deflated and written in base64. -2147483648 marks a point that isn't painted. A chunk with nothing painted in it is left out of the file. Decoding is in `scripts/track_terrain.gd`. |
| Between points | The height is the painted points' around it, weighted by nearness, and it counts only as much as those points are painted. Where some of them aren't, the painted ground eases back to the style's own ground over the last 4 m. |
| Meeting the road | The road keeps its nodes' heights. Past the road's own edge, painted ground is cut down to meet it at no steeper than 45°, or built up to it at no steeper than about 31°, as a road cut through a hill or carried over a hollow on an embankment. A `bridge` stands over whatever is painted under it. The edge is a circuit's road edge, a street's gravel shoulder, Mulholland's gravel verge, and on the Aqueduct the top of a side and 1 m of concrete past its yellow line. |
| Unpainted ground | Keeps the style's own shape: a circuit's grass, a street's banks, Mulholland's hillsides and drops from each node's `left` and `right`, the Aqueduct's concrete. |
| How it's drawn | On a track with any painting, all the ground past the road's edge is drawn from the paint and the style's own ground together (`race_track.gd`'s `_build_painted_ground()`), unpainted parts included. A strip down each side of the road follows its edge exactly, from the road's edge (behind the start too) out 12 m, and a grid covers the rest: every 4 m in painted chunks and in unpainted ones near the road, 32 m away from it. Where the strip covers the ground the grid leaves it to the strip. It is grass, turning to dirt where it is steeper than about 35°, and on Mulholland its unpainted hillsides turn to dirt as they rise, as before. |
| Driving on it | A car can leave the road and drive over painted ground. Where it is painted, Mulholland's hillside walls and the Aqueduct's side walls are left out and Mulholland's drops don't send the car over an edge. Uphill slows the car and downhill speeds it up, in both driving models, and a slope across it leans and pulls it as a bank does. Ground steeper than about 37° (a rise of 0.75 m a meter) can't be climbed: it stops the car as a wall would, without damage, and the car slides along its foot. On the road nothing changes, so the road drives as it did. |

## Points of interest

A point of interest is not a street intersection. It lives in `pois`, has its own id, and names the street node its driveway joins.

```json
{ "id": "garage", "name": "Garage", "at": 1, "x": -12, "y": 0 }
```

| Field | Required | Default | Description |
| --- | --- | --- | --- |
| `id` | yes | — | Unique string, such as `garage` or `drive-in`. |
| `name` | no | the `id` | Display name. |
| `at` | yes | — | Id of the street node this place is attached to. |
| `x`, `y` | no | the street node's | Planar position of the stop, in the same meters as street nodes. Give both, or neither. |
| `z` | no | `0` | Height in meters (world Y). |

The cruise from one place to another drives from the origin's `x`/`y` onto its `at` node, follows directed roads to the destination's `at` node, and ends on the destination's `x`/`y`. When `x` and `y` are omitted, the stop is the street node itself.

`assets/maps/city.trk` is the town: the garage, the drive-in, and the gas station, plus scenery buildings.

## Buildings

Optional boxes for the city view. They do not affect the road graph or the cruise route.

```json
{ "x": 20, "y": 16, "w": 12, "d": 9, "h": 7, "color": [0.45, 0.42, 0.38], "sign": "MARKET" }
```

| Field | Required | Default | Description |
| --- | --- | --- | --- |
| `x`, `y` | yes | — | Planar center, same meters as street nodes. |
| `w` | no | `10` | Width along world X, in meters. |
| `d` | no | `8` | Depth along world Z, in meters. |
| `h` | no | `6` | Height in meters. |
| `color` | no | a neutral gray | `[r, g, b]` from 0 to 1. |
| `sign` | no | none | Shop name on the street sign, such as `MARKET`. Leave it out for a block of homes. |

## Scenery

A `street`, `mountain`, or `aqueduct` track lists what stands on and beside it. Height comes from the ground at that spot. On a `street` track nothing has collision. The kinds marked solid below stop a car, and a rival steers around them.

```json
{ "kind": "tree", "x": 5.78, "y": 120 }
```

| Field | Required | Description |
| --- | --- | --- |
| `kind` | yes | One of the kinds below. An unknown kind gives a warning and is left out. |
| `x`, `y` | yes | Planar position in meters. The driver heading along `+Y` has their right at `-X`. |

| Kind | What it is |
| --- | --- |
| `tree`, `big_tree`, `bare_tree` | A round tree, a larger one, and a sparse one. |
| `pole` | A telephone pole. |
| `gantry` | An overhead highway sign across the road. |
| `dash` | A 5 m road mark starting at `y`. |
| `finish` | The yellow finish line, 5 m long, starting at `y`. |
| `dark_streak` | A black mark on the shoulder, starting at `y`. |
| `shrub`, `bush` | A low shrub and a big bush. |
| `post` | A white roadside post with a blue band. |
| `rock`, `boulder_side` | Rocks beside the road. |
| `rockfall_left`, `rockfall_right` | Solid. Rocks reaching 2 m into the road from its edge, on that side. |
| `road_boulder` | Solid. A boulder on the road. |
| `road_rock` | A flat rock on the road. Going over it jolts the car and costs some speed. |
| `barricade` | A sawhorse reaching 2.6 m into the road from its edge. A car smashes through it, which costs some damage and a little speed, and the broken bits stay on the road. A rival goes around it if it can. |
| `road_work_sign`, `speed_sign`, `narrows_sign`, `curves_sign`, `curves_back_sign`, `chevron_left`, `chevron_right` | Signs. |
| `joint` | A seam across the Aqueduct's floor and banks. |
| `gutter` | The Aqueduct's dark middle, from `y` to `to`. |
| `drain` | Solid. A dark block on the bank on that side of the Aqueduct, 5 m long. |
| `stain` | A black patch on the floor. |
| `slab` | Solid. A low block 5.4 m wide and 5 m long across the middle of the floor. |
| `fin` | Solid. A wall 1.5 m high and 5 m long, standing along the floor. |

## Street drag

`street_drag.trk` is baked from Street Rod 2's cruise drag race (race kind 1, lines 200 to 380 of its road), using the SR2 port's own road builder from the EXE's starting seed. Its fixed parts are the same in every Street Rod 2 game: the straight road, the two rises and dips, the road marks, the shoulder, the telephone poles, and the finish. Its trees, its black marks, and the sign's position are random in Street Rod 2, rolled once per game. This file holds one such roll, and it is the same in every game here.

| Street Rod 2 | Here | Why |
| --- | --- | --- |
| One line | 5 m | From its mph, its speed table, and its road frame's pace: 15.5 to 17 ft a line, or about 900 m for the race. |
| Gray sprites at the road's edge, every fourth line | A continuous gravel shoulder, 0.75 m wide | They stand for a shoulder, drawn as strips only because of what the game could draw. |
| Road width 1800 | 8 m | The car's size in the same units suggests 5.4 to 7 m. 8 m is the format's default and leaves room to steer. |
| One height word | 0.4 m | Set by eye. Street Rod 2's height only shifts the view up and down, so it has no real size. |
| Heights running straight to a point | Nodes only at the tops, the bottoms, and where a rise leaves level road | The tops and bottoms stay at Street Rod 2's lines and heights, but the track's curve rounds them. In 3D the points looked and felt sharp. |

## Mulholland drive

`mulholland_0.trk` to `mulholland_9.trk` are baked from Street Rod 2's road race (race kind 0x10, lines 370 to 960) by the SR2 port's own road builder, one file for each of its ten courses. As in Street Rod 2, a new game picks one and keeps it, and the save holds which. What is random in Street Rod 2, such as the trees and rocks, is one roll from the EXE's starting seed. It differs a little between the files, because the courses clear different lines.

| Street Rod 2 | Here | Why |
| --- | --- | --- |
| One heading unit | 0.102 degrees | How far its car moves sideways for pointing off the road: 2 across per unit per line. So a turn is about 32 degrees over 225 m, a radius of 400 m. |
| A kind word above 0 or below 0 | A hillside or a drop, up to 17.8 m, on the same 1800 across to 8 m scale | The road race draws them as banks reaching full height in 600 across. |
| Touching a hillside, a barrier at speed, or a rock ends the race | A wall or solid object, with damage by how hard the car hits | Street Rod 3's own crash model. |
| Going off a drop with no barrier ends the race | The car is totaled | Only the left has no rail, as in Street Rod 2. |
| Over 60 mph on road work ends the race | The gravel handles like grass | A wreck totals a car here, and nothing in the 3D view says why. |
| The sawhorse is a sprite the car drives through | A car smashes through it, at 3 to 11% damage by speed and up to 3 m/s, and leaves debris | Driving through one untouched looks wrong in 3D. |
| Narrow road 800 across, with posts and bars | A 3.56 m truss bridge, 4.6 m high | Street Rod 2's bars are only 1.8 m up, under the car's own height. |

The bake takes a boulder off the road only where it and fallen rocks would leave less than 2.6 m, and records it in the track's `left_out` list. None comes to that, so all of Street Rod 2's boulders are on the road. Sawhorses don't count, since a car can go through them.

Oncoming and same-direction civilian traffic is spawned dynamically ahead of the racers, managed by `mulholland_traffic.gd` with 3D spline alignment, obstacle dodging, and two-way car bump resolution with both player and opponent.

## Aqueduct race

`aqueduct.trk` is baked from the same table Street Rod 2 builds for race kind 8, lines 8 to 342, at 5 m a line. It is all constants, so it is the same in every game.

| Street Rod 2 | Here | Why |
| --- | --- | --- |
| Strip 1480 to 3320 across, banks out to 1080 and 3720, tops at height 1660 against 2000 | Floor 8.2 m wide, banks 1.8 m across and 1.5 m high | Same scale as the road. |
| View turned as the car climbs a bank, and the car pushed back | The car rolls with the bank and is pushed back at 0.8 m/s, then 2.1 m/s high up | From its 15 and 25 across a frame. |
| Going over the top of a bank ends the race | A wall at the top, with damage by how hard the car hits | Street Rod 3's own crash model. |
| Fins 33 across wide | 0.3 m wide | At Street Rod 2's 0.15 m they are hard to see. |
| Touching the middle costs speed | Painted only | Not built yet. |

## Stunt track

`stunt.trk` is a test course for jumps, 1.5 km on a 14 m road, made by hand rather than baked from Street Rod 2. In order: a tabletop (a 15% kicker to a 1.5 m table 45 m long, then a ramp down), two rounded 3 m crests that throw a car past about 100 km/h, two 45 degree bends to the right, the big jump (a long climb to a 12% kicker 4 m up, with a landing that bends down after the lip like a ski jump's), and two short humps close together.

How a car flies is in `scripts/air_time.gd`. In the air it keeps the speed and heading it took off with, and its nose turns to the way it is flying. Landing up to 4 m/s into the road costs nothing; past that, half the rest is a hit to the car, as if from a barrier. A rival flies the same way, off its line, and once down it drives back to the line from the closest point to where it landed.

Measured with the stock Corvette in the arcade drive, foot down: the tabletop 20 m at 93 km/h, each crest about 47 m at 150 km/h, the big jump 64 m at 150 km/h, 3.3 m over the road at the top, with 12% damage on landing. About 17% for a whole run. At 80 km/h every jump is free.

## Example

```json
{
  "nodes": [
    { "id": 1, "x": 0, "y": 0, "type": "start" },
    { "id": 2, "x": 100, "y": 0, "z": 4 },
    { "id": 3, "x": 100, "y": 80 },
    { "id": 4, "x": 0, "y": 80, "type": "finish" }
  ],
  "roads": [
    { "from": 1, "to": 2, "width": 8 },
    { "from": 2, "to": 3, "width": 8, "type": "narrow-left" },
    { "from": 3, "to": 4, "width": 8, "surface": "wet" },
    { "from": 4, "to": 1, "width": 8 }
  ]
}
```

This is a 400 m-ish rectangle. Node 2 is 4 m above the ground. The others stay at 0 because `z` is left out. The last road is a circuit closer and is ignored for the start→finish race path.

## Shipping

`.trk` files are not Godot-imported resources. Web export includes them through `include_filter=*.trk` in `export_presets.cfg`. Read them at runtime with `TrackFile.load_path("res://assets/tracks/....trk")`.
