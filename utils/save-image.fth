\ ---- M24: save-image / load-image ----
\ Image = dictionary bytes [0x8000, HERE). save-image copies them to img-buf and
\ returns ( addr len ); load-image copies them back (round trip, unit-tested in
\ test/m24). STUB: writing bootimg.bin to the FAT image is not implemented -
\ writable FAT32 is an explicit v1.0 non-goal; the FAT write path is v2.x.
create img-buf 262144 allot
: image-len ( -- len ) here 32768 - ;                    \ 0x8000
: save-image ( -- addr len ) img-buf image-len 2dup 32768 swap move ;
: load-image ( addr len -- ) 32768 swap move ;
