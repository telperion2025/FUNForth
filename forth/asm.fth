\ forth/asm.fth - M15 assembler core (CODE/end-code, postfix ARM encodings).
\ Loaded from the SD card (load asm.fth) when needed; not in BOOT.LST so
\ the M12 boot transcript is unchanged. No seed changes: the address of the
\ seed NEXT is found at load time by scanning 'dup''s body for its b-to-NEXT
\ (next-init). All immediates are 0-255 (rotated encodings are M16); labels
\ are backward-only via label/<name> + 'name mark (the seed tokenizer cannot
\ dispatch the spec's :<name> prefix; deferred to M16 with latest! + in_ptr).

\ ---- staging variables ----
create code-h0 0 ,  \ HERE at 'code' entry: error rollback target
create code-b  0 ,  \ PFA (body) of the word being assembled
create ci 0 ,       \ disassembler: current cell
create c2 0 ,       \ disassembler: lookahead cell
create ao1 0 ,      \ emitter staging: dest / base / opcode
create ao2 0 ,      \ emitter staging: src1 / off / rd
create ao3 0 ,      \ emitter staging: src2 / dest
create rv 0 ,       \ disassembler: rm / imm
create s1 0 ,       \ disassembler: shift amount
create s2 0 ,       \ disassembler: shift type
create nextv 0 ,    \ address of the seed NEXT (found by next-init)

\ ---- shared helpers ----
: pfa ( xt -- a ) dup 9 + c@ + 10 + align4 ;

: btarget ( a -- t )          \ target of a b/bl cell at a
  dup @ 16777215 and          \ 24-bit offset ( low 24 )
  dup 8388608 > if 16777216 - then   \ sign-extend when bit23 set ( < not >= )
  2 lshift swap 8 + + ;       \ [r4]... ( x<<2 ) + (a+8)

: asm-abort ( -- )            \ bad operand: roll HERE back and abort the line
  code-h0 @ here - allot
  abort ;

\ ---- operand validators (operand checked BEFORE the cell is written) ----
: ?rk ( p -- r )              \ register operand 0..15
  dup 0 < over 15 > or if ." -? reg " asm-abort then ;
: ?imm8 ( p -- n )            \ #-flagged immediate 0..255
  4026531839 and dup 255 > if ." -? imm " asm-abort then ;
: ?imm12 ( n -- n )           \ plain ldr/str offset 0..4095
  dup 0 < over 4095 > or if ." -? imm " asm-abort then ;
: ?imm5 ( n -- n )            \ shift amount 0..31
  dup 0 < over 31 > or if ." -? imm " asm-abort then ;

\ ---- operand-2 encode ----
\ # flags the number under it ( bit 268435456 ): immediate 0..255
\ ( 0x02000000 | imm ) else register 0..15.
: mk-op2 ( p -- w2 )
  dup 268435456 and if
    ?imm8 33554432 or
  else
    ?rk
  then ;

\ ---- CODE / end-code ----
\ code creates the header (name from the input stream); code-h0 is saved
\ BEFORE create so a failed assembly rolls HERE fully back (the stray header
\ stays linked until the next create; latest! cleanup is M16).
: code ( -- )
  here code-h0 !
  create
  here code-b ! ;
: end-code ( -- )             \ patch cfa := body start; NEXT jumps to [xt+4]
  code-b @ latest @ 4 + ! ;

\ ---- registers: colon constants ----
: r0 0 ;  : r1 1 ;  : r2 2 ;  : r3 3 ;
: r4 4 ;  : r5 5 ;  : r6 6 ;  : r7 7 ;
: r8 8 ;  : r9 9 ;  : r10 10 ; : r11 11 ;
: r12 12 ; : r13 13 ; : r14 14 ; : r15 15 ;
: sp 13 ; : lr 14 ; : pc 15 ;

\ # flags the number already on the stack as an immediate operand ( bit 268435456 )
: # ( n -- n' ) 268435456 or ;

\ ---- data ops ( postfix ; full operand order dest a b -- ) ----
: mov, ( d p -- )
  swap ao1 ! mk-op2 ao2 !
  3785359360 ao1 @ 4096 * ao2 @ or or , ;
