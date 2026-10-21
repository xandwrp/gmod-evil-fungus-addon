EvilFungus = EvilFungus or {}

local old = EvilFungus.Client
if old then
	for _, chunk in pairs(old.chunks) do
		if chunk.mesh then chunk.mesh:Destroy() end
		chunk.mesh, chunk.count = nil, 0
	end
	for _, cell in pairs(old.bodyCells or {}) do
		if cell.bodyMesh then cell.bodyMesh:Destroy() end
		cell.bodyMesh = nil
	end
end

local M = { nodes = {}, edges = {}, chunks = {}, body = {}, bodyCells = {}, count = 0 }
EvilFungus.Client = M

local CHUNK = 64
local SETTLED_CHUNK = 512
local SETTLED_DELAY = 1.5
local DRAW_RANGE = 6000
local LEVELS = 15
local BODY_MAX_MASS = 8
local GROWN = 0.4
local THICKENED = 2
local CHECK = 2
local RESYNC = 6
local SHORT = 0.5

M.LEVELS = LEVELS

local function ChunkAt(pos, size)
	size = size or CHUNK
	local ix, iy, iz = math.floor(pos.x / size), math.floor(pos.y / size), math.floor(pos.z / size)
	local key = ((ix + 512) * 1048576 + (iy + 512) * 1024 + (iz + 512)) * 2 + (size == CHUNK and 0 or 1)
	local chunk = M.chunks[key]
	if not chunk then
		chunk = { key = key, edges = {}, patches = {}, count = 0, settled = size ~= CHUNK or nil,
			center = Vector((ix + 0.5) * size, (iy + 0.5) * size, (iz + 0.5) * size), cull = (DRAW_RANGE + size * 2) ^ 2 }
		M.chunks[key] = chunk
	end
	return chunk
end

local function ChunkFor(e)
	return ChunkAt((e.a.pos + e.b.pos) * 0.5, (e.a.felt or e.b.felt) and SETTLED_CHUNK or CHUNK)
end

function M.Stale(chunk, delay)
	if chunk.settled then delay = math.max(delay, SETTLED_DELAY) end
	chunk.due = math.min(chunk.due or math.huge, RealTime() + delay)
end

local function Unlink(node, e)
	for i, oe in ipairs(node.edges) do
		if oe == e then
			table.remove(node.edges, i)
			return
		end
	end
end

local function RemoveEdge(e)
	M.edges[e.eid] = nil
	Unlink(e.a, e)
	Unlink(e.b, e)
	local chunk = e.chunk
	if chunk and chunk.edges[e] then
		chunk.edges[e] = nil
		chunk.count = chunk.count - 1
		M.Stale(chunk, GROWN)
	end
end

net.Receive("EvilFungusMat", function()
	for _ = 1, net.ReadUInt(8) do
		local nid = net.ReadUInt(24)
		local pos, normal, felt = net.ReadVector(), net.ReadNormal(), net.ReadBool()
		if not M.nodes[nid] then
			local node = { nid = nid, pos = pos, normal = normal, edges = {}, target = 0, shown = 0, felt = felt or nil }
			M.nodes[nid] = node
			M.count = M.count + 1
			if felt then
				local chunk = ChunkAt(pos, SETTLED_CHUNK)
				node.chunk = chunk
				chunk.patches[node] = true
				chunk.count = chunk.count + 1
				M.Stale(chunk, GROWN)
			end
		end
	end
	for _ = 1, net.ReadUInt(8) do
		local eid, an, bn, level = net.ReadUInt(24), net.ReadUInt(24), net.ReadUInt(24), net.ReadUInt(4)
		local a, b = M.nodes[an], M.nodes[bn]
		if a and b and not M.edges[eid] then
			local e = { eid = eid, a = a, b = b, level = level }
			M.edges[eid] = e
			a.edges[#a.edges + 1] = e
			b.edges[#b.edges + 1] = e
			local chunk = ChunkFor(e)
			e.chunk = chunk
			chunk.edges[e] = true
			chunk.count = chunk.count + 1
			M.Stale(chunk, GROWN)
		end
	end
end)

net.Receive("EvilFungusDrop", function()
	for _ = 1, net.ReadUInt(12) do
		local node = M.nodes[net.ReadUInt(24)]
		if node then
			for i = #node.edges, 1, -1 do RemoveEdge(node.edges[i]) end
			local chunk = node.chunk
			if chunk and chunk.patches[node] then
				chunk.patches[node] = nil
				chunk.count = chunk.count - 1
				M.Stale(chunk, GROWN)
			end
			M.nodes[node.nid] = nil
			M.count = M.count - 1
			M.body[node] = nil
		end
	end
end)

net.Receive("EvilFungusLevels", function()
	for _ = 1, net.ReadUInt(12) do
		local e, level = M.edges[net.ReadUInt(24)], net.ReadUInt(4)
		if e and e.level ~= level then
			e.level = level
			M.Stale(e.chunk, THICKENED)
		end
	end
end)

net.Receive("EvilFungusBody", function()
	local seen = {}
	for _ = 1, net.ReadUInt(12) do
		local node, m = M.nodes[net.ReadUInt(24)], net.ReadUInt(8) / 255 * BODY_MAX_MASS
		if node then
			node.target = m
			seen[node] = true
			M.body[node] = true
		end
	end
	for node in pairs(M.body) do
		if not seen[node] then node.target = 0 end
	end
end)

local asked, short = false, nil

local function Ready()
	asked = true
	net.Start("EvilFungusReady")
	net.SendToServer()
end

if IsValid(LocalPlayer()) then
	Ready()
else
	hook.Add("InitPostEntity", "EvilFungusReady", Ready)
end

timer.Create("EvilFungusSync", CHECK, 0, function()
	if not IsValid(LocalPlayer()) then return end
	if not asked then
		Ready()
		return
	end
	if M.count >= GetGlobal2Int(EvilFungus.NODES_VAR, 0) * SHORT then
		short = nil
		return
	end
	local now = RealTime()
	short = short or now
	if now - short >= RESYNC then
		short = now
		Ready()
	end
end)
