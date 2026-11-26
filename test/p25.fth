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
wm-list @ wm-cur !
wm-cur @ dup wm-win ! @ wm-cur !
0 0 fb-w @ 1- fb-h @ 1- clip!
wm-win @ win-x@ wm-win @ win-y@ wm-win @ win-w@ wm-win @ win-x@ + 1- wm-win @ win-y@ wm-win @ win-h@ + 1- fillrect0
." B" cr
wm-win @ wm-chrome
." C" cr
clip>
." D" cr
wm-win @ dup win-redraw@ execute
." E" cr
menu-bar!
." F" cr
." DONE" cr
