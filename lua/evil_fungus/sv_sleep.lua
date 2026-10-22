EvilFungus = EvilFungus or {}
local Sleep = EvilFungus.Sleep or { drowsy = {}, sleepers = {} }
Sleep.dreamers = Sleep.dreamers or {}
EvilFungus.Sleep = Sleep
EvilFungus.Sleepers = Sleep.sleepers

local LOOSE, CONSUMING, KEPT, FREED = EvilFungus.LOOSE, EvilFungus.CONSUMING, EvilFungus.KEPT, EvilFungus.FREED

local UPDATE = 0.1
local CONSUME_UPDATE = 1
local WEAR_OFF = 8
local DOSE_FRESH = 0.3

local TOUCH_RADIUS = 24
local TOUCH_PAD = Vector(96, 96, 96)
local LET_GO = 3
local HIT_GRACE = 2
local SLAM_SPEED = 250
local WAKE_AFTER = 10

local SHRINK_SPAN = 0.25
local FOOD_PER_KG = 0.5
local FOOD_VALUE = { 10, 60 }
local PALE = { 215, 205, 190 }
local CHAR = { 45, 38, 32 }
local CHAR_TIME = 8

local FEAR_TIME = 90

local KEPT_VAR = "EvilCrawlerKept"
local HEAD_PART = 1

local STANDING_OFFSETS = { Vector(0, 0, 0), Vector(32, 0, 0), Vector(-32, 0, 0), Vector(0, 32, 0), Vector(0, -32, 0) }

local function Drowsy(ent, d)
	ent.EvilFungusDrowsy = d
	if ent:IsPlayer() then ent:SetNW2Float(EvilFungus.DROWSY_VAR, d) end
end

local function Wakeful(ply)
	Sleep.dreamers[ply] = nil
	ply:SetNW2Bool(EvilFungus.ASLEEP_VAR, false)
end

local function Kilos(ent)
	local kg = 0
	for i = 0, ent:GetPhysicsObjectCount() - 1 do
		local phys = ent:GetPhysicsObjectNum(i)
		if IsValid(phys) then kg = kg + phys:GetMass() end
	end
	return kg
end

local function Pose(rag, ent)
	local vel = ent:GetVelocity()
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		local m = ent:GetBoneMatrix(rag:TranslatePhysBoneToBone(i))
		if IsValid(phys) and m then
			phys:SetPos(m:GetTranslation())
			phys:SetAngles(m:GetAngles())
			phys:SetVelocity(vel)
			phys:Wake()
		end
	end
end

local function Body(ent)
	local rag = ents.Create("prop_ragdoll")
	if not IsValid(rag) then return end
	rag.EvilFungusSleeper = true
	rag.DoNotDuplicate = true
	rag:SetModel(ent:GetModel())
	rag:SetPos(ent:GetPos())
	rag:SetAngles(ent:GetAngles())
	rag:SetSkin(ent:GetSkin())
	rag:SetRenderMode(ent:GetRenderMode())
	rag:SetColor(ent:GetColor())
	rag:SetMaterial(ent:GetMaterial())
	for _, group in ipairs(ent:GetBodyGroups()) do
		rag:SetBodygroup(group.id, ent:GetBodygroup(group.id))
	end
	if ent:IsPlayer() then rag:SetNW2Vector(EvilFungus.COLOR_VAR, ent:GetPlayerColor()) end
	rag:Spawn()
	rag:Activate()
	if ent:GetNoDraw() then rag:SetNoDraw(true) end
	if ent:HasFlexManipulatior() then
		rag:SetFlexScale(ent:GetFlexScale())
		for i = 0, math.min(ent:GetFlexNum(), rag:GetFlexNum()) - 1 do rag:SetFlexWeight(i, ent:GetFlexWeight(i)) end
	end

	local ok, err = pcall(Pose, rag, ent)
	if not ok or rag:GetPhysicsObjectCount() == 0 then
		if not ok then ErrorNoHalt("Evil Fungus couldn't lay a sleeper down: ", tostring(err), "\n") end
		rag:Remove()
		return
	end
	rag:SetCollisionGroup(COLLISION_GROUP_WEAPON)
	return rag
end

