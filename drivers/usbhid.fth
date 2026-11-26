\ ---- M21: USB HID host - boot-protocol decoders + report ring ----
\ DWC2 host init is hardware-only (QEMU raspi0 emulates no USB block), so
\ usb-init is a stub reporting "not present". Decoders + ring are unit-tested
\ offline in test/m21.fth with synthetic report vectors.
create usb-reps 64 allot          \ ring: 8 reports x 8 bytes
create usb-head 0 , create usb-tail 0 ,
create usb-src 0 , create usb-dst 0 ,
: usb-push ( rep -- )             \ enqueue 8-byte report (ISR path on hw)
  usb-dst !
  usb-tail @ 8 * usb-reps + usb-src !
  8 0 do usb-dst @ i + c@ usb-src @ i + c! loop
  usb-tail @ 1+ 8 mod usb-tail ! ;
: usb-pop ( rep -- f )            \ dequeue into rep; -1 if one was present
  usb-dst !
  usb-head @ usb-tail @ = if 0 exit then
  usb-head @ 8 * usb-reps + usb-src !
  8 0 do usb-src @ i + c@ usb-dst @ i + c! loop
  usb-head @ 1+ 8 mod usb-head !
  -1 ;
create rep-a 0 , create kbd-key 0 ,
: kbd-decode ( rep -- key mods )  \ boot keyboard: b0=mods b2..b7=keycodes
  rep-a !
  rep-a @ c@ >r
  0 kbd-key !
  6 2 do
    rep-a @ i + c@ dup if kbd-key @ 0= if kbd-key ! else drop then else drop then
  loop
  r> kbd-key @ swap ;
: s8 ( u8 -- s8 ) dup 127 > if 256 - then ;
: mouse-decode ( rep -- buttons dx dy )   \ boot mouse: b0=buttons b1=dx b2=dy
  rep-a !
  rep-a @ c@
  rep-a @ 1+ c@ s8
  rep-a @ 2 + c@ s8 ;
create usb-buf 8 allot
: keyusb ( -- key )               \ 0 if no report pending
  usb-buf usb-pop 0= if 0 exit then
  usb-buf kbd-decode nip ;
: moused@ ( -- buttons dx dy )
  usb-buf usb-pop 0= if 0 0 0 exit then
  usb-buf mouse-decode ;
: usb-init ( -- present ) 0 ;     \ STUB: DWC2 host bring-up is hardware-only
