# Chrysler 426 Hemi (Street Hemi)

| Path | What it is |
| --- | --- |
| `hemi-426.stl` | A rough sculpt of a Street Hemi with its transmission, dual quads and headers, given on 2026-11-26 as the reference for `tools/make_hemi.py`; copied from `~/Downloads`. One shell, 1,000,102 triangles, normalized to 1.0 along its length (no units); head, block and manifolds blend into each other |
| `24470110-B-RB-ENGINE.pdf` | Chrysler Direct Connection Race Bulletin #2 (P4007910, 1980), the B and RB wedge engines' racing manual: the raised block's dimensions, which the Hemi's own block shares, and notes on what Hemi parts interchange with the wedges (water pump, bellhousing, distributor by adapter, main bearings, oil and fuel pumps). Kept also for the 383 and 440 wedges planned later |
| `Hemi-cross-section.gif` | A cutaway across a race Hemi (cross-ram, headers): the heads' general shape, the plug tubes |
| `BB_Mopar_bell4.jpg` | The B/RB (and Hemi) bellhousing bolt pattern |
| `https:⁄⁄www.allpar.com⁄attachments⁄street-hemi-jpg.53141⁄…` | Chrysler's original design layout of the Hemi, July 1963 (titled "RB Hemi", allpar.com, courtesy of Willem Weertman): the head in plan, the intake flange and ports |
| `https:⁄⁄www.allpar.com⁄attachments⁄neon-20-jpg.53149⁄…` | A photo of a 1966 Street Hemi with tandem four-barrels (allpar.com via W. Weertman): the colors, the valve covers, the exhaust manifolds, the front |

No link or license was given for the STL. A CGTrader listing ("vintage-hemi-engine") was also suggested; its page would not load for a script, so nothing was taken from it.

## Scale and frame

The STL is scaled by 57.6 to inches, which puts its exhaust ports 4.80 in apart (the Hemi's bore spacing). In the script's frame (inches, +X toward the back, +Y right, +Z up, the crank on the X axis), the STL's (x, y, z) is (−(y − 0.1333) × 57.6, x × 57.6, (z + 0.1146) × 57.6): its front is +y, its right +x, its crank at z −0.1146.

## Numbers from Chrysler

The 426 Hemi is not one of the B or RB wedges: its block is its own casting, cross-bolted, with its own head bolt pattern and engine mounting lugs (bulletin p. 4), but it is laid out on the raised-block wedge's dimensions, so the deck height, bore spacing and stroke are the RB's.

| Dimension | Value |
| --- | --- |
| Deck height, crank to deck | 10.725 in (the raised block's, bulletin p. 4) |
| Bore × stroke | 4.25 × 3.75 in |
| Rod | 6.86 in |
| Bore spacing | 4.80 in (bulletin p. 4) |
| Bank angle | 90 degrees |
| Left bank | ahead of the right (cylinder 1 is the left front) |
| Distributor | right front: the bulletin (p. 2) puts all B and RB distributors there, and the Hemi takes an RB distributor (p. 4) |
| Oil filter | low on the left, on the oil pump |
| Water pump | interchangeable with the B and RB wedges' (bulletin p. 3) |

## What was taken from the sculpt

| Feature | Value (script frame) |
| --- | --- |
| Heads | the outline across the bank: exhaust face square to the ground at y ≈ 13.1, the rail from (14.0, 11.8) to (6.7, 16.2), the intake face high over the valley |
| Valve covers | the section: tall outer side leaning in, the top falling toward the valley, the crown at z ≈ 16.9 |
| Intake | one long body along the middle, carb pads near z 21, carburetors about 8 in apart |
| Front | the water pump high (hub at z ≈ 9.2), a big pump pulley, the alternator high on the right at (7.2, 10), the fan at x ≈ −19 |
| Oil pan | rail to about 12.3 in under the crank, deepest at the front |

The sculpt's pan rail sits at the crank's height, but Chrysler's big blocks are deep-skirted, so the script puts the rail 3 in below the crank. The sculpt's distributor stands in the middle of the front; the script follows Chrysler's right-front location.

From the 1966 photo: Hemi Orange paint, crinkle-black valve covers bolted round their flange with a well for each plug's wire on top, black pulleys and fan, cast exhaust manifolds shaped like headers with the outlet at the back.
