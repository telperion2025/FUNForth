\ gui.fth - M19 FORm API: needs, event queue (event?/event@), pointer state
\ (pointer-x pointer-y buttons), win-full, wtext, button click-regions,
\ close box, gui-poll dispatcher. requires fb font vdi wm. SD as GUI.FTH.

: needs ( -- ) word count 2dup find if drop 2drop else 2drop load-file then ;

\ ---- event queue: 16 slots x 4 cells (+0 key +4 x +8 y +12 type) ----
\ type: 1=key 2=move 3=press 4=release
create ev-queue 256 allot
create ev-head 0 , create ev-tail 0 ,
: ev-push ( key x y type -- )
  ev-tail @ 1+ 16 mod ev-head @ = if 2drop 2drop exit then   \ queue full: drop event
  ev-tail @ 16 * ev-queue + >r
  r@ 12 + ! r@ 8 + ! r@ 4 + ! r@ !
  ev-tail @ 1+ 16 mod ev-tail ! ;
: event? ( -- f ) ev-head @ ev-tail @ <> ;
: event@ ( -- key x y type )
  ev-head @ 16 * ev-queue + >r
  r@ @ r@ 4 + @ r@ 8 + @ r> 12 + @
  ev-head @ 1+ 16 mod ev-head ! ;

\ ---- pointer state ----
create ptr-x 0 , create ptr-y 0 , create ptr-btn 0 ,
: pointer-x ( -- x ) ptr-x @ ;
: pointer-y ( -- y ) ptr-y @ ;
: buttons ( -- b ) ptr-btn @ ;

\ ---- win-full: maximize/restore a win-pool window ----
create full-save 8 16 * allot
create fs 0 ,
: win-full ( win -- )
  >r
  r@ 4 + @ 8 and if                       \ full -> restore
    r@ 4 + dup @ 8 invert and swap !
    r@ win-pool - 40 / 16 * full-save + fs !
    fs @ @ r@ win-x!
    fs @ 4 + @ r@ win-y!
    fs @ 8 + @ r@ 16 + !
    fs @ 12 + @ r@ 20 + !
  else
    r@ win-pool - 40 / 16 * full-save + fs !
    r@ win-x@ fs @ !
    r@ win-y@ fs @ 4 + !
    r@ win-w@ fs @ 8 + !
    r@ win-h@ fs @ 12 + !
    0 r@ win-x!
    16 r@ win-y!
    fb-w @ r@ 16 + !
    fb-h @ 16 - r@ 20 + !
    r@ 4 + dup @ 8 or swap !
  then
  r> drop
  wm-request-redraw ;

\ ---- wtext: text at (x,y) relative to focused window content ----
: wtext ( addr len x y -- )
  wm-focus @ 0= if 2drop 2drop exit then
  wm-focus @ >r
  swap r@ win-x@ + swap r@ win-y@ 16 + + text
  r> drop ;

\ ---- hit testing ----
create h-x 0 , create h-y 0 , create h-rx 0 , create h-ry 0 , create h-rw 0 , create h-rh 0 ,
: in-rect? ( x y rx ry rw rh -- f )
  h-rh ! h-rw ! h-ry ! h-rx ! h-y ! h-x !
  h-rx @ h-x @ < 0= h-x @ h-rx @ h-rw @ + < and
  h-ry @ h-y @ < 0= h-y @ h-ry @ h-rh @ + < and and ;
create at-win 0 ,
: win-at ( x y -- win )                     \ topmost window containing point
  0 at-win !
  wm-list @ begin dup while
    >r 2dup r@ win-x@ r@ win-y@ r@ win-w@ r@ win-h@ in-rect? if r@ at-win ! then r> drop @
  repeat drop 2drop at-win @ ;

\ ---- buttons: 8 slots x 24B (+0 x +4 y +8 w +12 h +16 win +20 xt), abs coords
create btn-tab 192 allot
create btn-cnt 0 ,
create btn-t 0 ,
create b-x 0 , create b-y 0 , create b-w 0 , create b-h 0 ,
: button ( addr len x y w h xt -- )         \ draw + register in focused window
  btn-t !
  b-h ! b-w ! b-y ! b-x !
  wm-focus @ 0= if 2drop exit then
  wm-focus @ win-x@ b-x @ + b-x !
  wm-focus @ win-y@ 16 + b-y @ + b-y !
  btn-cnt @ 8 < if
    btn-cnt @ 1+ btn-cnt !
    btn-cnt @ 24 * btn-tab + >r
    btn-t @ r@ 20 + !
    wm-focus @ r@ 16 + !
    b-h @ r@ 12 + !
    b-w @ r@ 8 + !
    b-y @ r@ 4 + !
    b-x @ r@ !
    r> drop
  then
  b-x @ b-y @ b-x @ b-w @ + 1- b-y @ b-h @ + 1- rect
  b-x @ 4 + b-y @ 4 + text ;

\ ---- dispatcher ----
create gp-win 0 , create gp-b 0 ,
: gui-press ( x y -- )    \ r@ is unusable inside do loops (reads loop params)
  2dup win-at dup 0= if drop 2drop exit then
  gp-win !
  2dup gp-win @ win-x@ gp-win @ win-w@ + 16 - gp-win @ win-y@ 16 16 in-rect? if   \ close box
    gp-win @ win-close 2drop exit
  then
  gp-win @ wm-focus @ = if
    btn-cnt @ 0 do
      i 24 * btn-tab + gp-b !
      2dup gp-b @ @ gp-b @ 4 + @ gp-b @ 8 + @ gp-b @ 12 + @ in-rect? if
        2drop gp-b @ 20 + @ execute unloop exit
      then
    loop
  then
  2drop ;

: gui-poll ( -- )
  event? 0= if exit then
  event@
  dup 1 = if drop rot wm-key 2drop exit then
  dup 2 = if drop rot drop dup ptr-y ! ptr-x ! exit then
  dup 3 = if drop rot drop 1 ptr-btn ! gui-press exit then
  drop 2drop drop 0 ptr-btn ! ;

\ one task drives everything: redefine wm-poll to also drain the event queue
: wm-poll ( -- )
  wm-redraw-pend @ if 0 wm-redraw-pend ! wm-redraw-all then
  key? if key wm-key then
  event? if gui-poll then ;

: gui ;                                     \ marker so 'needs gui' is a no-op
