local Debris = game:GetService("Debris")

local MonsterAudio = {}
local fxFolder = script.Parent
if not fxFolder then
	error("MonsterAudio must be parented under fx")
end
local soundsFolder = fxFolder:WaitForChild("Sounds")

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

function MonsterAudio.FindSound(soundName: string): Sound?
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

function MonsterAudio.PlayNamed(controller, soundName: string, cleanUpTime: number?, soundParent: Instance?): Sound?
	local soundTemplate = MonsterAudio.FindSound(soundName)
	if not soundTemplate then
		return nil
	end

	local parent = soundParent or controller.RootPart
	if not parent then
		return nil
	end

	return MonsterAudio.PlaySound(soundTemplate, parent, cleanUpTime)
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
	local footstepConfig = controller.Config.Audio.Footsteps

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

	if moveMagnitude <= footstepConfig.MOVE_THRESHOLD and horizontalSpeed <= footstepConfig.MOVE_THRESHOLD then
		return false
	end

	local footstepSound = MonsterAudio.FindSound("WanderFootstep")
	local soundParent = controller.Monster.PrimaryPart
		or controller.Monster:FindFirstChild("HumanoidRootPart")
		or controller.Monster:FindFirstChildWhichIsA("BasePart")

	if not footstepSound or not footstepSound:IsA("Sound") then
		return false
	end

	if not soundParent then
		return false
	end

	MonsterAudio.PlaySound(footstepSound, soundParent, footstepConfig.SOUND_CLEANUP_TIME)
	controller._audioLastFootstepAt = now
	return true
end

local function getWanderAmbientSounds(): { Sound }
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

-- Ambient wander sounds loop.
local function startWanderSoundLoop(controller)
	local ambientConfig = controller.Config.Audio.Ambient
	local minDelay = math.max(0, ambientConfig.MIN_DELAY)
	local maxDelay = math.max(minDelay, ambientConfig.MAX_DELAY)

	task.spawn(function()
		while controller._audioRunning and controller.Monster.Parent and controller.Humanoid.Health > 0 do
			local availableSounds = getWanderAmbientSounds()
			if #availableSounds > 0 then
				local randomSound = availableSounds[math.random(1, #availableSounds)]
				if randomSound:IsA("Sound") then
					MonsterAudio.PlaySound(randomSound, controller.Monster)
					task.wait(randomSound.TimeLength + 0.1)
				end
			end

			local delay = minDelay + (math.random() * (maxDelay - minDelay))
			task.wait(delay)
		end
	end)
end

function MonsterAudio.Start(controller)
	if controller._audioRunning then
		return
	end

	controller._audioRunning = true
	-- startWanderSoundLoop(controller)  -- Commented out to stop ambient whistling
end

function MonsterAudio.Stop(controller)
	controller._audioRunning = false
end

return MonsterAudio
