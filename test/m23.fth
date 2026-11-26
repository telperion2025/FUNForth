\ M23: IRQ machinery on QEMU raspi0 - systimer C1 path (UART RX hook is hw-only)
create hook-cnt 0 ,
: hook1 hook-cnt @ 1+ hook-cnt ! ;
uart-irq-rx
' hook1 irq-hook-uart
0 irq-hook-uart
irq-off
irqs@ 0> .
tick-irqs@ 0> .
tick-start
1 irq-enable
irq-on
100000 0 do loop
irq-off
irqs@ 0> .
tick-irqs@ 0> .
hook-cnt @ 0> .
pat
." M23-DONE" cr
