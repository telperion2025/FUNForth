\ TEMPORARY probe v11: real menu-bar! + minimal cpsid dis1 (short lines!)
load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
load asm.fth
640 400 8 fb-alloc .
fb-clear
wm-init
create win1 0 ,
200 120 win-new win1 !
word One count win1 @ win-title!
100 win1 @ win-x! 60 win1 @ win-y! win1 @ win-open
menu-bar! ." M9" cr
code m1 128 cpsid, next end-code
' m1 pfa @ h. cr
' m1 pfa dis1 2drop cr ." C4" cr
see m1 ." C5" cr
." DONE" cr
