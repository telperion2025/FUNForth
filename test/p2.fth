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
' hello-redraw hw @ win-redraw!
220 hw @ win-x!
100 hw @ win-y!
hw @ win-open
." A" cr
begin-redraw
." B" cr
next-redraw .
." C" cr
menu-bar!
." D" cr
wm-redraw-all
." E" cr
." DONE" cr
