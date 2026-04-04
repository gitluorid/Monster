local Debris = game:GetService("Debris")

local Utility = {}

local DEFAULT_SOUND_CLEANUP = 5
local DEFAULT_HITBOX_LIFETIME = 0.3

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

-- Creates a short-lived damage volume and prevents duplicate hits per character.
function Utility.CreateHitbox(parent: Model, size: Vector3, cframe: CFrame, damage: number): BasePart
	local hitbox = Instance.new("Part")
	hitbox.Size = size
	hitbox.Transparency = 0.5
	hitbox.CanCollide = false
	hitbox.Anchored = true
	hitbox.Material = Enum.Material.ForceField
	hitbox.Color = Color3.new(1, 0, 0)
	hitbox.CastShadow = false
	hitbox.CanTouch = true
	hitbox.CanQuery = false
	hitbox.Massless = true
	hitbox.Name = parent.Name .. "Hitbox"
	hitbox.CFrame = cframe
	hitbox.Parent = parent

	Debris:AddItem(hitbox, DEFAULT_HITBOX_LIFETIME)

	local damagedModels: {[Model]: boolean} = {}
	hitbox.Touched:Connect(function(hit: BasePart)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character or character == parent or damagedModels[character] then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		damagedModels[character] = true
		humanoid:TakeDamage(damage)
	end)

	return hitbox
end

return Utility
