EvilFungus = EvilFungus or {}

local Mat = {}
Mat.__index = Mat
EvilFungus.Mat = Mat

local CELL = 32
local STEP = 20
local SPACING = 13
local FUSE = 28
local FUSE_CHANCE = 0.5
local LIFT = 4
local MASK = MASK_SOLID_BRUSHONLY
local D_FLOOR = 0.4
local D_MAX = 10
local D_GAIN = 0.06
local D_DECAY = 0.004
local EMPTY = 1e-3

Mat.STEP = STEP
Mat.D_FLOOR = D_FLOOR
Mat.EMPTY = EMPTY
Mat.FUSE = FUSE

function EvilFungus.NewMat()
	return setmetatable({ nodes = {}, count = 0, cells = {}, full = {}, nextId = 1 }, Mat)
end

local function Key(ix, iy, iz)
	return (ix + 512) * 1048576 + (iy + 512) * 1024 + (iz + 512)
end

local function CellOf(pos)
	return math.floor(pos.x / CELL), math.floor(pos.y / CELL), math.floor(pos.z / CELL)
end

local function Place(self, node)
	node.id = self.nextId
	self.nextId = self.nextId + 1
	self.nodes[node.id] = node
	self.count = self.count + 1
	if node.m > EMPTY then self.full[node] = true end

	local pos = node.pos
	local key = Key(CellOf(pos))
	local cell = self.cells[key]
	if not cell then
		cell = {}
		self.cells[key] = cell
	end
	cell[node] = true
	node.cell = key

	if self.mins then
		self.mins = Vector(math.min(self.mins.x, pos.x), math.min(self.mins.y, pos.y), math.min(self.mins.z, pos.z))
		self.maxs = Vector(math.max(self.maxs.x, pos.x), math.max(self.maxs.y, pos.y), math.max(self.maxs.z, pos.z))
	else
		self.mins, self.maxs = Vector(pos), Vector(pos)
	end
end

function Mat:Add(pos, normal)
	local node = { pos = pos, normal = normal, m = 0, edges = {} }
	Place(self, node)
	return node
end

-- Takes over every strand of another mat, body and all, leaving it empty.
function Mat:Absorb(other)
	for _, node in pairs(other.nodes) do Place(self, node) end
	other.nodes, other.cells, other.full, other.count = {}, {}, {}, 0
	other.mins, other.maxs = nil, nil
end

function Mat:Remove(node)
	local cell = self.cells[node.cell]
	if cell then
		cell[node] = nil
		if next(cell) == nil then self.cells[node.cell] = nil end
	end
	for _, e in ipairs(node.edges) do
		local other = e.a == node and e.b or e.a
		for i, oe in ipairs(other.edges) do
			if oe == e then table.remove(other.edges, i) break end
		end
	end
	self.full[node] = nil
	self.nodes[node.id] = nil
	self.count = self.count - 1
	node.dead = true
end

function Mat:Other(e, node)
	return e.a == node and e.b or e.a
end

function Mat:Linked(a, b)
	for _, e in ipairs(a.edges) do
		if e.a == b or e.b == b then return true end
	end
	return false
end

