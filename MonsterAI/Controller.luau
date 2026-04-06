local MonsterController = {}

local logicFolder = (script.Parent :: Instance):WaitForChild("logic")
local fxFolder = (script.Parent :: Instance):WaitForChild("fx")

local replicatedStorage = game:GetService("ReplicatedStorage")
local remote = replicatedStorage:WaitForChild("Remotes"):WaitForChild("MonsterChasingEvent")

local MonsterConfig = require((script.Parent :: Instance):WaitForChild("Config") :: ModuleScript)
local MovementLogic = require(logicFolder:WaitForChild("Movement") :: ModuleScript)
local CombatLogic = require(logicFolder:WaitForChild("Combat") :: ModuleScript)
local MonsterStateMachine = require(logicFolder:WaitForChild("StateMachine") :: ModuleScript)
local MonsterVisual = require(fxFolder:WaitForChild("Visual") :: ModuleScript)
local MonsterAudio = require(fxFolder:WaitForChild("Audio") :: ModuleScript)

local function setTargetWalkSpeed(controller, speed: number)
	controller._movementTargetWalkSpeed = math.max(0, speed)
	controller._movementLastUpdateAt = os.clock()
end

local function updateMovementAnimationSpeed(controller)
	if controller.Visual and controller.Visual.UpdateMovementAnimationSpeed then
		controller.Visual.UpdateMovementAnimationSpeed(controller)
	end
end

local function updateWalkSpeed(controller)
	local targetSpeed = controller._movementTargetWalkSpeed
	if targetSpeed == nil then
		updateMovementAnimationSpeed(controller)
		return
	end

	local now = os.clock()
	local dt = now - controller._movementLastUpdateAt
	controller._movementLastUpdateAt = now

	if dt <= 0 then
		updateMovementAnimationSpeed(controller)
		return
	end

	local transitionConfig = controller.Config.MovementTransition
	local currentSpeed = controller.Humanoid.WalkSpeed
	local speedDelta = targetSpeed - currentSpeed
	local distanceToTarget = math.abs(speedDelta)
	if distanceToTarget <= transitionConfig.SNAP_DISTANCE then
		controller.Humanoid.WalkSpeed = targetSpeed
		updateMovementAnimationSpeed(controller)
		return
	end

	local ratePerSecond = transitionConfig.ACCELERATION
	if speedDelta < 0 then
		ratePerSecond = transitionConfig.DECELERATION
	end

	local stepAmount = math.max(0, ratePerSecond) * dt
	if stepAmount >= distanceToTarget then
		controller.Humanoid.WalkSpeed = targetSpeed
		updateMovementAnimationSpeed(controller)
		return
	end

	local direction = if speedDelta > 0 then 1 else -1
	controller.Humanoid.WalkSpeed = currentSpeed + (direction * stepAmount)
	updateMovementAnimationSpeed(controller)
end

local function getRandomIdleDuration(config): number
	local minDuration = config.Idle.MIN_DURATION
	local maxDuration = config.Idle.MAX_DURATION

	if maxDuration < minDuration then
		minDuration, maxDuration = maxDuration, minDuration
	end

	return minDuration + math.random() * (maxDuration - minDuration)
end

-- Runs idle state for a duration.
local function enterIdle(controller, duration: number)
	local config = controller.Config
	controller.StateMachine:SetState(MonsterStateMachine.States.Idle)
	setTargetWalkSpeed(controller, 0)
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
		updateWalkSpeed(controller)
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
-- 4) Return to idle
local function wanderStep(controller)
	local config = controller.Config
	controller.StateMachine:SetState(MonsterStateMachine.States.Wander)
	controller.Audio.SetFootstepInterval(controller, config.Audio.Footsteps.WANDER_INTERVAL)
	setTargetWalkSpeed(controller, config.MovementSpeeds.WANDER)
	controller.Visual.PlayUniqueAnimation(controller, "Walk")
	updateWalkSpeed(controller)
	local wanderStartTime = os.clock()
	local wanderGoal, goalDistance = chooseWanderGoal(controller)
	local wanderSpeed = math.max(0.1, config.MovementSpeeds.WANDER)
	local wanderTimeBudget = math.max(config.Wander.MAX_STEP_DURATION, (goalDistance / wanderSpeed) + 1)

	while controller._running and controller.Humanoid.Health > 0 do
		local elapsed = os.clock() - wanderStartTime
		if elapsed >= wanderTimeBudget then
			break
		end

		local path = controller.Movement.ComputePath(config.Path, controller.RootPart.Position, wanderGoal)
		if not path then
			updateWalkSpeed(controller)
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
				updateWalkSpeed(controller)
				controller.Audio.TryPlayFootstep(controller)
			end
		)

		if (controller.RootPart.Position - wanderGoal).Magnitude <= config.Wander.REACHED_DISTANCE then
			break
		end

		task.wait()
	end

	enterIdle(controller, getRandomIdleDuration(config))
