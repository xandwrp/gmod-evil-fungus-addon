local FEEL_INTERVAL = 0.1
local FEEL_RADIUS = 28
local STANDING = 0.5
local BOX_PAD = Vector(64, 64, 64)
local MAX_PENDING = 32
local WAVE_SPEED = 500
local QUICKER = 1
local WAVE_RANGE = 900
local STEP_DISTANCE = 56
local STILL_STEP = 2.5
local STILL_SPEED = 5
local FEEL_MASS = 0.3
local GRIP_RADIUS = 48
local DRAG_MASS = { 1, 8 }
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
local SMELL_INTERVAL = 0.5
local HURT_SMELL = 1
local SMELL_KEEP = 0.5
local SHAKE_INTERVAL = 0.25
local SHAKE_SPEED = 200
local SHAKE_MIN = 40
local SHAKE_MAX = 5
local SHAKE_GAP = 8
local SPY_PAD = Vector(256, 256, 256)
local OVER = Vector(0, 0, 64)
local OVER_RADIUS = 72
local HIGH = 32
local BHOP = 1.1
local SPY_LIFT = Vector(0, 0, 8)
local AIR_RADIUS = 40
local AGAINST_PAD = Vector(6, 6, 6)
local SCAVENGE_INTERVAL = 1
local CARRION_KEEP = 0.5
local CARRION_LIFT = Vector(0, 0, 8)

-- Everything it feels gets through the mat faster once it's got more to think with.
function ENT:WaveSpeed()
	return WAVE_SPEED * EvilFungus.TimeScale() * (1 + QUICKER * self.Mind:Grasp())
end

local ai_ignoreplayers = GetConVar("ai_ignoreplayers")

local Creature = EvilFungus.Creature

function ENT:InitFeel()
	self.Touching, self.Pending, self.Waves, self.Dragged = {}, {}, {}, {}
	self.NextFeel, self.FeltAt = 0, -math.huge
	self.NextSmell, self.Smelled = 0, nil
	self.NextShake = 0
end

local function Noclipping(ply)
	return ply:GetMoveType() == MOVETYPE_NOCLIP and not ply:InVehicle()
end

function ENT:Perceivable(ent, noclip)
	if not IsValid(ent) or ent:IsFlagSet(FL_NOTARGET) or ent.EvilFungusAsleep or EvilFungus.CrawlerHas(ent) then return false end
	if ent:IsPlayer() then
		return EvilFungus.Setting("attack_players") > 0
			and not (ai_ignoreplayers and ai_ignoreplayers:GetBool())
			and ent:Alive()
			and (noclip or not Noclipping(ent))
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

local function Against(mat, ent)
	local mins, maxs = ent:WorldSpaceAABB()
	mins, maxs = mins - AGAINST_PAD, maxs + AGAINST_PAD
	local center = (mins + maxs) * 0.5
	return mat:Nearest(center, center:Distance(maxs), function(n)
		return n.up <= STANDING and not n.air and n.pos:WithinAABox(mins, maxs)
	end)
end

function ENT:Feel(now)
	if now < self.NextFeel then return end
	local real = math.min(FEEL_INTERVAL * 3, now - (self.LastFeel or now))
	local dt = real * EvilFungus.TimeScale()
	self.LastFeel, self.NextFeel = now, now + FEEL_INTERVAL

	local mat = self.Mat
	local touching = {}
	if mat.mins then
		local mins, maxs = mat.mins - BOX_PAD, mat.maxs + BOX_PAD
		-- Off the ground, only strands it's put up in the air can get hold of you.
		local aloft = next(mat.air) ~= nil
		local noclip = self.Mind:Knows("noclip") > 0
		local function Visit(ent)
			local pos = ent:GetPos()
			if not pos:WithinAABox(mins, maxs) then return end
			local node
			if EvilFungus.OnGround(ent) then
				if not self:Perceivable(ent) then return end
				node = mat:Nearest(pos, FEEL_RADIUS, function(n) return n.up > STANDING and not n.air end) or Against(mat, ent)
			elseif aloft and self:Perceivable(ent, noclip) then
				node = mat:Nearest(ent:WorldSpaceCenter(), AIR_RADIUS, function(n) return n.air end)
			end
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
	if mat.mins then self:Spy(touching, real) end
	self:Breathe(dt)
	self:Smell(now)
	self:Shake(now)

	for ent, st in pairs(touching) do
		if st.food then
			self:Digest(ent, st.node, dt)
		else
			local speed = EvilFungus.Speed(ent)
			st.walked = st.walked + speed * real
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
			if p.lure then
				self:Lured(p.lure)
			else
				self:Felt(p.ent, p.node, now, p.from)
			end
		end
	end

	for i = #self.Waves, 1, -1 do
		local w = self.Waves[i]
		if (now - w.start) * w.speed > w.reach then table.remove(self.Waves, i) end
	end
