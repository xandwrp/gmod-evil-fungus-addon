EvilFungus = EvilFungus or {}
local Net = EvilFungus.Net or { nodes = {}, edges = {}, nextNode = 1, nextEdge = 1, players = {}, dropped = {}, dirty = {} }
EvilFungus.Net = Net

local LEVELS = 15
local NODES_PER_TICK = 120
local EDGES_PER_TICK = 200
local SCAN_PER_TICK = 4000
local LEVEL_INTERVAL = 0.25
local LEVELS_PER_SEND = 1000
local BODY_INTERVAL = 1 / 6
local BODY_MAX_MASS = 8
local BODY_MIN = 0.08
local BODY_LIMIT = 800
local DECAY_INTERVAL = 2
local DROP_CHUNK = 2000
local LEVEL_SLACK = 0.75
local RESYNC_GAP = 5

Net.LEVELS = LEVELS
Net.BODY_MAX_MASS = BODY_MAX_MASS
Net.count = Net.count or table.Count(Net.nodes)

util.AddNetworkString("EvilFungusReady")
util.AddNetworkString("EvilFungusMat")
util.AddNetworkString("EvilFungusDrop")
util.AddNetworkString("EvilFungusLevels")
util.AddNetworkString("EvilFungusBody")

local function Thickness(e)
	local Mat = EvilFungus.Mat
	return (e.D - Mat.D_FLOOR) / (Mat.D_MAX - Mat.D_FLOOR) * LEVELS
end

function Net.Level(e)
	return math.Clamp(math.floor(Thickness(e) + 0.5), 0, LEVELS)
end

function Net.Node(node)
	node.nid = Net.nextNode
	Net.nodes[node.nid] = node
	Net.nextNode = Net.nextNode + 1
	Net.count = Net.count + 1
end

function Net.Edge(e)
	e.eid = Net.nextEdge
	e.level = Net.Level(e)
	Net.edges[e.eid] = e
	Net.nextEdge = Net.nextEdge + 1
end

-- A vein hovering on the line between two thicknesses would flicker back and forth, and every flicker is a rebuilt chunk.
function Net.Touch(e)
	if not e.eid then return end
	local x = Thickness(e)
	if math.abs(x - e.level) < LEVEL_SLACK then return end
	local level = math.Clamp(math.floor(x + 0.5), 0, LEVELS)
	if level ~= e.level then
		e.level = level
		Net.dirty[e] = true
	end
end

