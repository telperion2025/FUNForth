#!/usr/bin/env python3
"""tools/hosttest.py - host-side test suite for FUNForth (no ARM toolchain needed).

Checks:
  1. forth-lint: every .fth file parses clean (control-flow balance, word
     resolution against seed+core+drivers+wins, balanced quotes/parens).
     forth-order: non-test files have no use-before-definition (a colon body
     resolves names at compile time, so forward refs abort the load on QEMU).
  2. makefile: test-* targets reference existing files; SD_FILES entries are
     valid 8.3 names with existing host paths; .PHONY covers all targets;
     every `load x.fth` in sd/boot.lst and test/*.fth is on the SD image.
  3. sd-image: build build/sd.img with tools/mksd.py and verify every file's
     FAT32 content sha256 against the host file.
  4. fbcheck: synthetic PPM passes a golden and fails on one wrong pixel.
  5. mkfont: regenerating drivers/font8x16.fth is byte-identical.
  6. asm-golden: recompute the `see` lines of test/expected-asm.txt from an
     independent ARMv6 encoder+disassembler model and compare.

Usage: python3 tools/hosttest.py   (exit 0 = all PASS)
"""
import hashlib
import os
import re
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

failures = []

def check(name, ok, detail=""):
    print("%-24s %s%s" % (name, "PASS" if ok else "FAIL", (" - " + detail) if detail and not ok else ""))
    if not ok:
        failures.append(name)

# ---------------------------------------------------------------- forth lint
def strip_line(line):
    line = re.sub(r'\\[^\n]*$', ' ', line)          # \ comment
    line = re.sub(r'\(\s[^)]*\)', ' ', line)          # ( ... ) comment (single line)
    line = re.sub(r'\.\"[^"]*"', ' .STR ', line)       # ." string"
    return line

FORTH_FILES = []
for d in ("forth", "drivers"):
    for f in sorted(os.listdir(d)):
        if f.endswith(".fth"):
            FORTH_FILES.append(os.path.join(d, f))
for f in ("wm.fth", "term.fth", "gui.fth", "hello.fth"):
    FORTH_FILES.append(f)
FORTH_FILES += sorted("test/" + f for f in os.listdir("test") if f.endswith(".fth"))

seed = open("src/seed.S").read()
SEED_WORDS = set(re.findall(r'defword\s+\w+,\s*"([^"]+)"', seed))

def known_words():
    known = set(SEED_WORDS) | {"[']", "'", "[", "]", ";", ".STR"}
    for f in FORTH_FILES:
        s = "\n".join(strip_line(l) for l in open(f))
        known |= set(re.findall(r'(?m)^:\s+(\S+)', s))
        known |= set(re.findall(r':\s+([^\s;()]+)', s))
        known |= set(re.findall(r'create\s+([^\s,]+)', s))
        known |= set(re.findall(r'([a-z0-9._-]+)\s+-?\d+\s*,', s))   # create cells (incl. mid-line)
        known |= set(re.findall(r'\d+\s+task:\s+(\S+)', s))
        known |= set(re.findall(r'(?m)^variable\s+(\S+)', s))
    return known

KNOWN = known_words()

