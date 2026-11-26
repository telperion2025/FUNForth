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
: hb-1 ( w -- ) drop t-count count 10 40 80 24 ['] counter-inc button ." y1" cr ;
' hb-1 hw @ win-redraw!
hw @ wm-win !
clip>
hw @ dup win-redraw@ execute
." B" cr
: hb-2 ( w -- ) drop 230 156 309 179 rect ." y2" cr ;
' hb-2 hw @ win-redraw!
hw @ dup win-redraw@ execute
." C" cr
: hb-3 ( w -- ) drop t-count count 234 160 text ." y3" cr ;
' hb-3 hw @ win-redraw!
hw @ dup win-redraw@ execute
." D" cr
." DONE" cr
