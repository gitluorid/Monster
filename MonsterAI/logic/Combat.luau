local Debris = game:GetService("Debris")

local MonsterCombat = {}

-- Shared helper used to read target parts safely.
local function getHumanoidAndRoot(model: Model): (Humanoid?, BasePart?)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return humanoid, nil
	end

	return humanoid, rootPart
end
-- Performs one melee swing attack.
-- Returns (didAttack, newLastAttackTime, attackedModel, attackedRoot).
function MonsterCombat.PerformSwingAttack(
	monster: Model,
	target: Model,
	monsterRoot: BasePart,
	config,
	lastAttackTime: number
): (boolean, number, Model?, BasePart?)
	local combatConfig = config.Combat
	-- Cooldown gate.
	local now = os.clock()
	if now - lastAttackTime < combatConfig.ATTACK_COOLDOWN then
		return false, lastAttackTime, nil, nil
	end

	-- Validate target rig pieces.
	local targetHumanoid, targetRoot = getHumanoidAndRoot(target)
	if not targetHumanoid or not targetRoot then
		return false, lastAttackTime, nil, nil
	end

	local targetModel = targetRoot.Parent
	if not targetModel or not targetModel:IsA("Model") then
		return false, lastAttackTime, nil, nil
	end

	-- Prevent any same-target edge case.
	if targetModel == monster then
		return false, lastAttackTime, nil, nil
	end

	-- Wait for swing windup so the hit lands after the animation starts.
	local hitDelay = combatConfig.SWING_HIT_DELAY

	-- Hold the full target rig by root so body/head stay together.
	local leftHand = monster:FindFirstChild("Left Hand") or monster:FindFirstChild("LeftHand")
	local holdWeld: WeldConstraint? = nil
	local anchoredMonsterForSwing = false
	if leftHand and leftHand:IsA("BasePart") then
		monsterRoot.Anchored = true
		anchoredMonsterForSwing = true

		targetModel:PivotTo(leftHand.CFrame * CFrame.new(0, -2.5, -0.8))
		targetRoot.AssemblyLinearVelocity = Vector3.zero
		targetRoot.AssemblyAngularVelocity = Vector3.zero

		local createdWeld = Instance.new("WeldConstraint")
		createdWeld.Part0 = leftHand
		local targetHead = targetModel:FindFirstChild("Head")
		if targetHead and targetHead:IsA("BasePart") then
			createdWeld.Part1 = targetHead
		else
			createdWeld.Part1 = targetRoot
		end
		createdWeld.Name = "MonsterWeld"
		createdWeld.Parent = leftHand
		holdWeld = createdWeld
	end

	if hitDelay > 0 then
		task.wait(hitDelay)
	end

	-- Kill instantly after the swing windup delay.
	if targetHumanoid.Health > 0 then
		targetHumanoid.Health = 0
	end

	if holdWeld and holdWeld.Parent then
		holdWeld:Destroy()
	end

	task.wait(0.01)

	local leftForce = -monsterRoot.CFrame.RightVector * combatConfig.KNOCKBACK_FORCE
	local bv = Instance.new("BodyVelocity")
	bv.Velocity = leftForce
	bv.Parent = targetRoot
	bv.P = combatConfig.KNOCKBACK_POWER
	bv.MaxForce = Vector3.new(combatConfig.KNOCKBACK_POWER, combatConfig.KNOCKBACK_POWER, combatConfig.KNOCKBACK_POWER)
	Debris:AddItem(bv, combatConfig.KNOCKBACK_DURATION)

	if anchoredMonsterForSwing then
		monsterRoot.Anchored = false
	end
	return true, now, targetModel, targetRoot
end
return MonsterCombat
