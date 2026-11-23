# FUNForth Implementation Specification v2.0 (milestone-revised)

Status: this document **supersedes** the uploaded PDF `DAQVTaNM-FUNForth.pdf` (v1.0).
Where v2.0 states a number, name, or command, v2.0 wins. v1.0 remains the source for
rationale; only the deltas and the re-divided milestone plan are new here.

Purpose: a machine-actionable specification for automated coding agents. Every
milestone states: artifacts to produce, exact behavior, and an automated acceptance
test. Milestones are sized so that **one milestone = one branch = one PR**, and each
PR can be made green independently with `make test` (QEMU) in a single pass.

Targets: Pi Zero/Zero W (BCM2835, ARMv6, single core) and Pi 3A+/3B (BCM2837,
Cortex-A53, quad core in 32-bit mode). One binary, `kernel.img`, boots both.

Languages: ARM assembly for the seed only (`src/seed.S` family), FUNForth source for
everything else. No C. Toolchain: `arm-none-eabi-gcc` used as assembler+linker only
(`-nostdlib -nostartfiles -mfloat-abi=soft -march=armv6k` for the Zero baseline;
`-march=armv8-a` accepted since ARMv6 code is a subset and the same image must run
on both). Dev loop: QEMU-first; hardware runs verify board-specific layers.

## 0. Conventions for the coding agent

1. One milestone = one branch = one PR. Do not implement later milestones to make an
   earlier test pass.
2. Tests are FORTH source checked into `test/`, executed by `make test`, which boots
   the image under QEMU, pipes a test script over the serial console, and compares the
   transcript with `test/expected.txt`. Get `make test` green before a milestone is
   done.
3. Stack-effect comments are mandatory on every defined word: `( a b -- c )`.
4. Naming: FORTH words lowercase-hyphenated (`win-open`); code-words in caps (`NEXT`,
   `PAUSE`); assembler mnemonics lowercase (`mov,`); constants uppercase (`UART0-DR`).
5. Never delete or redefine an existing word silently; redefinition is allowed
   (later link wins) and `see` must show the active one.
6. Peripheral access ALWAYS goes through `io-base`-relative words, never absolute
   addresses in driver code.
7. Keep each PR small: if a milestone's diff exceeds ~1200 lines, split the milestone
   further rather than growing it.

## 1. Repository layout

```
funforth/
Makefile            # builds kernel.img + kernel.elf, runs make test / make run
link.ld             # linker script (entry reset, . = 0x8000)
boot/               # firmware blobs copied from a Raspberry Pi OS card:
                    #   bootcode.bin start.elf config.txt (+ README.md saying so)
config.txt          # arm_64bit=0, gpu_mem=16, disable_commandline_tags=0
src/
  seed.S            # assembly seed: entry, NEXT, core primitives, EARLY uart
  hal-2835.S        # BCM2835 slab: peripheral base, pull-up protocol
  hal-2837.S        # BCM2837 slab: peripheral base, core parking, alt GPIO pulls
forth/
  core.fth          # compiler, outer interpreter, QUIT (embedded for test builds,
                    # loaded from SD when present)
  asm.fth           # ASSEMBLER vocabulary
  tasks.fth         # multitasker
  smp.fth           # 3A+ worker cores (no-op on Zero)
drivers/
  uart.fth timer.fth gpio.fth mailbox.fth fb.fth sd.fth fat32.fth
  i2c.fth ssd1306.fth usbhid.fth rtc-ds3231.fth
vdi.fth wm.fth term.fth gui.fth
utils/probe.fth utils/save-image.fth
tools/
  qemu-ctl.py       # drives QEMU (stdin script, transcript capture, QMP screendump)
  mksd.py           # builds the FAT32 test SD image used by make test-sd
doc/manual.fth      # the user manual as FORTH comments + help words
docs/SPEC-v1-notes.md  # delta list v1.0 -> v2.0 (this file is SPEC.md itself)
test/
  all.fth           # test entry: includes each t-*.fth present at this milestone
  t-core.fth t-tasks.fth t-asm.fth t-drivers.fth t-smp.fth t-gui.fth
  expected.txt      # golden console transcript for `make test`
SPEC.md             # this document
README.md
```

