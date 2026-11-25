\ TEMPORARY probe v6: bisect wm-redraw-all with correct xt store
load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
640 400 8 fb-alloc .
fb-clear
wm-init
create win1 0 ,
create win2 0 ,
200 120 win-new win1 !
word One count win1 @ win-title!
: redraw1 ( win -- ) drop 120 90 180 110 fillrect ;
' redraw1 win1 @ win-redraw!
100 win1 @ win-x! 60 win1 @ win-y! win1 @ win-open
150 100 win-new win2 !
word Two count win2 @ win-title!
: redraw2 ( win -- ) drop 168 130 198 160 rect ;
' redraw2 win2 @ win-redraw!
158 win2 @ win-x! 108 win2 @ win-y! win2 @ win-open
." P1" cr
fb-clear ." P2" cr
begin-redraw ." P3" cr
next-redraw . ." P4" cr
next-redraw . ." P5" cr
next-redraw . ." P6" cr
menu-bar! ." P7" cr
wm-redraw-all ." P8" cr
." DONE" cr
