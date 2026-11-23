\ ---- M10: framebuffer via mailbox property channel (channel 8) ----
\ tags: 0x48003 set phys w/h, 0x48004 set virt w/h, 0x48005 set depth,
\ 0x48006 pixel order, 0x48007 alpha, 0x40008 get pitch, 0x40001 allocate fb,
\ 0x4800b set palette (8bpp: entry0=black entry1=white for QEMU visibility;
\ QEMU's bcm2835_fb renderer has no 1bpp case and would paint it all black)
create fb-w 0 ,
create fb-h 0 ,
create fb-depth 0 ,
create fb-pitch 0 ,
create fb-addr 0 ,
create fb-size 0 ,
create fb-msg 0 ,
align16
here fb-msg !
160 allot

: b! ( x ofs -- ) fb-msg @ + ! ;        \ store x at fb-msg[ofs]  (! takes addr on top)

: fb-alloc ( w h depth -- ok )
  fb-depth ! fb-h ! fb-w !               \ [w h depth] -> vars
  \ call 1: configure (QEMU applies it at the end of the message)
  100 0 b!   0 4 b!
  294915 8 b!  8 12 b!  0 16 b!          \ 0x48003 set phys w/h
  fb-w @ 20 b!  fb-h @ 24 b!
  294916 28 b!  8 32 b!  0 36 b!         \ 0x48004 set virt w/h
  fb-w @ 40 b!  fb-h @ 44 b!
  294917 48 b!  4 52 b!  0 56 b!         \ 0x48005 set depth
  fb-depth @ 60 b!
  294918 64 b!  4 68 b!  0 72 b!         \ 0x48006 pixel order (1 = RGB)
  1 76 b!
  294919 80 b!  4 84 b!  0 88 b!         \ 0x48007 alpha mode (0)
  0 92 b!
  0 96 b!                                \ end tag
  fb-msg @ mbox-call drop
  \ call 2: get pitch + allocate
  48 0 b!   0 4 b!
  262152 8 b!  4 12 b!  0 16 b!          \ 0x40008 get pitch
  262145 24 b!  8 28 b!  0 32 b!         \ 0x40001 allocate framebuffer
  16 36 b!  0 40 b!
  0 44 b!                                \ end tag
  fb-msg @ mbox-call drop
  20 fb-msg @ + @ fb-pitch !
  36 fb-msg @ + @ 1073741823 and fb-addr !   \ bus addr -> ARM physical (0x3FFFFFFF)
  40 fb-msg @ + @ fb-size !
  \ call 3: 8bpp palette black/white (QEMU reads palette from vcram_base)
  fb-depth @ 8 = if
    40 0 b!   0 4 b!
    294923 8 b!  16 12 b!  0 16 b!       \ 0x4800b set palette
    0 20 b!  2 24 b!  0 28 b!  -1 32 b!   \ offset 0, len 2, black, white
    0 36 b!
    fb-msg @ mbox-call drop
  then
  4 fb-msg @ + @ 31 rshift ;             \ ok = response code 0x80000000

: fb-clear ( -- ) fb-addr @ fb-size @ 0 fill ;
: fb-off ( -- ) fb-clear ;               \ blank the display
