local MonsterController = {}

local logicFolder = (script.Parent :: Instance):WaitForChild("logic")
local fxFolder = (script.Parent :: Instance):WaitForChild("fx")

local MonsterConfig = require((script.Parent :: Instance):WaitForChild("Config") :: ModuleScript)
local MovementLogic = require(logicFolder:WaitForChild("Movement") :: ModuleScript)
local CombatLogic = require(logicFolder:WaitForChild("Combat") :: ModuleScript)
local MonsterStateMachine = require(logicFolder:WaitForChild("StateMachine") :: ModuleScript)
local MonsterVisual = require(fxFolder:WaitForChild("Visual") :: ModuleScript)
local MonsterAudio = require(fxFolder:WaitForChild("Audio") :: ModuleScript)

-- Returns a random idle duration between the configured minimum and maximum.
local function getRandomIdleDuration(config): number
	local minDuration = config.Idle.MIN_DURATION
	local maxDuration = config.Idle.MAX_DURATION

	if maxDuration < minDuration then
		minDuration, maxDuration = maxDuration, minDuration
	end

	local duration = minDuration + math.random() * (maxDuration - minDuration)
	return duration
end

-- Returns the HumanoidRootPart of a target if valid, otherwise nil.
local function getTargetRootPart(target: Model?): BasePart?
	if not target then
		return nil
	end

	local rootPart = target:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return nil
	end

	return rootPart
end

-- Returns the configured target re-evaluation interval and switch distance delta.
local function getTargetSelectionTuning(config): (number, number)
	local targetingConfig = config.Targeting
	local reevaluateInterval = 0.2
	local switchDistanceDelta = 0

	if targetingConfig then
		reevaluateInterval = math.max(0.01, targetingConfig.REEVALUATE_INTERVAL or reevaluateInterval)
		switchDistanceDelta = math.max(0, targetingConfig.SWITCH_DISTANCE_DELTA or switchDistanceDelta)
	end

	return reevaluateInterval, switchDistanceDelta
end

-- Returns whether the monster should stare at the current target instead of chasing.
local function shouldStareAtTarget(config): boolean
	local targetingConfig = config.Targeting
	local stareChance = targetingConfig and targetingConfig.STARE_CHANCE or 0.5
	return math.random() < stareChance
end

-- Chooses the preferred target based on current target validity and proximity.
local function getPreferredTarget(controller, currentTarget: Model?): Model?
	local config = controller.Config
	local candidate =
		controller.Movement.GetClosestTarget(controller.Monster, controller.RootPart, config.Combat.DETECTION_RANGE)
	if not candidate then
		return currentTarget
	end

	if not currentTarget or not controller.Movement.IsValidTarget(currentTarget, controller.Monster) then
		return candidate
	end

	if candidate == currentTarget then
		return currentTarget
	end

	local currentRoot = getTargetRootPart(currentTarget)
	local candidateRoot = getTargetRootPart(candidate)
	if not currentRoot then
		return candidate
	end
	if not candidateRoot then
		return currentTarget
	end

	local _, switchDistanceDelta = getTargetSelectionTuning(config)
	local currentDistance = (controller.RootPart.Position - currentRoot.Position).Magnitude
	local candidateDistance = (controller.RootPart.Position - candidateRoot.Position).Magnitude
	if candidateDistance + switchDistanceDelta < currentDistance then
		return candidate
	end

	return currentTarget
end

-- Runs idle state for a duration.
local function runIdleForDuration(controller, duration: number)
	local config = controller.Config
	controller.StateMachine:SetState(MonsterStateMachine.States.Idle)
	controller.Movement.StopImmediately(controller)
	controller.Audio.SetFootstepInterval(controller, config.Audio.Footsteps.WANDER_INTERVAL)
	controller.Visual.PlayIdleAnimation(controller)

	local endTime = os.clock() + duration
	while
		controller._running
		and controller.Monster.Parent
		and controller.Humanoid.Health > 0
		and os.clock() < endTime
	do
		controller.Movement.StepWalkSpeedTransition(controller)
		task.wait(config.Idle.TICK_INTERVAL)
	end
end

-- Chooses one random wander goal and returns the goal position and distance from start.
local function chooseWanderGoal(controller): (Vector3, number)
	local config = controller.Config
	local startPosition = controller.RootPart.Position
	local goal = controller.Movement.GetRandomWanderGoal(
		controller.RootPart,
		config.Wander.RADIUS,
		config.Wander.MIN_GOAL_DISTANCE,
		config.Wander.GOAL_ATTEMPTS
	)
	local goalDistance = (startPosition - goal).Magnitude
	return goal, goalDistance
end

