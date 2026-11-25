\ TEMPORARY probe v14: h. / if / if-else inside colon words
load asm.fth
code m1 128 cpsid, next end-code
' m1 pfa @ ci !
: d3 ( -- ) ci @ 448 and h. space cr ;
d3 ." A6" cr
: d4 ( -- ) ci @ 262144 and if ." cpsid " then cr ;
d4 ." A7" cr
: d5 ( -- ) ci @ 262144 and if ." cpsid " else ." cpsie " then cr ;
d5 ." A8" cr
." DONE" cr
