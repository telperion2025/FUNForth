\ forth/core.fth - FUNForth core, interpreted at cold (embedded via .incbin in
\ src/seed.S for test builds; from M12 loaded from SD by boot instead).
\ The compiler entry words (: ; literal immediate create ." word) are seeded in
\ assembly; everything above them is defined here in FORTH.

\ 2dup  ( a b -- a b a b )
: 2dup over over ;
