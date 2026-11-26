\ wm.fth - M17 window manager core: window records, menu bar, redraw
\ protocol, XOR-outline keyboard drag, one WM task owning redraw arbitration.
\ requires fb.fth font8x16.fth vdi.fth tasks.fth (all in BOOT.LST / loaded first).
\ Screen is 8bpp black/white (palette 0=black 1=white); VDI pixel = white.
\
\ Window record (v1.0 10.1-style), 40 bytes, pool of 8:
\   +0 link (toward top; 0=none)   +4 flags (bit0 open)   +8 x   +12 y
\   +16 w  +20 h   +24 redraw-xt ( win -- )   +28 title-addr  +32 title-len
\   +36 close-xt (0=none)
\ Window list: wm-list head = BOTTOM window, tail = top. Focus = wm-focus.
\ Title bar = top 16 px of the window rect; content clip = rest.

create win-pool 8 40 * allot
create win-next win-pool ,
create wm-list 0 ,
create wm-focus 0 ,
create wm-cur 0 ,
create wm-win 0 ,
create wm-drag 0 ,
create wm-dx 0 ,
create wm-dy 0 ,
create wm-redraw-pend 0 ,
create key-st 0 ,
create mb-x 0 ,

\ ---- record accessors ----
: win-x@ ( w -- x ) 8 + @ ;    : win-x! ( x w -- ) 8 + ! ;
: win-y@ ( w -- y ) 12 + @ ;   : win-y! ( y w -- ) 12 + ! ;
: win-w@ ( w -- w ) 16 + @ ;
: win-h@ ( w -- h ) 20 + @ ;
: win-flags@ ( w -- f ) 4 + @ ;
: win-title! ( ta tl w -- ) >r r@ 32 + ! r> 28 + ! ;
: win-title@ ( w -- ta tl ) dup 28 + @ swap 32 + @ ;
: win-redraw! ( xt w -- ) 24 + ! ;
: win-redraw@ ( w -- xt ) 24 + @ ;
: win-close-xt! ( xt w -- ) 36 + ! ;

\ ---- allocation + list (head = bottom, tail = top) ----
: wm-unlink ( win -- )
  wm-list @ over = if @ wm-list ! exit then
  wm-list @ begin dup 0= if 2drop exit then 2dup @ <> while @ repeat over @ swap ! drop ;

: wm-request-redraw ( -- ) 1 wm-redraw-pend ! ;

: wm-do-close ( win -- )
  dup wm-unlink
  dup 4 + dup @ 1 invert and swap !
  dup wm-focus @ = if 0 wm-focus ! then
  drop
  wm-request-redraw ;

