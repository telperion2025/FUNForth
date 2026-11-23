\ forth/core.fth - FUNForth core, interpreted at cold (embedded via .incbin in
\ src/seed.S for test builds; from M12 loaded from SD by boot instead).
\ The compiler entry words (: ; literal immediate create ." word) are seeded in
\ assembly; everything above them is defined here in FORTH.

\ 2dup  ( a b -- a b a b )
: 2dup over over ;

\ ---- M5: control-flow stack + control words (SPEC 4.1) ----
\ cf stack is a separate memory stack: r13 is the Forth return stack (used by
\ >r/r> and DOCOL/EXIT), so compile-time control-flow state must not live there.
create cfbuf 256 allot
create cfsp 0 ,
: cfpush ( x -- ) cfsp @ 2 lshift cfbuf + ! cfsp @ 1+ cfsp ! ;
: cfpop  ( -- x ) cfsp @ 1- dup cfsp ! 2 lshift cfbuf + @ ;
: cfdepth ( -- n ) cfsp @ ;

: if   postpone (0branch) here 0 , cfpush ; immediate
: else postpone (branch) here 0 , cfpop here swap ! cfpush ; immediate
: then cfpop here swap ! ; immediate

: begin here cfpush ; immediate
: until postpone (0branch) here 0 , cfpop swap ! ; immediate
: again postpone (branch) here 0 , cfpop swap ! ; immediate
: while postpone (0branch) here 0 , cfpush ; immediate
: repeat postpone (branch) here 0 , cfpop here swap ! cfpop swap ! ; immediate

create leavebuf 64 allot
create leavesp 0 ,
: lpush ( x -- ) leavesp @ 2 lshift leavebuf + ! leavesp @ 1+ leavesp ! ;
: lpop ( -- x ) leavesp @ 1- dup leavesp ! 2 lshift leavebuf + @ ;
: ldepth ( -- n ) leavesp @ ;
: patchleaves ( -- ) ldepth 0> if lpop here swap ! patchleaves then ;
: do  postpone (do) here 0 , cfpush here cfpush ; immediate
: ?do postpone (?do) here 0 , cfpush here cfpush ; immediate
: leave postpone (leave) here 0 , lpush ; immediate
: loop postpone (loop) postpone (branch) here 0 , patchleaves cfpop swap ! cfpop here swap ! ; immediate
: +loop postpone (+loop) postpone (branch) here 0 , patchleaves cfpop swap ! cfpop here swap ! ; immediate

: ?dup dup if dup then ;

create casecnt 0 ,
: case 0 casecnt ! ; immediate
: of postpone over postpone = postpone (0branch) here 0 , cfpush casecnt @ 1+ casecnt ! ; immediate
: endof postpone (branch) here 0 , cfpop here swap ! cfpush casecnt @ 1+ casecnt ! ; immediate
: endpatch ( -- ) cfdepth 0> if cfpop here swap ! endpatch then ;
: endcase postpone drop endpatch ; immediate
