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

const MaxHandlerNestDepth = 6

## A Signal, whose size is defined at compile-time
## is an ordinal value that discriminates an Event
when defined(sig16):
  type Signal = int16
elif defined(sig32):
  type Signal = int32
else:
  type Signal = int8

## There are three categories of signals for different uses
type
  PrvSignal* = Signal.low .. -1.Signal
  SysSignal = 0.Signal .. 3.Signal
  PubSignal* = SysSignal.high + 1.Signal .. Signal.high

## SysSignals are used internally by the Awsm framework
## for hierarchical traversal of nested event handlers
const
  Empty = 0.SysSignal
  Entry = 1.SysSignal
  Exit = 2.SysSignal
  Init = 3.SysSignal

type
  Event* = object
    sig*: Signal
    val*: Value

  Actor = ref object of RootObj ## Actors have an event queue and can spawn children
    evtQueue: seq[Event]
    children: seq[Awsm]

  Awsm* = ref object of Actor ## Awsm is an Actor with a state machine
    currentHandler*: EventHandler

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

  EventHandler* = proc(self: Awsm, event: Event): HandlerReturn {.nimcall.}

  TransitionPath = array[MaxHandlerNestDepth, EventHandler]

const
  ## System signals
  EmptySig* = Empty.Signal
  EntrySig* = Entry.Signal
  ExitSig* = Exit.Signal
  InitSig* = Init.Signal
  ## System events (index via system signals *Sig)
  ReservedEvt* = [
    Event(sig: EmptySig, val: default(Value)),
    Event(sig: EntrySig, val: default(Value)),
    Event(sig: ExitSig, val: default(Value)),
    Event(sig: InitSig, val: default(Value)),
  ]

when not defined(release):
  func `$`*(s: EventHandler): string =
    result = s.repr

template toEventHandler*[T: Awsm](
    handler: proc(self: T, event: Event): HandlerReturn {.nimcall.}
): EventHandler =
  ## Converts Awsm subtype EventHandler to Awsm EventHandler.
  ## The .nimcall pragma forces all handlers to be written in Nim for typesafety
  cast[EventHandler](handler)

func newAwsm*(
    evtQueueDepth: Natural, numChildren: Natural, initialHandler: EventHandler
): Awsm =
  ## Create a new Awsm with the given event queue depth, number of children and initial handler
  result.evtQueue = newSeqOfCap[Event](evtQueueDepth)
  result.children = newSeqOfCap[Awsm](numChildren)
  result.currentHandler = initialHandler

func postEvent*(self: Awsm, evt: Event) {.inline.} =
  ## Post an event to the Awsm's queue
  self.evtQueue.add(evt)

proc top*(self: Awsm, evt: Event): HandlerReturn {.nimcall.} =
  ## The top handler ignores all events
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

template trig(self: Awsm, state: EventHandler, sig: SysSignal): HandlerReturn =
  ## Triggers an event with the given reserved signal
  state(self, ReservedEvt[sig.Signal])

template enter*(self: Awsm, state: EventHandler): HandlerReturn =
  ## Triggers entry action in an Awsm
  trig(self, state, Entry)

template exit*(self: Awsm, state: EventHandler): HandlerReturn =
  ## Triggers exit action in an Awsm
  trig(self, state, Exit)

####

proc handleInitialTransition(self: Awsm, sourceState: EventHandler): EventHandler =
  ## Handles initial transitions starting from sourceState
  ## Returns the final target state after all initial transitions
  result = sourceState
  if RetTransitioned == self.trig(sourceState, Init):
    var path: TransitionPath
    var pathIdx = 0'i8
    # Save the target of the initial transition
    path[0] = self.currentHandler
    discard trig(self, self.currentHandler, Empty)
    while self.currentHandler != sourceState:
      inc pathIdx
      path[pathIdx] = self.currentHandler
      discard trig(self, self.currentHandler, Empty)
    # Restore the target of the initial transition
    self.currentHandler = path[0]
    # Retrace the entry path in reverse order
    while pathIdx >= 0'i8:
      discard enter(self, path[pathIdx])
      dec pathIdx
    result = handleInitialTransition(self, path[0])

proc init*(self: Awsm, evt: Event) =
  ## Execute the top-most initial transition and enter the target
  let r = self.currentHandler(self, evt)
  assert r == RetTransitioned
  self.currentHandler = handleInitialTransition(self, self.currentHandler)

