\ forth/asm.fth - M15+M16 assembler (CODE/end-code, postfix ARM encodings).
\ Loaded from the SD card (load asm.fth) when needed; not in BOOT.LST so
\ the M12 boot transcript is unchanged. No seed changes: the address of the
\ seed NEXT is found at load time by scanning 'dup''s body for its b-to-NEXT
\ (next-init).
\
\ M16 adds: condition prefixes (eq..al, consumed by the next emitted cell),
\ the s flag (S bit on the next emitted cell), ldr/str addressing-mode
\ modifiers (neg post wb) + register-offset ldrr,/strr,, halfword/signed
\ imm forms (ldrh, strh, ldrsb, ldrsh,), ldm,/stm, with ia/ib/da/db modes,
\ swp,, mla, umull, smull, mrs, msr, bkpt,, dsb, dmb, isb,, cpsid, cpsie,,
\ nop,, lit, (inline literal), rotated immediates (imm32), operand-count
\ guards (?n), aborted-header neutralization + remaining-line abort.
\ Labels stay backward-only via label/<name> + '<name> mark: the spec's
\ :<name> token syntax needs a seed tokenizer hook (delta D4).

\ ---- staging variables ----
create code-h0 0 ,  \ HERE at 'code' entry: error rollback target
create code-b  0 ,  \ PFA (body) of the word being assembled
create code-xt 0 ,  \ xt of the word being assembled (latest may move: label)
create ci 0 ,       \ disassembler: current cell
create c2 0 ,       \ disassembler: lookahead cell
create ao1 0 ,      \ emitter staging: dest / base / opcode
create ao2 0 ,      \ emitter staging: src1 / off / rd
create ao3 0 ,      \ emitter staging: src2 / dest
create rv 0 ,       \ disassembler: rm / imm
create s1 0 ,       \ disassembler: shift amount
create s2 0 ,       \ disassembler: shift type
create nextv 0 ,    \ address of the seed NEXT (found by next-init)
create ccv 14 28 lshift ,  \ condition prefix, default AL (0xE0000000)
create sfv 0 ,      \ S-bit flag, consumed by the next emitted cell
create mm 0 ,       \ ldr/str modifiers: 1=neg(U=0) 2=post(P=0) 4=wb(W=1)
create lm 0 ,
create asm-dead 0 ,
: ,safe ( w -- ) asm-dead @ if drop exit then , ;       \ ldm/stm mode: 0=ia 1=ib 2=da 3=db

\ ---- shared helpers ----
: pfa ( xt -- a ) dup 9 + c@ + 10 + align4 ;

: btarget ( a -- t )          \ target of a b/bl cell at a
  dup @ 16777215 and          \ 24-bit offset ( low 24 )
  dup 8388608 and if 16777216 - then   \ sign-extend when bit23 set
  2 lshift swap 8 + + ;