`config.txt`:

```
arm_64bit=0
gpu_mem=16
disable_commandline_tags=0   # keep the ATAGS/DTB pointer in r2 at entry
```

Build outputs: `kernel.img` (raw at 0x8000), plus `kernel.elf` kept for objdump audits.

## 2. Memory map (authoritative)

| Region | Address / rule |
| --- | --- |
| Load & entry | 0x00008000 (r2 = ATAGS pointer from firmware) |
| Kernel image | .text .rodata .data starting 0x8000; .bss follows |
| Dictionary base | FORTH-START = end of .bss, 4-byte aligned |
| Dictionary grows UP | arena cap HERE-LIMIT = FORTH-START + 1 MB (kernel words only); extensions continue into free RAM |
| Task table + user areas | static array after dictionary limit, 64 user areas x 96 bytes; task stacks from arena, default 256 B PS + 256 B RS each |
| Framebuffer (M10+) | GPU-allocated via mailbox (32 KB, 1 bpp, 640x400); mapped device/uncached |
| Peripheral base | 0x20000000 (BCM2835) / 0x3F000000 (BCM2837); resolved at boot into IO-BASE, exposed as FORTH constant `io-base` |
| MMU | OFF until M24; then identity-mapped, Device type for peripherals, Cacheable for RAM |

Hard limits: image (seed+std words) <= 16 KB machine code; boot SD load of `core.fth`
may add up to 32 KB.

## 3. Seed assembly (src/seed.S)

### 3.1 Boot sequence

1. `reset` at 0x8000: CPSR mode = SYS, IRQ/FIQ disabled, copy the 8-word vector slab
   to 0x0000.
2. Walk ATAGS in r2: capture mem size (tag 0x10002) and board revision; default
   512 MB.
3. Detect SoC from the ATAGS revision code (bits 16-23 == 0x0d => BCM2837 class);
   set IO-BASE 0x3F000000 vs 0x20000000 accordingly (fallback 0x20000000). On 2837 use
   `hal-2837.S` init; park cores 1-3.
4. Zero .bss; r13 (return stack) = top-of-RAM - 4 KB; r4 (parameter stack) = 1 KB
   window above the dictionary arena; I-cache ON, D-cache OFF (MMU off until M24).
5. Init UART0 PL011: 115200 8N1.
6. `cold`: set UP (HERE), emit seed word headers directly, set latest, enter FORTH:
   interpret the embedded core string (test build) or `boot` from SD (M12+).

### 3.2 Register allocation (fixed; all files obey)

| Register | Role |
| --- | --- |
| r10 | IP (instruction pointer) |
| r11 | W (current word pointer) |
| r13 | return stack pointer |
| r4 | SP (parameter stack pointer, grows DOWN) |
| r0-r3 | TOS scratch: r0 = TOS; r1 free; r2-r3 scratch |
| r5 | task pointer (user area of current task) |
| r6 | latest dictionary pointer; r7 = HERE; r8 = state; r9 = IO-BASE |
| r12 | clobberable |

Guards: 512 B below PS0 and above RS0 reserved; under/overflow raises `err` abort.

### 3.3 NEXT (DTC) and primitive pattern

```
NEXT:   ldr r11, [r10], #4
        ldr pc, [r11, #4]      @ CFA is: 0 pad, PFA-code addr
```

Header per word (v2.0 refined layout, implemented in M1; wins over v1.0 prose; at
HERE, growing UP): **link(4) | cfa(4) | flags(1) | len(1) | name(len) | pad-to-4 |
PFA**. `xt` = header address; threaded lists contain xts; flags bit0 = immediate,
bit1 = smudge. Code words end with `b next`. `EXECUTE` (asm helper) saves lr on the
scratch stack, points r10 at a one-cell list holding the `tramp` word's xt, and
`blx`s the code field; `tramp` (`pop {pc}`) returns. Stack convention: **r4 points
at the TOS cell ([r4] = TOS)**; r0-r3/r12 are pure scratch (v1.0's "r0 = TOS cell"
was revised: the outer interpreter needs r0 as scratch).

