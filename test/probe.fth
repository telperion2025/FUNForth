\ TEMPORARY probe v13: cps-branch pieces at top level vs in colon word
load asm.fth
code m1 128 cpsid, next end-code
' m1 pfa @ ci ! ci @ h. cr ." A0" cr
ci @ 262144 and if ." cpsid " else ." cpsie " then cr ." A2" cr
ci @ 448 and h. space cr ." A3" cr
: d2 ( -- ) ci @ 262144 and if ." cpsid " else ." cpsie " then ci @ 448 and h. space cr ;
d2 ." A4" cr
' m1 pfa dis1 2drop cr ." A5" cr
." DONE" cr
