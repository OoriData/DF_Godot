---
type: technical
tags:
  - kind/process
  - status/current
aliases:
  - "GDScript Verification"
  - "Compile Check"
created: 2026-07-30
updated: 2026-07-31
verified_against_code: 2026-07-30
status: current
---

# Verifying GDScript Changes

How to prove an edit is "compile-clean" before you claim it. Every command and every default in
this doc was measured against **Godot `4.6.stable.official.89cea1439`** on 2026-07-30 — re-measure
before trusting them against a different engine build.

```bash
GODOT=/Users/aidan/Applications/Godot.app/Contents/MacOS/Godot   # not on PATH
```

There are **two** checks. Neither substitutes for the other: the editor pass resolves autoloads and
`class_name` globals but only sees scripts something actually loads; the probe sees exactly the files
you name but is the only way to promote a warning to a failure.

---

## What Godot 4.6 actually does with warnings

Two facts that invalidate the obvious approach:

- **`debug/gdscript/warnings/treat_warnings_as_errors` does not exist in Godot 4.6.** Writing it into
  `project.godot` is a no-op — `ProjectSettings` reports it as absent by default, and setting it to
  `true` changed nothing in a controlled A/B run. Warning severity is **per warning**, as an int:
  `0` = ignore, `1` = warn, `2` = error.
- **`project.godot` has no `[debug]` section at all**, so the repo runs on engine defaults. The ones
  that matter here, read back from `ProjectSettings` at runtime:

  | `debug/gdscript/warnings/…` | Default | Consequence |
  |---|---|---|
  | `inference_on_variant` | **2 — Error** | `var x := some_variant` is a **hard parse error** already. No configuration needed. |
  | `inferred_declaration` | 0 — Ignore | Never fires. Not the setting behind the error above, despite the similar name. |
  | `unused_variable` | 1 — Warn | Never fails a load. A `_`-prefixed name suppresses it outright. |
  | `untyped_declaration` | 0 — Ignore | Never fires. |
  | `shadowed_variable` / `standalone_expression` | 1 — Warn | Never fail a load. |
  | `enable` | true | Warnings are generated; severity still decides. |