function Net.Drop(node)
	if not node.nid or Net.nodes[node.nid] ~= node then return end
	Net.nodes[node.nid] = nil
	Net.count = Net.count - 1
	Net.dropped[#Net.dropped + 1] = node.nid
	for _, e in ipairs(node.edges) do
		if e.eid then
			Net.edges[e.eid] = nil
			Net.dirty[e] = nil
		end
	end
end

net.Receive("EvilFungusReady", function(_, ply)
	local now, st = RealTime(), Net.players[ply]
	if st and now - (st.asked or 0) < RESYNC_GAP then return end
	Net.players[ply] = { node = 0, edge = 0, asked = now }
end)

hook.Add("PlayerDisconnected", "EvilFungusNet", function(ply)
	Net.players[ply] = nil
end)

-- Catches one player up a slice at a time: strands in the order they grew, then the links between strands they already have.
local function Sync(ply, st)
	local nodes, edges = {}, {}
	local nid, scan = st.node, 0
	while #nodes < NODES_PER_TICK and nid < Net.nextNode - 1 and scan < SCAN_PER_TICK do
		nid = nid + 1
		scan = scan + 1
		local node = Net.nodes[nid]
		if node then nodes[#nodes + 1] = node end
	end
	st.node = nid

	local eid
	eid, scan = st.edge, 0
	while #edges < EDGES_PER_TICK and eid < Net.nextEdge - 1 and scan < SCAN_PER_TICK do
		local e = Net.edges[eid + 1]
		if e and (e.a.nid > nid or e.b.nid > nid) then break end
		eid = eid + 1
		scan = scan + 1
		if e then edges[#edges + 1] = e end
	end
	st.edge = eid

	if #nodes == 0 and #edges == 0 then return end
	net.Start("EvilFungusMat")
	net.WriteUInt(#nodes, 8)
	for _, node in ipairs(nodes) do
		net.WriteUInt(node.nid, 24)
		net.WriteVector(node.pos)
		net.WriteNormal(node.normal)
		net.WriteUInt(node.felt and math.Clamp(node.folded or 1, 1, 63) or 0, 6)
	end
	net.WriteUInt(#edges, 8)
	for _, e in ipairs(edges) do
		net.WriteUInt(e.eid, 24)
		net.WriteUInt(e.a.nid, 24)
		net.WriteUInt(e.b.nid, 24)
		net.WriteUInt(e.level, 4)
	end
	net.Send(ply)
end

local function SendDrops(ready)
	local dropped = Net.dropped
	Net.dropped = {}
	for first = 1, #dropped, DROP_CHUNK do
		local last = math.min(#dropped, first + DROP_CHUNK - 1)
		net.Start("EvilFungusDrop")
		net.WriteUInt(last - first + 1, 12)
		for i = first, last do net.WriteUInt(dropped[i], 24) end
		net.Send(ready)
	end
end

local function SendLevels(ready)
	local list = {}
	for e in pairs(Net.dirty) do
		Net.dirty[e] = nil
		if Net.edges[e.eid] == e then list[#list + 1] = e end
		if #list >= LEVELS_PER_SEND then break end
	end
	if #list == 0 then return end
	net.Start("EvilFungusLevels")
	net.WriteUInt(#list, 12)
	for _, e in ipairs(list) do
		net.WriteUInt(e.eid, 24)
		net.WriteUInt(e.level, 4)
	end
	net.Send(ready)
end

local function WriteBody(list, n)
	net.Start("EvilFungusBody")
	net.WriteUInt(n, 12)
	for i = 1, n do
		local node = list[i]
		net.WriteUInt(node.nid, 24)
		net.WriteUInt(math.Clamp(math.Round(node.m / BODY_MAX_MASS * 255), 1, 255), 8)
	end
end

local function Kth(a, n, k)
	local lo, hi = 1, n
	while lo < hi do
		local x, i, j = a[k], lo, hi
		repeat
			while a[i] < x do i = i + 1 end
			while x < a[j] do j = j - 1 end
			if i <= j then
				a[i], a[j] = a[j], a[i]
				i, j = i + 1, j - 1
			end
		until i > j
		if j < k then lo = i end
		if k < i then hi = j end
	end
	return a[k]
end

local function Viewer(ply)
	local view = ply:GetViewEntity()
	if IsValid(view) and view ~= ply then return view:GetPos() end
	return ply:EyePos()
end

local dist, pick, near = {}, {}, {}

local function Nearest(list, n, ply)
	local ex, ey, ez = Viewer(ply):Unpack()
	for i = 1, n do
		local node = list[i]
		local d = (node.x - ex) ^ 2 + (node.y - ey) ^ 2 + (node.z - ez) ^ 2
		dist[i], pick[i] = d, d
	end
	local cut = Kth(pick, n, BODY_LIMIT)
	local count = 0
	for i = 1, n do
		if dist[i] < cut then
			count = count + 1
			near[count] = list[i]
		end
	end
	for i = 1, n do
		if count >= BODY_LIMIT then break end
		if dist[i] == cut then
			count = count + 1
			near[count] = list[i]
		end
	end
	return near, count
end

local function SendBody(ready)
	local list, n = {}, 0
	for colony in pairs(EvilFungus.Colonies or {}) do
		if IsValid(colony) and colony.Mat then
			for node in pairs(colony.Mat.full) do
				if node.m > BODY_MIN and node.nid then
					n = n + 1
					list[n] = node
				end
			end
		end
	end
	if n <= BODY_LIMIT then
		WriteBody(list, n)
		net.Send(ready)
		return
	end
	for _, ply in ipairs(ready) do
		WriteBody(Nearest(list, n, ply))
		net.Send(ply)
	end
end

-- Veins nobody uses thin out slowly on their own; this notices when they've thinned enough to look different.
local function Decay(now)
	local Mat = EvilFungus.Mat
	for _, e in pairs(Net.edges) do
		if e.D > Mat.D_FLOOR then
			Mat.Conductance(nil, e, now)
			Net.Touch(e)
		end
	end
end

local nextLevels, nextBody, nextDecay, lastTick = 0, 0, 0, -1

local function Step()
	local tick = engine.TickCount()
	if tick == lastTick then return end
	lastTick = tick
	local now = CurTime()
	if GetGlobal2Int(EvilFungus.NODES_VAR, 0) ~= Net.count then SetGlobal2Int(EvilFungus.NODES_VAR, Net.count) end
	local ready = {}
	for ply, st in pairs(Net.players) do
		if IsValid(ply) then
			ready[#ready + 1] = ply
			Sync(ply, st)
		else
			Net.players[ply] = nil
		end
	end

	if #ready == 0 then
		Net.dropped = {}
		return
	end
	if #Net.dropped > 0 then SendDrops(ready) end
	if now >= nextLevels then
		nextLevels = now + LEVEL_INTERVAL
		SendLevels(ready)
	end
	if now >= nextBody then
		nextBody = now + BODY_INTERVAL
		SendBody(ready)
	end
	if now >= nextDecay and EvilFungus.Mat then
		nextDecay = now + DECAY_INTERVAL
		Decay(now)
	end
end

hook.Add("Tick", "EvilFungusNet", Step)
timer.Create("EvilFungusNet", 0, 0, Step)