local function Parts(ent, list)
	list = list or {}
	for _, child in ipairs(ent:GetChildren()) do
		if IsValid(child) then
			list[#list + 1] = child
			Parts(child, list)
		end
	end
	return list
end

local function Worn(npc)
	local list, seen = Parts(npc), { [npc] = true }
	for _, part in ipairs(list) do seen[part] = true end
	local function Add(ent)
		if not isentity(ent) or not IsValid(ent) or seen[ent] or ent:IsPlayer() or ent:IsNPC() then return end
		if not ent:IsEffectActive(EF_BONEMERGE) or IsValid(ent:GetParent()) then return end
		seen[ent] = true
		list[#list + 1] = ent
		for _, part in ipairs(Parts(ent)) do
			if not seen[part] then
				seen[part] = true
				list[#list + 1] = part
			end
		end
	end
	for _, v in pairs(npc:GetTable()) do
		if istable(v) then
			for _, w in pairs(v) do Add(w) end
		else
			Add(v)
		end
	end
	for _, ent in ipairs(ents.GetAll()) do
		if ent:GetOwner() == npc then Add(ent) end
	end
	return list
end

local function Merged(part, npc)
	while IsValid(part) and part ~= npc do
		if part:IsWeapon() or not part:IsEffectActive(EF_BONEMERGE) then return false end
		part = part:GetParent()
	end
	return true
end

local function Shade(ent, color)
	ent:SetColor(Color(color.r, color.g, color.b, ent:GetColor().a))
end

local function Tint(rag, color)
	Shade(rag, color)
	for _, part in ipairs(rag.EvilFungusParts or {}) do
		if IsValid(part) then Shade(part, color) end
	end
end

local function Dress(rag, npc, worn)
	rag.EvilFungusParts = {}
	for _, part in ipairs(worn) do
		local model = IsValid(part) and part:GetModel()
		if model and Merged(part, npc) and not part:GetNoDraw() and util.IsValidModel(model) then
			local copy = ents.Create("prop_dynamic")
			if IsValid(copy) then
				copy:SetModel(model)
				copy:SetKeyValue("solid", "0")
				copy:SetPos(rag:GetPos())
				copy:SetParent(rag)
				copy:AddEffects(EF_BONEMERGE)
				copy:Spawn()
				copy:SetSkin(part:GetSkin())
				for _, group in ipairs(part:GetBodyGroups()) do
					copy:SetBodygroup(group.id, part:GetBodygroup(group.id))
				end
				copy:SetMaterial(part:GetMaterial())
				copy:SetRenderMode(part:GetRenderMode())
				copy:SetColor(part:GetColor())
				copy.DoNotDuplicate = true
				rag:DeleteOnRemove(copy)
				rag.EvilFungusParts[#rag.EvilFungusParts + 1] = copy
			end
		end
	end
end

local function Hide(npc, worn)
	npc.EvilFungusHadNoTarget = npc:IsFlagSet(FL_NOTARGET)
	npc.EvilFungusHadNoDraw = npc:GetNoDraw()
	npc.EvilFungusMoveType = npc:GetMoveType()
	npc.EvilFungusParts = {}
	for _, part in ipairs(worn) do
		if IsValid(part) and not part:GetNoDraw() then
			part:SetNoDraw(true)
			npc.EvilFungusParts[#npc.EvilFungusParts + 1] = part
		end
	end
	npc:SetNoDraw(true)
	npc:DrawShadow(false)
	npc:SetNotSolid(true)
	npc:SetMoveType(MOVETYPE_NONE)
	npc:AddFlags(FL_NOTARGET)
	npc:AddEFlags(EFL_NO_THINK_FUNCTION)
	npc:ClearSchedule()
	npc:SetEnemy(NULL)
end

local function Show(npc, spot)
	npc:SetPos(spot)
	npc:SetAngles(Angle(0, math.Rand(0, 360), 0))
	npc:RemoveEFlags(EFL_NO_THINK_FUNCTION)
	npc:SetMoveType(npc.EvilFungusMoveType or MOVETYPE_STEP)
	npc:SetNotSolid(false)
	npc:SetNoDraw(npc.EvilFungusHadNoDraw or false)
	npc:DrawShadow(true)
	for _, part in ipairs(npc.EvilFungusParts or {}) do
		if IsValid(part) then part:SetNoDraw(false) end
	end
	npc.EvilFungusParts = nil
	if not npc.EvilFungusHadNoTarget then npc:RemoveFlags(FL_NOTARGET) end
end

local function StandingSpot(ent, rag)
	local pos = rag:GetPos()
	local mins, maxs, mask = ent:OBBMins(), ent:OBBMaxs(), MASK_NPCSOLID
	if ent:IsPlayer() then
		mins, maxs = ent:GetHull()
		mask = MASK_PLAYERSOLID
	end
	for _, offset in ipairs(STANDING_OFFSETS) do
		local from = pos + offset + Vector(0, 0, 8)
		local tr = util.TraceHull({ start = from, endpos = from - Vector(0, 0, 96), mins = mins, maxs = maxs, mask = mask, filter = { ent, rag } })
		if not tr.StartSolid then return tr.HitPos end
	end
	return pos
end

local function SetStage(s, stage)
	s.stage, s.stageAt = stage, CurTime()
	s.rag:SetNW2Int(EvilFungus.STAGE_VAR, stage)
	s.rag:SetNW2Float(EvilFungus.STAGE_AT_VAR, s.stageAt)
end

-- Whoever last laid a hand on a sleeper, or hit one, or threw something at one.
local function Touched(s, by)
	if IsValid(by) and by:IsPlayer() then s.by, s.byAt = by, CurTime() end
end

local function Thrower(ent)
	if ent:IsPlayer() then return ent end
	return ent.GetPhysicsAttacker and ent:GetPhysicsAttacker(HIT_GRACE)
end

-- Somebody had a hand in them coming off it, rather than them just rolling off.
local function Tugged(s, now)
	return s.gripped or now - (s.byAt or -math.huge) < LET_GO + HIT_GRACE
end

local function Rescued(s)
	local fungus = s.fungus
	if IsValid(s.by) and IsValid(fungus) then fungus.Mind:Watch(s.by, "rescue", 1) end
	Sleep.Free(s)
end

-- Outermost parts go first, the trunk last, and the head not at all.
local function Schedule(rag, whole)
	local head = not whole and EvilFungus.HeadBone(rag)
	local list, deepest = {}, 1
	for bone = 0, rag:GetBoneCount() - 1 do
		if not (head and EvilFungus.UnderHead(rag, bone, head)) then
			local depth, p = 0, rag:GetBoneParent(bone)
			while p and p >= 0 do
				depth = depth + 1
				p = rag:GetBoneParent(p)
			end
			list[#list + 1] = { bone = bone, depth = depth, scale = 1 }
			deepest = math.max(deepest, depth)
		end
	end
	for _, b in ipairs(list) do b.start = (1 - b.depth / deepest) * (1 - SHRINK_SPAN) end
	return list
end

local function Freeze(rag)
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		if IsValid(phys) then phys:EnableMotion(false) end
	end
end

local function Consume(s)
	SetStage(s, CONSUMING)
	if s.schedule then return end
	s.schedule = Schedule(s.rag, s.corpse)
	s.food = math.Clamp(Kilos(s.rag) * FOOD_PER_KG, FOOD_VALUE[1], FOOD_VALUE[2])
	s.fed, s.progress, s.held = 0, 0, 0
end

local function Gone(s, by)
	local owner = s.owner
	s.owner = nil
	if not IsValid(owner) then return end
	if owner:IsPlayer() then
		if owner.EvilFungusHeld == s then owner.EvilFungusHeld = nil end
	else
		by = IsValid(by) and by or s.fungus
		owner.EvilFungusAsleep = nil
		owner:SetHealth(0)
		hook.Run("OnNPCKilled", owner, by, by)
		owner:Remove()
	end
end

local function Keep(s)
	SetStage(s, KEPT)
	Freeze(s.rag)
	Gone(s)
end

function Sleep.Raise(s)
	local rag = s.rag
	Sleep.sleepers[rag] = nil
	if IsValid(s.fungus) then s.fungus:Unclaim(rag) end
	rag:SetNW2Int(KEPT_VAR, 0)
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		if IsValid(phys) then
			phys:EnableMotion(true)
			phys:Wake()
		end
	end
end

function Sleep.Free(s)
	if s.stage >= KEPT then return end
	SetStage(s, FREED)
	if IsValid(s.fungus) then s.fungus:Unclaim(s.rag) end
end

local function Wake(s)
	local rag, owner = s.rag, s.owner
	Sleep.sleepers[rag] = nil
	rag.EvilFungusSleeper = nil
	rag.DoNotDuplicate = nil
	rag:SetNW2Int(EvilFungus.STAGE_VAR, 0)
	rag:SetNW2Int(KEPT_VAR, 0)
	rag:SetNW2Bool(EvilFungus.WHOLE_VAR, false)
	for _, b in ipairs(s.schedule or {}) do
		if b.scale > 0 then rag:ManipulateBoneScale(b.bone, Vector(1, 1, 1)) end
	end

	local rescued = not s.mauled and IsValid(owner) and (not owner:IsPlayer() or owner.EvilFungusHeld == s)
	if not rescued then
		Gone(s)
		if EvilFungus.Food(rag) then EvilFungus.Foods[rag] = true end
		return
	end

	local spot = StandingSpot(owner, rag)
	if owner:IsPlayer() then
		local kit = s.kit or {}
		owner.EvilFungusHeld = nil
		owner.EvilFungusWaking = true
		owner:UnSpectate()
		owner:Spawn()
		owner.EvilFungusWaking = nil
		Wakeful(owner)
		owner:SetPos(spot)
		owner:SetHealth(s.health or owner:GetMaxHealth())
		owner:SetArmor(kit.armor or 0)
		owner:StripWeapons()
		owner:RemoveAllAmmo()
		for _, w in ipairs(kit.weapons or {}) do
			local wep = owner:Give(w.class, true)
			if IsValid(wep) then
				wep:SetClip1(w.clip1)
				wep:SetClip2(w.clip2)
			end
		end
		for id, count in pairs(kit.ammo or {}) do owner:SetAmmo(count, id) end
		if kit.active then owner:SelectWeapon(kit.active) end
	else
		owner.EvilFungusAsleep = nil
		Show(owner, spot)
		Evil.Scare(owner, FEAR_TIME)
	end
	rag:Remove()
end

local function Surrender(s, crawler)
	local rag = s.rag
	Sleep.sleepers[rag] = nil
	if IsValid(s.fungus) then s.fungus:Unclaim(rag) end
	rag.EvilFungusSleeper = nil
	rag.DoNotDuplicate = nil
	rag:SetNW2Int(EvilFungus.STAGE_VAR, 0)
	rag:SetNW2Int(KEPT_VAR, 0)
	rag:SetNW2Bool(EvilFungus.WHOLE_VAR, false)
	for _, b in ipairs(s.schedule or {}) do
		if b.scale > 0 and rag:GetManipulateBoneScale(b.bone).x > 0 then rag:ManipulateBoneScale(b.bone, Vector(1, 1, 1)) end
	end
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		if IsValid(phys) then
			phys:EnableMotion(true)
			phys:Wake()
		end
	end
	s.mauled = true
	Gone(s, crawler)
	if EvilFungus.Food(rag) then EvilFungus.Foods[rag] = true end
end

function Sleep.Burn(rag)
	local s = Sleep.sleepers[rag]
	if not s then return end
	Sleep.sleepers[rag] = nil
	if IsValid(s.fungus) then s.fungus:Unclaim(rag) end
	rag.EvilFungusSleeper = nil
	rag.DoNotDuplicate = nil
	rag.EvilFungusBurnt = true
	rag:SetNW2Int(EvilFungus.STAGE_VAR, 0)
	rag:SetNW2Int(KEPT_VAR, 0)
	rag:SetNW2Bool(EvilFungus.WHOLE_VAR, false)
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		if IsValid(phys) then
			phys:EnableMotion(true)
			phys:Wake()
		end
	end
	s.mauled = true
	Gone(s)
	rag:Ignite(CHAR_TIME)
	timer.Simple(CHAR_TIME, function()
		if IsValid(rag) then Tint(rag, Color(CHAR[1], CHAR[2], CHAR[3])) end
	end)
end

-- Builds up while the fibers are on you and wears off once they aren't.
function EvilFungus.Sedate(ent, amount, fungus)
	if EvilFungus.CrawlerHas(ent) or Evil.Owner(ent) then return false end
	ent.EvilFungusDosedAt = CurTime()
	Sleep.drowsy[ent] = true
	Drowsy(ent, math.min(1, (ent.EvilFungusDrowsy or 0) + amount))
	if ent.EvilFungusDrowsy < 1 then return false end
	return true, Sleep.Under(ent, fungus)
end

-- As far as the game is concerned a player just died. The body stays, and it's the fungus's now.
function Sleep.Under(ent, fungus)
	Sleep.drowsy[ent] = nil
	Drowsy(ent, 0)
	local rag = Body(ent)

	if ent:IsPlayer() then
		local s
		if rag then
			local active = ent:GetActiveWeapon()
			local kit = { armor = ent:Armor(), ammo = ent:GetAmmo(), weapons = {}, active = IsValid(active) and active:GetClass() }
			for _, wep in ipairs(ent:GetWeapons()) do
				kit.weapons[#kit.weapons + 1] = { class = wep:GetClass(), clip1 = wep:Clip1(), clip2 = wep:Clip2() }
			end
			s = { kit = kit, health = ent:Health() }
		end
		ent:KillSilent()
		ent:AddDeaths(1)
		hook.Run("PlayerDeath", ent, fungus, fungus)
		if not rag then return end
		ent:SetNW2Bool(EvilFungus.ASLEEP_VAR, true)
		ent:Spectate(OBS_MODE_CHASE)
		ent:SpectateEntity(rag)
		Sleep.dreamers[ent] = rag
		ent.EvilFungusHeld = s
		Sleep.Hold(rag, ent, fungus, s)
		return rag
	end

	if not rag then
		ent:SetHealth(0)
		hook.Run("OnNPCKilled", ent, fungus, fungus)
		ent:Remove()
		return
	end
	local worn = Worn(ent)
	Dress(rag, ent, worn)
	Hide(ent, worn)
	ent.EvilFungusAsleep = rag
	Sleep.Hold(rag, ent, fungus, {})
	return rag
end

-- Wherever any part of them is lying on it, it has them.
local function Contact(rag)
	local pos = rag:GetPos()
	local best, bestD, owner
	for colony in pairs(EvilFungus.Colonies or {}) do
		local mat = IsValid(colony) and not colony.Absorbed and colony.Mat
		if mat and mat.mins and pos:WithinAABox(mat.mins - TOUCH_PAD, mat.maxs + TOUCH_PAD) then
			for i = 0, rag:GetPhysicsObjectCount() - 1 do
				local phys = rag:GetPhysicsObjectNum(i)
				if IsValid(phys) then
					local node, d = mat:Nearest(phys:GetPos(), TOUCH_RADIUS)
					if node and (not bestD or d < bestD) then best, bestD, owner = node, d, colony end
				end
			end
		end
	end
	return best, owner
end

-- Eaten while they're on it, left alone while they're not, and let go if they stay off it.
local function Check(s, now)
	local node, colony = Contact(s.rag)
	if not node then
		if s.stage == CONSUMING then SetStage(s, LOOSE) end
		if IsValid(s.hauler) then return end
		if now - s.stageAt >= LET_GO then
			if Tugged(s, now) and not s.corpse then Rescued(s) else Sleep.Free(s) end
		end
		return
	end

	if colony ~= s.fungus then
		if IsValid(s.fungus) then s.fungus:Unclaim(s.rag) end
		colony:Claim(s.rag)
	end
	if s.nest ~= node then
		s.nest = node
		s.rag:SetNW2Vector(EvilFungus.NEST_VAR, node.pos)
		s.rag:SetNW2Vector(EvilFungus.NEST_UP_VAR, node.normal)
	end
	if s.stage == LOOSE then Consume(s) end
end

function Sleep.Hold(rag, owner, fungus, s)
	s.rag, s.owner = rag, owner
	s.brain = EvilFungus.Brain(owner)
	s.profile = owner:IsPlayer() and EvilFungus.Souls:Profile(owner) or nil
	s.since = CurTime()
	rag:SetNW2Float(EvilFungus.SINCE_VAR, s.since)
	rag:SetNW2Int(KEPT_VAR, bit.lshift(1, HEAD_PART - 1))
	Sleep.sleepers[rag] = s
	SetStage(s, LOOSE)
	if IsValid(fungus) then fungus:Claim(rag) end
	rag:AddCallback("PhysicsCollide", function(ent, data)
		local held = Sleep.sleepers[ent]
		local hit = data.HitEntity
		if held and IsValid(hit) and not hit:IsWorld() and data.Speed > SLAM_SPEED then Touched(held, Thrower(hit)) end
	end)
	Check(s, s.since)
end

function Sleep.Wrap(rag, fungus)
	EvilFungus.Foods[rag] = nil
	rag.EvilFungusSleeper = true
	rag.DoNotDuplicate = true
	local s = { rag = rag, corpse = true, brain = 0, since = CurTime() }
	rag:SetNW2Float(EvilFungus.SINCE_VAR, s.since)
	rag:SetNW2Int(KEPT_VAR, 0)
	rag:SetNW2Bool(EvilFungus.WHOLE_VAR, true)
	Sleep.sleepers[rag] = s
	SetStage(s, LOOSE)
	if IsValid(fungus) then fungus:Claim(rag) end
	Check(s, s.since)
end

local function Digest(s, now)
	s.progress = math.min(1, s.progress + CONSUME_UPDATE * EvilFungus.TimeScale() / math.max(1, EvilFungus.Setting("consume_time")))
	local k = s.progress
	local min = EvilFungus.MIN_SCALE
	for _, b in ipairs(s.schedule) do
		if b.scale > 0 and s.rag:GetManipulateBoneScale(b.bone).x == 0 then b.scale = 0 end
		local scale = Lerp(math.Clamp((k - b.start) / SHRINK_SPAN, 0, 1), 1, min)
		if b.scale > 0 and (math.abs(scale - b.scale) > 0.01 or scale == min and b.scale ~= min) then
			b.scale = scale
			s.rag:ManipulateBoneScale(b.bone, Vector(scale, scale, scale))
		end
	end
	Tint(s.rag, Color(Lerp(k, 255, PALE[1]), Lerp(k, 255, PALE[2]), Lerp(k, 255, PALE[3])))
	s.rag:SetNW2Float(EvilFungus.CONSUMED_VAR, k)

	local due = s.food * k
	local fungus, nest = s.fungus, s.nest
	if due > s.fed and IsValid(fungus) and nest and not nest.dead then
		fungus.Mat:SetMass(nest, nest.m + due - s.fed)
	end
	s.fed = due
	local hosts = EvilFungus.Hosts
	if hosts and s.stage == KEPT then
		if s.rise == nil and EvilFungus.Setting("hosts") > 0 then s.rise = hosts.Roll(s) end
		if s.rise and k >= s.rise then
			hosts.Rise(s)
			return
		end
	end
	if k >= 1 then
		s.done = true
		if IsValid(fungus) then
			fungus.Mind:Keep(s.brain)
			if s.profile then fungus.Mind:Learn(s.profile) end
		end
	end
end

local nextUpdate, nextConsume = 0, 0

hook.Add("Think", "EvilFungusSleep", function()
	local now = CurTime()
	if now >= nextUpdate then
		nextUpdate = now + UPDATE
		for ent in pairs(Sleep.drowsy) do
			if not IsValid(ent) then
				Sleep.drowsy[ent] = nil
			elseif now - (ent.EvilFungusDosedAt or 0) > DOSE_FRESH then
				local d = ent.EvilFungusDrowsy - UPDATE * EvilFungus.TimeScale() / WEAR_OFF
				if d <= 0 then
					d = 0
					Sleep.drowsy[ent] = nil
				end
				Drowsy(ent, d)
			end
		end

		local rescue = EvilFungus.Setting("rescue_time")
		local scale = EvilFungus.TimeScale()
		for rag, s in pairs(Sleep.sleepers) do
			if not IsValid(rag) then
				Sleep.sleepers[rag] = nil
			elseif EvilFungus.CrawlerHas(rag) then
				Surrender(s, rag.EvilCrawlerVictim)
			else
				local owner = s.owner
				if IsValid(owner) and not owner:IsPlayer() then owner:SetPos(rag:GetPos()) end
				if s.stage == LOOSE or s.stage == CONSUMING then Check(s, now) end
				if s.stage == CONSUMING then s.held = s.held + UPDATE * scale end
				if s.stage == CONSUMING and s.held >= rescue then
					Keep(s)
				elseif s.stage == FREED and now - s.stageAt >= WAKE_AFTER then
					Wake(s)
				end
			end
		end

		for ply, rag in pairs(Sleep.dreamers) do
			local s = IsValid(ply) and IsValid(rag) and Sleep.sleepers[rag]
			if not IsValid(ply) then
				Sleep.dreamers[ply] = nil
			elseif ply:Alive() or not s or s.done and ply.EvilFungusHeld ~= s then
				Wakeful(ply)
			else
				local target = ply:GetObserverTarget()
				if ply:GetObserverMode() ~= OBS_MODE_CHASE or IsValid(target) and target ~= rag then
					Wakeful(ply)
					if ply.EvilFungusHeld == s then Gone(s) end
				elseif not IsValid(target) and ply.EvilFungusHeld == s then
					ply:SpectateEntity(rag)
				end
			end
		end
	end

	if now >= nextConsume then
		nextConsume = now + CONSUME_UPDATE
		for rag, s in pairs(Sleep.sleepers) do
			if IsValid(rag) and (s.stage == CONSUMING or s.stage == KEPT) and not s.done then Digest(s, now) end
		end
	end
end)

local function Locked(ent)
	local s = Sleep.sleepers[ent]
	return s ~= nil and s.stage == KEPT
end

local function Held(ent)
	return Sleep.sleepers[ent] ~= nil
end

hook.Add("PhysgunPickup", "EvilFungusSleep", function(_, ent) if Locked(ent) then return false end end)
hook.Add("CanPlayerUnfreeze", "EvilFungusSleep", function(_, ent) if Locked(ent) then return false end end)
hook.Add("GravGunPickupAllowed", "EvilFungusSleep", function(_, ent) if Locked(ent) then return false end end)
hook.Add("CanTool", "EvilFungusSleep", function(_, tr) if IsValid(tr.Entity) and Held(tr.Entity) then return false end end)
hook.Add("CanProperty", "EvilFungusSleep", function(_, _, ent) if Held(ent) then return false end end)
hook.Add("EntityTakeDamage", "EvilFungusSleep", function(ent, dmg)
	if ent.EvilFungusAsleep or Locked(ent) then return true end
	local s = Sleep.sleepers[ent]
	if s then Touched(s, dmg:GetAttacker()) end
end)

local function Grabbed(ply, ent)
	local s = Sleep.sleepers[ent]
	if s then
		s.gripped = true
		Touched(s, ply)
	end
end

local function Dropped(ply, ent)
	local s = Sleep.sleepers[ent]
	if s then
		s.gripped = nil
		Touched(s, ply)
	end
end

local function Punted(ply, ent)
	local s = Sleep.sleepers[ent]
	if s then Touched(s, ply) end
end

hook.Add("OnPhysgunPickup", "EvilFungusSleep", Grabbed)
hook.Add("PhysgunDrop", "EvilFungusSleep", Dropped)
hook.Add("GravGunOnPickedUp", "EvilFungusSleep", Grabbed)
hook.Add("GravGunOnDropped", "EvilFungusSleep", Dropped)
hook.Add("GravGunPunt", "EvilFungusSleep", Punted)

hook.Add("PlayerDeathThink", "EvilFungusSleep", function(ply)
	local s = ply.EvilFungusHeld
	if not s then return end
	if EvilFungus.Setting("give_up") == 0 or not ply:KeyPressed(IN_JUMP) then return false end
	Gone(s)
	Wakeful(ply)
end)

hook.Add("EntityRemoved", "EvilFungusSleep", function(ent)
	local s = Sleep.sleepers[ent]
	if not s then return end
	Sleep.sleepers[ent] = nil
	local owner = s.owner
	if not IsValid(owner) then return end
	if owner:IsPlayer() then
		if owner.EvilFungusHeld == s then owner.EvilFungusHeld = nil end
	elseif owner.EvilFungusAsleep then
		owner:Remove()
	end
end)

hook.Add("PlayerSpawn", "EvilFungusSleep", function(ply)
	if ply.EvilFungusWaking then return end
	local s = ply.EvilFungusHeld
	if s then s.owner = nil end
	ply.EvilFungusHeld = nil
	Wakeful(ply)
	Drowsy(ply, 0)
	Sleep.drowsy[ply] = nil
end)

hook.Add("EvilCrawlerAte", "EvilFungusSleep", function(crawler, rag)
	local s = Sleep.sleepers[rag]
	if not s then return end
	local fungus = s.fungus
	Surrender(s, crawler)
	if EvilFungus.Infect then EvilFungus.Infect(crawler, fungus) end
end)
