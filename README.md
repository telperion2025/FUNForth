# FUNForth

A Forth operating system for Raspberry Pi Zero/Zero W (BCM2835) and Pi 3A+/3B
(BCM2837): one `kernel.img`, ARM assembly seed + FUNForth source, no C, QEMU-first
dev loop.

- **[SPEC.md](SPEC.md)** — the implementation specification v2.0, divided into
  milestones M0–M25 (one milestone = one branch = one PR, each with an automated
  `make test` acceptance). It supersedes the original PDF spec where they differ.
- `make` builds `kernel.img`; `make run` boots it under QEMU (`-M raspi0`);
  `make test` runs the golden-transcript test suite.
