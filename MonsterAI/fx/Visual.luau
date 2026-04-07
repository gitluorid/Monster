local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local MonsterVisual = {}
local fxFolder = script.Parent
if not fxFolder then
	error("MonsterVisual must be parented under fx")
end
local animationsFolder = fxFolder:WaitForChild("Animations")
local DEFAULT_EFFECT_LIFETIME = 5
local DEFAULT_ANIMATION_FADE_IN = 0.12
local DEFAULT_ANIMATION_FADE_OUT = 0.16
local DEFAULT_RUN_MIN_MULTIPLIER = 0.45
local DEFAULT_RUN_MAX_MULTIPLIER = 1
local DEFAULT_WALK_MIN_MULTIPLIER = 0.65
local DEFAULT_WALK_MAX_MULTIPLIER = 1

local function sanitizeFadeTime(value: any, fallback: number): number
	if type(value) ~= "number" then
		return fallback
	end

	return math.max(0, value)
end

local function getAnimationTransitionTimes(controller): (number, number)
	local visualConfig = controller and controller.Config and controller.Config.Visual
	local transitionConfig = visualConfig and visualConfig.AnimationTransitions
	if not transitionConfig then
		return DEFAULT_ANIMATION_FADE_IN, DEFAULT_ANIMATION_FADE_OUT
	end

	local fadeInTime = sanitizeFadeTime(transitionConfig.FADE_IN_TIME, DEFAULT_ANIMATION_FADE_IN)
	local fadeOutTime = sanitizeFadeTime(transitionConfig.FADE_OUT_TIME, DEFAULT_ANIMATION_FADE_OUT)

	return fadeInTime, fadeOutTime
end

local function sanitizeSpeedMultiplier(value: any, fallback: number): number
	if type(value) ~= "number" then
		return fallback
	end

	return math.max(0.05, value)
end

local function getAnimationSpeedMapping(controller, animationName: string): (boolean, number, number, number)
	local movementSpeeds = controller and controller.Config and controller.Config.MovementSpeeds
	if not movementSpeeds then
		return false, 0, 0, 1
	end

	local visualConfig = controller and controller.Config and controller.Config.Visual
	local speedConfig = visualConfig and visualConfig.AnimationSpeed

	if animationName == "Run" then
		local minMultiplier =
			sanitizeSpeedMultiplier(speedConfig and speedConfig.RUN_MIN_MULTIPLIER, DEFAULT_RUN_MIN_MULTIPLIER)
		local maxMultiplier =
			sanitizeSpeedMultiplier(speedConfig and speedConfig.RUN_MAX_MULTIPLIER, DEFAULT_RUN_MAX_MULTIPLIER)
		if maxMultiplier < minMultiplier then
			minMultiplier, maxMultiplier = maxMultiplier, minMultiplier
		end

		return true, minMultiplier, maxMultiplier, math.max(0.01, movementSpeeds.CHASE or 0)
	end

	if animationName == "Walk" then
		local minMultiplier =
			sanitizeSpeedMultiplier(speedConfig and speedConfig.WALK_MIN_MULTIPLIER, DEFAULT_WALK_MIN_MULTIPLIER)
		local maxMultiplier =
			sanitizeSpeedMultiplier(speedConfig and speedConfig.WALK_MAX_MULTIPLIER, DEFAULT_WALK_MAX_MULTIPLIER)
		if maxMultiplier < minMultiplier then
			minMultiplier, maxMultiplier = maxMultiplier, minMultiplier
		end

		return true, minMultiplier, maxMultiplier, math.max(0.01, movementSpeeds.WANDER or 0)
	end

	return false, 0, 0, 1
end

local function _playAnimation(animationTemplate: Animation, model: Model, fadeInTime: number?): AnimationTrack?
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
	animationTrack:Play(math.max(0, fadeInTime or 0))

	animationTrack.Stopped:Connect(function()
		if animationClone.Parent then
			animationClone:Destroy()
		end
	end)

	return animationTrack
end

