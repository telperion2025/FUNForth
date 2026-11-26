\ M22: SMP cores count + send/recv ring (QEMU raspi0: single-core path)
load smp.fth
cores .
42 0 send
0 recv . .
7 0 send
0 5 recvx . .
0 recv . .
corelist .
." M22-DONE" cr
