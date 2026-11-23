@ src/hal-2835.S - BCM2835 (Pi Zero/Zero W) board variant slab.
    .arm
    .section .rodata
    .align 2
    .global io_base_2835
io_base_2835:
    .word   0x20000000
    .global hal_name_2835
hal_name_2835:
    .asciz  "bcm2835"
