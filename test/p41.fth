load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
load term.fth
load gui.fth
load hello.fth
640 400 8 fb-alloc .
fb-clear
wm-init
create w2 0 ,
200 120 win-new w2 !
word Plain count w2 @ win-title!
60 w2 @ win-x! 40 w2 @ win-y!
hello
w2 @ win-open
wm-redraw-all
hello-win @ wm-focus !
: gp4 ( x y -- )
  gp-y ! gp-x !
  gp-x @ gp-y @ win-at dup 0= if 2drop exit then
  gp-win ! ." g1" cr
  gp-x @ gp-y @ gp-win @ win-x@ gp-win @ win-w@ + 16 - gp-win @ win-y@ 16 16 in-rect? if gp-win @ win-close exit then
  ." g2" cr
  gp-win @ wm-focus @ = if
    ." g3" cr
    btn-cnt @ 0 do
      i 24 * btn-tab + gp-b ! ." g4" cr
      gp-x @ gp-y @ gp-b @ @ gp-b @ 4 + @ gp-b @ 8 + @ gp-b @ 12 + @ in-rect? if
        ." g5" cr
        gp-b @ 20 + @ execute ." g6" cr
        unloop exit
      then
    loop
  then
  ." g7" cr ;
250 165 gp4
." ---" cr
250 165 gp4
." DONE" cr
counter @ . cr
