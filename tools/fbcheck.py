#!/usr/bin/env python3
# tools/fbcheck.py - magic-pixel check of a QEMU screendump PPM against a golden.
# Usage: fbcheck.py <dump.ppm> <golden.txt>
#   golden lines: "x y RRGGBB" (hex RGB of the expected pixel)
import sys

def read_ppm(path):
    with open(path, "rb") as f:
        data = f.read()
    if not data.startswith(b"P6"):
        sys.exit("error: not a P6 PPM: %s" % path)
    pos = 2
    fields = []
    while len(fields) < 3:
        while pos < len(data) and data[pos:pos+1].isspace():
            pos += 1
        if data[pos:pos+1] == b"#":
            while data[pos:pos+1] not in (b"\n", b""):
                pos += 1
            continue
        start = pos
        while pos < len(data) and not data[pos:pos+1].isspace():
            pos += 1
        fields.append(int(data[start:pos]))
    pos += 1  # single whitespace after maxval
    w, h, maxval = fields
    return w, h, data[pos:pos + w * h * 3]

def main():
    ppm, golden = sys.argv[1], sys.argv[2]
    w, h, px = read_ppm(ppm)
    print("screendump: %dx%d" % (w, h))
    bad = 0
    n = 0
    with open(golden) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            x, y, rgb = line.split()
            x, y = int(x), int(y)
            exp = bytes.fromhex(rgb)
            off = (y * w + x) * 3
            got = px[off:off + 3]
            n += 1
            if got != exp:
                bad += 1
                print("MISMATCH (%d,%d): expected #%s got #%s"
                      % (x, y, exp.hex(), got.hex()))
    if bad:
        print("FAIL: %d/%d magic pixels wrong" % (bad, n))
        return 1
    print("PASS: %d magic pixels match %s" % (n, golden))
    return 0

if __name__ == "__main__":
    sys.exit(main())
