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
create pb-b 0 ,
200 150 win-new hw !
word Hello count hw @ win-title!
220 hw @ win-x!
100 hw @ win-y!
hw @ win-open
." A" cr
: pb-1 ( a l x y w h xt -- ) btn-t ! b-h ! b-w ! b-y ! b-x ! 2drop ." z1" cr ;
: pb-3 ( -- )
  btn-cnt @ 8 < if
    btn-cnt @ 1+ btn-cnt !
    btn-cnt @ 24 * btn-tab + pb-b !
    pb-b @ 20 + btn-t @ swap !
    pb-b @ 16 + wm-focus @ swap !
    pb-b @ 12 + b-h @ swap !
    pb-b @ 8 + b-w @ swap !
    pb-b @ 4 + b-y @ swap !
    pb-b @ b-x @ swap !
  then
  ." z3" cr ;
: pb-4 ( -- ) b-x @ b-y @ b-x @ b-w @ + 1- b-y @ b-h @ + 1- rect ." z4" cr ;
: pb-5 ( a l -- ) b-x @ 4 + b-y @ 4 + text ." z5" cr ;
t-count count 10 40 80 24 ['] counter-inc pb-1
." B" cr
pb-3
." C" cr
pb-4
." D" cr
t-count count pb-5
." E" cr
." DONE" cr
