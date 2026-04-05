local MonsterController = {}

local logicFolder = (script.Parent :: Instance):WaitForChild("logic")
local fxFolder = (script.Parent :: Instance):WaitForChild("fx")

local MonsterConfig = require((script.Parent :: Instance):WaitForChild("Config") :: ModuleScript)
local MovementLogic = require(logicFolder:WaitForChild("Movement") :: ModuleScript)
local CombatLogic = require(logicFolder:WaitForChild("Combat") :: ModuleScript)
local MonsterStateMachine = require(logicFolder:WaitForChild("StateMachine") :: ModuleScript)
local MonsterVisual = require(fxFolder:WaitForChild("Visual") :: ModuleScript)
local MonsterAudio = require(fxFolder:WaitForChild("Audio") :: ModuleScript)

-- Runs idle state for a fixed duration.
local function enterIdle(controller, duration: number)
	local config = controller.Config
	controller.StateMachine:SetState(MonsterStateMachine.States.Idle)
	controller.Humanoid.WalkSpeed = 0
	controller.Humanoid:Move(Vector3.zero)
	controller.Audio.SetFootstepInterval(controller, config.Audio.Footsteps.WANDER_INTERVAL)
	controller.Visual.PlayIdleAnimation(controller)

	local endTime = os.clock() + duration
	while
		controller._running
		and controller.Monster.Parent
		and controller.Humanoid.Health > 0
		and os.clock() < endTime
	do
		task.wait(config.Idle.TICK_INTERVAL)
	end
end

-- Chooses one wander destination point from path waypoints.
-- Returns position metadata, or nil on failure.
local function chooseWanderDestination(controller): (Vector3?, number?, number?)
	local config = controller.Config
	local goal = controller.Movement.GetRandomWanderGoal(
		controller.RootPart,
		config.Wander.RADIUS,
		config.Wander.MIN_GOAL_DISTANCE,
		config.Wander.GOAL_ATTEMPTS
	)

	local path = controller.Movement.ComputePath(config.Path.SETTINGS, controller.RootPart.Position, goal)
	if not path then
		return nil, nil, nil
	end

	local selectedPosition, selectedIndex, selectedDistance = controller.Movement.FindWanderWaypoint(
		path,
		controller.RootPart.Position,
		config.Path.WANDER_MIN_WAYPOINT_DISTANCE
	)

	return selectedPosition, selectedIndex, selectedDistance
end

-- Single wander action:
-- 1) Enter wander state
-- 2) Pick one destination
-- 3) Move once
-- 4) Return to idle
local function wanderStep(controller)
	local config = controller.Config
	controller.StateMachine:SetState(MonsterStateMachine.States.Wander)
	controller.Audio.SetFootstepInterval(controller, config.Audio.Footsteps.WANDER_INTERVAL)
	controller.Humanoid.WalkSpeed = config.MovementSpeeds.WANDER
	controller.Visual.PlayUniqueAnimation(controller, "Walk")
	local wanderStartTime = os.clock()

	local destination = chooseWanderDestination(controller)
	if not destination then
		enterIdle(controller, config.Wander.PATH_FAIL_IDLE_TIME)
		task.wait(config.Wander.PATH_FAIL_RETRY_DELAY)
		return
	end

	if os.clock() - wanderStartTime >= config.Wander.MAX_STEP_DURATION then
		enterIdle(controller, config.Idle.AFTER_WANDER_TIME)
		return
	end

	if not controller._running or controller.Humanoid.Health <= 0 then
		return
	end

	controller.Movement.MoveToPosition(
		controller.Humanoid,
		controller.RootPart,
		destination,
		config.Path.WANDER_REACHED_DISTANCE,
		config.Path.WANDER_STEP_TIMEOUT,
		function()
			controller.Audio.TryPlayFootstep(controller)
		end
	)

	enterIdle(controller, config.Idle.AFTER_WANDER_TIME)
end

local function playAttackHitPresentation(controller, didAttack: boolean, attackedModel: Model?, attackedRoot: BasePart?)
	if not didAttack or not attackedModel or not attackedRoot then
		return
	end

	local headBlowSound = controller.Audio.FindSound("HeadBlow")
	if headBlowSound and headBlowSound:IsA("Sound") then
		controller.Audio.PlaySound(headBlowSound, controller.RootPart, 3)
	end

	controller.Visual.PlayKillBlood(controller, attackedModel, attackedRoot, controller.Config.Visual.BLOOD_PART_AMOUNT)
end

local function performMeleeAttack(controller, target: Model)
	local config = controller.Config
	controller.StateMachine:SetState(MonsterStateMachine.States.Attack)
	controller.Visual.PlayUniqueAnimation(controller, "Attack")

	local attackSound = controller.Audio.FindSound("Attack")
	if attackSound and attackSound:IsA("Sound") then
		controller.Audio.PlaySound(attackSound, controller.RootPart, 4)
	end

	local didAttack, newLastAttack, attackedModel, attackedRoot = controller.Combat.PerformSwingAttack(
		controller.Monster,
		target,
		controller.RootPart,
		config,
		controller._lastAttackTime
	)
	controller._lastAttackTime = newLastAttack

	playAttackHitPresentation(controller, didAttack, attackedModel, attackedRoot)

	controller.StateMachine:SetState(MonsterStateMachine.States.Chase)
	task.wait(config.Combat.POST_ATTACK_RECOVERY_TIME)
