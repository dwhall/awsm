## Copyright 2025 Dean Hall
##
## Actor with State Machine (Awsm)
## an event-driven framework for real-time concurrency in embedded systems
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
  # -128 ..  -1 : user events encapsulated in a software unit
  Signal* = int8
const sizeOfSignal = sizeof(Signal)
type
  SysSignal* {.size: sizeOfSignal.} = enum
    Empty
    Entry
    Exit
    Init
    User
    Priv = -128

  Event* = object
    sig*: Signal
    val*: Value

  Actor = ref object of RootObj
    ## Actors have an event queue and can spawn children
    evtQueue: seq[Event]
    children: seq[Awsm]
  Awsm* = ref object of Actor
    ## Awsm is an Actor with a state machine
    state*: EventHandler

  EventHandler* = proc(self: Awsm, event: Event): HandlerReturn {.nimcall.}

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

template toEventHandler*[T](
    handler: proc(self: T, event: Event): HandlerReturn {.nimcall.}
): proc(self: Awsm, event: Event): HandlerReturn {.nimcall.} =
  ## Converts Awsm subtype EventHandler to Awsm EventHandler.
  ## .nimcall forces all state handlers to be written in Nim for typesafety
  proc(self: Awsm, event: Event): HandlerReturn {.nimcall.} =
    var app = T(self)
    handler(app, event)

func newAwsm*(
    evtQueueDepth: Natural, numChildren: Natural, initialState: EventHandler
): Awsm =
  ## Create a new Awsm with the given event queue depth and number of children
  result.evtQueue = newSeqOfCap[Event](evtQueueDepth)
  result.children = newSeqOfCap[Awsm](numChildren)
  result.state = initialState

func postEvent*(self: Awsm, evt: Event) {.inline.} =
  ## Post an event to the Awsm's queue
  self.evtQueue.add(evt)

proc top*(self: Awsm, evt: Event): HandlerReturn {.nimcall.} =
  ## The top state ignores all events
  discard self
  discard evt
  RetIgnored

template returnTransitioned*(self: untyped, newState: untyped) =
  ## Make sure the handler returns "RetTransitioned" when the state changes
  self.state = newState.toEventHandler
  result = RetTransitioned

template returnSuper*(self: Awsm, newState: untyped) =
  ## Make sure the handler returns "RetSuper" when the state changes
  self.state = newState.toEventHandler
  result = RetSuper

template trig*(self: Awsm, state: EventHandler, sig: Signal): HandlerReturn =
  ## Trigger an event with the given signal and value
  state(self, ReservedEvt[sig])

template enter*(self: Awsm, state: EventHandler): HandlerReturn =
  ## Trigger entry action in an Awsm
  trig(self, state, EntrySig)

template exit*(self: Awsm, state: EventHandler): HandlerReturn =
  ## Trigger exit action in an Awsm
  trig(self, state, ExitSig)

####

proc init*(self: Awsm, evt: Event) =
  ## Execute the top-most initial transition and enter the target
  # Translated from PSiCC2.pdf, Listing 4.10, p 187
  let r = self.state(self, evt)
  assert r == RetTransitioned #, "Initial transition must return RetTransitioned"
  # Start at the top state
  var t: EventHandler = top
  while true:
    var path: array[MaxStateNestDepth, EventHandler]
    var pathIdx = 0'i8
    # Save the target of the initial transition
    path[0] = self.state
    discard trig(self, self.state, EmptySig)
    while self.state != t:
      inc pathIdx
      path[pathIdx] = self.state
      discard trig(self, self.state, EmptySig)
    # Restore the target of the initial transition
    self.state = path[0]
    # Retrace the entry path in reverse (desired) order
    while true:
      discard enter(self, path[pathIdx])
      dec pathIdx
      if pathIdx < 0'i8:
        break
    # Current state becomes the new source
    t = path[0]
    if RetTransitioned != self.trig(t, InitSig):
      break
  self.state = t

proc travelToTransitionSource(self: Awsm, current: var EventHandler, source: EventHandler) =
  ## Exit current state up to the transition source
  while current != source:
    if RetHandled == trig(self, current, ExitSig):
      # Find superstate of current
      discard trig(self, current, EmptySig)
    # self.state holds the superstate
    current = self.state

