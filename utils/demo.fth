\ ---- M25: demo pack (hello window + plain window on the WM) ----
load fb.fth
load font8x16.fth
load vdi.fth
load wm.fth
load term.fth
load gui.fth
load hello.fth
create t-demo 16 allot
word Demo count t-demo swap move
: demo ( -- )
  640 400 8 fb-alloc drop
  fb-clear
  wm-init
  hello
  200 120 win-new dup >r
  t-demo count r@ win-title!
  60 r@ win-x! 40 r@ win-y!
  r> win-open
  wm-redraw-all
  ." DEMO-READY" cr ;
