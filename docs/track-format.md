# Track file format (`.trk`)

Race courses are stored as JSON graphs. The file extension is `.trk`. Street Rod 3 currently loads `res://assets/tracks/track1.trk` for the road race and `res://assets/tracks/street_drag.trk` for the street drag.

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
| `style` | no | `"circuit"` | `circuit` builds curbs, barriers, narrow-road signs, and a checkered finish gantry. `street` builds none of those. It uses the `scenery` list instead, greener grass, a gravel shoulder down each side, and pavement that runs back behind the start. |
| `scenery` | no | none | What stands beside a `street` track. See [Scenery](#scenery). |

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
{ "x": 20, "y": 16, "w": 12, "d": 9, "h": 7, "color": [0.45, 0.42, 0.38] }
```

| Field | Required | Default | Description |
| --- | --- | --- | --- |
| `x`, `y` | yes | — | Planar center, same meters as street nodes. |
| `w` | no | `10` | Width along world X, in meters. |
| `d` | no | `8` | Depth along world Z, in meters. |
| `h` | no | `6` | Height in meters. |
| `color` | no | a neutral gray | `[r, g, b]` from 0 to 1. |

## Scenery

A `street` track lists what stands beside it. Each entry has no collision. Height comes from the road at that spot.

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

## Street drag

`street_drag.trk` is baked from Street Rod 2's cruise drag race (race kind 1, lines 200 to 380 of its road), using the SR2 port's own road builder from the EXE's starting seed. Its fixed parts are the same in every Street Rod 2 game: the straight road, the two rises and dips, the road marks, the shoulder, the telephone poles, and the finish. Its trees, its black marks, and the sign's position are random in Street Rod 2, rolled once per game. This file holds one such roll, and it is the same in every game here.

| Street Rod 2 | Here | Why |
| --- | --- | --- |
| One line | 5 m | From its mph, its speed table, and its road frame's pace: 15.5 to 17 ft a line, or about 900 m for the race. |
| Gray sprites at the road's edge, every fourth line | A continuous gravel shoulder, 0.75 m wide | They stand for a shoulder, drawn as strips only because of what the game could draw. |
| Road width 1800 | 8 m | The car's size in the same units suggests 5.4 to 7 m. 8 m is the format's default and leaves room to steer. |
| One height word | 0.4 m | Set by eye. Street Rod 2's height only shifts the view up and down, so it has no real size. |

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
