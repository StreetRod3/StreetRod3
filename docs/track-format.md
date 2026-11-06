# Track file format (`.trk`)

Race courses are stored as JSON graphs. The file extension is `.trk`. Street Rod 3 currently loads `res://assets/tracks/track1.trk` for the road race, `res://assets/tracks/street_drag.trk` for the street drag, `res://assets/tracks/mulholland_0.trk` to `mulholland_9.trk` for Mulholland drive, `res://assets/tracks/aqueduct.trk` for the Aqueduct race, and `res://assets/tracks/stunt.trk` for the stunt track.

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
| `style` | no | `"circuit"` | `circuit` builds curbs, barriers, narrow-road signs, and a checkered finish gantry. `street` builds none of those. It uses the `scenery` list instead, greener grass, a gravel shoulder down each side, and pavement that runs back behind the start. `mountain` is Mulholland: no grass grid, hillsides and drops from each node's `left` and `right`, a guard rail, and truss bridges. `aqueduct` is a concrete channel with sloped banks, where the road's width takes in the floor and both banks. |
| `jumps` | no | `false` | Cars can leave the road. Where it drops away faster than a car can fall, at a lip or over a crest taken fast, the car flies until it lands. Only on a `circuit` track for now. It also keeps the grass flat under the road, builds the ramps' sides down to it, paints yellow and black bands up to each lip, and leaves out the curbs. Off on every other track, so their rises and dips drive as they did. |
| `scenery` | no | none | What stands on and beside a `street`, `mountain`, or `aqueduct` track. See [Scenery](#scenery). |
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
| `left`, `right` | no | `0` | On a `mountain` track, the full height of a hillside (above 0) or drop (below 0) on the driver's left or right, in meters. It runs straight from node to node. |
| `rail` | no | `false` | On a `mountain` track, a guard rail on the driver's right from this node to the next. |
| `sharp` | no | `false` | The road's grade changes here at once, instead of rounding through the node. Two sharp nodes together make a straight ramp. A sharp node where the road then falls away more steeply than it came up is a lip. |

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

A closing road from finish back to start is allowed (a circuit) and is **not** followed for a single-lap point-to-point race.

If the walk cannot leave start, loading fails.

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

Oncoming traffic is not built.

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

How a car flies is in `scripts/air_time.gd`. In the air it keeps the speed and heading it took off with, and its nose turns to the way it is flying. Landing up to 4 m/s into the road costs nothing; past that, half the rest is a hit to the car, as if from a barrier. A rival flies too, but only its height: it keeps driving its line in the air.

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
