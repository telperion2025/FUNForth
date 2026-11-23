@ src/hal-2837.S - BCM2837 (Pi 3A+/3B) board variant slab.
    .arm
    .section .rodata
    .align 2
    .global io_base_2837
io_base_2837:
    .word   0x3F000000
    .global hal_name_2837
hal_name_2837:
    .asciz  "bcm2837"
