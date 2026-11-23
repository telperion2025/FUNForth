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
| [x] M2 | Seed stack/arith/memory word set | A | M1 | `make test` t-core part 1 |
| [x] M3 | Branch words + embedded core + compiler (`:` `;`) | A | M2 | greet/sq transcript |
| [x] M4 | QUIT/QUERY console discipline + console words | B | M3 | `make test` t-core part 2 |
| [x] M5 | Control-flow words | B | M4 | `make test` t-core part 3 |
| [x] M6 | `words` / `see` / `forget` / `marker` | B | M5 | `make test` t-core part 4 |
| [x] M7 | System timer `micros millis ms tick-start` | C | M4 | t-drivers timer (`make test` M7 section) |
| [x] M8 | GPIO `pin-mode pin! pin@ pin-pull led!` | C | M7 | t-drivers gpio (`make test` M8 section) |
| [x] M9 | Mailbox properties | C | M1 | t-drivers mbox (`make test` M9 section) |
| [ ] M10 | Framebuffer + VDI + font, screendump test | C | M9 | `make test-fb` diff |
| [ ] M11 | `console-fb` 80x25 grid + cursor blink | C | M10 | `make test-fb` text diff |
| [x] M12 | SD (Arasan SDHCI) + FAT32 RO + `boot.lst`/`load` | C | M4 | `make test-sd` checksum |
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
  Acceptance (`test/all.fth` golden, `make test`), e.g. `2 3 + .` -> `5 ok`,
  `10 3 /mod . .` -> `31 ok` (quot 3, rem 1; `.` prints no trailing space and the
  line suffix is ` ok`), `42 here ! here @ .` -> `42 ok`, `-10 3 /mod . .` ->
  `-3-1 ok`, `1 2 3 rot . . .` -> `132 ok`.
- **M3 Compiler bootstrap.** Artifacts: `(branch) (0branch) EXIT LIT` seed words,
  `DOCOL`/`DOCON` threaded-code entries, `execute_xt` trampoline (W=xt set before
  cfa; lr saved in a memory cell because r13/sp is shared with the Forth return
  stack), compile-mode `INTERPRET` (numbers compile as `LIT <n>`, non-immediate
  words append their xt, immediate words execute), seeded compiler words `: ; ."
  LITERAL IMMEDIATE CREATE WORD` (`;`/`."`/`LITERAL` immediate), header layout
  `link|cfa|flags|len|name|pad`, and `forth/core.fth` embedded via `.incbin` and
  interpreted at `cold` (`: 2dup over over ;` proves the compiler). `\."` compiles
  `( ." addr len` with the string embedded in the body; its runtime skips the
  string in the IP stream. Acceptance (`test/all.fth` golden, `make test`):
  `: sq dup * ; 7 sq .` -> `49 ok`; `: greet ." Hello, FUNForth" ; greet` ->
  `Hello, FUNForth ok`; `1 2 2dup . . . .` -> `2121 ok` (2dup from embedded core).
