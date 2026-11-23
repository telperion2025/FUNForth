\ M10 framebuffer/VDI test: allocate 640x400 1bpp, draw a known pattern.
load fb.fth
load font8x16.fth
load vdi.fth
640 400 8 fb-alloc .
fb-w @ . fb-h @ . fb-pitch @ . fb-addr @ h.
fb-clear
10 10 200 100 rect
20 20 190 90 invert-rect
0 0 639 399 line
639 0 0 399 line
300 50 500 150 fillrect
word FUNForth-M10 count 300 200 text
create bmp 128 allot
bmp 128 255 fill
bmp 400 300 64 16 blit
