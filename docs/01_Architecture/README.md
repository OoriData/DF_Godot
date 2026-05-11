# Architecture & Core

This section defines the high-level design patterns and data management strategies used across the project.

## Guides
- [**Architecture Overview**](Architecture.md): The high-level view of Autoloads, Domain Services, and the Event Bus.
- [**Data Flow**](DataFlow.md): A deep dive into the unidirectional pipeline from API requests to UI updates.

---

## Core Philosophy

*Desolate Frontiers* follows a **Service-Oriented, Event-Driven** architecture:
1. **Services** handle logic and API communication.
2. **GameStore** holds the current state snapshot.
3. **SignalHub** broadcasts changes to the rest of the app.
4. **UI** remains "thin" and only reacts to state changes.

This decoupling ensures that the game can handle offline idle progress and multi-platform scaling with minimal complexity.
