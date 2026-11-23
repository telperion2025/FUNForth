\ ---- M8: GPIO (base io-base+0x200000) ----
\ GPFSEL0=+0 GPSET0=+28 GPCLR0=+40 GPLEV0=+52 GPPUD=+148 GPPUDCLK0=+152 (x4 per bank)
: gpio-fsel   ( pin -- a ) 10 /mod nip 2 lshift io-base 2097152 + + ;
: gpio-set    ( pin -- a ) 32 /mod nip 2 lshift io-base 2097180 + + ;
: gpio-clr    ( pin -- a ) 32 /mod nip 2 lshift io-base 2097192 + + ;
: gpio-lev    ( pin -- a ) 32 /mod nip 2 lshift io-base 2097204 + + ;
: gpio-pudclk ( pin -- a ) 32 /mod nip 2 lshift io-base 2097304 + + ;
: gpio-mask   ( pin -- m ) 32 /mod drop 1 swap lshift ;
: gppud!      ( mode -- )  io-base 2097300 + ! ;

: pin-mode ( pin mode -- )   \ mode: 0=in 1=out
  over 10 /mod drop 3 * >r              \ pin mode     r: shift
  swap gpio-fsel dup @                  \ mode a old
  r@ 7 swap lshift invert and           \ mode a old'
  rot                                   \ a old' mode
  r> lshift or                          \ a new
  swap ! ;

: pin!   ( pin -- ) dup gpio-mask swap gpio-set ! ;
: pin-clr ( pin -- ) dup gpio-mask swap gpio-clr ! ;
: pin@   ( pin -- level ) dup gpio-mask swap gpio-lev @ and swap drop 0= 0= negate ;

: io-wait ( n -- ) 0 do loop ;
: pin-pull ( pin mode -- )   \ mode: 0=off 1=down 2=up (GPPUD protocol, hal wait)
  gppud!
  >r
  hal-pud-wait io-wait
  r@ dup gpio-mask swap gpio-pudclk !
  hal-pud-wait io-wait
  0 gppud!
  r> dup gpio-mask swap gpio-pudclk 0 swap ! drop ;

: led! ( on -- )   \ ACT LED = pin 47, active low
  47 1 pin-mode
  if 47 pin-clr else 47 pin! then ;
