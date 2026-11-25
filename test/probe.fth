\ TEMPORARY probe v10: dump wm-list links; menu-bar! redefined with marks
load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
640 400 8 fb-alloc .
fb-clear
wm-init
create win1 0 ,
create win2 0 ,
200 120 win-new win1 !
word One count win1 @ win-title!
100 win1 @ win-x! 60 win1 @ win-y! win1 @ win-open
150 100 win-new win2 !
word Two count win2 @ win-title!
158 win2 @ win-x! 108 win2 @ win-y! win2 @ win-open
wm-list @ h. cr
wm-list @ @ h. cr
wm-list @ @ @ h. cr
: mb2 ( -- ) 0 15 fb-w @ 1- 15 line ." L1" cr 4 mb-x ! wm-list @ begin dup while dup win-title@ mb-x @ 0 text ." L2" cr win-title@ nip 8 * 16 + mb-x +! @ repeat drop ." L3" cr ;
mb2 ." M9" cr
menu-bar! ." M8" cr
." DONE" cr
