--[[
	MonsterConfig
	-------------
	All gameplay tuning values live in this file.
	If someone is new to the codebase, this is the first file to edit.
]]

local Config = {
	-- Core combat behavior and attack pacing.
	Combat = {
		DETECTION_RANGE = 200,
		MELEE_RANGE = 15,
		ATTACK_COOLDOWN = 1.2,
		SWING_HIT_DELAY = 1.1,
		COOLDOWN_RETRY_TIME = 0.05,
		POST_ATTACK_RECOVERY_TIME = 0.05,
		KNOCKBACK_FORCE = 100,
		KNOCKBACK_POWER = 10000,
		KNOCKBACK_DURATION = 0.2,
	},

	-- Raw walk speeds for each locomotion mode.
	MovementSpeeds = {
		WANDER = 12,
		CHASE = 34,
	},

	-- Idle pacing around wander actions.
	Idle = {
		BEFORE_WANDER_TIME = 0.5,
		AFTER_WANDER_TIME = 0.3,
		TICK_INTERVAL = 0.05,
	},

	-- Random wander target selection and failure behavior.
	Wander = {
		RADIUS = 150,
		MIN_GOAL_DISTANCE = 150,
		GOAL_ATTEMPTS = 10,
		MAX_STEP_DURATION = 3.5,
		PATH_FAIL_IDLE_TIME = 1,
		PATH_FAIL_RETRY_DELAY = 0.2,
	},

	-- Pathfinding and MoveTo thresholds.
	Path = {
		-- Chasing uses this to skip tiny waypoints.
		CHASE_MIN_WAYPOINT_DISTANCE = 20,

		-- Chasing must get close to each step target to avoid stutter.
		CHASE_REACHED_DISTANCE = 2,

		-- Maximum time for one chase MoveTo step before repathing.
		-- Lower values increase responsiveness to moving targets.
		CHASE_STEP_TIMEOUT = 0.15,

		-- Wander-only waypoint filtering and completion thresholds.
		WANDER_MIN_WAYPOINT_DISTANCE = 100,
		WANDER_REACHED_DISTANCE = 5,
		WANDER_STEP_TIMEOUT = 3,

		SETTINGS = {
			AgentRadius = 4,
			AgentHeight = 8,
			AgentCanJump = false,
			AgentCanClimb = true,
		},
	},

	Audio = {
		Footsteps = {
			WANDER_INTERVAL = 0.8,
			CHASE_INTERVAL = 0.3,
			MOVE_THRESHOLD = 0.05,
			SOUND_CLEANUP_TIME = 1,
		},

		-- Delay range between ambient wander sounds when enabled.
		Ambient = {
			MIN_DELAY = 20,
			MAX_DELAY = 90,
		},
	},

	Visual = {
		BLOOD_PART_AMOUNT = 60,
		EFFECT_LIFETIME = 5,
	},

	Loop = {
		MAIN_TICK_INTERVAL = 0.1,
	},
}

return Config
