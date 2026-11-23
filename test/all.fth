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
