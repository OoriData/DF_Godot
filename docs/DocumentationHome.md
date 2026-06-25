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

> [!IMPORTANT]
> **Scaling model (June 2026):** All UI scaling is now handled by a single `content_scale_factor` set in `UIScaleManager`. There is no per-node font scaling — `TextScale` (deleted) and `DeviceStateManager.get_scaled_base_font_size()` (deleted) must not be recreated. Font sizes are fixed logical values. See [Responsive UI / Scaling](02_UI_UX/ui_system.md) for the full model before touching any font or layout code.

> [!TIP]
> Start with the [**UI Element Audit**](02_UI_UX/UIAudit.md) for any UI task — it contains the layer map, script mapping, per-element inventory, implementation patterns, and all known issues.

- [**UI Element Audit**](02_UI_UX/UIAudit.md) ⭐ — **Start here for all UI work.** Full inventory of every element, layer map, script mapping, implementation patterns, known issues, and links to every per-menu doc.

**Supporting deep-dives** (linked from UIAudit):
- [Scene Architecture](02_UI_UX/SceneArchitecture.md) · [Responsive UI / Scaling](02_UI_UX/ui_system.md) · [Device State](02_UI_UX/DeviceState.md)
- [MenuBase Contract](02_UI_UX/MenuBase.md) · [MenuManager](02_UI_UX/MenuManager.md) · [Design System](02_UI_UX/DesignSystem.md)
- [Convoy Menu](02_UI_UX/ConvoyMenu.md) · [Cargo Menu](02_UI_UX/ConvoyCargoMenu.md) · [Warehouse Menu](02_UI_UX/WarehouseMenu.md) · [Vendor Panel](02_UI_UX/VendorPanel/VendorPanelOverview.md)

---

## 03 Game Systems
- [**Game Systems Index**](03_Systems/GameSystemsIndex.md): Overview of all game systems.
- [**Game Lifecycle**](03_Systems/GameLifecycle.md): Visualized state machines for Auth, Journeys, and Mechanics.
- [**Items & Missions**](03_Systems/ItemsAndMissions.md): Unified item model, mission detection, and the full delivery lifecycle.
- [**Auto-Sell System**](03_Systems/AutoSellSystem.md): Post-journey cargo detection, snapshot diffing, and receipt modal.
- [**Mechanics & Parts**](03_Systems/Mechanics.md): Vehicle customization and part compatibility.
- [**Map System**](03_Systems/MapSystem/MapSystemOverview.md): Tile rendering, camera, and settlement management.
  - [**Map Menu & Overlays**](03_Systems/MapSystem/MapMenuSystem.md): Visual layers, toggles, signals, and architectural design.
  - [**Settlement Overlay System**](03_Systems/MapSystem/SettlementOverlay.md): Tile outlines, focus pins, route arcs, color coding, dimming, and zoom smoothing.
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
- [**Data Examples**](99_Reference/data_dumps/README.md): Indexed JSON/markdown snapshots of common domain payloads — map, convoy, vehicle, cargo, parts, vendor, tutorial — with the shape and related doc for each.

