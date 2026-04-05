# Monster AI

Modular monster AI with clear separation between gameplay logic and presentation.

- Gameplay logic is in `MonsterAI/logic`.
- Presentation is in `MonsterAI/fx`.
- Runtime orchestration is in `MonsterAI/Controller.luau`.
- Tuning values are centralized in `MonsterAI/Config.luau`.

## Project Layout

```text
Monster/
  init.legacy.luau
  MonsterAI/
    init.luau
    Controller.luau
    Config.luau
    logic/
      Movement.luau
      Combat.luau
      StateMachine.luau
    fx/
      Audio.luau
      Visual.luau
      Animations/
      Objects/
      Sounds/
```

## Quick Start

`init.legacy.luau` is a simple server entry script that starts one monster controller.

```luau
local MonsterAI = require(script:WaitForChild("MonsterAI"))

local monster = workspace:WaitForChild("Monster")
if not monster:IsA("Model") then
    return
end

MonsterAI.StartController(monster :: Model, true)
```

`StartController(monster, enableWanderSounds)`:

- `monster`: target monster `Model`.
- `enableWanderSounds`: set `true` to enable ambient wander sounds, or `false` to disable.

## Runtime Flow

1. `MonsterAI/init.luau` calls `Controller.new(monster)`.
2. Controller validates the rig (`Humanoid` and `HumanoidRootPart`).
3. Controller starts the `Visual` and `Audio` subsystems.
4. Main loop runs:
   - Find closest valid target.
   - If target exists, run chase + attack flow.
   - If no target, run idle then wander flow.
5. Loop exits when the monster dies, is unparented, or controller stops.

## Module Responsibilities

### `Controller.luau`

- Orchestrates state transitions, movement calls, combat calls, and presentation timing.
- Owns runtime fields (running flags, last attack time, current animation track name/handle).

### `logic/Movement.luau`

- Target validation and nearest-target selection.
- Path computation.
- MoveTo execution with timeout and waypoint helpers.
- Wander goal and waypoint selection.

### `logic/Combat.luau`

- Gameplay-only attack resolution.
- Enforces cooldown and swing-hit delay.
- Applies kill result.
- Returns attack result metadata for presentation:
  - `(didAttack, newLastAttackTime, attackedModel, attackedRoot)`

### `logic/StateMachine.luau`

- Minimal state machine with state name and time-in-state tracking.

### `fx/Visual.luau`

- Animation play/stop helpers (`Walk`, `Run`, `Attack`, optional `Idle`).
- Kill blood visual handling.
- Uses object templates from `fx/Objects` when available.
- Falls back to procedural blood particles when templates are missing.

### `fx/Audio.luau`

- Safe cloned sound playback.
- Footstep interval and motion-threshold gating.
- Named sound lookup from `fx/Sounds`.
- Optional ambient wander sound loop.

### `Config.luau`

- Single source of gameplay and pacing values, grouped by behavior area.

Current top-level groups:

- `Combat`: detection, melee range, cooldown/windup, and knockback values.
- `MovementSpeeds`: wander/chase walk speed.
- `Idle`: idle timing before/after wander.
- `Wander`: random goal selection and fail-retry pacing.
- `Path`: chase and wander movement thresholds + pathfinding settings.
- `Audio`: footstep pacing and ambient delay range.
- `Visual`: blood amount and visual effect lifetime.
- `Loop`: main AI loop cadence.

Important chase tuning:

- `Path.CHASE_STEP_TIMEOUT` = maximum time a single chase `MoveTo` step can run before controller repaths.
- Lower value: faster repath and more responsive pursuit.
- Higher value: fewer repaths but slower reaction to moving targets.

## Asset Expectations

### `MonsterAI/fx/Animations`

Expected animation asset names:

- `Walk`
- `Run`
- `Attack`
- `Idle` (optional)

### `MonsterAI/fx/Sounds`

Expected named sounds used by controller/audio logic:

- `StartChaseSound`
- `Attack`
- `HeadBlow`
- `WanderFootstep`

Optional ambient sounds:

- Place ambient sounds in `Sounds/Wander` or `Sounds/Ambient` for explicit ambient selection.
- If those folders are missing, ambient selection falls back to sounds in the full `Sounds` tree excluding core one-shot names.

### `MonsterAI/fx/Objects`

Optional blood templates for kill VFX:

- Preferred names: `NeckBlood` or `Blood`.
- Can also use any model/basepart/particle-emitter hierarchy.

## Troubleshooting

### Monster does not move

1. Confirm the monster has `Humanoid` and `HumanoidRootPart`.
2. Confirm pathfinding space is walkable.
3. Confirm startup script calls `MonsterAI.StartController(monster, ...)`.

### Monster does not animate

1. Confirm `MonsterAI/fx/Animations` contains `Walk`, `Run`, and `Attack`.
2. Ensure animation instances are `Animation` objects.

### Sounds do not play

1. Confirm `MonsterAI/fx/Sounds` contains required one-shot sounds.
2. Check that sound objects are `Sound` instances and not muted.
3. If ambient sounds are expected, verify `enableWanderSounds` is `true` when starting the controller.

### Kill blood effect does not appear

1. Confirm `MonsterAI/fx/Objects` exists.
2. Add a template named `NeckBlood` or `Blood`, or rely on procedural fallback.

## Notes

- This package is currently server-driven and does not require RemoteEvent wiring for chase feedback.
- Keeping responsibilities split (`logic` vs `fx`) makes behavior changes safer and easier to reason about.
