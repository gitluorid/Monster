--[[
"# Monster AI: Full Logic Walkthrough

This document explains the complete runtime flow of the monster system,
including what each function does and when it is called.

Read in this order:
1. Startup flow
2. Main loop flow
3. Per-module function reference
4. Troubleshooting and tuning notes

---------------------------------------------------------------------
STARTUP FLOW (FROM SERVER SCRIPT TO AI LOOP)
---------------------------------------------------------------------

1) init.legacy.luau (top-level script)
   - Requires MonsterMain package + MonsterMain/MonsterConfig
   - Waits for workspace.Monster model:
       local monster = workspace:WaitForChild("Monster")
   - Calls MonsterMain.StartController(monster, false)
   - Uses pcall for safe error reporting.

2) MonsterMain/MonsterController.luau
   - Function: MonsterController.new(monster)
   - Validates monster rig (Humanoid + HumanoidRootPart)
   - Loads submodules: config, movement, combat, VFX, state machine
   - Creates one controller table that stores runtime state
   - Stores VFX runtime fields on controller and creates StateMachine object

---------------------------------------------------------------------
MAIN LOOP FLOW (WHAT HAPPENS EVERY TICK)
---------------------------------------------------------------------

Entry point:
  MonsterController.Start(enableWanderSounds)

Loop behavior:
1. Find closest target with Movement.GetClosestTarget(...)
2. If target exists:
   - run chaseTarget(controller, target)
3. If no target:
   - run enterIdle(controller, "No targets found", ...)
   - then run wanderStep(controller)
4. Repeat while monster is alive and parented

---------------------------------------------------------------------
FUNCTION-BY-FUNCTION FLOW GUIDE
---------------------------------------------------------------------

=== MonsterController.luau ===

setState(controller, nextState)
- Calls state machine SetState.

enterIdle(controller, duration)
- State = Idle
- WalkSpeed = 0
- Stops movement
- Plays idle animation (if available)
- Waits for the idle duration

chooseWanderDestination(controller)
- Picks random wander goal using Movement.GetRandomWanderGoal
- Computes path to that goal
- Uses Movement.FindWanderWaypoint to pick a waypoint far enough away
- Returns selected position/index/distance or nil

wanderStep(controller)
- State = Wander
- Sets wander walk speed
- Plays walk animation
- Picks wander destination via chooseWanderDestination
- Moves once to that selected waypoint with Movement.MoveToPosition
- Plays footsteps while moving
- Returns to Idle

chaseTarget(controller, target)
- State = Chase
- Sets chase walk speed
- Plays run animation
- While target is valid:
  - Re-enforce chase speed if changed
  - Check distance
   - If close enough: switch to Attack and call Combat.PerformSwingAttack
  - Else: compute chase path, pick waypoint, move toward it
- Exits when target invalid/out of range

start(controller, enableWanderSounds)
- Starts VFX module
- Runs the main behavior loop (target check -> chase OR idle+wander)

stop(controller)
- Stops VFX
- Sets state to Idle

MonsterController.new(monster)
- Constructor/factory for the controller table

=== MonsterMovement.luau ===

GetHumanoidAndRoot(model)
- Returns Humanoid and HumanoidRootPart if present

IsValidTarget(target, monster)
- Target must exist, not be monster itself, be alive, and have root part

GetClosestTarget(monster, monsterRoot, detectionRange)
- Scans Workspace models and returns nearest valid target in range

ComputePath(pathSettings, startPosition, endPosition)
- Creates and computes Roblox Path object
- Returns nil on failure

MoveToPosition(humanoid, rootPart, position, closeDistance, timeout, onStep)
- Calls Humanoid:MoveTo(position)
- Polls until reached (using horizontal distance only) or timeout
- Runs optional onStep callback each frame

PickNextWaypoint(path, monsterRoot, minimumDistance, fallbackPosition)
- Used for chase: chooses first meaningful waypoint

FindWanderWaypoint(path, startPosition, minimumDistance)
- Used for wander: chooses first waypoint far enough from wander start

GetRandomWanderGoal(monsterRoot, wanderRadius, minimumDistance, maxAttempts)
- Randomly picks offset goal around monster
- Enforces minimum distance when possible

=== MonsterVFX.luau ===

setFootstepInterval(controller, interval)
- Changes minimum time between footsteps

playUniqueAnimation(controller, animationName)
- Plays animation by name
- Ensures one active animation track at a time

playIdleAnimation(controller)
- Tries Idle animation
- If missing, stops current movement animation

tryPlayFootstep(controller, reason)
- Plays one footstep if moving and interval threshold passed
- Uses move direction + horizontal velocity checks

startWanderSoundLoop(controller)
- Optional ambient random sounds loop

start(controller, enableWanderSounds)
- Starts VFX subsystem

stop(controller)
- Stops VFX subsystem and active animation

MonsterVFX.<helper functions>
- Includes shared audio/animation helpers used by VFX, controller, and combat

=== MonsterCombat.luau ===

getHumanoidAndRoot(model)
- Internal helper to read target rig parts safely

spawnBlood(origin, amount)
- Spawns temporary blood parts for impact feedback

MonsterCombat.PerformSwingAttack(...)
- Attack cooldown check
- Target validity checks
- Play attack animation/sounds
- Wait for swing hit delay
- Kill target immediately (Health = 0)
- Spawn blood
- Return (didAttack, attackTime)

=== MonsterStateMachine.luau ===

MonsterStateMachine.new(initialState)
- Creates lightweight state machine object with:
  - GetState()
  - SetState(nextState)
  - TimeInState()

---------------------------------------------------------------------
CONFIG-DRIVEN BEHAVIOR
---------------------------------------------------------------------

Most gameplay behavior is controlled by MonsterMain/MonsterConfig.luau.

Key sections:
- Combat/Targeting: detection range, melee range, cooldown
- Movement Speeds: wander speed, chase speed
- Wander Behavior: radius, minimum distances, timeouts
- Idle Behavior: idle durations
- Footsteps/Audio: intervals and movement threshold
- Attack Presentation: swing hit delay, blood amount

TROUBLESHOOTING CHECKLIST
---------------------------------------------------------------------

If monster does not move:
1. Confirm monster has Humanoid and HumanoidRootPart
2. Confirm pathfinding area is walkable
3. Confirm startup script calls MonsterMain.StartController(monster, false)

If monster does not animate:
1. Check ReplicatedStorage.Monster.Animations contains Walk/Run/Attack
2. Optional Idle animation is recommended for cleaner idle state

If attack looks wrong:
1. Confirm target has Humanoid + HumanoidRootPart
2. Confirm sounds exist under MonsterMain/OtherSounds

---------------------------------------------------------------------
END NOTE
---------------------------------------------------------------------

The system is intentionally split into small modules so beginners can edit
one behavior area at a time without touching everything.
]]