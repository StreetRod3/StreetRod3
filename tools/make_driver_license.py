#!/usr/bin/env python3
"""Build assets/ui/driver_license.svg: the printed card with its text outlined
(Godot's SVG importer does not draw <text>), plus a layer of live sample text
that marks where the game prints each value. Run from the project root."""
import subprocess
import sys
import tempfile
from pathlib import Path

OUT = Path("assets/ui/driver_license.svg")

NAVY = "#2e3a70"
GOLD = "#d8ae45"
BAND_INK = "#3a3322"
TEAL = "#4f8397"
LABEL = "#85857e"
RULE = "#6e6e68"
SEAL = "#7fb0ae"
YEAR = "#3f4a82"
YEAR_WORN = "#8f97c0"

SANS = "font-family:'Nimbus Sans'"
NARROW = "font-family:'Nimbus Sans Narrow'"


def label(x, y, text, size=13):
    return f'<text x="{x}" y="{y}" style="{SANS};font-size:{size}px;letter-spacing:1px;fill:{LABEL}">{text}</text>'


def dot(x, y):
    return f'<circle cx="{x}" cy="{y}" r="3.2" fill="#2b2b2b"/>'


def box(x, y, w=24, h=24):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="none" stroke="{RULE}" stroke-width="1.6"/>'


# The year is a typed look: heavy ink with pale flecks, as on the photo.
YEAR_STROKES = [
    ("M95 206L104.5 199L105 241", "3 11 5 14"),
    ("M171 212C171 203 167 198.5 160 198.5C153 198.5 149.5 203 149.5 210C149.5 216.5 154 220 160.5 220C165 220 169 217 171 212C172.5 222 172 231 169 236C165 242.5 156 243 151 236", "4 13 6 16 3 11 5 19"),
    ("M209 203L231 201Q225 215 219 228Q216 236 218.5 241.5", "3 12 6 9 4 15"),
    ("M264 203L286.5 201.5Q280 216 275 229Q273 237 273.5 244", "4 15 6 10 3 13"),
]


def year_digits():
    ink = "".join(f'<path d="{d}" stroke="{YEAR}" stroke-width="6.5"/>' for d, _ in YEAR_STROKES)
    core = "".join(f'<path d="{d}" stroke="{YEAR_WORN}" stroke-width="2" stroke-dasharray="{dash}"/>'
                   for d, dash in YEAR_STROKES)
    return f'<g id="expires-year" fill="none" stroke-linecap="round" stroke-linejoin="round">{ink}{core}</g>'


