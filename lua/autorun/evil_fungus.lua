AddCSLuaFile("evil_fungus/sh_settings.lua")
AddCSLuaFile("evil_fungus/cl_settings.lua")
AddCSLuaFile("evil_fungus/sh_drag.lua")
include("evil_fungus/sh_settings.lua")
include("evil_fungus/sh_drag.lua")
if CLIENT then
	include("evil_fungus/cl_settings.lua")
end
