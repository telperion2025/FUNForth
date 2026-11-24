\ M18 terminal windows test: 3 terminals, scripted typing, drag snap, resize,
\ close refused on last terminal
load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
load term.fth
640 400 8 fb-alloc .
fb-clear
wm-init
create t1 0 , create t2 0 , create t3 0 ,
10 4 term-new t1 !
word T1 count t1 @ win-title!
16 6 term-new t2 !
word T2 count t2 @ win-title!
8 3 term-new t3 !
word T3 count t3 @ win-title!
60 t1 @ win-x! 40 t1 @ win-y! t1 @ win-open
200 t2 @ win-x! 60 t2 @ win-y! t2 @ win-open
320 t3 @ win-x! 30 t3 @ win-y! t3 @ win-open
wm-redraw-all
t1 @ wm-focus !
word HELLO count term-type
t2 @ wm-focus !
word WORLD count term-type
wm-redraw-all
t3 @ wm-focus !
word HI count term-type
\ drag t3: right then down, commits snapped to the 8x16 cell grid
100 wm-key
27 wm-key 91 wm-key 67 wm-key
27 wm-key 91 wm-key 66 wm-key
13 wm-key
t3 @ win-x@ . t3 @ win-y@ .
\ resize t3 by one cell right and one cell down
term-resize-start
1 0 term-arrow
0 1 term-arrow
term-resize-end
t3 @ win-w@ . t3 @ win-h@ .
\ close t1 and t2 (allowed); t3 is the last terminal and must be refused
t1 @ win-close
t2 @ win-close
t3 @ win-close
wm-redraw-all
." END-TERM"
