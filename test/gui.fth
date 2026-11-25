\ M17 WM core test: windows, menu bar, redraw protocol, XOR drag, focus cycle
load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
640 400 8 fb-alloc .
fb-clear
wm-init
create win1 0 ,
create win2 0 ,
200 120 win-new win1 !
word One count win1 @ win-title!
: redraw1 ( win -- ) drop 120 90 60 20 fillrect ;
['] redraw1 win1 @ win-redraw!
100 win1 @ win-x! 60 win1 @ win-y! win1 @ win-open
win1 @ win-x@ . win1 @ win-y@ .
150 100 win-new win2 !
word Two count win2 @ win-title!
: redraw2 ( win -- ) drop 168 130 30 30 rect ;
['] redraw2 win2 @ win-redraw!
158 win2 @ win-x! 108 win2 @ win-y! win2 @ win-open
wm-redraw-all
\ scripted drag of focused win2: 'd' starts XOR outline, arrows move, CR commits
100 wm-key
27 wm-key 91 wm-key 68 wm-key
27 wm-key 91 wm-key 65 wm-key
13 wm-key
win2 @ win-x@ . win2 @ win-y@ .
win1 @ win-x@ . win1 @ win-y@ .
\ TAB cycles focus to win1
9 wm-key
wm-focus @ win1 @ = .
wm-redraw-all
\ close win1: focus falls back to none
win1 @ win-close
wm-focus @ 0= .
wm-redraw-all
." END-GUI"