-- Single wander action:
-- 1) Enter wander state
-- 2) Pick one random goal
-- 3) Repath in short waypoint steps toward that goal
-- 4) Return to idle unless interrupted by a detected target
local function runWanderStep(controller): Model?
	local config = controller.Config
	controller.StateMachine:SetState(MonsterStateMachine.States.Wander)
	controller.Audio.SetFootstepInterval(controller, config.Audio.Footsteps.WANDER_INTERVAL)
	controller.Movement.SetWalkSpeedTarget(controller, config.MovementSpeeds.WANDER)
	controller.Visual.PlayUniqueAnimation(controller, "Walk")
	controller.Movement.StepWalkSpeedTransition(controller)
	local reevaluateInterval = getTargetSelectionTuning(config)
	local nextTargetCheckAt = 0
	local detectedTarget: Model? = nil

	local function tryFindTarget(now: number): boolean
		if now < nextTargetCheckAt then
			return false
		end

		nextTargetCheckAt = now + reevaluateInterval
		local candidate = getPreferredTarget(controller, nil)
		if not candidate then
			return false
		end

		detectedTarget = candidate
		return true
	end

	local wanderStartTime = os.clock()
	local wanderGoal, goalDistance = chooseWanderGoal(controller)
	local wanderSpeed = math.max(0.1, config.MovementSpeeds.WANDER)
	local wanderTimeBudget = math.max(config.Wander.MAX_STEP_DURATION, (goalDistance / wanderSpeed) + 1)

	while controller._running and controller.Humanoid.Health > 0 do
		local elapsed = os.clock() - wanderStartTime
		if tryFindTarget(os.clock()) then
			return detectedTarget
		end

		if elapsed >= wanderTimeBudget then
			break
		end

		local path = controller.Movement.ComputePath(config.Path, controller.RootPart.Position, wanderGoal)
		if not path then
			controller.Movement.StepWalkSpeedTransition(controller)
			task.wait(config.Wander.PATH_FAIL_RETRY_DELAY)
			continue
		end

		local waypointPosition = controller.Movement.PickNextWaypoint(
			path,
			controller.RootPart,
			config.Wander.MIN_WAYPOINT_DISTANCE,
			wanderGoal
		)

		local remainingTime = wanderTimeBudget - elapsed
		local stepTimeout = math.min(config.Wander.STEP_TIMEOUT, remainingTime)
		if stepTimeout <= 0 then
			break
		end

		controller.Movement.MoveToPosition(
			controller.Humanoid,
			controller.RootPart,
			waypointPosition,
			config.Wander.REACHED_DISTANCE,
			stepTimeout,
			function()
				controller.Movement.StepWalkSpeedTransition(controller)
				controller.Audio.TryPlayFootstep(controller)
				if tryFindTarget(os.clock()) then
					return true
				end

				return false
			end
		)

		if detectedTarget then
			return detectedTarget
		end

		if (controller.RootPart.Position - wanderGoal).Magnitude <= config.Wander.REACHED_DISTANCE then
			break
		end

		task.wait()
	end

	return nil
end

-- Enters stare state and faces the target until it leaves detection range.
local function stareAtTarget(controller, target: Model)
	local config = controller.Config
	controller.StateMachine:SetState(MonsterStateMachine.States.Stare)
	controller.Movement.SetWalkSpeedTarget(controller, config.MovementSpeeds.STARE)
	controller.Movement.StepWalkSpeedTransition(controller)
	controller.Visual.PlayUniqueAnimation(controller, "Stare")
	controller.Humanoid:MoveTo(controller.RootPart.Position)

	while controller._running and controller.Movement.IsValidTarget(target, controller.Monster) do
		local targetRoot = getTargetRootPart(target)
		if not targetRoot then
			return
		end

		local distanceToTarget = (controller.RootPart.Position - targetRoot.Position).Magnitude
		if distanceToTarget > config.Combat.DETECTION_RANGE then
			return
		end

		local targetPositionOnPlane =
			Vector3.new(targetRoot.Position.X, controller.RootPart.Position.Y, targetRoot.Position.Z)
		controller.RootPart.CFrame = CFrame.lookAt(controller.RootPart.Position, targetPositionOnPlane)
		task.wait(config.Loop.MAIN_TICK_INTERVAL)
	end
end

-- Executes the full melee attack flow against a target, including animation and damage presentation.
local function performMeleeAttack(controller, target: Model)
	local config = controller.Config
	controller.Movement.StopImmediately(controller)
	controller.Humanoid:MoveTo(controller.RootPart.Position)
	controller.StateMachine:SetState(MonsterStateMachine.States.Attack)
	local attackTrack = controller.Visual.PlayUniqueAnimation(controller, "Attack")
	controller.Audio.PlayNamed(controller, "Attack", 4)

	local didAttack, newLastAttack, attackedModel, attackedRoot = controller.Combat.PerformSwingAttack(
		controller.Monster,
		target,
		controller.RootPart,
		config,
		controller._lastAttackTime
	)
	controller._lastAttackTime = newLastAttack
	if didAttack then
		controller.Audio.PlayNamed(controller, "HeadBlow", 3)
		controller.Visual.PlayAttackHitPresentation(controller, attackedModel, attackedRoot)
	end
	controller.Visual.WaitForAttackAnimationHandoff(controller, attackTrack)

	controller.StateMachine:SetState(MonsterStateMachine.States.Chase)
	local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
	if targetHumanoid and targetHumanoid.Health > 0 then
		controller.Movement.SetWalkSpeedTarget(controller, config.MovementSpeeds.CHASE)
	else
		controller.Movement.SetWalkSpeedTarget(controller, 0)
	end
	task.wait(config.Combat.POST_ATTACK_RECOVERY_TIME)
