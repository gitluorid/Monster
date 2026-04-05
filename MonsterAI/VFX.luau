local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local MonsterVFX = {}

local function playAnimation(animationTemplate: Animation, model: Model): AnimationTrack?
	if not animationTemplate or not model then
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animationClone = animationTemplate:Clone()
	animationClone.Parent = model

	local animationTrack = animator:LoadAnimation(animationClone)
	animationTrack:Play()

	animationTrack.Stopped:Connect(function()
		if animationClone.Parent then
			animationClone:Destroy()
		end
	end)

	return animationTrack
end

local function stopAnimation(animationTrack: AnimationTrack?)
	if animationTrack then
		animationTrack:Stop()
	end
end

-- Spawns simple blood particles for visual feedback.
function MonsterVFX.SpawnBlood(origin: CFrame, amount: number)
	task.spawn(function()
		for _ = 1, amount do
			local part = Instance.new("Part")
			part.Size = Vector3.new(0.5, 0.5, 0.5)
			part.CFrame = origin
			part.Anchored = false
			part.CanCollide = false
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

-- Chooses blood origin from target head when available, then spawns blood.
function MonsterVFX.PlayKillBlood(targetModel: Model, targetRoot: BasePart, amount: number)
	local targetHead = targetModel:FindFirstChild("Head")
	local bloodOrigin = targetRoot.CFrame
	if targetHead and targetHead:IsA("BasePart") then
		bloodOrigin = targetHead.CFrame
		targetHead:Destroy()
	end

	MonsterVFX.SpawnBlood(bloodOrigin, amount)
end

-- Plays an animation by name and ensures only one animation track is active at a time.
function MonsterVFX.PlayUniqueAnimation(controller, animationName: string): AnimationTrack?
	local animation = controller.AnimationsFolder:FindFirstChild(animationName)
	if not animation or not animation:IsA("Animation") then
		return nil
	end

	if
		controller._vfxCurrentAnimationTrack
		and controller._vfxCurrentAnimationTrack.IsPlaying
		and controller._vfxCurrentAnimationName == animation.Name
	then
		return controller._vfxCurrentAnimationTrack
	end

	if controller._vfxCurrentAnimationTrack then
		stopAnimation(controller._vfxCurrentAnimationTrack)
		controller._vfxCurrentAnimationTrack = nil
		controller._vfxCurrentAnimationName = nil
	end

	controller._vfxCurrentAnimationTrack = playAnimation(animation, controller.Monster)
	controller._vfxCurrentAnimationName = animation.Name

	return controller._vfxCurrentAnimationTrack
end

-- Tries to play idle animation.
-- If no Idle animation exists, it stops the currently playing movement animation.
function MonsterVFX.PlayIdleAnimation(controller): AnimationTrack?
	local idleTrack = MonsterVFX.PlayUniqueAnimation(controller, "Idle")
	if idleTrack then
		return idleTrack
	end

	-- If there is no idle animation asset, stop motion animation so the monster visually idles.
	if controller._vfxCurrentAnimationTrack then
		stopAnimation(controller._vfxCurrentAnimationTrack)
		controller._vfxCurrentAnimationTrack = nil
		controller._vfxCurrentAnimationName = nil
	end

	return nil
end

-- Starts VFX subsystem for this monster.
function MonsterVFX.Start(controller)
	if controller._vfxRunning then
		return
	end

	controller._vfxRunning = true
end

-- Stops VFX and active animation track.
function MonsterVFX.Stop(controller)
	controller._vfxRunning = false

	if controller._vfxCurrentAnimationTrack then
		stopAnimation(controller._vfxCurrentAnimationTrack)
		controller._vfxCurrentAnimationTrack = nil
		controller._vfxCurrentAnimationName = nil
	end
end

return MonsterVFX
