local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local MonsterVisual = {}
local fxFolder = script.Parent
if not fxFolder then
	error("MonsterVisual must be parented under fx")
end
local animationsFolder = fxFolder:WaitForChild("Animations")
local DEFAULT_EFFECT_LIFETIME = 5

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
function MonsterVisual.SpawnBlood(origin: CFrame, amount: number, effectLifetime: number?)
	local lifetime = effectLifetime or DEFAULT_EFFECT_LIFETIME
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
			part.Parent = workspace
			local velocity = Instance.new("BodyVelocity")
			velocity.Velocity = Vector3.new(math.random(-20, 20), math.random(10, 20), math.random(-20, 20))
			velocity.Parent = part

			Debris:AddItem(velocity, 0.2)
			Debris:AddItem(part, lifetime)
		end
	end)
end

-- Chooses blood origin from target head when available, then plays kill blood visual effects.
function MonsterVisual.PlayKillBloodEffect(controller, targetModel: Model, targetRoot: BasePart, amount: number)
	local effectLifetime = controller.Config.Visual.EFFECT_LIFETIME
	local targetHead = targetModel:FindFirstChild("Head")
	local bloodOrigin = targetRoot.CFrame
	if targetHead and targetHead:IsA("BasePart") then
		bloodOrigin = targetHead.CFrame
		targetHead:Destroy()
	end

	MonsterVisual.SpawnBlood(bloodOrigin, amount, effectLifetime)
end

-- Plays an animation by name and ensures only one animation track is active at a time.
function MonsterVisual.PlayUniqueAnimation(controller, animationName: string): AnimationTrack?
	local animation = animationsFolder:FindFirstChild(animationName)
	if not animation or not animation:IsA("Animation") then
		return nil
	end

	if
		controller._visualCurrentAnimationTrack
		and controller._visualCurrentAnimationTrack.IsPlaying
		and controller._visualCurrentAnimationName == animation.Name
	then
		return controller._visualCurrentAnimationTrack
	end

	if controller._visualCurrentAnimationTrack then
		stopAnimation(controller._visualCurrentAnimationTrack)
		controller._visualCurrentAnimationTrack = nil
		controller._visualCurrentAnimationName = nil
	end

	controller._visualCurrentAnimationTrack = playAnimation(animation, controller.Monster)
	controller._visualCurrentAnimationName = animation.Name

	return controller._visualCurrentAnimationTrack
end

-- Tries to play idle animation.
-- If no Idle animation exists, it stops the currently playing movement animation.
function MonsterVisual.PlayIdleAnimation(controller): AnimationTrack?
	local idleTrack = MonsterVisual.PlayUniqueAnimation(controller, "Idle")
	if idleTrack then
		return idleTrack
	end

	-- If there is no idle animation asset, stop motion animation so the monster visually idles.
	if controller._visualCurrentAnimationTrack then
		stopAnimation(controller._visualCurrentAnimationTrack)
		controller._visualCurrentAnimationTrack = nil
		controller._visualCurrentAnimationName = nil
	end

	return nil
end

-- Starts visual subsystem for this monster.
function MonsterVisual.Start(controller)
	if controller._visualRunning then
		return
	end

	controller._visualRunning = true
end

-- Stops visuals and active animation track.
function MonsterVisual.Stop(controller)
	controller._visualRunning = false

	if controller._visualCurrentAnimationTrack then
		stopAnimation(controller._visualCurrentAnimationTrack)
		controller._visualCurrentAnimationTrack = nil
		controller._visualCurrentAnimationName = nil
	end
end

return MonsterVisual
