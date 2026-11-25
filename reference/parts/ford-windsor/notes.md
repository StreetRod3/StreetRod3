# Ford small-block V8 (Windsor: 260, 289, 302, 351 W)

| Path | What it is |
| --- | --- |
| `351W-Assembly.STEP` | A SolidWorks 2018 model of a 351 W (exported 2022-03-03), given on 2026-11-24 as the reference for `tools/make_sbf.py`; copied from `~/Downloads`. Two solids: the block with the pan, timing cover and balancer, and the heads, valve covers and intake fused together. No part names, no internals. Its intake is a modern fuel-injected one, its valve covers finned aluminum, its front a serpentine drive |
| `renders/` | Orthographic renders of the STEP from the front, both sides and the top, with a one-inch grid in the script's design frame (inches from the crank, +X toward the back, +Y right, +Z up, the block's middle at X 0) |

No link or license was given for the STEP.

## What was taken from it

The STEP is in inches (millimeters once FreeCAD reads it). Measured in the script's frame:

| Dimension | Value |
| --- | --- |
| Crank axis | the balancer's and the rear main flange's axis |
| Cam bore | 4.93 in above the crank |
| Deck, crank to deck | 9.635 in on the STEP; the script uses Ford's 8.206 in (260, 289, 302) and 9.480 in (351 W) instead |
| Bank angle | 90 degrees |
| Deck width | 2.75 in out and 4.55 in in from the bank's axis |
| Bore spacing | 4.38 in (111.2 mm) |
| Bank offset | the right bank 0.84 in ahead of the left |
| Block faces | back (bellhousing) at X 9.91, front at -9.91; the timing cover's seal face -11.97, its pump face -12.95 |
| Heads | 19.75 in long, centered on their bores; the outline across them in each deck's frame is in `HEAD` |
| Exhaust ports | 0.99 in behind each right bank bore (ahead on the left), high on the exhaust face; two bolts 2.58 in apart |
| Plugs | axis (-0.293, 0.93, 0.221) on the right bank, out, forward and a little up; 0.21 in ahead of each bore |
| Lower head bolts | five a side, 4.38 in apart, on the ledge under the exhaust face |
| Intake ports | at the bores; six bolts a side, 0.715, 4.375 and 9.445 in each way from the bank's middle |
| Distributor | at X -9.34, Y -0.89 |
| Thermostat | at X -10.29, Y 2.58 |
| Oil pan | rail 2.62 in below the crank; the bottom 6.55 in below the crank at the front, 5.57 through the middle, the rear sump 7.93 |
| Balancer | 6.4 in across, X -13.45 to -14.75 |

Not in the STEP, so drawn from Ford's layout of the sixties: the stock cast-iron four-barrel intake, the carburetor and air cleaner (`make_sbc.py`'s), the distributor and coil, the water pump, the V-belt pulleys and fan, the alternator on the right, the fuel pump on the timing cover's left, the oil filter low at the front on the left, the starter on the right, the stamped valve covers and the headers. The cast-iron exhaust manifolds are shaped from product photos of stock 260/289/302 manifolds the user sent on 2026-11-25 (not kept here): a flange on each port, a runner curving down from each into a body well under the ports, the plugs in the openings between the runners, the outlet turned down at one end. Sizes were scaled from the 4.38 in port spacing.
