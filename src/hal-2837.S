@ src/hal-2837.S - BCM2837 (Pi 3A+/3B) board variant slab.
@ M0 stub; M1 adds peripheral-base resolution, alt GPIO pull offsets, and
@ parking of cores 1-3 until M22 (SMP).
    .arm
    .section .rodata
    .global hal_name_2837
hal_name_2837:
    .asciz  "bcm2837"
