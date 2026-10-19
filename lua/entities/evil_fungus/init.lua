AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")
include("evil_fungus/sv_mat.lua")
include("sv_feel.lua")
include("sv_debug.lua")

local Mat = EvilFungus.Mat
local EMPTY = Mat.EMPTY

local CAP = 4
local FLOW = 160
local SPREAD = 0.8
local SPREAD_MASS = 0.2
local GROW_MASS = 1
local GROW_COST = 0.1
local MIN_BODY = 8
local REACH_RATE = 2.5
local SPREAD_RATE = 3
local REACH_JITTER = 0.7
local SEED_RING = 8
local DECIDE_INTERVAL = 0.25
local COST_WINDOW = 1
local WANDER_TIME = { 8, 16 }
local WANDER_RANGE = 700
local WANDER_TRIES = 6
local PATROL_CHANCE = 0.3
local PATROL_NODES = 40
local ARRIVE = 32
local REST_TIME = { 2, 5 }
local LOSE_TIME = 8
local NEAR_GOAL = 96
local LEAD_TIME = 1.5
local HEADING_TIME = 0.6
local LEAD_LIFT = Vector(0, 0, 16)
local RISE_JITTER = 0.3
local TUNNEL_HOLD = 2
local AIR_HOLD = 10
local AIR_DROP = 2
local WEAVE_RATE = 6
local WEAVE_RADIUS = 64
local WEAVE_SPACING = 7
local WEAVE_MAX = 140
local DEBT_CAP = 3
local SPROUTS_PER_TICK = 48
local FLOW_SUBSTEPS = 4
local MIN_DECIDE = 0.08
local SPORE_BODY = 80
local SPORE_SHARE = 0.3
local SPORE_EVERY = 45
local SPORE_RANGE = 1200
local SPORE_CLEAR = 300
local SPORE_TRIES = 4
local MAX_COLONIES = 16
local FLEE = 4
local BURN_COST = 1e6
local HEAT_COST = 40
local BEHIND = 4
local BEHIND_MARGIN = 24
local DETOUR_FLAT = 48
local DETOUR_PROBES = 8
local DETOUR_RANGE = 384
local DETOUR_STEP = 48
local DETOUR_DROP = 16
local DETOUR_LEAN = 0.3
local DETOUR_HOLD = 6
local DETOUR_OFF = 64
local DETOUR_MOVED = 256

local ai_disabled = GetConVar("ai_disabled")

EvilFungus.Colonies = EvilFungus.Colonies or {}

-- However fast it's told to run, the whole map only lays so many strands a tick.
hook.Add("Tick", "EvilFungusSprouts", function()
	EvilFungus.SproutsLeft = SPROUTS_PER_TICK
end)

-- Every strand on the map, all fungus together, since it's all one fungus.
function EvilFungus.Strands()
	local n = 0
	for colony in pairs(EvilFungus.Colonies) do
		if colony.Mat then n = n + colony.Mat.count end
	end
	return n
end