### 3.4 Mandatory seed word set (assembly)

- State/stack: `DUP DROP SWAP OVER NIP TUCK ROT >R R> R@ RDROP DEPTH`
- Arithmetic/logic: `+ - * /MOD U/MOD AND OR XOR INVERT LSHIFT RSHIFT 0= 0< 0> = < >
  U< <> MIN MAX 1+ 1- 2* 2/ ABS NEGATE`
- Memory: `@ ! C@ C! +! W@ W! ALLOT , C, HERE FILL MOVE`
- Return/jump: `(branch) (0branch) (next) (loop) EXIT NEXT PAUSE-lite BYE`
- Outer: `EMIT-EARLY KEY?-EARLY KEY-EARLY`
- Compiler bootstrap: `: ; LITERAL IMMEDIATE CREATE` (minimum viable; full compiler is
  FORTH-written in `forth/core.fth`)
- System: `COLD WARM IO-BASE LATEST HERE PAUSE TASKS BREAK`
- Asm table allocator hook: `ASSEMBLE-SLOT` (used by M15+)

## 4. FORTH core (forth/core.fth)

### 4.1 Outer interpreter / QUIT

- `QUIT`: reset input source; loop: `QUERY` (line in, max 128 chars) -> `INTERPRET`
  -> `ok` -> `cr` -> recurse. Errors: `err` switches source to keyboard after
  printing `-? <word>`.
- `QUERY`: per-task line buffer, backspace = `\b space \b`, history ring of 8 lines
  per task.
- Control-flow/compiler words: `refill word find number IF ELSE THEN BEGIN UNTIL
  AGAIN WHILE REPEAT CASE ENDCASE ENDOF DO ?DO LEAVE +LOOP UNLOOP I J EXIT ?DUP ABORT
  ." POSTPONE [ ] ' ['] EXECUTE STATE BOOT-MSG`
- `see` (decompile: code words print `<code> addr/len`; colon words walk PFA cells,
  print nested xt names, literals as `lit n`, branches as `-> label`), `words`
  (latest->oldest, 8 per line), `forget`, `marker`.

### 4.2 Console word set (per-task EMIT target)

`emit key key? cr space type expect span accept` route to the current task's console
vector in its user area; `console-uart console-fb console-oled` set it.

## 5-11. Drivers, VDI/WM/GUI, storage (normative content unchanged from v1.0 except deltas below)

Register offsets are `io-base`-relative. Key blocks: system timer +0x3000
(`micros millis ms tick-start`); UART PL011 +0x201000 (`emit-uart key?-uart key-uart
baud`); GPIO +0x200000 (`pin-mode pin! pin@ pin-pull led!`); mailbox 0 +0xB880
(`mbox-call` + tags `board-model board-rev mac ram-size temp fb-alloc`); framebuffer
640x400 1bpp (`fb-off`, VDI `clip! pixel line rect fillrect invert-rect blit text`,
font `glyph` from embedded `font8x16`); I2C BSC +0x804000 (`i2c! i2c@`), SSD1306 at
0x3C/0x3D, DS3231 at 0x68 (`time@ time!`); USB HID via dwc2 OTG +0x98000 (2835) /
+0x980000 (2837) (`moused@`, `keyusb`); WM/GUI structures and FORm API exactly as
v1.0 sections 9-10.

### Delta D1 (v1.0 section 8.6): SD card via the Arasan SDHCI (EMMC) controller

v1.0 specified the legacy SDHOST at +0x202000. That block is **not emulated by QEMU's
raspi machines and is used by the Wi-Fi chip on the 3B**, so a SDHOST driver could
never be tested under QEMU and is the wrong card controller. v2.0 uses the Arasan
SDHCI at **peripheral base +0x300000** (EMMC2), which QEMU raspi0/raspi3ap emulate and
Linux uses for the SD card on all models. Words unchanged: `sd-read ( lba buf --
flag )`, `load ( name -- )`, plus the FAT32 RO layer (`find-file open read`, 8.3
names only, MBR/BPB parse, first partition type 0x0B/0x0C). SDHOST is a non-goal.

