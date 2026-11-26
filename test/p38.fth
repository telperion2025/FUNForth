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
create w2 0 ,
200 120 win-new w2 !
word Plain count w2 @ win-title!
60 w2 @ win-x! 40 w2 @ win-y!
hello
w2 @ win-open
wm-redraw-all
hello-win @ wm-focus !
." vars:" cr
btn-cnt @ . b-x @ . b-y @ . b-w @ . b-h @ . btn-t @ h. cr
." slot0:" cr
btn-tab @ . btn-tab 4 + @ . btn-tab 8 + @ . btn-tab 12 + @ . btn-tab 16 + @ h. btn-tab 20 + @ h. cr
." slot1:" cr
btn-tab 24 + @ . btn-tab 28 + @ . btn-tab 32 + @ . btn-tab 36 + @ . btn-tab 40 + @ h. btn-tab 44 + @ h. cr
." slot2:" cr
btn-tab 48 + @ . btn-tab 52 + @ . btn-tab 56 + @ . btn-tab 60 + @ . btn-tab 64 + @ h. btn-tab 68 + @ h. cr
create rt 0 , 0 ,
: rt-test ( -- ) 7 rt 4 + >r r@ ! r> drop ;
rt-test
." rt:" rt 4 + @ . cr
." DONE" cr
