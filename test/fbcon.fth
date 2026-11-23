\ M11 console-fb test: 80x25 grid on the fb, prompt + echo rendered on screen.
\ console-fb itself is fb-only; the harness paces on "ok> " over UART, so the
\ test mirrors every emitted char to both fb and UART (fb-out).
load fb.fth
load font8x16.fth
load vdi.fth
load con-fb.fth
640 400 8 fb-alloc .
: fb-out ( c -- ) dup fb-emit emit-uart ;
: con-fb ( -- ) fb-clear  0 fb-cx !  0 fb-cy !  0 fb-inv !  millis fb-last !
  ['] fb-out con-emit! ['] key-fb con-key! ;
con-fb
: greet ." HELLO-FB" ;
greet
1 2 + .