-- Whoever spawned the fungus can clean up every patch it starts, not just the first.
local function Own(colony, ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	colony:SetCreator(ply)
	if cleanup then cleanup.Add(ply, "sents", colony) end
end

function ENT:SpawnFunction(ply, tr, class)
	if not tr.HitWorld or tr.HitSky then return end

	local ent = ents.Create(class)
	ent:SetPos(tr.HitPos + tr.HitNormal * 4)
	ent.SpawnAt = tr.HitPos
	ent.SpawnUp = tr.HitNormal
	ent:Spawn()
	ent:Activate()
	return ent
end

function ENT:Initialize()
	self:SetModel("models/props_junk/PopCan01a.mdl")
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_NONE)
	self:DrawShadow(false)

	local now = CurTime()
	self.Mind = self.Mind or EvilFungus.NewMind()
	local mat = EvilFungus.NewMat()
	self.Mat = mat

	local up = self.SpawnUp or vector_up
	local seed = mat:Add(self.SpawnAt or self:GetPos(), up)
	local ring = { seed }
	local ang = up:Angle()
	local right, side = ang:Right(), ang:Up()
	for i = 1, SEED_RING do
		local a = i / SEED_RING * math.pi * 2
		local node = mat:Grow(seed, right * math.cos(a) + side * math.sin(a), now)
		if node then ring[#ring + 1] = node end
	end
	local share = (self.StartMass or EvilFungus.Setting("start_mass")) / #ring
	for _, node in ipairs(ring) do mat:SetMass(node, share) end

	self.Center, self.Up, self.Body = seed.pos, up, share * #ring
	self.ReachDebt, self.SpreadDebt, self.WeaveDebt = 0, 0, 0
	self.NextDecide = 0
	self.TargetUntil = 0
	self.Claimed = {}
	self.Costs, self.CostReport, self.CostSince = {}, {}, now
	self:InitFeel()

	EvilFungus.Colonies[self] = true
	for _, node in ipairs(ring) do
		if self:Meet(node, now) then return end
	end
end

function ENT:Think()
	local now = CurTime()
	if self.Absorbed then return end
	if self.Mat.count <= 0 then
		self:Remove()
		return
	end
	if not (ai_disabled and ai_disabled:GetBool()) then
		local t = SysTime()
		local scale = EvilFungus.TimeScale()
		if now >= self.NextDecide then
			self:Decide(now)
			self.NextDecide = now + math.max(MIN_DECIDE, DECIDE_INTERVAL / scale)
			t = self:Cost("decide", t)
		end
		local dt = FrameTime() * scale
		local steps = math.Clamp(math.ceil(scale), 1, FLOW_SUBSTEPS)
		local rate = FLOW * EvilFungus.Setting("flow_speed")
		if self.Hunting then rate = rate * (0.5 + 0.5 * EvilFungus.Setting("aggression")) end
		for _ = 1, steps do self:Flow(dt / steps, now, rate) end
		t = self:Cost("flow", t)
		self:Spread(dt, now)
		if self.Absorbed then return end
		self:Spores(dt)
		t = self:Cost("grow", t)
		self:Feel(now)
		self:Cost("feel", t)
	else
		self:Slump(FrameTime() * EvilFungus.TimeScale())
	end
	self:Report(now)
	self:DebugDraw(now)
	self:NextThink(now)
	return true
end

function ENT:Cost(name, since)
	local t = SysTime()
	self.Costs[name] = (self.Costs[name] or 0) + t - since
	return t
end

-- Milliseconds of server time each part took over the last second.
function ENT:Report(now)
	local span = now - self.CostSince
	if span < COST_WINDOW then return end
	for name, cost in pairs(self.Costs) do
		self.CostReport[name] = cost * 1000 / span
		self.Costs[name] = 0
	end
	self.CostSince = now
end

function ENT:Settle()
	local cx, cy, cz, ux, uy, uz, body = 0, 0, 0, 0, 0, 0, 0
	for node in pairs(self.Mat.full) do
		local m, n = node.m, node.normal
		cx, cy, cz = cx + node.x * m, cy + node.y * m, cz + node.z * m
		local nx, ny, nz = n:Unpack()
		ux, uy, uz = ux + nx * m, uy + ny * m, uz + nz * m
		body = body + m
	end
	self.Body = body
	if body <= EMPTY then return end
	self.Center = Vector(cx / body, cy / body, cz / body)
	self.Up = Vector(ux, uy, uz):GetNormalized()
	self:SetPos(self.Center + self.Up * 4)
end

local function Behind(node, x, y, z)
	if node.air then return false end
	local nx, ny, nz = node.normal:Unpack()
	return (node.x - x) * nx + (node.y - y) * ny + (node.z - z) * nz > BEHIND_MARGIN
end

function ENT:Closest(pos, sided)
	local px, py, pz = pos:Unpack()
	local node = self.Mat:Nearest(pos, NEAR_GOAL, sided and function(n) return not Behind(n, px, py, pz) end or nil)
	if node then return node end
	local bestD2 = math.huge
	for _, n in pairs(self.Mat.nodes) do
		local dx, dy, dz = n.x - px, n.y - py, n.z - pz
		local d2 = dx * dx + dy * dy + dz * dz
		if sided and Behind(n, px, py, pz) then d2 = d2 * BEHIND end
		if d2 < bestD2 then node, bestD2 = n, d2 end
	end
	return node
end

local function Gap(lift, dir, drop)
	local tr = util.TraceLine({ start = lift, endpos = lift + dir * DETOUR_RANGE, mask = MASK_SOLID_BRUSHONLY })
	local wall = tr.Hit and not tr.HitSky and tr.Fraction * DETOUR_RANGE or math.huge
	for dist = DETOUR_STEP, math.min(wall, DETOUR_RANGE), DETOUR_STEP do
		local p = lift + dir * dist
		if not util.TraceLine({ start = p, endpos = p + drop, mask = MASK_SOLID_BRUSHONLY }).Hit then return dist end
	end
	return wall
end

local function Stuck(node, target)
	if node.air then return false end
	local to = target - node.pos
	local n = node.normal
	local off = to:Dot(n)
	return math.abs(off) > DETOUR_OFF and (to - n * off):Length() < DETOUR_FLAT
end

local function Detour(node, target)
	local n = node.normal
	local ang = n:Angle()
	local right, up = ang:Right(), ang:Up()
	local lift = node.pos + n * 4
	local drop = n * -DETOUR_DROP
	local to = target - node.pos
	local along = to - n * to:Dot(n)
	local toward = along:LengthSqr() > 1 and along:GetNormalized()
	local spin = math.random() * math.pi * 2
	local best, bestGap, bestScore
	for i = 1, DETOUR_PROBES do
		local a = spin + i / DETOUR_PROBES * math.pi * 2
		local dir = right * math.cos(a) + up * math.sin(a)
		local gap = Gap(lift, dir, drop)
		local score = gap
		if toward then score = score * (1 - DETOUR_LEAN * dir:Dot(toward)) end
		if not bestScore or score < bestScore then best, bestGap, bestScore = dir, gap, score end
	end
	return lift + best * math.min(bestGap, DETOUR_RANGE)
end

function ENT:Around(goal, now)
	local target = self.Target
	if not goal or not target or self.Hunting and (self.Tunnel or 0) > 0 then
		self.Waypoint = nil
		return goal
	end
	local way = self.Waypoint
	if way then
		local near = self.Mat:Nearest(way, ARRIVE * 2, function(n) return n ~= self.WaypointFrom end)
		if now > self.WaypointUntil or target:DistToSqr(self.WaypointFor) > DETOUR_MOVED * DETOUR_MOVED or near and not Stuck(near, target) then
			self.Waypoint, self.GoalStale = nil, true
			return self:Closest(target, true) or goal
		end
		if near then
			way, self.Waypoint, goal = nil, nil, near
		end
	end
	if not way and Stuck(goal, target) then
		way = Detour(goal, target)
		self.Waypoint, self.WaypointFrom, self.WaypointUntil, self.WaypointFor = way, goal, now + DETOUR_HOLD, target
	end
	if way then return self:Closest(way) or goal end
	return goal
end

local function RandomNode(set, accept)
	local pick, seen = nil, 0
	for key, value in pairs(set) do
		local node = value == true and key or value
		if not accept or accept(node) then
			seen = seen + 1
			if math.random(seen) == 1 then pick = node end
		end
	end
	return pick
end

function ENT:PickTarget(now)
	self.TargetUntil = now + math.Rand(WANDER_TIME[1], WANDER_TIME[2])
	self.Resting = false
	self.GoalStale = true

	if self.Mat.count > PATROL_NODES and math.random() < PATROL_CHANCE then
		self.Target = RandomNode(self.Mat.nodes, function(n) return not n.air end).pos
		return
	end

	local from = self.Center + self.Up * 16
	for _ = 1, WANDER_TRIES do
		local dir = VectorRand():GetNormalized()
		local tr = util.TraceLine({ start = from, endpos = from + dir * WANDER_RANGE, mask = MASK_SOLID_BRUSHONLY })
		if tr.Hit and not tr.HitSky and not tr.HitNoDraw and not tr.StartSolid and tr.Fraction > 0.15 then
			self.Target = tr.HitPos
			return
		end
	end
	self.Target = self.Center
end

-- Up off the ground, it only knows to go after you as well as it knows the trick you're using.
function ENT:Aloft(prey)
	local mind = self.Mind
	if prey:IsPlayer() and prey:GetMoveType() == MOVETYPE_NOCLIP then return mind:Knows("noclip") end
	if not EvilFungus.OnGround(prey) then return math.max(mind:Knows("jump"), mind:Knows("bhop")) end
	local ground = prey:GetGroundEntity()
	if IsValid(ground) and not ground:IsWorld() then return mind:Knows("high") end
	return 0
end

local function Tip(mat, node)
	for _, e in ipairs(node.edges) do
		local other = mat:Other(e, node)
		if other.air and other.height > node.height then return false end
	end
	return true
end

-- With nothing up there left to reach for, the strands in the air let go from the tips back and run down into the rest.
function ENT:Retract()
	local mat, dropped = self.Mat, 0
	for node in pairs(mat.air) do
		if Tip(mat, node) then
			local low
			for _, e in ipairs(node.edges) do
				local other = mat:Other(e, node)
				if not low or other.height < low.height then low = other end
			end
			if low then mat:SetMass(low, low.m + node.m) end
			mat:Remove(node)
			dropped = dropped + 1
			if dropped >= AIR_DROP then return end
		end
	end
end

function ENT:Decide(now)
	self:Settle()
	if next(self.Mat.air) and now - (self.TunnelAt or -math.huge) > AIR_HOLD then self:Retract() end

	local prey, node = self.Prey, self.PreyNode
	local memory = LOSE_TIME * math.max(0.25, EvilFungus.Setting("aggression")) / EvilFungus.TimeScale()
	local known = IsValid(prey) and (self:Touches(prey) or self.Smelled == prey)
	local still = IsValid(prey) and node and not node.dead and self:Perceivable(prey, known)
	self.Hunting = still and now - self.FeltAt < memory
	if still and not self.Hunting and prey:IsPlayer() then self.Mind:Watch(prey, "outrun", 1) end
	if not self.Hunting then
		self.Prey, self.PreyNode, self.PreyFrom, self.Eating = nil, nil, nil, nil
	end

	local aloft = self.Hunting and known and self:Aloft(prey) or 0
	if aloft > 0 then
		self.Tunnel, self.TunnelAt = aloft, now
	elseif not self.Hunting or now - (self.TunnelAt or -math.huge) > TUNNEL_HOLD then
		self.Tunnel = 0
	end

	local goal
	self.Tending = not self.Hunting and self:Patient() or nil
	if self.Hunting then
		self.Target = known and self:Lead(prey, now) or self.PreyFrom or node.pos
		goal = self:Closest(self.Target, true) or node
		self.PreyNode = goal
		goal = self:Around(goal, now)
	elseif self.Tending then
		goal = self.Tending.nest
		self.Target, self.Waypoint = goal.pos, nil
		self.GoalStale = true
	else
		local was = self.Carrion
		local body = self:Scavenge(now)
		if body then
			local pos = body:GetPos()
			if body ~= was or not self.Target or self.Target:DistToSqr(pos) > ARRIVE * ARRIVE then self.GoalStale = true end
			self.Target, self.Lure, self.Resting = pos, nil, false
			self.TargetUntil = now + WANDER_TIME[1]
		elseif self.Lure then
			self.Target, self.Lure, self.Resting, self.GoalStale = self.Lure, nil, false, true
			self.TargetUntil = now + math.Rand(WANDER_TIME[1], WANDER_TIME[2])
		end
		if not self.Target or now >= self.TargetUntil then self:PickTarget(now) end
		goal = self.Goal
		if self.GoalStale or not goal or goal.dead then
			goal = self:Closest(self.Target, true)
			self.GoalStale = false
		end
		goal = self:Around(goal, now)
		if not body and not self.Resting and goal.m > GROW_MASS and goal.pos:Distance(self.Target) < ARRIVE then
			self.Resting = true
			self.TargetUntil = math.min(self.TargetUntil, now + math.Rand(REST_TIME[1], REST_TIME[2]))
		end
	end
	self.Goal = goal

	-- Only the body needs to know the way, so the search ends once it has reached every part of it.
	local mat = self.Mat
	local left, reached = 0, {}
	for _ in pairs(mat.full) do left = left + 1 end
	self.Dist = mat:Distances({ [goal] = 0 }, function(e)
		if e.a.burn or e.b.burn then return BURN_COST end
		local heat = math.max(e.a.heat or 0, e.b.heat or 0)
		return e.len / mat:Conductance(e, now) * (1 + heat * HEAT_COST)
	end, nil,
		function(node)
			if not mat.full[node] or reached[node] then return false end
			reached[node] = true
			left = left - 1
			return left <= 0
		end)
end

-- The more it knows, the less it goes where you are and the more it goes where you're headed.
-- It reads that off how you've been moving, not off the last juke.
function ENT:Lead(prey, now)
	local pos = prey:GetPos()
	local vel = prey:GetVelocity()
	vel.z = 0
	if self.LeadOf ~= prey then
		self.LeadOf, self.Heading = prey, vel
	else
		self.Heading = LerpVector(1 - math.exp(-(now - self.LeadAt) / HEADING_TIME), self.Heading, vel)
	end
	self.LeadAt = now

	local ahead = LEAD_TIME * self.Mind:Grasp() / EvilFungus.TimeScale()
	if ahead <= 0 then return pos end
	local tr = util.TraceLine({ start = pos + LEAD_LIFT, endpos = pos + self.Heading * ahead + LEAD_LIFT, mask = MASK_SOLID_BRUSHONLY })
	return tr.HitPos - LEAD_LIFT
end

local flowList = {}
local Conductance, Thicken, SetMass = Mat.Conductance, Mat.Thicken, Mat.SetMass

function ENT:Flow(dt, now, rate)
	local dist, mat = self.Dist, self.Mat
	if not dist then return end

	local n = 0
	for node in pairs(mat.full) do
		n = n + 1
		flowList[n] = node
	end

	local spread = math.min(0.25, SPREAD * dt)
	for i = 1, n do
		local node = flowList[i]
		flowList[i] = nil
		local m = node.m
		local heat = node.burn and 2 or node.heat
		if m > EMPTY and not node.dead and heat then
			local edges, safe = node.edges, 0
			for j = 1, #edges do
				local other = edges[j].a == node and edges[j].b or edges[j].a
				if (other.burn and 2 or other.heat or 0) < heat then safe = safe + 1 end
			end
			if safe > 0 then
				local q = m * math.min(0.9, FLEE * dt) / safe
				for j = 1, #edges do
					local e = edges[j]
					local other = e.a == node and e.b or e.a
					if (other.burn and 2 or other.heat or 0) < heat then
						SetMass(mat, other, other.m + q)
						m = m - q
					end
				end
				SetMass(mat, node, m)
			end
		elseif m > EMPTY and not node.dead then
			local edges = node.edges
			local d, down, to = dist[node] or math.huge, nil, nil
			for j = 1, #edges do
				local e = edges[j]
				local other = e.a == node and e.b or e.a
				local od = dist[other]
				if od and od < d and other.m < CAP and not other.burn and not other.heat then d, down, to = od, e, other end
			end
			if down then
				local q = m * math.min(0.9, rate * Conductance(mat, down, now) / down.len * dt)
				m = m - q
				SetMass(mat, to, to.m + q)
				Thicken(mat, down, q, now)
			end
			if m > SPREAD_MASS then
				for j = 1, #edges do
					local e = edges[j]
					local other = e.a == node and e.b or e.a
					local om = other.m
					if om < m and not other.burn and not other.heat then
						local q = (m - om) * spread
						m = m - q
						SetMass(mat, other, om + q)
					end
				end
			end
			SetMass(mat, node, m)
		end
	end
end

function ENT:Slump(dt)
	local mat = self.Mat
	local n = 0
	for node in pairs(mat.full) do
		n = n + 1
		flowList[n] = node
	end
	local k = math.min(0.25, SPREAD * dt)
	for i = 1, n do
		local node = flowList[i]
		flowList[i] = nil
		local m = node.m
		if m > EMPTY and not node.dead then
			local edges = node.edges
			for j = 1, #edges do
				local e = edges[j]
				local other = e.a == node and e.b or e.a
				local om = other.m
				if om < m then
					local q = (m - om) * k
					m = m - q
					SetMass(mat, other, om + q)
				end
			end
			SetMass(mat, node, m)
		end
	end
end

local function Frontier(node)
	return node.m > GROW_MASS and not node.burn and not node.heat
end

-- The newest catch still within reach of rescue. The body goes and sits with it.
function ENT:Patient()
	local best
	for rag in pairs(self.Claimed) do
		local s = EvilFungus.Sleepers[rag]
		if s and s.nest and not s.nest.dead and (s.stage == EvilFungus.LOOSE or s.stage == EvilFungus.CONSUMING)
			and (not best or s.since > best.since) then
			best = s
		end
	end
	return best
end

function ENT:Sprout(from, dir, now, spacing, payer, rise)
	if from.burn or from.heat then return end
	payer = payer or from
	local cost = GROW_COST * EvilFungus.Setting("grow_cost")
	if payer.m < cost or (EvilFungus.SproutsLeft or 1) <= 0 then return end
	EvilFungus.SproutsLeft = (EvilFungus.SproutsLeft or 1) - 1
	local node
	if rise then node = self.Mat:Rise(from, dir, now) else node = self.Mat:Grow(from, dir, now, spacing) end
	if not node then return end
	if cost > 0 then self.Mat:SetMass(payer, payer.m - cost) end
	local goal, target = self.Goal, self.Waypoint or self.Target
	if not self.Hunting and goal and target and node.pos:DistToSqr(target) < goal.pos:DistToSqr(target) then
		self.Goal = node
	end
	self:Meet(node, now)
	return node
end

-- There is only one fungus. Two mats that touch recognise each other and carry on as one.
function ENT:Meet(node, now)
	local reach = Vector(Mat.FUSE, Mat.FUSE, Mat.FUSE)
	local pos = node.pos
	for other in pairs(EvilFungus.Colonies) do
		local mat = other ~= self and IsValid(other) and not other.Absorbed and other.Mat
		if mat and mat.mins and pos:WithinAABox(mat.mins - reach, mat.maxs + reach) then
			local theirs = mat:Nearest(pos, Mat.FUSE, function(n) return Mat.Facing(node, n) and Mat.Reaches(node, n) end)
			if theirs then return self:Fuse(other, node, theirs, now) end
		end
	end
	return false
end

function ENT:Fuse(other, mine, theirs, now)
	local keep, lose = self, other
	if other.Mat.count > self.Mat.count then keep, lose = other, self end

	if not IsValid(keep:GetCreator()) then Own(keep, lose:GetCreator()) end
	keep.Mat:Absorb(lose.Mat)
	EvilFungus.Converge(keep.Mind, lose.Mind)
	keep.Mat:Link(mine, theirs, now)
	keep:Adopt(lose)
	keep:Ripple(mine, now)
	keep.NextDecide = 0
	keep.GoalStale = true

	lose.Absorbed = true
	EvilFungus.Colonies[lose] = nil
	lose:Remove()
	return lose == self
end

function ENT:Spread(dt, now)
	local mat = self.Mat
	if self.Body < MIN_BODY then return end
	local speed = EvilFungus.Setting("grow_speed")
	local sprawl = EvilFungus.Setting("sprawl")
	local cap = math.min(SPROUTS_PER_TICK, DEBT_CAP * math.max(1, EvilFungus.TimeScale()))
	local reach = REACH_RATE * (self.Hunting and EvilFungus.Setting("aggression") or 1)
	self.ReachDebt = math.min(cap, self.ReachDebt + reach * speed * dt)
	self.SpreadDebt = math.min(cap, self.SpreadDebt + SPREAD_RATE * sprawl * speed * dt)
	if self.ReachDebt < 1 and self.SpreadDebt < 1 and not self.Tending then return end
	if EvilFungus.Strands() >= EvilFungus.Setting("max_nodes") then
		self.ReachDebt, self.SpreadDebt, self.WeaveDebt = 0, 0, 0
		return
	end

	-- New strands start empty, so the edge it grows from only changes once a strand's cost takes it under.
	-- Only what's on a surface wanders off. What's up in the air is only ever there to reach something.
	local frontier, best, bestD2 = nil, nil, math.huge
	local target = self.Waypoint or self.Target
	local tunnel = self.Hunting and self.Tunnel or 0
	local function Scan()
		frontier, best, bestD2 = {}, nil, math.huge
		local tx, ty, tz
		if target then tx, ty, tz = target:Unpack() end
		for node in pairs(mat.full) do
			if Frontier(node) then
				if not node.air then frontier[#frontier + 1] = node end
				if tx and (tunnel > 0 or not node.air) then
					local dx, dy, dz = node.x - tx, node.y - ty, node.z - tz
					local d2 = dx * dx + dy * dy + dz * dz
					if Behind(node, tx, ty, tz) then d2 = d2 * BEHIND end
					if d2 < bestD2 then best, bestD2 = node, d2 end
				end
			end
		end
	end

	while self.ReachDebt >= 1 and target do
		self.ReachDebt = self.ReachDebt - 1
		if not frontier or best and not Frontier(best) then Scan() end
		if best and bestD2 > ARRIVE * ARRIVE then
			-- Going up after something in the air, it heads straight out through it, and climbs whatever's in the way.
			local rise = tunnel > 0 and (best.air or math.random() < tunnel)
			local jitter = REACH_JITTER * (0.5 + 0.5 * sprawl) * (rise and RISE_JITTER or 1)
			local dir = (target - best.pos):GetNormalized() + VectorRand() * jitter
			if not (rise and self:Sprout(best, dir, now, nil, nil, true)) and not self.Absorbed then self:Sprout(best, dir, now) end
			if self.Absorbed then return end
		end
	end

	while self.SpreadDebt >= 1 do
		self.SpreadDebt = self.SpreadDebt - 1
		if not frontier then Scan() end
		local from
		for _ = 1, #frontier do
			local i = math.random(#frontier)
			if Frontier(frontier[i]) then from = frontier[i] break end
		end
		if from then self:Sprout(from, VectorRand(), now) end
		if self.Absorbed then return end
	end

	self:Weave(dt, now, speed)
end

-- Around a fresh catch the mat knits itself much tighter than anywhere else.
function ENT:Weave(dt, now, speed)
	local s = self.Tending
	if not s then
		self.WeaveDebt = 0
		return
	end
	local cap = math.min(SPROUTS_PER_TICK, DEBT_CAP * math.max(1, EvilFungus.TimeScale()))
	self.WeaveDebt = math.min(cap, self.WeaveDebt + WEAVE_RATE * speed * dt)
	while self.WeaveDebt >= 1 do
		self.WeaveDebt = self.WeaveDebt - 1
		local near = {}
		self.Mat:Near(s.nest.pos, WEAVE_RADIUS, function(node) near[#near + 1] = node end)
		if #near == 0 or #near >= WEAVE_MAX then return end
		self:Sprout(near[math.random(#near)], VectorRand(), now, WEAVE_SPACING, s.nest)
		if self.Absorbed then return end
	end
end

local function Colonies()
	local n = 0
	for colony in pairs(EvilFungus.Colonies) do
		if IsValid(colony) and not colony.Absorbed then n = n + 1 end
	end
	return n
end

-- Whether the map has room for another patch at all.
function EvilFungus.Room()
	return Colonies() < MAX_COLONIES and EvilFungus.Strands() < EvilFungus.Setting("max_nodes") * 0.9
end

function EvilFungus.Taken(pos, clear)
	clear = clear or SPORE_CLEAR
	for colony in pairs(EvilFungus.Colonies) do
		if IsValid(colony) and colony.Mat and colony.Mat:Nearest(pos, clear) then return true end
	end
	return false
end
local Taken = EvilFungus.Taken

-- A new patch on the ground at pos, starting with that much body and thinking with that mind.
function EvilFungus.Plant(pos, normal, mass, mind, creator)
	local spore = ents.Create("evil_fungus")
	if not IsValid(spore) then return end
	spore:SetPos(pos + normal * 4)
	spore.SpawnAt, spore.SpawnUp, spore.StartMass = pos, normal, mass
	spore.Mind = mind
	spore:Spawn()
	spore:Activate()
	Own(spore, creator)
	return spore
end

concommand.Add("evil_fungus_clear", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local list = {}
	for colony in pairs(EvilFungus.Colonies) do
		if IsValid(colony) then list[#list + 1] = colony end
	end
	for _, colony in ipairs(list) do colony:Remove() end
end, nil, "Remove every patch of fungus on the map")

-- Takes that much body out of the mat, evenly from everywhere it has any.
function ENT:Spend(mass)
	if self.Body <= EMPTY then return end
	local keep = math.max(0, 1 - mass / self.Body)
	for node in pairs(self.Mat.full) do self.Mat:SetMass(node, node.m * keep) end
	self.Body = self.Body * keep
end

function ENT:Throw(from, dir)
	local tr = util.TraceLine({ start = from, endpos = from + dir * SPORE_RANGE, mask = MASK_SOLID_BRUSHONLY })
	if not tr.HitWorld or tr.HitSky or tr.HitNoDraw or tr.StartSolid or tr.Fraction <= 0.2 or Taken(tr.HitPos) then return false end
	local mass = self.Body * SPORE_SHARE
	if not EvilFungus.Plant(tr.HitPos, tr.HitNormal, mass, self.Mind, self:GetCreator()) then return true end
	self:Spend(mass)

	local fx = EffectData()
	fx:SetStart(from)
	fx:SetOrigin(tr.HitPos)
	fx:SetNormal(tr.HitNormal)
	util.Effect("evil_fungus_spore", fx, true, true)
	return true
end

-- Fed well enough, it throws part of itself somewhere else to start over. Same fungus, so they find each other again.
-- Whoever it can smell getting away gets one at their feet, or once it's learned a bit, wherever they're running to.
function ENT:Spores(dt)
	local rate = EvilFungus.Setting("spores")
	if rate <= 0 or self.Body < SPORE_BODY then
		self.SporeDebt = 0
		return
	end
	self.SporeDebt = (self.SporeDebt or 0) + dt * rate / SPORE_EVERY
	if self.SporeDebt < 1 then return end
	self.SporeDebt = 0
	if not EvilFungus.Room() then return end

	local from = self.Center + self.Up * 24
	local prey = self.Hunting and self.Smelled == self.Prey and self.Prey
	local at = IsValid(prey) and self.Target
	if at and from:DistToSqr(at) < SPORE_RANGE * SPORE_RANGE
		and self:Throw(from, (at - from):GetNormalized()) then
		return
	end
	for _ = 1, SPORE_TRIES do
		local dir = VectorRand()
		dir.z = math.abs(dir.z) * 0.5 + 0.2
		dir:Normalize()
		if self:Throw(from, dir) then return end
	end
end

function ENT:OnRemove()
	EvilFungus.Colonies[self] = nil
	if not self.Absorbed and self.Mat and EvilFungus.Net then
		for _, node in pairs(self.Mat.nodes) do EvilFungus.Net.Drop(node) end
	end
	if not self.Absorbed then
		for rag in pairs(self.Claimed or {}) do
			local s = EvilFungus.Sleepers[rag]
			if s and s.stage < EvilFungus.KEPT then
				EvilFungus.Sleep.Free(s)
			elseif IsValid(rag) then
				rag:Remove()
			end
		end
	end
	self:ReleaseAll()
end
