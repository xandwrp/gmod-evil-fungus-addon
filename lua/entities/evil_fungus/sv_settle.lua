local Mat = EvilFungus.Mat

local FOLD_INTERVAL = { 2, 0.25 }
local FOLDS = { 12, 64 }
local FOLD_MIN = 6
local AGE = 30
local GROW_MASS = 1
local WAKE_RADIUS = 128
local FOOD_WAKE = 64
local KEEP_CLEAR = 96
local ROUSE_INTERVAL = 0.1
local UNFOLDS = 16
local FLAT = 16
local BOX_PAD = Vector(256, 256, 256)
local SIDES = {
	[0] = { Vector(1, 0, 0), Vector(0, 1, 0) },
	[1] = { Vector(1, 0, 0), Vector(0, 1, 0) },
	[2] = { Vector(0, 1, 0), Vector(0, 0, 1) },
	[3] = { Vector(0, 1, 0), Vector(0, 0, 1) },
	[4] = { Vector(1, 0, 0), Vector(0, 0, 1) },
	[5] = { Vector(1, 0, 0), Vector(0, 0, 1) },
}
local UP = { [0] = Vector(0, 0, 1), Vector(0, 0, -1), Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0), Vector(0, -1, 0) }

function ENT:Stirring()
	local list = {}
	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() then list[#list + 1] = { ply:GetPos(), WAKE_RADIUS } end
	end
	for ent in pairs(EvilFungus.Creatures) do
		if IsValid(ent) then list[#list + 1] = { ent:GetPos(), WAKE_RADIUS } end
	end
	for ent in pairs(EvilFungus.Foods) do
		if IsValid(ent) then list[#list + 1] = { ent:GetPos(), FOOD_WAKE } end
	end
	for rag in pairs(self.Claimed) do
		if IsValid(rag) then list[#list + 1] = { rag:GetPos(), WAKE_RADIUS } end
	end
	for _, crawler in ipairs(ents.FindByClass("evil_crawler")) do list[#list + 1] = { crawler:GetPos(), WAKE_RADIUS } end
	return list
end

function ENT:Rouse(now)
	local mat = self.Mat
	if not next(mat.settled) or not mat.mins or now < (self.NextRouse or 0) then return end
	self.NextRouse = now + ROUSE_INTERVAL
	local mins, maxs = mat.mins - BOX_PAD, mat.maxs + BOX_PAD
	for _, s in ipairs(self:Stirring()) do
		if s[1]:WithinAABox(mins, maxs) then mat:Wake(s[1], s[2], now) end
	end
end

local function Loose(self, mat, node, now, age)
	return not node.air and not node.burn and not node.heat and not mat.woven[node] and node.m < GROW_MASS
		and now - (node.born or 0) > age and node ~= self.Goal and node ~= self.PreyNode
end

local function Key(cell, bucket)
	return cell * 8 + bucket
end

local function Flat(list)
	local first = list[1]
	local px, py, pz = first.x, first.y, first.z
	local nx, ny, nz = first.normal:Unpack()
	for _, node in ipairs(list) do
		if math.abs((node.x - px) * nx + (node.y - py) * ny + (node.z - pz) * nz) > FLAT then return false end
	end
	return true
end

local function Hemmed(mat, occupied, cell, bucket, center)
	local up = UP[bucket]
	for _, axis in ipairs(SIDES[bucket]) do
		for sign = -1, 1, 2 do
			local dir = axis * sign
			local filled = false
			for lift = -1, 1 do
				local at = center + dir * Mat.FELT + up * (lift * Mat.FELT)
				if occupied[Mat.FeltCell(at:Unpack())] then
					filled = true
					break
				end
			end
			if not filled then
				local from = center + up * 8
				filled = util.TraceLine({ start = from, endpos = from + dir * Mat.FELT, mask = MASK_SOLID_BRUSHONLY }).Hit
			end
			if not filled then return false end
		end
	end
	return true
end

function ENT:Settling(now)
	if now < (self.NextFold or 0) then return end
	local hurt = EvilFungus.Setting("hurtilizer")
	self.NextFold = now + Lerp(hurt, FOLD_INTERVAL[1], FOLD_INTERVAL[2])
	local age, most = AGE * (1 - hurt), math.Round(Lerp(hurt, FOLDS[1], FOLDS[2]))
	local mat = self.Mat
	if EvilFungus.Setting("settle") <= 0 then
		if not next(mat.settled) then return end
		local list = {}
		for node in pairs(mat.settled) do
			if not node.burn then list[#list + 1] = node end
			if #list >= UNFOLDS then break end
		end
		for _, node in ipairs(list) do mat:Unfold(node, now) end
		return
	end

	local groups, blocked, occupied = {}, {}, {}
	for _, node in pairs(mat.nodes) do
		local cell = Mat.FeltCell(node.x, node.y, node.z)
		occupied[cell] = true
		if not node.bucket then node.bucket = Mat.Bucket(node.normal) end
		local key = not node.felt and not node.air and Key(cell, node.bucket)
		if key and not blocked[key] then
			if Loose(self, mat, node, now, age) then
				local g = groups[key]
				if not g then
					g = { cell = cell, list = {} }
					groups[key] = g
				end
				g.list[#g.list + 1] = node
			else
				blocked[key] = true
				groups[key] = nil
			end
		end
	end

	local stirring = self:Stirring()
	local folds = 0
	for key, g in pairs(groups) do
		if not blocked[key] and #g.list >= FOLD_MIN then
			local first = g.list[1]
			local bucket = key % 8
			local clear = true
			for _, s in ipairs(stirring) do
				local r = s[2] + KEEP_CLEAR + Mat.FELT
				if s[1]:DistToSqr(first.pos) < r * r then
					clear = false
					break
				end
			end
			if clear and Flat(g.list) and Hemmed(mat, occupied, g.cell, bucket, first.pos) then
				mat:Fold(g.list, g.cell, now)
				folds = folds + 1
				if folds >= most then break end
			end
		end
	end
	if folds > 0 then self.GoalStale = true end
end