proc handleSelfTransition(self: Awsm, state: EventHandler): int8 {.inline.} =
  ## Handle transition from state to itself
  discard exit(self, state)
  return 0'i8

proc handleTransitionToParent(self: Awsm, source: EventHandler, target: EventHandler): int8 {.inline.} =
  ## Handle transition to parent state
  discard trig(self, target, EmptySig)
  let parent = self.state
  if source == parent:
    return 0'i8
  else:
    return -1'i8  # Indicates need for complex transition handling

proc handleTransitionToChild(self: Awsm, source: EventHandler, target: EventHandler): int8 {.inline.} =
  ## Handle transition to child state
  discard trig(self, source, EmptySig)
  if self.state == target:
    discard exit(self, source)
    return 0'i8
  else:
    return -1'i8  # Indicates need for complex transition handling

proc handleComplexTransition(self: Awsm, path: var array[MaxStateNestDepth, EventHandler], source: EventHandler, target: var EventHandler): int8 =
  ## Handle complex state transitions (LCA algorithm)
  var pathIdx: int8
  var pathIdxHelper: int8
  var r: HandlerReturn

  if self.state == path[0]:
    discard exit(self, source)
    return 0'i8
  else:
    pathIdxHelper = 0'i8
    pathIdx = 1'i8
    path[1] = target
    target = self.state
    r = trig(self, path[1], EmptySig)

    # Find the Least Common Ancestor (LCA)
    while r == RetSuper:
      inc pathIdx
      path[pathIdx] = self.state
      if self.state == source:
        pathIdxHelper = 1'i8
        dec pathIdx
        r = RetHandled
      else:
        r = trig(self, self.state, EmptySig)

    if pathIdxHelper == 0'i8:
      discard exit(self, source)
      # Check the rest of source->super path
      pathIdxHelper = pathIdx
      r = RetIgnored

      # Find if target is in the exit path
      while pathIdxHelper >= 0'i8:
        if target == path[pathIdxHelper]:
          r = RetHandled
          pathIdx = pathIdxHelper - 1'i8
          break
        dec pathIdxHelper

      # Exit states until LCA is found
      if r != RetHandled:
        while true:
          if RetHandled == trig(self, target, ExitSig):
            discard trig(self, target, EmptySig)
          target = self.state

          # Check if we've reached the LCA
          pathIdxHelper = pathIdx
          while pathIdxHelper >= 0'i8:
            if target == path[pathIdxHelper]:
              pathIdx = pathIdxHelper - 1'i8
              r = RetHandled
              break
            dec pathIdxHelper

          if r == RetHandled:
            break

    return pathIdx

proc executeEntryPath(self: Awsm, path: array[MaxStateNestDepth, EventHandler], pathIdx: int8) =
  ## Execute entry actions along the path to target state
  var idx = pathIdx
  while idx >= 0'i8:
    discard enter(self, path[idx])
    dec idx

proc handleHierarchicalEvent(self: Awsm, evt: Event): HandlerReturn =
  ## Process event hierarchically up the state chain
  var s: EventHandler
  var r: HandlerReturn

  while true:
    s = self.state
    r = s(self, evt)
    if r != RetSuper:
      break

  return r

proc dispatch*(self: Awsm, evt: Event) =
  ## Have the current state handle the event
  # Simplified main dispatch logic
  var path: array[MaxStateNestDepth, EventHandler]
  var current: EventHandler = self.state
  var pathIdx: int8

  # Process the event hierarchically
  let r = handleHierarchicalEvent(self, evt)

  if r == RetTransitioned:
    let target = self.state
    let source = current

    travelToTransitionSource(self, current, source)

    # Determine transition type and handle accordingly
    if source == target:
      pathIdx = handleSelfTransition(self, source)
    else:
      pathIdx = handleTransitionToParent(self, source, target)
      if pathIdx < 0:
        pathIdx = handleTransitionToChild(self, source, target)
        if pathIdx < 0:
          var targetState = target
          pathIdx = handleComplexTransition(self, path, source, targetState)
          current = targetState

    # Restore target and execute entry path if needed
    if pathIdx >= 0:
      path[0] = target
      executeEntryPath(self, path, pathIdx)

  else:
    # Only restore original state if no transition occurred
    self.state = current



