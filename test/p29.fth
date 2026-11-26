load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
load term.fth
640 400 8 fb-alloc .
fb-clear
wm-init
create t3 0 ,
8 3 term-new t3 !
word T3 count t3 @ win-title!
320 t3 @ win-x!
30 t3 @ win-y!
t3 @ win-open
t3 @ wm-focus !
word HI count term-type
." A" cr
t3 @ 56 + @ . cr
t3 @ 57 + @ . cr
t3 @ 40 + @ . cr
t3 @ 44 + @ . cr
t3 @ 48 + @ . cr
t3 @ 52 + @ . cr
wm-redraw-all
." B" cr
t3 @ 56 + @ . cr
." DONE" cr
