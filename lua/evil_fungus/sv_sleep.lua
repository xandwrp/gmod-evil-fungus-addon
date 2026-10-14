EvilFungus = EvilFungus or {}
local Sleep = EvilFungus.Sleep or { drowsy = {}, sleepers = {} }
EvilFungus.Sleep = Sleep
EvilFungus.Sleepers = Sleep.sleepers

local UPDATE = 0.1
local WEAR_OFF = 8
local DOSE_FRESH = 0.3
local SETTLE_TIME = 4
local SETTLED = 8

local function Drowsy(ent, d)
	ent.EvilFungusDrowsy = d
	if ent:IsPlayer() then ent:SetNW2Float(EvilFungus.DROWSY_VAR, d) end
end

local function Pose(rag, ent)
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		local m = ent:GetBoneMatrix(rag:TranslatePhysBoneToBone(i))
		if IsValid(phys) and m then
			phys:SetPos(m:GetTranslation())
			phys:SetAngles(m:GetAngles())
			phys:Wake()
		end
	end
end

local function Body(ent)
	local rag = ents.Create("prop_ragdoll")
	if not IsValid(rag) then return end
	rag.EvilFungusSleeper = true
	rag:SetModel(ent:GetModel())
	rag:SetPos(ent:GetPos())
	rag:SetAngles(ent:GetAngles())
	rag:SetSkin(ent:GetSkin())
	rag:SetColor(ent:GetColor())
	rag:SetMaterial(ent:GetMaterial())
	for _, group in ipairs(ent:GetBodyGroups()) do
		rag:SetBodygroup(group.id, ent:GetBodygroup(group.id))
	end
	if ent:IsPlayer() then rag:SetNW2Vector(EvilFungus.COLOR_VAR, ent:GetPlayerColor()) end
	rag:Spawn()
	rag:Activate()

	local ok, err = pcall(Pose, rag, ent)
	if not ok or rag:GetPhysicsObjectCount() == 0 then
		if not ok then ErrorNoHalt("Evil Fungus couldn't lay a sleeper down: ", tostring(err), "\n") end
		rag:Remove()
		return
	end
	rag:SetCollisionGroup(COLLISION_GROUP_WEAPON)
	return rag
end

-- Builds up while the fibers are on you and wears off once they aren't.
function EvilFungus.Sedate(ent, amount, fungus)
	ent.EvilFungusDosedAt = CurTime()
	Sleep.drowsy[ent] = true
	Drowsy(ent, math.min(1, (ent.EvilFungusDrowsy or 0) + amount))
	if ent.EvilFungusDrowsy < 1 then return false end
	Sleep.Under(ent, fungus)
	return true
end

-- As far as the game is concerned they died. The body stays, and it's the fungus's now.
function Sleep.Under(ent, fungus)
	local rag = Body(ent)
	Sleep.drowsy[ent] = nil
	Drowsy(ent, 0)
	if rag then
		rag.EvilFungusSince = CurTime()
		if IsValid(fungus) then fungus:Claim(rag) else Sleep.sleepers[rag] = true end
	end

	if ent:IsPlayer() then
		ent:KillSilent()
		ent:AddDeaths(1)
		hook.Run("PlayerDeath", ent, fungus, fungus)
		if rag then
			ent:Spectate(OBS_MODE_CHASE)
			ent:SpectateEntity(rag)
		end
		ent:SetNW2Bool(EvilFungus.ASLEEP_VAR, true)
	else
		ent:SetHealth(0)
		hook.Run("OnNPCKilled", ent, fungus, fungus)
		ent:Remove()
	end
	return rag
end

local function Owned(ent)
	return Sleep.sleepers[ent] ~= nil
end

local nextUpdate = 0

hook.Add("Think", "EvilFungusSleep", function()
	local now = CurTime()
	if now < nextUpdate then return end
	nextUpdate = now + UPDATE

	for ent in pairs(Sleep.drowsy) do
		if not IsValid(ent) then
			Sleep.drowsy[ent] = nil
		elseif now - (ent.EvilFungusDosedAt or 0) > DOSE_FRESH then
			local d = ent.EvilFungusDrowsy - UPDATE / WEAR_OFF
			if d <= 0 then
				d = 0
				Sleep.drowsy[ent] = nil
			end
			Drowsy(ent, d)
		end
	end

	for rag in pairs(Sleep.sleepers) do
		if not IsValid(rag) then
			Sleep.sleepers[rag] = nil
		elseif not rag.EvilFungusSettled and now - rag.EvilFungusSince > SETTLE_TIME then
			local root = rag:GetPhysicsObject()
			if not IsValid(root) or root:GetVelocity():Length() < SETTLED then
				rag.EvilFungusSettled = true
				for i = 0, rag:GetPhysicsObjectCount() - 1 do
					local phys = rag:GetPhysicsObjectNum(i)
					if IsValid(phys) then phys:EnableMotion(false) end
				end
			end
		end
	end
end)

hook.Add("PhysgunPickup", "EvilFungusSleep", function(_, ent) if Owned(ent) then return false end end)
hook.Add("GravGunPickupAllowed", "EvilFungusSleep", function(_, ent) if Owned(ent) then return false end end)
hook.Add("CanTool", "EvilFungusSleep", function(_, tr) if IsValid(tr.Entity) and Owned(tr.Entity) then return false end end)
hook.Add("CanProperty", "EvilFungusSleep", function(_, _, ent) if Owned(ent) then return false end end)
hook.Add("EntityTakeDamage", "EvilFungusSleep", function(ent) if Owned(ent) then return true end end)

hook.Add("PlayerSpawn", "EvilFungusSleep", function(ply)
	ply:SetNW2Bool(EvilFungus.ASLEEP_VAR, false)
	Drowsy(ply, 0)
	Sleep.drowsy[ply] = nil
end)
