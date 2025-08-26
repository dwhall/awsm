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

test "Transition to current state":
  var a = newAllTransAwsm()
  a.state = s.toEventHandler
  a.dispatch(IEvt)
  check a.state == s.toEventHandler

test "Transition to parent state":
  var a = newAllTransAwsm()
  a.state = s1.toEventHandler
  a.dispatch(DEvt)
  check a.state == s.toEventHandler