: mvn, ( d p -- )
  swap ao1 ! mk-op2 ao2 !
  3789553664 ao1 @ 4096 * ao2 @ or or , ;
: add, ( d a p -- )
  rot ao1 ! swap ao2 ! mk-op2 ao3 !
  3766484992 ao1 @ 4096 * ao2 @ 65536 * or ao3 @ or or , ;
: sub, ( d a p -- )
  rot ao1 ! swap ao2 ! mk-op2 ao3 !
  3762290688 ao1 @ 4096 * ao2 @ 65536 * or ao3 @ or or , ;
: cmp, ( a p -- )
  swap ao1 ! mk-op2 ao2 !
  3780116480 ao1 @ 65536 * ao2 @ or or , ;
: and, ( d a p -- )
  rot ao1 ! swap ao2 ! mk-op2 ao3 !
  3758096384 ao1 @ 4096 * ao2 @ 65536 * or ao3 @ or or , ;
: orr, ( d a p -- )
  rot ao1 ! swap ao2 ! mk-op2 ao3 !
  3783262208 ao1 @ 4096 * ao2 @ 65536 * or ao3 @ or or , ;
: eor, ( d a p -- )
  rot ao1 ! swap ao2 ! mk-op2 ao3 !
  3760193536 ao1 @ 4096 * ao2 @ 65536 * or ao3 @ or or , ;
: bic, ( d a p -- )
  rot ao1 ! swap ao2 ! mk-op2 ao3 !
  3787456512 ao1 @ 4096 * ao2 @ 65536 * or ao3 @ or or , ;
: mul, ( d a b -- )
  rot ao1 ! swap ao2 ! ao3 !
  3758096528 ao1 @ 65536 * ao2 @ 256 * or ao3 @ or or , ;

\ ---- shifts ( dest src amount -- ; imm5, dropped into a mov encoding ) ----
: lsl, ( d s n -- )
  rot ao1 ! swap ao2 ! ?imm5 ao3 !
  3785359360 ao1 @ 4096 * ao2 @ ao3 @ 128 * or or or , ;
: lsr, ( d s n -- )
  rot ao1 ! swap ao2 ! ?imm5 ao3 !
  3785359392 ao1 @ 4096 * ao2 @ ao3 @ 128 * or or or , ;
: asr, ( d s n -- )
  rot ao1 ! swap ao2 ! ?imm5 ao3 !
  3785359424 ao1 @ 4096 * ao2 @ ao3 @ 128 * or or or , ;

\ ---- memory ( base off dest -- ; imm12 offset, P=1 U=1 ) ----
: ldr, ( b o d -- )
  ao3 ! swap ao1 ! ?imm12 ao2 !
  3851419648 ao3 @ 4096 * ao1 @ 65536 * or ao2 @ or or or , ;
: str, ( b o d -- )
  ao3 ! swap ao1 ! ?imm12 ao2 !
  3850371072 ao3 @ 4096 * ao1 @ 65536 * or ao2 @ or or or , ;

\ ---- r13 stack pair + TOS pair helpers ----
: rpush ( r -- ) 1 swap lshift 3912040448 or , ;   \ stmdb r13!, {r}
: rpop ( r -- ) 1 swap lshift 3904700416 or , ;     \ ldmia r13!, {r}

\ tos-pop r:   ldr r,[r4] / add r4,r4,#4   ( TOS cell cell -> reg )
: tos-pop ( r -- )
  ?rk 4096 * 3851681792 or , 3800317956 , ;
\ tos-push r: sub r4,r4,#4 / str r,[r4]   ( reg -> new TOS cell )
: tos-push ( r -- )
  ?rk 4096 * 3850633216 or 3796123652 swap , , ;

\ ---- branches ----
: b, ( t -- )
  here 8 + -
  dup abs 33554428 > if ." -? branch " asm-abort then
  2 rshift 16777215 and 3925868544 or , ;
: bl, ( t -- )
  here 8 + -
  dup abs 33554428 > if ." -? branch " asm-abort then
  2 rshift 16777215 and 3942645760 or , ;
: bx, ( p -- ) ?rk 3778019088 or , ;
: next ( -- ) nextv @ b, ;       \ branch to the seed NEXT

