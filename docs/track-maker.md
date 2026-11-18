# Track maker

The track maker draws race courses and takes them for a test drive. It is a developer tool for now: open it by typing `trackmaker` at the main menu's ~ prompt. Players will get it later.

It reads and writes `.trk` files, described in [track-format.md](track-format.md). The 3D road, hills, rails, bridges, jumps and scenery are all built by the game from the file, so what you see on a test drive is what a race on that file would look like.

## The screen

| Part | What it does |
| --- | --- |
| Map | The course from above, as the driver sees it: ahead from the start (+Y) is up and the driver's right (-X) is on the right. Roads are drawn at their width and colored by type. The start is green with an arrow, the finish red, sharp nodes are squares, and heights and banks show beside the nodes ("L up 25°" is a bank with the left edge up). |
| Height strip | Each node's height along the course, start on the left. Drag a node up or down to set its height, in 0.1 m steps. The game rounds the grade through nodes that aren't sharp, so the real road is smoother than the strip's straight lines. |
| Side panel | The file, the track's name, style and jumps, the tool, the selected node and the road leaving it, the scenery kind, and what the game's loader says about the course. |

## Loops and laps

Tick "Loop (the finish is the start)" for a track you drive laps on, and set the laps below it. The road from the last node back to the start becomes part of the course: it is drawn as a road, clicking it splits it, and selecting the last node edits it as "Road to the next node". The start gets a red ring as the finish line too. The length shown is one lap, and the height strip ends on the start again.

The road back to the start can come in at any angle. The race rounds that corner off behind the line, so the road is already on the start straight when it crosses it. Unticking Loop takes the road back to the start away again.

## Banking

Bank, under Sharp in the selected node's fields, leans the road across at that node, up to 45° either way, on a circuit track. Above 0 the left edge is up, for a bend to the right; below 0 the right edge is up. The line under it says which edge is up and whether that leans into the node's bend or out of it (off-camber). The bank holds all round the node's corner and eases to the next node's over the straight between, so give a straight's middle node a bank of 0 if the straight should be flat. On other styles the maker warns that the road won't bank. How the game builds and drives a banked road is in [track-format.md](track-format.md#banking).

## Sky

Sky, under Laps, picks the photographed sky over the course in races and test drives. A sky whose file isn't in the game yet says "file missing: day sky" and races under the day sky until it is added. The track keeps the choice either way, so adding the file later is enough. The skies, and how to add one, are in [ground-textures.md](ground-textures.md#skies).

## Mouse and keys

| Input | Road tool | Scenery tool |
| --- | --- | --- |
| Left click on empty ground | Adds a node at the finish end | Places the chosen kind |
| Left click on a road | Splits it there with a new node | — |
| Left drag | Moves a node | Moves a placed thing |
| Right or middle drag | Moves the map | Moves the map |
| Wheel | Zooms at the pointer | Zooms at the pointer |
| Delete or Backspace | Deletes the selected node | Deletes the selected thing |

| Key | What it does |
| --- | --- |
| Ctrl+Z, Ctrl+Y (or Ctrl+Shift+Z) | Undo and redo, up to 200 steps |
| Ctrl+S, Ctrl+Shift+S | Save, save as |
| F | Fit the whole course on the map |
| F5 | Test drive |
| Esc | Back to the main menu (asks first if there are unsaved changes) |

"Snap to 5 m" puts new and dragged nodes and scenery on a 5 m grid.

## Rules it keeps

- The course is one chain of nodes from the start to the finish. The first node is the start and the last is the finish, or on a loop the start is both; their `type` is written on save.
- The start stays at 0, 0 and the second node stays on the +Y axis, because the race scene puts the cars at the origin facing +Y. The start can't be dragged or deleted, and node 2 only slides ahead.
- A new node at the finish end copies the last road's width, type and surface, and the last node's height and mountain sides. A node that splits a road copies that road and takes a height between its neighbors.
- Fields left at their defaults are left out of the file: height 0, not sharp, width 8, regular road, regular surface.
- Scenery only shows on `street`, `mountain` and `aqueduct` tracks, as in the game. The maker warns when a circuit has some.

## Files

| Where | What |
| --- | --- |
| `user://tracks/` | Where Open and Save start. Under `~/.local/share/godot/app_userdata/Street Rod 3/tracks/` on Linux. |
| `assets/tracks/` | The game's own tracks. "Open game track..." starts here, and only shows when the game runs from the project rather than an exported build. Save writes straight back to the file, so the change shows in git. |
| `user://track_maker_test.trk` | The course as it was sent on the last test drive. |

Opening a file reads it along its race path. Fields the maker doesn't edit are kept and written back in place: node ids, `pois`, `buildings`, `left_out`, a closing road from the finish back to the start, and extra scenery fields such as `to`. Nodes and roads off the race path are left out, with a warning.

Files are written in the layout the bake tools use (`tools/make_sr2_courses.py`, `tools/make_street_drag.py`): one line for each node, road, and piece of scenery. Measurements keep a decimal point (`8.0`), ids are whole numbers, and other numbers are written exactly as read. Saving a game track without editing it leaves the course the same. The Mulholland files come back byte for byte. The Aqueduct and street drag change only `0` to `0.0` in a few places, and `track1.trk` and `stunt.trk`, which are laid out one field to a line, change layout the first time they are saved. `tests/track_maker_test.gd` checks this for every track.

## Test drive

F5 or "Test drive" checks the course, writes it to `user://track_maker_test.trk`, and starts the real race scene on it, with your current car and driving settings. At the main menu that is the stock Corvette, since no game is loaded.

- There is no rival. It is moved out of the way and switched off.
- The lights count down as in a race.
- Nothing is kept: no fuel is burned, nothing wears, a blown engine stays in, a wreck doesn't total the car, and no tires blow.
- Crossing the finish shows the time; on a loop of more than one lap it shows the lap ("Lap 2 of 3") while driving and the best lap at the end. A wreck or a blown engine ends the drive. Either way a click goes back to the maker.
- The pause menu's "Back to track maker" leaves straight away.
- The maker comes back as it was, with its undo history, view and selection.

A course with errors can't be test-driven; the panel lists what to fix.

## Code

| File | What it holds |
| --- | --- |
| `scripts/track_maker.gd`, `scenes/track_maker.tscn` | The screen, files, undo, and the test drive |
| `scripts/track_maker_doc.gd` | The course: reading, writing, editing, and checking it |
| `scripts/track_maker_map.gd` | The top-down map |
| `scripts/track_maker_profile.gd` | The height strip |
| `GameState.begin_test_drive()`, `end_test_drive()`, `RACE_TEST` | The test drive race type |
| `race.gd`, `_test_drive` | What a test drive does differently in the race |

Not built yet: rivals on made tracks (loops included), a menu entry for players, a 3D preview while editing, and drawing a curve that becomes nodes. See [todo.md](todo.md).
