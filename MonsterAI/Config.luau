--[[
	MonsterConfig
	-------------
	All gameplay tuning values live in this file.
	If someone is new to the codebase, this is the first file to edit.
]]

local Config = {
	-- =============================
	-- Combat / Targeting
	-- =============================
	ATTACK_DETECTION_RANGE = 200,
	MELEE_RANGE = 15,
	ATTACK_COOLDOWN = 1.2,

	-- =============================
	-- Movement Speeds
	-- =============================
	WANDER_WALK_SPEED = 12,
	CHASE_WALK_SPEED = 34,

	-- =============================
	-- Wander Behavior
	-- =============================
	-- Random goal is picked inside this radius around the monster.
	WANDER_RADIUS = 150,

	-- Goal must be at least this far from current position.
	WANDER_MIN_DISTANCE = 150,

	-- Selected waypoint on the path must be at least this far from start.
	WANDER_MIN_WAYPOINT_DISTANCE = 100,

	-- How many times we try to pick a random goal before using fallback.
	WANDER_GOAL_ATTEMPTS = 10,

	-- Hard limit for one wander action.
	WANDER_MAX_DURATION = 3.5,

	-- How long MoveTo can take when walking to the selected wander waypoint.
	WANDER_WAYPOINT_TIMEOUT = 3,

	-- Idle duration if no valid wander path/waypoint is found.
	WANDER_PATH_FAIL_IDLE_TIME = 1,

	-- =============================
	-- Idle Behavior
	-- =============================
	IDLE_BEFORE_WANDER_TIME = 0.5,
	IDLE_AFTER_WANDER_TIME = 0.3,
	IDLE_TICK_INTERVAL = 0.05,

	-- =============================
	-- Path Following Distances
	-- =============================
	-- Chasing uses this to skip tiny waypoints.
	WAYPOINT_MIN_DISTANCE = 20,

	-- Generic move reach threshold.
	WAYPOINT_REACHED_DISTANCE = 10,

	-- Chasing must get much closer to each move target to avoid micro-step slowdown.
	CHASE_WAYPOINT_REACHED_DISTANCE = 2,

	-- How long each chase MoveTo call can run before path refresh.
	CHASE_MOVE_TIMEOUT = 0.15,

	-- =============================
	-- Footsteps / Audio
	-- =============================
	WANDER_FOOTSTEP_INTERVAL = 0.8,
	CHASE_FOOTSTEP_INTERVAL = 0.3,
	FOOTSTEP_MOVE_THRESHOLD = 0.05,

	-- =============================
	-- Attack Presentation
	-- =============================
	-- Delay between starting swing animation and applying the kill hit.
	ATTACK_SWING_HIT_DELAY = 1.1,
	BLOOD_PART_AMOUNT = 60,

	-- =============================
	-- Pathfinding Settings
	-- =============================
	PATH_SETTINGS = {
		AgentRadius = 4,
		AgentHeight = 8,
		AgentCanJump = false,
		AgentCanClimb = true,
	},
}

return Config
