#!fmt: off

# This is a pedagogical state machine that contains all possible state
# transition topologies up to four levels of state nesting;
# making it a good example for testing the code which handles transitions.
# Reference: PSiCC2, Figure 2.11, p. 88 (PDF p.105)
# https://www.state-machine.com/doc/PSiCC2.pdf
# Fig 2.11 is updated in the PSiCC2 Errata, p. 6 (PDF p.11):
# https://www.state-machine.com/doc/PSiCC2_Updates+Errata.pdf

import awsm

type
  InputSignal = enum
    A = PublicSignalRange.low, B, C, D, E, F, G, H, I

  AllTransAwsm = ref object of Awsm
    foo: int
    entryCount: int # strictly for testing
    exitCount: int  # strictly for testing

const
  ASig = Signal(A)
  BSig = Signal(B)
  CSig = Signal(C)
  DSig = Signal(D)
  ESig = Signal(E)
  FSig = Signal(F)
  GSig = Signal(G)
  HSig = Signal(H)
  ISig = Signal(I)

  AEvt = Event(sig:ASig, val:0)
  BEvt = Event(sig:BSig, val:0)
  CEvt = Event(sig:CSig, val:0)
  DEvt = Event(sig:DSig, val:0)
  EEvt = Event(sig:ESig, val:0)
  FEvt = Event(sig:FSig, val:0)
  GEvt = Event(sig:GSig, val:0)
  HEvt = Event(sig:HSig, val:0)
  IEvt = Event(sig:ISig, val:0)

# Fwd decls
proc s2(self: AllTransAwsm, evt: Event): HandlerReturn
proc s11(self: AllTransAwsm, evt: Event): HandlerReturn
proc s211(self: AllTransAwsm, evt: Event): HandlerReturn

proc initial(self: AllTransAwsm, evt: Event): HandlerReturn =
  discard evt
  self.foo = 0
  returnTransitioned(self, s2)

proc newAllTransAwsm(): AllTransAwsm =
  var self = AllTransAwsm()
  self.currentHandler = initial.toEventHandler
  result = self

proc s(self: AllTransAwsm, evt: Event): HandlerReturn =
  case evt.sig:
  of InitSig:
    returnTransitioned(self, s11)
  of EntrySig:
    inc self.entryCount
    return RetHandled
  of ExitSig:
    inc self.exitCount
    return RetHandled
  of ESig:
    returnTransitioned(self, s11)
  of ISig:
    if self.foo != 0: self.foo = 0
    return RetHandled
  else:
    returnSuper(self, top)

proc s1(self: AllTransAwsm, evt: Event): HandlerReturn =
  case evt.sig:
  of InitSig:
    returnTransitioned(self, s11)
  of EntrySig:
    inc self.entryCount
    return RetHandled
  of ExitSig:
    inc self.exitCount
    return RetHandled
  of ASig:
    returnTransitioned(self, s1)
  of BSig:
    returnTransitioned(self, s11)
  of CSig:
    returnTransitioned(self, s2)
  of DSig:
    if self.foo == 0: self.foo = 1
    returnTransitioned(self, s)
  of FSig:
    returnTransitioned(self, s211)
  of ISig:
    return RetHandled
  else:
    returnSuper(self, s)

proc s11(self: AllTransAwsm, evt: Event): HandlerReturn =
  case evt.sig:
  of EntrySig:
    return RetHandled
  of ExitSig:
    return RetHandled
  of DSig:
    if self.foo != 0: self.foo = 0
    returnTransitioned(self, s1)
  of GSig:
    returnTransitioned(self, s211)
  of HSig:
    returnTransitioned(self, s)
  else:
    returnSuper(self, s1)

proc s2(self: AllTransAwsm, evt: Event): HandlerReturn =
  case evt.sig:
  of InitSig:
    returnTransitioned(self, s211)
  of EntrySig:
    return RetHandled
  of ExitSig:
    return RetHandled
  of CSig:
    returnTransitioned(self, s1)
  of FSig:
    returnTransitioned(self, s11)
  of ISig:
    if self.foo == 0: self.foo = 1
    return RetHandled
  else:
    returnSuper(self, s)

proc s21(self: AllTransAwsm, evt: Event): HandlerReturn =
  case evt.sig:
  of InitSig:
    returnTransitioned(self, s211)
  of EntrySig:
    return RetHandled
  of ExitSig:
    return RetHandled
  of ASig:
    returnTransitioned(self, s21)
  of BSig:
    returnTransitioned(self, s211)
  of GSig:
    returnTransitioned(self, s1)
  else:
    returnSuper(self, s2)

proc s211(self: AllTransAwsm, evt: Event): HandlerReturn =
  case evt.sig:
  of DSig:
    returnTransitioned(self, s21)
  of HSig:
    returnTransitioned(self, s)
  else:
    returnSuper(self, s21)
