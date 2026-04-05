local MonsterController = {}

local parentFolder = script.Parent
if not parentFolder then
	error("MonsterController must be parented before requires")
end

local logicFolder = parentFolder:WaitForChild("logic")
local fxFolder = parentFolder:WaitForChild("fx")

local configModule = parentFolder:WaitForChild("Config") :: ModuleScript
local movementModule = logicFolder:WaitForChild("Movement") :: ModuleScript
local combatModule = logicFolder:WaitForChild("Combat") :: ModuleScript
local stateMachineModule = logicFolder:WaitForChild("StateMachine") :: ModuleScript
local visualModule = fxFolder:WaitForChild("Visual") :: ModuleScript
local audioModule = fxFolder:WaitForChild("Audio") :: ModuleScript

local Config = require(configModule)
local Movement = require(movementModule)
local Combat = require(combatModule)
local MonsterVisual = require(visualModule)
local MonsterAudio = require(audioModule)
local MonsterStateMachine = require(stateMachineModule)

-- State transition wrapper.
local function setState(controller, nextState: string)
	controller.StateMachine:SetState(nextState)
end

-- Runs idle state for a fixed duration.
local function enterIdle(controller, duration: number)
	controller:_setState(MonsterStateMachine.States.Idle)
	controller.Humanoid.WalkSpeed = 0
	controller.Humanoid:Move(Vector3.zero)
	controller.Audio.SetFootstepInterval(controller, controller.Config.WANDER_FOOTSTEP_INTERVAL)
	controller.Visual.PlayIdleAnimation(controller)

	local endTime = os.clock() + duration
	while
		controller._running
		and controller.Monster.Parent
		and controller.Humanoid.Health > 0
		and os.clock() < endTime
	do
		task.wait(controller.Config.IDLE_TICK_INTERVAL)
	end
end

-- Chooses one wander destination point from path waypoints.
-- Returns position metadata, or nil on failure.
local function chooseWanderDestination(controller): (Vector3?, number?, number?)
	local goal = controller.Movement.GetRandomWanderGoal(
		controller.RootPart,
		controller.Config.WANDER_RADIUS,
		controller.Config.WANDER_MIN_DISTANCE,
		controller.Config.WANDER_GOAL_ATTEMPTS
	)

	local path = controller.Movement.ComputePath(controller.Config.PATH_SETTINGS, controller.RootPart.Position, goal)
	if not path then
		return nil, nil, nil
	end

	local selectedPosition, selectedIndex, selectedDistance = controller.Movement.FindWanderWaypoint(
		path,
		controller.RootPart.Position,
		controller.Config.WANDER_MIN_WAYPOINT_DISTANCE
	)

	return selectedPosition, selectedIndex, selectedDistance
end

-- Single wander action:
-- 1) Enter wander state
-- 2) Pick one destination
-- 3) Move once
-- 4) Return to idle
local function wanderStep(controller)
	controller:_setState(MonsterStateMachine.States.Wander)
	controller.Audio.SetFootstepInterval(controller, controller.Config.WANDER_FOOTSTEP_INTERVAL)
	controller.Humanoid.WalkSpeed = controller.Config.WANDER_WALK_SPEED
	controller.Visual.PlayUniqueAnimation(controller, "Walk")
	local wanderStartTime = os.clock()

	local destination = chooseWanderDestination(controller)
	if not destination then
		controller:_enterIdle(controller.Config.WANDER_PATH_FAIL_IDLE_TIME)
		task.wait(0.2)
		return
	end

	if os.clock() - wanderStartTime >= controller.Config.WANDER_MAX_DURATION then
		controller:_enterIdle(controller.Config.IDLE_AFTER_WANDER_TIME)
		return
	end

	if not controller._running or controller.Humanoid.Health <= 0 then
		return
	end
	controller.Movement.MoveToPosition(
		controller.Humanoid,
		controller.RootPart,
		destination,
		5,
		controller.Config.WANDER_WAYPOINT_TIMEOUT,
		function()
			controller.Audio.TryPlayFootstep(controller)
		end
	)

	controller:_enterIdle(controller.Config.IDLE_AFTER_WANDER_TIME)
end

