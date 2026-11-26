\ TEMPORARY probe v20: menu-bar! loop tail bisect (mbA/mbB/mbC)
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
: mbA ( -- ) wm-list @ begin dup while dup win-title@ mb-x @ 0 text win-title@ nip drop @ repeat drop ;
4 mb-x !
mbA ." A" cr
: mbB ( -- ) wm-list @ begin dup while dup win-title@ nip drop 8 * 16 + mb-x +! @ repeat drop ;
mbB ." B" cr
: mbC ( -- ) wm-list @ begin dup while dup win-title@ mb-x @ 0 text drop drop 8 * 16 + mb-x +! @ repeat drop ;
mbC ." C" cr
." DONE" cr
