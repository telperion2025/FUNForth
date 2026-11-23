io-base h.
1 2 + depth . drop
foobar
2 3 + .
10 3 /mod . .
42 here ! here @ .
-10 3 /mod . .
5 0< . -3 0< . 0 0= .
7 3 < . 3 7 < . 3 3 = . 3 4 <> .
-1 1 u< .
5 3 min . 5 3 max .
7 1+ . 7 1- . 5 2* . 7 2/ . -7 2/ .
-5 abs . 5 negate .
12 10 and . 12 10 or . 12 10 xor . 0 invert h.
1 4 lshift . 256 4 rshift .
1 2 nip .
1 2 3 rot . . .
5 >r r@ . rdrop depth .
65 here c! here c@ .
999 here w! here w@ .
here 100 + 7 over +! here 100 + @ .
here 3 65 fill here c@ . here 2 + c@ .
: sq dup * ;
7 sq .
: greet ." Hello, FUNForth" ;
greet
1 2 2dup . . . .
foobar
40 2 + .
[A
65 emit
1 . space 2 .
key? .
16 base ! 255 .
255 u.
2 base ! 5 .
10 base !
-1 u.
here 8 allot here 8 - 5 72 fill here 8 - 5 type
span @ .
console-uart
: tloop 5 0 do i . loop ;
tloop
: tploop 10 0 do i . 2 +loop ;
tploop
: tqdo 3 0 ?do i . loop ;
tqdo
: tqdo0 5 5 ?do i . loop ;
tqdo0
: twhile 0 begin dup 3 < while dup . 1+ repeat drop ;
twhile
: tuntil 3 begin 1 - dup . dup 0= until drop ;
tuntil
: fib dup 2 < if exit then 1 - dup fib swap 1 - fib + ;
10 fib .
: tcase1 1 case 1 of ." one" endof ." other" endcase ;
tcase1
: tcase3 3 case 1 of ." one" endof 2 of ." two" endof ." other" endcase ;
tcase3
5 ?dup . .
0 ?dup .
7 ' sq execute .
: t2 [ 40 2 + ] . ;
t2
\ --- extended edge-case tests (review pass) ---
-7 2 /mod . .
-1 10 u/mod . .
16 base ! -255 .
36 base ! 35 .
36 base ! 36 .
10 base !
1 base ! 123 .
10 base !
create xx 42 , xx @ .
word abc c@ .
: a1 1 ;
: b1 2 ;
a1 b1 + .
." direct string"
( paren comment ) 5 6 + .
1 2 3 abort depth .
state @ .
1 2 3 depth . drop drop drop
0 0= . 5 0= .
: tl 10 0 do i . i 5 = if leave then loop ;
tl
: tn 3 0 do 2 0 do i . j . loop loop ;
tn
: tg ." a b, c!" ;
tg
here latest @ u< .
here 8 allot here 8 - 3 65 fill here 8 - here 8 - 8 + 3 move here 8 - 8 + c@ .
foobar 1 2 + .
7 3 mod-check-nope
\ --- M6: introspection ---
see sq
see greet
see dup
marker m1
: mw 123 ;
mw .
m1
mw
: zz 99 ;
zz .
forget zz
zz
words
\ --- M7: system timer ---
millis dup - .
0 millis 100 ms millis swap - dup 90 < 0= swap 110 > 0= and . drop
tick-start 5 ms tick? .
micros 10 ms micros swap - dup 9000 < 0= swap 100000 > 0= and .
\ --- M8: GPIO ---
47 1 pin-mode 47 pin! 47 pin@ .
47 pin-clr 47 pin@ .
1 led! 47 pin@ .
0 led! 47 pin@ .
47 2 pin-pull
47 0 pin-pull
hal-pud-wait .
