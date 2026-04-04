local MonsterMain = require(script:WaitForChild("MonsterMain"))

local monster = workspace:WaitForChild("Monster")
if not monster:IsA("Model") then
	return
end

MonsterMain.StartController(monster :: Model, true)