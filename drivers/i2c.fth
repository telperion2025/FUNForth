\ ---- M20: I2C bus master (BCM2835/7 BSC0 at io-base+0x804000) ----
\ BSC register byte offsets: C=0 S=4 DLEN=8 A=12 FIFO=16 DIV=20 DEL=24 CLKT=28
\ QEMU raspi0 emulates the BSC registers but attaches no devices: transfers
\ NAK or time out, so i2c-probe returns 0 and i2c-read fills zeros (deterministic).
: i2c-base ( -- a ) io-base 8413184 + ;            \ 0x804000
: i2c! ( v off -- ) i2c-base + ! ;
: i2c@ ( off -- v ) i2c-base + @ ;
: i2c-div! ( div -- ) 20 i2c! ;                    \ clock divider register

: fsel! ( pin mode -- )   \ any 3-bit GPFSEL mode (gpio.fth pin-mode does 0/1 only)
  over 10 /mod drop 3 * >r
  swap gpio-fsel dup @
  r@ 7 swap lshift invert and
  rot rot r> lshift or
  swap ! ;

: i2c-pins ( -- )         \ GPIO2=SDA GPIO3=SCL, alt0 (4), pull-up
  2 4 fsel!  3 4 fsel!
  2 2 pin-pull  3 2 pin-pull ;

create i2c-b 0 , create i2c-n 0 , create i2c-a 0 , create i2c-r 0 ,
: i2c-wait ( -- s )       \ poll S.DONE up to 100k times; S if done, else 0
  2000 0 do 4 i2c@ 2 and if 4 i2c@ unloop exit then loop 0 ;
: i2c-xfer ( buf len slave read? -- ok )   \ ok=-1 acked, 0 nak/timeout
  i2c-r ! i2c-a ! i2c-n ! i2c-b !
  i2c-a @ 1 lshift i2c-r @ or 12 i2c!      \ A = slave<<1 | read?
  i2c-n @ 8 i2c!                            \ DLEN
  i2c-r @ 0= if                             \ write: prefill FIFO (<=16 bytes)
    i2c-b @ i2c-n @ 16 min 0 do dup i + c@ 16 i2c! loop drop
  then
  i2c-r @ if 32913 else 32912 then 0 i2c!  \ C = ST|CLR|I2CEN (+READ)
  i2c-wait
  dup 2 and 0= if drop 0 exit then          \ no DONE: timeout
  256 and 0= 0= if drop 0 exit then         \ ERR: NAK
  i2c-r @ if i2c-b @ i2c-n @ 0 do 16 i2c@ over i + c! loop drop then
  drop -1 ;
: i2c-probe ( slave -- ack )  0 0 rot 1 i2c-xfer ;   \ -1 if device ACKs
