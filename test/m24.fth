\ M24: MMU identity map + caches on; save-image/load-image RAM round trip
load saveimg.fth
mmu@ .
mmu-on
mmu@ .
1 2 + .
io-base h.
: m24w 777 ;
save-image nip 0> .
save-image load-image
m24w .
." M24-DONE" cr
