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
