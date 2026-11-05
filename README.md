# Street Rod 3

A single-player garage and street-racing game built with Godot 4.6. Buy parts, paint the car, then race a rival on a quarter-mile drag strip, a road course, or Street Rod 2's street drag, Mulholland drive, and Aqueduct race.

**Play in the browser:** [https://streetrod3.github.io/StreetRod3/](https://streetrod3.github.io/StreetRod3/)

Pushes to `main` export a Web build and deploy it with GitHub Pages on [StreetRod3/StreetRod3](https://github.com/StreetRod3/StreetRod3).

## Play

| Action | Control |
| --- | --- |
| Throttle | W or Up |
| Brake | S or Down |
| Steer | A/D or Left/Right |
| Shift | Q / E |
| Reverse | Q from first gear (or drive) with the car stopped |
| Camera | C |

On a phone or a narrow window, on-screen pedals and a steering wheel replace the keyboard hint.

A steering wheel, pedals, a hand brake, and an H-pattern or sequential shifter or a wheel's paddles can be bound under Wheel and shifter setup in the settings. The keyboard keeps working alongside them. There is no force feedback, so the wheel only centers itself if its own settings do that.

New Game asks for your name on a driver's license, then starts you in the garage with cash, a basic car, and an automatic 3-speed. Click the newspaper to buy parts, and the garage doors to pick a rival. Rivals turn up one at a time: beat the newest and the next arrives in a faster car. Parts wear as you race, and tires worn right down blow out in the next race, which loses it and the set, and the spare-parts list shows each one's condition and has a Sell button: a buyer makes an offer you can accept or turn down for another. Click low on the car between the wheels (or press T) to get under it and change the transmission: back both bellhousing bolts out to drop the gearbox, select a spare, and tighten the bolts before driving out. Click the engine compartment (or press H) to work under the hood: back the bolts out of a part to lift it off, use Parts to put in a spare engine, camshaft (the heads have to be off to reach it), cylinder heads, intake, carburetor, distributor, or air cleaner, and tighten every bolt and put the plug wires on before the engine will run. Tune there brings up a timing light on the balancer; advance or retard the distributor until the mark lines up with the red pointer and the idle runs smooth. Click the creeper on the floor beside the car (or press U) to roll under it and change the exhaust manifolds, the exhaust, the mufflers, and the rear end: click a part to swap in a spare, take a muffler off to leave its pipe open, or take the exhaust off for open headers. A dual exhaust has a muffler on each side, and the two can differ. A shorter rear end pulls harder in every gear but tops out lower. The springs and shocks are changed there too. Stiffer springs lean less and hold the road better, but they want better shocks to go with them, and worn ones make a car wallow. Buy tires in the newspaper. To change them, take the wheels off the car from the wheel list, click the tire machine against the front wall (or press T), pick the wheels, and pick the tires. The old tires go to spare parts, and the wheels stay in spare parts until you put them back on the car. Tires do most for how the car holds and pulls. Wheels (click the jack or press W) can be changed or taken off, tires and all. They change the look, and a lighter set like the magnesium wheels adds a little pull. In a race, crashes add up. Barriers and the other car both do damage by how suddenly they change your speed, so a heavy car takes less from a light one. Damage cuts your power and wears your parts, and enough of it totals the car, yours or your rival's. Total your rival and you win the race and the money, but not the pink slips.

## Run locally

Install [Git LFS](https://git-lfs.com) and run `git lfs install` before you clone, because most of the models and the music are stored in it. Then install [Godot 4.6.1](https://godotengine.org/download) (standard build, not .NET), open this folder, and press F5. The main scene is `scenes/main_menu.tscn`.

Setup, Web export, and save-file locations are in [docs/setup.md](docs/setup.md). Architecture and the track file format are in [docs/architecture.md](docs/architecture.md) and [docs/track-format.md](docs/track-format.md). Known bugs are in [docs/bugs.md](docs/bugs.md).
