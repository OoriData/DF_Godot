# Desolate Frontiers Documentation

Welcome to the technical documentation for *Desolate Frontiers*. This folder is organized into a logical learning path for developers and AI agents.

> [!TIP]
> **New to the project?** Start with the [**Project Map**](PROJECT_MAP.md) and the [**Glossary**](99_Reference/Glossary.md) to quickly find your way around.

## 01 Architecture & Core
- [**Architecture Overview**](01_Architecture/Architecture.md): High-level system design and event-driven patterns.
- [**Data Flow**](01_Architecture/DataFlow.md): The unidirectional pipeline from APICalls to SignalHub.
- [**Developer Cookbook**](01_Architecture/Cookbook.md): Step-by-step recipes for common tasks.

## 02 UI & UX System
- [**Scene Architecture**](02_UI_UX/SceneArchitecture.md): Viewport layering, MainScreen hierarchy, and menu composition.
- [**Responsive UI System**](02_UI_UX/ui_system.md): Logical scaling, orientation handling, and mobile design patterns.
- [**Design System**](02_UI_UX/DesignSystem.md): Visual tokens, typography, and premium component standards.
- [**Asset Pipeline**](02_UI_UX/AssetPipeline.md): Standards for textures, fonts, and map tiles.
- [**MenuManager**](02_UI_UX/MenuManager.md): Navigation hub, transitions, and state persistence.
- [**MenuBase Contract**](02_UI_UX/MenuBase.md): Standardizing menu initialization and lifecycle.

## 03 Game Systems
- [**Game Lifecycle**](03_Systems/GameLifecycle.md): Visualized state machines for Auth, Journeys, and Mechanics.
- [**Items & Missions**](03_Systems/ItemsAndMissions.md): Unified item model and mission detection logic.
- [**Tutorial System**](03_Systems/Tutorials.md): Managing onboarding levels, steps, and UI highlights.
- [**Mechanics & Parts**](03_Systems/Mechanics.md): Vehicle customization and part compatibility.
- [**Map System**](03_Systems/README.md): Tile rendering and settlement management.

## 04 Technical Reference
- [**Autoload Order**](04_Technical/AutoloadOrder.md): Initialization sequence and dependency management.
- [**Diagnostics & Troubleshooting**](04_Technical/Diagnostics.md): Logging, watchdogs, and network debugging.
- [**Dependency Graph**](04_Technical/Dependencies.md): Visual mapping of singleton relationships.
- [**API Reference**](04_Technical/API_Reference.md): Backend endpoints and JSON contracts.
- [**Deployment & Environment**](04_Technical/Deployment.md): Build targets and CI/CD pipelines.
- [**Identity & Auth**](04_Technical/Identity.md): Account linking, merging, and session management.
- [**Testing Guidelines**](04_Technical/README.md): Unit testing and integration verification.

---

## 99 Appendix
- [**Project Glossary**](99_Reference/Glossary.md): Definitions of domain and technical terms.
- [**Data Examples**](99_Reference/data_dumps/): JSON snapshots of common domain payloads for reference.
