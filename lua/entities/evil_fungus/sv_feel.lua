local FEEL_INTERVAL = 0.1
local FEEL_RADIUS = 28
local STANDING = 0.5
local BOX_PAD = Vector(64, 64, 64)
local WAVE_SPEED = 500
local WAVE_RANGE = 900
local STEP_DISTANCE = 56
local STILL_STEP = 2.5
local STILL_SPEED = 5
local FEEL_MASS = 0.3
local GRIP_RADIUS = 48
local DRAG_MASS = { 1, 8 }
local DRAG_MAX = 0.85
local GRAB_MASS = 2.5
local FEED_DPS = 10
local FEED_GAIN = 0.5
local KILL_GAIN = 15
local NPC_SLOW, NPC_FAST = 0.4, 1.4
local NPC_RUN = 240

ENT.WAVE_SPEED = WAVE_SPEED

local ai_ignoreplayers = GetConVar("ai_ignoreplayers")

local function Creature(ent)
	return ent:IsNPC() or ent:IsNextBot()
end

function ENT:InitFeel()
	self.Touching, self.Pending, self.Waves, self.Dragged, self.Bites = {}, {}, {}, {}, {}
	self.NextFeel, self.FeltAt = 0, -math.huge
end

function ENT:Perceivable(ent)
	if not IsValid(ent) or ent:IsFlagSet(FL_NOTARGET) then return false end
	if ent:IsPlayer() then
		return EvilFungus.Setting("attack_players") > 0
			and not (ai_ignoreplayers and ai_ignoreplayers:GetBool())
			and ent:Alive()
			and not (ent:GetMoveType() == MOVETYPE_NOCLIP and not ent:InVehicle())
			and ent:GetObserverMode() == OBS_MODE_NONE
	end
	return Creature(ent) and EvilFungus.Setting("attack_npcs") > 0 and ent:Health() > 0
end

function ENT:Touches(ent)
	return self.Touching[ent] ~= nil
end

local function Strength(ent, speed)
	if ent:IsPlayer() then
		if speed < STILL_SPEED then return 0.4 end
		if ent:Crouching() then return 0.35 end
		if ent:KeyDown(IN_SPEED) and speed > ent:GetWalkSpeed() then return 1.6 end
		if ent:KeyDown(IN_WALK) then return 0.6 end
		return 1
	end
	return Lerp(math.Clamp(speed / NPC_RUN, 0, 1), NPC_SLOW, NPC_FAST)
end

function ENT:Feel(now)
	if now < self.NextFeel then return end
	local dt = math.min(FEEL_INTERVAL * 3, now - (self.LastFeel or now))
	self.LastFeel, self.NextFeel = now, now + FEEL_INTERVAL

	local mat = self.Mat
	local touching = {}
	if mat.mins then
		for _, ent in ipairs(ents.FindInBox(mat.mins - BOX_PAD, mat.maxs + BOX_PAD)) do
			if (ent:IsPlayer() or Creature(ent)) and ent:IsOnGround() and self:Perceivable(ent) then
				local node = mat:Nearest(ent:GetPos(), FEEL_RADIUS, function(n) return n.normal.z > STANDING end)
				if node then
					local st = self.Touching[ent] or { walked = 0, still = now + STILL_STEP }
					st.node = node
					touching[ent] = st
				end
			end
		end
	end

	for ent in pairs(self.Touching) do
		if not touching[ent] then self:Release(ent) end
	end
	self.Touching = touching

	for ent, st in pairs(touching) do
		local speed = ent:GetVelocity():Length()
		st.walked = st.walked + speed * dt
		if st.walked >= STEP_DISTANCE or now >= st.still then
			st.walked, st.still = 0, now + STILL_STEP
			self:Tremor(st.node, Strength(ent, speed), now, ent)
		end
		self:Feed(ent, st.node, dt)
	end

	for i = #self.Pending, 1, -1 do
		local p = self.Pending[i]
		if now >= p.at then
			table.remove(self.Pending, i)
			self:Felt(p.ent, p.node, now)
		end
	end

	for i = #self.Waves, 1, -1 do
		local w = self.Waves[i]
		if (now - w.start) * WAVE_SPEED > w.reach then table.remove(self.Waves, i) end
	end
end

-- A footstep runs out through the mat; whatever of the body it reaches feels it once the wave gets there.
function ENT:Tremor(node, strength, now, ent)
	local mat = self.Mat
	local reach = WAVE_RANGE * strength
	local dist = mat:Distances({ [node] = 0 }, function(e) return e.len end, reach)

	local nearest = math.huge
	for n in pairs(mat.full) do
		local d = dist[n]
		if d and d < nearest and n.m > FEEL_MASS then nearest = d end
	end
	if nearest < math.huge then
		self.Pending[#self.Pending + 1] = { at = now + nearest / WAVE_SPEED, ent = ent, node = node }
	end
	if self:Debugging() then
		self.Waves[#self.Waves + 1] = { dist = dist, start = now, reach = reach }
	end
end

function ENT:Felt(ent, node, now)
	if not IsValid(ent) or node.dead or not self:Perceivable(ent) then return end
	if self.Eating and IsValid(self.Prey) and self.Prey ~= ent then return end
	self.Prey, self.PreyNode, self.FeltAt = ent, node, now
	self.NextDecide = 0
end

function ENT:Feed(ent, node, dt)
	local mat = self.Mat
	local m = 0
	mat:Near(ent:GetPos(), GRIP_RADIUS, function(n) m = m + n.m end)

	if ent:IsPlayer() then
		local drag = math.Clamp((m - DRAG_MASS[1]) / (DRAG_MASS[2] - DRAG_MASS[1]), 0, 1) * DRAG_MAX
		ent:SetNW2Float(EvilFungus.DRAG_VAR, drag)
		self.Dragged[ent] = drag > 0 or nil
	end

	if m < GRAB_MASS then return end
	if ent == self.Prey then self.Eating = true end

	local bite = (self.Bites[ent] or 0) + FEED_DPS * dt * math.Clamp(m / 8, 0.5, 2)
	local whole = math.floor(bite)
	self.Bites[ent] = bite - whole
	if whole < 1 then return end

	local dmg = DamageInfo()
	dmg:SetDamage(whole)
	dmg:SetDamageType(DMG_ACID)
	dmg:SetAttacker(self)
	dmg:SetInflictor(self)
	dmg:SetDamagePosition(ent:GetPos())
	ent:TakeDamageInfo(dmg)

	local gain = whole * FEED_GAIN
	if ent:Health() <= 0 or ent:IsPlayer() and not ent:Alive() then
		gain = gain + KILL_GAIN
		self.Eating = nil
	end
	mat:SetMass(node, node.m + gain)
end

function ENT:Release(ent)
	self.Bites[ent] = nil
	if self.Dragged[ent] then
		self.Dragged[ent] = nil
		if IsValid(ent) then ent:SetNW2Float(EvilFungus.DRAG_VAR, 0) end
	end
end

function ENT:ReleaseAll()
	for ent in pairs(self.Dragged or {}) do self:Release(ent) end
end
