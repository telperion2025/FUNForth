\ TEMPORARY probe v17: menu-bar! remaining piece (mb-x update in loop)
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
: mb3 ( -- ) wm-list @ begin dup while win-title@ nip 8 * 16 + mb-x +! @ repeat drop ;
4 mb-x !
mb3 ." C" cr
menu-bar! ." M9" cr
." DONE" cr