: win-new ( w h -- win )
  win-next @ dup >r 40 + win-next !
  r@ 40 0 fill
  r@ 20 + ! r@ 16 + !
  ['] wm-do-close r@ 36 + !
  r> ;
: win-close ( win -- ) dup 36 + @ swap execute ;   \ via close-xt (may refuse)

: wm-append ( win -- )            \ link at tail (top)
  dup wm-list @ 0= if drop wm-list ! exit then
  drop
  wm-list @ begin dup @ while @ repeat ! ;

: win-open ( win -- )
  dup 4 + dup @ 1 or swap !
  dup wm-append
  wm-focus !
  wm-request-redraw ;
: win-top ( win -- )
  dup wm-unlink
  dup wm-append
  wm-focus !
  wm-request-redraw ;
: wm-next-focus ( -- )
  wm-focus @ 0= if wm-list @ wm-focus ! exit then
  wm-focus @ @ dup 0= if drop wm-list @ then wm-focus ! ;

\ ---- drawing ----
: fillrect0 ( x0 y0 x1 y1 -- )    \ black fill (clip-respecting, 8bpp row fill)
  r-y1 ! r-x1 ! r-y0 ! r-x0 !
  r-y1 @ 1+ r-y0 @ do
    i clip-y0 @ < 0= i clip-y1 @ > 0= and if
      r-x0 @ clip-x0 @ max f-x0 !
      r-x1 @ clip-x1 @ min f-x1 !
      fb-depth @ 8 = if
        f-x0 @ f-x1 @ > 0= if
          i fb-pitch @ * fb-addr @ + f-x0 @ + f-x1 @ f-x0 @ - 1+ 0 fill
        then
      else
        r-x1 @ 1+ r-x0 @ do i j pixel-clear loop
      then
    then
  loop ;

: wm-chrome ( win -- )            \ clip must be full-screen; draws frame+title
  >r
  r@ win-x@ r@ win-y@ r@ win-w@ r@ win-x@ + 1- r@ win-y@ r@ win-h@ + 1- rect
  r@ win-x@ r@ win-y@ 16 + r@ win-w@ r@ win-x@ + 1- r@ win-y@ 16 + line
  r@ win-title@ r@ win-x@ 2 + r@ win-y@ text
  r> drop ;

: menu-bar! ( -- )
  0 15 fb-w @ 1- 15 line
  4 mb-x !
  wm-list @ begin dup while
    dup win-title@ mb-x @ 0 text
    dup win-title@ nip 8 * 16 + mb-x +!
    @
  repeat drop ;

\ ---- redraw protocol: begin-redraw ... next-redraw (clip> re-asserts clip) ----
: begin-redraw ( -- ) wm-list @ wm-cur ! ;
: clip> ( -- )                    \ content clip of the current redraw window
  wm-win @ win-x@ wm-win @ win-y@ 16 + wm-win @ win-w@ wm-win @ win-x@ + 1- wm-win @ win-y@ 16 + wm-win @ win-h@ + 1- clip! ;
: next-redraw ( -- f )            \ one window per call, bottom to top; f=0 at end
  wm-cur @ 0= if 0 exit then
  wm-cur @ dup wm-win ! @ wm-cur !
  0 0 fb-w @ 1- fb-h @ 1- clip!
  wm-win @ win-x@ wm-win @ win-y@ wm-win @ win-w@ wm-win @ win-x@ + 1- wm-win @ win-y@ wm-win @ win-h@ + 1- fillrect0
  wm-win @ wm-chrome
  clip>
  wm-win @ win-redraw@ execute
  -1 ;

: wm-redraw-all ( -- )
  fb-clear
  begin-redraw
  begin next-redraw 0= until
  menu-bar! ;

\ ---- XOR-outline keyboard drag (arrows = ESC [ A/B/C/D, CR commits, x cancels)
: drag-outline ( -- )
  wm-dx @ wm-dy @ wm-dx @ wm-drag @ win-w@ + 1- wm-dy @ wm-drag @ win-h@ + 1- invert-rect ;
: wm-drag-start ( -- )
  wm-focus @ 0= if exit then
  wm-focus @ dup wm-drag !
  dup win-x@ wm-dx ! win-y@ wm-dy !
  drag-outline ;
: wm-arrow ( dx dy -- )
  wm-drag @ 0= if 2drop exit then
  drag-outline
  rot wm-dx @ + wm-dx !
  wm-dy @ + wm-dy !
  drag-outline ;
: wm-drag-commit ( -- )
  wm-drag @ 0= if exit then
  drag-outline
  wm-drag @ 4 + @ 2 and if        \ cell-snap window (flags bit1): 8x16 grid
    wm-dx @ -8 and wm-dx !
    wm-dy @ -16 and wm-dy !
    wm-dy @ 16 < if 16 wm-dy ! then
  then
  wm-dx @ wm-drag @ win-x!
  wm-dy @ wm-drag @ win-y!
  0 wm-drag !
  wm-redraw-all ;
: wm-drag-cancel ( -- )
  wm-drag @ 0= if exit then
  drag-outline
  0 wm-drag ! ;

: wm-key ( c -- )
  key-st @ 0 = if
    dup 9 = if drop wm-next-focus exit then
    dup 100 = if drop wm-drag-start exit then
    dup 120 = if drop wm-drag-cancel exit then
    dup 13 = if drop wm-drag-commit exit then
    dup 27 = if drop 1 key-st ! exit then
    drop exit
  then
  key-st @ 1 = if
    91 = if 2 key-st ! else 0 key-st ! then exit
  then
  0 key-st !
  dup 65 = if drop -8 0 wm-arrow exit then
  dup 66 = if drop 8 0 wm-arrow exit then
  dup 67 = if drop 0 8 wm-arrow exit then
  dup 68 = if drop 0 -8 wm-arrow exit then
  drop ;

\ ---- one WM task owns redraw arbitration + events ----
: wm-poll ( -- )
  wm-redraw-pend @ if 0 wm-redraw-pend ! wm-redraw-all then
  key? if key wm-key then ;
1 task: wm-ua
: wm-loop ( -- ) begin wm-poll yield again ;
: wm-start ( -- ) ['] wm-loop wm-ua @ spawn ;

: wm-init ( -- )
  0 wm-list ! 0 wm-focus ! 0 wm-drag ! 0 wm-redraw-pend ! 0 key-st !
  menu-bar! ;