### Delta D2: QEMU machine names

The v1.0 baseline `-M raspi` is named **`raspi0`** in current QEMU (Zero) and the
3A+ model is **`raspi3ap`** (exposed by `qemu-system-aarch64`; `qemu-system-arm`
carries raspi0/raspi1ap/raspi2b only). Canonical commands are in Appendix A. If the
local QEMU build cannot enter AArch32 on raspi3ap, 3A+/SMP acceptance is
hardware-only and marked as such per milestone.

### Delta D3: QEMU loads a raw `-kernel` image at 0x10000 on raspi models

Verified on QEMU 10.0 (`-M raspi0`): a raw `kernel.img` passed via `-kernel` is
loaded at 0x10000, not 0x8000, so a 0x8000-linked raw image executes at the wrong
address. The harness therefore boots **`kernel.elf`** (ELF program headers are
honored, entry 0x8000). Real hardware still boots the raw `kernel.img` at 0x8000
via the GPU firmware. `make run` / `make test` use `kernel.elf`; `kernel.img`
remains the SD-card artifact.

## 12. Milestones v2.0 (phased, each one branch = one PR)

Tracking table (check off in the PR that completes the milestone):

| # | Milestone | Phase | Depends on | Automated acceptance |
| --- | --- | --- | --- | --- |
| [x] M0 | Build scaffolding + UART boot banner | A | - | `make test` M0 transcript |
| [x] M1 | Seed machine setup + IO-BASE + seed REPL | A | M0 | `make test` M1 |
| [ ] M2 | Seed stack/arith/memory word set | A | M1 | `make test` t-core part 1 |
| [ ] M3 | Branch words + embedded core + compiler (`:` `;`) | A | M2 | greet/sq transcript |
| [ ] M4 | QUIT/QUERY console discipline + console words | B | M3 | `make test` t-core part 2 |
| [ ] M5 | Control-flow words | B | M4 | `make test` t-core part 3 |
| [ ] M6 | `words` / `see` / `forget` / `marker` | B | M5 | `make test` t-core part 4 |
| [ ] M7 | System timer `micros millis ms tick-start` | C | M4 | t-drivers timer |
| [ ] M8 | GPIO `pin-mode pin! pin@ pin-pull led!` | C | M7 | t-drivers gpio |
| [ ] M9 | Mailbox properties | C | M1 | t-drivers mbox |
| [ ] M10 | Framebuffer + VDI + font, screendump test | C | M9 | `make test-fb` diff |
| [ ] M11 | `console-fb` 80x25 grid + cursor blink | C | M10 | `make test-fb` text diff |
| [ ] M12 | SD (Arasan SDHCI) + FAT32 RO + `boot.lst`/`load` | C | M4 | `make test-sd` checksum |
| [ ] M13 | Task ring + PAUSE + `task: spawn wake kill halt tasks` | D | M4 | t-tasks basic |
| [ ] M14 | 1 kHz tick preemption (`preemptible`) | D | M7, M13 | t-tasks preempt |
| [ ] M15 | `CODE`/`end-code` assembler core | E | M3 | t-asm double/see/error |
| [ ] M16 | Full assembler word set + encoding guards | E | M15 | t-asm full |
| [ ] M17 | WM core: windows, menu bar, redraw, XOR drag | F | M10 | t-gui scripted |
| [ ] M18 | Terminal window in WM + arrow-key fallback | F | M11, M17 | t-gui 3 windows |
| [ ] M19 | GUI FORm API + hello demo | F | M18 | t-gui demo |
| [ ] M20 | I2C + SSD1306 OLED console + DS3231 | G | M8 | hardware visual |
| [ ] M21 | USB HID keyboard/mouse | G | M4 | report-vector unit test |
| [ ] M22 | SMP worker cores (3A+) | G | M13 | t-smp (hw or raspi3ap) |
| [ ] M23 | IRQ-driven UART/tick + latency bound | G | M14 | latency unit test |
| [ ] M24 | MMU identity map + caches + `save-image`/`load-image` | G | M12 | speed + save/restore |
| [ ] M25 | Release: `doc/manual.fth` help words, probe, demo pack, soak | G | all | full `make test` both models |