\ ---- labels ( backward refs only ) ----
\ label <name>: word whose body pushes its marked assembly address.
\ 'name mark binds it to the current assembly position (HERE).
: label ( -- )
  create
  docol-addr latest @ 4 + !
  ['] lit , 0 , ['] exit , ;
: mark ( xt -- ) pfa 4 + here swap ! ;

\ ---- decompiler ( used by the redefined see ) ----
: .reg ( r -- ) 114 emit . ;     \ "r<n>" ( digits via "." base-aware )

: regbit ( m -- r )              \ register of a 1-bit stm/ldm rlist
  rv !
  16 0 do rv @ 1 i lshift = if i unloop exit then loop -1 ;

: dis1 ( a -- a' f )             \ decode one cell; f true after "b next"
  dup @ ci ! dup 4 + @ c2 !
  ci @ 4278190080 and 3925868544 =
  if
    dup btarget nextv @ =
    if ." b next " 4 + -1 exit then
    ." b " dup btarget h. space 4 + 0 exit
  then
  ci @ 268435440 and 19922704 =
  if ." bx " ci @ 15 and .reg space 4 + 0 exit then
  ci @ 4294905855 and 3851681792 = c2 @ 3800317956 = and
  if ." tos-pop " ci @ 12 rshift 15 and .reg space 8 + 0 exit then
  ci @ 3796123652 = c2 @ 4294905855 and 3850633216 = and
  if ." tos-push " c2 @ 12 rshift 15 and .reg space 8 + 0 exit then
  ci @ 234881024 and 67108864 =
  if
    ci @ 1048576 and if ." ldr " else ." str " then
    ci @ 12 rshift 15 and .reg 32 emit 91 emit
    ci @ 16 rshift 15 and .reg 32 emit ci @ 4095 and . 93 emit space
    4 + 0 exit
  then
  ci @ 234881024 and 134217728 =
  ci @ 4294901760 and dup 3912040448 = swap 3904700416 = or and
  if
    ci @ 4294901760 and 3904700416 = if ." rpop " else ." rpush " then
    ci @ 65535 and regbit .reg space
    4 + 0 exit
  then
  ci @ 268435440 and 144 = ci @ 33554432 and 0= and
  if
    ." mul " ci @ 16 rshift 15 and .reg 32 emit ci @ 15 and .reg space
    4 + 0 exit
  then
  ci @ 234881024 and 33554432 = ci @ 8 rshift 15 and 0= and
  if
    ci @ 21 rshift 15 and ao1 !
    ci @ 12 rshift 15 and ao2 !
    ci @ 16 rshift 15 and ao3 !
    ci @ 255 and rv !
    ao1 @ 13 = if ." mov " ao2 @ .reg space 35 emit rv @ . space 4 + 0 exit then
    ao1 @ 15 = if ." mvn " ao2 @ .reg space 35 emit rv @ . space 4 + 0 exit then
    ao1 @ 4 = if ." add " ao2 @ .reg space ao3 @ .reg space 35 emit rv @ . space 4 + 0 exit then
    ao1 @ 2 = if ." sub " ao2 @ .reg space ao3 @ .reg space 35 emit rv @ . space 4 + 0 exit then
    ao1 @ 11 = if ." cmp " ao3 @ .reg space 35 emit rv @ . space 4 + 0 exit then
    ao1 @ 0 = if ." and " ao2 @ .reg space ao3 @ .reg space 35 emit rv @ . space 4 + 0 exit then
    ao1 @ 12 = if ." orr " ao2 @ .reg space ao3 @ .reg space 35 emit rv @ . space 4 + 0 exit then
    ao1 @ 1 = if ." eor " ao2 @ .reg space ao3 @ .reg space 35 emit rv @ . space 4 + 0 exit then
    ao1 @ 14 = if ." bic " ao2 @ .reg space ao3 @ .reg space 35 emit rv @ . space 4 + 0 exit then
  then
  ci @ 234881040 and 0 =
  if
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
    ao1 @ 11 = if ." cmp " ao3 @ .reg space rv @ .reg space 4 + 0 exit then
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
