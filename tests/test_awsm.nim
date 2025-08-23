#!fmt: off

import std/unittest

include awsm_all_trans


test "Plain states can test for state equality":
  var a = newAllTransAwsm()
  a.state = top
  check a.state == top

test "Converted states can test for state equality":
  var a = newAllTransAwsm()
  a.state = top.toEventHandler
  check a.state == top

#test "AllTransAwsm initializes to s211":
#  var a = newAllTransAwsm()
#  a.state = initial.toEventHandler
#  a.init(ReservedEvt[InitSig])
#  check a.state == s211.toEventHandler
