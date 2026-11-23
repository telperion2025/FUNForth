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
1:  sub     r13, r0, #0x1000            @ r13 = sp = top-of-RAM - 4 KB (shared:
    @ Forth return stack and asm subroutine stack are the same ARM sp)
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
    .ltorg

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

    .ltorg

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

@ print_dec ( r0 = signed -- ) : no trailing space; sign emitted directly
    .global print_dec
print_dec:
    push    {lr}
    mov     r12, r0                     @ value; survives emit_char/divmod10
    cmp     r12, #0
    bge     1f
    mov     r3, #0x2D                   @ '-'
    bl      emit_char
    neg     r12, r12
1:  ldr     r3, =numbuf + 16
2:  mov     r0, r12
    bl      divmod10
    add     r1, r1, #0x30
    sub     r3, r3, #1
    strb    r1, [r3]
    mov     r12, r0
    cmp     r12, #0
    bne     2b
    mov     r0, r3
    bl      print_str
    pop     {pc}
    .ltorg

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
    .ltorg

@ print_base ( r0 = unsigned n, r1 = base -- ) : digits 0-9 A-Z, no trailing space
    .global print_base
print_base:
    push    {lr}
    sub     sp, sp, #8
    str     r1, [sp]                    @ base
    ldr     r3, =numbuf + 16
    str     r3, [sp, #4]                @ digit ptr (grows down from numbuf+16)
1:  ldr     r1, [sp]
    bl      udivmod                     @ r0 = quot, r1 = rem (clobbers r2,r3,r12)
    ldr     r3, [sp, #4]
    cmp     r1, #10
    addlo   r1, r1, #0x30
    addhs   r1, r1, #0x37               @ A-Z
    sub     r3, r3, #1
    strb    r1, [r3]
    str     r3, [sp, #4]
    cmp     r0, #0
    bne     1b
    ldr     r0, [sp, #4]
    bl      print_str
    add     sp, sp, #8
    pop     {pc}
    .ltorg

@ udivmod ( r0 = n, r1 = d -- r0 = quot, r1 = rem ) : unsigned, bit-by-bit
@ (ARMv6 has no udiv). Clobbers r2, r3, r12.
    .global udivmod
udivmod:
    mov     r2, #0                      @ quot
    mov     r3, #0                      @ rem
    mov     r12, #32
1:  lsls    r0, r0, #1
    adc     r3, r3, r3                  @ rem = rem*2 + carry-out of n
    cmp     r3, r1
    subhs   r3, r3, r1
    adc     r2, r2, r2
    subs    r12, r12, #1
    bne     1b
    mov     r0, r2
    mov     r1, r3
    bx      lr

@ sdivmod ( r0 = a, r1 = b -- r0 = quot, r1 = rem ) : signed, trunc toward zero,
@ rem takes the sign of a. Clobbers r2, r3, r12.
    .global sdivmod
sdivmod:
    push    {lr}
    mov     r2, #0                      @ asign
    cmp     r0, #0
    bge     1f
    neg     r0, r0
    mov     r2, #1
1:  mov     r3, r2                      @ qsign = asign
    cmp     r1, #0
    bge     2f
    neg     r1, r1
    eor     r3, r3, #1                  @ qsign ^= bsign
2:  push    {r2, r3}
    bl      udivmod
    pop     {r2, r3}
    cmp     r3, #1
    rsbeq   r0, r0, #0
    cmp     r2, #1
    rsbeq   r1, r1, #0
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
    .ltorg

@ ---------------------------------------------------------------- REPL
@ query ( -- ) : read a line into tib with echo + backspace; sets tib_len
    .global query
query:
    push    {lr}
    ldr     r12, =tib
    mov     r5, #0                      @ len
    ldr     r0, =hist_view
    mov     r1, #0xFF
    str     r1, [r0]                    @ not recalling
qln:
    bl      key_vec
    ldr     r12, =tib                  @ key_vec/execute_xt clobber r12: reload
    cmp     r0, #0x0D
    beq     qdonel
    cmp     r0, #0x0A
    beq     qdonel
    cmp     r0, #0x08
    beq     qbsl
    cmp     r0, #0x7F
    beq     qbsl
    cmp     r0, #0x1B                   @ ESC: arrow-key history recall
    beq     qescl
    cmp     r5, #127
    bhs     qln
    strb    r0, [r12, r5]
    add     r5, r5, #1
    mov     r3, r0
    bl      emit_vec
    b       qln
qbsl:
    cmp     r5, #0
    beq     qln
    sub     r5, r5, #1
    mov     r3, #8
    bl      emit_vec
    mov     r3, #32
    bl      emit_vec
    mov     r3, #8
    bl      emit_vec
    b       qln
qescl:
    bl      key_vec
    cmp     r0, #0x5B                   @ '['
    bne     qln
    bl      key_vec
    cmp     r0, #0x41                   @ 'A' = up (older)
    beq     qupl
    cmp     r0, #0x42                   @ 'B' = down (newer)
    beq     qdownl
    b       qln
qupl:
    ldr     r0, =hist_cnt
    ldr     r0, [r0]
    cmp     r0, #0
    beq     qln
    ldr     r0, =hist_view
    ldr     r1, [r0]
    cmp     r1, #0xFF
    bne     qup2l
    ldr     r2, =hist_idx
    ldr     r2, [r2]
    add     r1, r2, #7
    and     r1, r1, #7                  @ most recent = idx-1 mod 8
    b       qup3l
qup2l:
    ldr     r2, =hist_idx
    ldr     r2, [r2]
    ldr     r3, =hist_cnt
    ldr     r3, [r3]
    sub     r2, r2, r3
    add     r2, r2, #8
    and     r2, r2, #7                  @ oldest
    cmp     r1, r2
    beq     qredrawl
    add     r1, r1, #7
    and     r1, r1, #7
qup3l:
    ldr     r0, =hist_view
    str     r1, [r0]
    b       qredrawl
qdownl:
    ldr     r0, =hist_view
    ldr     r1, [r0]
    cmp     r1, #0xFF
    beq     qln
    ldr     r2, =hist_idx
    ldr     r2, [r2]
    add     r1, r1, #1
    and     r1, r1, #7
    cmp     r1, r2
    mov     r3, #0xFF
    moveq   r1, r3                      @ past newest: back to fresh line
    str     r1, [r0]
qredrawl:
    cmp     r5, #0
    beq     qrd2l
    mov     r3, #8
    bl      emit_vec
    mov     r3, #32
    bl      emit_vec
    mov     r3, #8
    bl      emit_vec
    sub     r5, r5, #1
    b       qredrawl
qrd2l:
    ldr     r0, =hist_view
    ldr     r1, [r0]
    cmp     r1, #0xFF
    beq     qln
    ldr     r2, =hist
    mov     r3, #132
    mul     r3, r1, r3
    add     r2, r2, r3                  @ src = hist + view*132
    mov     r5, #0
qrd3l:
    ldr     r12, =tib
    ldr     r0, =hist_view                @ recompute src every iteration:
    ldr     r1, [r0]                    @ emit_vec clobbers r0-r3, r10-r12
    ldr     r2, =hist
    mov     r3, #132
    mul     r3, r1, r3
    add     r2, r2, r3
    ldrb    r0, [r2, r5]
    cmp     r0, #0
    beq     qln
    strb    r0, [r12, r5]
    add     r5, r5, #1
    mov     r3, r0
    bl      emit_vec
    b       qrd3l
qdonel:
    mov     r3, #13
    bl      emit_vec
    mov     r3, #10
    bl      emit_vec
    ldr     r12, =tib
    mov     r0, #0
    strb    r0, [r12, r5]
    cmp     r5, #0                      @ store non-empty line in history ring
    beq     qnstorel
    ldr     r0, =hist_idx
    ldr     r1, [r0]
    ldr     r2, =hist
    mov     r3, #132
    mul     r3, r1, r3
    add     r2, r2, r3                  @ dest = hist + idx*132
    mov     r3, #0
qcopyl:
    ldrb    r0, [r12, r3]
    strb    r0, [r2, r3]
    cmp     r0, #0
    add     r3, r3, #1
    bne     qcopyl
    ldr     r0, =hist_idx
    ldr     r1, [r0]
    add     r1, r1, #1
    and     r1, r1, #7
    str     r1, [r0]
    ldr     r0, =hist_cnt
    ldr     r1, [r0]
    cmp     r1, #8
    bhs     qnstorel
    add     r1, r1, #1
    str     r1, [r0]
qnstorel:
    ldr     r0, =tib_len
    str     r5, [r0]
    pop     {pc}
    .ltorg

@ number_q ( r0 = token, r1 = len -- r0 = value, r1 = 1 valid / 0 invalid )
@ Valid iff the token is an optional '-' followed by >=1 digits, nothing else.
    .global number_q
number_q:
    push    {lr}
    sub     sp, sp, #8
    str     r0, [sp]                    @ start
    mov     r3, r1                      @ len
    mov     r1, #0                      @ sign
    ldrb    r12, [r0]
    cmp     r12, #0x2D                  @ '-'
    bne     1f
    mov     r1, #1
    add     r0, r0, #1
1:  str     r1, [sp, #4]                @ sign
    mov     r2, #0                      @ acc
2:  ldrb    r1, [r0]
    cmp     r1, #0x30
    blo     3f
    cmp     r1, #0x39
    bhi     3f
    sub     r1, r1, #0x30
    mov     r12, r2, lsl #3
    add     r12, r12, r2, lsl #1        @ acc*10
    add     r2, r12, r1
    add     r0, r0, #1
    b       2b
3:  ldr     r12, [sp]
    sub     r0, r0, r12                 @ consumed chars
    cmp     r0, r3
    bne     4f                          @ must consume the whole token
    ldr     r1, [sp, #4]
    sub     r0, r0, r1                  @ minus sign is not a digit
    cmp     r0, #0
    ble     4f
    cmp     r1, #1
    rsbeq   r2, r2, #0
    mov     r0, r2
    mov     r1, #1
    add     sp, sp, #8
    pop     {pc}
4:  mov     r0, #0
    mov     r1, #0
    add     sp, sp, #8
    pop     {pc}
    .ltorg

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
    .ltorg

@ execute_xt ( r0 = xt -- ) : run a code word via NEXT + trampoline.
@ lr is saved in a memory cell (sp/r13 is shared with the Forth return stack,
@ so the trampoline must not use it); the word ends with `b next`, which lands
@ in tramp_code, returning through exec_lr.
    .global execute_xt
execute_xt:
    @ save IP+lr on a memory stack (r13 is shared with the Forth return stack,
    @ so the trampoline state must NOT live on r13); nestable via exec_idx
    ldr     r12, =exec_idx
    ldr     r11, [r12]
    ldr     r3, =exec_stack
    add     r3, r3, r11, lsl #3
    str     r10, [r3]                   @ save IP
    str     lr, [r3, #4]                @ save lr
    add     r11, r11, #1
    str     r11, [r12]
    ldr     r12, [r0, #4]               @ code address
    ldr     r10, =exec_cell
    ldr     r11, =tramp_hdr
    str     r11, [r10]
    mov     r11, r0                     @ W = xt (NEXT sets W before jumping to cfa)
    blx     r12
    bx      lr
    .ltorg

@ emit_vec ( r3 = char -- ) : emit via the current console emit vector (on stack)
    .global emit_vec
emit_vec:
    push    {lr}
    sub     r4, r4, #4
    str     r3, [r4]
    ldr     r0, =con_emit
    ldr     r0, [r0]
    bl      execute_xt
    pop     {pc}
    .ltorg

@ key_vec ( -- r0 = char ) : blocking key via the current console key vector
    .global key_vec
key_vec:
    push    {lr}
    ldr     r0, =con_key
    ldr     r0, [r0]
    bl      execute_xt
    ldr     r0, [r4], #4
    pop     {pc}
    .ltorg

@ interpret ( r0 = buffer -- ) : interpret NUL-terminated buffer. r5 = cursor,
@ reloaded from in_ptr after each word so that : / ." can advance it. r8 = state
@ (0 interpreting, 1 compiling) — preserved by callees, set by : and ;.
@ In compile mode: numbers compile as lit <n>; non-immediate words append their
@ xt; immediate words execute. Unknown word: print "-? <tok>", reset state, abort.
@ '\' skips to end of line. \n \r are whitespace.
@ err_impl : reset compile state after an error (used by INTERPRET and err)
    .global err_impl
err_impl:
    mov     r8, #0
    ldr     r0, =state_v
    str     r8, [r0]
    bx      lr

    .global interpret
interpret:
    push    {lr}
    mov     r5, r0
    ldr     r0, =in_ptr
    str     r5, [r0]
    ldr     r8, =state_v                @ STATE lives in memory so state ! works
    ldr     r8, [r8]
iloop:
    ldrb    r1, [r5]
    cmp     r1, #0
    beq     idone
    cmp     r1, #0x20
    beq     iadv
    cmp     r1, #9
    beq     iadv
    cmp     r1, #0x0A
    beq     iadv
    cmp     r1, #0x0D
    beq     iadv
    b       itok
iadv:
    add     r5, r5, #1
    b       iloop
itok:
    mov     r3, r5                      @ scan token end
1:  ldrb    r1, [r3]
    cmp     r1, #0
    beq     2f
    cmp     r1, #0x20
    beq     2f
    cmp     r1, #9
    beq     2f
    cmp     r1, #0x0A
    beq     2f
    cmp     r1, #0x0D
    beq     2f
    add     r3, r3, #1
    b       1b
2:  ldr     r0, =in_ptr
    str     r3, [r0]                    @ in_ptr = token end
    ldrb    r1, [r5]
    cmp     r1, #0x5C                   @ '\' comment: skip to newline
    bne     3f
4:  ldrb    r1, [r5]
    cmp     r1, #0
    beq     idone
    cmp     r1, #0x0A
    beq     iadv
    add     r5, r5, #1
    b       4b
3:  mov     r0, r5
    sub     r1, r3, r5
    bl      number_q
    cmp     r1, #1
    beq     inum
    mov     r0, r5
    ldr     r3, =in_ptr
    ldr     r3, [r3]                    @ token end (number_q clobbers r3)
    sub     r1, r3, r5
    bl      find
    cmp     r0, #0
    bne     ifound
    bl      err_impl
    ldr     r0, =str_err                @ "-? "
    bl      print_str
    mov     r0, r5
    ldr     r1, =in_ptr
    ldr     r1, [r1]
    sub     r1, r1, r5
    mov     r12, r1
5:  ldrb    r3, [r0], #1
    bl      emit_char
    subs    r12, r12, #1
    bne     5b
    b       idone
ifound:
    ldrb    r2, [r0, #8]                @ flags
    cmp     r8, #0                      @ state?
    beq     iexec
    tst     r2, #1                      @ immediate?
    bne     iexec
    add     r7, r7, #3                  @ compile xt
    bic     r7, r7, #3
    str     r0, [r7], #4
    b       idonext
iexec:
    bl      execute_xt
    b       idonext
inum:
    cmp     r8, #0
    bne     inumc
    sub     r4, r4, #4
    str     r0, [r4]
    b       idonext
inumc:
    add     r7, r7, #3                  @ compile lit <n>
    bic     r7, r7, #3
    ldr     r1, =lit_hdr
    str     r1, [r7], #4
    str     r0, [r7], #4
idonext:
    ldr     r0, =in_ptr
    ldr     r5, [r0]
    ldr     r8, =state_v
    ldr     r8, [r8]
    b       iloop
idone:
    pop     {pc}
    .ltorg

@ parse_name ( -- r0 = wordbuf, r1 = len ) : skip spaces at in_ptr, copy next
@ token to wordbuf (NUL-terminated), advance in_ptr past the token.
    .global parse_name
parse_name:
    push    {lr}
    ldr     r2, =in_ptr
    ldr     r3, [r2]                    @ cursor
1:  ldrb    r0, [r3]
    cmp     r0, #0
    beq     pn_done
    cmp     r0, #0x20
    beq     pn_adv
    cmp     r0, #9
    beq     pn_adv
    cmp     r0, #0x0A
    beq     pn_done
    cmp     r0, #0x0D
    beq     pn_done
    b       pn_tok
pn_adv:
    add     r3, r3, #1
    b       1b
pn_tok:
    ldr     r0, =wordbuf
pn_copy:
    ldrb    r12, [r3]
    cmp     r12, #0
    beq     pn_end
    cmp     r12, #0x20
    beq     pn_end
    cmp     r12, #9
    beq     pn_end
    cmp     r12, #0x0A
    beq     pn_end
    cmp     r12, #0x0D
    beq     pn_end
    strb    r12, [r0], #1
    add     r3, r3, #1
    b       pn_copy
pn_end:
    mov     r12, #0
    strb    r12, [r0]
    str     r3, [r2]                    @ in_ptr = delimiter position
    ldr     r1, =wordbuf
    sub     r1, r0, r1                  @ r1 = len
    ldr     r0, =wordbuf                @ r0 = wordbuf
    pop     {pc}
pn_done:
    ldr     r0, =wordbuf
    mov     r12, #0
    strb    r12, [r0]
    mov     r1, #0
    pop     {pc}
    .ltorg

@ docol : colon-definition entry (cfa target). r11 = xt. Push IP, set IP = PFA.
    .global docol
docol:
    sub     r13, r13, #4
    str     r10, [r13]
    ldrb    r1, [r11, #9]               @ len
    add     r10, r11, #10
    add     r10, r10, r1
    add     r10, r10, #3
    bic     r10, r10, #3                @ pfa = align4(hdr + 10 + len)
    b       next

@ docon : CREATE entry: push PFA address.
    .global docon
docon:
    ldrb    r1, [r11, #9]
    add     r0, r11, #10
    add     r0, r0, r1
    add     r0, r0, #3
    bic     r0, r0, #3
    sub     r4, r4, #4
    str     r0, [r4]
    b       next
    .ltorg

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

defword dot, "."                        @ ( n -- ) signed, in BASE
dot_code:
    ldr     r0, [r4], #4
    cmp     r0, #0
    bge     1f
    push    {r0}
    mov     r3, #0x2D                   @ '-'
    bl      emit_vec
    pop     {r0}
    neg     r0, r0
1:  ldr     r1, =base_v
    ldr     r1, [r1]
    bl      print_base
    b       next

defword udot, "u."                      @ ( n -- ) unsigned, in BASE
udot_code:
    ldr     r0, [r4], #4
    ldr     r1, =base_v
    ldr     r1, [r1]
    bl      print_base
    b       next

defword hdot, "h."
hdot_code:
    ldr     r0, [r4]
    bl      print_hex
    add     r4, r4, #4
    b       next

defword base_w, "base"                  @ ( -- addr ) BASE variable
base_w_code:
    ldr     r0, =base_v
    sub     r4, r4, #4
    str     r0, [r4]
    b       next

defword span_w, "span"                  @ ( -- addr ) SPAN variable (last accept len)
span_w_code:
    ldr     r0, =span_v
    sub     r4, r4, #4
    str     r0, [r4]
    b       next

defword emit, "emit"                    @ ( c -- ) via console emit vector
emit_code:
    ldr     r0, =con_emit
    ldr     r0, [r0]
    bl      execute_xt
    b       next

defword emit_uart, "emit-uart"          @ ( c -- ) PL011 emit (console-uart target)
emit_uart_code:
    ldr     r3, [r4], #4
    bl      emit_char
    b       next

defword key, "key"                      @ ( -- c ) via console key vector
key_code:
    ldr     r0, =con_key
    ldr     r0, [r0]
    bl      execute_xt
    b       next

defword key_uart, "key-uart"            @ ( -- c ) PL011 blocking read
key_uart_code:
    bl      key_char
    sub     r4, r4, #4
    str     r0, [r4]
    b       next

defword keyq, "key?"                    @ ( -- flag ) via console key? vector
keyq_code:
    ldr     r0, =con_keyq
    ldr     r0, [r0]
    bl      execute_xt
    b       next

defword keyq_uart, "key?-uart"          @ ( -- flag ) PL011 RX-empty?
keyq_uart_code:
    add     r1, r9, #0x200000
    add     r1, r1, #0x1000
    add     r1, r1, #0x18               @ FR
    ldr     r2, [r1]
    tst     r2, #0x10                   @ RXFE
    movne   r0, #0
    moveq   r0, #1
    sub     r4, r4, #4
    str     r0, [r4]
    b       next

defword cr, "cr"
cr_code:
    mov     r3, #13
    bl      emit_vec
    mov     r3, #10
    bl      emit_vec
    b       next

defword space, "space"
space_code:
    mov     r3, #32
    bl      emit_vec
    b       next

defword type_w, "type"                  @ ( addr len -- ) print len chars via vector
type_w_code:
    ldr     r1, [r4], #4                @ len
    ldr     r0, [r4], #4                @ addr
1:  cmp     r1, #0
    beq     2f
    push    {r0, r1}
    ldrb    r3, [r0]
    bl      emit_vec
    pop     {r0, r1}
    add     r0, r0, #1
    sub     r1, r1, #1
    b       1b
2:  b       next

defword accept, "accept"                @ ( addr len -- n ) line into addr, echo, -> SPAN
accept_code:
    ldr     r1, [r4], #4                @ max
    ldr     r0, [r4], #4                @ buf
    push    {r5}
    mov     r5, r0                      @ buf
    sub     r4, r4, #8                  @ scratch on data stack (key_vec/emit_vec
    str     r1, [r4]                    @ clobber r0-r3,r10-r12): [sp]=max [sp+4]=cnt
    mov     r0, #0
    str     r0, [r4, #4]
1:  bl      key_vec
    cmp     r0, #0x0D
    beq     2f
    cmp     r0, #0x0A
    beq     2f
    cmp     r0, #0x08
    beq     3f
    cmp     r0, #0x7F
    beq     3f
    ldr     r1, [r4]                    @ max
    ldr     r2, [r4, #4]                @ count
    cmp     r2, r1
    bhs     1b
    strb    r0, [r5, r2]
    add     r2, r2, #1
    str     r2, [r4, #4]
    mov     r3, r0
    bl      emit_vec
    b       1b
3:  ldr     r2, [r4, #4]
    cmp     r2, #0
    beq     1b
    sub     r2, r2, #1
    str     r2, [r4, #4]
    mov     r3, #8
    bl      emit_vec
    mov     r3, #32
    bl      emit_vec
    mov     r3, #8
    bl      emit_vec
    b       1b
2:  mov     r3, #13
    bl      emit_vec
    mov     r3, #10
    bl      emit_vec
    ldr     r2, [r4, #4]
    ldr     r0, =span_v
    str     r2, [r0]
    add     r4, r4, #8
    sub     r4, r4, #4
    str     r2, [r4]
    pop     {r5}
    b       next

defword expect, "expect"                @ ( addr len -- n ) same as accept
expect_code:
    b       accept_code

defword err, "err"                      @ ( -- ) reset compile state after error
err_code:
    bl      err_impl
    b       next

@ console_uart_impl : point console vectors at the UART primitives
    .global console_uart_impl
console_uart_impl:
    ldr     r0, =emit_uart_hdr
    ldr     r1, =con_emit
    str     r0, [r1]
    ldr     r0, =key_uart_hdr
    ldr     r1, =con_key
    str     r0, [r1]
    ldr     r0, =keyq_uart_hdr
    ldr     r1, =con_keyq
    str     r0, [r1]
    bx      lr

defword console_uart, "console-uart"    @ ( -- ) select UART console
console_uart_code:
    bl      console_uart_impl
    b       next
    .ltorg

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
    mov     r8, #0                      @ state = interpreting
    bl      console_uart_impl           @ console vectors -> UART
    ldr     r0, =base_v
    mov     r1, #10
    str     r1, [r0]                    @ BASE = 10
    ldr     r0, =hist_view
    mov     r1, #0xFF
    str     r1, [r0]                    @ history recall view = none
    bl      uart_init
    ldr     r0, =banner
    bl      print_str
    ldr     r0, =core_fth
    bl      interpret                    @ embedded forth/core.fth (test build)
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
    ldr     r0, =tib
    bl      interpret
    ldr     r0, =str_ok                 @ " ok\r\n"
    bl      print_str
    b       qloop

@ ---- M2: remaining stack words -------------------------------------------
defword nip, "nip"                      @ ( a b -- b )
nip_code:
    ldr     r0, [r4]                    @ b (TOS) survives
    add     r4, r4, #4                  @ drop a's cell
    str     r0, [r4]
    b       next

defword tuck, "tuck"                    @ ( a b -- b a b )
tuck_code:
    ldr     r0, [r4]                    @ b
    ldr     r1, [r4, #4]                @ a
    sub     r4, r4, #4
    str     r0, [r4]
    str     r1, [r4, #4]
    str     r0, [r4, #8]
    b       next

defword rot, "rot"                      @ ( a b c -- b c a )
rot_code:
    ldr     r0, [r4]                    @ c
    ldr     r1, [r4, #4]                @ b
    ldr     r2, [r4, #8]                @ a
    str     r2, [r4]
    str     r0, [r4, #4]
    str     r1, [r4, #8]
    b       next

defword to_r, ">r"                      @ ( x -- ) (RS: -- x)
to_r_code:
    ldr     r0, [r4], #4
    sub     r13, r13, #4
    str     r0, [r13]
    b       next

defword from_r, "r>"                    @ ( -- x ) (RS: x --)
from_r_code:
    ldr     r0, [r13], #4
    sub     r4, r4, #4
    str     r0, [r4]
    b       next

defword r_fetch, "r@"                   @ ( -- x ) (RS: x -- x)
r_fetch_code:
    ldr     r0, [r13]
    sub     r4, r4, #4
    str     r0, [r4]
    b       next

defword rdrop, "rdrop"                  @ ( -- ) (RS: x --)
rdrop_code:
    add     r13, r13, #4
    b       next

@ ---- M2: arithmetic / logic -------------------------------------------------
defword minus, "-"                      @ ( a b -- a-b )
minus_code:
    ldr     r0, [r4]
    ldr     r1, [r4, #4]
    sub     r0, r1, r0
    add     r4, r4, #4
    str     r0, [r4]
    b       next

defword star, "*"                       @ ( a b -- a*b )
star_code:
    ldr     r0, [r4]
    ldr     r1, [r4, #4]
    mul     r0, r1, r0
    add     r4, r4, #4
    str     r0, [r4]
    b       next

defword slashmod, "/mod"                @ ( a b -- rem quot )
slashmod_code:
    ldr     r0, [r4, #4]                @ a
    ldr     r1, [r4]                    @ b
    bl      sdivmod                     @ r0 = quot, r1 = rem
    str     r1, [r4, #4]                @ rem
    str     r0, [r4]                    @ quot
    b       next

defword umod, "u/mod"                   @ ( a b -- rem quot ) unsigned
umod_code:
    ldr     r0, [r4, #4]
    ldr     r1, [r4]
    bl      udivmod
    str     r1, [r4, #4]
    str     r0, [r4]
    b       next

defword and_w, "and"                    @ ( a b -- a&b )
and_w_code:
    ldr     r0, [r4]
    ldr     r1, [r4, #4]
    and     r0, r1, r0
    add     r4, r4, #4
    str     r0, [r4]
    b       next

defword or_w, "or"                      @ ( a b -- a|b )
or_w_code:
    ldr     r0, [r4]
    ldr     r1, [r4, #4]
    orr     r0, r1, r0
    add     r4, r4, #4
    str     r0, [r4]
    b       next

defword xor_w, "xor"                    @ ( a b -- a^b )
xor_w_code:
    ldr     r0, [r4]
    ldr     r1, [r4, #4]
    eor     r0, r1, r0
    add     r4, r4, #4
    str     r0, [r4]
    b       next

defword invert, "invert"                @ ( a -- ~a )
invert_code:
    ldr     r0, [r4]
    mvn     r0, r0
    str     r0, [r4]
    b       next

defword lshift, "lshift"                @ ( u n -- u<<n )
lshift_code:
    ldr     r0, [r4]                    @ n
    ldr     r1, [r4, #4]                @ u
    mov     r0, r1, lsl r0
    add     r4, r4, #4
    str     r0, [r4]
    b       next

defword rshift, "rshift"                @ ( u n -- u>>n logical )
rshift_code:
    ldr     r0, [r4]
    ldr     r1, [r4, #4]
    mov     r0, r1, lsr r0
    add     r4, r4, #4
    str     r0, [r4]
    b       next

defword z_eq, "0="                      @ ( a -- flag )
z_eq_code:
    ldr     r0, [r4]
    cmp     r0, #0
    mov     r0, #0
    mvneq   r0, #0
    str     r0, [r4]
    b       next

defword z_lt, "0<"                      @ ( a -- flag )
z_lt_code:
    ldr     r0, [r4]
    cmp     r0, #0
    mov     r0, #0
    mvnlt   r0, #0
    str     r0, [r4]
    b       next

defword z_gt, "0>"                      @ ( a -- flag )
z_gt_code:
    ldr     r0, [r4]
    cmp     r0, #0
    mov     r0, #0
    mvngt   r0, #0
    str     r0, [r4]
    b       next

defword eq, "="                         @ ( a b -- flag )
eq_code:
    ldr     r0, [r4]
    ldr     r1, [r4, #4]
    cmp     r1, r0
    mov     r0, #0
    mvneq   r0, #0
    add     r4, r4, #4
    str     r0, [r4]
    b       next

defword lt, "<"                         @ ( a b -- flag ) a<b
lt_code:
    ldr     r0, [r4]
    ldr     r1, [r4, #4]
    cmp     r1, r0
    mov     r0, #0
    mvnlt   r0, #0
    add     r4, r4, #4
    str     r0, [r4]
    b       next

defword gt, ">"                         @ ( a b -- flag ) a>b
gt_code:
    ldr     r0, [r4]
    ldr     r1, [r4, #4]
    cmp     r1, r0
    mov     r0, #0
    mvngt   r0, #0
    add     r4, r4, #4
    str     r0, [r4]
    b       next

defword u_lt, "u<"                      @ ( a b -- flag ) unsigned a<b
u_lt_code:
    ldr     r0, [r4]
    ldr     r1, [r4, #4]
    cmp     r1, r0
    mov     r0, #0
    mvnlo   r0, #0
    add     r4, r4, #4
    str     r0, [r4]
    b       next

defword ne, "<>"                        @ ( a b -- flag )
ne_code:
    ldr     r0, [r4]
    ldr     r1, [r4, #4]
    cmp     r1, r0
    mov     r0, #0
    mvnne   r0, #0
    add     r4, r4, #4
    str     r0, [r4]
    b       next

defword min, "min"                      @ ( a b -- min )
min_code:
    ldr     r0, [r4]
    ldr     r1, [r4, #4]
    cmp     r1, r0
    movlo   r0, r1
    add     r4, r4, #4
    str     r0, [r4]
    b       next

defword max, "max"                      @ ( a b -- max )
max_code:
    ldr     r0, [r4]
    ldr     r1, [r4, #4]
    cmp     r1, r0
    movgt   r0, r1
    add     r4, r4, #4
    str     r0, [r4]
    b       next

defword one_plus, "1+"                  @ ( a -- a+1 )
one_plus_code:
    ldr     r0, [r4]
    add     r0, r0, #1
    str     r0, [r4]
    b       next

defword one_minus, "1-"                 @ ( a -- a-1 )
one_minus_code:
    ldr     r0, [r4]
    sub     r0, r0, #1
    str     r0, [r4]
    b       next

defword two_star, "2*"                  @ ( a -- a*2 )
two_star_code:
    ldr     r0, [r4]
    add     r0, r0, r0
    str     r0, [r4]
    b       next

defword two_slash, "2/"                 @ ( a -- a/2 arithmetic )
two_slash_code:
    ldr     r0, [r4]
    asr     r0, r0, #1
    str     r0, [r4]
    b       next

defword abs_w, "abs"                    @ ( a -- |a| )
abs_w_code:
    ldr     r0, [r4]
    cmp     r0, #0
    rsblt   r0, r0, #0
    str     r0, [r4]
    b       next

defword negate, "negate"                @ ( a -- -a )
negate_code:
    ldr     r0, [r4]
    rsb     r0, r0, #0
    str     r0, [r4]
    b       next

@ ---- M2: memory words -------------------------------------------------------
defword fetch, "@"                      @ ( a -- x )
fetch_code:
    ldr     r0, [r4]
    ldr     r0, [r0]
    str     r0, [r4]
    b       next

defword store, "!"                      @ ( x a -- )
store_code:
    ldr     r0, [r4]                    @ a
    ldr     r1, [r4, #4]                @ x
    str     r1, [r0]
    add     r4, r4, #8
    b       next

defword c_fetch, "c@"                   @ ( a -- c )
c_fetch_code:
    ldr     r0, [r4]
    ldrb    r0, [r0]
    str     r0, [r4]
    b       next

defword c_store, "c!"                   @ ( c a -- )
c_store_code:
    ldr     r0, [r4]                    @ a
    ldr     r1, [r4, #4]                @ c
    strb    r1, [r0]
    add     r4, r4, #8
    b       next

defword plus_store, "+!"                @ ( x a -- ) a += x
plus_store_code:
    ldr     r0, [r4]                    @ a
    ldr     r1, [r4, #4]                @ x
    ldr     r2, [r0]
    add     r2, r2, r1
    str     r2, [r0]
    add     r4, r4, #8
    b       next

defword w_fetch, "w@"                   @ ( a -- w ) halfword
w_fetch_code:
    ldr     r0, [r4]
    ldrh    r0, [r0]
    str     r0, [r4]
    b       next

defword w_store, "w!"                   @ ( w a -- ) halfword
w_store_code:
    ldr     r0, [r4]
    ldr     r1, [r4, #4]
    strh    r1, [r0]
    add     r4, r4, #8
    b       next

defword allot, "allot"                  @ ( n -- ) HERE += n
allot_code:
    ldr     r0, [r4]
    add     r7, r7, r0
    add     r4, r4, #4
    b       next

defword comma, ","                      @ ( x -- ) align HERE, store cell
comma_code:
    ldr     r0, [r4]
    add     r7, r7, #3
    bic     r7, r7, #3
    str     r0, [r7], #4
    add     r4, r4, #4
    b       next

defword c_comma, "c,"                   @ ( c -- ) store byte
c_comma_code:
    ldr     r0, [r4]
    strb    r0, [r7], #1
    add     r4, r4, #4
    b       next

defword fill, "fill"                    @ ( a n c -- ) fill n bytes at a with c
fill_code:
    ldr     r0, [r4]                    @ c
    ldr     r1, [r4, #4]                @ n
    ldr     r2, [r4, #8]                @ a
1:  cmp     r1, #0
    beq     2f
    strb    r0, [r2], #1
    sub     r1, r1, #1
    b       1b
2:  add     r4, r4, #12
    b       next

defword move, "move"                    @ ( src dst n -- ) byte move
move_code:
    ldr     r0, [r4]                    @ n
    ldr     r1, [r4, #4]                @ dst
    ldr     r2, [r4, #8]                @ src
1:  cmp     r0, #0
    beq     2f
    ldrb    r3, [r2], #1
    strb    r3, [r1], #1
    sub     r0, r0, #1
    b       1b
2:  add     r4, r4, #12
    b       next

@ ---- M3: threading + compiler bootstrap words ------------------------------
defword exit, "exit"                    @ ( -- ) (RS: ip --)
exit_code:
    ldr     r10, [r13], #4
    b       next

defword lit, "lit"                      @ ( -- x ) (IP: -- x)
lit_code:
    ldr     r0, [r10], #4
    sub     r4, r4, #4
    str     r0, [r4]
    b       next

defword branch, "(branch)"              @ ( -- ) (IP: -- target)
branch_code:
    ldr     r10, [r10]
    b       next

defword zbranch, "(0branch)"            @ ( flag -- ) branch if flag == 0
zbranch_code:
    ldr     r0, [r4], #4
    cmp     r0, #0
    beq     1f
    add     r10, r10, #4
    b       next
1:  ldr     r10, [r10]
    b       next

defword word_w, "word"                   @ ( -- addr ) parse next token to wordbuf
word_w_code:
    bl      parse_name
    ldr     r0, =wordbuf
    sub     r4, r4, #4
    str     r0, [r4]
    b       next

@ header_create ( r0 = name, r1 = len, r2 = cfa ) : emit header at HERE, link to
@ latest, set latest; advances HERE past name, aligned. Clobbers r0-r3.
    .global header_create
header_create:
    str     r6, [r7]                    @ link = latest
    str     r2, [r7, #4]                @ cfa
    mov     r3, #0
    strb    r3, [r7, #8]                @ flags
    strb    r1, [r7, #9]                @ len
    add     r2, r7, #10
1:  cmp     r1, #0
    beq     2f
    ldrb    r3, [r0], #1
    strb    r3, [r2], #1
    sub     r1, r1, #1
    b       1b
2:  mov     r6, r7                      @ latest = new header
    mov     r7, r2
    add     r7, r7, #3
    bic     r7, r7, #3                  @ HERE = align4(after name)
    bx      lr

defword colon, ":"                      @ ( -- ) parse name, create colon word, state=1
colon_code:
    bl      parse_name
    ldr     r2, =docol
    bl      header_create
    mov     r8, #1
    ldr     r0, =state_v
    str     r8, [r0]
    b       next

defword semicolon, ";", 1               @ ( -- ) immediate: compile exit, state=0
semicolon_code:
    add     r7, r7, #3
    bic     r7, r7, #3
    ldr     r0, =exit_hdr
    str     r0, [r7], #4
    mov     r8, #0
    ldr     r0, =state_v
    str     r8, [r0]
    b       next

defword literal, "literal", 1           @ ( x -- ) immediate: compile lit x
literal_code:
    ldr     r0, [r4], #4
    add     r7, r7, #3
    bic     r7, r7, #3
    ldr     r1, =lit_hdr
    str     r1, [r7], #4
    str     r0, [r7], #4
    b       next

defword immediate, "immediate"          @ ( -- ) set immediate flag of latest
immediate_code:
    ldrb    r0, [r6, #8]
    orr     r0, r0, #1
    strb    r0, [r6, #8]
    b       next

defword create, "create"                @ ( -- ) parse name, create word (cfa=docon)
create_code:
    bl      parse_name
    ldr     r2, =docon
    bl      header_create
    b       next

defword dotquote, ".\"", 1              @ ( -- ) immediate: ." string"
dotquote_code:
    push    {r5, r8, lr}
    ldr     r0, =in_ptr
    ldr     r12, [r0]                   @ cursor
1:  ldrb    r2, [r12]
    cmp     r2, #0x20
    beq     2f
    cmp     r2, #9
    beq     2f
    b       3f
2:  add     r12, r12, #1
    b       1b
3:  mov     r0, r12                     @ string start
4:  ldrb    r2, [r12]
    cmp     r2, #0
    beq     5f
    cmp     r2, #0x22                   @ '"'
    beq     5f
    add     r12, r12, #1
    b       4b
5:  sub     r1, r12, r0                 @ len
    ldrb    r2, [r12]
    cmp     r2, #0x22
    bne     6f
    add     r12, r12, #1                 @ skip closing quote
6:  ldr     r2, =in_ptr
    str     r12, [r2]                   @ in_ptr past string
    cmp     r8, #0                      @ interpreting: print directly
    bne     dq_compile
    sub     r4, r4, #8                  @ print via vector; keep addr/len on the
    str     r0, [r4]                    @ data stack (emit_vec clobbers r0-r3,r12)
    str     r1, [r4, #4]
7:  ldr     r1, [r4, #4]
    cmp     r1, #0
    beq     71f
    ldr     r0, [r4]
    ldrb    r3, [r0]
    bl      emit_vec
    ldr     r0, [r4]
    add     r0, r0, #1
    str     r0, [r4]
    ldr     r1, [r4, #4]
    sub     r1, r1, #1
    str     r1, [r4, #4]
    b       7b
71: add     r4, r4, #8
    b       dq_done
dq_compile:
    add     r7, r7, #3
    bic     r7, r7, #3
    ldr     r2, =dotq_rt_hdr
    str     r2, [r7], #4                @ compile: ." runtime, addr, len
    add     r2, r7, #8                  @ string follows the addr/len cells
    str     r2, [r7], #4                @ addr
    str     r1, [r7], #4                @ len
    mov     r5, r1                      @ r5 = len (counter)
8:  cmp     r5, #0
    beq     dq_done
    ldrb    r3, [r0], #1
    strb    r3, [r7], #1
    sub     r5, r5, #1
    b       8b
dq_done:
    pop     {r5, r8, lr}
    b       next

defword dotq_rt, "(.\""                 @ runtime of ." : (IP: addr len --)
dotq_rt_code:
    ldr     r0, [r10], #4               @ addr
    ldr     r1, [r10], #4               @ len
    add     r10, r10, r1                @ skip the string embedded in the body
    add     r10, r10, #3
    bic     r10, r10, #3
    sub     r4, r4, #8                  @ addr/len on data stack (emit_vec clobbers
    str     r0, [r4]                    @ r0-r3, r10-r12)
    str     r1, [r4, #4]
1:  ldr     r1, [r4, #4]
    cmp     r1, #0
    beq     2f
    ldr     r0, [r4]
    ldrb    r3, [r0]
    bl      emit_vec
    ldr     r0, [r4]
    add     r0, r0, #1
    str     r0, [r4]
    ldr     r1, [r4, #4]
    sub     r1, r1, #1
    str     r1, [r4, #4]
    b       1b
2:  add     r4, r4, #8
    b       next

defword tramp, "tramp"
tramp_code:
    ldr     r12, =exec_idx
    ldr     r11, [r12]
    sub     r11, r11, #1
    str     r11, [r12]
    ldr     r3, =exec_stack
    add     r3, r3, r11, lsl #3
    ldr     r10, [r3]                   @ restore IP saved by execute_xt
    ldr     pc, [r3, #4]                @ return via saved lr

@ ---- M5: compiler-support + control-flow runtime words ---------------------
defword paren, "(", 1                   @ immediate: skip to ')'
paren_code:
    ldr     r0, =in_ptr
    ldr     r12, [r0]
1:  ldrb    r2, [r12]
    cmp     r2, #0
    beq     2f
    cmp     r2, #0x29                   @ ')'
    beq     3f
    add     r12, r12, #1
    b       1b
2:  str     r12, [r0]
    b       next
3:  add     r12, r12, #1
    str     r12, [r0]
    b       next

defword lbracket, "[", 1                @ ( -- ) immediate: interpret mode
lbracket_code:
    mov     r8, #0
    ldr     r0, =state_v
    str     r8, [r0]
    b       next

defword rbracket, "]", 1                @ ( -- ) immediate: compile mode
rbracket_code:
    mov     r8, #1
    ldr     r0, =state_v
    str     r8, [r0]
    b       next

defword postpone, "postpone", 1         @ immediate: compile lit <xt> ,
postpone_code:
    bl      parse_name
    bl      find
    cmp     r0, #0
    bne     1f
    bl      err_impl
    ldr     r0, =str_err
    bl      print_str
    ldr     r0, =wordbuf
    bl      print_str
    b       next
1:  add     r7, r7, #3
    bic     r7, r7, #3
    ldr     r1, =lit_hdr
    str     r1, [r7], #4
    str     r0, [r7], #4
    ldr     r1, =comma_hdr
    str     r1, [r7], #4
    b       next

defword find_w, "find"                  @ ( addr len -- xt flag )
find_w_code:
    ldr     r1, [r4], #4
    ldr     r0, [r4], #4
    bl      find
    cmp     r0, #0
    sub     r4, r4, #4
    str     r0, [r4]
    mvnne   r1, #0
    moveq   r1, #0
    sub     r4, r4, #4
    str     r1, [r4]
    b       next

defword number_w, "number"              @ ( addr len -- n flag )
number_w_code:
    ldr     r1, [r4], #4
    ldr     r0, [r4], #4
    bl      number_q
    sub     r4, r4, #4
    str     r0, [r4]
    sub     r4, r4, #4
    str     r1, [r4]
    b       next

defword execute_w, "execute"            @ ( xt -- )
execute_w_code:
    ldr     r0, [r4], #4
    bl      execute_xt
    b       next

defword tick, "'"                       @ ( -- xt )
tick_code:
    bl      parse_name
    bl      find
    cmp     r0, #0
    bne     1f
    bl      err_impl
    ldr     r0, =str_err
    bl      print_str
    ldr     r0, =wordbuf
    bl      print_str
    mov     r0, #0
1:  sub     r4, r4, #4
    str     r0, [r4]
    b       next

defword tickb, "[']", 1                 @ immediate: compile lit <xt>
tickb_code:
    bl      parse_name
    bl      find
    cmp     r0, #0
    bne     1f
    bl      err_impl
    ldr     r0, =str_err
    bl      print_str
    ldr     r0, =wordbuf
    bl      print_str
    mov     r0, #0
1:  add     r7, r7, #3
    bic     r7, r7, #3
    ldr     r1, =lit_hdr
    str     r1, [r7], #4
    str     r0, [r7], #4
    b       next

defword state_w, "state"                @ ( -- addr ) STATE variable
state_w_code:
    ldr     r0, =state_v
    sub     r4, r4, #4
    str     r0, [r4]
    b       next

defword abort_w, "abort"                @ ( -- ) reset data stack + state
abort_w_code:
    ldr     r0, =ps0
    ldr     r4, [r0]
    mov     r8, #0
    ldr     r0, =state_v
    str     r8, [r0]
    b       next

defword refill, "refill"                @ ( -- flag ) read a line via QUERY
refill_code:
    bl      query
    mvn     r0, #0
    sub     r4, r4, #4
    str     r0, [r4]
    b       next

defword boot_msg, "boot-msg"            @ ( -- ) print banner
boot_msg_code:
    ldr     r0, =banner
    bl      print_str
    b       next

defword do_rt, "(do)"                   @ ( limit index -- ) (R: -- limit index)
do_rt_code:
    ldr     r0, [r4], #4                @ index
    ldr     r1, [r4], #4                @ limit
    sub     r13, r13, #8
    str     r1, [r13, #4]
    str     r0, [r13]
    add     r10, r10, #4                @ skip the L placeholder cell
    b       next

defword qdo_rt, "(?do)"                 @ ( limit index -- ) skip loop if equal
qdo_rt_code:
    ldr     r0, [r4], #4
    ldr     r1, [r4], #4
    cmp     r0, r1
    beq     1f
    sub     r13, r13, #8
    str     r1, [r13, #4]
    str     r0, [r13]
    add     r10, r10, #4
    b       next
1:  ldr     r10, [r10]                  @ jump to [L] = after loop
    b       next

defword loop_rt, "(loop)"               @ (R: limit index -- )
loop_rt_code:
    ldr     r0, [r13]
    add     r0, r0, #1
    ldr     r1, [r13, #4]
    str     r0, [r13]
    cmp     r0, r1
    beq     1f
    b       next                          @ continue: fall into (branch)
1:  add     r13, r13, #8
    add     r10, r10, #8                @ skip (branch) xt + target
    b       next

defword plusloop_rt, "(+loop)"          @ ( n -- ) (R: limit index -- )
plusloop_rt_code:
    ldr     r0, [r4], #4                @ step
    ldr     r1, [r13]
    add     r1, r1, r0
    str     r1, [r13]
    ldr     r2, [r13, #4]
    cmp     r0, #0
    bge     2f
    cmp     r1, r2
    blt     1f
    b       next
2:  cmp     r1, r2
    bge     1f
    b       next
1:  add     r13, r13, #8
    add     r10, r10, #8
    b       next

defword leave_rt, "(leave)"             @ (R: limit index -- ) to after loop
leave_rt_code:
    add     r13, r13, #8
    ldr     r10, [r10]
    b       next

defword unloop_w, "unloop"              @ (R: limit index -- )
unloop_w_code:
    add     r13, r13, #8
    b       next

defword i_w, "i"                        @ ( -- index ) code word: r@ inside a
i_w_code:                               @ colon word would read the pushed IP
    ldr     r0, [r13]
    sub     r4, r4, #4
    str     r0, [r4]
    b       next

defword j_w, "j"                        @ ( -- outer index ) code word
j_w_code:
    ldr     r0, [r13, #8]
    sub     r4, r4, #4
    str     r0, [r4]
    b       next
    .ltorg

    .set    seed_latest, last_hdr
    .global seed_latest
    .ltorg

    .section .rodata
    .global banner
banner:     .asciz  "FUNForth seed 0.1 "
str_prompt: .asciz  "ok> "
str_ok:     .asciz  " ok\r\n"
str_err:    .asciz  "-? "
    .align 2
    .global core_fth
core_fth:
    .incbin "forth/core.fth"
    .byte   0                           @ NUL-terminate for interpret
core_fth_end:

    .section .bss
    .align 2
    .global tib
tib:        .space  132
    .global tib_len
tib_len:    .space  4
    .global numbuf
numbuf:     .space  20
    .global abort_flag
abort_flag: .space  4
    .global board_rev
board_rev:  .space  4
    .global ps0
ps0:        .space  4
    .global exec_cell
exec_cell:  .space  4
    .global exec_stack
exec_stack: .space  512               @ 64 entries of (IP, lr) for execute_xt
    .global exec_idx
exec_idx:   .space  4
    .global in_ptr
in_ptr:     .space  4
    .global wordbuf
wordbuf:    .space  64
    .global con_emit
con_emit:   .space  4
    .global con_key
con_key:    .space  4
    .global con_keyq
con_keyq:   .space  4
    .global base_v
base_v:     .space  4
    .global span_v
span_v:     .space  4
    .global hist
hist:       .space  8*132                 @ 8-line history ring
    .global hist_idx
hist_idx:   .space  4
    .global hist_cnt
hist_cnt:   .space  4
    .global hist_view
hist_view:  .space  4
    .global state_v
state_v:    .space  4
