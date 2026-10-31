# Street Rod 3

A single-player garage and street-racing game built with Godot 4.6. Buy parts, paint the car, then race a rival on a quarter-mile drag strip or a road course.

**Play in the browser:** [https://streetrod3.github.io/StreetRod3/](https://streetrod3.github.io/StreetRod3/)

Pushes to `main` export a Web build and deploy it with GitHub Pages on [StreetRod3/StreetRod3](https://github.com/StreetRod3/StreetRod3).

## Play

| Action | Control |
| --- | --- |
| Throttle | W or Up |
| Brake | S or Down |
| Steer | A/D or Left/Right |
| Shift (manual gearbox) | Q / E |
| Camera | C |

On a phone or a narrow window, on-screen pedals and a steering wheel replace the keyboard hint.

New Game starts in the garage with cash, a basic car, and an automatic 3-speed. Click the newspaper to buy parts, and the garage doors to pick a rival. Click low on the car between the wheels (or press T) to get under it and change the transmission: back both bellhousing bolts out to drop the gearbox, select a spare, and tighten the bolts before driving out. Click the engine compartment (or press H) to work under the hood: back the bolts out of a part to lift it off, use Parts to put in a spare engine, intake, carburetor, distributor, or air cleaner, and tighten every bolt and put the plug wires on before the engine will run. Tune there brings up a timing light on the balancer; advance or retard the distributor until the mark sits at the timing on the tune-up sticker. Click the creeper on the floor beside the car (or press U) to roll under it and change the exhaust manifolds, the exhaust, the mufflers, and the rear end: click a part to swap in a spare, take a muffler off to leave its pipe open, or take the exhaust off for open headers. A dual exhaust has a muffler on each side, and the two can differ. A shorter rear end pulls harder in every gear but tops out lower.

## Run locally

Install [Godot 4.6.1](https://godotengine.org/download) (standard build, not .NET), open this folder, and press F5. The main scene is `scenes/main_menu.tscn`.

Setup, Web export, and save-file locations are in [docs/setup.md](docs/setup.md). Architecture and the track file format are in [docs/architecture.md](docs/architecture.md) and [docs/track-format.md](docs/track-format.md).
