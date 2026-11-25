\ TEMPORARY probe v8: menu-bar! body bisect + dis1 cps-branch pieces
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
." M0" cr
0 15 fb-w @ 1- 15 line ." M1" cr
4 mb-x !
wm-list @ begin dup while dup win-title@ mb-x @ 0 text ." M3" cr win-title@ nip 8 * 16 + mb-x +! @ repeat drop ." M4" cr
code misc 0 bkpt, dsb, dmb, isb, 128 cpsid, 128 cpsie, next end-code
' misc pfa 16 + @ ci ! ci @ h. cr ." C0" cr
ci @ 267386880 and 16777216 = . cr ." C1" cr
ci @ 262144 and . cr ." C2" cr
ci @ 448 and h. cr ." C3" cr
' misc pfa 16 + dis1 2drop cr ." C4" cr
." DONE" cr
