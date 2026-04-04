local Debris = game:GetService("Debris")

local MonsterVFX = {}

local DEFAULT_SOUND_CLEANUP = 5

function MonsterVFX.PlaySound(soundTemplate: Sound, parent: Instance, cleanUpTime: number?): Sound?
	if not soundTemplate or not parent then
		return nil
	end

	local soundClone = soundTemplate:Clone()
	soundClone.Parent = parent
	soundClone:Play()

	Debris:AddItem(soundClone, cleanUpTime or DEFAULT_SOUND_CLEANUP)
	return soundClone
end

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

-- Updates how often footsteps are allowed to play.
function MonsterVFX.SetFootstepInterval(controller, interval: number)
	controller._vfxFootstepInterval = interval
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

-- Attempts to play one footstep sound.
-- Returns true when a footstep was played.
function MonsterVFX.TryPlayFootstep(controller, reason: string?): boolean
	if not controller._vfxRunning or not controller.Monster.Parent or controller.Humanoid.Health <= 0 then
		return false
	end

	local now = os.clock()
	if now - controller._vfxLastFootstepAt < controller._vfxFootstepInterval then
		return false
	end

	local moveMagnitude = controller.Humanoid.MoveDirection.Magnitude
	local rootPart = controller.Monster:FindFirstChild("HumanoidRootPart")
	local horizontalSpeed = 0
	if rootPart and rootPart:IsA("BasePart") then
		horizontalSpeed = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
	end

	if
		moveMagnitude <= controller.Config.FOOTSTEP_MOVE_THRESHOLD
		and horizontalSpeed <= controller.Config.FOOTSTEP_MOVE_THRESHOLD
	then
		return false
	end

	local footstepSound = controller.OtherSoundsFolder:FindFirstChild("WanderFootstep")
	local soundParent = controller.Monster.PrimaryPart
		or controller.Monster:FindFirstChild("HumanoidRootPart")
		or controller.Monster:FindFirstChildWhichIsA("BasePart")

	if not footstepSound or not footstepSound:IsA("Sound") then
		return false
	end

	if not soundParent then
		return false
	end

	MonsterVFX.PlaySound(footstepSound, soundParent, 1)
	controller._vfxLastFootstepAt = now
	return true
end

-- Optional ambient wander sounds loop.
local function startWanderSoundLoop(controller)
	if not controller.WanderSoundsFolder then
		return
	end

	task.spawn(function()
		while controller._vfxRunning and controller.Monster.Parent and controller.Humanoid.Health > 0 do
			local availableSounds = controller.WanderSoundsFolder:GetChildren()
			if #availableSounds > 0 then
				local randomSound = availableSounds[math.random(1, #availableSounds)]
				if randomSound:IsA("Sound") then
					MonsterVFX.PlaySound(randomSound, controller.Monster)
					task.wait(randomSound.TimeLength + 0.1)
				end
			end

			task.wait(math.random(20, 90))
		end
	end)
end

-- Starts VFX subsystem for this monster.
function MonsterVFX.Start(controller, enableWanderSounds: boolean)
	if controller._vfxRunning then
		return
	end

	controller._vfxRunning = true

	if enableWanderSounds then
		startWanderSoundLoop(controller)
	end
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