def lint_forth(path):
    errs = []
    stack = []
    in_def = False
    for ln, raw in enumerate(open(path), 1):
        line = strip_line(raw.rstrip("\n"))
        # quote/paren sanity on the raw line
        if raw.count('"') % 2 == 1 and '."' not in raw:
            errs.append("line %d: odd quote count" % ln)
        toks = line.split()
        skip_name = False
        for ti, tok in enumerate(toks):
            if skip_name:                             # the word being defined
                skip_name = False
                continue
            prev = toks[ti - 1] if ti else ""
            if any(ord(c) < 32 or ord(c) == 127 for c in tok):
                continue                              # raw control bytes (scripted keys)
            if prev in ("word", "load", "needs") or "." in tok:
                continue                              # runtime-parsed name / filename arg
            if prev in ("code", "label", "marker"):
                KNOWN.add(tok)                        # code/label/marker define a word at runtime
                continue
            if tok in (":",):
                if in_def:
                    errs.append("line %d: ':' inside definition" % ln)
                in_def = True
                stack.append("def")
                skip_name = True
            elif tok == ";":
                if not stack or stack[-1] != "def":
                    errs.append("line %d: ';' with stack %s" % (ln, stack))
                else:
                    stack.pop()
                in_def = False
            elif tok in ("if", "?do", "do", "begin", "case"):
                stack.append(tok)
            elif tok == "else":
                if not stack or stack[-1] != "if":
                    errs.append("line %d: 'else' with stack %s" % (ln, stack))
            elif tok == "then":
                if not stack or stack[-1] != "if":
                    errs.append("line %d: 'then' with stack %s" % (ln, stack))
                else:
                    stack.pop()
            elif tok == "while":
                if not stack or stack[-1] != "begin":
                    errs.append("line %d: 'while' outside begin (stack %s)" % (ln, stack))
            elif tok in ("until", "again", "repeat"):
                if not stack or stack[-1] != "begin":
                    errs.append("line %d: '%s' with stack %s" % (ln, tok, stack))
                else:
                    stack.pop()
            elif tok in ("loop", "+loop"):
                if not stack or stack[-1] not in ("do", "?do"):
                    errs.append("line %d: '%s' with stack %s" % (ln, tok, stack))
                else:
                    stack.pop()
            elif tok == "of":
                if not stack or stack[-1] != "case":
                    errs.append("line %d: 'of' with stack %s" % (ln, stack))
                else:
                    stack.append("of")
            elif tok == "endof":
                if not stack or stack[-1] != "of":
                    errs.append("line %d: 'endof' with stack %s" % (ln, stack))
                else:
                    stack.pop()
            elif tok == "endcase":
                if not stack or stack[-1] != "case":
                    errs.append("line %d: 'endcase' with stack %s" % (ln, stack))
                else:
                    stack.pop()
            elif re.fullmatch(r'-?\d+', tok) or tok in KNOWN:
                pass
            elif "-nope" in tok or tok in ("foobar",):
                pass                                  # deliberate -? error-path test words
            else:
                errs.append("line %d: unknown word %r" % (ln, tok))
    if stack:
        errs.append("unclosed at EOF: %s" % stack)
    return errs

lint_ok = True
for f in FORTH_FILES:
    errs = lint_forth(f)
    if errs:
        lint_ok = False
        print("  %s:" % f)
        for e in errs[:8]:
            print("    " + e)
check("forth-lint", lint_ok, "%d files" % len(FORTH_FILES))

# --------------------------------------- definition-order lint (non-test files)
# A colon body is resolved at COMPILE time, so every word it names (including
# behind [']) must already be defined when the definition is reached; loading
# a file with a forward reference aborts with -? <name> on real hardware.
ORDER_FILES = (["forth/core.fth", "drivers/sd.fth", "drivers/timer.fth",
                "drivers/gpio.fth", "drivers/mailbox.fth", "drivers/fb.fth",
                "drivers/font8x16.fth", "drivers/vdi.fth",
                "drivers/console-fb.fth", "forth/tasks.fth", "forth/asm.fth",
                "wm.fth", "term.fth", "gui.fth", "hello.fth"])

def file_defs(path):
    defs = []
    for raw in open(path):
        toks = strip_line(raw.rstrip("\n")).split()
        for i, tok in enumerate(toks[:-1]):
            if tok in (":", "create"):
                defs.append(toks[i + 1].strip("();"))
    return defs

def lint_order(path):
    errs = []
    defs = file_defs(path)
    pending = set(defs)
    defined = set(KNOWN) - pending
    for ln, raw in enumerate(open(path), 1):
        toks = strip_line(raw.rstrip("\n")).split()
        for i, tok in enumerate(toks):
            tok = tok.strip("();")
            if not tok or re.fullmatch(r'-?\d+', tok):
                continue
            prev = toks[i - 1] if i else ""
            if prev in ("word", "load", "needs", "code", "label", "marker") or "." in tok:
                continue
            if tok in (":", "create") and i + 1 < len(toks):
                name = toks[i + 1].strip("();")
                defined.add(name)
                pending.discard(name)
                continue
            if tok in pending:
                errs.append("line %d: '%s' used before its definition" % (ln, tok))
    return errs

order_ok = True
for f in ORDER_FILES:
    errs = lint_order(f)
    if errs:
        order_ok = False
        print("  %s:" % f)
        for e in errs[:8]:
            print("    " + e)
