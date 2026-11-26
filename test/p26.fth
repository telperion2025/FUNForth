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
220 hw @ win-x!
100 hw @ win-y!
hw @ win-open
." A" cr
: hr-1 ( w -- ) drop ." x1" cr ;
' hr-1 hw @ win-redraw!
hw @ wm-win !
clip>
hw @ dup win-redraw@ execute
." B" cr
: hr-2 ( w -- ) drop t-hello count 10 10 wtext ." x2" cr ;
' hr-2 hw @ win-redraw!
hw @ dup win-redraw@ execute
." C" cr
: hr-3 ( w -- ) drop t-hello count 10 10 wtext t-count count 10 40 80 24 ['] counter-inc button ." x3" cr ;
' hr-3 hw @ win-redraw!
hw @ dup win-redraw@ execute
." D" cr
." DONE" cr
