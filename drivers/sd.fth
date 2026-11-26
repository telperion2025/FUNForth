\ ---- M12: SD via Arasan SDHCI (io-base+0x300000) + FAT32 read-only ----
\ regs: ARG=8 TRNMOD|CMD=12 RSP0=16 BDATA=32 PRNSTS=36 PWRCON=41(0x29)
\ CLKCON=44(0x2C) SWRST=47(0x2F) NISR=48(0x30) NISREN=52(0x34) CAPAB=64(0x40)
: sd-base io-base 3145728 + ;
: sd@  ( off -- v ) sd-base + @ ;
: sd!  ( v off -- ) sd-base + ! ;
: sdc! ( v off -- ) sd-base + c! ;
: sdc@ ( off -- v ) sd-base + c@ ;

: sd-cc ( -- ) begin 48 sd@ 1 and until 1 48 sd! ;          \ CMDCMP
: sd-cmd ( arg cmd -- ) begin 36 sd@ 1 and 0= until
  swap 8 sd! 16 lshift 12 sd! sd-cc ;

create sd-rca 0 ,
create sd-hc 0 ,

: sd-init ( -- ok )
  1 47 sdc!  begin 47 sdc@ 1 and 0= until          \ reset all
  15 41 sdc!                                       \ power 3.3V
  64 sd@ 8 rshift 255 and 5 * 4 / 255 min 8 lshift 7 or 14 16 lshift or 44 sd!
  -1 52 sd!                                        \ enable all NISR bits
  0 0 sd-cmd                                       \ CMD0
  426 2050 sd-cmd                                  \ CMD8 R7
  0 14082 sd-cmd                                   \ CMD55
  1090486272 10498 sd-cmd                          \ ACMD41 arg 0x40FF8000
  16 sd@ 1073741824 and 0= 0= sd-hc !              \ CCS bit30 -> SDHC
  0 513 sd-cmd                                     \ CMD2 R2
  0 770 sd-cmd                                     \ CMD3 R6 -> RCA
  16 sd@ 16 rshift dup sd-rca ! 16 lshift 1795 sd-cmd   \ CMD7 R1b RCA<<16
  512 4098 sd-cmd                                  \ CMD16 blocklen 512
  48 sd@ 32768 and 0= ;                            \ ok if no error

: sd-read ( lba addr -- )                          \ CMD17 PIO 512 bytes
  >r
  begin 36 sd@ 3 and 0= until
  sd-hc @ if else 512 * then 8 sd!
  66048 4 sd!                                      \ BLKSIZECNT = 1 block, 512
  287440912 12 sd!                                 \ TRNMOD=read CMD17 R1+data
  begin 48 sd@ 32 and until 32 48 sd!              \ RBUFRDY
  r>                                               \ addr back on data stack
  128 0 do 32 sd@ over ! 4 + loop drop
  begin 48 sd@ 2 and until 2 48 sd!                \ TRSCMP
  ;

create sdbuf 512 allot
create load-buf 65536 allot
create lb-cap 65535 ,                              \ max file bytes (NUL needs 1)

\ FAT32: BPB spc@13 res@14 nfats@16 fatsz32@36 rootclus@44
create fat-spc 0 ,
create fat-res 0 ,
create fat-nfats 0 ,
create fat-fatsz 0 ,
create fat-data 0 ,
create fat-root 0 ,
create fat-dest 0 ,

: sd-mount ( -- ok )
  sd-init 0= if 0 exit then
  0 sdbuf sd-read
  sdbuf 510 + c@ 85 = sdbuf 511 + c@ 170 = and 0= if 0 exit then
  sdbuf 13 + c@ fat-spc !
  sdbuf 14 + c@ sdbuf 15 + c@ 8 lshift or fat-res !
  sdbuf 16 + c@ fat-nfats !
  sdbuf 36 + @ fat-fatsz !
  fat-res @ fat-nfats @ fat-fatsz @ * + fat-data !
  sdbuf 44 + @ fat-root !
  -1 ;

: clus-lba ( clus -- lba ) 2 - fat-spc @ * fat-data @ + ;

: fat-next ( clus -- next )                        \ FAT32 entry, 28-bit
  4 * dup 9 rshift fat-res @ + sdbuf sd-read
  sdbuf swap 511 and + @ 268435455 and ;          \ entry offset within the sector

create name11 11 allot
create namepos 0 ,
: mkname ( a len -- )                              \ -> 8.3 uppercase in name11
  >r                                               \ a  r: len
  name11 11 32 fill
  0 namepos !
  r> 0 do
    dup i + c@ dup 46 = if                         \ dot: pad base field to 8
      drop 8 namepos !
    else
      dup 96 > if 32 - then                        \ uppercase
      name11 namepos @ + c!
      namepos @ 1+ namepos !
    then
  loop drop ;

: name= ( e -- f )                                 \ dir entry name == name11
  11 0 do dup i + c@ name11 i + c@ <> if drop unloop 0 exit then loop
  drop -1 ;

create fat-e 0 ,
create fat-stop 0 ,
: fat-find ( -- e|0 )                              \ search root dir
  0 fat-e !  0 fat-stop !
  fat-root @
  begin dup 268435200 < fat-stop @ 0= and while
    dup clus-lba sdbuf sd-read
    16 0 do
      fat-stop @ 0= if
        sdbuf i 5 lshift + dup c@ 0= if          \ end of dir
          drop -1 fat-stop !
        else
          dup c@ 229 = 0= if                       \ not deleted
            dup 11 + c@ dup 15 and 0= swap 16 and 0= and if   \ regular file
              dup name= if fat-e ! -1 fat-stop ! else drop then
            else drop then
          else drop then
        then
      then
    loop
    fat-stop @ 0= if fat-next then
  repeat
  drop fat-e @ ;

: fat-read ( e addr -- len )                       \ read cluster chain to addr
  >r                                               \ r: addr
  r@ fat-dest !
  dup 28 + @ >r                                    \ size  r: addr size
  dup 26 + c@ over 20 + c@ 16 lshift or nip        \ clus (e is in sdbuf, fat-next clobbers it)
  begin dup 268435200 < while
    dup clus-lba fat-dest @ sd-read
    fat-dest @ 512 + fat-dest !
    fat-next
  repeat drop r> rdrop ;

: load-file ( a len -- )                           \ load+interpret file named a len
  2dup mkname
  fat-find dup 0= if drop ." -? " type cr exit then
  dup 28 + @ dup lb-cap @ > if ." -? big " cr 2drop 2drop exit then
  drop nip nip
  load-buf fat-read load-buf + 0 swap c!          \ NUL-terminate
  load-buf interpret ;

: load ( -- ) word count load-file ;

create bootlst 8 c, 66 c, 79 c, 79 c, 84 c, 46 c, 76 c, 83 c, 84 c,   \ "BOOT.LST"

create boot-buf 2048 allot

: file-sum ( -- n )                                \ checksum of file named next
  word count 2dup mkname
  fat-find dup 0= if drop ." -? " type cr 0 exit then
  dup 28 + @ dup lb-cap @ > if ." -? big " cr 2drop 2drop 0 exit then
  drop nip nip
  load-buf fat-read >r
  0
  r> 0 do load-buf i + c@ + loop ;

: sd-boot ( -- )                                   \ cold: mount + run BOOT.LST
  sd-mount 0= if exit then
  bootlst 1+ 8 mkname
  fat-find dup 0= if drop exit then
  boot-buf fat-read boot-buf + 0 swap c!
  boot-buf interpret ;