Per-milestone definition (artifacts / behavior / acceptance):

- **M0 Build scaffolding + boot banner.** Artifacts: `Makefile` (targets `all`,
  `kernel.img`, `kernel.elf`, `run`, `test`, `test-fb`, `test-sd`, `clean`),
  `link.ld`, `config.txt`, `boot/README.md` (firmware blobs are copied from a Pi OS
  card; not committed), `src/seed.S` with reset vector, SYS mode, IRQ/FIQ off,
  .bss zero, PL011 init + `EMIT-EARLY`, banner `FUNForth seed 0.1 ok> `, and a spin
  loop. `tools/qemu-ctl.py` harness. Acceptance: `make test` boots
  `qemu-system-arm -M raspi0 -kernel kernel.elf -serial stdio -display none`
  (Delta D3), feeds an empty script, transcript matches `test/expected.txt`
  (banner line only).
- **M1 Seed machine setup + REPL.** Artifacts: ATAGS walk, SoC detect, `hal-2835.S` /
  `hal-2837.S`, words `io-base latest here cold warm`; a minimal seed REPL over UART
  that parses a number (push) or finds a seed word (execute). Console discipline:
  banner `FUNForth seed 0.1 ` then prompt `ok> ` per line; after each line ` ok` +
  CRLF; unknown word prints `-? <word>` and aborts the line. Acceptance (`make test`):
  `io-base h.` prints `20000000 ok` on raspi0; `1 2 + depth .` prints `1 ok`;
  `foobar` prints `-? foobar ok`.
- **M2 Seed word set.** Artifacts: all stack/arith/logic/memory words of 3.4.
  Acceptance: `test/t-core.fth` part 1 golden, e.g. `2 3 + .` -> `5 ok`,
  `10 3 /mod . .` -> `3 1 ok`, `here @ .` runs, `42 here ! here @ .` -> `42 ok`.
- **M3 Compiler bootstrap.** Artifacts: `(branch) (0branch) EXIT`, embedded core
  string in seed interpreted at `cold`, FORTH-written `: ; LITERAL IMMEDIATE CREATE
  ."`. Acceptance: `: sq dup * ; 7 sq .` -> `49 ok`; `: greet ." Hello, FUNForth" ;
  greet` -> `Hello, FUNForth ok` (one-space discipline after `ok`).
- **M4 Console discipline.** Artifacts: `QUIT QUERY INTERPRET err` with 128-char line
  buffer, backspace handling, 8-line history ring; console words `emit key key? cr
  space type expect span accept` via per-task console vector (`console-uart`);
  number output `. u. base`. Acceptance: t-core part 2 golden, including error
  `foobar` -> `-? foobar ok`.
- **M5 Control flow.** Artifacts: the v1.0 4.1 word list implemented in `core.fth`.
  Acceptance: t-core part 3 golden: `5 0 do i . loop` -> `0 1 2 3 4 ok`, recursive
  fib `10 fib .` -> `55 ok`, `case` example.
- **M6 Introspection.** Artifacts: `words see forget marker`. Acceptance: `see sq`
  prints the decompiled definition; `words` lists latest first, 8 per line.
- **M7 System timer.** Artifacts: `drivers/timer.fth` over +0x3000: `micros millis
  ms tick-start` (1 kHz compare1). Acceptance: `millis dup - .` prints `0 ok`;
  `0 millis 100 ms millis swap - .` prints a value in 90..110.
- **M8 GPIO.** Artifacts: `drivers/gpio.fth`: `pin-mode pin! pin@ pin-pull led!`
  (ACT LED = pin 47), with hal pull-up protocol differences. Acceptance:
  `47 1 pin-mode 47 pin! 47 pin@ .` -> `1 ok`; hardware: ACT LED blinks.
- **M9 Mailbox.** Artifacts: `drivers/mailbox.fth`: `mbox-call` (channel 8,
  16-byte-aligned buffer) + `board-model board-rev mac ram-size temp`. Acceptance on
  QEMU raspi0: `ram-size .` prints the QEMU RAM size (512M => `200000 ok` in hex
  `20000000`), `board-rev h.` prints a revision word.