ART = f"""<svg xmlns="http://www.w3.org/2000/svg" width="930" height="622" viewBox="0 0 930 622">
<g id="card">
  <rect id="stock" width="930" height="622" rx="12" fill="#ebe8dc"/>
  <path id="portrait-slot" d="M0 280H276V622H12A12 12 0 0 1 0 610Z" fill="#8ea8bf"/>
</g>
<g id="heading">
  <text transform="translate(40 76) scale(0.94 1)" style="{SANS};font-weight:bold;font-style:italic;font-size:73px;fill:{NAVY}">CALIFORNIA</text>
  <text transform="translate(480 78) scale(0.91 1)" style="{NARROW};font-size:61px;letter-spacing:4px;fill:{NAVY}">DRIVER LICENSE</text>
  <rect id="band" y="82" width="930" height="34" fill="{GOLD}"/>
  <text transform="translate(25 106) scale(0.902 1)" style="{NARROW};font-weight:bold;font-size:25px;letter-spacing:0.35px;fill:{BAND_INK}">MUST BE CARRIED WHEN OPERATING A MOTOR VEHICLE AND WHEN APPLYING FOR RENEWAL</text>
</g>
<g id="expires" style="{SANS};font-weight:bold;font-size:26px;letter-spacing:2.5px;fill:{TEAL};text-anchor:middle">
  <text x="140" y="143">EXPIRES ON</text>
  <text x="140" y="177">BIRTHDAY IN</text>
</g>
{year_digits()}
<g id="seal" transform="translate(858 200)" fill="none" stroke="{SEAL}">
  <path id="seal-ring" d="M0 53A53 53 0 1 1 0 -53A53 53 0 1 1 0 53" stroke="none"/>
  <circle r="66" stroke-width="2.6"/>
  <circle r="46" stroke-width="2"/>
  <text style="{SANS};font-weight:bold;font-size:12.5px;letter-spacing:2.5px;fill:{SEAL};stroke:none"><textPath href="#seal-ring">THE GREAT SEAL OF THE STREET ROD *</textPath></text>
  <g fill="{SEAL}" stroke="none">
    <circle cx="-12" cy="-14" r="10"/>
    <path d="M-12 -30V-27M-27 -24L-25 -22M3 -24L1 -22M-31 -14H-27M3 -14H7" stroke="{SEAL}" stroke-width="2"/>
    <path d="M-44 8L-26 -8L-14 2L4 -18L22 0L30 -6L45 8Z"/>
  </g>
  <path d="M-42 15Q-35 10 -28 15T-14 15T0 15T14 15T28 15T42 15M-37 25Q-30 20 -23 25T-9 25T5 25T19 25T33 25M-26 34Q-19 29 -12 34T2 34T16 34T26 34" stroke-width="2.4"/>
</g>
<g id="form">
  {dot(336, 156)}{dot(336, 190)}{dot(336, 224)}{dot(336, 256)}
  {label(346, 293, "SEX")}{label(392, 293, "HAIR")}{label(474, 293, "EYES")}{label(554, 293, "HEIGHT")}{label(674, 293, "WEIGHT")}{label(780, 293, "PREV LIC")}
  {label(346, 350, "DATE OF BIRTH")}{label(674, 350, "DATE ISSUED")}
  {label(346, 413, "OTHER", 12)}{label(346, 428, "ADDRESS", 12)}{label(346, 452, "CLASS", 12)}
  {dot(306, 446)}
  {label(424, 444, "ISSUED SUBJECT TO THE VEHICLE CODE OF THE STATE OF CALIFORNIA", 10.5)}
  {label(424, 458, "AND TO ANY RESTRICTIONS SHOWN ON THE REVERSE SIDE", 10.5)}
  {label(346, 489, "SEE REVERSE SIDE FOR RESTRICTIONS", 11.5)}{box(610, 472)}
  {label(730, 481, "MUST WEAR", 11.5)}{label(730, 495, "CORRECTIVE LENSES", 11.5)}{box(892, 472)}
</g>
<g id="signature">
  <path d="M344 548L358 562M358 548L344 562" stroke="#2b2b2b" stroke-width="2" fill="none"/>
  <path d="M344 558H930M344 596H500" stroke="{RULE}" stroke-width="1.6" fill="none"/>
</g>
<g id="footer" style="{SANS};font-size:26px;letter-spacing:2.6px;fill:{TEAL}">
  <text x="494" y="616">DO NOT LAMINATE</text>
  <circle cx="454" cy="607" r="3.6"/><circle cx="470" cy="607" r="3.6"/>
  <circle cx="784" cy="607" r="3.6"/><circle cx="800" cy="607" r="3.6"/>
</g>
</svg>
"""


def field(ident, x, y, text, size=30, color="#25252a", extra=";letter-spacing:1.8px"):
    return (f'    <text id="field-{ident}" x="{x}" y="{y}" style="font-family:\'Liberation Mono\';'
            f'font-weight:bold;font-size:{size}px;fill:{color}{extra}">{text}</text>\n')


FIELDS = (
    "  <!-- Sample values, one id per field, showing where the game prints each one. Godot's SVG\n"
    "       importer does not draw text, so the card still imports blank and the screen prints these\n"
    "       itself; x and y are the left end of the text baseline. Name and address lines hold 28\n"
    "       characters before they reach the right edge of the card. field-portrait is hidden because\n"
    "       Godot would draw it. -->\n"
    '  <g id="fields">\n'
    '    <g id="field-portrait" style="display:none" transform="translate(138 622)" fill="#5a6d82">\n'
    '      <circle cy="-210" r="62"/>\n'
    '      <path d="M-138 0V-70Q-138 -125 -60 -135Q0 -115 60 -135Q138 -125 138 -70V0Z"/>\n'
    '    </g>\n'
    + field("number", 354, 166, "R1234567")
    + field("name", 354, 200, "JOHNNY RAY DRAGSTER")
    + field("address", 354, 234, "1234 HOT ROD LN")
    + field("city", 354, 266, "VALLEY CITY, CAL, 90000")
    + field("sex", 354, 336, "M")
    + field("hair", 392, 336, "BRN")
    + field("eyes", 474, 336, "BRN")
    + field("height", 554, 336, "5-08")
    + field("weight", 674, 336, "165")
    + field("prev-lic", 794, 336, "73")
    + field("birth", 354, 400, "08-13-55")
    + field("issued", 674, 400, "08-13-73")
    + field("signature", 366, 548, "Johnny Ray Dragster", 40, "#2a2d55",
            ";font-family:'Z003';font-weight:normal;font-style:italic")
    + '  </g>\n'
)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp, "src.svg")
        flat = Path(tmp, "flat.svg")
        src.write_text(ART)
        subprocess.run(["inkscape", str(src), "--export-text-to-path", "--export-plain-svg",
                        f"--export-filename={flat}"], check=True, stderr=subprocess.DEVNULL)
        svg = flat.read_text()
    if "<text" in svg:
        sys.exit("text left in the outlined art")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(svg.replace("</svg>", FIELDS + "</svg>"))
    print(OUT, OUT.stat().st_size)


main()
