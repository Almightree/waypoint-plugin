"""Generate the original north/up arrow. Python 3, no external packages."""
from pathlib import Path
import struct

SIZE = 64
POLYGON = [(32, 5), (55, 44), (35, 35), (35, 58), (29, 58), (29, 35), (9, 44)]


def inside(x, y):
    result = False
    for a, b in zip(POLYGON, POLYGON[1:] + POLYGON[:1]):
        if (a[1] > y) != (b[1] > y) and x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]:
            result = not result
    return result


pixels = bytearray()
# Uncompressed BGRA, bottom-left origin, eight alpha bits; 4x coverage antialiasing.
for y in reversed(range(SIZE)):
    for x in range(SIZE):
        coverage = sum(inside(x + (sx + .5) / 4, y + (sy + .5) / 4) for sy in range(4) for sx in range(4))
        pixels.extend((255, 255, 255, round(255 * coverage / 16)))
header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x08)
target = Path(__file__).resolve().parents[1] / "AlmightreeWaypoint" / "Arrow.tga"
target.write_bytes(header + pixels)