end

local function tryHandleMeleeRange(controller, target: Model, distanceToTarget: number): boolean
	local combatConfig = controller.Config.Combat
	if distanceToTarget > combatConfig.MELEE_RANGE then
		return false
	end

	if os.clock() - controller._lastAttackTime < combatConfig.ATTACK_COOLDOWN then
		task.wait(combatConfig.COOLDOWN_RETRY_TIME)
		return true
	end

	performMeleeAttack(controller, target)
	return true
end

local function performChaseMoveStep(controller, targetRoot: BasePart)
	local pathConfig = controller.Config.Path
	local path = controller.Movement.ComputePath(pathConfig.SETTINGS, controller.RootPart.Position, targetRoot.Position)
	local nextPosition = targetRoot.Position
	if path then
		nextPosition = controller.Movement.PickNextWaypoint(
			path,
			controller.RootPart,
			pathConfig.CHASE_MIN_WAYPOINT_DISTANCE,
			targetRoot.Position
		)
	end

	controller.Movement.MoveToPosition(
		controller.Humanoid,
		controller.RootPart,
		nextPosition,
		pathConfig.CHASE_REACHED_DISTANCE,
		pathConfig.CHASE_STEP_TIMEOUT,
		function()
			controller.Audio.TryPlayFootstep(controller)
		end
	)
end

-- Chase loop: runs while target is valid and in range.
local function chaseTarget(controller, target: Model)
	local config = controller.Config
	local combatConfig = config.Combat
	controller.StateMachine:SetState(MonsterStateMachine.States.Chase)
	controller.Audio.SetFootstepInterval(controller, config.Audio.Footsteps.CHASE_INTERVAL)
	controller.Humanoid.WalkSpeed = config.MovementSpeeds.CHASE
	controller.Visual.PlayUniqueAnimation(controller, "Run")

	local startChaseSound = controller.Audio.FindSound("StartChaseSound")
	if startChaseSound then
		controller.Audio.PlaySound(startChaseSound, controller.RootPart, 5)
	end

	while controller._running and controller.Movement.IsValidTarget(target, controller.Monster) do
		if controller.Humanoid.WalkSpeed ~= config.MovementSpeeds.CHASE then
			controller.Humanoid.WalkSpeed = config.MovementSpeeds.CHASE
		end

		local targetRoot = target:FindFirstChild("HumanoidRootPart")
		if not targetRoot or not targetRoot:IsA("BasePart") then
			return
		end

		local distanceToTarget = (controller.RootPart.Position - targetRoot.Position).Magnitude
		if distanceToTarget > combatConfig.DETECTION_RANGE then
			return
		end

		if tryHandleMeleeRange(controller, target, distanceToTarget) then
			continue
		end

		performChaseMoveStep(controller, targetRoot)
		task.wait()
	end
end

-- Main update loop for one monster controller instance.
local function start(controller)
	local config = controller.Config
	if controller._running then
		return
	end

	controller._running = true
	controller.Visual.Start(controller)
	controller.Audio.Start(controller)

	while controller._running and controller.Monster.Parent and controller.Humanoid.Health > 0 do
		local target =
			controller.Movement.GetClosestTarget(controller.Monster, controller.RootPart, config.Combat.DETECTION_RANGE)

		if target then
			chaseTarget(controller, target)
		else
			enterIdle(controller, config.Idle.BEFORE_WANDER_TIME)
			if not controller._running or controller.Humanoid.Health <= 0 then
				break
			end
			wanderStep(controller)
		end

		task.wait(config.Loop.MAIN_TICK_INTERVAL)
	end
	controller:Stop() -- Ensure we clean up if we exited the loop without an explicit stop call.
end

-- Stops this controller instance.
local function stop(controller)
	if not controller._running then
		return
	end

	controller._running = false
	controller.Audio.Stop(controller)
	controller.Visual.Stop(controller)
	controller.StateMachine:SetState(MonsterStateMachine.States.Idle)
end

-- Creates one controller for one monster model.
function MonsterController.new(monster: Model)
	local humanoid = monster:FindFirstChildOfClass("Humanoid")
	local rootPart = monster:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart or not rootPart:IsA("BasePart") then
		return nil, "Monster is missing Humanoid or HumanoidRootPart"
	end

	local controller = {
		Monster = monster,
		Humanoid = humanoid,
		RootPart = rootPart,
		Config = MonsterConfig,
		Movement = MovementLogic,
		Combat = CombatLogic,
		Visual = MonsterVisual,
		Audio = MonsterAudio,
		StateMachine = MonsterStateMachine.new(MonsterStateMachine.States.Idle),

		_running = false,
		_lastAttackTime = 0,
		_visualRunning = false,
		_visualCurrentAnimationTrack = nil,
		_visualCurrentAnimationName = nil,
		_audioRunning = false,
		_audioFootstepInterval = MonsterConfig.Audio.Footsteps.WANDER_INTERVAL,
		_audioLastFootstepAt = 0,

		Start = start,
		Stop = stop,
	}

	return controller
end

return MonsterController
