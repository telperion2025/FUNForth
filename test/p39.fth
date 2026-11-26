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
: gp3 ( x y -- )
  btn-cnt @ 0 do
    ." i=" i . cr
    i 24 * btn-tab + gp-b !
    ." b=" gp-b @ . gp-b @ @ . gp-b @ 4 + @ . gp-b @ 8 + @ . gp-b @ 12 + @ . cr
    2dup gp-b @ @ gp-b @ 4 + @ gp-b @ 8 + @ gp-b @ 12 + @ in-rect? . cr
  loop
  2drop ;
250 165 gp3
250 165 230 156 80 24 in-rect? . cr
." DONE" cr
