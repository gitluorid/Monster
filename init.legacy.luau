local MonsterAI = require(script:WaitForChild("MonsterAI"))

local monster = workspace:WaitForChild("Monster")
if not monster:IsA("Model") then
	warn("Monster is not a Model")
	return
end

MonsterAI.StartController(monster :: Model)
task.wait(2)
MonsterAI.StopController(monster)
