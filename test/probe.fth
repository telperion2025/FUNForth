\ TEMPORARY probe v15: re-test cps dis1 + menu-bar! pieces after ." align fix
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
see m1 ." C5" cr
create win1 0 ,
200 120 win-new win1 !
word One count win1 @ win-title!
100 win1 @ win-x! 60 win1 @ win-y! win1 @ win-open
: mb1 ( -- ) 0 15 fb-w @ 1- 15 line ;
mb1 ." A" cr
: mb2 ( -- ) wm-list @ begin dup while dup win-title@ mb-x @ 0 text @ repeat drop ;
mb2 ." B" cr
menu-bar! ." M9" cr
." DONE" cr
