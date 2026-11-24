\ M15 t-asm: assembler core (code words, run, decompile, error)
load asm.fth
code double r0 tos-pop r0 r0 add, r0 tos-push next end-code
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
." END-ASM"