end

-- How everyone near it who isn't on it is staying off it, for whatever it can make of that.
function ENT:Spy(touching, real)
	local mat, mind = self.Mat, self.Mind
	local mins, maxs = mat.mins - SPY_PAD, mat.maxs + SPY_PAD
	for _, ply in ipairs(player.GetAll()) do
		local pos = ply:GetPos()
		if not touching[ply] and pos:WithinAABox(mins, maxs) then
			if Noclipping(ply) then
				if self:Perceivable(ply, true) then mind:Watch(ply, "noclip", real) end
			elseif ply:GetMoveType() == MOVETYPE_WALK and ply:WaterLevel() < 2 and self:Perceivable(ply) then
				local grounded = ply:IsOnGround()
				local below = pos.z - (grounded and HIGH or 0)
				local floor = mat:Nearest(pos - OVER, OVER_RADIUS, function(n) return n.up > STANDING and not n.air and n.z < below end)
				if floor and not util.TraceLine({ start = pos + SPY_LIFT, endpos = floor.pos + floor.normal * 4, mask = MASK_SOLID_BRUSHONLY }).Hit then
					if grounded then
						mind:Watch(ply, "high", real)
					else
						local vel = ply:GetVelocity()
						vel.z = 0
						mind:Watch(ply, vel:Length() > ply:GetRunSpeed() * BHOP and "bhop" or "jump", real)
					end
				end
			end
		end
	end
end

