local MonsterAI = require(script:WaitForChild("MonsterAI"))

local monster = workspace:WaitForChild("Monster")
if not monster:IsA("Model") then
	return
end

MonsterAI.StartController(monster :: Model, true)
