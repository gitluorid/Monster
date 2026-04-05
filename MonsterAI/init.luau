local Monster = {}

-- This module is the entry point for starting/stopping monster AI.
local MonsterController = require(script:WaitForChild("Controller") :: ModuleScript)
local activeControllers: { [Model]: any } = {}

local function clearControllerIfCurrent(monster: Model, controller: any)
	if activeControllers[monster] == controller then
		activeControllers[monster] = nil
	end
end

-- Creates and starts one controller instance.
-- Returns (success, errorMessage).
function Monster.StartController(monster: Model): (boolean, string?)
	if activeControllers[monster] then
		return false, "Controller is already running for this monster"
	end

	-- Build one controller for this monster model.
	local controller, errorMessage = MonsterController.new(monster)
	if not controller then
		return false, tostring(errorMessage)
	end

	activeControllers[monster] = controller

	-- Start the AI loop.
	task.spawn(function()
		controller:Start()
		clearControllerIfCurrent(monster, controller)
	end)

	return true, nil
end

-- Stops one running controller instance by monster model.
-- Returns (success, errorMessage).
function Monster.StopController(monster: Model): (boolean, string?)
	local controller = activeControllers[monster]
	if not controller then
		return false, "Controller is not running for this monster"
	end

	controller:Stop()
	clearControllerIfCurrent(monster, controller)

	return true, nil
end

return Monster