: asm-abort ( -- )            \ bad encoding: roll HERE back, neutralize the
  code-h0 @ here - allot
  1 asm-dead !      \ aborted header (cfa := abort; latest lives in
  code-xt @ 4 + ['] abort 4 + @ swap !   \ r6, no Forth-visible writer - D4),
  begin word count nip 0= until       \ skip the rest of the input line,
  0 0 0 state ! ;                            \ then abort

: ?n ( n -- )                 \ operand-count guard
  depth over 1 + < if ." -? ops" asm-abort then drop ;

\ ---- operand validators (operand checked BEFORE the cell is written) ----
: ?rk ( p -- r )              \ register operand 0..15
  dup 0 < over 15 > or if ." -? reg" asm-abort then ;
: ?imm12 ( n -- n )           \ plain ldr/str offset 0..4095
  dup 0 < over 4095 > or if ." -? imm" asm-abort then ;
: ?imm8r ( n -- n )           \ halfword offset 0..255
  dup 0 < over 255 > or if ." -? imm" asm-abort then ;
: ?imm5 ( n -- n )            \ shift amount 0..31
  dup 0 < over 31 > or if ." -? imm" asm-abort then ;
: ?imm16 ( n -- n )           \ bkpt immediate 0..65535
  dup 0 < over 65535 > or if ." -? imm" asm-abort then ;
: ?mask ( m -- m )            \ ldm/stm register mask / cps AIF mask 0..65535
  dup 0 < over 65535 > or if ." -? reg" asm-abort then ;

\ ---- rotated immediates (imm32: 8-bit value ror even 0..30) ----
: ror32 ( n s -- n' )
  >r dup r@ rshift swap r> 32 swap - lshift or ;
: ?imm32 ( n -- op2 )
  dup 0< if ." -? imm" asm-abort then
  16 0 do
    dup i 2 * 32 swap - ror32 dup 255 > 0= if i 8 lshift swap or swap drop unloop exit then
    drop
  loop
  ." -? imm" asm-abort ;

\ ---- operand-2 encode ----
\ # flags the number under it ( bit 268435456 ): immediate (rotated imm32)
\ ( 0x02000000 | op2 ) else register 0..15.
: mk-op2 ( p -- w2 )
  dup 268435456 and if
    268435455 and ?imm32 33554432 or
  else
    ?rk
  then ;

\ ---- cell emitter: applies cond prefix + S flag, then resets both ----
: emitc ( w -- )
  ccv @ or sfv @ 1048576 * or ,safe
  14 28 lshift ccv ! 0 sfv ! ;

\ ---- CODE / end-code ----
\ code creates the header (name from the input stream); code-h0 is saved
\ BEFORE create so a failed assembly rolls HERE fully back.
: code ( -- )
  0 asm-dead !
  here latest = if here 9 + c@ 10 + align4 allot then
  here code-h0 !
  create
  latest code-xt !
  here code-b ! ;
: end-code ( -- )             \ patch cfa := body start; NEXT jumps to [xt+4]
  code-b @ code-xt @ 4 + ! ;

\ ---- registers: colon constants ----
: r0 0 ;  : r1 1 ;  : r2 2 ;  : r3 3 ;
: r4 4 ;  : r5 5 ;  : r6 6 ;  : r7 7 ;
: r8 8 ;  : r9 9 ;  : r10 10 ; : r11 11 ;
: r12 12 ; : r13 13 ; : r14 14 ; : r15 15 ;
: sp 13 ; : lr 14 ; : pc 15 ;

\ # flags the number already on the stack as an immediate operand ( bit 268435456 )
: # ( n -- n' ) 268435456 or ;

\ ---- condition prefixes (consumed by the next emitted cell) ----
: eq 0 ccv ! ;  : ne 1 28 lshift ccv ! ;  : hs 2 28 lshift ccv ! ;
: lo 3 28 lshift ccv ! ;  : mi 4 28 lshift ccv ! ;  : pl 5 28 lshift ccv ! ;
: vs 6 28 lshift ccv ! ;  : vc 7 28 lshift ccv ! ;  : hi 8 28 lshift ccv ! ;
: ls 9 28 lshift ccv ! ;  : ge 10 28 lshift ccv ! ; : lt 11 28 lshift ccv ! ;
: gt 12 28 lshift ccv ! ; : le 13 28 lshift ccv ! ; : al 14 28 lshift ccv ! ;
: cs 2 28 lshift ccv ! ;  : cc 3 28 lshift ccv ! ;
: s 1 sfv ! ;                \ S bit on the next emitted cell

\ ---- data ops ( postfix ; full operand order dest a b -- ) ----
\ bases are cond-free (emitc ORs ccv back in)
: mov, ( d p -- )
  2 ?n swap ao1 ! mk-op2 ao2 !
  27262976 ao1 @ 4096 * ao2 @ or or emitc ;
: mvn, ( d p -- )
  2 ?n swap ao1 ! mk-op2 ao2 !
  31457280 ao1 @ 4096 * ao2 @ or or emitc ;
: add, ( d a p -- )
  3 ?n rot ao1 ! swap ao2 ! mk-op2 ao3 !
  8388608 ao1 @ 4096 * ao2 @ 65536 * or ao3 @ or or emitc ;
: sub, ( d a p -- )
  3 ?n rot ao1 ! swap ao2 ! mk-op2 ao3 !
  4194304 ao1 @ 4096 * ao2 @ 65536 * or ao3 @ or or emitc ;
: cmp, ( a p -- )
  2 ?n swap ao1 ! mk-op2 ao2 !
  22020096 ao1 @ 65536 * ao2 @ or or emitc ;
: and, ( d a p -- )
  3 ?n rot ao1 ! swap ao2 ! mk-op2 ao3 !
  0 ao1 @ 4096 * ao2 @ 65536 * or ao3 @ or or emitc ;
: orr, ( d a p -- )
  3 ?n rot ao1 ! swap ao2 ! mk-op2 ao3 !
  25165824 ao1 @ 4096 * ao2 @ 65536 * or ao3 @ or or emitc ;
: eor, ( d a p -- )
  3 ?n rot ao1 ! swap ao2 ! mk-op2 ao3 !
  2097152 ao1 @ 4096 * ao2 @ 65536 * or ao3 @ or or emitc ;
: bic, ( d a p -- )
  3 ?n rot ao1 ! swap ao2 ! mk-op2 ao3 !
  29360128 ao1 @ 4096 * ao2 @ 65536 * or ao3 @ or or emitc ;
: mul, ( d a b -- )
  3 ?n rot ao1 ! swap ao2 ! ao3 !
  144 ao1 @ 65536 * ao2 @ 256 * or ao3 @ or or emitc ;
: mla, ( d rm rs rn -- )      \ mla d, rm, rs, rn
  4 ?n ao3 ! ao2 ! swap ao1 !
  2097296 ao1 @ 65536 * or ao3 @ 4096 * or ao2 @ 256 * or swap or emitc ;
: umull, ( lo hi rm rs -- )
  4 ?n ao3 ! ao2 ! swap ao1 !
  8388752 swap 16 lshift or ao1 @ 4096 * or ao3 @ 256 * or ao2 @ or emitc ;
: smull, ( lo hi rm rs -- )
  4 ?n ao3 ! ao2 ! swap ao1 !
  12583056 swap 16 lshift or ao1 @ 4096 * or ao3 @ 256 * or ao2 @ or emitc ;
: nop, 27262976 emitc ;       \ mov r0, r0

\ ---- shifts ( dest src amount -- ; imm5, dropped into a mov encoding ) ----
: lsl, ( d s n -- )
  3 ?n rot ao1 ! swap ao2 ! ?imm5 ao3 !
  27262976 ao1 @ 4096 * ao2 @ ao3 @ 128 * or or or emitc ;
: lsr, ( d s n -- )
  3 ?n rot ao1 ! swap ao2 ! ?imm5 ao3 !
  27263008 ao1 @ 4096 * ao2 @ ao3 @ 128 * or or or emitc ;
: asr, ( d s n -- )
  3 ?n rot ao1 ! swap ao2 ! ?imm5 ao3 !
  27263040 ao1 @ 4096 * ao2 @ ao3 @ 128 * or or or emitc ;

\ ---- memory: addressing-mode modifiers consumed by the next mem op ----
\ neg: U=0 (subtract offset)   post: P=0 (post-index)   wb: W=1 (writeback)
: neg 1 mm ! ;  : post 2 mm ! ;  : wb 4 mm ! ;
: applymm ( base -- base' )   \ base carries P=1 U=1
  mm @ 1 and if 8388608 xor then
  mm @ 2 and if 16777216 xor then
  mm @ 4 and if 2097152 or then
  0 mm ! ;

\ ---- word ldr/str: imm12 offset ( ldr, ) and register offset ( ldrr, ) ----
\ ldr, ( b o d -- )   ldrr, ( b r d -- )
: ldr, ( b o d -- )
  3 ?n ao3 ! swap ao1 ! ?imm12 ao2 !
  93323264 applymm ao3 @ 4096 * or ao1 @ 65536 * or ao2 @ or emitc ;
: str, ( b o d -- )
  3 ?n ao3 ! swap ao1 ! ?imm12 ao2 !
  92274688 applymm ao3 @ 4096 * or ao1 @ 65536 * or ao2 @ or emitc ;
: ldrr, ( b r d -- )
  3 ?n ao3 ! swap ao1 ! ?rk ao2 !
  126877696 applymm ao3 @ 4096 * or ao1 @ 65536 * or ao2 @ or emitc ;
: strr, ( b r d -- )
  3 ?n ao3 ! swap ao1 ! ?rk ao2 !
  125829120 applymm ao3 @ 4096 * or ao1 @ 65536 * or ao2 @ or emitc ;

\ ---- halfword / signed byte, imm8 offset ( b o d -- ) ----
: ldrh, ( b o d -- )
  3 ?n ao3 ! swap ao1 ! ?imm8r ao2 !
  30408880 applymm ao3 @ 4096 * or ao1 @ 65536 * or ao2 @ 4 rshift 8 lshift or ao2 @ 15 and or emitc ;
: strh, ( b o d -- )
  3 ?n ao3 ! swap ao1 ! ?imm8r ao2 !
  29360304 applymm ao3 @ 4096 * or ao1 @ 65536 * or ao2 @ 4 rshift 8 lshift or ao2 @ 15 and or emitc ;
: ldrsb, ( b o d -- )
  3 ?n ao3 ! swap ao1 ! ?imm8r ao2 !
  30408912 applymm ao3 @ 4096 * or ao1 @ 65536 * or ao2 @ 4 rshift 8 lshift or ao2 @ 15 and or emitc ;
: ldrsh, ( b o d -- )
  3 ?n ao3 ! swap ao1 ! ?imm8r ao2 !
  30408944 applymm ao3 @ 4096 * or ao1 @ 65536 * or ao2 @ 4 rshift 8 lshift or ao2 @ 15 and or emitc ;

\ ---- ldm/stm ( b mask -- ), mode set by ia/ib/da/db, writeback always ----
: ia 0 lm ! ;  : ib 1 lm ! ;  : da 2 lm ! ;  : db 3 lm ! ;
: ldm, ( b mask -- )
  2 ?n swap ao1 ! ?mask ao2 !
  145752064 lm @ 1 and 24 lshift or lm @ 2 < 0= if 8388608 xor then
  ao1 @ 65536 * or ao2 @ or emitc 0 lm ! ;
: stm, ( b mask -- )
  2 ?n swap ao1 ! ?mask ao2 !
  144703488 lm @ 1 and 24 lshift or lm @ 2 < 0= if 8388608 xor then
  ao1 @ 65536 * or ao2 @ or emitc 0 lm ! ;

\ ---- swap: swp, ( b r d -- ) = swp d, r, [b] ----
: swp, ( b r d -- )
  3 ?n ao3 ! swap ao1 ! ?rk ao2 !
  16777360 ao3 @ 4096 * or ao1 @ 65536 * or ao2 @ or emitc ;

\ ---- r13 stack pair + TOS pair helpers ----
: rpush ( r -- ) 1 ?n 1 swap lshift 153944064 or emitc ;   \ stmdb r13!, {r}
: rpop ( r -- ) 1 ?n 1 swap lshift 146604032 or emitc ;    \ ldmia r13!, {r}

\ tos-pop r:   ldr r,[r4] / add r4,r4,#4   ( TOS cell -> reg )
: tos-pop ( r -- )
  1 ?n ?rk 4096 * 93585408 or emitc 42221572 emitc ;
\ tos-push r: sub r4,r4,#4 / str r,[r4]   ( reg -> new TOS cell )
: tos-push ( r -- )
  1 ?n ?rk 4096 * 92536832 or >r 38027268 emitc r> emitc ;

\ ---- branches ----
: b, ( t -- )
  1 ?n here 8 + -
  dup abs 33554432 > if ." -? branch" asm-abort then
  2 rshift 16777215 and 167772160 or emitc ;
: bl, ( t -- )
  1 ?n here 8 + -
  dup abs 33554432 > if ." -? branch" asm-abort then
  2 rshift 16777215 and 184549376 or emitc ;
: bx, ( p -- ) 1 ?n ?rk 19922704 or emitc ;
: next ( -- ) nextv @ b, ;       \ branch to the seed NEXT

\ ---- system / status ----
: mrs, ( d -- ) 1 ?n ?rk 4096 * 17760256 or emitc ;
: msr, ( r -- ) 1 ?n ?rk 19918848 or emitc ;      \ msr CPSR_f, r
: bkpt, ( imm -- ) 1 ?n ?imm16
  dup 4 rshift 4095 and 8 lshift swap 15 and or 18874480 or emitc ;
: dsb, -301527142 emitc ;        \ 0x0E070F9A | cond : mcr p15,0,r0,c7,c10,4
: dmb, -301527141 emitc ;        \ 0x0E070F9B : mcr p15,0,r0,c7,c10,5
: isb, -301527147 emitc ;        \ 0x0E070F95 : mcr p15,0,r0,c7,c5,4
: cpsid, ( m -- ) 1 ?n ?mask -250871808 or ,safe ;   \ 0xF10C0000 | AIF (cond 0xF fixed)
: cpsie, ( m -- ) 1 ?n ?mask -251133952 or ,safe ;   \ 0xF1080000 | AIF
: lit, ( n -- ) asm-dead @ if drop exit then ['] lit , , ;    \ inline literal pair (pool = inline lit,)

\ ---- labels ( backward refs only ) ----
\ label <name>: word whose body pushes its marked assembly address.
\ '<name> mark binds it to the current assembly position (HERE).
: label ( -- )
  create
  docol-addr latest 4 + !
  ['] lit , 0 , ['] exit , ;
: mark ( xt -- ) pfa 4 + here swap ! ;

\ ---- decompiler ( used by the redefined see ) ----
: .reg ( r -- ) 114 emit . ;     \ "r<n>" ( digits via "." base-aware )

: .cond ( c -- )                 \ print 2-letter cond prefix unless AL
  dup 14 = if drop exit then
  dup 0 = if drop ." eq " exit then
  dup 1 = if drop ." ne " exit then
  dup 2 = if drop ." hs " exit then
  dup 3 = if drop ." lo " exit then
  dup 4 = if drop ." mi " exit then
  dup 5 = if drop ." pl " exit then
  dup 6 = if drop ." vs " exit then
  dup 7 = if drop ." vc " exit then
  dup 8 = if drop ." hi " exit then
  dup 9 = if drop ." ls " exit then
  dup 10 = if drop ." ge " exit then
  dup 11 = if drop ." lt " exit then
  dup 12 = if drop ." gt " exit then
  dup 13 = if drop ." le " exit then
  drop ;

: regbit ( m -- r )              \ register of a 1-bit stm/ldm rlist
  rv !
  16 0 do rv @ 1 i lshift = if i unloop exit then loop -1 ;

: dis1 ( a -- a' f )             \ decode one cell; f true after "b next"
  dup @ ci ! dup 4 + @ c2 !
  ci @ 28 rshift .cond
  ci @ 251658240 and ao1 !
  ao1 @ 167772160 = if           \ b
    dup btarget nextv @ =
    if ." b next " 4 + -1 exit then
    ." b " dup btarget h. space 4 + 0 exit then
  ao1 @ 184549376 = if ." bl " dup btarget h. space 4 + 0 exit then
  ci @ 268435216 and 19922704 = if ." bx " ci @ 15 and .reg space 4 + 0 exit then
  ci @ 268374015 and 93585408 = c2 @ 268435455 and 42221572 = and
  if ." tos-pop " ci @ 12 rshift 15 and .reg space 8 + 0 exit then
  ci @ 268435455 and 38027268 = c2 @ 268374015 and 92536832 = and
  if ." tos-push " c2 @ 12 rshift 15 and .reg space 8 + 0 exit then
  ci @ 201326592 and 67108864 = if            \ word ldr/str (imm or reg off)
    ci @ 1048576 and if ." ldr " else ." str " then
    ci @ 12 rshift 15 and .reg 32 emit 91 emit
    ci @ 16 rshift 15 and .reg 32 emit
    ci @ 25 rshift 1 and if ci @ 15 and .reg else ci @ 4095 and . then
    93 emit space 4 + 0 exit then
  ci @ 234881168 and 144 = if                 \ halfword/signed extra ls
    ci @ 5 rshift 3 and s2 ! ci @ 20 rshift 1 and ao1 !
    s2 @ 1 = ao1 @ 1 = and if ." ldrh " then
    s2 @ 1 = ao1 @ 0 = and if ." strh " then
    s2 @ 2 = if ." ldrsb " then
    s2 @ 3 = if ." ldrsh " then
    ci @ 12 rshift 15 and .reg 32 emit 91 emit
    ci @ 16 rshift 15 and .reg 32 emit
    ci @ 22 rshift 1 and if ci @ 8 rshift 15 and 4 lshift ci @ 15 and or . else ci @ 15 and .reg then
    93 emit space 4 + 0 exit then
  ci @ 234881024 and 134217728 = if           \ ldm/stm
    ci @ 1048576 and if ." ldm " else ." stm " then
    ci @ 24 rshift 1 and ao1 ! ci @ 23 rshift 1 and ao2 !
    ao1 @ 0= ao2 @ 1 = and if ." ia " then
    ao1 @ 1 = ao2 @ 1 = and if ." ib " then
    ao1 @ 0= ao2 @ 0= and if ." da " then
    ao1 @ 1 = ao2 @ 0= and if ." db " then
    ci @ 16 rshift 15 and .reg space ci @ 65535 and h. space
    4 + 0 exit then
  ci @ 263196656 and 16777360 = if            \ swp
    ." swp " ci @ 12 rshift 15 and .reg 32 emit ci @ 15 and .reg 32 emit
    ci @ 16 rshift 15 and .reg space 4 + 0 exit then
  ci @ 266338544 and ao1 !                    \ multiply family
  ao1 @ 144 = if ." mul " ci @ 16 rshift 15 and .reg 32 emit ci @ 15 and .reg space 4 + 0 exit then
  ao1 @ 2097296 = if ." mla " ci @ 16 rshift 15 and .reg 32 emit ci @ 12 rshift 15 and .reg 32 emit ci @ 8 rshift 15 and .reg 32 emit ci @ 15 and .reg space 4 + 0 exit then
  ao1 @ 8388752 = if ." umull " ci @ 16 rshift 15 and .reg 32 emit ci @ 12 rshift 15 and .reg 32 emit ci @ 8 rshift 15 and .reg 32 emit ci @ 15 and .reg space 4 + 0 exit then
  ao1 @ 12583056 = if ." smull " ci @ 16 rshift 15 and .reg 32 emit ci @ 12 rshift 15 and .reg 32 emit ci @ 8 rshift 15 and .reg 32 emit ci @ 15 and .reg space 4 + 0 exit then
  ci @ 264179711 and 17760256 = if ." mrs " ci @ 12 rshift 15 and .reg space 4 + 0 exit then
  ci @ 263258096 and 19918848 = if ." msr " ci @ 15 and .reg space 4 + 0 exit then
  ci @ 267387120 and 18874480 = if            \ bkpt
    ." bkpt " ci @ 8 rshift 4095 and 4 lshift ci @ 15 and or . space
    4 + 0 exit then
  ci @ 268435455 and 235343765 = if ." isb " 4 + 0 exit then
  ci @ 268435455 and 235343770 = if ." dsb " 4 + 0 exit then
  ci @ 268435455 and 235343771 = if ." dmb " 4 + 0 exit then
  ci @ 267386880 and 16777216 = if            \ cps family (cond 0xF)
    ci @ 262144 and if ." cpsid " else ." cpsie " then
    ci @ 448 and h. space 4 + 0 exit then
  ci @ 234881024 and 33554432 = ci @ 8 rshift 15 and 0= and if   \ data, imm
    ci @ 21 rshift 15 and ao1 !
    ci @ 12 rshift 15 and ao2 !
    ci @ 16 rshift 15 and ao3 !
    ci @ 255 and rv !
    ao1 @ 13 = if ." mov " ao2 @ .reg space 35 emit rv @ . space 4 + 0 exit then
    ao1 @ 15 = if ." mvn " ao2 @ .reg space 35 emit rv @ . space 4 + 0 exit then
    ao1 @ 4 = if ." add " ao2 @ .reg space ao3 @ .reg space 35 emit rv @ . space 4 + 0 exit then
    ao1 @ 2 = if ." sub " ao2 @ .reg space ao3 @ .reg space 35 emit rv @ . space 4 + 0 exit then
    ao1 @ 10 = if ." cmp " ao3 @ .reg space 35 emit rv @ . space 4 + 0 exit then
    ao1 @ 0 = if ." and " ao2 @ .reg space ao3 @ .reg space 35 emit rv @ . space 4 + 0 exit then
    ao1 @ 12 = if ." orr " ao2 @ .reg space ao3 @ .reg space 35 emit rv @ . space 4 + 0 exit then
    ao1 @ 1 = if ." eor " ao2 @ .reg space ao3 @ .reg space 35 emit rv @ . space 4 + 0 exit then
    ao1 @ 14 = if ." bic " ao2 @ .reg space ao3 @ .reg space 35 emit rv @ . space 4 + 0 exit then
  then
  ci @ 234881040 and 0 = if                   \ data, reg
    ci @ 21 rshift 15 and ao1 !
    ci @ 12 rshift 15 and ao2 !
    ci @ 16 rshift 15 and ao3 !
    ci @ 15 and rv !
    ao1 @ 13 = if
      ci @ 4 rshift 255 and 0 = if
        ." mov " ao2 @ .reg space rv @ .reg space 4 + 0 exit
      then
      ci @ 5 rshift 3 and s2 !
      ci @ 7 rshift 31 and s1 !
      s2 @ 0 = if ." lsl " then
      s2 @ 1 = if ." lsr " then
      s2 @ 2 = if ." asr " then
      ao2 @ .reg space rv @ .reg space 35 emit s1 @ . space
      4 + 0 exit
    then
    ao1 @ 15 = if ." mvn " ao2 @ .reg space rv @ .reg space 4 + 0 exit then
    ao1 @ 10 = if ." cmp " ao3 @ .reg space rv @ .reg space 4 + 0 exit then
    ao1 @ 4 = if ." add " ao2 @ .reg space ao3 @ .reg space rv @ .reg space 4 + 0 exit then
    ao1 @ 2 = if ." sub " ao2 @ .reg space ao3 @ .reg space rv @ .reg space 4 + 0 exit then
    ao1 @ 0 = if ." and " ao2 @ .reg space ao3 @ .reg space rv @ .reg space 4 + 0 exit then
    ao1 @ 12 = if ." orr " ao2 @ .reg space ao3 @ .reg space rv @ .reg space 4 + 0 exit then
    ao1 @ 1 = if ." eor " ao2 @ .reg space ao3 @ .reg space rv @ .reg space 4 + 0 exit then
    ao1 @ 14 = if ." bic " ao2 @ .reg space ao3 @ .reg space rv @ .reg space 4 + 0 exit then
  then
  ." ? " ci @ h. space 4 + 0  ;

\ ---- see ( redefined: decompiles code words to mnemonics ) ----
\ Colon words are decompiled exactly like the core see; code words walk
\ from the PFA until dis1 prints the closing b-to-NEXT.
: see ( -- )
  '
  dup 4 + @ docol-addr =
  if
    dup .name ." : "
    dup 9 + c@ + 10 + align4
    begin dup @ ['] exit <> while cell. repeat
    drop ." ;" cr
  else
    dup .name ." : <code> " pfa
    begin dis1 until
    ." ;" cr drop
  then ;

\ ---- locate the seed NEXT ( no seed change: scan 'dup''s body ) ----
: next-init ( -- )
  ['] dup pfa
  begin dup @ 4278190080 and 3925868544 = 0= while 4 + repeat
  btarget nextv ! ;

next-init