- **M4 Console discipline.** Artifacts: `QUIT QUERY INTERPRET err` with 128-char line
  buffer, backspace handling, 8-line history ring; console words `emit key key? cr
  space type expect span accept` via per-task console vector (`console-uart`);
  number output `. u. base`. Acceptance: t-core part 2 golden, including error
  `foobar` -> `-? foobar ok`.
  Implemented: `QUERY` reads via the console key vector with echo/backspace and an
  8-line history ring (ESC [ A / ESC [ B recall, redraw = `\b space \b` per char,
  non-empty lines stored); console vectors are cells `con_emit`/`con_key`/`con_keyq`
  (single task at M4) set by `console-uart` to `emit-uart`/`key-uart`/`key?-uart`;
  `emit key key? cr space type accept expect span` route through them (`accept` =
  `expect`, stores the count in `SPAN`); `base` variable (default 10) with
  base-aware `.`/`u.` (`print_base`, digits 0-9A-Z); `err` resets compile state.
  `execute_xt` saves IP+lr on a memory stack (`exec_stack`/`exec_idx`), NOT on r13,
  because r13 is shared with the Forth return stack (`>r`/`r>`). Acceptance
  (`test/all.fth` golden, `make test`): `foobar` -> `-? foobar ok`;
  `40 2 + .` then ESC[A recalls it -> `42 ok` twice; `65 emit` -> `A ok`;
  `1 . space 2 .` -> `1 2 ok`; `key? .` -> `0 ok`; `16 base ! 255 .` -> `FF ok`;
  `255 u.` -> `FF ok`; `2 base ! 5 .` -> `101 ok`; `-1 u.` -> `4294967295 ok`;
  `here 8 allot here 8 - 5 72 fill here 8 - 5 type` -> `HHHHH ok`.
- **M5 Control flow.** Artifacts: the v1.0 4.1 word list. Seed (asm): `postpone [ ]
  ' ['] find number execute state abort refill boot-msg ( (do) (?do) (loop)
  (+loop) (leave) unloop i j` (`i`/`j` are code words: `r@` inside a colon word
  would read the IP pushed by DOCOL). FORTH in `core.fth`: a dedicated control-flow
  stack (`cfbuf`/`cfsp`; r13 is the Forth return stack and must not hold compile
  state across immediate words) + `if else then begin until again while repeat do
  ?do leave loop +loop ?dup case of endof endcase`. `postpone` compiles the triple
  `lit <xt> ,` so immediate colon words append xts to the word being compiled.
  Control words are compile-only (standard); tests use `: name ... ; name`.
  Acceptance (`test/all.fth` golden, `make test`): `: tloop 5 0 do i . loop ; tloop`
  -> `01234 ok` (`.` prints no trailing space); `10 0 do i . 2 +loop` -> `02468 ok`;
  `3 0 ?do i . loop` -> `012 ok`; `5 5 ?do i . loop` -> ` ok`;
  `0 begin dup 3 < while dup . 1+ repeat drop` -> `012 ok`;
  `3 begin 1 - dup . dup 0= until drop` -> `210 ok`;
  `: fib dup 2 < if exit then 1 - dup fib swap 1 - fib + ; 10 fib .` -> `55 ok`;
  `1 case 1 of ." one" endof ." other" endcase` -> `one ok`; same with 3/1/2 ->
  `other ok`; `5 ?dup . .` -> `55 ok`; `7 ' sq execute .` -> `49 ok`;
  `: t2 [ 40 2 + ] . ; t2` -> `42 ok`.
- **M6 Introspection.** Artifacts: `words see forget marker`. Seed (asm): `>name`
  (reverse dictionary walk from `latest`, r0=xt -> r0=hdr|0), `count`,
  `docol-addr`, `forget` (parse+find, then `latest=[xt]` link, `here=xt`),
  `marker` + `domarker` (header whose PFA stores old latest/here; `domarker`
  restores both). FORTH in `core.fth`: `align4`, `.name` (prints a header name,
  keeps hdr — the consuming idiom `dup 9 + c@ swap 10 + swap type` eats the hdr
  when it is alone on the stack), `words` (latest-first walk via the link field,
  8 per line), `cell.` (decompiles one cell: `lit n`, `-> target` for
  (0branch)/(branch), inline string for (.", name via `>name`, else `?`), `see`
  (`word count 2dup find`, colon words decompiled from PFA until `exit`, code
  words printed as `<code> hdr len`). Acceptance (`test/all.fth` golden,
  `make test`): `see sq` -> `sq: dup * ; ok`; `see greet` ->
  `greet: Hello, FUNForth ; ok`; `see dup` -> `<code> 00008A9C 3 ok`;
  `marker m1` / `: mw 123 ;` / `mw .` -> `123 ok` / `m1` / `mw` -> `-? mw ok`;
  `forget zz` then `zz` -> `-? zz ok`; `words` lists the dictionary latest
  first, 8 per line.
- **M7 System timer.** Artifacts: `drivers/timer.fth` (embedded via `.incbin`
  after `forth/core.fth`, interpreted at cold; pure Forth over the BCM2835/2837
  SYSTIMER at PERIPHERALS+0x3000, offsets from `io-base`: CS=12288 CLO=12292
  C1=12304): `sys-cs sys-clo sys-c1`, `micros` (CLO, 1 MHz free-running low 32),
  `millis` (`micros 1000 u/mod nip` — quot is on top of `u/mod`),
  `ms` (`1000 * micros + begin dup micros swap < 0= until drop` — `until` exits
  when the flag is true, so the wait condition must be inverted),
  `tick-start` (C1 = CLO+1000, clear M1 in CS; 1 kHz compare1), `tick?` (CS bit 1).
  QEMU raspi0/raspi3ap emulate CLO and the C1 compare flag. Acceptance
  (`test/all.fth` golden, `make test`): `millis dup - .` -> `0 ok`;
  `0 millis 100 ms millis swap -` in 90..110 -> `-1 ok`;
  `tick-start 5 ms tick? .` -> `-1 ok`; `micros 10 ms micros swap -` in
  9000..100000 -> `-1 ok`.
- **M8 GPIO.** Artifacts: `drivers/gpio.fth` (embedded via `.incbin` after
  `drivers/timer.fth`, interpreted at cold) over GPIO at `io-base+0x200000`:
  helpers `gpio-fsel/set/clr/lev/pudclk` (bank = pin/10 or pin/32, `2 lshift`
  for the +4 stride), `gpio-mask`, `gppud!`; words `pin-mode` (pin mode --;
  mode 0=in 1=out; RMW of the 3-bit field), `pin!`, `pin-clr`, `pin@` (pin --
  0/1 level), `pin-pull` (pin mode --; GPPUD protocol with `hal-pud-wait`
  cycles around the GPPUDCLK write), `led!` (on --; ACT LED = pin 47, active
  low). Hal pull-up difference: each hal slab (`src/hal-2835.S`/`hal-2837.S`)
  exports `hal_pud_wait_<soc>`; boot stores it in `hal_pud_wait_v` (after the
  .bss clear!) and `hal-pud-wait` exposes it. QEMU raspi0/raspi3ap emulate
  GPSET/GPCLR/GPLEV. Acceptance (`test/all.fth` golden, `make test`):
  `47 1 pin-mode 47 pin! 47 pin@ .` -> `1 ok`; `47 pin-clr 47 pin@ .` -> `0 ok`;
  `1 led! 47 pin@ .` -> `0 ok` (active low); `0 led!` -> `1 ok`;
  `47 2 pin-pull` / `47 0 pin-pull` no-op cleanly; `hal-pud-wait .` -> `150 ok`;
  hardware: ACT LED blinks.
- **M9 Mailbox.** Artifacts: `drivers/mailbox.fth` (embedded via `.incbin` after
  `drivers/gpio.fth`, interpreted at cold) over mailbox 0 at `io-base+0xB880`:
  `mbox-read@ mbox-status@ mbox-write!`, `mbox-full`/`mbox-empty` (STATUS bit31
  full / bit30 empty, computed as `1 31 lshift` / `1 30 lshift` — hex literals
  don't work because BASE is cached per INTERPRET call), `mbox-call`
  (buf -- resp): wait-not-full, write `(buf & ~0xF) | 8`, poll until a channel-8
  message arrives, strip the channel nibble. The buffer must be **16-byte
  aligned** — `create` puts a 20-byte header before the PFA, so
  `create mbox-buf 0 , align16 here mbox-buf ! 128 allot` (variable holding the
  aligned address). `mbox-tag` builds a 32-byte single-tag message
  ([0]=size [1]=0 [2]=tag [3]=8 [4]=0 [5..6]=value [7]=0 end) and returns
  buf+20. Tags (decimal, BASE is cached per line): 65537 board-model,
  65538 board-rev, 65539 mac (8 bytes at buf+20), 65542 vc-mem (base,size —
  `ram-size` = base+size = total RAM), 196614 temp (milli-C; QEMU writes it at
  value+16, real firmware at value+12 — we read buf+20 per spec). Acceptance on
  QEMU raspi0 (`test/all.fth` golden, `make test`): `ram-size h.` ->
  `20000000 ok` (512M), `board-rev h.` -> `00920092 ok`, `mac h. h.` ->
  `0400573412005452 ok` (QEMU default 52:54:00:12:34:5x), `temp 0< 0= .` ->
  `-1 ok` (QEMU writes temp at value+16 so buf+20 reads 0). QEMU's board-model
  tag (65537) is NYI. NOTE: at M9 kernel.img was 15916 B of the 16 KB limit;
  since M12 the timer/GPIO/mailbox drivers load from SD (kernel.img 14180 B / 16 KB).
- **M10 Framebuffer + VDI.** Artifacts: `drivers/fb.fth` (`fb-alloc` via tags
  0x40001, 640x400 1bpp, `fb-off`), `vdi.fth` (`clip! pixel line rect fillrect
  invert-rect blit text`), embedded `font8x16` + `glyph`. Acceptance: `make test-fb`
  draws a known pattern, QMP `screendump` PPM diffed against golden (magic-pixel
  checks).
- **M11 console-fb.** Artifacts: 80x25 grid over the 1 bpp fb, 2 Hz cursor blink via
  M7 timer, `console-fb` vector; same QUERY/accept paths as UART. Acceptance:
  `make test-fb` screendump contains the `ok>` prompt pixels; scripted keys echo on
  the fb console.
- **M12 SD + FAT32.** DONE. Artifacts: `drivers/sd.fth` (Arasan SDHCI +0x300000:
  SWRST/power/CLKCON from CAPAB, CMD0/CMD8/CMD55/ACMD41/CMD2/CMD3/CMD7/CMD16,
  `sd-read` = CMD17 PIO 512 B via BDATA), FAT32 RO in the same file (BPB, FAT chain,
  root-dir 8.3 scan, `fat-find`/`fat-read`/`load-file`/`load`/`file-sum`), cold boot
  runs `sd-boot` (mount + interpret BOOT.LST from a dedicated `boot-buf`), `sd/boot.lst`
  loads TIMER/GPIO/MBOX.FTH, `tools/mksd.py` builds the 32 MB FAT32 test image
  (`build/sd.img`), `make test`/`make test-sd` run QEMU with `--sd build/sd.img`.
  From M12 the kernel embeds only comment-stripped `build/core.fth` + `build/sd.fth`
  (Makefile sed rules); timer/GPIO/mailbox drivers live on the SD card. Acceptance
  (QEMU raspi0): `make test` green (M9 golden, words list extended with sd words),
  `make test-sd` green: `sd-mount .` -> -1, LBA0 55 AA, `file-sum hello.txt .` ->
  5653 and `file-sum boot.lst .` -> 3892 (host-computed), `load hello.txt` + `hi`
  -> hello-from-sd, `load nosuch.txt` -> -? nosuch.txt. No SD card = bare UART
  prompt (sd-mount fails clean). kernel.img 14180 B / 16 KB (was 15916 B at M9).
  Seed fixes this milestone: `allot` and `header_create` keep HERE 4-aligned (odd
  `allot`/`c,` counts corrupted the next header's link -> dictionary cycle);
  `interpret` saves/restores `in_ptr` on a small bss stack so `load` nests.
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

`make test` mechanics: `tools/qemu-ctl.py` starts QEMU with the serial on a unix
socket (`-serial unix:...,server`, wait=on so no boot output is lost; `-serial
stdio` drops output when stdin is a pipe), paces `test/all.fth` line-by-line waiting
for each `ok> ` prompt (the PL011 FIFO is 16 deep — blasting the script drops
bytes), captures the transcript until idle/timeout, terminates QEMU, and diffs
against `test/expected.txt` (trailing whitespace stripped). `make test-fb` adds
a QMP socket and issues `screendump` for pixel diffs; `make test-sd` adds `-sd` with
the image built by `tools/mksd.py`.

Note: on ARM, r13 **is** sp — the Forth return stack and the asm subroutine stack
share it (spec 3.2's r13 = RS). `EXECUTE`'s trampoline therefore saves lr in a
memory cell (`exec_lr`), not on the stack, so `>r`/`r>` inside a word cannot corrupt
it. Forth code must keep the RS balanced within a word (as usual).
