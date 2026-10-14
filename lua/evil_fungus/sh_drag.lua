EvilFungus = EvilFungus or {}

EvilFungus.DRAG_VAR = "EvilFungusDrag"
EvilFungus.DROWSY_VAR = "EvilFungusDrowsy"
EvilFungus.ASLEEP_VAR = "EvilFungusAsleep"
EvilFungus.COLOR_VAR = "EvilFungusColor"

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
