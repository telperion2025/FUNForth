@ src/seed.S - FUNForth seed (M1): entry, ATAGS walk, SoC detect -> IO-BASE,
@ dictionary, DTC NEXT, seed words, UART console, seed REPL (QUIT).
@
@ Register allocation (SPEC.md 3.2): r10 IP, r11 W, r13 RS, r4 SP (points at the
@ TOS cell, [r4] = TOS), r5 task, r6 latest, r7 HERE, r8 state, r9 IO-BASE.
@ r0-r3, r12 are scratch.
@ Word header (v2.0 refined layout): link(4) | cfa(4) | flags(1) | len(1) |
@ name(len) | pad-to-4. xt = header address; NEXT: ldr r11,[r10],#4;
@ ldr pc,[r11,#4]. Code words end with `b next`.

    .arm
    .section .text.boot, "ax"
    .global reset
reset:
    mov     r12, r2                     @ save ATAGS pointer
    mov     r5, r1                      @ save board revision code
    @ copy the vector slab (8 vectors + 8 literals = 16 words) to 0x0000
    mov     r0, #0
    ldr     r1, =vector_slab
    ldmia   r1!, {r2-r9}
    stmia   r0!, {r2-r9}
    ldmia   r1!, {r2-r9}
    stmia   r0!, {r2-r9}
    @ SYS mode, IRQ+FIQ masked
    msr     cpsr_c, #0xDF
    @ ATAGS walk -> mem size in r0 (default 512 MB)
    mov     r2, r12
    mov     r0, #0x20000000
    cmp     r2, #0
    beq     1f
    ldr     r3, [r2]
    cmp     r3, #0
    beq     1f
atag_walk:
    ldr     r3, [r2, #4]                @ tag
    cmp     r3, #0                      @ ATAG_NONE
    beq     1f
    ldr     r12, =0x54410002
    cmp     r3, r12                     @ ATAG_MEM
    bne     2f
    ldr     r0, [r2, #8]                @ mem size
2:  ldr     r3, [r2]                    @ size in words
    mov     r3, r3, lsl #2
    add     r2, r2, r3
    b       atag_walk
1:  sub     r13, r0, #0x1000            @ RS top = top-of-RAM - 4 KB
    ldr     sp, =0x00700000             @ scratch C stack
    @ SoC detect: probe 2837 mailbox status; data abort or zero -> 2835
    ldr     r0, =abort_flag
    mov     r1, #0
    str     r1, [r0]
    ldr     r1, =0x3F00B898
    ldr     r2, [r1]                    @ may data-abort
    ldr     r0, =abort_flag
    ldr     r3, [r0]
    cmp     r3, #0
    bne     is2835
    cmp     r2, #0
    bne     is2837
    ldr     r0, =abort_flag
    mov     r1, #0
    str     r1, [r0]
    ldr     r1, =0x2000B898
    ldr     r2, [r1]                    @ may data-abort
    ldr     r0, =abort_flag
    ldr     r3, [r0]
    cmp     r3, #0
    bne     is2837
    b       is2835
is2835:
    ldr     r9, =io_base_2835
    ldr     r9, [r9]
    b       soc_done
is2837:
    ldr     r9, =io_base_2837
    ldr     r9, [r9]
soc_done:
    ldr     r0, =board_rev
    str     r5, [r0]
    @ zero .bss
    ldr     r0, =__bss_start
    ldr     r1, =__bss_end
    mov     r2, #0
zb: cmp     r0, r1
    bhs     zb_done
    str     r2, [r0], #4
    b       zb
zb_done:
    b       cold_code

    .section .text
    .global vector_slab
vector_slab:
    .rept 8
    ldr     pc, [pc, #0x18]             @ vectors 0x00-0x1C -> literals at 0x20+
    .endr
    .word   hang, hang, hang, hang, abort_handler, 0, hang, hang

    .global hang
hang:
    b       hang

    .global abort_handler
abort_handler:
    ldr     r0, =abort_flag
    mov     r1, #1
    str     r1, [r0]
    subs    pc, lr, #4                  @ skip faulting instruction

@ NEXT (DTC): r11 = [r10++]; pc = [r11+4]  (cfa cell holds code address)
    .global next
next:
    ldr     r11, [r10], #4
    ldr     pc, [r11, #4]

@ ---------------------------------------------------------------- dictionary
.macro defword label, name, flags=0
    .align 2
    .global \label\()_hdr
\label\()_hdr:
    .word   last_hdr
    .word   \label\()_code
    .byte   \flags
    .byte   9f - 8f
8:  .ascii  "\name"
9:  .align 2
    .set    last_hdr, \label\()_hdr
.endm

    .set    last_hdr, 0

@ ---------------------------------------------------------------- console io
@ emit_char ( r3 = char -- ) : blocking PL011 emit
    .global emit_char
emit_char:
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

@ print_str ( r0 = asciz -- )
    .global print_str
print_str:
    push    {lr}
1:  ldrb    r3, [r0], #1
    cmp     r3, #0
    beq     2f
    bl      emit_char
    b       1b
2:  pop     {pc}

@ key_char ( -- r0 = char ) : blocking PL011 read
    .global key_char
key_char:
    push    {lr}
1:  add     r1, r9, #0x200000
    add     r1, r1, #0x1000
    add     r1, r1, #0x18               @ FR
    ldr     r2, [r1]
    tst     r2, #0x10                   @ RXFE
    bne     1b
    add     r1, r9, #0x200000
    add     r1, r1, #0x1000             @ DR
    ldr     r0, [r1]
    and     r0, r0, #0xFF
    pop     {pc}

@ divmod10 ( r0 = n >= 0 -- r0 = quot, r1 = rem )
    .global divmod10
divmod10:
    mov     r1, #0
1:  cmp     r0, #10
    blo     2f
    sub     r0, r0, #10
    add     r1, r1, #1
    b       1b
2:  mov     r2, r0
    mov     r0, r1
    mov     r1, r2
    bx      lr

@ print_dec ( r0 = signed -- ) : no trailing space
    .global print_dec
print_dec:
    push    {lr}
    ldr     r3, =numbuf + 16
    mov     r1, r0
    cmp     r1, #0
    bge     1f
    mov     r2, #0x2D                   @ '-'
    sub     r3, r3, #1
    strb    r2, [r3]
    neg     r1, r1
1:  mov     r0, r1
    bl      divmod10
    add     r1, r1, #0x30
    sub     r3, r3, #1
    strb    r1, [r3]
    mov     r1, r0
    cmp     r1, #0
    bne     1b
    mov     r0, r3
    bl      print_str
    pop     {pc}

@ print_hex ( r0 -- ) : 8 hex digits; clobbers r0,r3,r12 (+r1,r2 via emit_char)
    .global print_hex
print_hex:
    push    {lr}
    mov     r12, #28
1:  mov     r3, r0, lsr r12
    and     r3, r3, #0xF
    cmp     r3, #10
    addlo   r3, r3, #0x30
    addhs   r3, r3, #0x37
    bl      emit_char
    subs    r12, r12, #4
    bpl     1b
    pop     {pc}

@ uart_init ( -- ) : PL011 at IO-BASE+0x201000, 115200 8N1 (IBRD=1 FBRD=40)
    .global uart_init
uart_init:
    add     r0, r9, #0x200000           @ GPIO
    ldr     r1, [r0, #0x04]             @ GPFSEL1
    bic     r1, r1, #0x0003F000
    orr     r1, r1, #0x00024000         @ GPIO14/15 alt0
    str     r1, [r0, #0x04]
    mov     r1, #0
    str     r1, [r0, #0x94]             @ GPPUD
    mov     r1, #150
1:  subs    r1, r1, #1
    bne     1b
    mov     r1, #0
    str     r1, [r0, #0x98]             @ GPPUDCLK0
    add     r0, r9, #0x200000
    add     r0, r0, #0x1000             @ UART0 base
    mov     r1, #0
    str     r1, [r0, #0x30]             @ CR: disable
    mov     r1, #1
    str     r1, [r0, #0x24]             @ IBRD
    mov     r1, #40
    str     r1, [r0, #0x28]             @ FBRD
    mov     r1, #0x70
    str     r1, [r0, #0x2C]             @ LCRH: WLEN=8, FEN
    mov     r1, #0
    str     r1, [r0, #0x38]             @ IMSC
    mov     r1, #0x300
    orr     r1, r1, #1
    str     r1, [r0, #0x30]             @ CR: UART|TX|RX
    bx      lr

@ ---------------------------------------------------------------- REPL
@ query ( -- ) : read a line into tib with echo + backspace; sets tib_len
    .global query
query:
    push    {lr}
    ldr     r12, =tib
    mov     r5, #0                      @ len
1:  bl      key_char
    cmp     r0, #0x0D
    beq     2f
    cmp     r0, #0x0A
    beq     2f
    cmp     r0, #0x08
    beq     3f
    cmp     r0, #0x7F
    beq     3f
    cmp     r5, #127
    bhs     1b
    strb    r0, [r12, r5]
    add     r5, r5, #1
    mov     r3, r0
    bl      emit_char
    b       1b
3:  cmp     r5, #0
    beq     1b
    sub     r5, r5, #1
    mov     r3, #8
    bl      emit_char
    mov     r3, #32
    bl      emit_char
    mov     r3, #8
    bl      emit_char
    b       1b
2:  mov     r3, #13
    bl      emit_char
    mov     r3, #10
    bl      emit_char
    mov     r0, #0
    strb    r0, [r12, r5]
    ldr     r0, =tib_len
    str     r5, [r0]
    pop     {pc}

@ number? ( r0 = token -- r0 = value, r1 = valid )
    .global number_q
number_q:
    push    {lr}
    ldrb    r2, [r0]
    mov     r3, #0                      @ sign
    cmp     r2, #0x2D                   @ '-'
    bne     1f
    mov     r3, #1
    add     r0, r0, #1
1:  mov     r2, #0                      @ acc
    mov     r1, #0                      @ valid
2:  ldrb    r12, [r0]
    cmp     r12, #0x30
    blo     3f
    cmp     r12, #0x39
    bhi     3f
    sub     r12, r12, #0x30
    mov     r1, r2, lsl #3
    add     r1, r1, r2, lsl #1          @ acc*10
    add     r2, r1, r12
    mov     r1, #1
    add     r0, r0, #1
    b       2b
3:  cmp     r1, #1
    bne     4f
    cmp     r3, #1
    rsbeq   r2, r2, #0
    mov     r0, r2
    pop     {pc}
4:  mov     r1, #0
    mov     r0, #0
    pop     {pc}

@ find ( r0 = token, r1 = len -- r0 = xt | 0 ) ; preserves r5, r8.
@ r3 holds len for the whole walk (never clobbered by memcmp).
    .global find
find:
    push    {r5, r8, lr}
    mov     r2, r0                      @ token
    mov     r3, r1                      @ len
    mov     r12, r6                     @ h = latest
1:  cmp     r12, #0
    beq     8f
    ldrb    r1, [r12, #9]               @ hdr len
    cmp     r1, r3
    bne     7f
    add     r0, r12, #10                @ name
    mov     r5, #0                      @ i  (r2 = token, r3 = len, both kept)
2:  cmp     r5, r3
    bhs     3f
    ldrb    r1, [r0, r5]
    ldrb    r8, [r2, r5]
    cmp     r1, r8
    bne     7f
    add     r5, r5, #1
    b       2b
3:  mov     r0, r12
    pop     {r5, r8, pc}
7:  ldr     r12, [r12]                  @ link
    b       1b
8:  mov     r0, #0
    pop     {r5, r8, pc}

@ execute_xt ( r0 = xt -- ) : run a code word via NEXT + trampoline.
@ The return address is saved on the scratch stack (words clobber lr via bl);
@ the word ends with `b next`, which lands in tramp_code: pop {pc}.
    .global execute_xt
execute_xt:
    ldr     r12, [r0, #4]               @ code address
    push    {lr}
    ldr     r10, =exec_cell
    ldr     r11, =tramp_hdr
    str     r11, [r10]
    blx     r12
    pop     {pc}

@ interpret ( -- ) : interpret tib; r5 = cursor, r8 = token end (both preserved
@ by callees). Unknown word: print "-? <tok>" and abort the line. `\` skips line.
    .global interpret
interpret:
    push    {lr}
    ldr     r5, =tib                    @ cursor
iloop:
    ldrb    r1, [r5]
    cmp     r1, #0
    beq     idone
    cmp     r1, #0x20
    beq     iadv
    cmp     r1, #9
    beq     iadv
    b       itok
iadv:
    add     r5, r5, #1
    b       iloop
itok:
    mov     r8, r5                      @ token end
1:  ldrb    r1, [r8]
    cmp     r1, #0
    beq     2f
    cmp     r1, #0x20
    beq     2f
    cmp     r1, #9
    beq     2f
    add     r8, r8, #1
    b       1b
2:  ldrb    r1, [r5]
    cmp     r1, #0x5C                  @ '\' comment: skip rest of line
    beq     idone
    mov     r0, r5
    sub     r1, r8, r5
    bl      number_q
    cmp     r1, #1
    beq     ipush
    mov     r0, r5
    sub     r1, r8, r5
    bl      find
    cmp     r0, #0
    bne     iexec
    ldr     r0, =str_err                @ "-? "
    bl      print_str
    mov     r0, r5
    sub     r8, r8, r5                  @ len
3:  ldrb    r3, [r0], #1
    bl      emit_char
    subs    r8, r8, #1
    bne     3b
    b       idone
iexec:
    bl      execute_xt
    mov     r5, r8
    b       iloop
ipush:
    sub     r4, r4, #4
    str     r0, [r4]
    mov     r5, r8
    b       iloop
idone:
    pop     {pc}

@ ---------------------------------------------------------------- seed words
@ Stack convention: r4 = SP, points at the TOS cell ([r4] = TOS); r0-r3, r12 scratch.
defword dup, "dup"
dup_code:
    ldr     r0, [r4]
    sub     r4, r4, #4
    str     r0, [r4]
    b       next

defword drop, "drop"
drop_code:
    add     r4, r4, #4
    b       next

defword swap, "swap"
swap_code:
    ldr     r0, [r4]
    ldr     r1, [r4, #4]
    str     r0, [r4, #4]
    str     r1, [r4]
    b       next

defword over, "over"
over_code:
    ldr     r0, [r4, #4]
    sub     r4, r4, #4
    str     r0, [r4]
    b       next

defword depth, "depth"
depth_code:
    ldr     r1, =ps0
    ldr     r1, [r1]
    sub     r1, r1, r4
    lsr     r1, r1, #2
    sub     r4, r4, #4
    str     r1, [r4]
    b       next

defword plus, "+"
plus_code:
    ldr     r0, [r4]
    ldr     r1, [r4, #4]
    add     r0, r1, r0
    add     r4, r4, #4
    str     r0, [r4]
    b       next

defword dot, "."
dot_code:
    ldr     r0, [r4]
    bl      print_dec
    add     r4, r4, #4
    b       next

defword hdot, "h."
hdot_code:
    ldr     r0, [r4]
    bl      print_hex
    add     r4, r4, #4
    b       next

defword emit, "emit"
emit_code:
    ldr     r3, [r4]
    add     r4, r4, #4
    bl      emit_char
    b       next

defword key, "key"
key_code:
    bl      key_char
    sub     r4, r4, #4
    str     r0, [r4]
    b       next

defword keyq, "key?"
keyq_code:
    add     r1, r9, #0x200000
    add     r1, r1, #0x1000
    add     r1, r1, #0x18               @ FR
    ldr     r2, [r1]
    tst     r2, #0x10                   @ RXFE
    movne   r1, #0
    moveq   r1, #1
    sub     r4, r4, #4
    str     r1, [r4]
    b       next

defword cr, "cr"
cr_code:
    mov     r3, #13
    bl      emit_char
    mov     r3, #10
    bl      emit_char
    b       next

defword space, "space"
space_code:
    mov     r3, #32
    bl      emit_char
    b       next

defword io_base, "io-base"
io_base_code:
    sub     r4, r4, #4
    str     r9, [r4]
    b       next

defword latest, "latest"
latest_code:
    sub     r4, r4, #4
    str     r6, [r4]
    b       next

defword here, "here"
here_code:
    sub     r4, r4, #4
    str     r7, [r4]
    b       next

defword cold, "cold"
cold_code:
    ldr     r6, =seed_latest
    ldr     r7, =__bss_end
    add     r7, r7, #3
    bic     r7, r7, #3                  @ forth_start = align4(end of .bss)
    add     r1, r7, #0x100000           @ PS0 = FORTH-START + 1 MB
    ldr     r2, =ps0
    str     r1, [r2]
    mov     r4, r1
    bl      uart_init
    ldr     r0, =banner
    bl      print_str
    b       quit_code

defword warm, "warm"
warm_code:
    b       quit_code

defword bye, "bye"
bye_code:
    b       bye_code

defword quit, "quit"
quit_code:
qloop:
    ldr     r0, =str_prompt             @ "ok> "
    bl      print_str
    bl      query
    bl      interpret
    ldr     r0, =str_ok                 @ " ok\r\n"
    bl      print_str
    b       qloop

defword tramp, "tramp"
tramp_code:
    pop     {pc}

    .set    seed_latest, last_hdr
    .global seed_latest

    .section .rodata
    .global banner
banner:     .asciz  "FUNForth seed 0.1 "
str_prompt: .asciz  "ok> "
str_ok:     .asciz  " ok\r\n"
str_err:    .asciz  "-? "

    .section .bss
    .align 2
    .global tib
tib:        .space  132
    .global tib_len
tib_len:    .space  4
    .global numbuf
numbuf:     .space  16
    .global abort_flag
abort_flag: .space  4
    .global board_rev
board_rev:  .space  4
    .global ps0
ps0:        .space  4
    .global exec_cell
exec_cell:  .space  4
