\ M14 t-tasks preempt: the (preemptible) shell is preempted mid-loop by the
\ 1 kHz tick checkpoint; a forced tick makes it deterministic (exactly one
\ preemption -> exactly one B from the other task). Then the real tick is
\ verified: tick-start arms C1, 50 ms later tick? is true.
256 task: t1
: job1 4 0 do ." B" pause loop halt ;
' job1 t1 @ spawn
preemptible
0 preempts !
: spin 5 0 do loop ;
19 quanta ! tick-force
spin
preempts @ .
t1 @ kill
tick-start
55 ms
preempts @ .
tasks-states
." END-PREEMPT"
