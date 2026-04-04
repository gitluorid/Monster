local Monster = {}

-- This module is the entry point for the AI package.
-- It only creates the controller and starts it.
local controllerModule = script:WaitForChild("MonsterController") :: ModuleScript
local MonsterController = require(controllerModule)

-- Creates and starts one controller instance.
-- Returns (success, errorMessage).
function Monster.StartController(monster: Model, enableWanderSounds: boolean?): (boolean, string?)
	-- Build one controller for this monster model.
	local controller, errorMessage = MonsterController.new(monster)
	if not controller then
		return false, tostring(errorMessage)
	end

	-- Start the AI loop. Passing false keeps ambient wander sounds disabled.
	local shouldEnableWanderSounds = enableWanderSounds == true
	controller:Start(shouldEnableWanderSounds)

	return true, nil
end

return Monster