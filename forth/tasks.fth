\ ---- M13: cooperative multitasker (SPEC v1.0 6): 64-slot ring, 96-byte user areas ----
\ seed words: pause task-table up-cur
\ user-area cells: 0 task# 1 ps0 2 psp 3 rs0 4 rsp 5 xt(resume IP) 6 state
\ 7 attr 8 console 9 spawn-cell 10 r5save 11 execidx 12 stsave 13 inptr 14 execbase
\ state: 0 idle 1 ready 2 run ; attr bit0 = preemptible (M14)
create task-cnt 1 ,                             \ slot 0 is the shell (tasks_init)
create t-slot 0 , create t-base 0 , create t-ps0 0 , create t-rs0 0 , create t-up 0 ,

: up ( n -- a ) task-table swap 96 * + ;        \ ring slot n -> user area

: task: ( n -- ) ( name )                       \ n task: name ; 'name @' -> user area
  task-cnt @ 64 < 0= if ." task-ring-full " exit then
  task-cnt @ t-slot !
  task-cnt @ 1+ task-cnt !
  t-slot @ 96 * task-table + t-up !
  64 max 4 * dup >r                             \ r: stack bytes (PS and RS each)
  here t-base ! 128 allot                       \ per-task exec area (16 entries)
  here t-ps0 ! r@ allot                         \ PS block (grows down from ps0)
  here t-rs0 ! r> allot                         \ RS block (grows down from rs0)
  t-slot @ t-up @ !                             \ cell0 task#
  t-ps0 @ t-up @ 4 + !                          \ ps0
  t-ps0 @ t-up @ 8 + !                          \ psp = ps0 (empty)
  t-rs0 @ t-up @ 12 + !                         \ rs0
  t-rs0 @ t-up @ 16 + !                         \ rsp = rs0
  t-up @ 36 + t-up @ 20 + !                     \ up-xt = &spawn-cell (cell 9)
  1 t-up @ 24 + !                               \ state = ready
  0 t-up @ 28 + !                               \ attr = 0 (not preemptible)
  t-base @ t-up @ 56 + !                        \ exec_base
  create                                        \ parse name; body cell = user area
  t-up @ ,
;

: spawn ( xt up -- )                            \ task runs xt (end it with halt)
  t-up !
  t-up @ 36 + !                                 \ spawn-cell = xt
  t-up @ 4 + @ t-up @ 8 + !                     \ psp = ps0
  t-up @ 12 + @ t-up @ 16 + !                   \ rsp = rs0
  0 t-up @ 40 + !                               \ r5save = 0
  0 t-up @ 44 + !                               \ execidx = 0
  0 t-up @ 48 + !                               \ stsave = 0
  0 t-up @ 52 + !                               \ inptr = 0
  1 t-up @ 24 + !                               \ state = ready
  drop ;

: wake ( up -- ) 1 swap 24 + ! ;                \ state = ready
: kill ( up -- ) 0 swap 24 + ! ;                \ state = idle
: halt ( -- ) begin up-cur 0 swap 24 + ! pause again ;   \ stop current task
: yield ( -- ) pause ;
: sleep ( n -- ) 1000 * micros + begin dup micros - 0< while yield repeat drop ;

: tasks ( -- )                                  \ #/state/xt/attr per used slot
  task-cnt @ 0 do
    i . space i up 24 + @ . space i up 20 + @ h. space i up 28 + @ . cr
  loop ;
