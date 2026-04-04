local Debris = game:GetService("Debris")

local Utility = {}

local DEFAULT_SOUND_CLEANUP = 5

-- Clones and plays a sound so the original sound instance can be reused safely.
function Utility.PlaySound(soundTemplate: Sound, parent: Instance, cleanUpTime: number?): Sound?
	if not soundTemplate or not parent then
		return nil
	end

	local soundClone = soundTemplate:Clone()
	soundClone.Parent = parent
	soundClone:Play()

	Debris:AddItem(soundClone, cleanUpTime or DEFAULT_SOUND_CLEANUP)
	return soundClone
end

-- Loads and plays an animation on a model's humanoid.
function Utility.PlayAnimation(animationTemplate: Animation, model: Model): AnimationTrack?
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

	-- Remove temporary animation objects once playback stops.
	animationTrack.Stopped:Connect(function()
		if animationClone.Parent then
			animationClone:Destroy()
		end
	end)

	return animationTrack
end

function Utility.StopAnimation(animationTrack: AnimationTrack?)
	if animationTrack then
		animationTrack:Stop()
	end
end

return Utility
