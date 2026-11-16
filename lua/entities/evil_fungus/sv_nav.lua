-- Finding the way round. Growing straight at something is all it does until that stops getting it any
-- closer; then it feels its way over the surfaces ahead of the mat, the same way a strand would step,
-- and follows what it found one point at a time. No navmesh: the map's own brushes are the graph.

local Mat = EvilFungus.Mat

local STEP = 40
local CELL = 28
local DIRS = 8
local WEIGHT = 1.3
local MAX_NODES = 1500
local EXPANSIONS_PER_TICK = 10
local SEEDS_NEAR = 8
local SEEDS_RANDOM = 8
local GOAL_REACH = 80
local LIFT = 4
local STALL = 3
local GAIN = 24
local NEAR = 64
local MOVED = 256
local PLAN_DROP = 512
local LOCK_TIME = 6
local KEEP_MOVED = 160
local ARRIVE = 40
local LOOKAHEAD = 5
local ROUTE_STALL = 6
local RETRY = 5
local COOLDOWN = 1
local PARTIAL_GAIN = 128
local SMOOTH_SPAN = 6
local SMOOTH_LEN = 160
local BEND = 0.9
local CORNER_FAR = 2 * 40
local CORNER_PROBE = 12
local CORNER_ARRIVE = 20
local LEAP_RANGE = 64
local LEAP_GAP = 0.75
local MASK = MASK_SOLID_BRUSHONLY
local WET = bit.bor(CONTENTS_WATER, CONTENTS_SLIME)

-- All fungus on the map shares one budget of steps a tick, so several stuck patches can't stall the server.
-- It's split evenly between the ones searching, or whichever thought first each tick took the lot and the
-- rest never finished a search.
hook.Add("Tick", "EvilFungusNav", function()
	local n = 0
	for colony in pairs(EvilFungus.Colonies or {}) do
		if IsValid(colony) and colony.Plan then n = n + 1 end
	end
	EvilFungus.NavLeft = EXPANSIONS_PER_TICK
	EvilFungus.NavShare = math.max(1, math.floor(EXPANSIONS_PER_TICK / math.max(1, n)))
end)

local function Key(pos, normal)
	local x, y, z = pos:Unpack()
	local ix, iy, iz = math.floor(x / CELL) + 1024, math.floor(y / CELL) + 1024, math.floor(z / CELL) + 1024
	return ((ix * 2048 + iy) * 2048 + iz) * 8 + Mat.Bucket(normal)
end

local function Clear(a, an, b, bn)
	return not util.TraceLine({ start = a + an * LIFT, endpos = b + (bn or an) * LIFT, mask = MASK }).Hit
end

-- A plain binary heap on f.
local function Push(heap, item)
	local n = #heap + 1
	heap[n] = item
	while n > 1 do
		local p = math.floor(n / 2)
		if heap[p].f <= item.f then break end
		heap[n], heap[p] = heap[p], item
		n = p
	end
end

local function Pop(heap)
	local top, n = heap[1], #heap
	if n == 0 then return end
	local last = heap[n]
	heap[n] = nil
	n = n - 1
	if n == 0 then return top end
	heap[1] = last
	local i = 1
	while true do
		local l, r, s = i * 2, i * 2 + 1, i
		if l <= n and heap[l].f < heap[s].f then s = l end
		if r <= n and heap[r].f < heap[s].f then s = r end
		if s == i then break end
		heap[i], heap[s] = heap[s], heap[i]
		i = s
	end
	return top
end

