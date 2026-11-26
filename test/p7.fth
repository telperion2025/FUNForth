load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
load term.fth
640 400 8 fb-alloc .
fb-clear
wm-init
create win1 0 ,
200 120 win-new win1 !
word One count win1 @ win-title!
: redraw1 ( win -- ) drop 120 90 180 110 fillrect ;
' redraw1 win1 @ win-redraw!
100 win1 @ win-x!
60 win1 @ win-y!
win1 @ win-open
wm-redraw-all
." A" cr
." DONE" cr
