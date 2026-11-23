\ ---- M7: system timer (BCM2835/BCM2837 SYSTIMER at PERIPHERALS+0x3000) ----
\ register offsets from io-base: CS=12288 CLO=12292 CHI=12296 C0=12300 C1=12304
: sys-cs  io-base 12288 + ;
: sys-clo io-base 12292 + ;
: sys-c1  io-base 12304 + ;

: micros ( -- u )  sys-clo @ ;                          \ 1 MHz free-running counter (low 32)
: millis ( -- ms ) micros 1000 u/mod nip ;
: ms ( n -- )  1000 * micros + begin dup micros swap < 0= until drop ;
: tick-start ( -- )  micros 1000 + sys-c1 !  sys-cs 2 ! ; \ 1 kHz compare1, clear M1 flag
: tick? ( -- flag )  sys-cs @ 2 and 0= 0= ;
