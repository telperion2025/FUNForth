\ term.fth - M18 terminal windows in the WM.
\ requires fb.fth font8x16.fth vdi.fth wm.fth (tasks.fth via BOOT.LST).
\ Terminal record = window record (40B) + +40 cols +44 rows +48 cx +52 cy
\ +56 buf[80*24 bytes]; record 1976B, pool of 3. flags: bit1 cell-snap, bit2
\ is-term. Each terminal owns a back-buffer; term-redraw blits it (char per
\ cell) into the window content clip set by next-redraw.

create term-pool 3 1976 * allot
create term-next term-pool ,
create term-rsz 0 ,

: term-redraw ( w -- )
  >r
  r@ 44 @ 0 do                              \ rows
    r@ 40 @ 0 do                            \ cols
      r@ 56 + j r@ 40 + @ * i + c@          \ buf[j*cols+i]
      r@ win-x@ i 8 * + r@ win-y@ 16 + j 16 * + char
    loop
  loop
  r> drop ;

: term-scroll ( t -- )
  >r
  r@ 56 + r@ 40 + @ + r@ 56 + r@ 40 + @ r@ 44 + @ 1- * move
  r@ 56 + r@ 40 + @ r@ 44 + @ 1- * + r@ 40 + @ 32 fill
  r> drop ;
: term-newline ( t -- )
  >r
  0 r@ 48 + !                               \ cx = 0
  r@ 52 + dup @ 1+ swap !                   \ cy++
  r@ 52 + @ r@ 44 + @ = if r@ term-scroll then
  r> drop ;
: term-bs ( t -- )
  >r
  r@ 48 + dup @ 0> if 1- swap ! then
  r> drop ;
: term-emit ( c -- )                       \ into focused terminal
  wm-focus @ dup 0= if 2drop exit then
  dup 4 + @ 4 and 0= if 2drop exit then
  >r
  dup 13 = over 10 = or if drop r@ term-newline r> drop exit then
  dup 8 = if drop r@ term-bs r> drop exit then
  r@ 56 + r@ 52 + @ r@ 40 + @ * r@ 48 + @ + c!
  r@ 48 + dup @ 1+ swap !                   \ cx++
  r@ 48 + @ r@ 40 + @ = if r@ term-newline then
  r> drop
  wm-request-redraw ;
: term-type ( addr len -- ) 0 do dup i + c@ term-emit loop drop ;

: term-open-count ( -- n )
  0 wm-list @ begin dup while dup 4 + @ 4 and if 1+ then @ repeat drop ;
: term-close-check ( win -- )              \ close refused on the last terminal
  term-open-count 1 > if wm-do-close else ." last-term" drop then ;

: term-new ( cols rows -- term )
  term-next @ dup >r 1976 + term-next !
  r@ 1976 0 fill
  r@ 44 + ! r@ 40 + !                       \ rows -> +44, cols -> +40
  r@ 40 + @ 8 * r@ 16 + !                   \ win w = cols*8
  r@ 44 + @ 16 * 16 + r@ 20 + !             \ win h = rows*16 + 16 (title bar)
  6 r@ 4 + !                                \ flags: cell-snap + is-term
  ['] term-redraw r@ 24 + !
  ['] term-close-check r@ 36 + !
  r> ;

\ cell-snapped resize: term-resize-start, term-arrow ( dx dy -- in cells ), end
: term-resize-start ( -- )
  wm-focus @ dup 0= if drop exit then
  dup 4 + @ 4 and 0= if drop exit then
  term-rsz ! ;
: term-arrow ( dx dy -- )
  term-rsz @ 0= if 2drop exit then
  >r rot r@ 40 + @ + dup 4 < if drop 4 then dup 80 > if drop 80 then r@ 40 + !
  r@ 44 + @ + dup 2 < if drop 2 then dup 24 > if drop 24 then r@ 44 + !
  r@ 40 + @ 8 * r@ 16 + !
  r@ 44 + @ 16 * 16 + r@ 20 + !
  0 r@ 48 + ! 0 r@ 52 + !
  r> drop
  wm-redraw-all ;
: term-resize-end ( -- ) 0 term-rsz ! ;
