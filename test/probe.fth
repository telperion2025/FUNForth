\ TEMPORARY probe v9: 2-window menu-bar! + minimal cpsid dis1
load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
load asm.fth
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
." M0" cr
0 15 fb-w @ 1- 15 line ." M1" cr
4 mb-x !
wm-list @ begin dup while ." W1" cr dup win-title@ mb-x @ 0 text ." W2" cr win-title@ nip 8 * 16 + mb-x +! @ repeat drop ." W3" cr
menu-bar! ." M2" cr
code m1 128 cpsid, next end-code
' m1 pfa @ h. cr
' m1 pfa dis1 2drop cr ." C4" cr
' m1 pfa 4 + dis1 2drop cr ." C5" cr
." DONE" cr
