\ ---- M11: console over the framebuffer: 80x25 grid of 8x16 cells, 2 Hz cursor blink ----
\ requires fb.fth (fb-addr fb-pitch fb-h), vdi.fth (char invert-rect pixel-clear),
\ font8x16.fth and timer.fth (millis). 640x400 fb = exactly 80x25 cells.
create fb-cx 0 ,  create fb-cy 0 ,  create fb-last 0 ,  create fb-inv 0 ,

create cr-x0 0 , create cr-y0 0 , create cr-x1 0 , create cr-y1 0 ,
: clear-rect ( x0 y0 x1 y1 -- )
  cr-y1 ! cr-x1 ! cr-y0 ! cr-x0 !
  cr-y1 @ 1+ cr-y0 @ do
    cr-x1 @ 1+ cr-x0 @ do
      i j pixel-clear
    loop
  loop ;

: fb-scroll ( -- )                      \ shift rows up one cell, clear bottom row
  fb-addr @ fb-pitch @ 16 * +           \ src = fb + pitch*16
  fb-addr @                             \ dst = fb
  fb-h @ 16 - fb-pitch @ *              \ n = (h-16)*pitch
  move
  fb-addr @ fb-h @ 16 - fb-pitch @ * +  \ last row start
  fb-pitch @ 16 * 0 fill ;

: fb-cursor ( -- )                      \ toggle XOR cursor on the current cell
  fb-cx @ 8 * fb-cy @ 16 *  fb-cx @ 8 * 7 + fb-cy @ 16 * 15 + invert-rect
  fb-inv @ 0= fb-inv ! ;

: fb-cursor-off ( -- )                  \ un-invert the cursor if it is shown
  fb-inv @ if fb-cursor then ;

: fb-newline ( -- )
  fb-cursor-off
  0 fb-cx !
  fb-cy @ 1+ dup 25 = if drop fb-scroll 24 then fb-cy ! ;

: fb-backspace ( -- )
  fb-cursor-off
  fb-cx @ 0> if
    fb-cx @ 1- fb-cx !
    fb-cx @ 8 * fb-cy @ 16 *  fb-cx @ 8 * 7 + fb-cy @ 16 * 15 + clear-rect
  then ;

: fb-emit ( c -- )                      \ CR = newline; LF/backspace/ctrl handled
  dup 13 = if drop fb-newline exit then
  dup 10 = if drop exit then
  dup 8 = if drop fb-backspace exit then
  dup 32 < if drop exit then
  fb-cursor-off
  fb-cx @ 8 * fb-cy @ 16 * char
  fb-cx @ 1+ dup 80 = if drop fb-newline else fb-cx ! then ;

: fb-blink ( -- )                       \ 2 Hz blink via M7 timer
  millis fb-last @ - 500 < 0= if
    millis fb-last !
    fb-cursor
  then ;

: key-fb ( -- c )                       \ UART keys, blink while waiting
  begin
    key?-uart if key-uart exit then
    fb-blink
  again ;

: console-fb ( -- )                     \ select the fb console (emit + key)
  fb-clear
  0 fb-cx !  0 fb-cy !  0 fb-inv !  millis fb-last !
  ['] fb-emit con-emit!
  ['] key-fb  con-key! ;
