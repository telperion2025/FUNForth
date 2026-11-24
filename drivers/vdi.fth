\ ---- M10: VDI over the 1 bpp framebuffer (MSB = leftmost pixel) ----
\ requires fb.fth (fb-addr fb-pitch fb-w fb-h) and font8x16 (font8x16)
create clip-x0 0 ,  create clip-y0 0 ,  create clip-x1 639 ,  create clip-y1 399 ,
: clip! ( x0 y0 x1 y1 -- ) clip-y1 ! clip-x1 ! clip-y0 ! clip-x0 ! ;

: px-addr ( x y -- a )                  \ 8bpp: byte per pixel; 1bpp: packs 8/byte
  fb-depth @ 8 = if
    fb-pitch @ * fb-addr @ + +
  else
    fb-pitch @ * fb-addr @ + swap 3 rshift +
  then ;
: px-mask ( x -- m ) fb-depth @ 8 = if drop 255 else 128 swap 7 and rshift then ;
: px-am ( x y -- a m ) 2dup px-addr >r px-mask r> nip ;

: in-clip? ( x y -- f )
  dup clip-y0 @ < if 2drop 0 exit then
  dup clip-y1 @ > if 2drop 0 exit then
  swap dup clip-x0 @ < if 2drop 0 exit then
  dup clip-x1 @ > if 2drop 0 exit then
  2drop -1 ;

: px! ( x y v -- )                      \ v!=0 -> set pixel, else clear
  >r
  fb-depth @ 8 = if
    px-addr r> swap c!                  \ 8bpp: store byte v
  else
    px-am r>                            \ 1bpp: a m v
    if swap dup @ rot or swap !         \ a = a|m
    else swap dup @ rot invert and swap ! \ a = a&~m
    then
  then ;

: pixel ( x y -- ) 2dup in-clip? if 1 px! else 2drop then ;
: pixel-clear ( x y -- ) 2dup in-clip? if 0 px! else 2drop then ;
: pixel-invert ( x y -- )
  2dup in-clip? if
    fb-depth @ 8 = if
      px-addr dup c@ 1 xor swap c!
    else
      px-am swap dup @ rot xor swap !
    then
  else 2drop then ;

create l-x0 0 , create l-y0 0 , create l-x1 0 , create l-y1 0 ,
create l-dx 0 , create l-dy 0 , create l-sx 0 , create l-sy 0 ,
create l-err 0 , create l-e2 0 ,
: line ( x0 y0 x1 y1 -- )               \ Bresenham
  l-y1 ! l-x1 ! l-y0 ! l-x0 !
  l-x1 @ l-x0 @ - abs l-dx !
  l-y1 @ l-y0 @ - abs negate l-dy !
  l-x1 @ l-x0 @ - 0< if -1 else 1 then l-sx !
  l-y1 @ l-y0 @ - 0< if -1 else 1 then l-sy !
  l-dx @ l-dy @ + l-err !
  begin
    l-x0 @ l-y0 @ pixel
    l-x0 @ l-x1 @ = l-y0 @ l-y1 @ = and if exit then
    l-err @ 2* l-e2 !
    l-e2 @ l-dy @ > if l-err @ l-dy @ + l-err ! l-x0 @ l-sx @ + l-x0 ! then
    l-e2 @ l-dx @ < if l-err @ l-dx @ + l-err ! l-y0 @ l-sy @ + l-y0 ! then
  again ;

create r-x0 0 , create r-y0 0 , create r-x1 0 , create r-y1 0 ,
create f-x0 0 , create f-x1 0 ,
: rect ( x0 y0 x1 y1 -- )
  r-y1 ! r-x1 ! r-y0 ! r-x0 !
  r-x0 @ r-y0 @ r-x1 @ r-y0 @ line
  r-x0 @ r-y1 @ r-x1 @ r-y1 @ line
  r-x0 @ r-y0 @ r-x0 @ r-y1 @ line
  r-x1 @ r-y0 @ r-x1 @ r-y1 @ line ;

: fillrect ( x0 y0 x1 y1 -- )     \ 8bpp: clip-clamped row fill; else per-pixel
  r-y1 ! r-x1 ! r-y0 ! r-x0 !
  r-y1 @ 1+ r-y0 @ do
    i clip-y0 @ < 0= i clip-y1 @ > 0= and if
      r-x0 @ clip-x0 @ max f-x0 !
      r-x1 @ clip-x1 @ min f-x1 !
      fb-depth @ 8 = if
        f-x0 @ f-x1 @ > 0= if
          i fb-pitch @ * fb-addr @ + f-x0 @ + f-x1 @ f-x0 @ - 1+ 1 fill
        then
      else
        r-x1 @ 1+ r-x0 @ do i j pixel loop
      then
    then
  loop ;

: invert-rect ( x0 y0 x1 y1 -- )
  r-y1 ! r-x1 ! r-y0 ! r-x0 !
  r-y1 @ 1+ r-y0 @ do
    r-x1 @ 1+ r-x0 @ do
      i j pixel-invert
    loop
  loop ;

create b-src 0 , create b-x 0 , create b-y 0 , create b-w 0 , create b-h 0 ,
: blit ( src dx dy w h -- )             \ 1bpp blit, 8 px per src byte, MSB left
  b-h ! b-w ! b-y ! b-x ! b-src !
  b-h @ 1+ 0 do
    b-w @ 1+ 0 do
      b-src @ j b-w @ 8 / * + i 8 / + + c@ 128 i 7 and rshift and if
        b-x @ i + b-y @ j + pixel
      then
    loop
  loop ;

: glyph ( c -- addr ) 32 - 16 * font8x16 + ;
create ch-g 0 , create ch-x 0 , create ch-y 0 , create ch-b 0 ,
: char ( c x y -- )
  ch-y ! ch-x ! glyph ch-g !
  16 0 do
    ch-g @ i + c@ ch-b !
    8 0 do
      ch-b @ 128 i rshift and if ch-x @ i + ch-y @ j + pixel then
    loop
  loop ;

create t-x 0 , create t-y 0 ,
: text ( addr len x y -- )
  t-y ! t-x !
  0 do
    dup i + c@ t-x @ t-y @ char
    t-x @ 8 + t-x !
  loop
  drop ;
