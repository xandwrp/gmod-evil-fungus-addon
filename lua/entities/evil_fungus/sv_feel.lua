local FEEL_INTERVAL = 0.1
local FEEL_RADIUS = 28
local STANDING = 0.5
local BOX_PAD = Vector(64, 64, 64)
local MAX_PENDING = 32
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
local DOSE_MASS = 4
local SLEEPER_RADIUS = 56
local BREATH_GAIN = 0.15
local NPC_SLOW, NPC_FAST = 0.4, 1.4
local NPC_RUN = 240
local RIPPLE_RANGE = 2000
local FOOD_RADIUS = 40
local FOOD_PER_KG = 0.5
local FOOD_VALUE = { 4, 60 }
local DIGEST_RATE = 4
local DIGEST_GAIN = 0.8
local LANDING = { 0.3, 1.2 }
local LANDING_KG = 100
local ROT = { 70, 55, 40 }

ENT.WAVE_SPEED = WAVE_SPEED

local ai_ignoreplayers = GetConVar("ai_ignoreplayers")

local Creature = EvilFungus.Creature

function ENT:InitFeel()
	self.Touching, self.Pending, self.Waves, self.Dragged = {}, {}, {}, {}
	self.NextFeel, self.FeltAt = 0, -math.huge
end

function ENT:Perceivable(ent)
	if not IsValid(ent) or ent:IsFlagSet(FL_NOTARGET) or ent.EvilFungusAsleep then return false end
	if ent:IsPlayer() then
		return EvilFungus.Setting("attack_players") > 0
			and not (ai_ignoreplayers and ai_ignoreplayers:GetBool())
			and ent:Alive()
			and not (ent:GetMoveType() == MOVETYPE_NOCLIP and not ent:InVehicle())
			and ent:GetObserverMode() == OBS_MODE_NONE
	end
	if Creature(ent) then
		return EvilFungus.Setting("attack_npcs") > 0 and ent:Health() > 0 and EvilFungus.Bleeds(ent)
	end
	return EvilFungus.Foods[ent] and EvilFungus.Setting("eat_props") > 0 and not ent:IsPlayerHolding() or false
end

