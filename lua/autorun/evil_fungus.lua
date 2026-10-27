if SERVER then resource.AddWorkshop("3823740816") end
if not file.Exists("evil_api/init.lua", "LUA") then
	EvilNeedsAPI = EvilNeedsAPI or {}
	EvilNeedsAPI[#EvilNeedsAPI + 1] = "Evil Fungus"
	if #EvilNeedsAPI > 1 then return end

	local API = "3823740816"
	local URL = "https://steamcommunity.com/sharedfiles/filedetails/?id=" .. API
	local RED = Color(255, 90, 90)

	local function Needs()
		return table.concat(EvilNeedsAPI, ", ") .. (#EvilNeedsAPI > 1 and " need" or " needs") .. " Syhgma's Evil API now."
	end

	hook.Add("Initialize", "EvilNeedsAPI", function()
		local fix = SERVER and game.IsDedicated() and "Add it to the server's workshop collection, then restart." or "Subscribe to it, then restart the game."
		MsgC(RED, Needs() .. " " .. fix .. " " .. URL .. "\n")
	end)
	if SERVER then return end

	local function Fix()
		if not game.SinglePlayer() and not LocalPlayer():IsListenServerHost() then return end
		for _, addon in ipairs(engine.GetAddons()) do
			if tostring(addon.wsid) == API then
				if not addon.downloaded then return "Steam is still downloading it, restart the game once it's done." end
				if not addon.mounted then return "It's turned off, turn it on in the Addons menu, then restart the game." end
				return "It's installed but didn't load. Unsubscribe and subscribe to it again, then restart the game."
			end
		end
		return "Subscribe to it, then restart the game."
	end

	hook.Add("InitPostEntity", "EvilNeedsAPI", function()
		local fix = Fix()
		if not fix then
			chat.AddText(RED, Needs() .. " This server doesn't have it, the server owner needs to add it to the server's workshop collection.")
			return
		end
		chat.AddText(RED, Needs() .. " " .. fix)

		local frame = vgui.Create("DFrame")
		frame:SetTitle("Syhgma's Evil API")
		frame:SetSize(420, 140)
		frame:Center()
		frame:MakePopup()

		local open = vgui.Create("DButton", frame)
		open:Dock(BOTTOM)
		open:SetTall(30)
		open:SetText("Open it on the Workshop")
		function open:DoClick()
			if steamworks and steamworks.ViewFile then
				steamworks.ViewFile(API)
			else
				gui.OpenURL(URL)
			end
		end

		local text = vgui.Create("DLabel", frame)
		text:Dock(FILL)
		text:DockMargin(4, 4, 4, 8)
		text:SetWrap(true)
		text:SetText(Needs() .. " " .. fix)
	end)
	return
end
include("evil_api/init.lua")

AddCSLuaFile("evil_fungus/sh_settings.lua")
AddCSLuaFile("evil_fungus/sh_drag.lua")
AddCSLuaFile("evil_fungus/cl_mat.lua")
AddCSLuaFile("evil_fungus/cl_render.lua")
AddCSLuaFile("evil_fungus/cl_dream.lua")
AddCSLuaFile("evil_fungus/cl_sleepers.lua")
AddCSLuaFile("evil_fungus/cl_carriers.lua")
AddCSLuaFile("evil_fungus/cl_fire.lua")
include("evil_fungus/sh_settings.lua")
include("evil_fungus/sh_drag.lua")
if CLIENT then
	include("evil_fungus/cl_mat.lua")
	include("evil_fungus/cl_render.lua")
	include("evil_fungus/cl_dream.lua")
	include("evil_fungus/cl_sleepers.lua")
	include("evil_fungus/cl_carriers.lua")
	include("evil_fungus/cl_fire.lua")
else
	resource.AddWorkshop("3821991353")
	resource.AddFile("materials/evil_fungus/flesh.vtf")
	resource.AddFile("materials/evil_fungus/fiber.vtf")
	resource.AddFile("materials/evil_fungus/web.vtf")
	resource.AddFile("materials/killicons/evil_fungus.png")
	include("evil_fungus/sv_creatures.lua")
	include("evil_fungus/sv_mind.lua")
	include("evil_fungus/sv_scent.lua")
	include("evil_fungus/sv_net.lua")
	include("evil_fungus/sv_sleep.lua")
	include("evil_fungus/sv_hosts.lua")
	include("evil_fungus/sv_carriers.lua")
	include("evil_fungus/sv_harm.lua")
	include("evil_fungus/sv_enemy.lua")
end
