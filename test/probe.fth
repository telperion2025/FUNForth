\ TEMPORARY probe v2: bisect hangs (read via CI artifact transcript)
load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
load asm.fth
640 400 8 fb-alloc .
fb-clear
wm-init
create win1 0 ,
200 120 win-new win1 !
word One count win1 @ win-title!
: redraw1 ( win -- ) drop ;
['] redraw1 win1 @ win-redraw!
100 win1 @ win-x! 60 win1 @ win-y! win1 @ win-open
." B1" cr
65280 ?imm32 h. cr ." B1b" cr
code movrot r0 65280 # mov, r0 tos-push next end-code
." B2" cr
' movrot pfa >r r@ @ h. r@ 4 + @ h. r@ 8 + @ h. r@ 12 + @ h. r> drop cr ." B3" cr
." C1" cr 0 0 639 399 clip! 100 60 299 179 fillrect0 ." C2" cr
120 90 60 20 fillrect0 ." C3" cr
." A1" cr
fb-clear ." A2" cr
begin-redraw ." A3" cr
next-redraw . ." A4" cr
next-redraw . ." A5" cr
menu-bar! ." A6" cr
wm-redraw-all ." A7" cr
movrot h. cr ." B4" cr
." DONE" cr
