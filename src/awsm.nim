## Copyright 2025 Dean Hall
##
## Actor with State Machine (Awsm)
## an event-driven framework for embedded systems
##

# Allow the Value type to be defined at compile-time,
# default to 32-bit signed
when defined(val64):
  type Value* = int64
elif defined(val16):
  type Value* = int16
else:
  type Value* = int32

const MaxStateNestDepth = 6

type
  HandlerReturn* = enum
    RetSuper
    #RetSuperSub
    RetUnhandled
    RetHandled
    RetIgnored
    RetEntry
    RetExit
    #RetNull
    RetTransitioned
    #RetTransInit
    #RetTransEp
    #RetTransHist
    #RetTransXp

  # Signal ranges:
  #    0 .. 127 : system and system-wide user events
  # -128 ..  -1 : local user events
  Signal* = int8
  SysSignal = enum
    Empty
    Entry
    Exit
    Init
    User

  Event* = object
    sig: Signal
    val: Value

  EventHandler* = proc(self: var Awsm, evt: Event): HandlerReturn

  Awsm* = ref object
    evtQueue: seq[Event]
    children: seq[Awsm]
    state: EventHandler

const
  EmptySig* = Signal(Empty)
  EntrySig* = Signal(Entry)
  ExitSig* = Signal(Exit)
  InitSig* = Signal(Init)
  UserSig* = Signal(User)
  ReservedEvt* = [
    Event(sig: EmptySig, val: default(Value)),
    Event(sig: EntrySig, val: default(Value)),
    Event(sig: ExitSig, val: default(Value)),
    Event(sig: InitSig, val: default(Value)),
  ]

func ctor*(self: var Awsm, initialState: EventHandler) =
  self.state = initialState

func postEvent*(self: var Awsm, evt: Event) {.inline.} =
  ## Post an event to the Awsm's queue
  self.evtQueue.add(evt)

proc top*(self: var Awsm, evt: Event): HandlerReturn =
  ## The top state ignores all events
  discard self
  discard evt
  RetIgnored

template returnTransitioned*(self: var Awsm, newState: EventHandler) =
  ## Make sure the handler returns "RetTransitioned" when the state changes
  self.state = newState
  result = RetTransitioned

template returnSuper*(self: var Awsm, newState: EventHandler) =
  ## Make sure the handler returns "RetSuper" when the state changes
  self.state = newState
  result = RetSuper

template trig*(self: var Awsm, state: EventHandler, sig: Signal): untyped =
  ## Trigger an event with the given signal and value
  state(self, ReservedEvt[sig])

template enter*(self: var Awsm, state: EventHandler): untyped =
  ## Trigger entry action in an Awsm
  trig(self, state, EntrySig)

template exit*(self: var Awsm, state: EventHandler): untyped =
  ## Trigger exit action in an Awsm
  trig(self, state, ExitSig)

####

proc init*(self: var Awsm, evt: Event) =
  ## Execute the top-most initial transition and enter the target
  # translated from PSiCC2.pdf, Listing 4.10, p 187
  let r = self.state(self, evt)
  assert r == RetTransitioned #, "Initial transition must return RetTransitioned"
  # start at the top state
  var t: EventHandler = top
  while true:
    var path: array[MaxStateNestDepth, EventHandler]
    var pathIdx = 0'i8
    # save the target of the initial transition
    path[0] = self.state
    discard trig(self, self.state, EmptySig)
    while self.state != t:
      inc pathIdx
      path[pathIdx] = self.state
      discard trig(self, self.state, EmptySig)
    # restore the target of the initial transition
    self.state = path[0]
    # retrace the entry path in reverse (desired) order
    while true:
      discard enter(self, path[pathIdx])
      dec pathIdx
      if pathIdx < 0'i8:
        break
    # current state becomes the new source
    t = path[0]
    if RetTransitioned != self.trig(t, InitSig):
      break
  self.state = t

proc dispatch*(self: var Awsm, evt: Event) =
  ## Have the current state handle the event
  # translated from PSiCC2.pdf, Listing 4.11, p 190
  var path: array[MaxStateNestDepth, EventHandler]
  var r: HandlerReturn
  var s: EventHandler
  var t: EventHandler = self.state
  # process the event hierarchically
  while true:
    s = self.state
    r = s(self, evt)
    if r != RetSuper:
      break
  if r == RetTransitioned:
    var pathIdx = -1'i8
    var pathIdxHelper: int8
    # save the target of the transition
    path[0] = me.state
    path[1] = t
    # exit current state to transition source
    while t != s:
      if RetHandled == trig(t, ExitSig):
        # find superstate of t
        trig(t, EmptySig)
      # me.state holds the superstate
      t = me.state
    # implementation translated from PSiCC2.pdf, Listing 4.12, p 194
    # target of the transition
    t = path[0]
    if s == t:
      exit(self, s)
      ip = 0'i8
    else:
      trig(self, t, EmptySig)
      t = me.state
      if s == t:
        ip = 0'i8
      else:
        trig(self, s, EmptySig)
        if me.state == t:
          exit(self, s)
          ip = 0'i8
        else:
          if me.state == path[0]:
            exit(self, s)
          else:
            pathIdxHelper = 0'i8
            pathIdx = 1'i8
            path[1] = t
            t = me.state
            r = trig(self, path[1], EmptySig)
            while r == RetSuper:
              inc pathIdx
              path[pathIdx] = me.state
              if me.state == s:
                pathIdxHelper = 1'i8
                dec pathIdx
                r = RetHandled
              else:
                r = trig(self, me.state, EmptySig)
            if pathIdxHelper == 0'i8:
              exit(self, s)
              # (f) check the rest of source->super
              pathIdxHelper = pathIdx
              r = RetIgnored
              while true:
                if t == path[pathIdxHelper]:
                  r = RetHandled
                  pathIdx = pathIdxHelper - 1'i8
                  pathIdxHelper = -1'i8
                else:
                  dec pathIdxHelper
                if pathIdxHelper > 0'i8:
                  break
              if r != RetHandled:
                # (g)
                r = RetIgnored
                while true:
                  if RetHandled == trig(t, ExitSig):
                    trig(t, EmptySig)
                  t = me.state
                  pathIdxHelper = pathIdx
                  while true:
                    if t == path[pathIdxHelper]:
                      pathIdx = pathIdxHelper - 1'i8
                      pathIdxHelper = -1'i8
                    else:
                      dec pathIdxHelper
                    if pathIdxHelper >= 0'i8:
                      break
                  if r != RetHandled:
                    break

  # p 196, line (12)
  # set new state or restore the current state
  me.state = t