So "warnings as errors" in this project means **`inference_on_variant` only**, unless you deliberately
promote others for a run (see [check 2](#check-2--the-load-probe-targeted)).

---

## Check 1 — the editor pass (structural)

Catches parse errors, compile errors, and unresolved types across the loaded script graph. This is the
only pass that registers autoloads and `class_name` globals.

```bash
"$GODOT" --headless --editor --quit-after 250 > /tmp/ed.log 2>&1
grep -inE "parse error|compile error|could not resolve|failed to load script" /tmp/ed.log
```

- **Runtime:** ≈15 s measured with a warm `.godot/` (11–17 s across four runs). The ~4–5 min figure
  quoted in older notes is the *cold* case — a fresh clone or a deleted `.godot/`, where the same
  command reimports every asset first. Not re-measured here; budget for it if the cache is cold.
- **Grep the full error set, not one string.** A grep narrowed to the warnings message let a live parse
  error through.

**Coverage is not universal — this is the trap.** Measured by planting the same canary in four files
and running one pass:

| Canary planted in | Reported? | Reached via |
|---|---|---|
| `Scripts/System/ui_theme.gd` (autoload) | ✅ | *Creating autoload scripts* |
| `Scripts/Menus/VendorPanel/cargo_fill_planner.gd` | ✅ | dependency of an autoload-reachable controller |
| `Scripts/Menus/warehouse_menu.gd` | ✅ | *Reopening scenes* — i.e. **whatever scenes this machine last had open** |
| `Scripts/Debug/wiring_smoke_test.gd` | ❌ | nothing loads it |

A brand-new file that nothing references yet is invisible to this pass, even with `class_name` and
`--quit-after 1000`. And the `warehouse_menu.gd` row is worse than it looks: it was only caught because
the editor reopened a scene using it, which is local editor state, not a property of the repo.

**Cascade noise:** dependents of a broken script report
`Compile Error: Failed to compile depended scripts` at line **`0`**. Line 0 means "someone I depend on
is broken". The real defect is the entry with a real line number.

---

## Check 2 — the load probe (targeted)

Loads exactly the files you name, in ~2 s. Use it for every file you edited, and whenever you want a
warning to actually fail.

```gdscript
# _probe.gd — repo root, delete when done
extends SceneTree

const TARGETS := [
	"res://Scripts/Menus/warehouse_menu.gd",
]

func _process(_delta: float) -> bool:
	for path in TARGETS:
		print("== PROBE ", path)
		ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
	return true  # quit after the first frame
```

```bash
"$GODOT" --headless --script res://_probe.gd 2>&1 | grep -A1 "Warning treated as error"
rm -f _probe.gd _probe.gd.uid
```

The `at: GDScript::reload (res://…:LINE)` line that follows names the file and the line.

**Load on the first frame, never in `_init()`.** Autoloads are registered as compiler-visible
identifiers *after* the SceneTree script is constructed. Loading in `_init()` produces
`Compile Error: Identifier not found: ErrorTranslator` / `UITheme` on perfectly healthy menu scripts —
a false failure that also masks real ones. Loading from `_process` on frame 1 resolves them and the
same two scripts load clean.

### Promoting a warning for one run

To make a level-1 warning fail, set that warning to `2` — temporarily, and **always restore**:

```bash
cp project.godot /tmp/pg.bak
printf '\n[debug]\n\ngdscript/warnings/unused_variable=2\n' >> project.godot
"$GODOT" --headless --script res://_probe.gd 2>&1 | grep -A1 "Warning treated as error"
cp /tmp/pg.bak project.godot          # restore, unconditionally
git status --porcelain project.godot  # must print nothing
```

Expect collateral: the codebase already violates several level-1 warnings, and promoting one breaks
*autoload* compilation too. `unused_variable=2` produced 31 `SCRIPT ERROR` lines from pre-existing
unused locals (`convoy_menu.gd`, `mechanics_menu.gd`, `warehouse_menu.gd`, `tutorial_manager.gd`,
`premium_upgrade_modal.gd`) before reaching the probe's targets. Scope the grep to your own paths:

```bash
… | grep -E "GDScript::reload \(res://Scripts/Menus/your_file\.gd"
```

Note also that anything reachable from the autoload graph is compiled once at boot and again by the
probe, so a genuine error in such a file appears **twice**. Same defect, not two.

---

## Traps

1. **`load()` returns a non-null placeholder for a script that failed to compile.** A null check is
   *not* a pass/fail signal — the failing script still printed
   `== RESULT … -> (res://…):<GDScript#…>`. The `Warning treated as error` / `Parse Error` line is the
   signal. Nothing else is.
2. **Positive-control the canary before trusting a clean run.** A silent pass and a pass that never
   looked at your file are indistinguishable in the log. Plant, confirm it fires, remove, re-run.
3. **Use an `inference_on_variant` canary** — it is the one diagnostic that fails a load out of the box:
   ```gdscript
   var d: Dictionary = {"k": 1}
   var x := d.get("k")   # inferred from Variant → parse error
   ```
   An unused-variable canary will not fire, and `_`-prefixing one hides it completely.
4. **Plant canaries with unique sentinels and remove by exact block match.**
   ```gdscript
   #<<CANARY
   …
   #CANARY>>
   ```
   A naive string-replace once deleted `func _canary…` while leaving its `static` behind, producing
   `static static func` — a parse error that shipped. Prefer `cp file /tmp/x.bak` before planting and
   `cp /tmp/x.bak file` after; then confirm with `git status --porcelain`.
5. **Restore `project.godot` on every path out**, including failure. Verify, don't assume.

## What neither check proves

Both checks stop at compile time. A script that loads clean can still fail at runtime — `String(x)` on
an `Object` or `int` throws only when the line executes, signal wiring is not exercised, and nothing
here opens a menu. For that, use the [Headless Smoke Test and GUT suites](TechnicalReference.md#testing--qa).
