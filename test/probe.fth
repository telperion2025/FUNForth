\ TEMPORARY probe v12: minimal colon loop + cpsid dis1 (short lines)
load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
load asm.fth
640 400 8 fb-alloc .
fb-clear
wm-init
code m1 128 cpsid, next end-code
' m1 pfa dis1 2drop cr ." C4" cr
' m1 pfa 4 + dis1 2drop cr ." C5" cr
create win1 0 ,
200 120 win-new win1 !
word One count win1 @ win-title!
100 win1 @ win-x! 60 win1 @ win-y! win1 @ win-open
: lp ( -- ) wm-list @ begin dup while @ repeat drop ;
lp ." LP" cr
menu-bar! ." M9" cr
." DONE" cr
