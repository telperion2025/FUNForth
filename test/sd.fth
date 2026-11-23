\ M12 SD/FAT tests: mount, raw sector read, file checksums, load+run from SD
sd-mount .
0 sdbuf sd-read sdbuf 510 + c@ . sdbuf 511 + c@ .
file-sum hello.txt .
file-sum boot.lst .
load hello.txt
hi
load nosuch.txt
