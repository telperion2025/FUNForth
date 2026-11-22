# boot/

Firmware blobs are **not committed** (licensing). Copy them from the boot
partition of any Raspberry Pi OS SD card into this directory:

- `bootcode.bin`
- `start.elf`
- `config.txt` — use the one at the repository root (`arm_64bit=0`,
  `gpu_mem=16`, `disable_commandline_tags=0` so the ATAGS/DTB pointer stays in
  r2 at entry).

`kernel.img` (built by `make`) goes next to them on the card.