check("forth-order", order_ok, "%d files" % len(ORDER_FILES))

# ---------------------------------------------------------------- makefile
mk = open("Makefile").read()
sd_files = dict(re.findall(r'([A-Z0-9._-]{1,8}\.[A-Z0-9]{1,3})=(\S+)', mk))
targets = re.findall(r'(?m)^([a-z-]+):', mk)
phony = re.search(r'\.PHONY:\s*(.+)', mk).group(1).split()
mk_ok = True
for name, path in sd_files.items():
    if not re.fullmatch(r'[A-Z0-9._-]{1,8}\.[A-Z0-9]{1,3}', name) or not os.path.exists(path):
        mk_ok = False
        print("  bad SD_FILES entry: %s=%s" % (name, path))
for t in targets:
    body = re.search(r'(?ms)^%s:.*?\n\n' % re.escape(t), mk + "\n")
    if body:
        for ref in re.findall(r'test/\S+?\.(?:fth|txt)', body.group(0)):
            if not os.path.exists(ref):
                mk_ok = False
                print("  target %s references missing %s" % (t, ref))
missing_phony = [t for t in targets if t not in phony and t not in ("all", "build")]
if missing_phony:
    mk_ok = False
    print("  targets missing from .PHONY:", missing_phony)
# every load name in boot.lst and tests must be on the SD image
loads = set()
for src in ["sd/boot.lst"] + sorted("test/" + f for f in os.listdir("test") if f.endswith(".fth")):
    loads |= set(re.findall(r'(?m)^load\s+(\S+)', open(src).read(), re.I))
sd_names = {n.upper() for n in sd_files}
for l in sorted(loads):
    up = l.upper()
    if up not in sd_names and up != "NOSUCH.TXT":   # nosuch.txt tests the error path
        mk_ok = False
        print("  load %s not on SD image" % l)
check("makefile", mk_ok, "%d SD_FILES, %d targets" % (len(sd_files), len(targets)))

# ---------------------------------------------------------------- sd image
def build_sd():
    args = ["python3", "tools/mksd.py", "build/sd.img", "32"] + \
           ["%s=%s" % kv for kv in sorted(sd_files.items())]
    os.makedirs("build", exist_ok=True)
    r = subprocess.run(args, capture_output=True, text=True)
    return r.returncode == 0

def verify_sd():
    img = open("build/sd.img", "rb").read()
    bps = struct.unpack_from("<H", img, 11)[0]
    spc = img[13]
    reserved = struct.unpack_from("<H", img, 14)[0]
    nfats = img[16]
    fatsz = struct.unpack_from("<I", img, 36)[0]
    root_clus = struct.unpack_from("<I", img, 44)[0]
    data_start = (reserved + nfats * fatsz) * bps
    cb = spc * bps
    fat_off = reserved * bps
    def chain(c):
        out = b""
        while 2 <= c < 0x0FFFFFF8:
            out += img[data_start + (c - 2) * cb: data_start + (c - 1) * cb]
            c = struct.unpack_from("<I", img, fat_off + c * 4)[0] & 0x0FFFFFFF
        return out
    data = chain(root_clus)
    ents = {}
    for i in range(0, len(data), 32):
        e = data[i:i + 32]
        if e[0] == 0:
            break
        if e[0] == 0xE5 or e[11] == 0x0F:
            continue
        name = e[0:8].decode().rstrip() + "." + e[8:11].decode().rstrip()
        size = struct.unpack_from("<I", e, 28)[0]
        clus = struct.unpack_from("<H", e, 26)[0] | (struct.unpack_from("<H", e, 20)[0] << 16)
        ents[name] = chain(clus)[:size]
    ok = set(ents) == set(sd_files)
    for name, path in sd_files.items():
        if name in ents:
            ok = ok and hashlib.sha256(ents[name]).digest() == hashlib.sha256(open(path, "rb").read()).digest()
    return ok

check("sd-image", build_sd() and verify_sd(), "15 files sha256-verified")