- **M10 Framebuffer + VDI.** Artifacts: `drivers/fb.fth` (`fb-alloc` via tags
  0x40001, 640x400 1bpp, `fb-off`), `vdi.fth` (`clip! pixel line rect fillrect
  invert-rect blit text`), embedded `font8x16` + `glyph`. Acceptance: `make test-fb`
  draws a known pattern, QMP `screendump` PPM diffed against golden (magic-pixel
  checks).
- **M11 console-fb.** Artifacts: 80x25 grid over the 1 bpp fb, 2 Hz cursor blink via
  M7 timer, `console-fb` vector; same QUERY/accept paths as UART. Acceptance:
  `make test-fb` screendump contains the `ok>` prompt pixels; scripted keys echo on
  the fb console.
- **M12 SD + FAT32.** Artifacts: `drivers/sd.fth` (Arasan SDHCI +0x300000: init
  CMD0/CMD8/CMD55/ACMD41, `sd-read`), `drivers/fat32.fth` RO (MBR, BPB, root cluster,
  8.3 names), `boot.lst` + `load`, `tools/mksd.py` builds the FAT32 test image.
  Acceptance: `make test-sd` boots with `-sd` image, loads a known file, prints its
  checksum; checksum matches golden in `expected.txt`. SD missing = bare UART prompt.
- **M13 Multitasker.** Artifacts: `forth/tasks.fth`: 64-slot ring, 96-byte user areas
  (offsets per v1.0 6), `PAUSE` save/advance/restore, `task: spawn wake kill halt
  tasks yield sleep ( n -- )`. Acceptance: t-tasks basic: two tasks alternate
  printing; `kill` stops one, the shell stays responsive.
- **M14 Tick preemption.** Artifacts: 1 kHz tick counts quanta; at 20 over-quanta,
  if `up-attr` preempt bit set, `up-force-pause`; PAUSE checkpoint at branch targets.
  Acceptance: an infinite-loop task stops a blinking-LED task; marking the shell
  `preemptible` recovers responsiveness within ~20 ms (t-tasks preempt test).
- **M15 Assembler core.** Artifacts: `forth/asm.fth` `CODE ... end-code`, data ops
  (`mov, add, sub, ...`), `b bl bx`, labels `:<name>` / `<name> b,`, `next`,
  `rpush/rpop/tos-push`. Acceptance: `code double 2* next end-code` (via asm words)
  `21 double .` -> `42 ok`; `see double` prints mnemonics; a bad encoding aborts
  with an error and does not move HERE.
- **M16 Full assembler.** Artifacts: memory ops with all postfix addressing modes,
  mult/ldm/stm/swp, condition prefixes, `-s` variants, `mrs/msr/bkpt/dsb/dmb/isb/
  cpsid/cpsie`, literal pool at `end-code`, diagnostic on illegal encodings.
  Acceptance: t-asm full golden.
- **M17 WM core.** Artifacts: `wm.fth` window records (v1.0 10.1 layout), menu bar,
  `WM_REDRAW` protocol with `begin-redraw ... next-redraw` (`clip> next-redraw`),
  XOR-outline drag, one WM task owning redraw arbitration. Acceptance: t-gui
  scripted event test (arrow-key fallback in QEMU).
- **M18 Terminal window.** Artifacts: `term.fth` terminal in a GEM window, cell-snapped
  move/resize, scroll region, close refused on last terminal; own back-buffer, blit
  on redraw. Acceptance: three windows simultaneously, scripted keys + screendump.
- **M19 GUI API + demo.** Artifacts: `gui.fth` FORm API (v1.0 10.3:
  `needs gui win-new win-open win-close win-top win-full menu-bar! event? event@
  clip> next-redraw wtext button pointer-x pointer-y buttons`), demo `hello.fth`
  (200x150 window, close box, counter button). Acceptance: scripted mouse events
  (arrow-key fallback in QEMU), counter increments, close box works.
