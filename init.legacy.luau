local CollectionService = game:GetService("CollectionService")
local MonsterAI = require(script:WaitForChild("MonsterAI"))

local function startMonster(instance: Instance)
	if not instance:IsA("Model") then
		return
	end

	local success, errorMessage = MonsterAI.StartController(instance)
	if not success then
		warn(("Failed to start MonsterAI for '%s': %s"):format(instance:GetFullName(), tostring(errorMessage)))
	end
end

for _, instance in CollectionService:GetTagged("Monster") do
	startMonster(instance)
end

CollectionService:GetInstanceAddedSignal("Monster"):Connect(startMonster)
