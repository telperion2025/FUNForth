load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
load term.fth
640 400 8 fb-alloc .
fb-clear
wm-init
create t1 0 ,
8 3 term-new t1 !
word T3 count t1 @ win-title!
320 t1 @ win-x!
30 t1 @ win-y!
t1 @ win-open
." A" cr
: rd-g ( w -- )
  tr-w !
  tr-w @ 44 + @ ." rows=" . cr
  tr-w @ 44 @ 0 do
    ." o" i . cr
    tr-w @ 40 @ 0 do
      ." i" i . cr
      tr-w @ 56 + j tr-w @ 40 + @ * i + c@ drop
    loop
  loop
  ." r1" cr ;
t1 @ rd-g
." B" cr
." DONE" cr