-- Where on the mat to start feeling from: the bit already nearest, which is where greed got stuck, and a
-- scattering from the rest, since the way round often starts somewhere else entirely.
-- The part of the mat the body can actually get to: everything joined by strands to wherever most of the
-- mass is. Bits that got cut off (burnt through, blown apart, settled away) are still lying around and still
-- count as mat, but nothing can flow out to them, so they can't grow, pay for anything, or carry a route on.
-- Worked out once per decision and reused.
function ENT:Connected(now)
	if self.BodySet and self.BodySetAt == now then return self.BodySet end
	local label, best, bestMass = {}, nil, -1
	for _, node in pairs(self.Mat.nodes) do
		if not label[node] then
			local part, mass, stack = {}, 0, { node }
			label[node] = part
			while #stack > 0 do
				local n = stack[#stack]
				stack[#stack] = nil
				part[n] = true
				mass = mass + n.m
				for _, e in ipairs(n.edges) do
					local o = e.a == n and e.b or e.a
					if not label[o] and not o.dead then
						label[o] = part
						stack[#stack + 1] = o
					end
				end
			end
			if mass > bestMass then best, bestMass = part, mass end
		end
	end
	self.BodySet, self.BodySetAt = best or {}, now
	return self.BodySet
end

-- The strand of the body nearest a spot, for steering the body at.
local function BodyNearest(mat, body, pos)
	local node = mat:Nearest(pos, 96, function(n) return body[n] and not n.air end)
	if node then return node end
	local bestD2 = math.huge
	for n in pairs(body) do
		if not n.air and not n.dead then
			local d2 = n.pos:DistToSqr(pos)
			if d2 < bestD2 then node, bestD2 = n, d2 end
		end
	end
	return node
end

local function Seeds(body, target)
	local near, pool = {}, {}
	for node in pairs(body) do
		if not node.air and not node.dead then
			pool[#pool + 1] = node
			local d2 = node.pos:DistToSqr(target)
			if #near < SEEDS_NEAR or d2 < near[#near].d2 then
				local at = #near + 1
				while at > 1 and near[at - 1].d2 > d2 do at = at - 1 end
				table.insert(near, at, { node = node, d2 = d2 })
				near[SEEDS_NEAR + 1] = nil
			end
		end
	end
	local list, seen = {}, {}
	for _, s in ipairs(near) do
		list[#list + 1], seen[s.node] = s.node, true
	end
	for _ = 1, math.min(SEEDS_RANDOM, #pool) do
		local node = pool[math.random(#pool)]
		if not seen[node] then list[#list + 1], seen[node] = node, true end
	end
	return list
end

function ENT:StartPlan(target, now)
	local heap, seen = {}, {}
	local plan = { heap = heap, seen = seen, target = Vector(target.x, target.y, target.z), expanded = 0 }
	for _, node in ipairs(Seeds(self:Connected(now), target)) do
		local p = { pos = node.pos, normal = node.normal, g = 0 }
		p.h = node.pos:Distance(target)
		p.f = p.h * WEIGHT
		local key = Key(p.pos, p.normal)
		if not seen[key] then
			seen[key] = p
			Push(heap, p)
			if not plan.closest or p.h < plan.closest.h then plan.closest = p end
		end
	end
	self.NavTried = now
	if not plan.closest then return end
	self.Plan = plan
	self.NavLockUntil = now + LOCK_TIME
end

local function Goal(p, target)
	return p.h < GOAL_REACH and Clear(p.pos, p.normal, target)
end

-- Where the face one point is on meets the face the next one is on: the crease of an inside corner or the
-- lip of an outside one. The two planes cross along a line; the corner is the bit of that line nearest the
-- two points. Its normal splits the two faces, so the mat coming off either side counts as touching it.
local function Corner(a, b)
	local n1, n2 = a.normal, b.normal
	local c = n1:Dot(n2)
	local det = 1 - c * c
	if det < 0.05 then return end
	local h1, h2 = n1:Dot(a.pos), n2:Dot(b.pos)
	local origin = n1 * ((h1 - h2 * c) / det) + n2 * ((h2 - h1 * c) / det)
	local along = n1:Cross(n2):GetNormalized()
	local mid = (a.pos + b.pos) * 0.5
	local pos = origin + along * (mid - origin):Dot(along)
	if pos:DistToSqr(mid) > CORNER_FAR * CORNER_FAR then return end
	local normal = (n1 + n2):GetNormalized()
	-- There has to be something solid right there, or the planes only meet in thin air (a gap, a ledge
	-- with nothing under the line) and a point there would hang the front off nothing.
	local tr = util.TraceLine({ start = pos + normal * CORNER_PROBE, endpos = pos - normal * CORNER_PROBE, mask = MASK })
	if not tr.Hit or tr.StartSolid then return end
	return { pos = pos, normal = normal, corner = true, exit = n2 }
end

-- Whether a step the search took really stays on the surface. With steps this long, the outside-edge wrap
-- in Mat:Walk can carry straight over the top of a thin wall and land on the floor or face on the far side,
-- which puts a waypoint through the wall. A real step either has open air between its two ends (flat, or an
-- inside corner), or bends over a lip that is actually there, with open air on both legs of the bend.
local function Joined(a, b)
	if Clear(a.pos, a.normal, b.pos, b.normal) then return true end
	local c = Corner(a, b)
	return c ~= nil and Clear(a.pos, a.normal, c.pos, c.normal) and Clear(c.pos, c.normal, b.pos, b.normal)
end

-- Walks the found points back to the mat, puts a point on every corner it goes round, then drops every
-- point that can be seen past on the same face, so the front grows in long straight runs instead of
-- zigzagging through every probe. Corners are never smoothed away: rounding them is the hard part.
local function Unwind(last)
	local back = {}
	local p = last
	while p do
		back[#back + 1] = p
		p = p.from
	end
	local raw = {}
	for i = #back, 1, -1 do
		local q = back[i]
		local prev = raw[#raw]
		if prev and prev.normal:Dot(q.normal) < BEND then
			local corner = Corner(prev, q)
			if corner then raw[#raw + 1] = corner end
		end
		raw[#raw + 1] = q
	end
	local out, i = {}, 1
	while i < #raw do
		local j = math.min(#raw, i + SMOOTH_SPAN)
		for k = i + 1, j do
			if raw[k].corner then
				j = k
				break
			end
		end
		while j > i + 1 do
			local a, b = raw[i], raw[j]
			if a.normal:Dot(b.normal) > 0.9 and a.pos:DistToSqr(b.pos) < SMOOTH_LEN * SMOOTH_LEN and Clear(a.pos, a.normal, b.pos, b.normal) then break end
			j = j - 1
		end
		out[#out + 1] = { pos = raw[j].pos, normal = raw[j].normal, corner = raw[j].corner, exit = raw[j].exit }
		i = j
	end
	return out
end

function ENT:FinishPlan(last, now, partial)
	local plan = self.Plan
	self.Plan = nil
	local points = Unwind(last)
	if #points == 0 then return end
	self.Route = { points = points, i = 1, for_ = plan.target, progress = now, partial = partial }
	self.NavLockUntil = now + LOCK_TIME
	self.Waypoint, self.GoalStale = nil, true
end

function ENT:FailPlan(now)
	local plan = self.Plan
	self.Plan = nil
	self.NavFailFor, self.NavFailUntil = plan.target, now + RETRY
end

-- A few steps of the search each tick, out of the shared budget.
function ENT:StepPlan(now)
	local plan = self.Plan
	if not plan then return end
	local heap, seen, target = plan.heap, plan.seen, plan.target
	local share = EvilFungus.NavShare or EXPANSIONS_PER_TICK
	while share > 0 and (EvilFungus.NavLeft or 0) > 0 do
		share = share - 1
		EvilFungus.NavLeft = EvilFungus.NavLeft - 1
		local p = Pop(heap)
		if not p or plan.expanded >= MAX_NODES then
			-- Out of map or out of patience. If it got somewhere much nearer than the mat already is,
			-- going there is still better than grinding where it is.
			local c = plan.closest
			local have = self:Closest(target, true)
			if c and c.from and have and c.h < have.pos:Distance(target) - PARTIAL_GAIN then
				return self:FinishPlan(c, now, true)
			end
			return self:FailPlan(now)
		end
		if not p.closed then
			p.closed = true
			plan.expanded = plan.expanded + 1
			if Goal(p, target) then return self:FinishPlan(p, now, false) end
			local ang = p.normal:Angle()
			local right, up = ang:Right(), ang:Up()
			for k = 1, DIRS do
				local a = k / DIRS * math.pi * 2
				local pos, normal = Mat.Walk(nil, p, right * math.cos(a) + up * math.sin(a), STEP)
				if pos and bit.band(util.PointContents(pos + normal * 2), WET) == 0 then
					local key = Key(pos, normal)
					local g = p.g + p.pos:Distance(pos)
					local old = seen[key]
					if (not old or not old.closed and g < old.g) and Joined(p, { pos = pos, normal = normal }) then
						local q = old or { pos = pos, normal = normal }
						q.g, q.from = g, p
						q.h = q.h or pos:Distance(target)
						q.f = g + q.h * WEIGHT
						seen[key] = q
						Push(heap, q)
						if q.h < plan.closest.h then plan.closest = q end
					end
				end
			end
		end
	end
end

-- Whether the mat has actually got to a point. Being near isn't enough: a point just round a corner or on
-- the far face of a thin wall is within reach of the mat stuck on this side, and counting that as reached
-- skipped the route straight past the way round and left the front pushing into the same wall as before.
-- A corner is only rounded once the mat is on the face past it, right at the crease or lip. Mat that has
-- merely got close on the face before it hasn't gone round anything yet.
-- Only the body counts: a cut-off scrap lying on a waypoint hasn't got there, and moving the route on past it
-- left the next point for something with nothing behind it to grow with.
local function Touched(mat, body, p)
	if p.corner then
		return mat:Nearest(p.pos, CORNER_ARRIVE, function(n)
			return body[n] and not n.air and n.normal:Dot(p.exit) > BEND and Clear(n.pos, n.normal, p.pos, p.normal)
		end) ~= nil
	end
	return mat:Nearest(p.pos, ARRIVE, function(n)
		return body[n] and not n.air and n.normal:Dot(p.normal) > 0.3 and Clear(n.pos, n.normal, p.pos, p.normal)
	end) ~= nil
end

-- A route point close by and in plain view of the strand nearest it doesn't need growing to: the strand
-- just reaches over and puts one there, if it can pay for it. Corners land on the face past the crease, so
-- they count as rounded. Spaced out so a route can't be crossed faster than growth could manage.
function ENT:LeapTo(p, now)
	if now < (self.LeapAt or 0) then return end
	local body = self:Connected(now)
	local from = self.Mat:Nearest(p.pos, LEAP_RANGE, function(n) return body[n] and not n.air end)
	if not from or not Clear(from.pos, from.normal, p.pos, p.normal) then return end
	local node = self:Leap(from, p.pos, p.exit or p.normal, now)
	if not node then return end
	body[node] = true
	self.LeapAt = now + LEAP_GAP / math.max(0.1, EvilFungus.Setting("grow_speed") * EvilFungus.TimeScale())
	return node
end

function ENT:DropRoute()
	if not self.Route then return end
	self.Route, self.Waypoint, self.GoalStale = nil, nil, true
end

-- The point on the route to grow at right now, or nil once there's no route worth following.
-- The second return is true when the target walked off the end of the route, which is worth a fresh look.
function ENT:RoutePoint(now)
	local route, target = self.Route, self.Target
	if not route then return end
	local points = route.points
	if target:DistToSqr(route.for_) > KEEP_MOVED * KEEP_MOVED then
		-- Moved a little and still in plain view of where the route comes out: the route still does.
		local last = points[#points]
		if target:DistToSqr(route.for_) < MOVED * MOVED and Clear(last.pos, last.normal, target) then
			route.for_ = Vector(target.x, target.y, target.z)
		else
			self:DropRoute()
			return nil, true
		end
	end
	local mat, reached = self.Mat, nil
	local body = self:Connected(now)
	for j = math.min(#points, route.i + LOOKAHEAD), route.i, -1 do
		if Touched(mat, body, points[j]) then
			reached = j
			break
		end
	end
	if reached then
		route.i, route.progress = reached + 1, now
	end
	if route.i > #points then return self:DropRoute() end
	if self:LeapTo(points[route.i], now) and Touched(mat, body, points[route.i]) then
		route.i, route.progress = route.i + 1, now
		if route.i > #points then return self:DropRoute() end
	end
	if now - route.progress > ROUTE_STALL / EvilFungus.TimeScale() then
		self.NavFailFor, self.NavFailUntil = Vector(target.x, target.y, target.z), now + RETRY
		return self:DropRoute()
	end
	return points[route.i].pos
end

-- Keeps track of whether growing straight at the target is still getting anywhere, and starts looking for
-- a way round once it isn't. Returns the node to steer the body at while a route is being followed.
function ENT:Navigate(goal, now)
	local target = self.Target
	if not target or self.Tending or (self.Hunting and (self.Tunnel or 0) > 0) or EvilFungus.Setting("hurtilizer") > 0
		or EvilFungus.Setting("pathfinding") <= 0 then
		self.Plan, self.NavAt, self.NavSince, self.NavKey = nil, nil, nil, nil
		self:DropRoute()
		return
	end

	local point, moved = self:RoutePoint(now)
	if point then
		self.Waypoint = point
		return BodyNearest(self.Mat, self:Connected(now), point) or goal
	end

	-- A search only gets thrown away when the target ends up somewhere else entirely. Someone running about,
	-- or the aim swinging ahead of them, used to scrap it before it could finish; the route it finds still
	-- gets checked against where the target really is once it's being followed.
	if self.Plan then
		if target:DistToSqr(self.Plan.target) > PLAN_DROP * PLAN_DROP then self.Plan = nil end
		return
	end

	-- Stuck means the strand nearest the target isn't going anywhere. Only the strand counts, not the target:
	-- someone running around used to keep resetting this and it never looked for a way round. The nearest
	-- strand has to be new growth to count as moving, or the nearest one just changing over to some old bit of
	-- mat as the target circles would look like progress too.
	if not goal then return end
	local d = goal.pos:Distance(target)
	-- Going after something new starts the clock again, so it gets a fair go at growing straight there
	-- before it's judged stuck. Who or what it's after, not where they've walked to.
	local key = self.Hunting and self.Prey or self.Carrion or self.TargetUntil
	if key ~= self.NavKey then
		self.NavKey, self.NavAt, self.NavSince = key, goal.pos, now
		if not moved then return end
	end
	if not self.NavAt or goal.pos:DistToSqr(self.NavAt) > GAIN * GAIN and (goal.born or 0) > self.NavSince then
		self.NavAt, self.NavSince = goal.pos, now
		if not moved then return end
	end
	if d < NEAR then return end
	if self.NavFailFor and now < self.NavFailUntil and target:DistToSqr(self.NavFailFor) < MOVED * MOVED then return end
	if now - (self.NavTried or -math.huge) < COOLDOWN then return end
	if moved or now - self.NavSince > STALL / EvilFungus.TimeScale() then
		self:StartPlan(target, now)
	end
end

-- While it's searching or following what it found, it doesn't drop who it's after for someone else, unless
-- they walk onto the mat. Flipping between two people used to throw away every search halfway through.
function ENT:PreyLocked(now)
	return (self.Plan ~= nil or self.Route ~= nil) and now < (self.NavLockUntil or 0)
end

local ROUTE = Color(0, 200, 255)
local PLAN = Color(0, 90, 140)
local CORNER = Color(255, 220, 0)

function ENT:DebugNav(life)
	local route = self.Route
	if route then
		local prev
		for i, p in ipairs(route.points) do
			local at = p.pos + p.normal * 3
			if prev then debugoverlay.Line(prev, at, life, i <= route.i and ROUTE or PLAN, true) end
			debugoverlay.Cross(at, i == route.i and 10 or p.corner and 7 or 4, life, p.corner and CORNER or ROUTE, true)
			prev = at
		end
	end
	local plan = self.Plan
	if plan and plan.closest then
		debugoverlay.Cross(plan.closest.pos, 8, life, PLAN, true)
	end
end
