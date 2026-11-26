\ ---- M20: SSD1306 OLED 128x64 console channel (I2C slave 0x3C=60) ----
\ needs i2c.fth, font8x16.fth, vdi.fth (glyph). Framebuffer is page format:
\ fb[page*128 + x], bit (y mod 8). Flush errors are ignored (stub-safe in QEMU).
create oled-fb 1024 allot
create o-x 0 , create o-y 0 , create o-v 0 , create o-dbg 0 ,
: oled-addr ( -- a ) oled-fb o-y @ 8 / 128 * o-x @ + + ;
: oled-mask ( -- m ) 1 o-y @ 8 mod lshift ;
: oled! ( x y v -- )      \ set/clear pixel in fb (no flush)
  o-v ! o-y ! o-x !
  oled-addr dup o-dbg !                      \ a, o-dbg = a (debug)
  dup @ oled-mask o-v @ if or else invert and then   \ a new
  swap ! ;
: oled@ ( x y -- v )      \ -1 if pixel set, else 0
  o-y ! o-x !
  oled-addr @ oled-mask and 0= 0= ;
: oled-clear ( -- ) oled-fb 1024 0 fill ;
create oled-acc 0 ,
: oled-sum ( -- n ) 0 oled-acc ! oled-fb 1024 0 do oled-fb i + c@ oled-acc @ + oled-acc ! loop oled-acc @ ;
create oc-c 0 , create oc-x 0 , create oc-y 0 ,
create oc-r 0 , create oc-k 0 ,
: oled-char ( c x y -- )  \ draw 8x8 (top half of the 8x16 glyph) at pixel x,y
  oc-y ! oc-x ! oc-c !
  8 0 do i oc-r !                         \ oc-r = row (i reads outer loop here)
    8 0 do i oc-k !                       \ oc-k = col (i reads inner loop here)
      font8x16 oc-c @ 32 - 16 * + oc-r @ + c@ 128 oc-k @ rshift and if
        oc-x @ oc-k @ + oc-y @ oc-r @ + 1 oled!
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
