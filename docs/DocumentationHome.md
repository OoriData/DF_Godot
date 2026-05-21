---
type: note
tags:
  - codex/readme
aliases:
  - "Desolate Frontiers Documentation"
created: 2026-05-18
---

# Desolate Frontiers Documentation

Welcome to the technical documentation for *Desolate Frontiers*. This folder is organized into a logical learning path for developers and AI agents.

> [!IMPORTANT]
> **AI Agents**: Start with the [**AI Onboarding Guide**](AI_ONBOARDING.md) to understand core architectural laws before contributing.

> [!TIP]
> **New to the project?** Start with the [**Project Map**](PROJECT_MAP.md) and the [**Glossary**](99_Reference/Glossary.md) to quickly find your way around.

---

## 01 Architecture & Core
- [**Architecture Overview**](01_Architecture/Architecture.md): High-level system design and event-driven patterns.
- [**Data Flow**](01_Architecture/DataFlow.md): The unidirectional pipeline from APICalls to SignalHub.
- [**Data Schema**](01_Architecture/Schema.md): Core object definitions — Convoy, Vehicle, Cargo, Part, **User, Settlement, Vendor, Journey**.
- [**Developer Cookbook**](01_Architecture/Cookbook.md): Step-by-step recipes for common tasks (menus, signals, item types, debugging).

---

## 02 UI & UX System
- [**Scene Architecture**](02_UI_UX/SceneArchitecture.md): Viewport layering, MainScreen hierarchy, and menu composition.
- [**Responsive UI System**](02_UI_UX/ui_system.md): Logical scaling, orientation handling, and mobile design patterns.
- [**Device State Management**](02_UI_UX/DeviceState.md): Orientation detection and viewport scaling coordination.
- [**Design System**](02_UI_UX/DesignSystem.md): Visual tokens, typography, and premium component standards.
- [**Asset Pipeline**](02_UI_UX/AssetPipeline.md): Standards for textures, fonts, and map tiles.
- [**MenuManager**](02_UI_UX/MenuManager.md): Navigation hub, transitions, and state persistence.
- [**MenuBase Contract**](02_UI_UX/MenuBase.md): Standardizing menu initialization and lifecycle.
- [**Convoy Menu**](02_UI_UX/ConvoyMenu.md): The primary convoy landing screen — vendor tabs, payload guard, debounce pattern.
- [**Warehouse Menu**](02_UI_UX/WarehouseMenu.md): Warehouse purchase, upgrades, cargo/vehicle management.
- [**Vendor Panel**](02_UI_UX/VendorPanel/VendorPanelOverview.md): Detailed reference for the complex trading and inventory system.

---

## 03 Game Systems
- [**Game Systems Index**](03_Systems/GameSystemsIndex.md): Overview of all game systems.
- [**Game Lifecycle**](03_Systems/GameLifecycle.md): Visualized state machines for Auth, Journeys, and Mechanics.
- [**Items & Missions**](03_Systems/ItemsAndMissions.md): Unified item model, mission detection, and the full delivery lifecycle.
- [**Auto-Sell System**](03_Systems/AutoSellSystem.md): Post-journey cargo detection, snapshot diffing, and receipt modal.
- [**Mechanics & Parts**](03_Systems/Mechanics.md): Vehicle customization and part compatibility.
- [**Map System**](03_Systems/MapSystem/MapSystemOverview.md): Tile rendering, camera, and settlement management.
  - [**Map Menu & Overlays**](03_Systems/MapSystem/MapMenuSystem.md): Visual layers, toggles, signals, and architectural design.
- [**Tutorial System**](03_Systems/TutorialSystem/TutorialSystemOverview.md): Managing onboarding levels, steps, and UI highlights.

---

## 04 Technical Reference
- [**Technical Reference**](04_Technical/TechnicalReference.md): Infrastructure index + testing + in-progress plans.
- [**Autoload Order**](04_Technical/AutoloadOrder.md): Initialization sequence and dependency management.
- [**Diagnostics & Troubleshooting**](04_Technical/Diagnostics.md): Logging, watchdogs, and network debugging.
- [**Refresh Scheduler**](04_Technical/RefreshScheduler.md): Polling heartbeat — interval, suspend/resume, adding services.
- [**Error Handling System**](04_Technical/ErrorSystem.md): ErrorTranslator pipeline, inline vs. modal errors.
- [**Dependency Graph**](04_Technical/Dependencies.md): Visual mapping of singleton relationships.
- [**API Reference**](04_Technical/API_Reference.md): Backend endpoints and JSON contracts.
- [**Deployment & Environment**](04_Technical/Deployment.md): Build targets and CI/CD pipelines.
- [**Identity & Auth**](04_Technical/Identity.md): Account linking, merging, and session management.
- [**AI Agent Guidelines**](04_Technical/AI_Guidelines.md): Standards for AI-assisted development.

---

## 99 Appendix
- [**Project Glossary**](99_Reference/Glossary.md): Definitions for all domain, API, and UI terminology.
- [**Data Examples**](99_Reference/data_dumps/): JSON snapshots of common domain payloads for reference.