local function Kilos(ent)
	local kg = 0
	for i = 0, ent:GetPhysicsObjectCount() - 1 do
		local phys = ent:GetPhysicsObjectNum(i)
		if IsValid(phys) then kg = kg + phys:GetMass() end
	end
	return kg
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
		local mins, maxs = mat.mins - BOX_PAD, mat.maxs + BOX_PAD
		local function Visit(ent)
			if not ent:GetPos():WithinAABox(mins, maxs) or not ent:IsOnGround() or not self:Perceivable(ent) then return end
			local node = mat:Nearest(ent:GetPos(), FEEL_RADIUS, function(n) return n.normal.z > STANDING end)
			if node then
				local st = self.Touching[ent] or { walked = 0, still = now + STILL_STEP }
				st.node = node
				touching[ent] = st
			end
		end
		for _, ply in ipairs(player.GetAll()) do Visit(ply) end
		for ent in pairs(EvilFungus.Creatures) do
			if IsValid(ent) then Visit(ent) end
		end
		for ent in pairs(EvilFungus.Foods) do
			if IsValid(ent) and ent:GetPos():WithinAABox(mins, maxs) and self:Perceivable(ent) then
				local node = mat:Nearest(ent:GetPos(), FOOD_RADIUS)
				if node then
					local st = self.Touching[ent]
					if not st then
						st = { food = true }
						local landing = Lerp(math.Clamp(Kilos(ent) / LANDING_KG, 0, 1), LANDING[1], LANDING[2])
						self:Tremor(node, landing, now, ent)
					end
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
	self:Breathe(dt)

	for ent, st in pairs(touching) do
		if st.food then
			self:Digest(ent, st.node, dt)
		else
			local speed = ent:GetVelocity():Length()
			st.walked = st.walked + speed * dt
			if st.walked >= STEP_DISTANCE or now >= st.still then
				st.walked, st.still = 0, now + STILL_STEP
				self:Tremor(st.node, Strength(ent, speed), now, ent)
			end
			self:Feed(ent, st.node, dt)
		end
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
	local debugging = self:Debugging()
	local nearest = math.huge
	local dist = mat:Distances({ [node] = 0 }, function(e) return e.len end, reach, function(n, d)
		if n.m > FEEL_MASS and d < nearest then nearest = d end
		return not debugging and nearest < math.huge
	end)

	if nearest < math.huge and #self.Pending < MAX_PENDING then
		self.Pending[#self.Pending + 1] = { at = now + nearest / WAVE_SPEED, ent = ent, node = node }
	end
	if debugging then
		self.Waves[#self.Waves + 1] = { dist = dist, start = now, reach = reach }
	end
end

function ENT:Ripple(node, now)
	if not self:Debugging() then return end
	local dist = self.Mat:Distances({ [node] = 0 }, function(e) return e.len end, RIPPLE_RANGE)
	self.Waves[#self.Waves + 1] = { dist = dist, start = now, reach = RIPPLE_RANGE }
end

-- Whatever the other half was feeling, holding or chasing, this half now is.
function ENT:Adopt(other)
	for ent, st in pairs(other.Touching) do
		if not self.Touching[ent] then self.Touching[ent] = st end
	end
	for ent in pairs(other.Dragged) do self.Dragged[ent] = true end
	for rag in pairs(other.Claimed) do self:Claim(rag) end
	other.Claimed = {}
	for _, p in ipairs(other.Pending) do self.Pending[#self.Pending + 1] = p end
	for _, w in ipairs(other.Waves) do self.Waves[#self.Waves + 1] = w end
	if other.FeltAt > self.FeltAt and IsValid(other.Prey) then
		self.Prey, self.PreyNode, self.FeltAt, self.Eating = other.Prey, other.PreyNode, other.FeltAt, other.Eating
	end
	other:InitFeel()
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
	local dose = dt / math.max(0.1, EvilFungus.Setting("sleep_time")) * math.Clamp(m / DOSE_MASS, 0.5, 2)
	if EvilFungus.Sedate(ent, dose, self) and ent == self.Prey then self.Eating = nil end
end

function ENT:Claim(rag)
	self.Claimed[rag] = true
	local s = EvilFungus.Sleepers[rag]
	if s then s.fungus = self end
end

function ENT:Unclaim(rag)
	self.Claimed[rag] = nil
end

-- They're asleep, not dead, whatever the scoreboard says. It lives off their breathing.
function ENT:Breathe(dt)
	local mat = self.Mat
	for rag in pairs(self.Claimed) do
		if IsValid(rag) then
			local node = mat:Nearest(rag:GetPos(), SLEEPER_RADIUS)
			if node then mat:SetMass(node, node.m + BREATH_GAIN * dt) end
		else
			self.Claimed[rag] = nil
		end
	end
end

-- What can't fight back just rots away into it.
function ENT:Digest(ent, node, dt)
	local mat = self.Mat
	local m = 0
	mat:Near(ent:GetPos(), GRIP_RADIUS, function(n) m = m + n.m end)
	if m < GRAB_MASS then return end
	if ent == self.Prey then self.Eating = true end

	if not ent.EvilFungusFood then
		ent.EvilFungusFood = math.Clamp(Kilos(ent) * FOOD_PER_KG, FOOD_VALUE[1], FOOD_VALUE[2])
		ent.EvilFungusLeft = ent.EvilFungusFood
	end
	local bite = math.min(ent.EvilFungusLeft, DIGEST_RATE * dt * math.Clamp(m / 8, 0.5, 2))
	ent.EvilFungusLeft = ent.EvilFungusLeft - bite
	mat:SetMass(node, node.m + bite * DIGEST_GAIN)

	local k = 1 - ent.EvilFungusLeft / ent.EvilFungusFood
	ent:SetColor(Color(Lerp(k, 255, ROT[1]), Lerp(k, 255, ROT[2]), Lerp(k, 255, ROT[3])))
	if ent.EvilFungusLeft <= 0 then
		if ent == self.Prey then self.Eating = nil end
		EvilFungus.Foods[ent] = nil
		ent:Remove()
	end
end

function ENT:Release(ent)
	if self.Dragged[ent] then
		self.Dragged[ent] = nil
		if IsValid(ent) then ent:SetNW2Float(EvilFungus.DRAG_VAR, 0) end
	end
end

function ENT:ReleaseAll()
	for ent in pairs(self.Dragged or {}) do self:Release(ent) end
end
