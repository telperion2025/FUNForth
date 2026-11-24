\ hello.fth - M19 demo: 200x150 window with close box + counter button.
needs gui
create hello-win 0 ,
create counter 0 ,
create t-hello 16 allot
create t-count 16 allot
word Hello count t-hello swap move
word COUNT count t-count swap move
: counter-inc ( -- ) 1 counter +! counter @ . ;
: hello-redraw ( win -- )
  drop
  t-hello count 10 10 wtext
  t-count count 10 40 80 24 ['] counter-inc button ;
: hello ( -- )
  200 150 win-new dup hello-win !
  t-hello count hello-win @ win-title!
  ['] hello-redraw hello-win @ win-redraw!
  220 hello-win @ win-x!
  100 hello-win @ win-y!
  hello-win @ win-open
  wm-redraw-all ;
