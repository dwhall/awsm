#!fmt: off

import unittest2

include awsm_all_trans

echo "s:    " & repr s
echo "s1:   " & repr s1
echo "s11:  " & repr s11
echo "s2:   " & repr s2
echo "s21:  " & repr s21
echo "s211: " & repr s211
echo "top:  " & repr top

test "Plain states can test for state equality":
  var a = newAllTransAwsm()
  a.currentHandler = top
  check a.currentHandler == top

test "Converted states can test for state equality":
  var a = newAllTransAwsm()
  a.currentHandler = top.toEventHandler
  check a.currentHandler == top

test "Converted states can still access custom fields":
  var a = newAllTransAwsm()
  a.foo = 42
  a.currentHandler = top.toEventHandler
  check a.foo == 42

test "Initial transitions are taken from implicit 'initial' handler":
  var a = newAllTransAwsm()
  a.init()
  check a.foo == 0
  check a.currentHandler == s211.toEventHandler

test "Initial transitions are taken from explicit 'initial' handler":
  var a = newAllTransAwsm()
  a.currentHandler = initial.toEventHandler
  a.init()
  check a.foo == 0
  # Initial to s2, then to s211
  check a.currentHandler == s211.toEventHandler

test "Unhandled event remains in current state":
  var a = newAllTransAwsm()
  a.currentHandler = s.toEventHandler
  a.entryCount = 0
  a.exitCount = 0
  a.dispatch(AEvt)
  check a.exitCount == 0
  check a.entryCount == 0
  check a.currentHandler == s.toEventHandler

test "Handled event remains in current state":
  var a = newAllTransAwsm()
  a.currentHandler = s.toEventHandler
  a.entryCount = 0
  a.exitCount = 0
  a.dispatch(IEvt)
  check a.exitCount == 0
  check a.entryCount == 0
  check a.currentHandler == s.toEventHandler

test "Transition to same state should exit, re-enter and follow initial":
  var a = newAllTransAwsm()
  a.currentHandler = s1.toEventHandler
  a.entryCount = 0
  a.exitCount = 0
  a.dispatch(AEvt)
  check a.exitCount == 1  # exit s1
  check a.entryCount == 2  # enter s1, enter s11
  # After transition to self, follow initial transition to s11
  check a.currentHandler == s11.toEventHandler

test "This particular transition to same state does not change the awsm variable":
  var a = newAllTransAwsm()
  a.currentHandler = s1.toEventHandler
  a.foo = 42
  a.dispatch(AEvt)
  check a.foo == 42

test "An event can cause a transition to super state":
  var a = newAllTransAwsm()
  a.currentHandler = s1.toEventHandler
  a.dispatch(DEvt)
  # from s1, D transitions to s, then initial transition to s11
  check a.currentHandler == s11.toEventHandler

test "Transition to super state should enter via initial transition":
  var a = newAllTransAwsm()
  a.currentHandler = s1.toEventHandler
  a.entryCount = 0
  a.exitCount = 0
  a.dispatch(DEvt)
  check a.exitCount == 1  # exit s1
  check a.entryCount == 2  # enter s1, s11

test "Transition to sub state":
  var a = newAllTransAwsm()
  a.currentHandler = s1.toEventHandler
  a.dispatch(BEvt)
  check a.currentHandler == s11.toEventHandler

test "Transition to sub state should not exit the starting state":
  var a = newAllTransAwsm()
  a.currentHandler = s1.toEventHandler
  a.entryCount = 0
  a.exitCount = 0
  a.dispatch(BEvt)
  check a.exitCount == 0
  check a.entryCount == 1  # enter s11

test "Transition up two states":
  var a = newAllTransAwsm()
  a.currentHandler = s11.toEventHandler
  a.dispatch(HEvt)
  # After transition to s, follow initial transition to s11
  check a.currentHandler == s11.toEventHandler

test "Transition down two states":
  var a = newAllTransAwsm()
  a.currentHandler = s.toEventHandler
  a.dispatch(EEvt)
  check a.currentHandler == s11.toEventHandler

test "Transition up one, down one":
  var a = newAllTransAwsm()
  a.currentHandler = s1.toEventHandler
  a.entryCount = 0
  a.exitCount = 0
  a.dispatch(CEvt)
  check a.exitCount == 1  # exit s1
  check a.entryCount == 3  # enter s2, s21, s211
  # After transition to s2, follow initial transition to s211
  check a.currentHandler == s211.toEventHandler

test "Transition up one, down one (reverse from other test)":
  var a = newAllTransAwsm()
  a.currentHandler = s2.toEventHandler
  a.entryCount = 0
  a.exitCount = 0
  a.dispatch(CEvt)
  check a.exitCount == 1  # exit s2
  check a.entryCount == 2  # enter s1, s11
  # After transition to s1, follow initial transition to s11
  check a.currentHandler == s11.toEventHandler

test "Transition up two, down two":
  var a = newAllTransAwsm()
  a.currentHandler = s21.toEventHandler
  a.dispatch(FEvt)
  check a.currentHandler == s11.toEventHandler

test "Indirect initial transitions are taken":
  # Indirect initial transitions occur when a transition target
  # has an initial transition, which must be processed.
  var a = newAllTransAwsm()
  a.currentHandler = s211.toEventHandler
  a.dispatch(GEvt)
  # G transitions to s1, which has an initial transition to s11
  check a.currentHandler == s11.toEventHandler

test "Indirect initial transitions are taken after transition to same state":
  var a = newAllTransAwsm()
  a.currentHandler = s11.toEventHandler
  a.entryCount = 0
  a.exitCount = 0
  a.dispatch(AEvt)
  check a.exitCount == 2  # exit s11, exit s1
  check a.entryCount == 2  # enter s1, enter s11
  # After transition to s1, follow initial transition to s11
  check a.currentHandler == s11.toEventHandler

test "Sequential transitions from PSiCC2 Fig. 2.12":
  var a = newAllTransAwsm()
  a.init()
  check a.currentHandler == s211.toEventHandler
  a.dispatch(GEvt)  # s211 -G-> s1 (then initial to s11)
  check a.currentHandler == s11.toEventHandler
  a.dispatch(IEvt)  # s11 -I-> (handled, stay in s11)
  check a.currentHandler == s11.toEventHandler
  a.dispatch(AEvt)  # s11 -> s1 -A-> s1 (self-transition, then initial to s11)
  check a.currentHandler == s11.toEventHandler
  a.dispatch(DEvt)  # s11 -> s1 -D-> s (then initial to s11)
  check a.currentHandler == s11.toEventHandler
  a.dispatch(DEvt)  # s11 -D-> top (handled by s, me->foo = 0, stay in s11)
  check a.currentHandler == s11.toEventHandler
  check a.foo == 0
  a.dispatch(CEvt)  # s11 -> s1 -C-> s2 (then initial to s211)
  check a.currentHandler == s211.toEventHandler
  a.dispatch(EEvt)  # s211 -> s2 -E-> s1 (then initial to s11)
  check a.currentHandler == s11.toEventHandler
  a.dispatch(EEvt)  # s11 -> s -E-> s1 (then initial to s11)
  check a.currentHandler == s11.toEventHandler
  a.dispatch(GEvt)  # s11 -G-> s2 (then initial to s211)
  check a.currentHandler == s211.toEventHandler
  a.dispatch(IEvt)  # s211 -I-> (handled, stay in s211)
  check a.currentHandler == s211.toEventHandler
  a.dispatch(IEvt)  # s211 -I-> (handled, stay in s211)
  check a.currentHandler == s211.toEventHandler
