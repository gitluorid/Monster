local MonsterStateMachine = {}

-- These are all behavior states used by the monster.
MonsterStateMachine.States = {
	Idle = "Idle",
	Wander = "Wander",
	Chase = "Chase",
	Attack = "Attack",
}

-- Creates a tiny state machine object with 3 methods:
-- GetState, SetState, TimeInState.
function MonsterStateMachine.new(initialState: string?)
	local stateMachine = {
		_state = initialState or MonsterStateMachine.States.Idle,
		_changedAt = os.clock(),
	}

	-- Returns current state as a string.
	function stateMachine.GetState(machine): string
		return machine._state
	end

	-- Changes state. Returns true when state changed, false when unchanged.
	function stateMachine.SetState(machine, nextState: string): boolean
		if machine._state == nextState then
			return false
		end

		machine._state = nextState
		machine._changedAt = os.clock()

		return true
	end

	-- Returns how long the state has been active, in seconds.
	function stateMachine.TimeInState(machine): number
		return os.clock() - machine._changedAt
	end

	return stateMachine
end

return MonsterStateMachine
