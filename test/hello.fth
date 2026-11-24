\ M19 gui demo test: hello window + plain window, 3 scripted counter clicks,
\ close-box click closes the plain window
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
\ 3 clicks on the COUNT button (abs rect 230,156 80x24)
0 250 165 3 ev-push
0 250 165 4 ev-push
0 250 165 3 ev-push
0 250 165 4 ev-push
0 250 165 3 ev-push
0 250 165 4 ev-push
gui-poll gui-poll gui-poll gui-poll gui-poll gui-poll
counter @ .
\ click w2's close box (w2 at 60,40 200x120 -> box at 244,40 16x16)
0 250 45 3 ev-push
0 250 45 4 ev-push
gui-poll gui-poll
hello-win @ wm-list @ = .
wm-redraw-all
." END-HELLO"
