\ ---- M20: DS3231 RTC on I2C slave 0x68=104 (needs i2c.fth) ----
\ QEMU has no RTC: i2c-probe fails, time@ returns zeros (deterministic stub).
create rtc-buf 8 allot
: bcd>bin ( bcd -- bin ) dup 4 rshift 10 * swap 15 and + ;
: bin>bcd ( bin -- bcd ) 10 /mod 16 * + ;
: time@ ( -- sec min hour dow date mon year )
  104 i2c-probe 0= if 0 0 0 0 0 0 0 exit then
  0 rtc-buf c!
  rtc-buf 1 104 0 i2c-xfer drop            \ set register pointer to 0
  rtc-buf 7 104 1 i2c-xfer drop            \ read 7 regs
  rtc-buf c@ bcd>bin
  rtc-buf 1+ c@ bcd>bin
  rtc-buf 2 + c@ bcd>bin
  rtc-buf 3 + c@ bcd>bin
  rtc-buf 4 + c@ bcd>bin
  rtc-buf 5 + c@ bcd>bin 127 and           \ strip century bit
  rtc-buf 6 + c@ bcd>bin ;
: time! ( sec min hour dow date mon year -- )
  104 i2c-probe 0= if drop drop drop drop drop drop drop exit then
  bin>bcd rtc-buf 6 + c!
  bin>bcd rtc-buf 5 + c!
  bin>bcd rtc-buf 4 + c!
  bin>bcd rtc-buf 3 + c!
  bin>bcd rtc-buf 2 + c!
  bin>bcd rtc-buf 1+ c!
  bin>bcd rtc-buf c!
  rtc-buf 8 104 0 i2c-xfer drop ;
