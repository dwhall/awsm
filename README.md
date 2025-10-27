# awsm: active objects with state machines.

Awsm is an event-driven framework for real-time concurrency in
embedded systems, written in Nim. It provides an event-driven runtime
with hierarchical state machines, suitable for resource-constrained
processors with no Memory Management Units (MMU).

This is a rewrite of the concepts of Miro Samek's
[QP Framework](https://www.state-machine.com/)
and not a verbatim translation.  I'm taking advantage of Nim's features
(e.g. strong type system, automatic memory management) where they are valuable.

## License

Copyright 2025 Dean Hall
MIT License
See LICENSE file for details

## Existing Features

- Active Objects: Each Awsm eschews a thread stack in favor of Run-To-Completion (RTC)
  semantics and an event queue which serializes processing.
- Hierarchical State Machines: Supports nested states and transitions
  for automating behavior.

## Planned Features

- Active objects can:
  * process an event atomically and serially from its event queue
  * change its own event handler for the next event
  * spawn child Awsms
  * post events to child Awsms
  * publish events system wide
- Event Dispatching: Efficient event handling and state transitions.
- Customizable Value Size: Choose between 16, 32, or 64-bit event values at compile time.

## Getting Started

1. Clone the repository from https://github.com/dwhall/awsm
2. Run tests
   ```
   nimble test
   ```

## References

- [Active Object](https://www.state-machine.com/active-object)
- [PSiCC2.pdf](https://www.state-machine.com/doc/PSiCC2.pdf) — Samek, Miro,
  _Practical UML Statecharts in C/C++, Second Edition: Event-driven Programming for Embedded Systems_,
  Elsevier, 2009.  ISBN: 978-0-7506-8706-5
- [PSiCC2 Updates+Errata](https://www.state-machine.com/doc/PSiCC2_Updates+Errata.pdf)