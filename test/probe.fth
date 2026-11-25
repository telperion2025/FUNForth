\ TEMPORARY probe v16: down-label cells + menu-bar! mb-x update piece
load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
load asm.fth
640 400 8 fb-alloc .
fb-clear
wm-init
code down r0 5 # mov, label top ' top mark r0 r0 1 # sub, r0 0 # cmp, ne top b, r0 tos-push next end-code
' down pfa >r r@ @ h. r@ 4 + @ h. r@ 8 + @ h. r@ 12 + @ h. r@ 16 + @ h. r@ 20 + @ h. r@ 24 + @ h. r> drop cr
' top pfa @ h. ' top pfa 4 + @ h. cr
down . ." D" cr
create win1 0 ,
200 120 win-new win1 !
word One count win1 @ win-title!
100 win1 @ win-x! 60 win1 @ win-y! win1 @ win-open
: mb3 ( -- ) wm-list @ begin dup while win-title@ nip 8 * 16 + mb-x +! @ repeat drop ;
4 mb-x !
mb3 ." C" cr
menu-bar! ." M9" cr
." DONE" cr
