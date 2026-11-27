\ M20: I2C + SSD1306 OLED + DS3231 RTC (QEMU: register pokes + no-device stub)
load fb.fth
load font8x16.fth
load vdi.fth
load i2c.fth
load ssd1306.fth
load rtc.fth
i2c-pins
1666 20 i2c!
66 12 i2c!
oled-init
oled-clear
5 7 1 oled!
o-x @ . space o-y @ . space o-v @ . cr
o-dbg h. cr
oled-fb h. cr
: t-addr oled-fb o-y @ 8 / 128 * o-x @ + + ;
t-addr h. cr
load asm.fth
see oled-addr
see t-addr
see oled!
5 7 oled@ .
65 8 8 oled-char
oled-sum .
oled-flush
." OLED-OK" cr
time@ . . . . . . .
30 14 6 3 25 11 24 time!
time@ . . . . . . .
60 i2c-probe drop
." M20-DONE" cr
