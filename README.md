# awsm: actors with state machines

Awsm is an event-driven framework for real-time concurrency in
embedded systems, written in Nim. It provides a lightweight actor model
with hierarchical state machines, suitable for resource-constrained
environments.

This is a rewrite of the concepts of Miro Samek's
[QP Framework](https://www.state-machine.com/) 
and not a verbatim translation.  I'm taking advantage of Nim's features 
(e.g. strong type system, automatic memory management) where possible.

## License

Copyright 2025 Dean Hall
MIT License
See LICENSE file for details

## Existing Features

- Actor Model: Each actor eschews a thread stack in favor of an event queue
  which serializes processing.
- Hierarchical State Machines: Supports nested states and transitions.

## Planned Features

-  Actor Model: Actors can spawn child actors.
- Event Dispatching: Efficient event handling and state transitions.
- Customizable Value Type: Choose between 16, 32, or 64-bit event values at compile time.

## Getting Started

1. Clone the repository from https://github.com/dwhall/awsm
2. Run tests
   ```
   nimble test
   ```

## References

- [PSiCC2.pdf](https://www.state-machine.com/doc/PSiCC2.pdf) — Pracical UML Statecharts in C/C++, Second Edition: Event-driven Programming for Embedded Systems
