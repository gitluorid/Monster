local Debris = game:GetService("Debris")

local MonsterAudio = {}

local DEFAULT_SOUND_CLEANUP = 5
local WANDER_EXCLUDED_SOUNDS = {
	Attack = true,
	HeadBlow = true,
	StartChaseSound = true,
	WanderFootstep = true,
}

function MonsterAudio.PlaySound(soundTemplate: Sound, parent: Instance, cleanUpTime: number?): Sound?
	if not soundTemplate or not parent then
		return nil
	end

	local soundClone = soundTemplate:Clone()
	soundClone.Parent = parent
	soundClone:Play()

	Debris:AddItem(soundClone, cleanUpTime or DEFAULT_SOUND_CLEANUP)
	return soundClone
end

function MonsterAudio.FindSound(controller, soundName: string): Sound?
	local soundsFolder = controller.SoundsFolder
	if not soundsFolder then
		return nil
	end

	local directMatch = soundsFolder:FindFirstChild(soundName)
	if directMatch and directMatch:IsA("Sound") then
		return directMatch
	end

	local nestedMatch = soundsFolder:FindFirstChild(soundName, true)
	if nestedMatch and nestedMatch:IsA("Sound") then
		return nestedMatch
	end

	return nil
end

function MonsterAudio.SetFootstepInterval(controller, interval: number)
	controller._audioFootstepInterval = interval
end

-- Attempts to play one footstep sound.
-- Returns true when a footstep was played.
function MonsterAudio.TryPlayFootstep(controller): boolean
	if not controller._audioRunning or not controller.Monster.Parent or controller.Humanoid.Health <= 0 then
		return false
	end

	local now = os.clock()
	if now - controller._audioLastFootstepAt < controller._audioFootstepInterval then
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

	local footstepSound = MonsterAudio.FindSound(controller, "WanderFootstep")
	local soundParent = controller.Monster.PrimaryPart
		or controller.Monster:FindFirstChild("HumanoidRootPart")
		or controller.Monster:FindFirstChildWhichIsA("BasePart")

	if not footstepSound or not footstepSound:IsA("Sound") then
		return false
	end

	if not soundParent then
		return false
	end

	MonsterAudio.PlaySound(footstepSound, soundParent, 1)
	controller._audioLastFootstepAt = now
	return true
end

local function getWanderAmbientSounds(controller): { Sound }
	local soundsFolder = controller.SoundsFolder
	if not soundsFolder then
		return {}
	end

	local preferredAmbientFolder = soundsFolder:FindFirstChild("Wander") or soundsFolder:FindFirstChild("Ambient")
	local sourceList = preferredAmbientFolder and preferredAmbientFolder:GetDescendants()
		or soundsFolder:GetDescendants()

	local ambientSounds: { Sound } = {}
	for _, candidate in sourceList do
		if candidate:IsA("Sound") then
			if candidate:GetAttribute("Ambient") == false then
				continue
			end

			if preferredAmbientFolder or not WANDER_EXCLUDED_SOUNDS[candidate.Name] then
				table.insert(ambientSounds, candidate)
			end
		end
	end

	return ambientSounds
end

-- Optional ambient wander sounds loop.
local function startWanderSoundLoop(controller)
	if not controller.SoundsFolder then
		return
	end

	task.spawn(function()
		while controller._audioRunning and controller.Monster.Parent and controller.Humanoid.Health > 0 do
			local availableSounds = getWanderAmbientSounds(controller)
			if #availableSounds > 0 then
				local randomSound = availableSounds[math.random(1, #availableSounds)]
				if randomSound:IsA("Sound") then
					MonsterAudio.PlaySound(randomSound, controller.Monster)
					task.wait(randomSound.TimeLength + 0.1)
				end
			end

			task.wait(math.random(20, 90))
		end
	end)
end

function MonsterAudio.Start(controller, enableWanderSounds: boolean)
	if controller._audioRunning then
		return
	end

	controller._audioRunning = true

	if enableWanderSounds then
		startWanderSoundLoop(controller)
	end
end

function MonsterAudio.Stop(controller)
	controller._audioRunning = false
end

return MonsterAudio
