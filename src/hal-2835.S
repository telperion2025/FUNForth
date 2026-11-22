@ src/hal-2835.S - BCM2835 (Pi Zero/Zero W) board variant slab.
@ M0 stub; M1 adds peripheral-base resolution and the 2835 GPPUD pull protocol.
    .arm
    .section .rodata
    .global hal_name_2835
hal_name_2835:
    .asciz  "bcm2835"