-- Chase loop: runs while target is valid and in range.
local function chaseTarget(controller, target: Model)
	controller:_setState(MonsterStateMachine.States.Chase)
	controller.Audio.SetFootstepInterval(controller, controller.Config.CHASE_FOOTSTEP_INTERVAL)
	controller.Humanoid.WalkSpeed = controller.Config.CHASE_WALK_SPEED
	controller.Visual.PlayUniqueAnimation(controller, "Run")

	local startChaseSound = controller.Audio.FindSound(controller, "StartChaseSound")
	if startChaseSound then
		controller.Audio.PlaySound(startChaseSound, controller.RootPart, 5)
	end

	while controller._running and controller.Movement.IsValidTarget(target, controller.Monster) do
		if controller.Humanoid.WalkSpeed ~= controller.Config.CHASE_WALK_SPEED then
			controller.Humanoid.WalkSpeed = controller.Config.CHASE_WALK_SPEED
		end

		local _, targetRoot = controller.Movement.GetHumanoidAndRoot(target)
		if not targetRoot then
			return
		end

		local distanceToTarget = (controller.RootPart.Position - targetRoot.Position).Magnitude
		if distanceToTarget > controller.Config.ATTACK_DETECTION_RANGE then
			return
		end

		if distanceToTarget <= controller.Config.MELEE_RANGE then
			if os.clock() - controller._lastAttackTime < controller.Config.ATTACK_COOLDOWN then
				task.wait(0.05)
				continue
			end

			controller:_setState(MonsterStateMachine.States.Attack)
			controller.Visual.PlayUniqueAnimation(controller, "Attack")

			local attackSound = controller.Audio.FindSound(controller, "Attack")
			if attackSound and attackSound:IsA("Sound") then
				controller.Audio.PlaySound(attackSound, controller.RootPart, 4)
			end

			local didAttack, newLastAttack, attackedModel, attackedRoot = controller.Combat.PerformSwingAttack(
				controller.Monster,
				target,
				controller.RootPart,
				controller.Config,
				controller._lastAttackTime
			)
			controller._lastAttackTime = newLastAttack

			if didAttack and attackedModel and attackedRoot then
				local headBlowSound = controller.Audio.FindSound(controller, "HeadBlow")
				if headBlowSound and headBlowSound:IsA("Sound") then
					controller.Audio.PlaySound(headBlowSound, controller.RootPart, 3)
				end

				controller.Visual.PlayKillBlood(
					controller,
					attackedModel,
					attackedRoot,
					controller.Config.BLOOD_PART_AMOUNT
				)
			end

			controller:_setState(MonsterStateMachine.States.Chase)
			task.wait(0.05)
			continue
		end

		local path = controller.Movement.ComputePath(
			controller.Config.PATH_SETTINGS,
			controller.RootPart.Position,
			targetRoot.Position
		)
		local nextPosition = targetRoot.Position
		if path then
			nextPosition = controller.Movement.PickNextWaypoint(
				path,
				controller.RootPart,
				controller.Config.WAYPOINT_MIN_DISTANCE,
				targetRoot.Position
			)
		end

		controller.Movement.MoveToPosition(
			controller.Humanoid,
			controller.RootPart,
			nextPosition,
			controller.Config.CHASE_WAYPOINT_REACHED_DISTANCE or controller.Config.WAYPOINT_REACHED_DISTANCE,
			controller.Config.CHASE_MOVE_TIMEOUT or 0.4,
			function()
				controller.Audio.TryPlayFootstep(controller)
			end
		)
		task.wait()
	end
end

-- Main update loop for one monster controller instance.
local function start(controller, enableWanderSounds: boolean?)
	if controller._running then
		return
	end

	controller._running = true
	controller.Visual.Start(controller)
	controller.Audio.Start(controller, enableWanderSounds == true)

	while controller._running and controller.Monster.Parent and controller.Humanoid.Health > 0 do
		local target = controller.Movement.GetClosestTarget(
			controller.Monster,
			controller.RootPart,
			controller.Config.ATTACK_DETECTION_RANGE
		)

		if target then
			controller:_chaseTarget(target)
		else
			controller:_enterIdle(controller.Config.IDLE_BEFORE_WANDER_TIME)
			if not controller._running or controller.Humanoid.Health <= 0 then
				break
			end
			controller:_wanderStep()
		end

		task.wait(0.1)
	end
	controller:Stop()
end

-- Stops this controller instance.
local function stop(controller)
	if not controller._running then
		return
	end

	controller._running = false
	controller.Audio.Stop(controller)
	controller.Visual.Stop(controller)
	controller:_setState(MonsterStateMachine.States.Idle)
end

-- Creates one controller for one monster model.
function MonsterController.new(monster: Model)
	local humanoid, rootPart = Movement.GetHumanoidAndRoot(monster)
	if not humanoid or not rootPart then
		return nil, "Monster is missing Humanoid or HumanoidRootPart"
	end

	local animationsFolder = fxFolder:WaitForChild("Animations")
	local objectsFolder = fxFolder:WaitForChild("Objects")
	local soundsFolder = fxFolder:WaitForChild("Sounds")

	local controller = {
		Monster = monster,
		Humanoid = humanoid,
		RootPart = rootPart,
		AnimationsFolder = animationsFolder,
		Config = Config,
		Movement = Movement,
		Combat = Combat,
		Visual = MonsterVisual,
		Audio = MonsterAudio,
		SoundsFolder = soundsFolder,
		ObjectsFolder = objectsFolder,
		StateMachine = MonsterStateMachine.new(MonsterStateMachine.States.Idle),

		_running = false,
		_lastAttackTime = 0,
		_visualRunning = false,
		_visualCurrentAnimationTrack = nil,
		_visualCurrentAnimationName = nil,
		_audioRunning = false,
		_audioFootstepInterval = Config.WANDER_FOOTSTEP_INTERVAL,
		_audioLastFootstepAt = 0,

		_setState = setState,
		_enterIdle = enterIdle,
		_wanderStep = wanderStep,
		_chaseTarget = chaseTarget,
		Start = start,
		Stop = stop,
	}

	return controller
end

return MonsterController