end

local function playAttackHitPresentation(controller, didAttack: boolean, attackedModel: Model?, attackedRoot: BasePart?)
	if not didAttack or not attackedModel or not attackedRoot then
		return
	end

	local headBlowSound = controller.Audio.FindSound("HeadBlow")
	if headBlowSound and headBlowSound:IsA("Sound") then
		controller.Audio.PlaySound(headBlowSound, controller.RootPart, 3)
	end

	controller.Visual.PlayKillBloodEffect(
		controller,
		attackedModel,
		attackedRoot,
		controller.Config.Visual.BLOOD_PART_AMOUNT
	)
end

local function waitForAttackAnimationHandoff(controller, attackTrack: AnimationTrack?)
	local visualConfig = controller.Config.Visual
	local transitionConfig = visualConfig and visualConfig.AnimationTransitions
	if not transitionConfig then
		return
	end

	local maxHold = math.max(0, transitionConfig.MAX_ATTACK_HOLD or 0)
	if maxHold <= 0 then
		return
	end

	if not attackTrack or attackTrack.Length <= 0 then
		return
	end

	local earlyBlend = math.max(0, transitionConfig.ATTACK_END_EARLY_BLEND or 0)
	local remainingTime = math.max(0, attackTrack.Length - attackTrack.TimePosition - earlyBlend)
	local waitDuration = math.min(remainingTime, maxHold)
	if waitDuration > 0 then
		task.wait(waitDuration)
	end
end

local function performMeleeAttack(controller, target: Model)
	local config = controller.Config
	setTargetWalkSpeed(controller, 0)
	controller.Humanoid.WalkSpeed = 0
	controller.Humanoid:Move(Vector3.zero)
	controller.Humanoid:MoveTo(controller.RootPart.Position)
	updateMovementAnimationSpeed(controller)
	controller.StateMachine:SetState(MonsterStateMachine.States.Attack)
	local attackTrack = controller.Visual.PlayUniqueAnimation(controller, "Attack")

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
	waitForAttackAnimationHandoff(controller, attackTrack)

	controller.StateMachine:SetState(MonsterStateMachine.States.Chase)
	local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
	if targetHumanoid and targetHumanoid.Health > 0 then
		setTargetWalkSpeed(controller, config.MovementSpeeds.CHASE)
	else
		setTargetWalkSpeed(controller, 0)
	end
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
			updateWalkSpeed(controller)
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
	setTargetWalkSpeed(controller, config.MovementSpeeds.CHASE)
	controller.Visual.PlayUniqueAnimation(controller, "Run")
	updateWalkSpeed(controller)

	local startChaseSound = controller.Audio.FindSound("StartChaseSound")
	if startChaseSound then
		controller.Audio.PlaySound(startChaseSound, controller.RootPart, 5)
	end

	local targetPlayer = game.Players:GetPlayerFromCharacter(target)

	--remote:FireClient(targetPlayer)

	while controller._running and controller.Movement.IsValidTarget(target, controller.Monster) do
		updateWalkSpeed(controller)

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
			enterIdle(controller, getRandomIdleDuration(config))
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
		_movementTargetWalkSpeed = humanoid.WalkSpeed,
		_movementLastUpdateAt = os.clock(),

		Start = start,
		Stop = stop,
	}

	return controller
end

return MonsterController
