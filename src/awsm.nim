## Copyright 2025 Dean Hall
##
## awsm: actors with state machines.
## an event-driven framework for real-time concurrency in embedded systems
##

## The Signal is an ordinal value that discriminates an Event.
## Its size is defined at compile-time, defaulting to 8-bit signed.
when defined(sig16):
  type Signal* = int16
elif defined(sig32):
  type Signal* = int32
else:
  type Signal* = int8

## The Value is an optional, arbitrary value the accompanies a signal.
## Its size is defined at compile-time, defaulting to 32-bit signed.
when defined(val64):
  type Value* = int64
elif defined(val16):
  type Value* = int16
else:
  type Value* = int32

type
  ## Actors receive events in a FIFO queue.
  ## Actors can spawn children.
  Actor = ref object of RootObj
    evtQueue: seq[Event]
    children: seq[Awsm]

  ## Awsm is an Actor with a state machine
  Awsm* = ref object of Actor
    currentHandler*: EventHandler

  ## Events are the primary communication between Actors.
  ## Events are posted from one Actor to a child Actor,
  ## or published to the framework so that every Actor
  ## subscribed to that Signal receives the Event.
  Event* = object
    sig*: Signal
    val*: Value

  ## An Actor has one or more EventHandler, which can transition
  ## to another EventHandler in response to an Event; forming a state machine.
  EventHandler* = proc(self: Awsm, event: Event): HandlerReturn {.nimcall.}

  ## Every EventHandler returns a HandlerReturn code to indicate
  ## how the event was processed.
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

  ## There are three categories of signals for different uses.
  ## Private signals are posted to self and children only; they cannot be published.
  ## System signals are reserved for use by the Awsm framework.
  ## Public signals are used for inter-actor communication via publishing,
  ## but may also be posted to self and children.
  PrvSignal* = Signal.low .. -1.Signal
  SysSignal = 0.Signal .. 3.Signal
  PubSignal* = SysSignal.high + 1.Signal .. Signal.high

const
  ## The maximum nesting depth of event handlers
  MaxHandlerNestDepth = 6

  ## SysSignals are used internally by the Awsm framework
  ## for hierarchical traversal of nested event handlers
  Empty = 0.SysSignal
  Entry = 1.SysSignal
  Exit = 2.SysSignal
  Init = 3.SysSignal
  ## System signals
  EmptySig* = Empty.Signal
  EntrySig* = Entry.Signal
  ExitSig* = Exit.Signal
  InitSig* = Init.Signal
  ## System events (index via system signals *Sig) are declared constants
  ## as an optimization to avoid repeated construction of often-used events
  ReservedEvt* = [
    Event(sig: EmptySig, val: default(Value)),
    Event(sig: EntrySig, val: default(Value)),
    Event(sig: ExitSig, val: default(Value)),
    Event(sig: InitSig, val: default(Value)),
  ]

when not defined(release):
  func `$`*(s: EventHandler): string =
    ## Emits the handler's address as a string for indentification
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

proc followInitialTransitions(self: Awsm, source: EventHandler): EventHandler =
  ## Follows an initial transition chain if it exists.
  ## Returns the final target state after all initial transitions
  result = source
  if RetTransitioned == self.trig(source, Init):
    var path = newSeqOfCap[EventHandler](MaxHandlerNestDepth)
    # Build path from initial transition target, up to source
    path.add(self.currentHandler) # initial transition target
    discard trig(self, self.currentHandler, Empty)
    while self.currentHandler != source:
      path.add(self.currentHandler)
      discard trig(self, self.currentHandler, Empty)
    # Restore the initial transition target
    self.currentHandler = path[0]
    # Enter the states in the reverse order of the path (downward to target)
    for i in countdown(path.high, 0):
      discard enter(self, path[i])
    # Recursively follow any further initial transitions
    result = followInitialTransitions(self, path[0])

proc init*(self: Awsm) =
  ## Execute the top-most and all subsequent initial transitions
  assert self.currentHandler(self, ReservedEvt[InitSig]) == RetTransitioned
  self.currentHandler = followInitialTransitions(self, self.currentHandler)

proc findLCA(self: Awsm, source, target: EventHandler): EventHandler =
  ## Find the Least Common Ancestor of source and target
  var targetPath = newSeqOfCap[EventHandler](MaxHandlerNestDepth)

  # Build path from target to root
  var state = target
  discard trig(self, state, Empty)
  while true:
    targetPath.add(self.currentHandler)
    state = self.currentHandler
    if trig(self, state, Empty) != RetSuper:
      break

  # Exit early if source is in target's path
  if source in targetPath:
    return source

  # Walk from source to root, looking for first match in target's path
  state = source
  while true:
    discard trig(self, state, Empty)
    state = self.currentHandler
    if state in targetPath:
      return state
    if trig(self, state, Empty) != RetSuper:
      break

  # Should never reach here if both states are in same hierarchy
  return source

proc executeTransition(self: Awsm, source, target: EventHandler) =
  ## Execute the complete transition from source to target

  # Special case: transition to superstate (no entry action, no initial transition)
  discard trig(self, source, Empty)
  if self.currentHandler == target:
    discard exit(self, source)
    self.currentHandler = target
    return

  # Special case: transition to direct substate
  discard trig(self, target, Empty)
  if self.currentHandler == source:
    discard enter(self, target)
    self.currentHandler = followInitialTransitions(self, target)
    return

  # General case: transition through LCA
  let lca = findLCA(self, source, target)

  # Exit from source up to (not including) LCA
  var current = source
  while current != lca:
    discard trig(self, current, Exit)
    discard trig(self, current, Empty)
    current = self.currentHandler

  # Build entry path in reverse (from target up to LCA)
  var entryPath = newSeqOfCap[EventHandler](MaxHandlerNestDepth)
  var state = target
  while state != lca:
    entryPath.add(state)
    discard trig(self, state, Empty)
    state = self.currentHandler

  # Enter from LCA down to target
  for i in countdown(entryPath.high, 0):
    discard enter(self, entryPath[i])

  # We may have trainsitioned to a state with an initial transition
  self.currentHandler = followInitialTransitions(self, target)

proc dispatch*(self: Awsm, evt: Event) =
  ## Process the event through the Awsm's handler
  let startState = self.currentHandler

  # Trace event upward
  var source = self.currentHandler
  var status = source(self, evt)
  while status == RetSuper:
    source = self.currentHandler
    status = source(self, evt)

  # Exit early if no transition
  if status != RetTransitioned:
    self.currentHandler = startState
    return

  # Remember the target
  let target = self.currentHandler

  # Exit from starting state up to source state
  var state = startState
  while state != source:
    discard trig(self, state, Exit)
    discard trig(self, state, Empty)  # Get superstate
    state = self.currentHandler

  executeTransition(self, source, target)