end

-- Determines whether to engage a melee target now or wait for cooldown.
local function handleMeleeEngagement(controller, target: Model, distanceToTarget: number): boolean
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

-- Calculates and executes one movement step while chasing the target.
local function performChaseMoveStep(controller, targetRoot: BasePart)
	local chaseConfig = controller.Config.Chase
	local pathConfig = controller.Config.Path
	local path = controller.Movement.ComputePath(pathConfig, controller.RootPart.Position, targetRoot.Position)
	local nextPosition = targetRoot.Position
	if path then
		nextPosition = controller.Movement.PickNextWaypoint(
			path,
			controller.RootPart,
			chaseConfig.MIN_WAYPOINT_DISTANCE,
			targetRoot.Position
		)
	end

	controller.Movement.MoveToPosition(
		controller.Humanoid,
		controller.RootPart,
		nextPosition,
		chaseConfig.REACHED_DISTANCE,
		chaseConfig.STEP_TIMEOUT,
		function()
			controller.Movement.StepWalkSpeedTransition(controller)
			controller.Audio.TryPlayFootstep(controller)
		end
	)
end

-- Chase loop: runs while target is valid and in range.
local function chaseTarget(controller, target: Model)
	local config = controller.Config
	local combatConfig = config.Combat
	local reevaluateInterval = getTargetSelectionTuning(config)
	local lastReevaluateAt = 0
	controller.StateMachine:SetState(MonsterStateMachine.States.Chase)
	controller.Audio.SetFootstepInterval(controller, config.Audio.Footsteps.CHASE_INTERVAL)
	controller.Movement.SetWalkSpeedTarget(controller, config.MovementSpeeds.CHASE)
	controller.Visual.PlayUniqueAnimation(controller, "Run")
	controller.Movement.StepWalkSpeedTransition(controller)

	local startChaseSound = controller.Audio.FindSound("StartChaseSound")
	if startChaseSound then
		controller.Audio.PlaySound(startChaseSound, controller.RootPart, 5)
	end

	while controller._running and controller.Movement.IsValidTarget(target, controller.Monster) do
		controller.Movement.StepWalkSpeedTransition(controller)
		local now = os.clock()
		if now - lastReevaluateAt >= reevaluateInterval then
			lastReevaluateAt = now
			local preferredTarget = getPreferredTarget(controller, target)
			if preferredTarget and preferredTarget ~= target then
				target = preferredTarget
			end
		end

		local targetRoot = getTargetRootPart(target)
		if not targetRoot then
			return
		end

		local distanceToTarget = (controller.RootPart.Position - targetRoot.Position).Magnitude
		if distanceToTarget > combatConfig.DETECTION_RANGE then
			return
		end

		if handleMeleeEngagement(controller, target, distanceToTarget) then
			continue
		end

		performChaseMoveStep(controller, targetRoot)
		task.wait()
	end
end

-- Main update loop for one monster controller instance.
local function startControllerLoop(controller)
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
			if shouldStareAtTarget(config) then
				stareAtTarget(controller, target)
			else
				chaseTarget(controller, target)
			end
		else
			runIdleForDuration(controller, getRandomIdleDuration(config))
			if not controller._running or controller.Humanoid.Health <= 0 then
				break
			end
			local wanderTarget = runWanderStep(controller)
			if wanderTarget then
				chaseTarget(controller, wanderTarget)
			end
		end

		task.wait(config.Loop.MAIN_TICK_INTERVAL)
	end
	controller:Stop() -- Ensure we clean up if we exited the loop without an explicit stop call.
end

-- Stops this controller instance.
local function stopControllerLoop(controller)
	if not controller._running then
		return
	end

	controller._running = false
	controller.Audio.Stop(controller)
	controller.Visual.Stop(controller)
	controller.StateMachine:SetState(MonsterStateMachine.States.Idle)
end

-- Creates and initializes a new monster controller instance for the given monster model.
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
		_movementTargetWalkSpeed = humanoid.WalkSpeed,
		_movementLastUpdateAt = os.clock(),

		Start = startControllerLoop,
		Stop = stopControllerLoop,
	}

	return controller
end

return MonsterController
