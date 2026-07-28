---
type: architecture
tags:
  - layer/service
  - kind/index
  - status/current
aliases:
  - "Architecture & Core"
created: 2026-05-18
updated: 2026-07-28
verified_against_code: 2026-07-28
status: current
---

# Architecture & Core

This section defines the high-level design patterns and data management strategies used across the project.

> [!NOTE]
> **This is the section index for `01_Architecture/`.** Every doc in the folder must appear below.
> CI enforces it — `tools/docs_check.py`.

## Guides
- [**Architecture Overview**](Architecture.md): The high-level view of Autoloads, Domain Services, and the Event Bus.
- [**Data Flow**](DataFlow.md): A deep dive into the unidirectional pipeline from API requests to UI updates.
- [**Data Schema**](Schema.md): Core object definitions — Convoy, Vehicle, Cargo, Part, User, Settlement, Vendor, Journey.
- [**Developer Cookbook**](Cookbook.md): Step-by-step recipes for common tasks (menus, signals, item types, debugging).

---

## Core Philosophy

*Desolate Frontiers* follows a **Service-Oriented, Event-Driven** architecture:
1. **Services** handle logic and API communication.
2. **GameStore** holds the current state snapshot.
3. **SignalHub** broadcasts changes to the rest of the app.
4. **UI** remains "thin" and only reacts to state changes.

This decoupling ensures that the game can handle offline idle progress and multi-platform scaling with minimal complexity.
