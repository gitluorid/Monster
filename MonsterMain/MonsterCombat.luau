local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local replicatedStorage = game:GetService("ReplicatedStorage")

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

-- Spawns simple blood particles for visual feedback.
local function spawnBlood(origin: CFrame, amount: number)
	task.spawn(function()
		for _ = 1, amount do
			local part = Instance.new("Part")
			part.Size = Vector3.new(0.5, 0.5, 0.5)
			part.CFrame = origin
			part.Anchored = false
			part.CanCollide = true
			part.Parent = Workspace
			part.Color = Color3.fromRGB(120, 0, 0)
			part.Material = Enum.Material.Limestone
			
			

			local velocity = Instance.new("BodyVelocity")
			velocity.Velocity = Vector3.new(math.random(-10, 10), math.random(10, 10), math.random(-10, 10))
			velocity.Parent = part

			Debris:AddItem(velocity, 0.2)
			Debris:AddItem(part, 5)
		end
	end)
end

-- Performs one melee swing attack.
-- Returns (didAttack, newLastAttackTime).
function MonsterCombat.PerformSwingAttack(
	monster: Model,
	target: Model,
	monsterRoot: BasePart,
	vfx,
	vfxContext,
	utils,
	otherSoundsFolder: Instance,
	config,
	lastAttackTime: number
): (boolean, number)
	-- Cooldown gate.
	local now = os.clock()
	if now - lastAttackTime < config.ATTACK_COOLDOWN then
		return false, lastAttackTime
	end

	-- Validate target rig pieces.
	local targetHumanoid, targetRoot = getHumanoidAndRoot(target)
	if not targetHumanoid or not targetRoot then
		return false, lastAttackTime
	end

	local targetModel = targetRoot.Parent
	if not targetModel or not targetModel:IsA("Model") then
		return false, lastAttackTime
	end

	-- Prevent any same-target edge case.
	if targetModel == monster then
		return false, lastAttackTime
	end

	-- Visual/audio startup for the attack.
	local _attackTrack = vfx.PlayUniqueAnimation(vfxContext, "Attack")
	
	local attackSound = otherSoundsFolder:FindFirstChild("Attack")
	if attackSound and attackSound:IsA("Sound") then
		utils.PlaySound(attackSound, monsterRoot, 4)
	end

	-- Wait for swing windup so the hit lands after the animation starts.
	local hitDelay = 0.7

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
		createdWeld.Part1 = targetRoot.Parent["Head"]
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

	local headBlowSound = otherSoundsFolder:FindFirstChild("HeadBlow")
	if headBlowSound and headBlowSound:IsA("Sound") then
		utils.PlaySound(headBlowSound, monsterRoot, 3)
	end

	-- Pick blood spawn origin (head preferred, root fallback).
	local targetHead = targetModel:FindFirstChild("Head")
	local bloodOrigin = targetRoot.CFrame
	if targetHead and targetHead:IsA("BasePart") then
		bloodOrigin = targetHead.CFrame
		targetHead:Destroy()
	end
	
	spawnBlood(bloodOrigin, config.BLOOD_PART_AMOUNT)
	
	local vfx = replicatedStorage.Monster.Vfx.NeckBlood
	
	if holdWeld and holdWeld.Parent then
		holdWeld:Destroy()
	end
	
	task.wait(0.01)
	
	local leftForce = -monsterRoot.CFrame.RightVector * 100 -- Multiply by force amount
	local bv = Instance.new("BodyVelocity")
	bv.Velocity = leftForce
	bv.Parent = targetModel.HumanoidRootPart
	bv.P = 10000
	bv.MaxForce = Vector3.new(10000, 10000, 10000)
	game.Debris:AddItem(bv, 0.2)

	if anchoredMonsterForSwing then
		monsterRoot.Anchored = false
	end
	return true, now
end
return MonsterCombat
