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

test "Transition from initial state through all InitSig transitions":
  var a = newAllTransAwsm()
  a.currentHandler = initial.toEventHandler
  a.init(ReservedEvt[InitSig])
  check a.currentHandler == s211.toEventHandler

test "Remain in current state":
  var a = newAllTransAwsm()
  a.currentHandler = s.toEventHandler
  a.entryCount = 0
  a.exitCount = 0
  a.dispatch(IEvt)
  check a.entryCount == 0
  check a.exitCount == 0
  check a.currentHandler == s.toEventHandler

test "Transition to current state":
  # A transition to current state involves exit and re-entry.
  var a = newAllTransAwsm()
  a.currentHandler = s1.toEventHandler
  a.entryCount = 0
  a.exitCount = 0
  a.dispatch(AEvt)
  check a.entryCount == 1
  check a.exitCount == 1
  check a.currentHandler == s1.toEventHandler

test "Transition to parent state":
  var a = newAllTransAwsm()
  a.currentHandler = s1.toEventHandler
  a.dispatch(DEvt)
  check a.currentHandler == s.toEventHandler

test "Transition to parent state should not re-enter parent":
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

test "Transition to sub state should not exit source":
  var a = newAllTransAwsm()
  a.currentHandler = s1.toEventHandler
  a.exitCount = 0
  a.dispatch(BEvt)
  check a.exitCount == 0

test "Transition up two states":
  var a = newAllTransAwsm()
  a.currentHandler = s11.toEventHandler
  a.dispatch(HEvt)
  check a.currentHandler == s.toEventHandler

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
  check a.currentHandler == s2.toEventHandler

test "Transition up one, down one (reverse from other test)":
  var a = newAllTransAwsm()
  a.currentHandler = s2.toEventHandler
  a.entryCount = 0
  a.exitCount = 0
  a.dispatch(CEvt)
  # should exit the source and enter the target (s2 doesn't affect counts)
  check a.entryCount == 1
  check a.exitCount == 0
  check a.currentHandler == s1.toEventHandler

test "Transition up two, down two":
  var a = newAllTransAwsm()
  a.currentHandler = s21.toEventHandler
  a.dispatch(FEvt)
  check a.currentHandler == s11.toEventHandler

test "Initial transitions are respected":
  var a = newAllTransAwsm()
  a.init(ReservedEvt[InitSig])
  check a.currentHandler == s211.toEventHandler
  check a.foo == 0
