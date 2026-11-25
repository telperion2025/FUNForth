\ TEMPORARY probe v18: menu-bar! combined loop body
load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
640 400 8 fb-alloc .
fb-clear
wm-init
create win1 0 ,
200 120 win-new win1 !
word One count win1 @ win-title!
100 win1 @ win-x! 60 win1 @ win-y! win1 @ win-open
: mb4 ( -- ) wm-list @ begin dup while dup win-title@ mb-x @ 0 text win-title@ nip 8 * 16 + mb-x +! @ repeat drop ;
4 mb-x !
mb4 ." E" cr
menu-bar! ." M9" cr
." DONE" cr
