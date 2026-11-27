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
5 7 1 oled!
oled-fb 5 + c@ h. cr
0 oled-fb 5 + c!
65 o-dbg @ !
oled-fb 5 + c@ h. cr
0 oled-fb 5 + c!
o-dbg @ 65 swap !
oled-fb 5 + c@ h. cr
0 oled-fb 5 + c!
o-dbg @ 1 if 65 else 66 then swap !
oled-fb 5 + c@ h. cr
0 oled-fb 5 + c!
o-dbg @ dup @ oled-mask o-v @ if or else invert and then swap !
oled-fb 5 + c@ h. cr
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