function Mat:Link(a, b, now)
	local e = { a = a, b = b, len = math.max(1, a.pos:Distance(b.pos)), D = D_FLOOR, t = now }
	a.edges[#a.edges + 1] = e
	b.edges[#b.edges + 1] = e
	return e
end

function Mat:Conductance(e, now)
	if e.D > D_FLOOR then
		e.D = D_FLOOR + (e.D - D_FLOOR) * math.exp(-D_DECAY * (now - e.t))
	end
	e.t = now
	return e.D
end

function Mat:Thicken(e, flux, now)
	e.D = math.min(D_MAX, self:Conductance(e, now) + flux * D_GAIN)
end

function Mat:SetMass(node, m)
	node.m = m
	self.full[node] = m > EMPTY or nil
end

function Mat:Near(pos, radius, visit)
	local r2 = radius * radius
	local x0, y0, z0 = CellOf(pos - Vector(radius, radius, radius))
	local x1, y1, z1 = CellOf(pos + Vector(radius, radius, radius))
	for ix = x0, x1 do
		for iy = y0, y1 do
			for iz = z0, z1 do
				local cell = self.cells[Key(ix, iy, iz)]
				if cell then
					for node in pairs(cell) do
						local d2 = node.pos:DistToSqr(pos)
						if d2 <= r2 and visit(node, d2) == false then return end
					end
				end
			end
		end
	end
end

function Mat:Nearest(pos, radius, accept)
	local best, bestD2 = nil, math.huge
	self:Near(pos, radius, function(node, d2)
		if d2 < bestD2 and (not accept or accept(node)) then best, bestD2 = node, d2 end
	end)
	return best, best and math.sqrt(bestD2)
end

local function Trace(from, to)
	local tr = util.TraceLine({ start = from, endpos = to, mask = MASK })
	if not tr.Hit or tr.StartSolid or tr.HitSky or tr.HitNoDraw then return nil, tr end
	return tr
end

-- One step across whatever surface the node is on: straight on, up into an inside corner, or over an outside edge.
function Mat:Walk(node, dir, step)
	step = step or STEP
	local p, n = node.pos, node.normal
	dir = dir - n * dir:Dot(n)
	if dir:LengthSqr() < 1e-6 then return end
	dir:Normalize()

	local lift = p + n * LIFT
	local ahead = lift + dir * step
	local wall, blocked = Trace(lift, ahead)
	if wall then return wall.HitPos, wall.HitNormal end
	if blocked.Hit then return end

	local floor = Trace(ahead, ahead - n * (LIFT + step * 0.6))
	if floor then return floor.HitPos, floor.HitNormal end

	local below = ahead - n * (LIFT + step * 0.5)
	local edge = Trace(below, below - dir * (step * 1.5))
	if edge then return edge.HitPos, edge.HitNormal end
end

function Mat.Facing(a, b)
	return a.normal:Dot(b.normal) > 0.3
end

function Mat.Reaches(a, b)
	return not util.TraceLine({ start = a.pos + a.normal * LIFT, endpos = b.pos + b.normal * LIFT, mask = MASK }).Hit
end

function Mat:Crowded(pos, normal)
	local crowded = false
	self:Near(pos, SPACING, function(node)
		if node.normal:Dot(normal) > 0.3 then
			crowded = true
			return false
		end
	end)
	return crowded
end

function Mat:Grow(from, dir, now)
	local pos, normal = self:Walk(from, dir)
	if not pos or self:Crowded(pos, normal) then return end
	if bit.band(util.PointContents(pos + normal * 2), bit.bor(CONTENTS_WATER, CONTENTS_SLIME)) ~= 0 then return end

	local node = self:Add(pos, normal)
	self:Link(from, node, now)
	self:Near(pos, FUSE, function(other)
		if other ~= node and other ~= from and Mat.Facing(node, other) and not self:Linked(node, other)
			and math.random() < FUSE_CHANCE then
			if Mat.Reaches(node, other) then self:Link(node, other, now) end
		end
	end)
	return node
end

local function Push(h, d, v)
	local n = h.n + 1
	h.n = n
	local i = n
	while i > 1 do
		local p = math.floor(i / 2)
		if h.d[p] <= d then break end
		h.d[i], h.v[i] = h.d[p], h.v[p]
		i = p
	end
	h.d[i], h.v[i] = d, v
end

local function Pop(h)
	local n = h.n
	if n == 0 then return end
	local topD, topV = h.d[1], h.v[1]
	local d, v = h.d[n], h.v[n]
	h.d[n], h.v[n] = nil, nil
	n = n - 1
	h.n = n
	local i = 1
	while true do
		local c = i * 2
		if c > n then break end
		if c < n and h.d[c + 1] < h.d[c] then c = c + 1 end
		if h.d[c] >= d then break end
		h.d[i], h.v[i] = h.d[c], h.v[c]
		i = c
	end
	if n > 0 then h.d[i], h.v[i] = d, v end
	return topD, topV
end

-- Graph distance from the sources, by each edge's cost, out to the limit.
function Mat:Distances(sources, cost, limit)
	limit = limit or math.huge
	local dist, h = {}, { n = 0, d = {}, v = {} }
	for node, d in pairs(sources) do
		dist[node] = d
		Push(h, d, node)
	end
	while h.n > 0 do
		local d, node = Pop(h)
		if d <= dist[node] then
			for _, e in ipairs(node.edges) do
				local other = e.a == node and e.b or e.a
				local nd = d + cost(e)
				if nd <= limit and nd < (dist[other] or math.huge) then
					dist[other] = nd
					Push(h, nd, other)
				end
			end
		end
	end
	return dist
end
