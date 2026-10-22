EvilFungus = EvilFungus or {}

local TICK = 1
local RANGE = 1500
local SEARCH = { 192, 384 }
local EYES = 6
local NPCS = 16
local LIFT = 2
local EYE_FLAGS = 65536 + 131072

local eyes = {}

local function Disposition()
	return EvilFungus.Setting("npcs_fight") > 0 and D_HT or D_NU
end

local function Fights(npc)
	return IsValid(npc) and npc:IsNPC() and npc:GetClass() ~= "npc_bullseye" and npc:Health() > 0
		and not npc:GetNoDraw() and not npc:IsEFlagSet(EFL_NO_THINK_FUNCTION)
end

local function Meet(npc, eye, d)
	if npc.IsDrGNextbot and npc.SetEntityRelationship then
		npc:SetEntityRelationship(eye, d, 1)
	elseif Fights(npc) then
		npc:AddEntityRelationship(eye, d, 0)
	end
end

local function Open(colony, i)
	colony.Eyes = colony.Eyes or {}
	local eye = colony.Eyes[i]
	if IsValid(eye) then return eye end
	eye = ents.Create("npc_bullseye")
	eye:SetKeyValue("spawnflags", tostring(EYE_FLAGS))
	eye:Spawn()
	eye:Activate()
	colony:DeleteOnRemove(eye)
	colony.Eyes[i] = eye
	eyes[eye] = true
	local d = Disposition()
	for _, npc in ipairs(ents.GetAll()) do
		if npc:IsNPC() or npc:IsNextBot() then Meet(npc, eye, d) end
	end
	return eye
end

local function Close(colony, from)
	for i = from, #(colony.Eyes or {}) do
		local eye = colony.Eyes[i]
		colony.Eyes[i] = nil
		if IsValid(eye) then
			eyes[eye] = nil
			eye:Remove()
		end
	end
end

local function Visible(from, node)
	local to = node.pos + node.normal * LIFT
	return util.TraceLine({ start = from, endpos = to, mask = MASK_SOLID_BRUSHONLY }).Fraction > 0.98
end

local function Spot(mat, npc)
	local eye = npc:EyePos()
	local at = Vector(
		math.Clamp(eye.x, mat.mins.x, mat.maxs.x),
		math.Clamp(eye.y, mat.mins.y, mat.maxs.y),
		math.Clamp(eye.z, mat.mins.z, mat.maxs.z))
	if at:DistToSqr(eye) > RANGE * RANGE then return end
	for _, radius in ipairs(SEARCH) do
		local node = mat:Nearest(at, radius, function(n) return not n.dead end)
		if node then return Visible(eye, node) and node or nil end
	end
end

local function Watch(colony, npcs)
	local mat = colony.Mat
	if colony.Absorbed or not mat or not mat.mins or mat.count <= 0 then
		Close(colony, 1)
		return
	end
	local used, n = {}, 0
	for _, npc in ipairs(npcs) do
		if n >= EYES then break end
		local node = Spot(mat, npc)
		if node and not used[node] then
			used[node] = true
			n = n + 1
			Open(colony, n):SetPos(node.pos + node.normal * LIFT)
		end
	end
	Close(colony, n + 1)
end

local nextTick = 0

hook.Add("Think", "EvilFungusEnemy", function()
	local now = CurTime()
	if now < nextTick then return end
	nextTick = now + TICK
	local colonies = EvilFungus.Colonies or {}
	if not next(colonies) then return end
	if EvilFungus.Setting("npcs_fight") == 0 then
		for colony in pairs(colonies) do
			if IsValid(colony) then Close(colony, 1) end
		end
		return
	end
	local npcs = {}
	for _, npc in ipairs(ents.FindByClass("npc_*")) do
		if Fights(npc) then
			npcs[#npcs + 1] = npc
			if #npcs >= NPCS then break end
		end
	end
	for colony in pairs(colonies) do
		if IsValid(colony) then Watch(colony, npcs) end
	end
end)

hook.Add("OnEntityCreated", "EvilFungusEnemy", function(ent)
	if not (ent:IsNPC() or ent:IsNextBot()) or ent:GetClass() == "npc_bullseye" then return end
	timer.Simple(0, function()
		if not IsValid(ent) then return end
		local d = Disposition()
		for eye in pairs(eyes) do
			if IsValid(eye) then Meet(ent, eye, d) else eyes[eye] = nil end
		end
	end)
end)
