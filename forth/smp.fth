\ ---- M22: SMP worker cores (BCM2837 3A+) - single-core path on Zero ----
\ Zero (BCM2835): cores = 1, nothing to park; send/recv use one SPSC ring.
\ 3A+ (BCM2837): cores = 4; core parking via doorbell/IPI is hardware-only
\ (STUB here): queues stay plain rings, so QEMU raspi0 acceptance is cores=1.
: cores ( -- n ) io-base @ 1056964608 = if 4 else 1 then ;   \ 0x3F000000
create smp-q 64 allot               \ 16-cell message ring
create smp-head 0 , create smp-tail 0 ,
: core ( n -- ) dup cores < 0= if ." -? core " drop exit then drop ;   \ consume n; error if n >= cores
: core! ( n -- ) core ;             \ STUB: per-core select (hw: doorbell)
: send ( msg core -- )
  core
  smp-tail @ 16 mod 4 * smp-q + !
  smp-tail @ 1+ 16 mod smp-tail ! ;
: recv ( core -- msg f )
  core
  smp-head @ smp-tail @ = if 0 0 exit then
  smp-head @ 16 mod 4 * smp-q + @
  smp-head @ 1+ 16 mod smp-head !
  -1 ;
: sendx ( msg core ms -- ok ) drop send -1 ;
: recvx ( core ms -- msg f ) >r r@ ms r> recv ;
: corelist ( -- ) cores . space smp-head @ . space smp-tail @ . ;
