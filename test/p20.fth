load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
640 400 8 fb-alloc .
fb-clear
wm-init
create win1 0 ,
200 120 win-new win1 !
' wm-do-close . cr
win1 @ . cr
win1 @ 36 + @ . cr
win1 @ 36 + @ ' wm-do-close = . cr
win1 @ 4 + @ . cr
win1 @ 16 + @ . cr
win1 @ 20 + @ . cr
." DONE" cr