local function stopAnimation(animationTrack: AnimationTrack?, fadeOutTime: number?)
	if animationTrack then
		animationTrack:Stop(math.max(0, fadeOutTime or 0))
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
			part.CanCollide = false
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

-- Plays the attack hit visual presentation when a swing lands.
function MonsterVisual.PlayAttackHitPresentation(controller, attackedModel: Model?, attackedRoot: BasePart?)
	if not attackedModel or not attackedRoot then
		return
	end

	MonsterVisual.PlayKillBloodEffect(
		controller,
		attackedModel,
		attackedRoot,
		controller.Config.Visual.BLOOD_PART_AMOUNT
	)
end

-- Plays an animation by name and ensures only one animation track is active at a time.
function MonsterVisual.PlayUniqueAnimation(controller, animationName: string): AnimationTrack?
	local animation = animationsFolder:FindFirstChild(animationName)
	if not animation or not animation:IsA("Animation") then
		return nil
	end

	local fadeInTime, fadeOutTime = getAnimationTransitionTimes(controller)

	if
		controller._visualCurrentAnimationTrack
		and controller._visualCurrentAnimationTrack.IsPlaying
		and controller._visualCurrentAnimationName == animation.Name
	then
		return controller._visualCurrentAnimationTrack
	end

	if controller._visualCurrentAnimationTrack then
		stopAnimation(controller._visualCurrentAnimationTrack, fadeOutTime)
		controller._visualCurrentAnimationTrack = nil
		controller._visualCurrentAnimationName = nil
	end

	controller._visualCurrentAnimationTrack = _playAnimation(animation, controller.Monster, fadeInTime)
	controller._visualCurrentAnimationName = animation.Name
	MonsterVisual.UpdateMovementAnimationSpeed(controller)

	return controller._visualCurrentAnimationTrack
end

-- Adjusts locomotion animation playback speed so visual pace matches current WalkSpeed ramping.
function MonsterVisual.UpdateMovementAnimationSpeed(controller)
	local currentTrack = controller._visualCurrentAnimationTrack
	if not currentTrack or not currentTrack.IsPlaying then
		return
	end

	local currentName = controller._visualCurrentAnimationName
	if not currentName then
		return
	end

	local hasMapping, minMultiplier, maxMultiplier, referenceWalkSpeed =
		getAnimationSpeedMapping(controller, currentName)
	if not hasMapping then
		return
	end
	local currentWalkSpeed = 0
	if controller.Humanoid then
		currentWalkSpeed = math.max(0, controller.Humanoid.WalkSpeed)
	end

	local alpha = math.clamp(currentWalkSpeed / referenceWalkSpeed, 0, 1)
	local playbackSpeed = minMultiplier + ((maxMultiplier - minMultiplier) * alpha)
	currentTrack:AdjustSpeed(playbackSpeed)
end

-- Tries to play idle animation.
-- If no Idle animation exists, it stops the currently playing movement animation.
function MonsterVisual.PlayIdleAnimation(controller): AnimationTrack?
	local idleTrack = MonsterVisual.PlayUniqueAnimation(controller, "Idle")
	if idleTrack then
		return idleTrack
	end

	local _, fadeOutTime = getAnimationTransitionTimes(controller)

	-- If there is no idle animation asset, stop motion animation so the monster visually idles.
	if controller._visualCurrentAnimationTrack then
		stopAnimation(controller._visualCurrentAnimationTrack, fadeOutTime)
		controller._visualCurrentAnimationTrack = nil
		controller._visualCurrentAnimationName = nil
	end

	return nil
end

-- Waits a short duration near the tail of the attack animation before handoff.
function MonsterVisual.WaitForAttackAnimationHandoff(controller, attackTrack: AnimationTrack?)
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
	local _, fadeOutTime = getAnimationTransitionTimes(controller)

	if controller._visualCurrentAnimationTrack then
		stopAnimation(controller._visualCurrentAnimationTrack, fadeOutTime)
		controller._visualCurrentAnimationTrack = nil
		controller._visualCurrentAnimationName = nil
	end
end

return MonsterVisual
