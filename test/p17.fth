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
." A" cr
: rd-a ( w -- ) drop ." x1" cr ;
t1 @ rd-a
." B" cr
: rd-b ( w -- ) drop 8 0 do i . loop cr ;
t1 @ rd-b
." C" cr
: rd-c ( w -- ) drop 3 0 do 8 0 do i . j . loop loop cr ;
t1 @ rd-c
." D" cr
t1 @ term-redraw
." E" cr
." DONE" cr
