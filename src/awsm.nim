## Copyright 2025 Dean Hall
##
## awsm: actors with state machines.
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

  Actor = ref object of RootObj ## Actors have an event queue and can spawn children
    evtQueue: seq[Event]
    children: seq[Awsm]

  Awsm* = ref object of Actor ## Awsm is an Actor with a state machine
    currentHandler*: EventHandler

  EventHandler* = proc(self: Awsm, event: Event): HandlerReturn {.nimcall.}

  TransitionPath = array[MaxStateNestDepth, EventHandler]

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

template toEventHandler*[T: Awsm](
    handler: proc(self: T, event: Event): HandlerReturn {.nimcall.}
): EventHandler =
  ## Converts Awsm subtype EventHandler to Awsm EventHandler.
  ## The .nimcall pragma forces all state handlers to be written in Nim for typesafety
  cast[EventHandler](handler)

func newAwsm*(
    evtQueueDepth: Natural, numChildren: Natural, initialState: EventHandler
): Awsm =
  ## Create a new Awsm with the given event queue depth, number of children and initial state
  result.evtQueue = newSeqOfCap[Event](evtQueueDepth)
  result.children = newSeqOfCap[Awsm](numChildren)
  result.currentHandler = initialState

func postEvent*(self: Awsm, evt: Event) {.inline.} =
  ## Post an event to the Awsm's queue
  self.evtQueue.add(evt)

proc top*(self: Awsm, evt: Event): HandlerReturn {.nimcall.} =
  ## The top state ignores all events
  discard self
  discard evt
  RetIgnored

template returnTransitioned*(self: untyped, newState: untyped) =
  ## Ensures the handler returns "RetTransitioned" when the state changes
  self.currentHandler = newState.toEventHandler
  result = RetTransitioned

template returnSuper*(self: untyped, newState: untyped) =
  ## Ensures the handler returns "RetSuper" when the state changes
  self.currentHandler = newState.toEventHandler
  result = RetSuper

template trig*(self: Awsm, state: EventHandler, sig: Signal): HandlerReturn =
  ## Triggers an event with the given reserved signal
  state(self, ReservedEvt[sig])

template enter*(self: Awsm, state: EventHandler): HandlerReturn =
  ## Triggers entry action in an Awsm
  trig(self, state, EntrySig)

template exit*(self: Awsm, state: EventHandler): HandlerReturn =
  ## Triggers exit action in an Awsm
  trig(self, state, ExitSig)

####

proc init*(self: Awsm, evt: Event) =
  ## Execute the top-most initial transition and enter the target
  # Translated from PSiCC2.pdf, Listing 4.10, p 187
  let r = self.currentHandler(self, evt)
  assert r == RetTransitioned #, "Initial transition must return RetTransitioned"
  # Start at the top state
  var t: EventHandler = top
  while true:
    var path: TransitionPath
    var pathIdx = 0'i8
    # Save the target of the initial transition
    path[0] = self.currentHandler
    discard trig(self, self.currentHandler, EmptySig)
    while self.currentHandler != t:
      inc pathIdx
      path[pathIdx] = self.currentHandler
      discard trig(self, self.currentHandler, EmptySig)
    # Restore the target of the initial transition
    self.currentHandler = path[0]
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
  self.currentHandler = t

proc transitionSource(
    self: Awsm, current: var EventHandler, source: EventHandler
) =
  ## Exit current state up to the transition source
  while current != source:
    if RetHandled == trig(self, current, ExitSig):
      # Find superstate of current
      discard trig(self, current, EmptySig)
    # self.currentHandler holds the superstate
    current = self.currentHandler

proc transitionToSameState(self: Awsm, state: EventHandler): int8 {.inline.} =
  # Exit the current state.  Re-entering it happens when dispatch() calls executeEntryPath()
  discard exit(self, state)
  return 0'i8

proc transitionToSubState(
    self: Awsm, source: EventHandler, target: EventHandler
): int8 {.inline.} =
  discard trig(self, target, EmptySig)
  if self.currentHandler == source:
    self.currentHandler = target
    discard enter(self, target)
    return 0'i8
  else:
    return -1'i8 # Indicates need for complex transition handling

proc transitionToSuperState(
    self: Awsm, source: EventHandler, target: EventHandler
): int8 {.inline.} =
  discard trig(self, source, EmptySig)
  if self.currentHandler == target:
    discard exit(self, source)
    self.currentHandler = target
    return -2'i8  # return value indicates super-state transition
  else:
    return -1'i8 # Indicates need for complex transition handling

proc transitionUpAndDown(
    self: Awsm,
    path: var TransitionPath,
    source: EventHandler,
    target: var EventHandler,
): int8 =
  var pathIdx: int8
  var r: HandlerReturn

  # Store original target state
  let originalTarget = target

  pathIdx = -1'i8  # Start at -1 to avoid re-entering states
  target = self.currentHandler

  r = trig(self, target, EmptySig)

  # Find the Least Common Ancestor (LCA)
  while r == RetSuper:
    if self.currentHandler != source:  # Only add to path if not moving upward
      inc pathIdx
      path[pathIdx] = self.currentHandler
      r = trig(self, self.currentHandler, EmptySig)
    else:
      r = RetHandled

  # Exit source state if needed
  discard exit(self, source)

  # Restore target state
  target = originalTarget
  self.currentHandler = originalTarget
  return pathIdx

proc executeEntryPath(self: Awsm, path: TransitionPath, pathIdx: int8) =
  ## Executes entry actions along the path to target state
  var idx = pathIdx
  while idx >= 0'i8:
    discard enter(self, path[idx])
    dec idx

proc handleHierarchicalEvent(self: Awsm, evt: Event): HandlerReturn =
  ## Processes event hierarchically up the state chain
  var s: EventHandler
  var r: HandlerReturn

  while true:
    s = self.currentHandler
    r = s(self, evt)
    if r != RetSuper:
      break

  return r

proc dispatch*(self: Awsm, evt: Event) =
  ## The current state handles the event
  # Simplified main dispatch logic
  var path: TransitionPath
  var current: EventHandler = self.currentHandler
  var pathIdx: int8

  # Process the event hierarchically
  let r = handleHierarchicalEvent(self, evt)

  if r == RetTransitioned:
    let target = self.currentHandler
    let source = current

    transitionSource(self, current, source)

    # Determine transition type and handle accordingly
    if source == target:
      pathIdx = transitionToSameState(self, source)
    else:
      pathIdx = transitionToSubState(self, source, target)
      if pathIdx < 0'i8:
        pathIdx = transitionToSuperState(self, source, target)
        if pathIdx == -2'i8:  # super-state transition completed
          return  # Skip entry actions
        if pathIdx < 0'i8:
          var targetState = target
          pathIdx = transitionUpAndDown(self, path, source, targetState)
          current = targetState

    # Restore target and execute entry path if needed
    if pathIdx >= 0'i8:
      path[0] = target
      executeEntryPath(self, path, pathIdx)
  else:
    # Only restore original state if no transition occurred
    self.currentHandler = current
