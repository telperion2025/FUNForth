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
wm-list @ wm-cur !
." B" cr
wm-cur @ dup wm-win ! @ wm-cur !
." C" cr
0 0 fb-w @ 1- fb-h @ 1- clip!
." D" cr
wm-win @ win-x@ wm-win @ win-y@ wm-win @ win-w@ wm-win @ win-x@ + 1- wm-win @ win-y@ wm-win @ win-h@ + 1- fillrect0
." E" cr
wm-win @ wm-chrome
." F" cr
clip>
." G" cr
wm-win @ win-redraw@ execute
." H" cr
menu-bar!
." I" cr
." DONE" cr
