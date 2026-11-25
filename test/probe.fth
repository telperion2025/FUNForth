\ TEMPORARY probe v7: dis1-on-cpsid + menu-bar! bisect
load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
load asm.fth
640 400 8 fb-alloc .
fb-clear
wm-init
code misc 0 bkpt, dsb, dmb, isb, 128 cpsid, 128 cpsie, next end-code
' misc pfa >r r@ @ h. r@ 4 + @ h. r@ 8 + @ h. r@ 12 + @ h. r@ 16 + @ h. r@ 20 + @ h. r@ 24 + @ h. r> drop cr ." D0" cr
' misc pfa dis1 2drop cr ." D1" cr
' misc pfa 16 + dis1 2drop cr ." D2" cr
' misc pfa 20 + dis1 2drop cr ." D3" cr
create win1 0 ,
create win2 0 ,
200 120 win-new win1 !
word One count win1 @ win-title!
: redraw1 ( win -- ) drop ;
' redraw1 win1 @ win-redraw!
100 win1 @ win-x! 60 win1 @ win-y! win1 @ win-open
150 100 win-new win2 !
word Two count win2 @ win-title!
: redraw2 ( win -- ) drop ;
' redraw2 win2 @ win-redraw!
158 win2 @ win-x! 108 win2 @ win-y! win2 @ win-open
0 15 fb-w @ 1- 15 line ." M1" cr
4 mb-x !
wm-list @ begin dup while dup win-title@ mb-x @ 0 text ." M2" cr win-title@ nip 8 * 16 + mb-x +! @ repeat drop ." M3" cr
." DONE" cr
