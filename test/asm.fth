\ M15 t-asm: assembler core (code words, run, decompile, error)
load asm.fth
code double r0 tos-pop r0 r0 r0 add, r0 tos-push next end-code
21 double .
code forty2 r0 42 # mov, r0 tos-push next end-code
forty2 .
create scratch 0 ,
123 scratch !
code deref r0 tos-pop r0 0 r0 ldr, r0 tos-push next end-code
scratch deref .
code rtest 5 rpush 5 rpop next end-code
rtest
1 2 + .
see double
see dup
create hsave 0 ,
here hsave !
code bad r0 99 mov,
hsave @ here = .
\ M16: cond prefixes, s flag, modes, ldm/stm, swp, mul family, sys, imm32,
\ guards, header neutralization, labels
code eqmov r1 tos-pop r2 tos-pop r0 0 # mov, r1 r2 cmp, eq r0 1 # mov, r0 tos-push next end-code
5 5 eqmov .
5 6 eqmov .
code addone r0 tos-pop r0 r0 1 # s add, r0 tos-push next end-code
41 addone .
code movrot r0 65280 # mov, r0 tos-push next end-code
movrot h.
create cell2 0 ,
77 cell2 !
code deref2 r1 0 # mov, r0 tos-pop r0 r1 r0 ldrr, r0 tos-push next end-code
cell2 deref2 .
create lsbuf 8 allot
code lsm r0 tos-pop r1 5 # mov, ib r0 2 stm, r0 2 ldm, r1 tos-push next end-code
' lsbuf pfa lsm .
create swp-a 111 ,
code swpt r0 tos-pop r2 tos-pop r1 222 # mov, r2 r0 r1 swp, r1 tos-push next end-code
' swp-a pfa 55 swpt .
swp-a @ .
code mlat r0 tos-pop r1 tos-pop r2 tos-pop r3 r0 r2 r1 mla, r3 tos-push next end-code
3 4 5 mlat .
code umt r0 tos-pop r1 tos-pop r2 r3 r0 r1 umull, r2 tos-push r3 tos-push next end-code
6 7 umt . .
code litw 65280 lit, r0 tos-pop r0 tos-push next end-code
litw h.
code misc 0 bkpt, dsb, dmb, isb, 128 cpsid, 128 cpsie, next end-code
see misc
see eqmov
code down r0 5 # mov, label top ' top mark r0 r0 1 # sub, r0 0 # cmp, ne top b, r0 tos-push next end-code
down .
create hsave2 0 ,
here hsave2 !
code bad2 r0 mov,
hsave2 @ here = .
bad2
." END-ASM"
