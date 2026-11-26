\ ---- M25: probe utilities (machine state snapshot) ----
\ needs smp.fth for cores
: probe ( -- )
  ." depth=" depth .
  ." here-ok=" here 0> .
  ." latest-ok=" latest 0> .
  ." task=" up-cur 0> .
  ." cores=" cores .
  ." irqs=" irqs@ .
  cr ;
: probe-mem ( a -- )        \ dump 16 cells from a, hex
  16 0 do dup i 4 * + @ h. space loop drop cr ;
