\ M23: IRQ words on QEMU raspi0 (no IRQ source enabled - real delivery is hw-only/v2)
create hook-cnt 0 ,
: hook1 hook-cnt @ 1+ hook-cnt ! ;
uart-irq-rx
' hook1 irq-hook-uart
0 irq-hook-uart
irq-off
irqs@ .
tick-irqs@ .
irq-on
irq-off
irqs@ .
hook-cnt @ .
pat
." M23-DONE" cr
