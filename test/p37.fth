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
btn-cnt @ . cr
btn-tab @ . btn-tab 4 + @ . btn-tab 8 + @ . btn-tab 12 + @ . btn-tab 20 + @ . cr
: tdo ( -- ) btn-cnt @ 0 do i 24 * btn-tab + gp-b ! ." d1" cr gp-b @ 20 + @ execute ." d2" cr loop ;
tdo
." DONE" cr
counter @ . cr
