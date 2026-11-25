\ TEMPORARY probe v4: ?imm32 fix check, next-redraw inline bisect, term, bad rect last
load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
load term.fth
load asm.fth
640 400 8 fb-alloc .
fb-clear
wm-init
." R1" cr 65280 8 ror32 h. cr
." R2" cr 65280 16 ror32 h. cr
." R3" cr 65280 32 ror32 h. cr
." I1" cr 65280 ?imm32 h. cr depth . cr
." I2" cr 42 ?imm32 h. cr
create win1 0 ,
200 120 win-new win1 !
word One count win1 @ win-title!
: redraw1 ( win -- ) drop ;
['] redraw1 win1 @ win-redraw!
100 win1 @ win-x! 60 win1 @ win-y! win1 @ win-open
wm-list @ wm-cur ! ." N1" cr
wm-cur @ h. cr
wm-cur @ dup wm-win ! @ wm-cur ! ." N2" cr
wm-cur @ h. cr
0 0 fb-w @ 1- fb-h @ 1- clip! ." N3" cr
wm-win @ win-x@ wm-win @ win-y@ wm-win @ win-w@ wm-win @ win-x@ + 1- wm-win @ win-y@ wm-win @ win-h@ + 1- fillrect0 ." N4" cr
wm-win @ wm-chrome ." N5" cr
clip> ." N6" cr
wm-win @ win-redraw@ h. cr
wm-win @ win-redraw@ execute ." N7" cr
." N8" cr
wm-redraw-all ." A7" cr
create t1 0 ,
10 4 term-new t1 !
word T1 count t1 @ win-title!
60 t1 @ win-x! 40 t1 @ win-y! t1 @ win-open
." T1" cr
wm-redraw-all ." T2" cr
120 90 60 20 fillrect0 ." C3" cr
code movrot r0 65280 # mov, r0 tos-push next end-code
movrot h. cr ." B4" cr
." DONE" cr