proc exitUpTo(self: Awsm, current: var EventHandler, source: EventHandler) =
  ## Exit current state up to the transition source
  while current != source:
    if RetHandled == trig(self, current, Exit):
      # Find superstate of current
      discard trig(self, current, Empty)
    current = self.currentHandler # the superstate

proc transitionToSameState(self: Awsm, state: EventHandler): int8 {.inline.} =
  discard exit(self, state)
  discard enter(self, state)
  # Set current handler to the state we just re-entered
  self.currentHandler = state
  return -1'i8 # no additional entry path needed

proc transitionToSubState(
    self: Awsm, source: EventHandler, target: EventHandler
): int8 {.inline.} =
  discard trig(self, target, Empty)
  if self.currentHandler == source:
    self.currentHandler = target
    discard enter(self, target)
    return -1'i8 # no additional entry path needed
  else:
    return -2'i8 # complex transition handling needed

proc transitionToSuperState(
    self: Awsm, source: EventHandler, target: EventHandler
): int8 {.inline.} =
  discard trig(self, source, Empty)
  if self.currentHandler == target:
    discard exit(self, source)
    self.currentHandler = target
    return -3'i8 # super-state transition (no entry)
  else:
    return -2'i8 # complex transition handling needed

proc transitionUpAndDown(
    self: Awsm, path: var TransitionPath, source: EventHandler, target: var EventHandler
): int8 {.inline.} =
  var pathIdx = -1'i8 # Start at -1 to avoid re-entering states
  var r: HandlerReturn
  let originalTarget = target

  target = self.currentHandler

  # Find the Least Common Ancestor (LCA)
  r = trig(self, target, Empty) # superstate of target
  while r == RetSuper:
    if self.currentHandler != source: # add to path if not moving upward
      inc pathIdx
      path[pathIdx] = self.currentHandler
      r = trig(self, self.currentHandler, Empty)
    else:
      r = RetHandled
  discard exit(self, source)
  target = originalTarget
  self.currentHandler = originalTarget
  return pathIdx

proc executeEntryPath(self: Awsm, path: TransitionPath, pathIdx: int8) =
  ## Executes entry actions along the path to target state
  var idx = pathIdx
  while idx >= 0'i8:
    discard enter(self, path[idx])
    dec idx

proc traceEventUpward(self: Awsm, evt: Event): tuple[result: HandlerReturn, source: EventHandler] =
  ## Trace an event up the hierarchy as needed.
  ## Returns the result and the state that handled the event (source of transition)
  ## NOTE: This function may change self.currentHandler
  var sourceState = self.currentHandler
  result.result = sourceState(self, evt)
  while result.result == RetSuper:
    sourceState = self.currentHandler  # Save the current state before calling it
    result.result = sourceState(self, evt)
  result.source = sourceState  # The state that returned something other than RetSuper

proc dispatch*(self: Awsm, evt: Event) =
  ## Process the event through the Awsm's handler
  # Exit early if the event does not cause a transition
  let startState: EventHandler = self.currentHandler
  let (status, sourceState) = traceEventUpward(self, evt)
  if status != RetTransitioned:
    self.currentHandler = startState
    return

  var path: TransitionPath
  var pathIdx: int8
  let target = self.currentHandler  # Where we're transitioning to (set by returnTransitioned)
  let source = sourceState          # Where the transition was triggered
  var current = startState          # Where we started from

  exitUpTo(self, current, source)

  # Determine transition type and handle accordingly
  if source == target:
    # Self-transition: exit, enter, then handle initial transitions
    pathIdx = transitionToSameState(self, source)
  else:
    pathIdx = transitionToSubState(self, source, target)
    if pathIdx == -2'i8: # Need complex transition
      pathIdx = transitionToSuperState(self, source, target)
      if pathIdx == -3'i8: # super-state transition completed (no entry action)
        # For superstate transitions, no initial transition handling
        return
      if pathIdx == -2'i8: # Still need complex transition
        var targetState = target
        pathIdx = transitionUpAndDown(self, path, source, targetState)
        current = targetState
        # Execute entry path for complex transitions
        if pathIdx >= 0'i8:
          executeEntryPath(self, path, pathIdx)
        # Now enter the target state itself
        discard enter(self, target)
        # Set handler to target before checking initial transitions
        self.currentHandler = target

  # Handle initial transitions from the target state
  # This works for: same-state, sub-state, and complex transitions
  # (but not superstate transitions which return early above)
  self.currentHandler = handleInitialTransition(self, target)
