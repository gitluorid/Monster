--[[
	MonsterConfig
	-------------
	All gameplay tuning values live in this file.
	If someone is new to the codebase, this is the first file to edit.
]]

local Config = {
	-- Core combat behavior and attack pacing.
	Combat = {
		-- Maximum distance where a target can be detected for chase.
		DETECTION_RANGE = 200,
		-- Distance threshold to trigger melee attack behavior.
		MELEE_RANGE = 15,
		-- Minimum seconds between consecutive attacks.
		ATTACK_COOLDOWN = 1.2,
		-- Delay from attack start to when damage is applied.
		SWING_HIT_DELAY = 0.7,
		-- Retry delay while waiting for attack cooldown.
		COOLDOWN_RETRY_TIME = 0.05,
		-- Recovery delay after an attack finishes.
		POST_ATTACK_RECOVERY_TIME = 0.05,
		-- Horizontal knockback force applied on hit.
		KNOCKBACK_FORCE = 100,
		-- BodyVelocity power and max-force strength for knockback.
		KNOCKBACK_POWER = 10000,
		-- Seconds knockback BodyVelocity remains active.
		KNOCKBACK_DURATION = 0.2,
	},

	-- Raw walk speeds for each locomotion mode.
	MovementSpeeds = {
		-- WalkSpeed while roaming without a target.
		WANDER = 18,
		-- WalkSpeed while actively chasing a target.
		CHASE = 26,
	},

	-- Idle pacing around wander actions.
	Idle = {
		-- Minimum random idle duration in seconds.
		MIN_DURATION = 0.25,
		-- Maximum random idle duration in seconds.
		MAX_DURATION = 5,
		-- Loop tick interval while waiting in idle state.
		TICK_INTERVAL = 0.05,
	},

	-- Wander target selection, move thresholds, and retry pacing.
	Wander = {
		-- Radius around monster used for random wander goals.
		RADIUS = 150,
		-- Minimum distance required for a random wander goal.
		MIN_GOAL_DISTANCE = 35,
		-- Number of random attempts before using fallback goal.
		GOAL_ATTEMPTS = 10,
		-- Max seconds allowed for one wander step attempt.
		MAX_STEP_DURATION = 3.5,
		-- Delay before retrying wander after path failure.
		PATH_FAIL_RETRY_DELAY = 0.2,
		-- Minimum distance from start before accepting a wander waypoint.
		MIN_WAYPOINT_DISTANCE = 100,
		-- Close-enough distance to consider wander MoveTo complete.
		REACHED_DISTANCE = 5,
		-- Maximum seconds to wait for one wander MoveTo step.
		STEP_TIMEOUT = 20,
	},

	-- Chase movement tuning for path-following responsiveness.
	Chase = {
		-- Minimum distance to consider a waypoint meaningfully ahead.
		MIN_WAYPOINT_DISTANCE = 15,
		-- Close-enough distance to consider chase MoveTo complete.
		REACHED_DISTANCE = 2,
		-- Maximum seconds to wait for one chase MoveTo step.
		STEP_TIMEOUT = 0.15,
	},

	-- Pathfinding agent settings.
	Path = {
		-- Pathfinding agent capsule radius.
		AgentRadius = 4,
		-- Pathfinding agent capsule height.
		AgentHeight = 8,
		-- Whether pathfinding can generate jump links.
		AgentCanJump = false,
		-- Whether pathfinding can generate climb links.
		AgentCanClimb = true,
	},

	Audio = {
		Footsteps = {
			-- Minimum delay between wander footsteps.
			WANDER_INTERVAL = 0.8,
			-- Minimum delay between chase footsteps.
			CHASE_INTERVAL = 0.3,
			-- Required movement magnitude before footsteps can play.
			MOVE_THRESHOLD = 0.05,
			-- Lifetime for cloned footstep sounds.
			SOUND_CLEANUP_TIME = 1,
		},

		-- Delay range between ambient wander sounds when enabled.
		Ambient = {
			-- Minimum ambient sound delay.
			MIN_DELAY = 20,
			-- Maximum ambient sound delay.
			MAX_DELAY = 90,
		},
	},

	Visual = {
		-- Number of procedural blood parts spawned per hit effect.
		BLOOD_PART_AMOUNT = 60,
		-- Lifetime in seconds for blood effect parts.
		EFFECT_LIFETIME = 100,
	},

	Loop = {
		-- Main AI loop sleep interval.
		MAIN_TICK_INTERVAL = 0.1,
	},
}

return Config
