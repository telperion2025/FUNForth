\ ---- M25: user manual (as FORTH comments) + help words ----
\ FUNForth v2.0 quick manual:
\   boot: kernel.img on the SD card boots to the "ok> " prompt (UART + fb console).
\   core:  arithmetic/stack/memory words; `: name ... ;` defines; `see name` decompiles;
\          `words` lists; numbers in BASE (default 10); `.` prints signed, `h.` hex.
\   console: console-uart (default), console-fb (80x25 on the framebuffer), console-oled.
\   tasks:  `n task: name` allocates, `spawn`/`wake`/`kill`/`halt`, `pause` yields,
\           `preemptible` + 1 kHz tick preempts (M13/M14); `tasks` lists.
\   asm:    `code name ... end-code` assembles ARMv6 (M15/M16); `see` disassembles.
\   wm/gui: `win-new win-open win-close`, drag with 'd'/arrows/CR, TAB focus,
\           `button` registers clickable rects, `ev-push` injects synthetic events (M17-M19).
\   drivers: timer (micros millis ms tick-start), gpio (pin-mode pin! pin@ pin-pull led!),
\           mbox, sd+load, fb+vdi, i2c/ssd1306/rtc (M20), usbhid (M21), smp (M22),
\           irq-on/irq-enable/irqs@/pat (M23), mmu-on/save-image (M24).
\   help:   `help` prints the topic list.
: help ( -- )
  ." FUNForth v2.0 topics: core console tasks asm wm term gui hello drivers irq mmu" cr
  ." see <word> decompiles a word; words lists the dictionary; ' <word> pushes its xt." cr ;
