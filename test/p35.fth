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
wm-list @ h. cr
hello-win @ h. cr
hello-win @ win-x@ . hello-win @ win-y@ . hello-win @ win-w@ . hello-win @ win-h@ . cr
w2 @ win-x@ . w2 @ win-y@ . cr
250 165 220 100 200 150 in-rect? . cr
250 165 win-at h. cr
wm-focus @ h. cr
wm-list @ @ h. cr
." DONE" cr
