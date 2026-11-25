#!/usr/bin/env python3
"""tools/simforth.py - host simulator for the FUNForth seed (no ARM toolchain).

Implements the seed dictionary (src/seed.S) semantics in Python: DTC threading
(xt = header, cfa at +4, pfa = align4(+10+len)), the interpret/compile loop,
core.fth + drivers, `load` from host files (Makefile SD_FILES mapping), and a
small ARMv6 interpreter so `code ... end-code` words from forth/asm.fth run for
real. Used to run test/*.fth scripts and diff against test/expected-*.txt.

Usage: python3 tools/simforth.py test/asm.fth test/expected-asm.txt
       python3 tools/simforth.py --dump-words test/all.fth   (just run, no diff)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

M32 = 0xFFFFFFFF
MEM_BASE = 0x10000
MEM_SIZE = 16 * 1024 * 1024
DOCOL = 0x9000          # sentinel cfa for colon words
DOCON = 0x9004          # sentinel cfa for create words
NEXT_ADDR = 0x14000  # sentinel: ARM `b next` target ends a code word (inside mem, in branch range)


def u32(x):
    return x & M32


class Abort(Exception):
    pass


class Machine:
    def __init__(self):
        self.mem = bytearray(MEM_SIZE)
        self.r = [0] * 16
        self.r[4] = 0  # sp, set below
        self.here = MEM_BASE + 0x8000
        self.latest = 0
        self.state = 0
        self.ps0 = MEM_BASE + 0x100000
        self.r[4] = self.ps0
        self.r[13] = self.ps0 + 0x10000   # return stack grows down from here
        self.base = 10
        self.out = bytearray()
        self.steps = 0
        self.words = {}          # name -> xt
        self.by_cfa = {}         # cfa -> ('native', fn) | ('arm',)
        self.colon = {}          # xt -> True (body lives in mem at pfa)
        self.code_alloc = 0x8000
        self.inptr_stack = []
        self.in_ptr = 0
        self.wordbuf = self.alloc_mem(64)
        self.script = []
        self.sd_map = self.sd_files()
        self.install_seed()

    # ------------------------------------------------------------ memory
    def rd32(self, a):
        o = a - MEM_BASE
        return int.from_bytes(self.mem[o:o + 4], "little")

    def wr32(self, a, v):
        o = a - MEM_BASE
        self.mem[o:o + 4] = u32(v).to_bytes(4, "little")

    def rd8(self, a):
        return self.mem[a - MEM_BASE]

    def wr8(self, a, v):
        self.mem[a - MEM_BASE] = v & 0xFF

    def alloc_mem(self, n):
        a = self.here
        self.here = (self.here + n + 3) & ~3
        return a

    # ------------------------------------------------------------ stack
    def push(self, v):
        self.r[4] -= 4
        self.wr32(self.r[4], v)

    def pop(self):
        v = self.rd32(self.r[4])
        self.r[4] += 4
        return v

    def rpush(self, v):
        self.r[13] -= 4
        self.wr32(self.r[13], v)

    def rpop(self):
        v = self.rd32(self.r[13])
        self.r[13] += 4
        return v

    # ------------------------------------------------------------ output
    def emit(self, c):
        self.out.append(c & 0xFF)

    def emit_str(self, s):
        self.out += s.encode("latin1") if isinstance(s, str) else s

    # ------------------------------------------------------------ dictionary
    def align4(self, a):
        return (a + 3) & ~3

    def pfa(self, xt):
        return self.align4(xt + 10 + self.rd8(xt + 9))

    def header_create(self, name, cfa):
        h = self.align4(self.here)
        self.wr32(h, self.latest)
        self.wr32(h + 4, cfa)
        self.wr8(h + 8, 0)
        self.wr8(h + 9, len(name))
        for i, ch in enumerate(name):
            self.wr8(h + 10 + i, ch)
        self.latest = h
        self.here = self.align4(h + 10 + len(name))
        return h

    def def_native(self, name, fn, flags=0):
        cfa = self.code_alloc
        self.code_alloc += 4
        xt = self.header_create(name.encode(), cfa)
        if flags:
            self.wr8(xt + 8, flags)
        self.by_cfa[cfa] = ("native", fn)
        self.words[name] = xt
        return xt

    def find(self, tok):
        h = self.latest
        while h:
            ln = self.rd8(h + 9)
            name = bytes(self.rd8(h + 10 + i) for i in range(ln))
            if name == tok:
                return h
            h = self.rd32(h)
        return 0

    # ------------------------------------------------------------ name parsing (from mem at in_ptr)
    def parse_name(self):
        p = self.in_ptr
        while True:
            c = self.rd8(p)
            if c == 0 or c in (0x0A, 0x0D):
                break
            if c in (0x20, 0x09):
                p += 1
                continue
            break
        start = p
        while True:
            c = self.rd8(p)
            if c == 0 or c in (0x20, 0x09, 0x0A, 0x0D):
                break
            p += 1
        tok = bytes(self.rd8(start + i) for i in range(p - start))
        self.in_ptr = p
        for i, ch in enumerate(tok):
            self.wr8(self.wordbuf + i, ch)
        self.wr8(self.wordbuf + len(tok), 0)
        return tok

    def number_q(self, tok):
        s = tok.decode("latin1")
        neg = s.startswith("-")
        if neg:
            s = s[1:]
        if not s or not s.isdigit():
            return None
        v = int(s)
        return u32(-v) if neg else u32(v)

    # ------------------------------------------------------------ compiler
    def compile(self, v):
        self.here = self.align4(self.here)
        self.wr32(self.here, v)
        self.here += 4

    def execute_xt(self, xt):
        self.steps += 1
        if self.steps > 20_000_000:
            raise RuntimeError("step limit; in_ptr=%#x out tail=%r" % (self.in_ptr, bytes(self.out[-200:])))
        cfa = self.rd32(xt + 4)
        if cfa == DOCOL:
            self.run_colon(xt)
            return
        if cfa == DOCON:
            self.push(self.pfa(xt))
            return
        k = self.by_cfa.get(cfa)
        if k is None:
            if MEM_BASE + 0x8000 <= cfa < MEM_BASE + MEM_SIZE:
                self.run_arm(cfa)   # code word: cfa = raw ARM cells in the heap
                return
            raise Abort()
        if k[0] == "native":
            k[1](self)
        else:
            self.run_arm(cfa)

    def run_colon(self, xt):
        ip = self.pfa(xt)
        while True:
            w = self.rd32(ip)
            if w == self.lit_xt:
                self.push(self.rd32(ip + 4)); ip += 8; continue
            if w == self.branch_xt:
                ip = self.rd32(ip + 4); continue
            if w == self.zbranch_xt:
                f = self.pop()
                ip = self.rd32(ip + 4) if f == 0 else ip + 8
                continue
            if w == self.exit_xt:
                return
            if w == self.do_xt:
                idx = self.pop(); lim = self.pop()
                self.rpush(lim); self.rpush(idx)
                ip += 8  # skip L placeholder
                continue
            if w == self.qdo_xt:
                idx = self.pop(); lim = self.pop()
                if idx == lim:
                    ip = self.rd32(ip + 4)
                else:
                    self.rpush(lim); self.rpush(idx)
                    ip += 8
                continue
            if w == self.loop_xt:
                idx = u32(self.rd32(self.r[13]) + 1)
                self.wr32(self.r[13], idx)
                lim = self.rd32(self.r[13] + 4)
                if idx == lim:
                    self.r[13] += 8
                    ip += 8
                else:
                    ip += 4  # fall into (branch)
                continue
            if w == self.plusloop_xt:
                step = self.pop()
                idx = u32(self.rd32(self.r[13]) + step)
                self.wr32(self.r[13], idx)
                lim = self.rd32(self.r[13] + 4)
                done = (idx >= lim) if step >= 0 else (idx < lim)
                if done:
                    self.r[13] += 8
                    ip += 8
                else:
                    ip += 4
                continue
            if w == self.leave_xt:
                self.r[13] += 8
                ip = self.rd32(ip + 4)
                continue
            if w == self.unloop_xt:
                self.r[13] += 8; ip += 4; continue
            if w == self.i_xt:
                self.push(self.rd32(self.r[13])); ip += 4; continue
            if w == self.j_xt:
                self.push(self.rd32(self.r[13] + 8)); ip += 4; continue
            if w == self.dotq_rt_xt:
                a = self.rd32(ip + 4); ln = self.rd32(ip + 8)
                self.emit_str(bytes(self.rd8(a + i) for i in range(ln)))
                ip += 12 + ((ln + 3) & ~3)
                continue
            self.execute_xt(w)
            ip += 4

    # ------------------------------------------------------------ interpret
    def interpret_mem(self, addr):
        self.inptr_stack.append(self.in_ptr)
        self.in_ptr = addr
        while True:
            self.steps += 1
            if self.steps > 20_000_000:
                raise RuntimeError("interpret step limit at %#x out tail=%r" % (self.in_ptr, bytes(self.out[-200:])))
            p = self.in_ptr
            c = self.rd8(p)
            if c == 0:
                break
            if c in (0x20, 0x09, 0x0A, 0x0D):
                self.in_ptr = p + 1
                continue
            if c == 0x5C:  # \ comment to end of line
                while self.rd8(p) not in (0, 0x0A):
                    p += 1
                self.in_ptr = p if self.rd8(p) == 0 else p + 1
                continue
            start = p
            while True:
                c = self.rd8(p)
                if c == 0 or c in (0x20, 0x09, 0x0A, 0x0D):
                    break
                p += 1
            tok = bytes(self.rd8(start + i) for i in range(p - start))
            self.in_ptr = p
            if tok[:1] == b"\\":
                while self.rd8(p) not in (0, 0x0A):
                    p += 1
                self.in_ptr = p if self.rd8(p) == 0 else p + 1
                continue
            n = self.number_q(tok)
            if n is not None:
                if self.state == 0:
                    self.push(n)
                else:
                    self.compile(self.lit_xt)
                    self.compile(n)
                continue
            xt = self.find(tok)
            if not xt:
                self.state = 0
                self.emit_str("-? ")
                self.emit_str(tok)
                break
            flags = self.rd8(xt + 8)
            if self.state == 0 or (flags & 1):
                self.execute_xt(xt)
            else:
                self.compile(xt)
        self.in_ptr = self.inptr_stack.pop()

    def interpret_str(self, s):
        buf = self.alloc_mem(len(s) + 1)
        for i, ch in enumerate(s.encode("latin1")):
            self.wr8(buf + i, ch)
        self.wr8(buf + len(s), 0)
        self.interpret_mem(buf)

    # ------------------------------------------------------------ ARMv6 subset
    def getf(self):
        return self.N, self.Z, self.C, self.V

    def setf(self, N, Z, C, V):
        self.N, self.Z, self.C, self.V = N, Z, C, V

    def cond_ok(self, cond):
        N, Z, C, V = self.N, self.Z, self.C, self.V
        return [Z == 1, Z == 0, C == 1, C == 0, N == 1, N == 0, V == 1, V == 0,
                C == 1 and Z == 0, C == 0 or Z == 1, N == V, N != V, Z == 1 or N != V,
                Z == 0 and N == V, True, False][cond]

    def shifter(self, w):
        # returns (value, carry)
        if (w >> 25) & 1:  # immediate
            imm = w & 0xFF
            rot = ((w >> 8) & 15) * 2
            if rot == 0:
                return imm, self.C
            v = u32((imm >> rot) | (imm << (32 - rot)))
            return v, (imm >> (rot - 1)) & 1
        rm = self.r[w & 15]
        if (w >> 4) & 1:  # register shift
            rs = (w >> 8) & 15
            amt = self.r[rs] & 0xFF
            st = (w >> 5) & 3
        else:
            amt = (w >> 7) & 31
            st = (w >> 5) & 3
        if st == 0:  # LSL
            if amt == 0:
                return rm, self.C
            return u32(rm << amt), (rm >> (32 - amt)) & 1 if amt < 32 else 0
        if st == 1:  # LSR
            if amt == 0:
                amt = 32
            return (rm >> amt) & M32, (rm >> (amt - 1)) & 1
        if st == 2:  # ASR
            if amt == 0:
                amt = 32
            v = rm >> amt if rm < 0x80000000 else u32(rm >> amt | (M32 << (32 - amt)) & M32)
            v = u32(int(rm - (1 << 32) if rm >= 0x80000000 else rm) >> amt)
            return v, (rm >> (amt - 1)) & 1
        # ROR
        if amt == 0:
            return rm, rm & 1
        amt %= 32
        return u32((rm >> amt) | (rm << (32 - amt))), (rm >> (amt - 1)) & 1

    def run_arm(self, addr):
        r = self.r
        pc = addr
        self.N = self.Z = self.C = self.V = 0
        while True:
            self.steps += 1
            if self.steps > 20_000_000:
                raise RuntimeError("arm step limit at pc=%#x" % pc)
            w = self.rd32(pc)
            cond = (w >> 28) & 15
            if not self.cond_ok(cond):
                pc += 4
                continue
            top = (w >> 24) & 0xF
            if top in (0xA, 0xB):  # B / BL
                imm = w & 0xFFFFFF
                if imm > 0x800000:
                    imm -= 0x1000000
                tgt = u32(pc + 8 + (imm << 2))
                if (w >> 24) & 1:  # BL
                    r[14] = pc + 4
                if tgt == NEXT_ADDR:
                    return
                pc = tgt
                continue
            if (w & 0x0FFFFFF0) == 0x012FFF10:  # BX
                tgt = r[w & 15]
                if tgt == NEXT_ADDR:
                    return
                pc = tgt
                continue
            if (w & 0x0FC000F0) == 0x00000090 or (w & 0x0F8000F0) == 0x00800090:
                # multiply family: bits 23-21 select mul/mla/umull/smull
                op = (w >> 21) & 7
                rd = (w >> 12) & 15
                rn = (w >> 16) & 15
                rs = (w >> 8) & 15
                rm = w & 15
                s = (w >> 20) & 1
                if op == 0:  # mul
                    res = u32(r[rm] * r[rs])
                    r[rd] = res
                    if s:
                        self.setf(1 if res >= 0x80000000 else 0, 1 if res == 0 else 0, self.C, 0)
                elif op == 1:  # mla
                    res = u32(r[rm] * r[rs] + r[rn])
                    r[rd] = res
                    if s:
                        self.setf(1 if res >= 0x80000000 else 0, 1 if res == 0 else 0, self.C, 0)
                elif op == 4:  # umull
                    res = r[rm] * r[rs]
                    r[rd] = u32(res)
                    r[rn] = u32(res >> 32)
                elif op == 6:  # smull
                    a = r[rm] - (1 << 32) if r[rm] >= 0x80000000 else r[rm]
                    b = r[rs] - (1 << 32) if r[rs] >= 0x80000000 else r[rs]
                    res = a * b
                    r[rd] = u32(res)
                    r[rn] = u32(res >> 32)
                pc += 4
                continue
            if (w >> 26) & 3 == 1 and ((w >> 4) & 1) == 0 and ((w >> 7) & 1) == 1:
                # ldr/str word/byte: bits 27-26 = 01
                I = (w >> 25) & 1
                P = (w >> 24) & 1
                U = (w >> 23) & 1
                B = (w >> 22) & 1
                W = (w >> 21) & 1
                L = (w >> 20) & 1
                rn = (w >> 16) & 15
                rd = (w >> 12) & 15
                if I:
                    off = self.shifter(w)[0]
                else:
                    off = w & 0xFFF
                base = r[rn]
                addr2 = u32(base + off) if U else u32(base - off)
                a = addr2 if P else base
                if L:
                    v = self.rd32(a) if not B else self.rd8(a)
                    r[rd] = v
                else:
                    self.wr32(a, r[rd]) if not B else self.wr8(a, r[rd] & 0xFF)
                if W or not P:
                    r[rn] = addr2
                pc += 4
                continue
            if ((w >> 25) & 7) == 0 and ((w >> 7) & 1) == 1 and ((w >> 4) & 1) == 1:
                # halfword/signed: bits 27-25=000, bit7=1, bit4=1
                P = (w >> 24) & 1
                U = (w >> 23) & 1
                W = (w >> 21) & 1
                L = (w >> 20) & 1
                rn = (w >> 16) & 15
                rd = (w >> 12) & 15
                h = (w >> 5) & 3   # 1=half unsigned, 2=signed byte, 3=signed half
                if (w >> 22) & 1:  # register offset
                    off = r[w & 15]
                else:
                    off = ((w >> 8) & 15) << 4 | (w & 15)
                base = r[rn]
                addr2 = u32(base + off) if U else u32(base - off)
                a = addr2 if P else base
                if L:
                    if h == 1:
                        v = self.rd32(a) & 0xFFFF
                    elif h == 2:
                        v = self.rd8(a)
                        if v >= 0x80:
                            v -= 0x100
                        v = u32(v)
                    else:
                        v = self.rd32(a) & 0xFFFF
                        if v >= 0x8000:
                            v -= 0x10000
                        v = u32(v)
                    r[rd] = v
                else:
                    self.wr32(a, r[rd] & 0xFFFF)
                if W or not P:
                    r[rn] = addr2
                pc += 4
                continue
            if ((w >> 25) & 7) == 4:  # ldm/stm
                P = (w >> 24) & 1
                U = (w >> 23) & 1
                W = (w >> 21) & 1
                L = (w >> 20) & 1
                rn = (w >> 16) & 15
                rlist = w & 0xFFFF
                regs = [i for i in range(16) if (rlist >> i) & 1]
                base = r[rn]
                if U:
                    a = u32(base + (4 if P else 0))
                    step = 4
                else:
                    a = u32(base - 4 * len(regs) + (0 if P else 4))
                    step = 4
                for i, reg in enumerate(regs):
                    addr2 = u32(a + i * 4) if U else u32(base - 4 * (len(regs) - i))
                    if L:
                        r[reg] = self.rd32(addr2)
                    else:
                        self.wr32(addr2, r[reg])
                if W:
                    r[rn] = u32(base + 4 * len(regs)) if U else u32(base - 4 * len(regs))
                pc += 4
                continue
            if (w & 0x0FB00FF0) == 0x01000090:  # swp
                rn = (w >> 16) & 15
                rd = (w >> 12) & 15
                rm = w & 15
                tmp = self.rd32(r[rn]) if (w >> 22) & 1 == 0 else self.rd8(r[rn])
                if (w >> 22) & 1:
                    self.wr8(r[rn], r[rm] & 0xFF)
                else:
                    self.wr32(r[rn], r[rm])
                r[rd] = tmp
                pc += 4
                continue
            if ((w >> 26) & 3) == 0 and ((w >> 4) & 1) == 0:
                # data processing
                I = (w >> 25) & 1
                op = (w >> 21) & 15
                S = (w >> 20) & 1
                rn = (w >> 16) & 15
                rd = (w >> 12) & 15
                op2, carry = self.shifter(w)
                a = r[rn]
                if op in (8, 9, 10, 11):  # tst/teq/cmp/cmn: no write, always set flags
                    S = 1
                    rd_out = None
                else:
                    rd_out = rd
                if op == 0: res = a & op2
                elif op == 1: res = a ^ op2
                elif op == 2:
                    res = u32(a - op2)
                    carry = 1 if a >= op2 else 0
                    v = 1 if (a - op2) < 0 else 0  # signed overflow approx
                elif op == 3:
                    res = u32(op2 - a)
                    carry = 1 if op2 >= a else 0
                elif op == 4:
                    res = u32(a + op2)
                    carry = 1 if res < a else 0
                elif op == 5:
                    res = u32(a + op2 + self.C)
                elif op == 6:
                    res = u32(a - op2 - (1 - self.C))
                elif op == 7:
                    res = u32(op2 - a - (1 - self.C))
                elif op == 8: res = a & op2
                elif op == 9: res = a ^ op2
                elif op == 10:
                    res = u32(a - op2)
                    carry = 1 if a >= op2 else 0
                elif op == 11:
                    res = u32(a + op2)
                    carry = 1 if res < a else 0
                elif op == 12: res = a | op2
                elif op == 13: res = op2
                elif op == 14: res = a & u32(~op2)
                elif op == 15: res = u32(~op2)
                res = u32(res)
                if S:
                    self.N = 1 if res >= 0x80000000 else 0
                    self.Z = 1 if res == 0 else 0
                    self.C = carry
                    self.V = 0  # good enough for cond tests used here
                if rd_out is not None:
                    r[rd_out] = res
                pc += 4
                continue
            # mrs/msr/bkpt/dsb/dmb/isb/cps: no-op in the simulator
            pc += 4

    # ------------------------------------------------------------ seed words
    def install_seed(self):
        m = self
        def nat(name, fn, flags=0):
            return self.def_native(name, fn, flags)

        nat("dup", lambda m: m.push(m.rd32(m.r[4])))
        # give dup a real ARM body so next-init's scan works
        dup_xt = self.words["dup"]
        body = self.pfa(dup_xt)
        cells = [0xE5940000, 0xE2444004, 0xE5840000]
        for i, c in enumerate(cells):
            self.wr32(body + 4 * i, c)
        # b NEXT_ADDR
        off = u32((NEXT_ADDR - (body + 12 + 8)) >> 2)
        self.wr32(body + 12, 0xEA000000 | (off & 0xFFFFFF))
        self.wr32(dup_xt + 4, body)
        self.by_cfa[body] = ("arm",)
        self.here = body + 16   # reserve the ARM body so the next header doesn't overwrite it

        nat("drop", lambda m: m.r.__setitem__(4, m.r[4] + 4))
        def _swap(m):
            a = m.rd32(m.r[4]); b = m.rd32(m.r[4] + 4)
            m.wr32(m.r[4], b); m.wr32(m.r[4] + 4, a)
        nat("swap", _swap)
        nat("over", lambda m: m.push(m.rd32(m.r[4] + 4)))
        nat("depth", lambda m: m.push((m.ps0 - m.r[4]) // 4))
        def _add(m):
            b = m.pop(); a = m.pop(); m.push(u32(a + b))
        nat("+", _add)
        def _sub(m):
            b = m.pop(); a = m.pop(); m.push(u32(a - b))
        nat("-", _sub)
        def _mul(m):
            b = m.pop(); a = m.pop(); m.push(u32(a * b))
        nat("*", _mul)
        def _sdivmod(a, b):
            sa = a - (1 << 32) if a >= 0x80000000 else a
            sb = b - (1 << 32) if b >= 0x80000000 else b
            q = abs(sa) // abs(sb)
            if (sa < 0) != (sb < 0):
                q = -q
            r = sa - q * sb
            return u32(q), u32(r)
        def _udivmod(a, b):
            return u32(a // b), u32(a % b)
        def _slashmod(m):
            b = m.pop(); a = m.pop()
            q, r = _sdivmod(a, b)
            m.push(r); m.push(q)
        nat("/mod", _slashmod)
        def _umod(m):
            b = m.pop(); a = m.pop(); m.push(u32(a % b))
        def _slash(m):
            b = m.pop(); a = m.pop(); m.push(u32(a // b))
        def _mod(m):
            b = m.pop(); a = m.pop()
            q, r = _sdivmod(a, b); m.push(r)
        nat("u/mod", lambda m: (lambda b, a: (m.push(u32(a % b)), m.push(u32(a // b))))(m.pop(), m.pop()))
        nat("/", _slash)
        nat("mod", _mod)
        nat("and", lambda m: (lambda b, a: m.push(u32(a & b)))(m.pop(), m.pop()))
        nat("or", lambda m: (lambda b, a: m.push(u32(a | b)))(m.pop(), m.pop()))
        nat("xor", lambda m: (lambda b, a: m.push(u32(a ^ b)))(m.pop(), m.pop()))
        nat("invert", lambda m: m.push(u32(~m.pop())))
        nat("lshift", lambda m: (lambda b, a: m.push(u32(a << (b & 31))))(m.pop(), m.pop()))
        nat("rshift", lambda m: (lambda b, a: m.push(u32(a >> (b & 31))))(m.pop(), m.pop()))
        nat("0=", lambda m: m.push(-1 if m.pop() == 0 else 0))
        def _0lt(m):
            v = m.pop()
            m.push(-1 if v >= 0x80000000 else 0)
        nat("0<", _0lt)
        def _0gt(m):
            v = m.pop()
            m.push(-1 if 0 < v < 0x80000000 else 0)
        nat("0>", _0gt)
        nat("=", lambda m: (lambda b, a: m.push(-1 if a == b else 0))(m.pop(), m.pop()))
        nat("<", lambda m: (lambda b, a: m.push(-1 if (a - (1 << 32) if a >= 0x80000000 else a) < (b - (1 << 32) if b >= 0x80000000 else b) else 0))(m.pop(), m.pop()))
        nat(">", lambda m: (lambda b, a: m.push(-1 if (a - (1 << 32) if a >= 0x80000000 else a) > (b - (1 << 32) if b >= 0x80000000 else b) else 0))(m.pop(), m.pop()))
        nat("u<", lambda m: (lambda b, a: m.push(-1 if a < b else 0))(m.pop(), m.pop()))
        nat("<>", lambda m: (lambda b, a: m.push(-1 if a != b else 0))(m.pop(), m.pop()))
        nat("min", lambda m: (lambda b, a: m.push(a if (a - (1 << 32) if a >= 0x80000000 else a) < (b - (1 << 32) if b >= 0x80000000 else b) else b))(m.pop(), m.pop()))
        nat("max", lambda m: (lambda b, a: m.push(a if (a - (1 << 32) if a >= 0x80000000 else a) > (b - (1 << 32) if b >= 0x80000000 else b) else b))(m.pop(), m.pop()))
        nat("1+", lambda m: m.push(u32(m.pop() + 1)))
        nat("1-", lambda m: m.push(u32(m.pop() - 1)))
        nat("2*", lambda m: m.push(u32(m.pop() * 2)))
        nat("2/", lambda m: (lambda v: m.push(u32((v - (1 << 32) if v >= 0x80000000 else v) >> 1)))(m.pop()))
        nat("abs", lambda m: (lambda v: m.push(u32(abs(v - (1 << 32) if v >= 0x80000000 else v))))(m.pop()))
        nat("negate", lambda m: m.push(u32(-m.pop())))
        nat("@", lambda m: m.push(m.rd32(m.pop())))
        nat("!", lambda m: (lambda a, v: m.wr32(a, v))(m.pop(), m.pop()))
        nat("c@", lambda m: m.push(m.rd8(m.pop())))
        nat("c!", lambda m: (lambda a, v: m.wr8(a, v))(m.pop(), m.pop()))
        def _plusstore(m):
            a = m.pop(); v = m.pop(); m.wr32(a, u32(m.rd32(a) + v))
        nat("+!", _plusstore)
        nat("w@", lambda m: (lambda a: m.push(m.rd32(a) & 0xFFFF))(m.pop()))
        nat("w!", lambda m: (lambda a, v: (m.wr8(a, v & 0xFF), m.wr8(a + 1, (v >> 8) & 0xFF)))(m.pop(), m.pop()))
        def _allot(m):
            n = m.pop()
            m.here = m.align4(m.here + n) if n >= 0 else m.here + n
        nat("allot", _allot)
        nat(",", lambda m: (m.wr32(m.align4(m.here), m.pop()), setattr(m, "here", m.align4(m.here) + 4)))
        def _cc(m):
            v = m.pop()
            m.wr8(m.here, v)
            m.here += 1
        nat("c,", _cc)
        def _fill(m):
            c = m.pop(); n = m.pop(); a = m.pop()
            for i in range(n):
                m.wr8(a + i, c)
        nat("fill", _fill)
        def _move(m):
            n = m.pop(); dst = m.pop(); src = m.pop()
            data = bytes(m.rd8(src + i) for i in range(n))
            for i in range(n):
                m.wr8(dst + i, data[i])
        nat("move", _move)
        self.exit_xt = nat("exit", lambda m: None)
        self.lit_xt = nat("lit", lambda m: None)
        self.branch_xt = nat("(branch)", lambda m: None)
        self.zbranch_xt = nat("(0branch)", lambda m: None)
        self.do_xt = nat("(do)", lambda m: None)
        self.qdo_xt = nat("(?do)", lambda m: None)
        self.loop_xt = nat("(loop)", lambda m: None)
        self.plusloop_xt = nat("(+loop)", lambda m: None)
        self.leave_xt = nat("(leave)", lambda m: None)
        self.unloop_xt = nat("unloop", lambda m: None)
        self.i_xt = nat("i", lambda m: None)
        self.j_xt = nat("j", lambda m: None)
        def _word(m):
            m.parse_name()
            m.push(m.wordbuf)
        nat("word", _word)
        def _colon(m):
            tok = m.parse_name()
            xt = m.header_create(tok, DOCOL)
            m.colon[xt] = True
            m.words[tok.decode("latin1")] = xt
            m.state = 1
        nat(":", _colon)
        def _semi(m):
            m.compile(self.exit_xt)
            m.state = 0
        nat(";", _semi, 1)
        nat("literal", lambda m: (m.compile(m.lit_xt), m.compile(m.pop())), 1)
        def _immediate(m):
            m.wr8(m.latest + 8, m.rd8(m.latest + 8) | 1)
        nat("immediate", _immediate)
        def _create(m):
            tok = m.parse_name()
            xt = m.header_create(tok, DOCON)
            m.words[tok.decode("latin1")] = xt
        nat("create", _create)
        def _bslash(m):
            p = m.in_ptr
            while m.rd8(p) not in (0, 0x0A):
                p += 1
            m.in_ptr = p
        nat("\\", _bslash)
        def _dotq(m):
            # skip spaces, read to '"'
            p = m.in_ptr
            while m.rd8(p) in (0x20, 0x09):
                p += 1
            start = p
            while m.rd8(p) not in (0, 0x22):
                p += 1
            ln = p - start
            if m.rd8(p) == 0x22:
                p += 1
            m.in_ptr = p
            if m.state == 0:
                m.emit_str(bytes(m.rd8(start + i) for i in range(ln)))
            else:
                m.compile(m.dotq_rt_xt)
                a = m.align4(m.here + 8)
                m.compile(a)
                m.compile(ln)
                m.here = a
                for i in range(ln):
                    m.wr8(m.here, m.rd8(start + i)); m.here += 1
                m.here = m.align4(m.here)
        nat('."', _dotq, 1)
        self.dotq_rt_xt = nat('(."', lambda m: None)
        def _paren(m):
            p = m.in_ptr
            while m.rd8(p) not in (0, 0x29):
                p += 1
            m.in_ptr = p + 1 if m.rd8(p) == 0x29 else p
        nat("(", _paren, 1)
        def _lb(m):
            m.state = 0
        nat("[", _lb, 1)
        nat("]", lambda m: setattr(m, "state", 1))
        def _postpone(m):
            tok = m.parse_name()
            xt = m.find(tok)
            if not xt:
                m.state = 0
                m.emit_str("-? ")
                m.emit_str(tok)
                return
            m.compile(m.lit_xt)
            m.compile(xt)
            m.compile(self.comma_xt)
        nat("postpone", _postpone, 1)
        self.comma_xt = self.words[","]
        def _find(m):
            ln = m.pop(); a = m.pop()
            tok = bytes(m.rd8(a + i) for i in range(ln))
            xt = m.find(tok)
            m.push(xt)
            m.push(-1 if xt else 0)
        nat("find", _find)
        def _number(m):
            ln = m.pop(); a = m.pop()
            tok = bytes(m.rd8(a + i) for i in range(ln))
            n = m.number_q(tok)
            m.push(0 if n is None else n)
            m.push(-1 if n is not None else 0)
        nat("number", _number)
        nat("execute", lambda m: m.execute_xt(m.pop()))
        def _tick(m):
            tok = m.parse_name()
            xt = m.find(tok)
            if not xt:
                m.state = 0
                m.emit_str("-? ")
                m.emit_str(tok)
                xt = 0
            m.push(xt)
        nat("'", _tick)
        def _tickb(m):
            tok = m.parse_name()
            xt = m.find(tok)
            if not xt:
                m.state = 0
                m.emit_str("-? ")
                m.emit_str(tok)
                xt = 0
            m.compile(m.lit_xt)
            m.compile(xt)
        nat("[']", _tickb, 1)
        self.state_v = self.alloc_mem(4)
        nat("state", lambda m: m.push(m.state_v))
        def _abort(m):
            raise Abort()
        nat("abort", _abort)
        nat("refill", lambda m: m.push(-1))
        nat("boot-msg", lambda m: m.emit_str("FUNForth seed 0.1 "))
        nat("quit", lambda m: None)
        nat("interpret", lambda m: m.interpret_mem(m.pop()))
        def _nip(m):
            b = m.rd32(m.r[4]); a = m.rd32(m.r[4] + 4)
            m.wr32(m.r[4] + 4, b)
            m.r[4] += 4
        nat("nip", _nip)
        def _tuck(m):
            b = m.rd32(m.r[4]); a = m.rd32(m.r[4] + 4)
            m.r[4] -= 4
            m.wr32(m.r[4] + 8, a); m.wr32(m.r[4] + 4, b); m.wr32(m.r[4], b)
        nat("tuck", _tuck)
        def _rot(m):
            c = m.rd32(m.r[4]); b = m.rd32(m.r[4] + 4); a = m.rd32(m.r[4] + 8)
            m.wr32(m.r[4], a); m.wr32(m.r[4] + 4, c); m.wr32(m.r[4] + 8, b)
        nat("rot", _rot)
        nat(">r", lambda m: (m.rpush(m.pop())))
        nat("r>", lambda m: m.push(m.rpop()))
        nat("r@", lambda m: m.push(m.rd32(m.r[13])))
        def _rdrop(m):
            m.r[13] += 4
        nat("rdrop", _rdrop)
        def _goname(m):
            xt = m.pop()
            m.push(xt)  # name_of reverse-walk; xt is its own header
        nat(">name", _goname)
        def _count(m):
            a = m.rd32(m.r[4])
            ln = 0
            while m.rd8(a + ln):
                ln += 1
            m.push(ln)
        nat("count", _count)
        nat("docol-addr", lambda m: m.push(DOCOL))
        nat("forget", lambda m: None)
        nat("marker", lambda m: None)
        # printing
        def _dot(m):
            v = m.pop()
            sv = v - (1 << 32) if v >= 0x80000000 else v
            if sv < 0:
                m.emit(0x2D)
                sv = -sv
            m.emit_str(str_base(sv, m.base))
        nat(".", _dot)
        nat("u.", lambda m: m.emit_str(str_base(m.pop(), m.base)))
        nat("h.", lambda m: m.emit_str("%08X" % m.pop()))
        self.base_v = self.alloc_mem(4)
        self.wr32(self.base_v, 10)
        nat("base", lambda m: m.push(m.base_v))
        nat("span", lambda m: m.push(0))
        nat("emit", lambda m: m.emit(m.pop()))
        nat("emit-uart", lambda m: m.emit(m.pop()))
        nat("key", lambda m: m.push(0))
        nat("key-uart", lambda m: m.push(0))
        nat("key?", lambda m: m.push(0))
        nat("key?-uart", lambda m: m.push(0))
        nat("cr", lambda m: m.emit_str("\n"))
        nat("space", lambda m: m.emit(0x20))
        def _type(m):
            ln = m.pop(); a = m.pop()
            m.emit_str(bytes(m.rd8(a + i) for i in range(ln)))
        nat("type", _type)
        nat("accept", lambda m: m.push(0))
        nat("expect", lambda m: None)
        nat("err", lambda m: None)
        nat("console-uart", lambda m: None)
        nat("con-emit!", lambda m: m.pop())
        nat("con-key!", lambda m: m.pop())
        nat("con-keyq!", lambda m: m.pop())
        nat("pause", lambda m: None)
        nat("task-table", lambda m: m.push(0))
        nat("up-cur", lambda m: m.push(0))
        nat("tick-ckpt", lambda m: None)
        nat("quanta", lambda m: m.push(0))
        nat("preempts", lambda m: m.push(0))
        nat("tick-force", lambda m: None)
        nat("preemptible", lambda m: None)
        nat("io-base", lambda m: m.push(0x20000000))
        nat("hal-pud-wait", lambda m: None)
        nat("latest", lambda m: m.push(m.latest))
        nat("here", lambda m: m.push(m.here))
        nat("cold", lambda m: None)
        nat("warm", lambda m: None)
        nat("bye", lambda m: None)
        def _align16(m):
            m.here = (m.here + 15) & ~15
        nat("align16", _align16)
        # sd / load from host
        nat("sd-mount", lambda m: m.push(-1))
        def _load_file(m):
            ln = m.pop(); a = m.pop()
            name = bytes(m.rd8(a + i) for i in range(ln)).decode("latin1").upper()
            path = m.sd_map.get(name)
            if not path:
                m.emit_str("-? ")
                m.emit_str(bytes(m.rd8(a + i) for i in range(ln)))
                raise Abort()
            data = open(path, "rb").read()
            buf = m.alloc_mem(len(data) + 1)
            for i, b in enumerate(data):
                m.wr8(buf + i, b)
            m.wr8(buf + len(data), 0)
            m.interpret_mem(buf)
        nat("load-file", _load_file)
        def _load(m):
            tok = m.parse_name()
            m.push(m.wordbuf)
            m.push(len(tok))
            _load_file(m)
        nat("load", _load)
        nat("sd-boot", lambda m: None)
        nat("file-sum", lambda m: m.push(0))
        nat("bootlst", lambda m: None)

    def sd_files(self):
        mk = open("Makefile").read()
        m = re.search(r"SD_FILES\s*=\s*(.+)", mk)
        entries = re.findall(r"([A-Z0-9._-]+\.[A-Z0-9]+)=(\S+)", m.group(1)) if m else []
        if not entries:
            entries = re.findall(r"([A-Z0-9._-]{1,8}\.[A-Z0-9]{1,3})=(\S+)", mk)
        return {name: path for name, path in entries}


def str_base(v, base):
    if v == 0:
        return "0"
    digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    out = ""
    while v:
        out = digits[v % base] + out
        v //= base
    return out


def run_test(script_path):
    m = Machine()
    # boot: banner + core.fth + sd.fth + boot.lst files (via host load)
    m.emit_str("FUNForth seed 0.1 ")
    for f in ("forth/core.fth", "drivers/sd.fth"):
        data = open(f, "rb").read()
        buf = m.alloc_mem(len(data) + 1)
        for i, b in enumerate(data):
            m.wr8(buf + i, b)
        m.wr8(buf + len(data), 0)
        m.interpret_mem(buf)
    for f in ("drivers/timer.fth", "drivers/gpio.fth", "drivers/mailbox.fth", "forth/tasks.fth"):
        data = open(f, "rb").read()
        buf = m.alloc_mem(len(data) + 1)
        for i, b in enumerate(data):
            m.wr8(buf + i, b)
        m.wr8(buf + len(data), 0)
        m.interpret_mem(buf)
    # script lines, paced like qemu-ctl
    lines = open(script_path, "rb").read().decode("latin1").split("\n")
    for line in lines:
        if line == "" and lines.index(line) == len(lines) - 1:
            break
        m.out += b"ok> " + line.encode("latin1") + b"\n"
        try:
            m.interpret_str(line)
        except Abort:
            m.r[4] = m.ps0
            m.state = 0
        m.out += b" ok\n"
    return bytes(m.out)


def main():
    if len(sys.argv) >= 3 and sys.argv[1].startswith("test/"):
        got = run_test(sys.argv[1]).decode("latin1")
        exp = open(sys.argv[2]).read()
        if got == exp:
            print("PASS: sim transcript matches %s" % sys.argv[2])
            return 0
        import difflib
        print("FAIL: sim transcript mismatch")
        for l in difflib.unified_diff(exp.splitlines(), got.splitlines(), "expected", "sim", lineterm=""):
            print(l)
        return 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
