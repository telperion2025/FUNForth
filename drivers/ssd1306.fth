\ ---- M20: SSD1306 OLED 128x64 console channel (I2C slave 0x3C=60) ----
\ needs i2c.fth, font8x16.fth, vdi.fth (glyph). Framebuffer is page format:
\ fb[page*128 + x], bit (y mod 8). Flush errors are ignored (stub-safe in QEMU).
create oled-fb 1024 allot
create o-x 0 , create o-y 0 , create o-v 0 ,
: oled! ( x y v -- )      \ set/clear pixel in fb (no flush)
  >r o-y ! o-x ! r> o-v !
  oled-fb o-y @ 8 / 128 * o-x @ + +        \ a
  dup @                                    \ a old
  o-y @ 8 mod 1 swap lshift                \ a old m
  o-v @ if or else invert and then         \ a new
  swap ! ;
: oled@ ( x y -- v )      \ -1 if pixel set, else 0
  o-y ! o-x !
  oled-fb o-y @ 8 / 128 * o-x @ + + @
  o-y @ 8 mod 1 swap lshift and 0= 0= ;
: oled-clear ( -- ) oled-fb 1024 0 fill ;
create oc-c 0 , create oc-x 0 , create oc-y 0 ,
: oled-char ( c x y -- )  \ draw 8x8 (top half of the 8x16 glyph) at pixel x,y
  oc-y ! oc-x ! oc-c !
  8 0 do                                  \ i = row
    8 0 do                                \ j = col
      font8x16 oc-c @ 32 - 16 * + i + c@ 128 j rshift and if
        oc-x @ j + oc-y @ i + 1 oled!
      then
    loop
  loop ;
create oled-cbuf 0 ,
: oled-cmd ( b -- ) oled-cbuf ! oled-cbuf 1 60 0 i2c-xfer drop ;
: oled-init ( -- )
  174 oled-cmd 32 oled-cmd 0 oled-cmd 176 oled-cmd 200 oled-cmd
  0 oled-cmd 16 oled-cmd 64 oled-cmd 129 oled-cmd 207 oled-cmd
  161 oled-cmd 166 oled-cmd 168 oled-cmd 63 oled-cmd
  211 oled-cmd 0 oled-cmd 213 oled-cmd 128 oled-cmd
  217 oled-cmd 241 oled-cmd 218 oled-cmd 18 oled-cmd
  219 oled-cmd 64 oled-cmd 141 oled-cmd 20 oled-cmd 175 oled-cmd ;
: oled-flush ( -- )       \ send fb as 64 x 16-byte pages (errors ignored)
  64 0 do oled-fb i 16 * + 16 60 0 i2c-xfer drop loop ;
create oled-cx 0 , create oled-cy 0 ,
: oled-emit ( c -- )
  dup 13 = over 10 = or if drop 0 oled-cx ! oled-cy @ 1+ 8 mod oled-cy ! exit then
  dup 32 < if drop exit then
  oled-cx @ 8 * oled-cy @ 8 * oled-char
  oled-cx @ 1+ dup 16 = if drop 0 oled-cx ! oled-cy @ 1+ 8 mod oled-cy ! else oled-cx ! then
  oled-flush ;
: console-oled ( -- ) oled-init oled-clear 0 oled-cx ! 0 oled-cy ! ['] oled-emit con-emit! ['] key-uart con-key! ;
