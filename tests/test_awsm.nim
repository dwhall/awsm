#!fmt: off

import unittest2

include awsm_all_trans

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
  a.init(ReservedEvt[InitSig])
  check a.foo == 0
  check a.currentHandler == s211.toEventHandler

test "Initial transitions are taken from explicit 'initial' handler":
  var a = newAllTransAwsm()
  a.currentHandler = initial.toEventHandler
  a.init(ReservedEvt[InitSig])
  check a.foo == 0
  # Initial to s2, then to s211
  check a.currentHandler == s211.toEventHandler

test "Unhandled event remains in current state":
  var a = newAllTransAwsm()
  a.currentHandler = s.toEventHandler
  a.entryCount = 0
  a.exitCount = 0
  a.dispatch(AEvt)
  check a.entryCount == 0
  check a.exitCount == 0
  check a.currentHandler == s.toEventHandler

test "Handled event remains in current state":
  var a = newAllTransAwsm()
  a.currentHandler = s.toEventHandler
  a.entryCount = 0
  a.exitCount = 0
  a.dispatch(IEvt)
  check a.entryCount == 0
  check a.exitCount == 0
  check a.currentHandler == s.toEventHandler

test "Transition to same state should exit, re-enter and follow initial":
  var a = newAllTransAwsm()
  a.currentHandler = s1.toEventHandler
  a.entryCount = 0
  a.exitCount = 0
  a.dispatch(AEvt)
  check a.entryCount == 1
  check a.exitCount == 1
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
  check a.currentHandler == s.toEventHandler

test "Transition to super state should not re-enter the super state":
  var a = newAllTransAwsm()
  a.currentHandler = s1.toEventHandler
  a.entryCount = 0
  a.dispatch(DEvt)
  check a.entryCount == 0
  check a.currentHandler == s.toEventHandler

test "Transition to sub state":
  var a = newAllTransAwsm()
  a.currentHandler = s1.toEventHandler
  a.dispatch(BEvt)
  check a.currentHandler == s11.toEventHandler

test "Transition to sub state should not exit the starting state":
  var a = newAllTransAwsm()
  a.currentHandler = s1.toEventHandler
  a.exitCount = 0
  a.dispatch(BEvt)
  check a.exitCount == 0

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
  # should exit the source and enter the target (s2 doesn't affect counts)
  check a.entryCount == 0
  check a.exitCount == 1
  # After transition to s2, follow initial transition to s211
  check a.currentHandler == s211.toEventHandler

test "Transition up one, down one (reverse from other test)":
  var a = newAllTransAwsm()
  a.currentHandler = s2.toEventHandler
  a.entryCount = 0
  a.exitCount = 0
  a.dispatch(CEvt)
  # should exit the source and enter the target (s2 doesn't affect counts)
  check a.entryCount == 1
  check a.exitCount == 0
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
  #check a.currentHandler == s1.toEventHandler # this should fail, but passes
  check a.currentHandler == s11.toEventHandler # this should pass, but fails
