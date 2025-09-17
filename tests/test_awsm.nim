#!fmt: off

import unittest2

include awsm_all_trans


test "Plain states can test for state equality":
  var a = newAllTransAwsm()
  a.state = top
  check a.state == top

test "Converted states can test for state equality":
  var a = newAllTransAwsm()
  a.state = top.toEventHandler
  check a.state == top

test "Converted states can still access custom fields":
  var a = newAllTransAwsm()
  a.foo = 42
  a.state = top.toEventHandler
  check a.foo == 42

test "Transition from initial state through all InitSig transitions":
  var a = newAllTransAwsm()
  a.state = initial.toEventHandler
  a.init(ReservedEvt[InitSig])
  check a.state == s211.toEventHandler

test "Remain in current state":
  var a = newAllTransAwsm()
  a.state = s.toEventHandler
  a.entryCount = 0
  a.exitCount = 0
  a.dispatch(IEvt)
  check a.entryCount == 0
  check a.exitCount == 0
  check a.state == s.toEventHandler

test "Transition to current state":
  # A transition to current state involves exit and re-entry.
  var a = newAllTransAwsm()
  a.state = s1.toEventHandler
  a.entryCount = 0
  a.exitCount = 0
  a.dispatch(AEvt)
  check a.entryCount == 1
  check a.exitCount == 1
  check a.state == s1.toEventHandler

test "Transition to parent state":
  var a = newAllTransAwsm()
  a.state = s1.toEventHandler
  a.dispatch(DEvt)
  check a.state == s.toEventHandler

test "Transition to sub state":
  var a = newAllTransAwsm()
  a.state = s1.toEventHandler
  a.dispatch(BEvt)
  check a.state == s11.toEventHandler

test "Transition up two states":
  var a = newAllTransAwsm()
  a.state = s11.toEventHandler
  a.dispatch(HEvt)
  check a.state == s.toEventHandler

test "Transition down two states":
  var a = newAllTransAwsm()
  a.state = s.toEventHandler
  a.dispatch(EEvt)
  check a.state == s11.toEventHandler

