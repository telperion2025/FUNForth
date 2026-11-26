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
0 250 165 3 ev-push
0 250 165 4 ev-push
0 250 165 3 ev-push
0 250 165 4 ev-push
0 250 165 3 ev-push
0 250 165 4 ev-push
." P1" cr gui-poll ." Q1" cr
." P2" cr gui-poll ." Q2" cr
." P3" cr gui-poll ." Q3" cr
." P4" cr gui-poll ." Q4" cr
." P5" cr gui-poll ." Q5" cr
." P6" cr gui-poll ." Q6" cr
counter @ . cr
." DONE" cr