-- A footstep runs out through the mat; whatever of the body it reaches feels it once the wave gets there.
function ENT:Tremor(node, strength, now, ent)
	local mat = self.Mat
	local reach = WAVE_RANGE * strength * EvilFungus.Setting("aggression")
	if reach <= 0 then return end
	local debugging = self:Debugging()
	local nearest = math.huge
	local dist = mat:Distances({ [node] = 0 }, function(e) return e.len end, reach, function(n, d)
		if n.m > FEEL_MASS and d < nearest then nearest = d end
		return not debugging and nearest < math.huge
	end)

	local speed = self:WaveSpeed()
	if nearest < math.huge and #self.Pending < MAX_PENDING then
		self.Pending[#self.Pending + 1] = { at = now + nearest / speed, ent = ent, node = node }
	end
	if debugging then
		self.Waves[#self.Waves + 1] = { dist = dist, start = now, reach = reach, speed = speed }
	end
end

local function Hurt(ent)
	local max = ent:GetMaxHealth()
	if max <= 0 then return 1 end
	return 1 + HURT_SMELL * math.Clamp(1 - ent:Health() / max, 0, 1)
end

-- Breathers off the mat leave something on the air. Close enough, with open air between, it knows where they are.
function ENT:Smell(now)
	local range = EvilFungus.Setting("smell")
	if range <= 0 then
		self.Smelled = nil
		return
	end
	if now < self.NextSmell or not self.Mat.mins then return end
	self.NextSmell = now + SMELL_INTERVAL
	self.Smelled = nil
	local prey = self.Prey
	if IsValid(prey) and (self.Eating or self:Touches(prey)) then return end

	local mins, maxs = self.Mat.mins, self.Mat.maxs
	local best, bestNode, bestScore
	local function Sniff(ent)
		if self.Touching[ent] or not self:Perceivable(ent, true) then return end
		local reach = range * Strength(ent, EvilFungus.Speed(ent)) * Hurt(ent)
		-- Someone flying about breathes like anyone else. It just has to know to check up there.
		if ent:IsPlayer() and Noclipping(ent) then reach = reach * self.Mind:Knows("noclip") end
		if reach <= 0 then return end
		local breath = ent:EyePos()
		local box = Vector(math.Clamp(breath.x, mins.x, maxs.x), math.Clamp(breath.y, mins.y, maxs.y), math.Clamp(breath.z, mins.z, maxs.z))
		if box:DistToSqr(breath) > reach * reach then return end
		local node = self:Closest(breath)
		if not node then return end
		local d = node.pos:Distance(breath)
		if d > reach then return end
		if util.TraceLine({ start = breath, endpos = node.pos + node.normal * 4, mask = MASK_SOLID_BRUSHONLY }).Hit then return end
		local score = d / reach * (ent == prey and SMELL_KEEP or 1)
		if not bestScore or score < bestScore then best, bestNode, bestScore = ent, node, score end
	end
	for _, ply in ipairs(player.GetAll()) do Sniff(ply) end
	for ent in pairs(EvilFungus.Creatures) do
		if IsValid(ent) then Sniff(ent) end
	end
	if not best then return end

	if best ~= prey then self.NextDecide = 0 end
	self.Prey, self.PreyNode, self.PreyFrom, self.FeltAt, self.Smelled = best, bestNode, nil, now, best
end

local function Eaten(ent, by)
	for colony in pairs(EvilFungus.Colonies) do
		if colony ~= by and IsValid(colony) and not colony.Absorbed and colony.Touching and colony.Touching[ent] then return true end
	end
	return false
end

function ENT:Scavenge(now)
	local had = self.Carrion
	local still = IsValid(had) and self:Perceivable(had) and not Eaten(had, self)
	if still and now < (self.NextScavenge or 0) then return had end
	self.NextScavenge = now + SCAVENGE_INTERVAL
	self.Carrion = nil
	local range = EvilFungus.Setting("scavenge")
	if range <= 0 or not self.Mat.mins then return end

	local mins, maxs = self.Mat.mins, self.Mat.maxs
	local best, bestScore
	for ent in pairs(EvilFungus.Foods) do
		if IsValid(ent) and ent:GetClass() == "prop_ragdoll" and not Eaten(ent, self) and self:Perceivable(ent) then
			local pos = ent:GetPos()
			local box = Vector(math.Clamp(pos.x, mins.x, maxs.x), math.Clamp(pos.y, mins.y, maxs.y), math.Clamp(pos.z, mins.z, maxs.z))
			if box:DistToSqr(pos) <= range * range then
				local node = self:Closest(pos)
				local d = node and node.pos:Distance(pos)
				if d and d <= range and not util.TraceLine({ start = pos + CARRION_LIFT, endpos = node.pos + node.normal * 4, mask = MASK_SOLID_BRUSHONLY }).Hit then
					local score = d * (ent == had and CARRION_KEEP or 1)
					if not bestScore or score < bestScore then best, bestScore = ent, score end
				end
			end
		end
	end
	self.Carrion = best
	return best
end

local function Grounded(ent)
	if ent:IsPlayer() or ent:IsNPC() then return EvilFungus.OnGround(ent) end
	if ent:IsNextBot() then return ent.loco ~= nil and ent.loco:IsOnGround() end
	local center = ent:WorldSpaceCenter()
	local mins = ent:WorldSpaceAABB()
	return util.TraceLine({ start = center, endpos = Vector(center.x, center.y, mins.z - SHAKE_GAP), filter = ent, mask = MASK_SOLID }).Hit
end

-- How hard something shakes the ground it's moving along. Faster is harder, and a can rolling past is quieter than a car.
local function Shaking(ent)
	local heavy
	if ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot() or ent:IsVehicle() then
		heavy = 1
	elseif ent:GetMoveType() == MOVETYPE_VPHYSICS and not ent.EvilFungusSleeper and not IsValid(ent:GetParent()) then
		local phys = ent:GetPhysicsObject()
		if not IsValid(phys) or phys:IsAsleep() then return 0 end
		heavy = Lerp(math.Clamp(Kilos(ent) / LANDING_KG, 0, 1), LANDING[1], LANDING[2])
	else
		return 0
	end
	local speed = EvilFungus.Speed(ent)
	if speed < SHAKE_MIN or not Grounded(ent) then return 0 end
	return heavy * math.min(SHAKE_MAX, speed / SHAKE_SPEED)
end

-- Anything moving along the ground near it comes through the ground to the mat's edge.
-- What it can take, it goes after where the shaking came from. Anything else it just goes to look at.
function ENT:Shake(now)
	local range = EvilFungus.Setting("vibration")
	if range <= 0 or now < self.NextShake or not self.Mat.mins then return end
	self.NextShake = now + SHAKE_INTERVAL

	local mins, maxs = self.Mat.mins, self.Mat.maxs
	local far = range * SHAKE_MAX * LANDING[2]
	local pad = Vector(far, far, far)
	local prey, lure = {}, {}
	for _, ent in ipairs(ents.FindInBox(mins - pad, maxs + pad)) do
		if not self.Touching[ent] then
			local shake = Shaking(ent)
			local reach = range * shake
			local pos = ent:GetPos()
			local box = Vector(math.Clamp(pos.x, mins.x, maxs.x), math.Clamp(pos.y, mins.y, maxs.y), math.Clamp(pos.z, mins.z, maxs.z))
			if shake > 0 and box:DistToSqr(pos) <= reach * reach then
				local node = self:Closest(pos)
				local d = node and node.pos:Distance(pos)
				if d and d <= reach then
					local who = ent:IsVehicle() and ent.GetDriver and ent:GetDriver() or ent
					local pick
					if IsValid(who) and self:Perceivable(who) then
						pick = prey
					elseif not (IsValid(who) and (who:IsPlayer() or Creature(who))) then
						pick = lure
					end
					local score = d / reach
					if pick and (not pick.score or score < pick.score) then
						pick.score, pick.ent, pick.node, pick.pos, pick.d = score, who, node, pos, d
					end
				end
			end
		end
	end

	local speed = self:WaveSpeed()
	if prey.ent and #self.Pending < MAX_PENDING then
		self.Pending[#self.Pending + 1] = { at = now + prey.d / speed, ent = prey.ent, node = prey.node, from = prey.pos }
	elseif lure.ent and #self.Pending < MAX_PENDING then
		self.Pending[#self.Pending + 1] = { at = now + lure.d / speed, lure = lure.pos }
	end
end

function ENT:Ripple(node, now)
	if not self:Debugging() then return end
	local dist = self.Mat:Distances({ [node] = 0 }, function(e) return e.len end, RIPPLE_RANGE)
	self.Waves[#self.Waves + 1] = { dist = dist, start = now, reach = RIPPLE_RANGE, speed = self:WaveSpeed() }
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
		self.PreyFrom = other.PreyFrom
	end
	other:InitFeel()
end

function ENT:Felt(ent, node, now, from)
	if not IsValid(ent) or node.dead or not self:Perceivable(ent, self:Touches(ent)) then return end
	local prey = self.Prey
	if IsValid(prey) and prey ~= ent then
		if self.Eating then return end
		-- Whoever's on it or on the air beats a rumble from somewhere off the mat.
		if from and (self:Touches(prey) or self.Smelled == prey) then return end
	end
	self.Prey, self.PreyNode, self.PreyFrom, self.FeltAt = ent, node, from, now
	self.NextDecide = 0
end

-- Something it can't eat moved nearby. Nothing better to do, so it goes and has a look.
function ENT:Lured(pos)
	if self.Hunting or self.Tending then return end
	self.Lure = pos
	self.NextDecide = 0
end

function ENT:Feed(ent, node, dt)
	local mat = self.Mat
	local m = 0
	local at = (node.air or node.up > STANDING) and ent:GetPos() or node.pos
	mat:Near(at, GRIP_RADIUS, function(n) m = m + n.m end)

	if ent:IsPlayer() then
		local drag = math.Clamp((m - DRAG_MASS[1]) / (DRAG_MASS[2] - DRAG_MASS[1]), 0, 1) * EvilFungus.Setting("grip")
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
		local s = EvilFungus.Sleepers[rag]
		if not IsValid(rag) then
			self.Claimed[rag] = nil
		elseif not (s and s.corpse) then
			local node = mat:Nearest(rag:GetPos(), SLEEPER_RADIUS)
			if node then mat:SetMass(node, node.m + BREATH_GAIN * dt) end
		end
	end
end

-- What can't fight back just rots away into it.
function ENT:Digest(ent, node, dt)
	local mat = self.Mat
	local m = 0
	mat:Near(ent:GetPos(), GRIP_RADIUS, function(n) m = m + n.m end)
	if m < GRAB_MASS then return end
	if ent:GetClass() == "prop_ragdoll" then
		if ent == self.Prey then self.Eating = nil end
		EvilFungus.Sleep.Wrap(ent, self)
		return
	end
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
