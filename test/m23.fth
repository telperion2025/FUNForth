\ M23: IRQ machinery (vector, IC enable, UART hook, watchdog pat) on QEMU raspi0
create hook-cnt 0 ,
: hook1 hook-cnt @ 1+ hook-cnt ! ;
uart-irq-rx
57 irq-enable
' hook1 irq-hook-uart
irq-on
100000 0 do loop
irq-off
irqs@ 0> .
hook-cnt @ 0> .
tick-irqs@ 0> 0= if ." tick-irq-poll-wins" cr then
pat
." M23-DONE" cr
