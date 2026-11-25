\ TEMPORARY probe v5: execute-of-redraw-xt + lsm cell dump
load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
load asm.fth
depth . cr
640 400 8 fb-alloc .
fb-clear
wm-init
create win1 0 ,
200 120 win-new win1 !
word One count win1 @ win-title!
: redraw1 ( win -- ) drop ;
['] redraw1 win1 @ win-redraw!
100 win1 @ win-x! 60 win1 @ win-y! win1 @ win-open
." E0" cr depth . cr
." E1" cr ' redraw1 h. cr
wm-list @ wm-cur ! wm-cur @ dup wm-win ! @ wm-cur ! wm-win @ win-redraw@ h. cr ." E2" cr
0 ' redraw1 execute ." E3" cr
' redraw1 execute ." E4" cr
wm-win @ dup win-redraw@ execute ." E5" cr
wm-win @ win-redraw@ execute ." E6" cr
." E7" cr depth . cr
create lsbuf 8 allot
code lsm ' lsbuf pfa lit, r2 tos-pop r1 5 # mov, ib r2 2 stm, r2 2 ldm, r1 tos-push next end-code
." L0" cr ' lit h. cr ' lsbuf pfa h. cr
' lsm pfa >r r@ @ h. r@ 4 + @ h. r@ 8 + @ h. r@ 12 + @ h. r@ 16 + @ h. r@ 20 + @ h. r@ 24 + @ h. r> drop cr ." L1" cr
lsm . ." L2" cr
." DONE" cr
