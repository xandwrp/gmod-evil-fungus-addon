EvilFungus = EvilFungus or {}
local Harm = EvilFungus.Harm or {}
EvilFungus.Harm = Harm

local TICK = 0.2
local SCAN = 0.25
local BURN_TIME = 3
local SPREAD = 0.15
local CATCH = 0.5
local SCORCH = 0.15
local CUT_RADIUS = 12
local BLAST_KILL = 0.6
local BLAST_MAGNITUDE = 100
local BLAST_GAP = 0.3
local LIFT = 4
local SEND_MAX = 2000
local SOUND_GAP = 0.5
local IGNITE_SOUND = "ambient/fire/ignite.wav"
local FLAME_PAD = 16
local FLAME_MAX = 128
local SOURCES = { env_fire = 48, env_flare = 16 }
local BODY_REACH = 24
local FEAR_PAD = 96
local RETREAT_MAX = 12

util.AddNetworkString("EvilFungusBurn")

local function On()
	return EvilFungus.Setting("killable") > 0
end

local function Around(pos, radius)
	local list, pad = {}, Vector(radius, radius, radius)
	for colony in pairs(EvilFungus.Colonies or {}) do
		local mat = IsValid(colony) and not colony.Absorbed and colony.Mat
		if mat and mat.mins and pos:WithinAABox(mat.mins - pad, mat.maxs + pad) then list[#list + 1] = colony end
	end
	return list
end

local function Clear(from, node)
	return not util.TraceLine({ start = from, endpos = node.pos + node.normal * LIFT, mask = MASK_SOLID_BRUSHONLY }).Hit
end

local queued = {}

function Harm.Ignite(colony, node, now)
	if node.burn or node.dead then return end
	node.burn = now
	colony.Mat.burning[node] = now
	if node.nid then queued[#queued + 1] = node.nid end
	for rag in pairs(colony.Claimed or {}) do
		if IsValid(rag) and rag:NearestPoint(node.pos):DistToSqr(node.pos) < BODY_REACH * BODY_REACH then EvilFungus.Sleep.Burn(rag) end
	end
	if now >= (colony.NextCrackle or 0) then
		colony.NextCrackle = now + SOUND_GAP
		sound.Play(IGNITE_SOUND, node.pos, 70, math.random(90, 110), 0.7)
	end
end

local function Kill(colony, node, scorch)
	if node.dead then return end
	if scorch and math.random() < SCORCH then
		util.Decal("SmallScorch", node.pos + node.normal * 8, node.pos - node.normal * 8)
	end
	colony.Mat:Remove(node)
end

function Harm.Cut(pos, radius)
	if not On() then return end
	for _, colony in ipairs(Around(pos, radius)) do
		local hit = {}
		colony.Mat:Near(pos, radius, function(node) hit[#hit + 1] = node end)
		for _, node in ipairs(hit) do Kill(colony, node) end
	end
end

local lastBlast, lastBlastAt = nil, -math.huge

function Harm.Blast(pos, radius)
	if not On() then return end
	local now = CurTime()
	if lastBlast and now - lastBlastAt < BLAST_GAP and lastBlast:DistToSqr(pos) < radius * radius then return end
	lastBlast, lastBlastAt = pos, now
	local kill2 = (radius * BLAST_KILL) ^ 2
	for _, colony in ipairs(Around(pos, radius)) do
		local hit = {}
		colony.Mat:Near(pos, radius, function(node, d2) hit[#hit + 1] = { node, d2 } end)
		for _, h in ipairs(hit) do
			local node, d2 = h[1], h[2]
			if Clear(pos, node) then
				if d2 < kill2 then Kill(colony, node, true) else Harm.Ignite(colony, node, now) end
			end
		end
	end
end

local function Catch(pos, radius, now)
	for _, colony in ipairs(Around(pos, radius)) do
		local hit = {}
		colony.Mat:Near(pos, radius, function(node) hit[#hit + 1] = node end)
		for _, node in ipairs(hit) do
			if math.random() < CATCH then Harm.Ignite(colony, node, now) end
		end
	end
end

local hot = {}

local function Cool()
	for node in pairs(hot) do node.heat = nil end
	hot = {}
end

local function Heat(pos, radius)
	local reach = radius + FEAR_PAD
	for _, colony in ipairs(Around(pos, reach)) do
		local mat = colony.Mat
		mat:Near(pos, reach, function(node, d2)
			local heat = 1 - math.sqrt(d2) / reach
			if heat > (node.heat or 0) then node.heat = heat end
			hot[node] = mat
		end)
	end
end

local function Retreat()
	local pulled = 0
	for node, mat in pairs(hot) do
		if pulled >= RETREAT_MAX then return end
		if not node.dead and not node.burn and #node.edges == 1 then
			local e = node.edges[1]
			local into = e.a == node and e.b or e.a
			if not into.burn and (into.heat or 0) < node.heat then
				mat:SetMass(into, into.m + node.m)
				mat:Remove(node)
				pulled = pulled + 1
			end
		end
	end
end

local function Scan(now)
	Cool()
	if not next(EvilFungus.Colonies or {}) then return end
	local fires = {}
	for _, flame in ipairs(ents.FindByClass("entityflame")) do
		local on = flame:GetParent()
		if not IsValid(on) then on = flame:GetInternalVariable("m_hEntAttached") end
		if IsValid(on) then
			fires[#fires + 1] = { on:GetPos(), math.min(FLAME_MAX, on:BoundingRadius() + FLAME_PAD) }
		else
			fires[#fires + 1] = { flame:GetPos(), FLAME_PAD * 2 }
		end
	end
	for class, radius in pairs(SOURCES) do
		for _, fire in ipairs(ents.FindByClass(class)) do
			if fire:GetInternalVariable("m_bEnabled") ~= false then fires[#fires + 1] = { fire:GetPos(), radius } end
		end
	end
	for _, f in ipairs(fires) do
		Catch(f[1], f[2], now)
		Heat(f[1], f[2])
	end
	Retreat()
end

local function Burn(now)
	for colony in pairs(EvilFungus.Colonies or {}) do
		local mat = IsValid(colony) and not colony.Absorbed and colony.Mat
		if mat and next(mat.burning) then
			local spread, burnt = {}, {}
			for node, at in pairs(mat.burning) do
				if node.dead then
					mat.burning[node] = nil
				elseif now - at >= BURN_TIME then
					burnt[#burnt + 1] = node
				else
					for _, e in ipairs(node.edges) do
						local other = e.a == node and e.b or e.a
						if not other.burn and math.random() < SPREAD then spread[#spread + 1] = other end
					end
				end
			end
			for _, node in ipairs(spread) do Harm.Ignite(colony, node, now) end
			for _, node in ipairs(burnt) do Kill(colony, node, true) end
		end
	end
end

local function Douse()
	Cool()
	for colony in pairs(EvilFungus.Colonies or {}) do
		local mat = IsValid(colony) and colony.Mat
		if mat and next(mat.burning) then
			for node in pairs(mat.burning) do node.burn = nil end
			mat.burning = {}
		end
	end
	queued = {}
end

local function Send()
	local n = math.min(#queued, SEND_MAX)
	if n == 0 then return end
	net.Start("EvilFungusBurn")
	net.WriteUInt(n, 12)
	for i = 1, n do net.WriteUInt(queued[i], 24) end
	net.Broadcast()
	local rest = {}
	for i = n + 1, #queued do rest[#rest + 1] = queued[i] end
	queued = rest
end

local nextScan, nextTick = 0, 0

hook.Add("Think", "EvilFungusHarm", function()
	local now = CurTime()
	if now < nextTick and now < nextScan then return end
	if not On() then
		Douse()
		return
	end
	if now >= nextScan then
		nextScan = now + SCAN
		Scan(now)
	end
	if now >= nextTick then
		nextTick = now + TICK
		Burn(now)
		Send()
	end
end)

hook.Add("EntityFireBullets", "EvilFungusHarm", function(ent, data)
	if not next(EvilFungus.Colonies or {}) or not On() then return end
	local src, dir = data.Src, data.Dir
	if not isvector(src) or not isvector(dir) then return end
	local spread = data.Spread
	if isnumber(spread) then
		spread = Vector(spread, spread, 0)
	elseif not isvector(spread) then
		spread = vector_origin
	end
	local ang = dir:Angle()
	local right, up = ang:Right(), ang:Up()
	local reach = tonumber(data.Distance) or 56756
	for _ = 1, math.Clamp(tonumber(data.Num) or 1, 1, 16) do
		local d = dir + right * spread.x * math.Rand(-1, 1) + up * spread.y * math.Rand(-1, 1)
		local tr = util.TraceLine({ start = src, endpos = src + d * reach, mask = MASK_SHOT, filter = { ent, data.IgnoreEntity } })
		if tr.HitWorld then Harm.Cut(tr.HitPos, CUT_RADIUS) end
	end
end)

hook.Add("OnEntityCreated", "EvilFungusHarm", function(ent)
	if ent:GetClass() ~= "env_explosion" then return end
	timer.Simple(0, function()
		if not IsValid(ent) or ent:CreatedByMap() then return end
		local kv = ent:GetKeyValues()
		local radius = tonumber(kv.iRadiusOverride) or 0
		if radius <= 0 then radius = (tonumber(kv.iMagnitude) or BLAST_MAGNITUDE) * 2.5 end
		Harm.Blast(ent:GetPos(), radius)
	end)
end)

hook.Add("EntityTakeDamage", "EvilFungusHarm", function(_, dmg)
	if not dmg:IsExplosionDamage() or not next(EvilFungus.Colonies or {}) then return end
	local inflictor = dmg:GetInflictor()
	if IsValid(inflictor) and inflictor:GetClass() == "env_explosion" then return end
	local pos = dmg:GetDamagePosition()
	if pos:IsZero() then return end
	Harm.Blast(pos, BLAST_MAGNITUDE * 2.5)
end)
