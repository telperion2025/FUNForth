@ src/seed.S - FUNForth seed (M0): entry, vectors, SYS mode, .bss clear,
@ UART0 PL011 diagnostics, boot banner, spin loop.
@ Register allocation (SPEC.md 3.2): r10 IP, r11 W, r13 RS, r4 PS, r5 task,
@ r6 latest, r7 HERE, r8 state, r9 IO-BASE.

    .arm
    .section .text.boot, "ax"
    .global reset
reset:
    @ copy the 8-word vector slab to 0x0000
    mov     r0, #0
    ldr     r1, =vector_slab
    ldmia   r1!, {r2-r9}
    stmia   r0!, {r2-r9}
    @ SYS mode, IRQ+FIQ masked
    msr     cpsr_c, #0xDF
    @ stacks: r13 = RS top (top-of-RAM - 4 KB; M1 computes top from ATAGS),
    @ r4 = PS window (1 KB above dictionary arena), sp = scratch stack
    ldr     r13, =0x08000000 - 0x1000
    ldr     r4,  =0x00080000 + 0x400
    ldr     sp,  =0x00700000
    @ zero .bss
    ldr     r0, =__bss_start
    ldr     r1, =__bss_end
    mov     r2, #0
1:  cmp     r0, r1
    bhs     2f
    str     r2, [r0], #4
    b       1b
2:
    bl      uart_init
    ldr     r0, =banner
    bl      emit_string
3:  b       3b                          @ M0: spin after the banner

    .section .text
    .global vector_slab
vector_slab:
    ldr     pc, =reset                  @ 0x00 reset
    ldr     pc, =reset                  @ 0x04 undefined
    ldr     pc, =reset                  @ 0x08 svc
    ldr     pc, =reset                  @ 0x0C prefetch abort
    ldr     pc, =reset                  @ 0x10 data abort
    nop                                 @ 0x14 reserved
    ldr     pc, =reset                  @ 0x18 irq
    ldr     pc, =reset                  @ 0x1C fiq

@ uart_init ( -- ): PL011 at IO-BASE+0x201000, IO-BASE=0x20000000 (M0: BCM2835
@ fixed; M1 resolves per SoC). 115200 8N1, IBRD=1 FBRD=40 (SPEC.md 8.2).
    .global uart_init
uart_init:
    ldr     r9, =0x20000000             @ IO-BASE
    @ GPIO14/15 -> alt0 (UART0 TXD/RXD)
    add     r0, r9, #0x200000
    ldr     r1, [r0, #0x04]             @ GPFSEL1
    bic     r1, r1, #0x0003F000
    orr     r1, r1, #0x00024000
    str     r1, [r0, #0x04]
    @ pulls off (150-cycle protocol)
    mov     r1, #0
    str     r1, [r0, #0x94]             @ GPPUD
    mov     r1, #150
1:  subs    r1, r1, #1
    bne     1b
    mov     r1, #0
    str     r1, [r0, #0x98]             @ GPPUDCLK0
    @ PL011 setup
    add     r0, r9, #0x200000
    add     r0, r0, #0x1000             @ r0 = UART0 base 0x20201000
    mov     r1, #0
    str     r1, [r0, #0x30]             @ CR: disable
    mov     r1, #1
    str     r1, [r0, #0x24]             @ IBRD
    mov     r1, #40
    str     r1, [r0, #0x28]             @ FBRD
    mov     r1, #0x70
    str     r1, [r0, #0x2C]             @ LCRH: WLEN=8, FEN
    mov     r1, #0
    str     r1, [r0, #0x38]             @ IMSC: no irqs
    mov     r1, #0x300
    orr     r1, r1, #1
    str     r1, [r0, #0x30]             @ CR: UART|TX|RX enable
    bx      lr

@ emit_early ( r3 = char -- ): blocking UART0 emit (M0 diagnostic)
    .global emit_early
emit_early:
    add     r1, r9, #0x200000
    add     r1, r1, #0x1000
    add     r1, r1, #0x18               @ FR
1:  ldr     r2, [r1]
    tst     r2, #0x20                   @ TXFF
    bne     1b
    add     r1, r9, #0x200000
    add     r1, r1, #0x1000             @ DR
    str     r3, [r1]
    bx      lr

@ emit_string ( r0 = asciz -- )
    .global emit_string
emit_string:
    push    {lr}
1:  ldrb    r3, [r0], #1
    cmp     r3, #0
    beq     2f
    bl      emit_early
    b       1b
2:  pop     {pc}

    .section .rodata
    .global banner
banner:
    .asciz  "FUNForth seed 0.1 ok> "
