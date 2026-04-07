local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")

local MonsterMovement = {}

-- Returns a model's Humanoid and HumanoidRootPart if available.
local function getHumanoidAndRoot(model: Model): (Humanoid?, BasePart?)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return humanoid, nil
	end

	return humanoid, rootPart
end

-- Sets desired walk speed used by the transition stepper.
function MonsterMovement.SetWalkSpeedTarget(controller, speed: number)
	controller._movementTargetWalkSpeed = math.max(0, speed)
	controller._movementLastUpdateAt = os.clock()
end

-- Steps WalkSpeed toward target using configured acceleration/deceleration values.
function MonsterMovement.StepWalkSpeedTransition(controller)
	local targetSpeed = controller._movementTargetWalkSpeed
	if targetSpeed == nil then
		controller.Visual.UpdateMovementAnimationSpeed(controller)
		return
	end

	local now = os.clock()
	local dt = now - controller._movementLastUpdateAt
	controller._movementLastUpdateAt = now

	if dt <= 0 then
		controller.Visual.UpdateMovementAnimationSpeed(controller)
		return
	end

	local transitionConfig = controller.Config.MovementTransition
	local currentSpeed = controller.Humanoid.WalkSpeed
	local speedDelta = targetSpeed - currentSpeed
	local distanceToTarget = math.abs(speedDelta)
	if distanceToTarget <= transitionConfig.SNAP_DISTANCE then
		controller.Humanoid.WalkSpeed = targetSpeed
		controller.Visual.UpdateMovementAnimationSpeed(controller)
		return
	end

	local ratePerSecond = transitionConfig.ACCELERATION
	if speedDelta < 0 then
		ratePerSecond = transitionConfig.DECELERATION
	end

	local stepAmount = math.max(0, ratePerSecond) * dt
	if stepAmount >= distanceToTarget then
		controller.Humanoid.WalkSpeed = targetSpeed
		controller.Visual.UpdateMovementAnimationSpeed(controller)
		return
	end

	local direction = if speedDelta > 0 then 1 else -1
	controller.Humanoid.WalkSpeed = currentSpeed + (direction * stepAmount)
	controller.Visual.UpdateMovementAnimationSpeed(controller)
end

-- Stops movement immediately while keeping animation speed in sync.
function MonsterMovement.StopImmediately(controller)
	MonsterMovement.SetWalkSpeedTarget(controller, 0)
	controller.Humanoid.WalkSpeed = 0
	controller.Humanoid:Move(Vector3.zero)
	controller.Visual.UpdateMovementAnimationSpeed(controller)
end

-- Valid target = exists, not the monster itself, still in workspace, alive, and has root part.
function MonsterMovement.IsValidTarget(target: Model?, monster: Model): boolean
	if not target or target == monster or not target.Parent then
		return false
	end

	local humanoid, rootPart = getHumanoidAndRoot(target)
	return humanoid ~= nil and rootPart ~= nil and humanoid.Health > 0
end

-- Finds the closest valid target model in Workspace within detectionRange.
function MonsterMovement.GetClosestTarget(monster: Model, monsterRoot: BasePart, detectionRange: number): Model?
	local closestTarget: Model? = nil
	local shortestDistance = detectionRange

	for _, candidate in ipairs(Workspace:GetChildren()) do
		if candidate:IsA("Model") and candidate ~= monster then
			local humanoid, rootPart = getHumanoidAndRoot(candidate)
			if humanoid and rootPart and humanoid.Health > 0 then
				local distance = (monsterRoot.Position - rootPart.Position).Magnitude
				if distance <= shortestDistance then
					shortestDistance = distance
					closestTarget = candidate
				end
			end
		end
	end

	return closestTarget
end

-- Computes a path from startPosition to endPosition using pathfinding.
function MonsterMovement.ComputePath(
	pathSettings: { [string]: any },
	startPosition: Vector3,
	endPosition: Vector3
): Path?
	local path = PathfindingService:CreatePath(pathSettings)
	local success = pcall(function()
		path:ComputeAsync(startPosition, endPosition)
	end)

	if not success then
		return nil
	end

	if path.Status ~= Enum.PathStatus.Success then
		return nil
	end

	return path
