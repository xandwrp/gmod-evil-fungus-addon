EvilFungus = EvilFungus or {}

EvilFungus.DRAG_VAR = "EvilFungusDrag"
EvilFungus.DROWSY_VAR = "EvilFungusDrowsy"
EvilFungus.ASLEEP_VAR = "EvilFungusAsleep"
EvilFungus.COLOR_VAR = "EvilFungusColor"
EvilFungus.STAGE_VAR = "EvilFungusStage"
EvilFungus.STAGE_AT_VAR = "EvilFungusStageAt"
EvilFungus.NEST_VAR = "EvilFungusNest"
EvilFungus.NEST_UP_VAR = "EvilFungusNestUp"
EvilFungus.CONSUMED_VAR = "EvilFungusConsumed"
EvilFungus.SINCE_VAR = "EvilFungusSince"
EvilFungus.WRAP_VAR = "EvilFungusWrap"
EvilFungus.LANDED_VAR = "EvilFungusLanded"

EvilFungus.POSING, EvilFungus.CONSUMING, EvilFungus.KEPT, EvilFungus.FREED = 1, 2, 3, 4
EvilFungus.MIN_SCALE = 0.2
EvilFungus.HOLD_BONES = {
	pelvis = "ValveBiped.Bip01_Pelvis", chest = "ValveBiped.Bip01_Spine2", head = "ValveBiped.Bip01_Head1",
	lshoulder = "ValveBiped.Bip01_L_UpperArm", rshoulder = "ValveBiped.Bip01_R_UpperArm",
	lelbow = "ValveBiped.Bip01_L_Forearm", relbow = "ValveBiped.Bip01_R_Forearm",
	lhand = "ValveBiped.Bip01_L_Hand", rhand = "ValveBiped.Bip01_R_Hand",
	lknee = "ValveBiped.Bip01_L_Calf", rknee = "ValveBiped.Bip01_R_Calf",
	lfoot = "ValveBiped.Bip01_L_Foot", rfoot = "ValveBiped.Bip01_R_Foot",
}

-- The bone it leaves alone, and everything hanging off it.
function EvilFungus.HeadBone(ent)
	local best, bestDepth
	for i = 0, ent:GetBoneCount() - 1 do
		local name = string.lower(ent:GetBoneName(i) or "")
		if string.find(name, "head", 1, true) then
			local depth, p = 0, ent:GetBoneParent(i)
			while p and p >= 0 do
				depth = depth + 1
				p = ent:GetBoneParent(p)
			end
			if not bestDepth or depth < bestDepth then best, bestDepth = i, depth end
		end
	end
	return best
end

function EvilFungus.UnderHead(ent, bone, head)
	while bone and bone >= 0 do
		if bone == head then return true end
		bone = ent:GetBoneParent(bone)
	end
	return false
end

local DROWSY_SLOW = 0.6

hook.Add("SetupMove", "EvilFungusDrag", function(ply, mv)
	local drag = ply:GetNW2Float(EvilFungus.DRAG_VAR, 0)
	local drowsy = ply:GetNW2Float(EvilFungus.DROWSY_VAR, 0)
	if drag <= 0 and drowsy <= 0 then return end
	local keep = (1 - drag) * (1 - drowsy * DROWSY_SLOW)
	mv:SetMaxSpeed(mv:GetMaxSpeed() * keep)
	mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * keep)
	if keep < 0.4 then mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(IN_JUMP))) end
end)
