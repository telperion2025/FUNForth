load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
load term.fth
640 400 8 fb-alloc .
fb-clear
wm-init
create t1 0 ,
8 3 term-new t1 !
word T3 count t1 @ win-title!
320 t1 @ win-x!
30 t1 @ win-y!
t1 @ win-open
." P1" cr
begin-redraw
." P2" cr
next-redraw .
." P3" cr
next-redraw .
." P4" cr
menu-bar!
." P5" cr
." DONE" cr
