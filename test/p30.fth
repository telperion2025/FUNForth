load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
load term.fth
load gui.fth
load hello.fth
640 400 8 fb-alloc .
fb-clear
wm-init
create hw 0 ,
200 150 win-new hw !
word Hello count hw @ win-title!
220 hw @ win-x!
100 hw @ win-y!
hw @ win-open
." A" cr
: pb-1 ( a l x y w h xt -- ) btn-t ! b-h ! b-w ! b-y ! b-x ! 2drop ." z1" cr ;
: pb-2 ( -- ) wm-focus @ 0= if exit then wm-focus @ win-x@ b-x @ + b-x ! wm-focus @ win-y@ 16 + b-y @ + b-y ! ." z2" cr ;
: pb-3 ( -- ) btn-cnt @ 8 < if btn-cnt @ 1+ btn-cnt ! btn-cnt @ 24 * btn-tab + dup >r btn-t @ r@ 20 + ! wm-focus @ r@ 16 + ! b-h @ r@ 12 + ! b-w @ r@ 8 + ! b-y @ r@ 4 + ! b-x @ r@ ! r> drop then ." z3" cr ;
: pb-4 ( -- ) b-x @ b-y @ b-x @ b-w @ + 1- b-y @ b-h @ + 1- rect ." z4" cr ;
: pb-5 ( a l -- ) b-x @ 4 + b-y @ 4 + text ." z5" cr ;
t-count count 10 40 80 24 ['] counter-inc pb-1
." B" cr
pb-2
." C" cr
pb-3
." D" cr
pb-4
." E" cr
t-count count pb-5
." F" cr
." DONE" cr
