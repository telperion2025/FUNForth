\ ---- M24: save-image / load-image ----
\ Image = dictionary bytes [0x8000, img-buf). save-image copies them to img-buf and
\ returns ( addr len ); load-image copies them back (round trip, unit-tested in
\ test/m24). STUB: writing bootimg.bin to the FAT image is not implemented -
\ writable FAT32 is an explicit v1.0 non-goal; the FAT write path is v2.x.
create img-buf 262144 allot
create si-a 0 , create si-n 0 ,
: image-len ( -- len ) img-buf 32768 - ;               \ image = [0x8000, img-buf)
: save-image ( -- addr len )
  image-len si-n !  img-buf si-a !
  32768 si-a @ si-n @ move                             \ move(0x8000 -> img-buf)
  si-a @ si-n @ ;
: load-image ( addr len -- )
  si-n ! si-a !
  si-a @ 32768 si-n @ move ;                           \ move(img-buf -> 0x8000)
