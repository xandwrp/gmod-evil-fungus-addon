EvilFungus = EvilFungus or {}

local SNIFF = 0.5
local DROP = 1
local LAST = 180
local MAX = 300
local FALL = Vector(0, 0, 4096)
local REACH = 48
local PAD = Vector(REACH, REACH, REACH)
local BHOP = 1.1

local scents = {}
EvilFungus.Scents = scents
local held = setmetatable({}, { __mode = "k" })

local function Tactic(ply)
	local move = ply:GetMoveType()
	if move == MOVETYPE_NOCLIP then return not ply:InVehicle() and "noclip" or nil end
	if move ~= MOVETYPE_WALK or ply:IsOnGround() or ply:WaterLevel() >= 2 then return end
	local vel = ply:GetVelocity()
	vel.z = 0
	return vel:Length() > ply:GetRunSpeed() * BHOP and "bhop" or "jump"
end

local function Drop(ply, tactic, amount, now)
	local from = ply:GetPos()
	local tr = util.TraceLine({ start = from, endpos = from - FALL, mask = MASK_SOLID_BRUSHONLY })
	if not tr.Hit or tr.HitSky then return end
	if #scents >= MAX then table.remove(scents, 1) end
	scents[#scents + 1] = { pos = tr.HitPos, tactic = tactic, amount = amount, at = now }
end

local function Found(s)
	for colony in pairs(EvilFungus.Colonies) do
		local mat = colony.Mat
		if IsValid(colony) and colony.Mind and mat and mat.mins and s.pos:WithinAABox(mat.mins - PAD, mat.maxs + PAD)
			and mat:Nearest(s.pos, REACH) then
			return colony
		end
	end
end

local nextSniff = 0

hook.Add("Think", "EvilFungusScent", function()
	local now = CurTime()
	if now < nextSniff then return end
	nextSniff = now + SNIFF
	if not next(EvilFungus.Colonies or {}) or EvilFungus.Setting("learning") <= 0 then return end

	for _, ply in ipairs(player.GetAll()) do
		local tactic = ply:Alive() and Tactic(ply)
		if tactic then
			local h = held[ply] or {}
			held[ply] = h
			h[tactic] = (h[tactic] or 0) + SNIFF
			if h[tactic] >= DROP then
				Drop(ply, tactic, h[tactic], now)
				h[tactic] = 0
			end
		end
	end

	for i = #scents, 1, -1 do
		local s = scents[i]
		if now - s.at > LAST then
			table.remove(scents, i)
		else
			local colony = Found(s)
			if colony then
				colony.Mind:Taste(s.tactic, s.amount)
				table.remove(scents, i)
			end
		end
	end
end)
