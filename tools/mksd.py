#!/usr/bin/env python3
# tools/mksd.py - build a minimal FAT32 SD image (8.3 names, no LFN) for QEMU -sd.
# Usage: mksd.py <out.img> <size_mb> <name=path> [<name=path> ...]
#   name must be 8.3 (e.g. BOOT.LST); path is a host file copied in.
import struct, sys

def fat32_image(size_mb, files):
    spc = 1                      # sectors per cluster (512 B clusters)
    bps = 512
    total = size_mb * 1024 * 1024 // bps
    reserved = 32
    nfats = 2
    # fat size: enough for all clusters
    nclus = total // spc
    fatsz = (nclus * 4 + bps - 1) // bps + 1
    data_start = reserved + nfats * fatsz
    img = bytearray(total * bps)
    # boot sector
    bs = bytearray(bps)
    bs[0:3] = b"\xeb\x58\x90"
    bs[3:11] = b"MSWIN4.1"
    struct.pack_into("<H", bs, 11, bps)
    bs[13] = spc
    struct.pack_into("<H", bs, 14, reserved)
    bs[16] = nfats
    struct.pack_into("<H", bs, 17, 0)          # root entries (0 = FAT32)
    struct.pack_into("<H", bs, 19, 0)          # totsec16
    bs[21] = 0xF8
    struct.pack_into("<H", bs, 22, 0)          # fatsz16
    struct.pack_into("<H", bs, 24, 32)         # spt
    struct.pack_into("<H", bs, 26, 64)         # heads
    struct.pack_into("<I", bs, 28, 0)          # hidden
    struct.pack_into("<I", bs, 32, total)      # totsec32
    struct.pack_into("<I", bs, 36, fatsz)      # fatsz32
    struct.pack_into("<H", bs, 40, 0)          # ext flags
    struct.pack_into("<H", bs, 42, 0)          # fs version
    struct.pack_into("<I", bs, 44, 2)          # root cluster
    struct.pack_into("<H", bs, 48, 1)          # fsinfo sector
    struct.pack_into("<H", bs, 50, 6)          # backup boot sector
    bs[64] = 0x80
    bs[66] = 0x29
    struct.pack_into("<I", bs, 67, 0x12345678)
    bs[71:82] = b"FUNFORTH   "
    bs[82:90] = b"FAT32   "
    bs[510:512] = b"\x55\xaa"
    img[0:bps] = bs
    # FATs
    fat = bytearray(fatsz * bps)
    struct.pack_into("<I", fat, 0, 0x0FFFFFF8)
    struct.pack_into("<I", fat, 4, 0xFFFFFFFF)
    # root dir: clusters 2..2+nroot-1, chained (FAT32 root is a cluster chain)
    nroot = max(1, (len(files) * 32 + bps - 1) // bps)
    for c in range(nroot):
        val = 2 + c + 1 if c < nroot - 1 else 0x0FFFFFFF
        struct.pack_into("<I", fat, (2 + c) * 4, val)
    for i in range(nfats):
        off = (reserved + i * fatsz) * bps
        img[off:off + len(fat)] = fat
    # root dir at clusters 2..
    root = bytearray(nroot * bps)
    next_clus = 2 + nroot
    for name, hostpath in files:
        with open(hostpath, "rb") as f:
            data = f.read()
        nclus_f = (len(data) + bps - 1) // bps
        if nclus_f == 0:
            nclus_f = 1
        first = next_clus
        for c in range(nclus_f):
            # FAT chain
            val = next_clus + c + 1 if c < nclus_f - 1 else 0x0FFFFFFF
            struct.pack_into("<I", fat, (next_clus + c) * 4, val)
            # data
            lba = data_start + (next_clus + c - 2) * spc
            chunk = data[c * bps:(c + 1) * bps]
            img[lba * bps:lba * bps + len(chunk)] = chunk
        next_clus += nclus_f
        # dir entry (8.3: base padded to 8, then 3-char ext)
        base, ext = name.split(".")
        e = bytearray(32)
        e[0:11] = (base.ljust(8)[:8] + ext.ljust(3)[:3]).encode("ascii")
        e[11] = 0x20                                    # archive
        struct.pack_into("<H", e, 20, (first >> 16) & 0xFFFF)
        struct.pack_into("<H", e, 26, first & 0xFFFF)
        struct.pack_into("<I", e, 28, len(data))
        off = files.index((name, hostpath)) * 32
        root[off:off + 32] = e
    for c in range(nroot):
        rlba = data_start + (2 + c - 2) * spc
        img[rlba * bps:rlba * bps + bps] = root[c * bps:(c + 1) * bps]
    # rewrite FATs with chains
    for i in range(nfats):
        off = (reserved + i * fatsz) * bps
        img[off:off + len(fat)] = fat
    return img

if __name__ == "__main__":
    out, size_mb = sys.argv[1], int(sys.argv[2])
    files = []
    for a in sys.argv[3:]:
        name, path = a.split("=", 1)
        assert len(name.split(".")[0]) <= 8 and len(name.split(".")[1]) <= 3, name
        files.append((name.upper(), path))
    img = fat32_image(size_mb, files)
    with open(out, "wb") as f:
        f.write(img)
    print("wrote %s (%d bytes, %d files)" % (out, len(img), len(files)))