end

-- Moves humanoid toward position until either reached or timeout.
-- Uses horizontal distance only, so different floor/height does not break completion.
function MonsterMovement.MoveToPosition(
	humanoid: Humanoid,
	rootPart: BasePart,
	position: Vector3,
	closeDistance: number,
	timeout: number,
	onStep: (() -> boolean?)?
): boolean
	humanoid:MoveTo(position)
	local targetFlat = Vector3.new(position.X, 0, position.Z)

	local startTime = os.clock()
	while os.clock() - startTime <= timeout do
		if onStep then
			if onStep() then
				humanoid:MoveTo(rootPart.Position)
				return false
			end
		end

		local currentFlat = Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
		if (currentFlat - targetFlat).Magnitude <= closeDistance then
			return true
		end
		task.wait()
	end

	return false
end

-- For chase movement: pick the first waypoint that is meaningfully ahead.
function MonsterMovement.PickNextWaypoint(
	path: Path,
	monsterRoot: BasePart,
	minimumDistance: number,
	fallbackPosition: Vector3
): Vector3
	local nextPosition = fallbackPosition

	for index, waypoint in ipairs(path:GetWaypoints()) do
		if index == 1 then
			continue
		end

		if (monsterRoot.Position - waypoint.Position).Magnitude > minimumDistance then
			nextPosition = waypoint.Position
			break
		end
	end

	return nextPosition
end

-- For wander movement: prefer the farthest waypoint that is far enough from start.
-- Falls back to the last waypoint so one-step wander heads toward the goal instead of stopping early.
function MonsterMovement.FindWanderWaypoint(
	path: Path,
	startPosition: Vector3,
	minimumDistance: number
): (Vector3?, number?, number?)
	local waypoints = path:GetWaypoints()
	local selectedPosition: Vector3? = nil
	local selectedIndex: number? = nil
	local selectedDistance: number? = nil
	local lastWaypointPosition: Vector3? = nil
	local lastWaypointIndex: number? = nil
	local lastWaypointDistance: number? = nil

	for index, waypoint in ipairs(waypoints) do
		if index == 1 then
			continue
		end

		local distanceFromStart = (startPosition - waypoint.Position).Magnitude
		lastWaypointPosition = waypoint.Position
		lastWaypointIndex = index
		lastWaypointDistance = distanceFromStart

		if distanceFromStart >= minimumDistance then
			selectedPosition = waypoint.Position
			selectedIndex = index
			selectedDistance = distanceFromStart
		end
	end

	if selectedPosition then
		return selectedPosition, selectedIndex, selectedDistance
	end

	return lastWaypointPosition, lastWaypointIndex, lastWaypointDistance
end

-- Picks a random wander goal around the monster.
-- minimumDistance avoids tiny "walk in place" wander moves.
function MonsterMovement.GetRandomWanderGoal(
	monsterRoot: BasePart,
	wanderRadius: number,
	minimumDistance: number?,
	maxAttempts: number?
): Vector3
	local maxDistance = math.max(0, wanderRadius)
	local minDistance = math.clamp(minimumDistance or 0, 0, maxDistance)
	local attempts = math.max(1, maxAttempts or 8)

	for _ = 1, attempts do
		local randomOffset =
			Vector3.new(math.random(-maxDistance, maxDistance), 0, math.random(-maxDistance, maxDistance))
		local offsetDistance = randomOffset.Magnitude

		if offsetDistance >= minDistance and offsetDistance <= maxDistance then
			return monsterRoot.Position + randomOffset
		end
	end

	local fallbackAngle = math.random() * math.pi * 2
	local fallbackDistance = minDistance + math.random() * (maxDistance - minDistance)
	local fallbackOffset =
		Vector3.new(math.cos(fallbackAngle) * fallbackDistance, 0, math.sin(fallbackAngle) * fallbackDistance)

	return monsterRoot.Position + fallbackOffset
end

return MonsterMovement
