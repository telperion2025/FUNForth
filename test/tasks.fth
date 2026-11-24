\ M13 t-tasks: two tasks alternate printing via pause; kill stops one;
\ the shell stays responsive afterwards. Deterministic: each task prints
\ exactly 8 chars then halts; the shell drives exactly 16 pauses.
256 task: t1
256 task: t2
: job1 8 0 do ." A" pause loop halt ;
: job2 8 0 do ." B" pause loop halt ;
' job1 t1 @ spawn
' job2 t2 @ spawn
: drive 16 0 do pause loop ;
drive
t1 @ kill
tasks-states
." END-TASKS"