# ---------------------------------------------------------------- fbcheck
def fbcheck_test():
    golden = []
    for line in open("test/expected-fb.txt"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        x, y, rgb = line.split()
        golden.append((int(x), int(y), bytes.fromhex(rgb)))
    w = h = 640, 400
    w, h = 640, 400
    pix = {(x, y): tuple(c) for x, y, c in golden}
    def ppm(path, p):
        d = bytearray(b"P6\n%d %d\n255\n" % (w, h))
        for yy in range(h):
            for xx in range(w):
                d += bytes(p.get((xx, yy), (0, 0, 0)))
        open(path, "wb").write(bytes(d))
    ppm("/tmp/ht-good.ppm", pix)
    r1 = subprocess.run([sys.executable, "tools/fbcheck.py", "/tmp/ht-good.ppm", "test/expected-fb.txt"],
                        capture_output=True, text=True)
    bad = dict(pix)
    bad[(10, 10)] = (1, 2, 3)
    ppm("/tmp/ht-bad.ppm", bad)
    r2 = subprocess.run([sys.executable, "tools/fbcheck.py", "/tmp/ht-bad.ppm", "test/expected-fb.txt"],
                        capture_output=True, text=True)
    return r1.returncode == 0 and r2.returncode == 1 and "MISMATCH (10,10)" in r2.stdout

check("fbcheck", fbcheck_test())

# ---------------------------------------------------------------- mkfont
def mkfont_test():
    r = subprocess.run([sys.executable, "tools/mkfont.py"], capture_output=True)
    return r.returncode == 0 and r.stdout == open("drivers/font8x16.fth", "rb").read()

check("mkfont", mkfont_test())

# ---------------------------------------------------------------- asm golden
M32 = 0xFFFFFFFF
AL = 0xE0000000

def enc():
    ccv = [AL]; sfv = [0]
    out = []
    def emitc(w):
        out.append((w | ccv[0] | (0x100000 if sfv[0] else 0)) & M32)
        ccv[0] = AL; sfv[0] = 0
    def ror32(n, s):
        return n & M32 if s == 0 else ((n >> s) | (n << (32 - s))) & M32
    def imm32(n):
        for i in range(16):
            r = ror32(n, i * 2)
            if r <= 255:
                return (i << 8) | r
        raise ValueError
    def op2(p):
        return (0x02000000 | imm32(p & 0xEFFFFFFF)) if p & 0x10000000 else p
    def mov(d, p): emitc(0x01A00000 | d << 12 | op2(p))
    def add(d, a, p): emitc(0x00800000 | d << 12 | a << 16 | op2(p))
    def cmp_(a, p): emitc(0x01500000 | a << 16 | op2(p))
    def tos_pop(r): emitc(0x05940000 | r << 12); emitc(0x02844004)
    def tos_push(r): emitc(0x02444004); emitc(0x05840000 | r << 12)
    def bkpt(i): emitc(0x01200070 | ((i >> 4 & 0xFFF) << 8) | (i & 0xF))
    def dsb(): emitc(0x0E070F9A)
    def dmb(): emitc(0x0E070F9B)
    def isb(): emitc(0x0E070F95)
    return out, ccv, mov, add, cmp_, tos_pop, tos_push, bkpt, dsb, dmb, isb

def disasm(cl, nextv=0x8100):
    """replica of asm.fth dis1 output for the words under test"""
    parts = []
    i = 0
    conds = ["eq","ne","hs","lo","mi","pl","vs","vc","hi","ls","ge","lt","gt","le"]
    while i < len(cl):
        ci = cl[i]
        c2 = cl[i + 1] if i + 1 < len(cl) else 0
        cond = (ci >> 28) & 15
        if cond < 14:
            parts.append(conds[cond])
        if (ci & 0x0F000000) == 0x0A000000:
            f = ci & 0xFFFFFF
            if f > 0x800000:
                f -= 0x1000000
            tgt = (f << 2) + 8 + i * 4   # relative to cell address i*4
            if tgt == nextv:
                parts.append("b next")
            else:
                parts.append("b %08X" % tgt)
            i += 1
            continue
        if (ci & 0x0FFF0FFF) == 0x05940000 and (c2 & 0x0FFFFFFF) == 0x02844004:
            parts.append("tos-pop r%d" % ((ci >> 12) & 15)); i += 2; continue
        if (ci & 0x0FFFFFFF) == 0x02444004 and (c2 & 0x0FFF0FFF) == 0x05840000:
            parts.append("tos-push r%d" % ((c2 >> 12) & 15)); i += 2; continue
        if (ci & 0x0C000000) == 0x04000000:
            m = "ldr" if ci & 0x100000 else "str"
            off = (ci & 15) if (ci >> 25) & 1 else (ci & 4095)
            parts.append("%s r%d [r%d %d]" % (m, (ci >> 12) & 15, (ci >> 16) & 15, off)); i += 1; continue
        if (ci & 0x0FF000F0) == 0x01200070:
            parts.append("bkpt %d" % (((ci >> 8 & 0xFFF) << 4) | (ci & 0xF))); i += 1; continue
        if (ci & 0x0FFFFFFF) == 0x0E070F95: parts.append("isb"); i += 1; continue
        if (ci & 0x0FFFFFFF) == 0x0E070F9A: parts.append("dsb"); i += 1; continue
        if (ci & 0x0FFFFFFF) == 0x0E070F9B: parts.append("dmb"); i += 1; continue
        if (ci & 0x0FF00000) == 0x01000000:
            m = "cpsid" if ci & 0x40000 else "cpsie"
            parts.append("%s %08X" % (m, ci & 0x1C0)); i += 1; continue
        if (ci & 0x0E000000) == 0x02000000 and ((ci >> 8) & 15) == 0:
            op = (ci >> 21) & 15; rd = (ci >> 12) & 15; rn = (ci >> 16) & 15; imm = ci & 0xFF
            names = {13: "mov", 15: "mvn", 4: "add", 2: "sub", 10: "cmp", 0: "and", 12: "orr", 1: "eor", 14: "bic"}
            if op == 10:
                parts.append("cmp r%d # %d" % (rn, imm))
            else:
                parts.append("%s r%d%s # %d" % (names[op], rd, "" if op in (13, 15) else " r%d" % rn, imm))
            i += 1; continue
        if (ci & 0x0E000010) == 0:
            op = (ci >> 21) & 15; rd = (ci >> 12) & 15; rn = (ci >> 16) & 15; rm = ci & 15
            names = {13: "mov", 15: "mvn", 4: "add", 2: "sub", 10: "cmp", 0: "and", 12: "orr", 1: "eor", 14: "bic"}
            if op == 10:
                parts.append("cmp r%d r%d" % (rn, rm))
            elif op == 13 and ((ci >> 4) & 0xFF) == 0:
                parts.append("mov r%d r%d" % (rd, rm))
            else:
                parts.append("%s r%d r%d r%d" % (names[op], rd, rn, rm))
            i += 1; continue
        parts.append("? %x" % ci)
        i += 1
    return " ".join(parts) + " ;"

def asm_golden_test():
    out, ccv, mov, add, cmp_, tos_pop, tos_push, bkpt, dsb, dmb, isb = enc()
    words = {}
    def word(name, fn):
        del out[:]
        fn()
        words[name] = list(out)
    word("double", lambda: (tos_pop(0), add(0, 0, 0), tos_push(0)))
    # dup body from seed.S: ldr r0,[r4] / sub r4,r4,#4 / str r0,[r4] / b next
    words["dup"] = [0xE5940000, 0xE2444004, 0xE5840000]
    def misc():
        bkpt(0); dsb(); dmb(); isb()
        out.append(0xF10C0080); out.append(0xF1080080)
    word("misc", misc)
    def eqmov():
        tos_pop(1); tos_pop(2); mov(0, 0x10000000 | 0); cmp_(1, 2)
        ccv[0] = 0
        mov(0, 0x10000000 | 1); tos_push(0)
    word("eqmov", eqmov)
    # append b next (offset patched so target == nextv placeholder)
    for name in words:
        words[name].append(0xEA000000 | (((0x8100 - (len(words[name]) * 4 + 8)) >> 2) & 0xFFFFFF))
    golden = open("test/expected-asm.txt").read()
    ok = True
    for name, cl in words.items():
        line = "%s: <code> %s" % (name, disasm(cl))
        if line not in golden:
            ok = False
            print("  missing golden line: %r" % line)
            print("  computed:            %r" % line)
    return ok

check("asm-golden", asm_golden_test())

# ---------------------------------------------------------------- summary
print()
if failures:
    print("HOSTTEST: FAIL (%s)" % ", ".join(failures))
    sys.exit(1)
print("HOSTTEST: all PASS")