- **M20 I2C/OLED/RTC.** Artifacts: `drivers/i2c.fth` (`i2c! i2c@`), `ssd1306.fth`
  (128x64 console channel, 21x8 chars at 6x8, `console-oled`), `rtc-ds3231.fth`
  (`time@ time!`). Acceptance: hardware visual (OLED shows prompt); QEMU: words
  exist and register writes are trapped cleanly (no bus fault).
- **M21 USB HID.** Artifacts: `drivers/usbhid.fth` dwc2 host, boot-protocol keyboard
  + mouse, `moused@ keyusb`; offline report-vector unit test in t-drivers. Acceptance:
  unit test decodes report vectors to events; hardware manual.
- **M22 SMP (3A+).** Artifacts: `forth/smp.fth`: cores 1-3 parked until vector write +
  `sev`, per-core rings, lock-free SPSC queues, `cores core core! send recv sendx
  recvx corelist`; on Zero `cores` returns 1. Acceptance: t-smp 4-core swp-locked
  counter on hardware 3A+ (QEMU raspi3ap if the local build enters AArch32).
- **M23 IRQs.** Artifacts: IRQ vector wiring, UART IRQ 57 handler (`irq-hook-uart`),
  tick-driven preemptive scheduling via IRQ, `pat` watchdog pat in the `ok` loop.
  Acceptance: tick latency < 2 ms under load measured with `micros` (unit test).
- **M24 MMU + image save.** Artifacts: identity-mapped MMU (Device for peripherals,
  Cacheable for RAM), caches on, `utils/save-image.fth` writes `bootimg.bin` FAT
  file, seed `load-image` reads it when `mold.txt` present. Acceptance: `100000 0 do
  loop` >= 3x faster than M23; save -> reboot -> custom word restored.
- **M25 Release.** Artifacts: `doc/manual.fth` (manual as FORTH comments + help
  words), `utils/probe.fth`, demo pack; full `make test` green on raspi0 (and
  raspi3ap where supported); 1 h hardware soak. Acceptance: CI-style full run.

## 13. Error handling (carried from v1.0)

- `err ( addr len -- )`: prints `-? <name> ok` and returns to QUIT; compilation errors
  abort the current definition.
- Watchdog: BCM watchdog at 8 s from seed; the `ok` loop pats it (`pat`); hung machine
  reboots.
- UART break dumps minimal task state (M23+); seed traps UART framing error to WARM.

## 14. Explicit non-goals (unchanged from v1.0)

No C runtime; no networking beyond serial/GPIO terminal; no writable FAT32 or LFN;
no multi-user/privilege rings; no floating point; `load` from SD is the only loader;
GUI theming is fixed monochrome GEM. (SDHOST/Wi-Fi is additionally a non-goal per
Delta D1.)

## Appendix A. Dev environment and QEMU baseline (verified)

Toolchain: xPack `arm-none-eabi-gcc` (e.g. 15.2.1) used as assembler+linker:

```
arm-none-eabi-gcc -nostdlib -nostartfiles -mfloat-abi=soft -march=armv6k \
  -T link.ld -o kernel.elf src/seed.S src/hal-2835.S src/hal-2837.S
arm-none-eabi-objcopy -O binary kernel.elf kernel.img
```

QEMU baseline (QEMU >= 8; machine names per Delta D2):

```
# Zero path (primary; kernel.elf per Delta D3):
qemu-system-arm -M raspi0 -kernel kernel.elf -serial stdio -display none
# 3A+ path (if the local build enters AArch32 for a 32-bit kernel; else hardware):
qemu-system-aarch64 -M raspi3ap -kernel kernel.elf -serial stdio -display none -cpu cortex-a53
```

`make test` mechanics: `tools/qemu-ctl.py` starts QEMU with `-serial stdio` (pipes
`test/all.fth` on stdin), captures the transcript until the `TESTS-DONE` marker (or a
timeout), terminates QEMU, and diffs against `test/expected.txt`. `make test-fb` adds
a QMP socket and issues `screendump` for pixel diffs; `make test-sd` adds `-sd` with
the image built by `tools/mksd.py`.
