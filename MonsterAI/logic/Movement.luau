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
	onStep: (() -> ())?
): boolean
	humanoid:MoveTo(position)
	local targetFlat = Vector3.new(position.X, 0, position.Z)

	local startTime = os.clock()
	while os.clock() - startTime <= timeout do
		if onStep then
			onStep()
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

-- For wander movement: find first waypoint that is far enough from where wander started.
function MonsterMovement.FindWanderWaypoint(
	path: Path,
	startPosition: Vector3,
	minimumDistance: number
): (Vector3?, number?, number?)
	local waypoints = path:GetWaypoints()
	for index, waypoint in ipairs(waypoints) do
		if index == 1 then
			continue
		end

		local distanceFromStart = (startPosition - waypoint.Position).Magnitude
		if distanceFromStart >= minimumDistance then
			return waypoint.Position, index, distanceFromStart
		end
	end

	return nil, nil, nil
end

-- Picks a random wander goal around the monster.
-- minimumDistance avoids tiny "walk in place" wander moves.
function MonsterMovement.GetRandomWanderGoal(
	monsterRoot: BasePart,
	wanderRadius: number,
	minimumDistance: number?,
	maxAttempts: number?
): Vector3
	local minDistance = math.clamp(minimumDistance or 0, 0, math.max(0, wanderRadius))
	local attempts = math.max(1, maxAttempts or 8)

	for _ = 1, attempts do
		local randomOffset =
			Vector3.new(math.random(-wanderRadius, wanderRadius), 0, math.random(-wanderRadius, wanderRadius))

		if randomOffset.Magnitude >= minDistance then
			return monsterRoot.Position + randomOffset
		end
	end

	local fallbackAngle = math.random() * math.pi * 2
	local fallbackDistance = math.max(minDistance, wanderRadius * 0.65)
	local fallbackOffset =
		Vector3.new(math.cos(fallbackAngle) * fallbackDistance, 0, math.sin(fallbackAngle) * fallbackDistance)

	return monsterRoot.Position + fallbackOffset
end

return MonsterMovement
