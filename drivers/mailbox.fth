\ ---- M9: mailbox 0 property channel (base io-base+0xB880) ----
\ READ=+0 POLL=+0x10 SENDER=+0x14 STATUS=+0x18 (bit31 full, bit30 empty) WRITE=+0x20
: mbox-read@  ( -- v ) io-base 47232 + @ ;
: mbox-status@ ( -- v ) io-base 47256 + @ ;
: mbox-write! ( v -- ) io-base 47264 + ! ;

: mbox-full  1 31 lshift ;   \ STATUS bit31 0x80000000: cannot write
: mbox-empty 1 30 lshift ;   \ STATUS bit30 0x40000000: nothing to read

: mbox-call ( buf -- resp )   \ buf: 16-byte aligned property message, [0]=size [1]=0
  begin mbox-status@ mbox-full and 0= until          \ wait writable
  dup 15 invert and 8 or mbox-write!                 \ (buf & ~0xF) | channel 8
  begin
    begin mbox-status@ mbox-empty and 0= until       \ wait readable
    mbox-read@ dup 15 and 8 =                        \ v flag(our channel)
    if 15 invert and exit then                       \ resp = addr (channel stripped)
    drop                                             \ discard other channels
  again ;

: align16 ( -- ) begin 0 , here 15 and 0= until ;
create mbox-buf 0 ,              \ variable holding the 16-byte-aligned buffer
align16
here mbox-buf !
128 allot

: mbox-tag ( tag -- valaddr )   \ build 32-byte single-tag message, call, -> &value
  mbox-buf @ >r                  \ tag            r: buf
  r@ 32 swap !                   \ buf[0] = buffer size
  r@ 4 + 0 swap !                \ buf[1] = 0 (request)
  r@ 8 + !                       \ buf[2] = tag
  r@ 12 + 8 swap !               \ buf[3] = 8 value bytes
  r@ 16 + 0 swap !               \ buf[4] = 0 request
  r@ 28 + 0 swap !               \ buf[7] = 0 end tag
  r@ mbox-call drop              \ response returns into buf
  r> 20 + ;                      \ value at buf+20

\ property tags (decimal): 0x00010001 board-model 0x00010002 board-rev
\ 0x00010003 mac 0x00010006 vc-mem(base,size) 0x00030006 temp(milli-C)
\ NOTE: QEMU writes the temperature at value+16 (buf[6]); real firmware uses
\ value+12 (buf[5]) - temp reads buf[5] per spec, so QEMU shows 0 there.
: board-model ( -- n )     65537 mbox-tag @ ;
: board-rev   ( -- n )     65538 mbox-tag @ ;
: mac         ( -- lo hi ) 65539 mbox-tag dup @ swap 4 + @ ;
: ram-size    ( -- n )     65542 mbox-tag dup @ swap 4 + @ + ;  \ vc base+size = total RAM
: temp        ( -- milli-c ) 196614 mbox-tag @ ;
