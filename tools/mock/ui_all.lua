-- Minimal Roblox mock for smoke-testing yslempet_EggTP.lua under the plain luau interpreter.
local M = {}
local now = 0
local sleepers = {}   -- {wake=, co=}
local ready = {}      -- coroutines to resume asap
local warnings = {}
M.warnings = warnings

----------------------------------------------------------------- math
local V3 = {}
V3.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X*t.X + t.Y*t.Y + t.Z*t.Z) end
	if k == "Unit" then local m = math.sqrt(t.X*t.X + t.Y*t.Y + t.Z*t.Z); if m == 0 then return t end; return setmetatable({X=t.X/m, Y=t.Y/m, Z=t.Z/m}, V3) end
	if k == "Dot" then return function(a, b) return a.X*b.X + a.Y*b.Y + a.Z*b.Z end end
	if k == "Cross" then return function(a, b) return setmetatable({X=a.Y*b.Z-a.Z*b.Y, Y=a.Z*b.X-a.X*b.Z, Z=a.X*b.Y-a.Y*b.X}, V3) end end
	if k == "Lerp" then return function(a, b, t_) return a + (b - a) * t_ end end
	return rawget(V3, k)
end
local function v3(x, y, z) return setmetatable({X=x or 0, Y=y or 0, Z=z or 0}, V3) end
V3.__add = function(a, b) return v3(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
V3.__sub = function(a, b) return v3(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
V3.__mul = function(a, b)
	if type(a) == "number" then return v3(a*b.X, a*b.Y, a*b.Z) end
	if type(b) == "number" then return v3(a.X*b, a.Y*b, a.Z*b) end
	return v3(a.X*b.X, a.Y*b.Y, a.Z*b.Z)
end
V3.__div = function(a, b) if type(b) == "number" then return v3(a.X/b, a.Y/b, a.Z/b) end return v3(a.X/b.X, a.Y/b.Y, a.Z/b.Z) end
V3.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V3.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
Vector3 = {new = v3, zero = v3(0, 0, 0)}

local CF = {}
CF.__index = function(t, k)
	if k == "Rotation" then return setmetatable({Position = v3(0,0,0)}, CF) end
	if k == "VectorToWorldSpace" then return function(_, v) return v end end
	if k == "PointToWorldSpace" then return function(c, v) return c.Position + v end end
	if k == "PointToObjectSpace" then return function(c, v) return v - c.Position end end
	if k == "LookVector" then return v3(0,0,-1) end
	if k == "RightVector" then return v3(1,0,0) end
	return rawget(CF, k)
end
local function cf(x, y, z)
	if type(x) == "table" then return setmetatable({Position = x}, CF) end
	return setmetatable({Position = v3(x or 0, y or 0, z or 0)}, CF)
end
CF.__mul = function(a, b)
	if getmetatable(b) == V3 then return a.Position + b end
	return setmetatable({Position = a.Position + b.Position}, CF)
end
CF.__sub = function(a, b) return setmetatable({Position = a.Position - b}, CF) end
CF.__add = function(a, b) return setmetatable({Position = a.Position + b}, CF) end
CFrame = {new = cf, Angles = function() return cf(0,0,0) end, lookAt = function(a, b) return cf(a) end}

UDim2 = {new = function(a,b,c,d) return {XS=a,XO=b,YS=c,YO=d, X={Scale=a,Offset=b}, Y={Scale=c,Offset=d}} end, fromOffset = function(a,b) return {X={Scale=0,Offset=a},Y={Scale=0,Offset=b}} end}
UDim = {new = function(a,b) return {Scale=a,Offset=b} end}
Color3 = {fromRGB = function(r,g,b) return {R=r,G=g,B=b} end, new = function(r,g,b) return {R=r,G=g,B=b} end}
ColorSequence = {new = function(...) return {...} end}
ColorSequenceKeypoint = {new = function(t, c) return {Time=t, Value=c} end}
TweenInfo = {new = function(...) return {...} end}
Enum = setmetatable({}, {__index = function(_, a) return setmetatable({}, {__index = function(_, b) return a .. "." .. b end}) end})
RaycastParams = {new = function() return {} end}
OverlapParams = {new = function() return {} end}

----------------------------------------------------------------- scheduler
task = {}
function task.wait(t)
	t = t or 1/60
	sleepers[#sleepers+1] = {wake = now + t, co = coroutine.running()}
	coroutine.yield()
	return t
end
function task.spawn(fn, ...)
	local co = coroutine.create(fn)
	local ok, err = coroutine.resume(co, ...)
	if not ok then warnings[#warnings+1] = "SPAWN ERROR: " .. tostring(err) .. "\n" .. debug.traceback(co) end
	return co
end
task.defer = task.spawn
function task.desynchronize() end
function task.synchronize() end
function M.step(dt)
	now = now + dt
	-- crude physics: parts move with their velocity
	for _, o in ipairs(M.all) do
		local v = rawget(o, "AssemblyLinearVelocity")
		if v and o.Parent and (v.X ~= 0 or v.Y ~= 0 or v.Z ~= 0) and rawget(o, "Name") == "HumanoidRootPart" then
			o.CFrame = CFrame.new(o.CFrame.Position + v * dt)
		end
	end
	table.sort(sleepers, function(a, b) return a.wake < b.wake end)
	local due = {}
	local keep = {}
	for _, s in ipairs(sleepers) do if s.wake <= now then due[#due+1] = s else keep[#keep+1] = s end end
	sleepers = keep
	for _, s in ipairs(due) do
		local ok, err = coroutine.resume(s.co)
		if not ok then warnings[#warnings+1] = "ERROR: " .. tostring(err) .. "\n" .. debug.traceback(s.co) end
	end
end
function M.now() return now end
warn = function(...) local t = {} for i, v in ipairs({...}) do t[i] = tostring(v) end warnings[#warnings+1] = table.concat(t, " ") end

----------------------------------------------------------------- signals
local function signal()
	local s = {conns = {}}
	function s:Connect(fn) local c = {fn = fn, Connected = true}; function c:Disconnect() c.Connected = false end; self.conns[#self.conns+1] = c; return c end
	function s:Fire(...) for _, c in ipairs(self.conns) do if c.Connected then task.spawn(c.fn, ...) end end end
	function s:Wait() return task.wait(1/60) end
	return s
end
M.signal = signal

----------------------------------------------------------------- instances
local CLASSES = {
	BasePart = {Part=1, MeshPart=1, UnionPart=1, SpherePart=1},
	GuiObject = {Frame=1, TextLabel=1, TextButton=1, ImageLabel=1, ImageButton=1, ScrollingFrame=1, ViewportFrame=1},
	GuiButton = {TextButton=1, ImageButton=1},
	Model = {Model=1},
	Folder = {Folder=1},
}
local all = {}
M.all = all
local Inst = {}
local function newInst(class, parent)
	local o = {ClassName = class, Name = class, Children = {}, _attrs = {}, Parent = nil}
	o.Changed = signal(); o.Destroying = signal()
	o.MouseButton1Click = signal(); o.MouseButton1Down = signal(); o.MouseButton1Up = signal(); o.MouseLeave = signal()
	o.InputBegan = signal(); o.InputEnded = signal(); o.InputChanged = signal(); o.Activated = signal()
	o.ChildAdded = signal(); o.FocusLost = signal(); o.Focused = signal()
	if class == "Part" or class == "MeshPart" then
		o.CFrame = cf(0,0,0); o.Size = v3(4,4,4); o.AssemblyLinearVelocity = v3(0,0,0); o.AssemblyAngularVelocity = v3(0,0,0); o.CanCollide = true; o.Anchored = false; o.CanQuery = true
	end
	if class == "Humanoid" then o.WalkSpeed = 20; o.Health = 100; o.MaxHealth = 100; o.PlatformStand = false; o.JumpPower = 50; o.UseJumpPower = true; o.Jump = false; o.state = "Running"; o.FloorMaterial = "Plastic" end
	if class == "ProximityPrompt" then o.ActionText = ""; o.ObjectText = ""; o.HoldDuration = 0.2; o.Enabled = true end
	if class == "TextLabel" or class == "TextButton" then o.Text = ""; o.Visible = true end
	if class == "ImageButton" or class == "ImageLabel" or class == "Frame" or class == "ScrollingFrame" then o.Visible = true end
	if class == "ScreenGui" then o.Enabled = true; o.IgnoreGuiInset = false end
	o.AbsoluteSize = v3(100, 30, 0); o.AbsolutePosition = v3(10, 10, 0)
	setmetatable(o, Inst)
	all[#all+1] = o
	if parent then o.Parent = parent end
	return o
end
local function isA(o, cls)
	if o.ClassName == cls then return true end
	if cls == "BasePart" then return CLASSES.BasePart[o.ClassName] ~= nil end
	if cls == "GuiObject" then return CLASSES.GuiObject[o.ClassName] ~= nil end
	if cls == "GuiButton" then return CLASSES.GuiButton[o.ClassName] ~= nil end
	if cls == "Instance" then return true end
	if cls == "LuaSourceContainer" then return false end
	return false
end
local function descendants(o, out)
	out = out or {}
	for _, c in ipairs(o.Children) do out[#out+1] = c; descendants(c, out) end
	return out
end
local function ancestorsOf(o) local p = o.Parent; return function() local r = p; if p then p = p.Parent end; return r end end
local methods = {
	IsA = function(o, c) return isA(o, c) end,
	FindFirstChild = function(o, n) for _, c in ipairs(o.Children) do if c.Name == n then return c end end end,
	WaitForChild = function(o, n) return o:FindFirstChild(n) end,
	FindFirstChildOfClass = function(o, c) for _, ch in ipairs(o.Children) do if ch.ClassName == c then return ch end end end,
	FindFirstChildWhichIsA = function(o, c) for _, ch in ipairs(o.Children) do if isA(ch, c) then return ch end end end,
	GetChildren = function(o) local t = {} for i, c in ipairs(o.Children) do t[i] = c end return t end,
	GetDescendants = function(o) return descendants(o) end,
	IsDescendantOf = function(o, a) for p in ancestorsOf(o) do if p == a then return true end end return false end,
	FindFirstAncestor = function(o, n) for p in ancestorsOf(o) do if p.Name == n then return p end end end,
	FindFirstAncestorOfClass = function(o, c) for p in ancestorsOf(o) do if p.ClassName == c then return p end end end,
	GetFullName = function(o) local t = {o.Name}; for p in ancestorsOf(o) do table.insert(t, 1, p.Name) end return table.concat(t, ".") end,
	Destroy = function(o)
		local p = rawget(o, "Parent")
		if p then for i, c in ipairs(p.Children) do if c == o then table.remove(p.Children, i) break end end end
		rawset(o, "Parent", nil)
		o.Destroying:Fire()
	end,
	Clone = function(o) return newInst(o.ClassName) end,
	GetPivot = function(o) return o.CFrame or cf(0,0,0) end,
	GetBoundingBox = function(o) return cf(0,0,0), v3(10,10,10) end,
	PivotTo = function(o, c) if o.HumanoidRootPart then o.HumanoidRootPart.CFrame = c end end,
	GetAttribute = function(o, k) return o._attrs[k] end,
	SetAttribute = function(o, k, v) o._attrs[k] = v end,
	GetAttributes = function(o) return o._attrs end,
	GetState = function(o) return o.state end,
	IsFocused = function() return false end,
	ChangeState = function(o, s) o.state = s end,
	SetStateEnabled = function() end,
	Move = function(o, v) o._move = v end,
	UnequipTools = function() end,
	GetPropertyChangedSignal = function() return signal() end,
	FireServer = function(o, ...) if M.onFire then M.onFire(o, ...) end end,
}
Inst.__index = function(o, k)
	if k == "Position" and rawget(o, "CFrame") then return o.CFrame.Position end
	if methods[k] then return methods[k] end
	local children = rawget(o, "Children")
	if children then for _, c in ipairs(children) do if c.Name == k then return c end end end
	return nil
end
Inst.__newindex = function(o, k, v)
	if k == "Parent" then
		local old = rawget(o, "Parent")
		if old then for i, c in ipairs(old.Children) do if c == o then table.remove(old.Children, i) break end end end
		rawset(o, "Parent", v)
		if v then v.Children[#v.Children+1] = o; if v.ChildAdded then v.ChildAdded:Fire(o) end end
	elseif k == "CFrame" and rawget(o, "ClassName") == "Part" and o.ClassName then
		rawset(o, "CFrame", v)
	else
		rawset(o, k, v)
	end
end
Instance = {new = function(class, parent) return newInst(class, parent) end}
M.newInst = newInst

----------------------------------------------------------------- services
local function service(name) local s = newInst("Folder"); s.Name = name; return s end
local game_ = newInst("Folder"); game_.Name = "game"
M.game = game_
game = game_
game.PlaceId = 124216119978534; game.GameId = 1; game.JobId = "x"
M.services = {}
local function getService(_, name)
	if not M.services[name] then M.services[name] = service(name) end
	return M.services[name]
end
game.GetService = getService
local RunService = getService(nil, "RunService")
RunService.Heartbeat = signal()
RunService.Heartbeat.Wait = function() return task.wait(1/60) end
RunService.RenderStepped = signal(); RunService.PreSimulation = signal()
local Tween = getService(nil, "TweenService")
Tween.Create = function(_, obj, info, props) return {Play = function() for k, v in pairs(props) do rawset(obj, k, v) end end} end
getService(nil, "UserInputService")
getService(nil, "ReplicatedStorage")
local Http = getService(nil, "HttpService")
Http.JSONEncode = function(_, t) return "{}" end
Http.JSONDecode = function(_, s) return {} end
getService(nil, "GuiService").GetGuiInset = function() return v3(0, 36, 0) end
getService(nil, "VirtualInputManager").SendMouseButtonEvent = function() M.mouseClicks = (M.mouseClicks or 0) + 1 end
getService(nil, "VirtualInputManager").SendKeyEvent = function() M.keys = (M.keys or 0) + 1 end
getService(nil, "StarterPlayer"); getService(nil, "CoreGui")
getService(nil, "MarketplaceService").GetProductInfo = function() return {Name = "Mock"} end
local WS = getService(nil, "Workspace"); WS.Name = "Workspace"
workspace = WS
WS.Gravity = 196.2
WS.StreamingEnabled = true
WS.CurrentCamera = newInst("Camera")
WS.GetServerTimeNow = function() return now end
WS.GetPartBoundsInRadius = function(_, center, radius)
	local out = {}
	for _, d in ipairs(descendants(WS)) do
		if d.ClassName == "Part" and d.CFrame and (d.CFrame.Position - center).Magnitude <= radius then out[#out+1] = d end
	end
	return out
end
WS.Raycast = function(_, origin, dir)
	return {Position = v3(origin.X, 0, origin.Z), Material = "Grass"}
end

local Players = getService(nil, "Players")
Players.GetPlayers = function() return M.players or {} end
Players.GetPlayerFromCharacter = function() return nil end
M.getService = getService
M.workspace = WS
M.Players = Players

typeof = function(v) if type(v) == "table" and getmetatable(v) == V3 then return "Vector3" end if type(v) == "table" and getmetatable(v) == CF then return "CFrame" end if type(v) == "table" and v.ClassName then return "Instance" end return type(v) end

local loadLib = function()
local SourcesAD = {}
do
	local _h  = string.format("%x", math.random(0x100000, 0xFFFFFF))
	local _t  = tostring(tick()):gsub("%.", ""):sub(-8)
	local _jf = tostring(game.JobId):gsub("-",""):sub(1,6)
	local _ck = tostring(math.floor(os.clock()*1e5 % 0xFFFFF))
	SourcesAD.NS = _h .. _t .. _jf .. _ck
	-- Layer 1 — cloneref
	SourcesAD.cr = (typeof(cloneref) == "function") and cloneref or function(x) return x end
	-- Layer 2 — newcclosure
	SourcesAD.ncc = (typeof(newcclosure) == "function") and newcclosure or function(f) return f end
	-- Layer 3 — pseudo-legit part names
	local names = {"Handle","Weld","Attachment","Joint","Motor","Bone","RootConstraint","BasePart","HRP","RootPart"}
	function SourcesAD.partName()
		return names[math.random(1, #names)] .. string.format("%04x", math.random(0, 0xFFFF))
	end
	-- Layer 6 — jitter helper
	function SourcesAD.jitter(base, amp)
		amp = amp or base * 0.18
		return math.max(0, base + (math.random() - 0.5) * 2 * amp)
	end
	-- Layer 7 — script-source evasion
	pcall(function()
		local scr = getfenv and getfenv(0) and getfenv(0).script or nil
		if not scr then return end
		if typeof(setscriptable) == "function" then
			pcall(function() setscriptable(scr, "Source", true) end)
			pcall(function() scr.Source = "" end)
		end
	end)
end

if not game:IsLoaded() then game.Loaded:Wait() end
do
	local lp = game:GetService("Players").LocalPlayer
	if lp and not lp.Character then lp.CharacterAdded:Wait() end
	-- clean relaunch: drop any previous SourcesHub interface
	pcall(function() local o = game:GetService("CoreGui"):FindFirstChild("SourcesHubGui"); if o then o:Destroy() end end)
	pcall(function() local o = lp.PlayerGui:FindFirstChild("SourcesHubGui"); if o then o:Destroy() end end)
	pcall(function()
		if typeof(gethui) == "function" then local o = gethui():FindFirstChild("SourcesHubGui"); if o then o:Destroy() end end
	end)
end

-- Not available to the script (nothing may load remote code, open sockets,
-- queue itself on teleport or disable the game's own connections)
local getconnections, queue_on_teleport, queueonteleport, loadstring, WebSocket, syn, fluxus = nil, nil, nil, nil, nil, nil, nil

-- ============================================================
-- SOURCES HUB LIBRARY — the UI layer. It exposes the same API the Sources Hub logic
-- was written against (CreateWindow / CreateTab / CreateSection / CreateToggle /
-- CreateSlider / CreateDropdown / CreateMultiDropdown / CreateText /
-- CreateButton / CreateInput / CreateState / CreateExclusiveGroup / Notify /
-- Finalize) but draws everything in the Sources Hub look, and keeps all values
-- in a local config file. No network access of any kind.
-- ============================================================
local lib = {handles = {}, states = {}}

do
	local UIS = game:GetService("UserInputService")
	local TweenService = game:GetService("TweenService")
	local HttpService = game:GetService("HttpService")
	local RunService = game:GetService("RunService")
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	-- ---------- persistence ----------
	local CONFIG_FILE = "SourcesHub_Config.json"
	local store = {}
	pcall(function()
		if isfile and isfile(CONFIG_FILE) then
			local d = HttpService:JSONDecode(readfile(CONFIG_FILE))
			if type(d) == "table" then store = d end
		end
	end)
	local saving = false
	local function saveSoon()
		if saving then return end
		saving = true
		task.delay(0.6, function()
			saving = false
			pcall(function() if writefile then writefile(CONFIG_FILE, HttpService:JSONEncode(store)) end end)
		end)
	end
	local function setStored(key, v) store[key] = v; saveSoon() end

	-- ---------- design system (Sources Hub) ----------
local C = {
	BG       = Color3.fromRGB(0,0,0),
	HEADER   = Color3.fromRGB(0,0,0),
	ROW      = Color3.fromRGB(0,0,0),     -- Sources Hub rows: black + 0.35 BackgroundTransparency
	BORDER   = Color3.fromRGB(50,12,12),
	WHITE    = Color3.fromRGB(255,255,255),
	MOON     = Color3.fromRGB(220,40,40),   -- main accent red
	MOON2    = Color3.fromRGB(255,90,90),  -- light accent red
	MOONTEXT = Color3.fromRGB(20,0,0),
	DIM      = Color3.fromRGB(140,110,110),
	TABIDLE  = Color3.fromRGB(255,140,140),
	ON_BG    = Color3.fromRGB(80,15,15),
	OFF_BG   = Color3.fromRGB(0,0,0),
	SILVER   = Color3.fromRGB(240,210,210),
	SILVER2  = Color3.fromRGB(210,140,140),
	RED      = Color3.fromRGB(220,40,40),
	GREEN    = Color3.fromRGB(60,220,120),
	YELLOW   = Color3.fromRGB(230,200,90),
	GOLD     = Color3.fromRGB(255,200,60),
	DEEP1    = Color3.fromRGB(12,2,2),
	DEEP2    = Color3.fromRGB(40,8,8),
	DEEP3    = Color3.fromRGB(140,25,25),
	DEEP4    = Color3.fromRGB(220,40,40),
}
-- Alias for compatibility with the rest of the file (names already used everywhere)
C.ACCENT, C.ACCENT2 = C.MOON, C.MOON2
C.TRACKOFF = C.OFF_BG

-- ---------- themes: one table so the lib block keeps few locals ----------
local TH = {names = {"Gold", "Moon", "Neon", "Toxic"}, list = {}}
do
	local function c3(r, g, b) return Color3.fromRGB(r, g, b) end
	TH.sets = {
		Moon  = {DEEP1 = c3(12,2,2),  DEEP2 = c3(40,8,8), DEEP3 = c3(140,25,25),  DEEP4 = c3(220,40,40),  MOON = c3(220,40,40),  MOON2 = c3(255,90,90), ON_BG = c3(80,15,15),
			SILVER = c3(240,210,210), SILVER2 = c3(210,140,140), HUDA = c3(255,220,220), HUDB = c3(255,120,120)},
		Neon  = {DEEP1 = c3(18,4,14), DEEP2 = c3(58,14,40), DEEP3 = c3(165,40,110), DEEP4 = c3(255,90,180),  MOON = c3(255,100,190), MOON2 = c3(255,170,220), ON_BG = c3(80,20,55),
			SILVER = c3(240,214,230), SILVER2 = c3(210,150,185), HUDA = c3(255,220,240), HUDB = c3(255,150,205)},
		Toxic = {DEEP1 = c3(4,16,6),  DEEP2 = c3(14,58,24), DEEP3 = c3(40,165,70),  DEEP4 = c3(110,255,140), MOON = c3(90,240,130),  MOON2 = c3(170,255,190), ON_BG = c3(20,80,35),
			SILVER = c3(214,240,222), SILVER2 = c3(150,210,165), HUDA = c3(220,255,230), HUDB = c3(150,255,180)},
		Gold  = {DEEP1 = c3(12,2,2), DEEP2 = c3(40,8,8), DEEP3 = c3(140,25,25), DEEP4 = c3(220,40,40),  MOON = c3(220,40,40),  MOON2 = c3(255,90,90), ON_BG = c3(80,15,15),
			SILVER = c3(240,210,210), SILVER2 = c3(210,140,140), HUDA = c3(255,220,220), HUDB = c3(255,120,120)},
	}
	TH.current = TH.sets[store["Theme"]] and store["Theme"] or "Gold"
	TH.apply = function(name)
		for k, v in pairs(TH.sets[name]) do C[k] = v end
		C.ACCENT, C.ACCENT2, C.TABIDLE = C.MOON, C.MOON2, C.MOON2
	end
	TH.apply(TH.current)
	TH.seq = function(a, b)
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(0.25, b), ColorSequenceKeypoint.new(0.5, a),
			ColorSequenceKeypoint.new(0.75, b), ColorSequenceKeypoint.new(1, a)})
	end
	TH.refresh = function()
		local list = TH.list
		for i = #list, 1, -1 do
			local e = list[i]
			if not e.inst.Parent then
				table.remove(list, i)
			elseif e.kind == "grad" then e.inst.Color = TH.seq(C.DEEP4, C.DEEP3)
			elseif e.kind == "strokegrad" then e.inst.Color = TH.seq(C.DEEP1, C.DEEP2)
			elseif e.kind == "stroke" then e.inst.Color = C.DEEP3
			elseif e.kind == "glow" then e.inst.Color = C.MOON
			end
		end
	end
	TH.reg = function(inst, kind) TH.list[#TH.list + 1] = {inst = inst, kind = kind} end
	TH.hooks = {}
	TH.pairsFor = function(fromName, toName)
		local list = {}
		for k, a in pairs(TH.sets[fromName]) do
			local b = TH.sets[toName][k]
			if b and a ~= b then list[#list + 1] = {a, b} end
		end
		return list
	end
	TH.mapColor = function(list, c)
		for i = 1, #list do
			if c == list[i][1] then return list[i][2] end
		end
		return c
	end
	TH.mapSeq = function(list, seq)
		local kps, changed = {}, false
		for i, kp in ipairs(seq.Keypoints) do
			local nc = TH.mapColor(list, kp.Value)
			if nc ~= kp.Value then changed = true end
			kps[i] = ColorSequenceKeypoint.new(kp.Time, nc)
		end
		return changed and ColorSequence.new(kps) or seq
	end
	TH.recolor = function(root, list)
		if #list == 0 then return end
		local function fix(inst, prop)
			local ok, v = pcall(function() return inst[prop] end)
			if ok and typeof(v) == "Color3" then
				local nv = TH.mapColor(list, v)
				if nv ~= v then inst[prop] = nv end
			end
		end
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("GuiObject") then
				fix(d, "BackgroundColor3")
				if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then fix(d, "TextColor3") end
				if d:IsA("ImageLabel") or d:IsA("ImageButton") then fix(d, "ImageColor3") end
				if d:IsA("ScrollingFrame") then fix(d, "ScrollBarImageColor3") end
			elseif d:IsA("UIStroke") then
				fix(d, "Color")
			elseif d:IsA("UIGradient") then
				d.Color = TH.mapSeq(list, d.Color)
			end
		end
	end
	TH.runHooks = function(list)
		for _, fn in ipairs(TH.hooks) do
			pcall(fn, function(c) return TH.mapColor(list, c) end, function(q) return TH.mapSeq(list, q) end, function(root) TH.recolor(root, list) end)
		end
	end
end
local function corner(inst, r) local c = Instance.new("UICorner", inst); c.CornerRadius = UDim.new(0, r or 8); return c end
local function stroke(inst, col, th, tr)
	local s = Instance.new("UIStroke", inst)
	s.Color = col or C.BORDER; s.Thickness = th or 1; s.Transparency = tr or 0
	return s
end
local function label(parent, text, size, color, font, ax, ay)
	local l = Instance.new("TextLabel", parent)
	l.BackgroundTransparency = 1
	l.Size = size or UDim2.new(1,0,1,0)
	l.Text = text or ""; l.TextSize = 13
	l.TextColor3 = color or C.WHITE
	l.Font = font or Enum.Font.GothamMedium
	l.TextXAlignment = ax or Enum.TextXAlignment.Left
	l.TextYAlignment = ay or Enum.TextYAlignment.Center
	return l
end

-- "Living" gradients/strokes. Only the ones asked for (window borders, window titles)
-- are animated; rows/buttons use the same colours statically, which costs nothing.
-- Animated ones are grouped per window and only rotate while their window is visible,
-- every third frame.
local _live = {}
local _liveAny = {}
local _liveTick = 0
RunService.RenderStepped:Connect(function()
	_liveTick = _liveTick + 1
	if _liveTick % 6 ~= 0 or lib.AnimUser == false or lib.AnimAuto == false then return end
	for root, list in pairs(_live) do
		if root.Parent then
			if root.Visible then
				for k = 1, #list do
					local g = list[k]
					if g.Parent then g.Rotation = (g.Rotation + 3.6) % 360 end
				end
			end
		else
			_live[root] = nil
		end
	end
	for k = 1, #_liveAny do
		local g = _liveAny[k]
		if g.Parent then g.Rotation = (g.Rotation + 3.6) % 360 end
	end
end)
local _sweep = {}
local _sweepTick = 0
RunService.RenderStepped:Connect(function()
	_sweepTick = _sweepTick + 1
	if _sweepTick % 3 ~= 0 or lib.AnimUser == false or lib.AnimAuto == false then return end
	local t = os.clock()
	for k = #_sweep, 1, -1 do
		local g = _sweep[k]
		if g.Parent then
			g.Offset = Vector2.new(math.sin(t * 1.3 + k) * 0.8, 0)
		else
			table.remove(_sweep, k)
		end
	end
end)
local function registerLive(g, inst)
	local root = inst
	while root.Parent and not root.Parent:IsA("ScreenGui") do root = root.Parent end
	if root:IsA("GuiObject") and root.Parent then
		local list = _live[root]
		if not list then list = {}; _live[root] = list end
		list[#list + 1] = g
	else
		_liveAny[#_liveAny + 1] = g
	end
end
local function liveGrad(inst, animated, sweep)
	local g = Instance.new("UIGradient", inst)
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    C.DEEP4), ColorSequenceKeypoint.new(0.25, C.DEEP3),
		ColorSequenceKeypoint.new(0.5,  C.DEEP4), ColorSequenceKeypoint.new(0.75, C.DEEP3),
		ColorSequenceKeypoint.new(1,    C.DEEP4),
	})
	if sweep then g.Rotation = 0; _sweep[#_sweep + 1] = g elseif animated then registerLive(g, inst) end
	TH.reg(g, "grad")
	return g
end
local function addLivingStroke(parent, thickness, animated, sweep)
	local s = Instance.new("UIStroke", parent)
	s.Color = C.DEEP3; s.Thickness = thickness or 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local g = Instance.new("UIGradient", s)
	g.Rotation = 45
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    C.DEEP1), ColorSequenceKeypoint.new(0.25, C.DEEP2),
		ColorSequenceKeypoint.new(0.5,  C.DEEP1), ColorSequenceKeypoint.new(0.75, C.DEEP2),
		ColorSequenceKeypoint.new(1,    C.DEEP1),
	})
	if sweep then g.Rotation = 0; g.Color = TH.seq(C.DEEP2, C.DEEP3); _sweep[#_sweep + 1] = g elseif animated then registerLive(g, parent) end
	TH.reg(s, "stroke"); TH.reg(g, "strokegrad")
	return s
end
-- press feedback shared by every button of the hub
local function pressFx(btn)
	local sc = Instance.new("UIScale"); sc.Parent = btn
	local function tw(v, t, es)
		TweenService:Create(sc, TweenInfo.new(t, es or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = v}):Play()
	end
	btn.MouseButton1Down:Connect(function() tw(0.92, 0.08); if lib.Sound then lib.Sound("click") end end)
	btn.MouseButton1Up:Connect(function() tw(1, 0.24, Enum.EasingStyle.Back) end)
	btn.MouseLeave:Connect(function() tw(1, 0.15) end)
	return function() sc.Scale = 1.14; tw(1, 0.36, Enum.EasingStyle.Back) end
end
-- Sources Hub's makeDivider: 1px DEEP3 line + living gradient, between every row
local function makeDivider(page)
	local d = Instance.new("Frame", page)
	d.Size = UDim2.new(1,-12,0,1)
	d.BackgroundColor3 = C.DEEP3
	d.BorderSizePixel = 0
	liveGrad(d)
	return d
end

-- Section header — visual grouping for a block of rows, collapsible
-- like the hub's own CreateSection({Expanded=...}). With as many
-- widgets as the full filter set now has per tab, an accordion is
-- what keeps the panel scannable instead of one long scroll.
-- Members are collected via page.ChildAdded from the moment a header
-- is created until the next one replaces it — every widget helper
-- (makeRow/makeSlider/makeCarousel/makeMultiSelect/makeButton/
-- makeDivider) already parents its root Frame straight to `page`, so
-- no call site elsewhere needs to change for this to work.
local function makeSwitch(parent, initial)
	local pill = Instance.new("Frame", parent)
	pill.Size = UDim2.new(0,40,0,20)
	pill.BackgroundColor3 = initial and C.ON_BG or C.OFF_BG
	pill.BackgroundTransparency = 0.1
	pill.BorderSizePixel = 0
	corner(pill, 10)
	addLivingStroke(pill, 1)

	local glow = Instance.new("UIStroke", pill)
	glow.Thickness = 2.5; glow.Color = C.MOON; glow.Transparency = 1
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local _glowTween = nil
	TH.reg(glow, "glow")
	local function burst()
		if not lib.ParticlesOn then return end
		for i = 1, 6 do
			local p = Instance.new("Frame", pill)
			p.Size = UDim2.fromOffset(3, 3); p.AnchorPoint = Vector2.new(0.5, 0.5)
			p.Position = UDim2.new(1, -10, 0.5, 0)
			p.BackgroundColor3 = i % 2 == 0 and C.MOON2 or C.WHITE; p.BorderSizePixel = 0; p.ZIndex = 50
			corner(p, 2)
			TweenService:Create(p, TweenInfo.new(0.5 + math.random() * 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(1, -10 + math.random(-16, 6), 0.5, -math.random(10, 20)),
				BackgroundTransparency = 1, Size = UDim2.fromOffset(1, 1)}):Play()
			game:GetService("Debris"):AddItem(p, 0.9)
		end
	end
	local function stopGlow()
		if _glowTween then _glowTween:Cancel(); _glowTween = nil end
		glow.Transparency = 1
	end
	local function startGlow()
		TweenService:Create(glow, TweenInfo.new(0.25), {Transparency = 0.6}):Play()
	end

	local knob = Instance.new("Frame", pill)
	knob.Size = UDim2.new(0,14,0,14)
	knob.Position = initial and UDim2.new(1,-17,0.5,-7) or UDim2.new(0,3,0.5,-7)
	knob.BackgroundColor3 = initial and C.WHITE or C.SILVER2
	knob.BorderSizePixel = 0
	corner(knob, 7)

	local btn = Instance.new("TextButton", pill)
	btn.Size = UDim2.new(1,0,1,0); btn.BackgroundTransparency = 1; btn.Text = ""

	local function setState(on)
		TweenService:Create(pill, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{BackgroundColor3 = on and C.ON_BG or C.OFF_BG}):Play()
		TweenService:Create(knob, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{Position = on and UDim2.new(1,-17,0.5,-7) or UDim2.new(0,3,0.5,-7),
			 BackgroundColor3 = on and C.WHITE or C.SILVER2}):Play()
		if on then startGlow(); burst() else stopGlow() end
	end
	if initial then startGlow() end
	return pill, btn, setState
end

local function makeCheck(parent, initial)
	local pill = Instance.new("Frame", parent)
	pill.Size = UDim2.new(0,26,0,26)
	pill.BackgroundColor3 = initial and C.MOON or C.OFF_BG
	pill.BorderSizePixel = 0
	corner(pill, 7)
	local ring = Instance.new("UIStroke", pill)
	ring.Thickness = 1.5; ring.Color = initial and C.MOON2 or C.DEEP3; ring.Transparency = 0.15
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local tick = Instance.new("TextLabel", pill)
	tick.Size = UDim2.new(1,0,1,0); tick.BackgroundTransparency = 1
	tick.Text = "\226\156\147"; tick.Font = Enum.Font.GothamBold; tick.TextSize = 16
	tick.TextColor3 = C.WHITE; tick.TextTransparency = initial and 0 or 1
	local tickScale = Instance.new("UIScale", tick)
	tickScale.Scale = initial and 1 or 0.4

	local btn = Instance.new("TextButton", pill)
	btn.Size = UDim2.new(1,0,1,0); btn.BackgroundTransparency = 1; btn.Text = ""

	local function ripple()
		if not lib.ParticlesOn then return end
		local r = Instance.new("Frame", pill)
		r.AnchorPoint = Vector2.new(0.5, 0.5); r.Position = UDim2.new(0.5, 0, 0.5, 0)
		r.Size = UDim2.fromOffset(26, 26); r.BackgroundTransparency = 1; r.BorderSizePixel = 0; r.ZIndex = 50
		corner(r, 7)
		local rs = Instance.new("UIStroke", r)
		rs.Thickness = 2; rs.Color = C.MOON2; rs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		TweenService:Create(r, TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(46, 46)}):Play()
		TweenService:Create(rs, TweenInfo.new(0.38), {Transparency = 1}):Play()
		task.delay(0.45, function() pcall(function() r:Destroy() end) end)
	end

	local function setState(on)
		TweenService:Create(pill, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{BackgroundColor3 = on and C.MOON or C.OFF_BG}):Play()
		TweenService:Create(ring, TweenInfo.new(0.2), {Color = on and C.MOON2 or C.DEEP3}):Play()
		TweenService:Create(tick, TweenInfo.new(0.18), {TextTransparency = on and 0 or 1}):Play()
		TweenService:Create(tickScale, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = on and 1 or 0.4}):Play()
		if on then ripple() end
	end
	return pill, btn, setState
end

-- Toggle row (dark background + 0.35 transparency, 0.15 on hover;
-- living stroke; living-gradient label; knob + breathing glow; a
-- divider after each row). Registers itself for post-load
-- restoration/activation (_toggleRegistry) and saves on every click.
	-- ---------- helpers ----------
	local function newSignalList()
		local list = {}
		return {
			Connect = function(fn)
				local c = {fn = fn}
				table.insert(list, c)
				return {Disconnect = function() c.fn = nil end}
			end,
			Fire = function(...)
				for _, c in ipairs(list) do if c.fn then task.spawn(c.fn, ...) end end
			end,
		}
	end
	local iconOf -- species picture for "Name [Rarity]" style option labels
	do
		local map
		iconOf = function(text)
			if not map then
				map = {}
				pcall(function()
					local dir = require(ReplicatedStorage.Data.Assets).Directory
					for k, e in pairs(dir) do
						if type(e) == "table" and e.Icon then
							local ic = tostring(e.Icon)
							if tonumber(ic) then ic = "rbxassetid://" .. ic end
							map[string.lower(tostring(k))] = ic
							if e.DisplayName then map[string.lower(tostring(e.DisplayName))] = ic end
						end
					end
				end)
			end
			local t = string.lower(tostring(text))
			local base = t:match("^(.-)%s*%[") or t
			local cat = t:match("%((.-)%)%s*$")
			return map[cat or ""] or map[base] or map[t]
		end
	end

	-- ---------- gui root ----------
	local function guiParent()
		if typeof(gethui) == "function" then
			local ok, r = pcall(gethui)
			if ok and typeof(r) == "Instance" then return r end
		end
		return game:GetService("CoreGui")
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "SourcesHubGui"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = true
	gui:SetAttribute("SourcesHubOwned", nil)
	pcall(function() gui.Parent = guiParent() end)
	if not gui.Parent then gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end
	lib.Gui = gui

	local zTop = 20
	local snapFrames = {}
	local function snapTo(target)
		local scr = gui.AbsoluteSize
		local pos, size = target.AbsolutePosition, target.AbsoluteSize
		local T = 14
		local bestX, bestY
		local function tryX(d) if math.abs(d) <= T and (not bestX or math.abs(d) < math.abs(bestX)) then bestX = d end end
		local function tryY(d) if math.abs(d) <= T and (not bestY or math.abs(d) < math.abs(bestY)) then bestY = d end end
		tryX(-pos.X); tryX(scr.X - (pos.X + size.X)); tryY(-pos.Y); tryY(scr.Y - (pos.Y + size.Y))
		for _, o in ipairs(snapFrames) do
			if o ~= target and o.Parent and o.Visible then
				local op, osz = o.AbsolutePosition, o.AbsoluteSize
				local vOverlap = pos.Y < op.Y + osz.Y and pos.Y + size.Y > op.Y
				local hOverlap = pos.X < op.X + osz.X and pos.X + size.X > op.X
				if vOverlap then tryX(op.X + osz.X - pos.X); tryX(op.X - (pos.X + size.X)) end
				if hOverlap then tryY(op.Y + osz.Y - pos.Y); tryY(op.Y - (pos.Y + size.Y)) end
			end
		end
		if bestX or bestY then
			local p = target.Position
			TweenService:Create(target, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(p.X.Scale, p.X.Offset + (bestX or 0), p.Y.Scale, p.Y.Offset + (bestY or 0))}):Play()
		end
	end
	local function drag(handle, target)
		if not table.find(snapFrames, target) then table.insert(snapFrames, target) end
		local dragging, dragStart, startPos = false, nil, nil
		handle.InputBegan:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
				dragging = true; dragStart = inp.Position; startPos = target.Position
				zTop = zTop + 1; target.ZIndex = zTop
			end
		end)
		UIS.InputChanged:Connect(function(inp)
			if not dragging then return end
			if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
				local d = inp.Position - dragStart
				target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end)
		UIS.InputEnded:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
				if dragging then dragging = false; pcall(snapTo, target) end
			end
		end)
	end

	-- ---------- toast ----------
	local toastHost = Instance.new("Frame", gui)
	toastHost.Size = UDim2.new(0, 240, 1, -20); toastHost.Position = UDim2.new(0.5, -120, 0, 8)
	toastHost.BackgroundTransparency = 1; toastHost.ZIndex = 900
	local tl = Instance.new("UIListLayout", toastHost)
	tl.Padding = UDim.new(0, 5); tl.SortOrder = Enum.SortOrder.LayoutOrder
	lib.Notify = function(title, text, dur)
		pcall(function()
			local f = Instance.new("Frame", toastHost)
			f.Size = UDim2.new(1, 0, 0, 46); f.BackgroundColor3 = C.BG; f.BackgroundTransparency = 0.1
			f.BorderSizePixel = 0; f.ZIndex = 901
			corner(f, 12); addLivingStroke(f, 1)
			local t = label(f, tostring(title or ""), UDim2.new(1, -16, 0, 16), C.WHITE, Enum.Font.GothamBold)
			t.Position = UDim2.new(0, 10, 0, 5); t.TextSize = 11; t.ZIndex = 902; liveGrad(t)
			local d = label(f, tostring(text or ""), UDim2.new(1, -16, 0, 22), C.SILVER, Enum.Font.GothamMedium)
			d.Position = UDim2.new(0, 10, 0, 21); d.TextSize = 9.5; d.TextWrapped = true
			d.TextYAlignment = Enum.TextYAlignment.Top; d.ZIndex = 902
			task.delay(tonumber(dur) or 4, function() pcall(function() f:Destroy() end) end)
		end)
	end

	-- ---------- badge: a small semi-transparent pill pinned under the top bar ----------
	local bannerToken = 0
	lib.Banner = function(text, dur)
		pcall(function()
			bannerToken = bannerToken + 1
			local mine = bannerToken
			local old = gui:FindFirstChild("SourcesHubBanner")
			if old then old:Destroy() end
			local f = Instance.new("TextLabel", gui)
			f.Name = "SourcesHubBanner"
			f.AnchorPoint = Vector2.new(0.5, 0)
			f.Position = UDim2.new(0.5, 0, 0, 42)
			f.Size = UDim2.new(0, 0, 0, 24); f.AutomaticSize = Enum.AutomaticSize.X
			f.BackgroundColor3 = C.BG; f.BackgroundTransparency = 0.35
			f.BorderSizePixel = 0; f.ZIndex = 920
			f.Text = tostring(text or ""); f.Font = Enum.Font.GothamBold; f.TextSize = 10
			f.TextColor3 = C.WHITE
			local pad = Instance.new("UIPadding", f)
			pad.PaddingLeft = UDim.new(0, 12); pad.PaddingRight = UDim.new(0, 12)
			corner(f, 12); addLivingStroke(f, 1.2); liveGrad(f)
			local sc = Instance.new("UIScale", f); sc.Scale = 0.85
			TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
			task.delay(tonumber(dur) or 5, function()
				if bannerToken == mine and f.Parent then
					TweenService:Create(f, TweenInfo.new(0.3), {BackgroundTransparency = 1, TextTransparency = 1}):Play()
					task.delay(0.3, function() pcall(function() f:Destroy() end) end)
				end
			end)
		end)
	end

	lib.GuideSeen = function() return store["GuideSeen"] == true end
	lib.MarkGuideSeen = function() setStored("GuideSeen", true) end
	lib.ThemeNames = TH.names
	lib.ThemeName = TH.current
	lib.SetTheme = function(name)
		if not TH.sets[name] or name == TH.current then return end
		local list = TH.pairsFor(TH.current, name)
		TH.current = name; lib.ThemeName = name
		TH.apply(name)
		TH.recolor(gui, list)
		TH.runHooks(list)
		setStored("Theme", name)
	end
	lib.ThemeHooks = TH.hooks
	lib.RunThemeHooksFrom = function(fromName)
		if TH.sets[fromName] and fromName ~= TH.current then TH.runHooks(TH.pairsFor(fromName, TH.current)) end
	end

	lib.SoundOn = true
	local sounds = {}
	lib.Sound = function(kind)
		if lib.SoundOn == false or not lib.ParticlesOn then return end
		pcall(function()
			local snd = sounds[kind]
			if not snd or not snd.Parent then
				snd = Instance.new("Sound")
				snd.Volume = kind == "click" and 0.25 or 0.35
				snd.SoundId = kind == "click" and "rbxasset://sounds/switch.wav" or "rbxasset://sounds/electronicpingshort.wav"
				snd.PlaybackSpeed = kind == "close" and 0.8 or (kind == "open" and 1.15 or 1)
				snd.Parent = gui
				sounds[kind] = snd
			end
			snd:Play()
		end)
	end

	-- ---------- risk badge: centered, red blinking stroke, gone after a few seconds ----------
	local riskToken = 0
	lib.RiskBadge = function(title, text, dur)
		pcall(function()
			riskToken = riskToken + 1
			local mine = riskToken
			local old = gui:FindFirstChild("SourcesHubRisk")
			if old then old:Destroy() end
			local f = Instance.new("Frame", gui)
			f.Name = "SourcesHubRisk"
			f.AnchorPoint = Vector2.new(0.5, 0.5); f.Position = UDim2.new(0.5, 0, 0.5, 0)
			f.Size = UDim2.new(0, 300, 0, 92)
			f.BackgroundColor3 = C.BG; f.BackgroundTransparency = 0.25
			f.BorderSizePixel = 0; f.ZIndex = 930
			corner(f, 14)
			local st = Instance.new("UIStroke", f)
			st.Color = C.RED; st.Thickness = 2.5; st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			local t = label(f, tostring(title or ""), UDim2.new(1, -20, 0, 18), C.RED, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
			t.Position = UDim2.new(0, 10, 0, 8); t.TextSize = 12; t.ZIndex = 931
			local d = label(f, tostring(text or ""), UDim2.new(1, -24, 0, 56), C.SILVER, Enum.Font.GothamMedium, Enum.TextXAlignment.Center)
			d.Position = UDim2.new(0, 12, 0, 28); d.TextSize = 10; d.TextWrapped = true
			d.TextYAlignment = Enum.TextYAlignment.Top; d.ZIndex = 931
			local sc = Instance.new("UIScale", f); sc.Scale = 0.85
			TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
			local endAt = os.clock() + (tonumber(dur) or 10)
			task.spawn(function()
				local dim = false
				while riskToken == mine and f.Parent and os.clock() < endAt do
					dim = not dim
					TweenService:Create(st, TweenInfo.new(0.3, Enum.EasingStyle.Sine), {Transparency = dim and 0.85 or 0}):Play()
					task.wait(0.3)
				end
				if riskToken == mine and f.Parent then
					TweenService:Create(f, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
					TweenService:Create(st, TweenInfo.new(0.3), {Transparency = 1}):Play()
					TweenService:Create(t, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
					TweenService:Create(d, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
					task.wait(0.35)
					pcall(function() f:Destroy() end)
				end
			end)
		end)
	end

	-- ---------- startup splash: what loaded and what did not ----------
	lib.Splash = function(lines)
		pcall(function()
			local rowH = 17
			local H = 54 + #lines * rowH
			local f = Instance.new("Frame", gui)
			f.Name = "SourcesHubSplash"
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.new(0.5, 0, 0.5, 0)
			f.Size = UDim2.new(0, 258, 0, H)
			f.BackgroundColor3 = C.BG; f.BorderSizePixel = 0; f.ZIndex = 950
			corner(f, 18); addLivingStroke(f, 1.5, true)
			local sc = Instance.new("UIScale", f); sc.Scale = 0.8
			local bad = 0
			for _, ln in ipairs(lines) do if ln.Ok == false then bad = bad + 1 end end
			local t = label(f, "Sources Hub", UDim2.new(1, -24, 0, 22), C.WHITE, Enum.Font.GothamBold)
			t.Position = UDim2.new(0, 14, 0, 8); t.TextSize = 15; t.ZIndex = 951; liveGrad(t)
			local sub = label(f, bad == 0 and "Everything loaded" or (bad .. " problem" .. (bad > 1 and "s" or "") .. " found"),
				UDim2.new(1, -24, 0, 12), bad == 0 and C.GREEN or C.GOLD, Enum.Font.GothamMedium)
			sub.Position = UDim2.new(0, 14, 0, 30); sub.TextSize = 9.5; sub.ZIndex = 951
			for i, ln in ipairs(lines) do
				local y = 50 + (i - 1) * rowH
				local dot = Instance.new("Frame", f)
				dot.Size = UDim2.new(0, 7, 0, 7); dot.Position = UDim2.new(0, 16, 0, y + 5)
				dot.BackgroundColor3 = ln.Ok and C.GREEN or C.RED; dot.BorderSizePixel = 0; dot.ZIndex = 951
				corner(dot, 4)
				local tx = label(f, ln.Text, UDim2.new(1, -40, 0, rowH), ln.Ok and C.SILVER or C.GOLD, Enum.Font.GothamMedium)
				tx.Position = UDim2.new(0, 30, 0, y); tx.TextSize = 9.5; tx.ZIndex = 951
				tx.TextTruncate = Enum.TextTruncate.AtEnd
			end
			TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
			task.delay(bad == 0 and 3.5 or 7, function()
				if f.Parent then
					TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.85}):Play()
					task.delay(0.26, function() pcall(function() f:Destroy() end) end)
				end
			end)
		end)
	end

	-- ---------- window ----------
	local windows = {}

	-- sidebar order and little drawn icons (no external images needed)
	local TAB_ORDER = {Farm = 1, StealPanel = 2, Events = 3, Config = 999}
	local TAB_ICON = {StealPanel = "egg", Events = "diamond", Config = "sliders"}
	local function drawTabIcon(btn, kind)
		local box = Instance.new("Frame", btn)
		box.Name = "Icon"; box.BackgroundTransparency = 1
		box.Size = UDim2.fromOffset(18, 18); box.Position = UDim2.new(0, 9, 0.5, -9)
		if kind == "egg" then
			local e = Instance.new("Frame", box)
			e.Size = UDim2.fromOffset(12, 16); e.Position = UDim2.new(0.5, -6, 0.5, -8)
			e.BackgroundColor3 = C.MOON2; e.BorderSizePixel = 0
			local ec = Instance.new("UICorner", e); ec.CornerRadius = UDim.new(0.5, 0)
			local eg = Instance.new("UIGradient", e); eg.Rotation = 90
			eg.Color = ColorSequence.new(C.WHITE, C.MOON)
			local spot = Instance.new("Frame", e)
			spot.Size = UDim2.fromOffset(3, 3); spot.Position = UDim2.new(0, 3, 0, 4)
			spot.BackgroundColor3 = C.WHITE; spot.BorderSizePixel = 0
			corner(spot, 2)
		elseif kind == "diamond" then
			local d = Instance.new("Frame", box)
			d.Size = UDim2.fromOffset(11, 11); d.Position = UDim2.new(0.5, -5, 0.5, -5)
			d.Rotation = 45; d.BackgroundColor3 = C.MOON; d.BackgroundTransparency = 0.5; d.BorderSizePixel = 0
			stroke(d, C.MOON2, 1.5)
			local dot = Instance.new("Frame", box)
			dot.Size = UDim2.fromOffset(4, 4); dot.Position = UDim2.new(0.5, -2, 0.5, -2)
			dot.BackgroundColor3 = C.WHITE; dot.BorderSizePixel = 0
			corner(dot, 2)
		elseif kind == "sliders" then
			local knobs = {10, 3, 8}
			for i = 1, 3 do
				local y = 3 + (i - 1) * 6
				local line = Instance.new("Frame", box)
				line.Size = UDim2.fromOffset(16, 2); line.Position = UDim2.new(0, 1, 0, y)
				line.BackgroundColor3 = C.MOON2; line.BorderSizePixel = 0
				local knob = Instance.new("Frame", box)
				knob.Size = UDim2.fromOffset(5, 5); knob.Position = UDim2.new(0, knobs[i], 0, y - 1)
				knob.BackgroundColor3 = C.WHITE; knob.BorderSizePixel = 0
				corner(knob, 2)
			end
		else
			local b = Instance.new("Frame", box)
			b.Size = UDim2.fromOffset(5, 5); b.Position = UDim2.new(0, 4, 0.5, -2)
			b.BackgroundColor3 = C.DEEP4; b.BorderSizePixel = 0
			corner(b, 2)
		end
	end
	
	local function newWindow(cfg)
		local w = {tabs = {}, order = {}, current = nil, name = cfg.name, isMain = cfg.isMain == true, newLook = true}
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)
		local H = math.min(cfg.h, math.max(240, vp.Y - 60))
		local frame = Instance.new("Frame", gui)
		frame.Name = cfg.frameName
		frame.Size = UDim2.new(0, cfg.w, 0, H)
		frame.Position = cfg.pos
		frame.BackgroundColor3 = C.BG
		frame.BorderSizePixel = 0
		frame.ClipsDescendants = true
		frame.Active = true
		frame.ZIndex = cfg.z or 20
		corner(frame, 8)
		addLivingStroke(frame, 1.5, true, true)
		local winScale = Instance.new("UIScale", frame)
		w.frame = frame

		local bgImg, subtitle
		do
			bgImg = Instance.new("ImageLabel", frame)
			bgImg.Name = "Bg"
			bgImg.BackgroundTransparency = 1; bgImg.BorderSizePixel = 0
			bgImg.Image = "rbxassetid://111331179075915"
			bgImg.ScaleType = Enum.ScaleType.Fit
			bgImg.ImageTransparency = 0.88
			bgImg.AnchorPoint = Vector2.new(0.5, 0.5)
			bgImg.Position = UDim2.new(0.5, 0, 0.56, 0)
			local bgSize = math.floor(math.min(cfg.w, H) * 0.86)
			bgImg.Size = UDim2.fromOffset(bgSize, bgSize)
			bgImg.ZIndex = 1
		end

		local header, moon, title, close, mini, sep, tabBar, content
		local contentX, bodyTopV = 0, 46
		do
			header = Instance.new("Frame", frame)
			header.Size = UDim2.new(1, 0, 0, 42)
			header.BackgroundColor3 = C.HEADER; header.BorderSizePixel = 0
			corner(header, 8)
			moon = Instance.new("ImageLabel", header)
			moon.Size = UDim2.new(0, 24, 0, 24); moon.Position = UDim2.new(0, 9, 0.5, -12)
			moon.BackgroundTransparency = 1; moon.BorderSizePixel = 0
			moon.Image = "rbxassetid://111331179075915"
			moon.ScaleType = Enum.ScaleType.Fit
			title = Instance.new("TextLabel", header)
			title.BackgroundTransparency = 1
			title.Text = cfg.title; title.TextSize = 14; title.Font = Enum.Font.GothamBold
			title.TextXAlignment = Enum.TextXAlignment.Left; title.TextColor3 = C.WHITE
			title.TextTruncate = Enum.TextTruncate.AtEnd
			if cfg.subtitle then
				title.Size = UDim2.new(1, -112, 0, 20); title.Position = UDim2.new(0, 40, 0, 4)
				subtitle = label(header, tostring(cfg.subtitle), UDim2.new(1, -112, 0, 12), C.DIM, Enum.Font.GothamMedium)
				subtitle.Position = UDim2.new(0, 40, 0, 25); subtitle.TextSize = 9; subtitle.TextTruncate = Enum.TextTruncate.AtEnd
				if cfg.subtitleCopy then
					subtitle.TextColor3 = C.MOON2
					local sb = Instance.new("TextButton", subtitle)
					sb.Size = UDim2.new(1, 0, 1, 0); sb.BackgroundTransparency = 1; sb.Text = ""
					sb.MouseButton1Click:Connect(function()
						pcall(function() setclipboard(cfg.subtitleCopy) end)
						if lib.Notify then lib.Notify("Discord", "Link copied: " .. cfg.subtitleCopy, 2.5) end
					end)
				end
			else
				title.Size = UDim2.new(1, -112, 1, 0); title.Position = UDim2.new(0, 40, 0, 0)
			end
			liveGrad(title, true, true)
			close = Instance.new("TextButton", header)
			close.Size = UDim2.new(0, 22, 0, 22); close.Position = UDim2.new(1, -30, 0.5, -11)
			close.BackgroundColor3 = Color3.fromRGB(58, 20, 20); close.Text = "X"; close.TextSize = 11
			close.TextColor3 = C.RED; close.Font = Enum.Font.GothamBold; close.BorderSizePixel = 0
			corner(close, 6); addLivingStroke(close, 1); pressFx(close)
			mini = Instance.new("TextButton", header)
			mini.Size = UDim2.new(0, 22, 0, 22); mini.Position = UDim2.new(1, -56, 0.5, -11)
			mini.BackgroundColor3 = Color3.fromRGB(24, 26, 35); mini.Text = "-"; mini.TextSize = 13
			mini.TextColor3 = C.ACCENT2; mini.Font = Enum.Font.GothamBold; mini.BorderSizePixel = 0
			corner(mini, 6); addLivingStroke(mini, 1); pressFx(mini)
			sep = Instance.new("Frame", frame)
			sep.Size = UDim2.new(1, 0, 0, 2); sep.Position = UDim2.new(0, 0, 0, 42)
			sep.BackgroundColor3 = C.WHITE; sep.BorderSizePixel = 0
			liveGrad(sep, true, true)

			if not cfg.noTabs then
				contentX = 108
				tabBar = Instance.new("ScrollingFrame", frame)
				tabBar.Name = "SideTabs"
				tabBar.Size = UDim2.new(0, contentX, 1, -44); tabBar.Position = UDim2.new(0, 0, 0, 44)
				tabBar.BackgroundColor3 = C.ROW; tabBar.BackgroundTransparency = 0.45; tabBar.BorderSizePixel = 0
				tabBar.ScrollBarThickness = 0
				tabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
				tabBar.AutomaticCanvasSize = Enum.AutomaticSize.Y
				tabBar.ScrollingDirection = Enum.ScrollingDirection.Y
				local tl2 = Instance.new("UIListLayout", tabBar)
				tl2.Padding = UDim.new(0, 3); tl2.SortOrder = Enum.SortOrder.LayoutOrder
				local tp2 = Instance.new("UIPadding", tabBar)
				tp2.PaddingTop = UDim.new(0, 6); tp2.PaddingLeft = UDim.new(0, 4); tp2.PaddingRight = UDim.new(0, 4)
				local sideLine = Instance.new("Frame", frame)
				sideLine.Name = "SideLine"
				sideLine.Size = UDim2.new(0, 1, 1, -44); sideLine.Position = UDim2.new(0, contentX, 0, 44)
				sideLine.BackgroundColor3 = C.BORDER; sideLine.BorderSizePixel = 0
				w.sideLine = sideLine
				w.tabBar = tabBar
			end
			content = Instance.new("Frame", frame)
			content.Size = UDim2.new(1, -contentX, 1, -46); content.Position = UDim2.new(0, contentX, 0, 46)
			content.BackgroundTransparency = 1; content.ClipsDescendants = true
			w.content = content
		end

		-- picker overlay (single / multi select) covering the content area
		local ov = Instance.new("Frame", frame)
		ov.Size = UDim2.new(1, -contentX, 1, -bodyTopV); ov.Position = UDim2.new(0, contentX, 0, bodyTopV)
		ov.BackgroundColor3 = C.BG; ov.BorderSizePixel = 0; ov.Visible = false; ov.ZIndex = 300
		local ovHead = Instance.new("Frame", ov)
		ovHead.Size = UDim2.new(1, 0, 0, 26); ovHead.BackgroundTransparency = 1; ovHead.ZIndex = 301
		local ovTitle = label(ovHead, "", UDim2.new(1, -120, 1, 0), C.WHITE, Enum.Font.GothamBold)
		ovTitle.Position = UDim2.new(0, 8, 0, 0); ovTitle.TextSize = 11.5; ovTitle.ZIndex = 301
		local ovClear = Instance.new("TextButton", ovHead)
		ovClear.Size = UDim2.new(0, 46, 0, 20); ovClear.Position = UDim2.new(1, -104, 0, 3)
		ovClear.BackgroundColor3 = Color3.fromRGB(24, 26, 35); ovClear.Text = "Clear"; ovClear.TextSize = 10
		ovClear.TextColor3 = C.SILVER; ovClear.Font = Enum.Font.GothamBold; ovClear.BorderSizePixel = 0; ovClear.ZIndex = 301
		corner(ovClear, 8); addLivingStroke(ovClear, 1); pressFx(ovClear)
		local ovDone = Instance.new("TextButton", ovHead)
		ovDone.Size = UDim2.new(0, 46, 0, 20); ovDone.Position = UDim2.new(1, -54, 0, 3)
		ovDone.BackgroundColor3 = C.MOON; ovDone.Text = "Done"; ovDone.TextSize = 10.5
		ovDone.TextColor3 = C.MOONTEXT; ovDone.Font = Enum.Font.GothamBold; ovDone.BorderSizePixel = 0; ovDone.ZIndex = 301
		corner(ovDone, 8); addLivingStroke(ovDone, 1); pressFx(ovDone)
		local ovList = Instance.new("ScrollingFrame", ov)
		ovList.Size = UDim2.new(1, 0, 1, -30); ovList.Position = UDim2.new(0, 0, 0, 28)
		ovList.BackgroundTransparency = 1; ovList.BorderSizePixel = 0; ovList.ScrollBarThickness = 3
		ovList.ScrollBarImageColor3 = C.ACCENT; ovList.CanvasSize = UDim2.new(0, 0, 0, 0)
		ovList.AutomaticCanvasSize = Enum.AutomaticSize.Y; ovList.ZIndex = 301
		local ovl = Instance.new("UIListLayout", ovList)
		ovl.Padding = UDim.new(0, 3); ovl.SortOrder = Enum.SortOrder.LayoutOrder
		local ovp = Instance.new("UIPadding", ovList)
		ovp.PaddingLeft = UDim.new(0, 8); ovp.PaddingRight = UDim.new(0, 8); ovp.PaddingTop = UDim.new(0, 4)
		ovDone.MouseButton1Click:Connect(function() ov.Visible = false end)
		local clearFn
		ovClear.MouseButton1Click:Connect(function() if clearFn then clearFn() end end)

		-- opts: {title, options, multi, isOn(opt), toggle(opt), onClear}
		function w.Pick(opts)
			ovTitle.Text = opts.title
			for _, c in ipairs(ovList:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
			ovClear.Visible = opts.multi == true
			local marks, rowsOf = {}, {}
			local function refreshMarks()
				for opt, m in pairs(marks) do
					local on = opts.isOn(opt)
					m.BackgroundColor3 = on and C.MOON or Color3.fromRGB(10, 14, 22)
					local rr = rowsOf[opt]
					if rr then
						rr.row.BackgroundColor3 = on and C.ON_BG or C.ROW
						rr.edge.BackgroundTransparency = on and 0 or 1
					end
				end
			end
			clearFn = function() if opts.onClear then opts.onClear() end; refreshMarks() end
			for i, opt in ipairs(opts.options) do
				local r = Instance.new("Frame", ovList)
				r.Size = UDim2.new(1, 0, 0, 30); r.BackgroundColor3 = C.ROW; r.BackgroundTransparency = 0.15
				r.BorderSizePixel = 0; r.ZIndex = 301; r.LayoutOrder = i
				corner(r, 8); addLivingStroke(r, 1)
				local edge = Instance.new("Frame", r)
				edge.Size = UDim2.new(0, 3, 1, -10); edge.Position = UDim2.new(0, 0, 0, 5)
				edge.BackgroundColor3 = C.MOON2; edge.BackgroundTransparency = 1; edge.BorderSizePixel = 0; edge.ZIndex = 302
				corner(edge, 2)
				rowsOf[opt] = {row = r, edge = edge}
				local off = 12
				local ic = iconOf(opt)
				if ic then
					local img = Instance.new("ImageLabel", r)
					img.Size = UDim2.fromOffset(22, 22); img.Position = UDim2.new(0, 8, 0.5, -11)
					img.BackgroundTransparency = 1; img.Image = ic; img.ZIndex = 302
					off = 36
				end
				local ol = label(r, tostring(opt), UDim2.new(1, -off - 38, 1, 0), C.WHITE, Enum.Font.GothamMedium)
				ol.Position = UDim2.new(0, off, 0, 0); ol.TextSize = 11; ol.ZIndex = 302
				ol.TextTruncate = Enum.TextTruncate.AtEnd
				local mark = Instance.new("Frame", r)
				mark.Size = UDim2.new(0, 18, 0, 18); mark.Position = UDim2.new(1, -28, 0.5, -9)
				mark.BorderSizePixel = 0; mark.ZIndex = 302
				corner(mark, opts.multi and 5 or 9); addLivingStroke(mark, 1)
				marks[opt] = mark
				local b = Instance.new("TextButton", r)
				b.Size = UDim2.new(1, 0, 1, 0); b.BackgroundTransparency = 1; b.Text = ""; b.ZIndex = 303
				b.MouseButton1Click:Connect(function()
					opts.toggle(opt)
					if opts.multi then refreshMarks() else ov.Visible = false end
				end)
			end
			refreshMarks()
			ov.Visible = true
		end

		-- minimize / close / drag
		local minimized, fullH = false, H
		local hudFps, hudPing, hudLabel, hudHint = 60, 0, nil, nil
		if cfg.isMain then
			local acc, frames = 0, 0
			RunService.RenderStepped:Connect(function(dt)
				acc = acc + dt; frames = frames + 1
				if acc >= 0.5 then
						hudFps = math.floor(frames / acc + 0.5); acc = 0; frames = 0
						lib.T0 = lib.T0 or os.clock()
						if os.clock() - lib.T0 > 6 then lib.PeakFps = math.max(lib.PeakFps or 0, hudFps) end
						local ref = lib.RefFps or 60

						if lib.PeakFps then
							for _, candidate in ipairs({ 30, 60, 90, 120, 144, 165, 240 }) do
								ref = candidate
								if candidate >= lib.PeakFps * 0.92 then break end
							end
						end

						if lib.RefFps ~= ref then
							lib.RefFps = ref
							if lib.OnRefFps then pcall(lib.OnRefFps, ref) end
						end
						local lowT, highT = (lib.RefFps or 60) * 0.58, (lib.RefFps or 60) * 0.75
						if hudFps < lowT then lib.AnimAuto = false elseif hudFps >= highT then lib.AnimAuto = true end
					end
			end)
			hudLabel = label(header, "", UDim2.new(1, -44, 0, 20), C.WHITE, Enum.Font.GothamBold, Enum.TextXAlignment.Left)
			hudLabel.Position = UDim2.new(0, 38, 0, 4); hudLabel.TextSize = 13; hudLabel.Visible = false
			liveGrad(hudLabel, true)
			hudHint = label(header, "tap to open", UDim2.new(1, -44, 0, 12), C.SILVER, Enum.Font.GothamBold, Enum.TextXAlignment.Left)
			hudHint.Position = UDim2.new(0, 38, 0, 24); hudHint.TextSize = 8.5; hudHint.Visible = false
			local tripStroke = Instance.new("UIStroke", frame)
			tripStroke.Thickness = 2.5; tripStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			tripStroke.Color = C.MOON2; tripStroke.Enabled = false
			local tripGrad = Instance.new("UIGradient", tripStroke)
			task.spawn(function()
				while frame.Parent do
					task.wait(0.2)
					local prog, kind = nil, nil
					if minimized and lib.TripStatus then
						local ok, a, b = pcall(lib.TripStatus)
						if ok then prog, kind = a, b end
					end
					if prog then
						prog = math.clamp(prog, 0.02, 0.99)
						tripGrad.Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(prog, 0),
							NumberSequenceKeypoint.new(math.min(prog + 0.002, 0.999), 1), NumberSequenceKeypoint.new(1, 1)})
						tripStroke.Color = kind == "fail" and C.RED or (kind == "done" and C.GREEN or C.MOON2)
						tripStroke.Enabled = true
					else
						tripStroke.Enabled = false
					end
				end
			end)
			task.spawn(function()
				while frame.Parent do
					task.wait(0.5)
					if minimized then
						pcall(function()
							hudPing = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5)
						end)
						hudLabel.Text = hudFps .. " FPS   " .. hudPing .. " ms"
					end
				end
			end)
		end
		local arrowBtn
		local function updateArrow()
			if arrowBtn then arrowBtn.Visible = minimized and w.wantOpen ~= false end
		end
		if not cfg.isMain then
			local tray = gui:FindFirstChild("PanelTray")
			if not tray then
				tray = Instance.new("Frame", gui)
				tray.Name = "PanelTray"; tray.BackgroundTransparency = 1
				tray.AnchorPoint = Vector2.new(0.5, 0); tray.Position = UDim2.new(0.5, 0, 0, 4)
				tray.Size = UDim2.new(0, 0, 0, 30); tray.AutomaticSize = Enum.AutomaticSize.X
				tray.ZIndex = 400
				local tl = Instance.new("UIListLayout", tray)
				tl.FillDirection = Enum.FillDirection.Horizontal; tl.Padding = UDim.new(0, 8)
				tl.HorizontalAlignment = Enum.HorizontalAlignment.Center
				tl.VerticalAlignment = Enum.VerticalAlignment.Center
			end
			arrowBtn = Instance.new("TextButton", tray)
			arrowBtn.Size = UDim2.new(0, 0, 0, 28); arrowBtn.AutomaticSize = Enum.AutomaticSize.X
			arrowBtn.AutoButtonColor = false
			arrowBtn.BackgroundColor3 = C.ROW; arrowBtn.BackgroundTransparency = 0.2
			arrowBtn.Text = "v  " .. string.upper(tostring(cfg.title or "")); arrowBtn.Font = Enum.Font.GothamBold; arrowBtn.TextSize = 12
			arrowBtn.TextColor3 = C.WHITE; arrowBtn.ZIndex = 401; arrowBtn.Visible = false
			local ap = Instance.new("UIPadding", arrowBtn)
			ap.PaddingLeft = UDim.new(0, 14); ap.PaddingRight = UDim.new(0, 14)
			corner(arrowBtn, 14); addLivingStroke(arrowBtn, 1.5); liveGrad(arrowBtn)
			arrowBtn.MouseButton1Click:Connect(function() w.SetMinimized(false) end)
		end
		-- dust forge: the panel builds itself from small stroked tiles and dust, and folds back into the top bar
		local forgeToken = 0
		local function forge(mode)
			forgeToken = forgeToken + 1
			local mine = forgeToken
			local old = gui:FindFirstChild("Forge_" .. tostring(cfg.name))
			if old then old:Destroy() end

			if mode == "in" then frame.Visible = true; updateArrow() end
			local scr = gui.AbsoluteSize
			local fp = frame.Position
			local margin = 5
			local pos = Vector2.new(fp.X.Scale * scr.X + fp.X.Offset - margin, fp.Y.Scale * scr.Y + fp.Y.Offset - margin)
			local size = Vector2.new(cfg.w + margin * 2, fullH + margin * 2)

			if size.X < 20 or size.Y < 20 then
				frame.Visible = mode == "in"
				updateArrow()
				return
			end
			local box = Instance.new("Folder", gui)
			box.Name = "Forge_" .. tostring(cfg.name)
			local cols = 6
			local tw = size.X / cols
			local rows = math.max(5, math.floor(size.Y / tw + 0.5))
			local th = size.Y / rows
			local center = pos + size / 2
			local maxDist = (size / 2).Magnitude
			local tiles = {}

			for r = 0, rows - 1 do
				for c = 0, cols - 1 do
					local tile = Instance.new("Frame", box)
					tile.BorderSizePixel = 0
					tile.BackgroundColor3 = C.BG
					tile.ZIndex = 800
					tile.AnchorPoint = Vector2.new(0.5, 0.5)
					tile.Size = UDim2.fromOffset(tw + 1, th + 1)
					local home = pos + Vector2.new((c + 0.5) * tw, (r + 0.5) * th)
					tile.Position = UDim2.fromOffset(home.X, home.Y)
					local ts = Instance.new("UIStroke", tile)
					ts.Color = C.DEEP4; ts.Thickness = 1; ts.Transparency = 0.2
					tiles[#tiles + 1] = {Frame = tile, Stroke = ts, Home = home, Delay = (home - center).Magnitude / maxDist}
				end
			end

			local function dust(count, fromOutside)
				for i = 1, count do
					local d = Instance.new("Frame", box)
					d.Size = UDim2.fromOffset(3, 3); d.AnchorPoint = Vector2.new(0.5, 0.5)
					d.BorderSizePixel = 0; d.ZIndex = 801
					d.BackgroundColor3 = i % 2 == 0 and C.MOON2 or C.DEEP4
					local inside = Vector2.new(pos.X + math.random() * size.X, pos.Y + math.random() * size.Y)
					local outside = inside + Vector2.new(math.random(-90, 90), math.random(-90, 90))
					local a, b = inside, outside
					if fromOutside then a, b = outside, inside end
					d.Position = UDim2.fromOffset(a.X, a.Y)
					d.BackgroundTransparency = fromOutside and 0.2 or 0.6
					TweenService:Create(d, TweenInfo.new(0.5 + math.random() * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Position = UDim2.fromOffset(b.X, b.Y), BackgroundTransparency = fromOutside and 0.9 or 1}):Play()
				end
			end

			if mode == "in" then
				dust(18, true)

				for _, t in ipairs(tiles) do
					task.delay(t.Delay * 0.45 + math.random() * 0.1, function()
						if forgeToken ~= mine then return end
						TweenService:Create(t.Frame, TweenInfo.new(0.26, Enum.EasingStyle.Quad), {
							BackgroundTransparency = 1, Size = UDim2.fromOffset(tw * 0.35, th * 0.35)}):Play()
						TweenService:Create(t.Stroke, TweenInfo.new(0.26), {Transparency = 1}):Play()
					end)
				end
				task.delay(0.95, function()
					if forgeToken == mine then box:Destroy() end
					updateArrow()
				end)
			else
				for _, t in ipairs(tiles) do
					t.Frame.BackgroundTransparency = 1
					t.Frame.Size = UDim2.fromOffset(tw * 0.35, th * 0.35)
					t.Stroke.Transparency = 1
					task.delay((1 - t.Delay) * 0.3 + math.random() * 0.08, function()
						if forgeToken ~= mine then return end
						TweenService:Create(t.Frame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
							BackgroundTransparency = 0, Size = UDim2.fromOffset(tw + 1, th + 1)}):Play()
						TweenService:Create(t.Stroke, TweenInfo.new(0.2), {Transparency = 0.2}):Play()
					end)
				end
				dust(10, false)
				task.delay(0.5, function()
					if forgeToken ~= mine then return end
					frame.Visible = false
					local target = Vector2.new(gui.AbsoluteSize.X / 2, 18)

					for _, t in ipairs(tiles) do
						local jitter = Vector2.new(math.random(-40, 40), math.random(-6, 6))
						TweenService:Create(t.Frame, TweenInfo.new(0.45 + math.random() * 0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
							Position = UDim2.fromOffset(target.X + jitter.X, target.Y + jitter.Y),
							Size = UDim2.fromOffset(4, 4), BackgroundTransparency = 0.6}):Play()
						TweenService:Create(t.Stroke, TweenInfo.new(0.5), {Transparency = 0.8}):Play()
					end
					task.delay(0.8, function()
						if forgeToken == mine then box:Destroy() end
						updateArrow()
					end)
				end)
			end
		end

		local function setMinimized(on)
			minimized = on
			if not cfg.isMain then
				if on then
					ov.Visible = false
					forge("out")
				else
					zTop = zTop + 1; frame.ZIndex = zTop
					winScale.Scale = 1
					mini.Text = "-"
					forge("in")
				end
				return
			end
			if cfg.isMain then
				if on then
					content.Visible = false; sep.Visible = false; ov.Visible = false
					if tabBar then tabBar.Visible = false end
					if w.sideLine then w.sideLine.Visible = false end
					title.Visible = false; mini.Visible = false; close.Visible = false; bgImg.Visible = false
					if subtitle then subtitle.Visible = false end
					hudLabel.Text = hudFps .. " FPS   " .. hudPing .. " ms"
					hudLabel.Visible = true; hudHint.Visible = true
					header.BackgroundTransparency = 1
					TweenService:Create(frame, TweenInfo.new(0.22, Enum.EasingStyle.Quint), {
						Size = UDim2.new(0, 168, 0, 42), BackgroundTransparency = 0.12}):Play()
				else
					hudLabel.Visible = false; hudHint.Visible = false
					title.Visible = true; mini.Visible = true; close.Visible = true; bgImg.Visible = true
					if subtitle then subtitle.Visible = true end
					header.BackgroundTransparency = 0
					TweenService:Create(frame, TweenInfo.new(0.22, Enum.EasingStyle.Quint), {
						Size = UDim2.new(0, cfg.w, 0, fullH), BackgroundTransparency = 0}):Play()
					content.Visible = true; sep.Visible = true
					if tabBar then tabBar.Visible = true end
					if w.sideLine then w.sideLine.Visible = true end
					mini.Text = "-"
				end
				return
			end
			if on then
				TweenService:Create(frame, TweenInfo.new(0.2), {Size = UDim2.new(0, cfg.w, 0, 42)}):Play()
				content.Visible = false; sep.Visible = false; ov.Visible = false
				if tabBar then tabBar.Visible = false end
					if w.sideLine then w.sideLine.Visible = false end
				mini.Text = "+"
			else
				TweenService:Create(frame, TweenInfo.new(0.2), {Size = UDim2.new(0, cfg.w, 0, fullH)}):Play()
				content.Visible = true; sep.Visible = true
				if tabBar then tabBar.Visible = true end
					if w.sideLine then w.sideLine.Visible = true end
				mini.Text = "-"
			end
		end
		w.SetMinimized = setMinimized
		
		mini.MouseButton1Click:Connect(function() setMinimized(not minimized) end)
		do
			local tapAt
			header.InputBegan:Connect(function(inp)
				if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
					tapAt = inp.Position
				end
			end)
			header.InputEnded:Connect(function(inp)
				if minimized and tapAt and (inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch) then
					if (inp.Position - tapAt).Magnitude < 8 then setMinimized(false) end
					tapAt = nil
				end
			end)
		end
		w.OnClose = newSignalList()
		local closing = 0
		function w.SetOpen(on)
			on = on == true
			if lib.Sound and on ~= w.IsOpen() then lib.Sound(on and "open" or "close") end
			closing = closing + 1
			local mine = closing
			if on and minimized and not cfg.isMain then minimized = false; mini.Text = "-" end
			if on then
				zTop = zTop + 1; frame.ZIndex = zTop
				winScale.Scale = 0.9
				frame.Visible = true
				TweenService:Create(winScale, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
			elseif frame.Visible then
				TweenService:Create(winScale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.88}):Play()
				task.delay(0.17, function()
					if closing == mine then frame.Visible = false; winScale.Scale = 1 end
				end)
			end
			w.wantOpen = on
			updateArrow()
			w.OnClose.Fire(on)

			if on and cfg.startCollapsed and not w.collapsedInit then
				w.collapsedInit = true
				setMinimized(true)
			end
		end
		function w.IsOpen() return frame.Visible and w.wantOpen ~= false end
		close.MouseButton1Click:Connect(function()
			if cfg.isMain then
				pcall(function() if lib.OnUnload then lib.OnUnload() end end)
				gui:Destroy()
			else
				setMinimized(true)
			end
		end)
		drag(header, frame)

		-- tabs
		function w.AddTab(name, hidden, display)
			local tab = {name = name, sections = {}, window = w}
			local page = Instance.new("ScrollingFrame", content)
			page.Name = name; page.Size = UDim2.new(1, 0, 1, 0)
			page.BackgroundTransparency = 1; page.BorderSizePixel = 0; page.ScrollBarThickness = 3
			page.ScrollBarImageColor3 = C.ACCENT; page.CanvasSize = UDim2.new(0, 0, 0, 0)
			page.AutomaticCanvasSize = Enum.AutomaticSize.Y; page.Visible = false
			local pl = Instance.new("UIListLayout", page)
			pl.Padding = UDim.new(0, 5); pl.SortOrder = Enum.SortOrder.LayoutOrder
			local pp = Instance.new("UIPadding", page)
			pp.PaddingTop = UDim.new(0, 4); pp.PaddingLeft = UDim.new(0, 6); pp.PaddingRight = UDim.new(0, 6)
			pp.PaddingBottom = UDim.new(0, 10)
			tab.page = page
			if tabBar and not hidden then
				local btn = Instance.new("TextButton", tabBar)
				btn.Size = UDim2.new(1, 0, 0, 30)
				btn.BackgroundColor3 = C.ROW; btn.BackgroundTransparency = 1
				btn.Text = ""; btn.AutoButtonColor = false; btn.BorderSizePixel = 0; btn.LayoutOrder = TAB_ORDER[name] or (10 + #w.order)
				corner(btn, 6)
				drawTabIcon(btn, TAB_ICON[name])
				local bl = label(btn, display or name, UDim2.new(1, -38, 1, 0), C.TABIDLE, Enum.Font.GothamBold)
				bl.Position = UDim2.new(0, 32, 0, 0); bl.TextSize = 11; bl.TextTruncate = Enum.TextTruncate.AtEnd
				local bar = Instance.new("Frame", btn)
				bar.Size = UDim2.new(0, 3, 0, 16); bar.Position = UDim2.new(0, 0, 0.5, -8)
				bar.BackgroundColor3 = C.MOON2; bar.BorderSizePixel = 0; bar.BackgroundTransparency = 1
				corner(bar, 2)
				pressFx(btn)
				tab.btn = btn; tab.btnLabel = bl; tab.bar = bar
				btn.MouseButton1Click:Connect(function() w.Select(name) end)
			end
			if hidden then page.Parent = nil end
			w.tabs[name] = tab
			table.insert(w.order, name)
			return tab
		end
		function w.Select(name)
			local target = w.tabs[name]
			if not target then return end
			local firstSelect = w.current == nil
			w.current = name
			for n, t in pairs(w.tabs) do
				local on = n == name
				if t.holder and t.holder.Parent then t.holder.Visible = on end
				if on and not t.page.Visible and not firstSelect then
					t.basePos = t.basePos or t.page.Position
					t.page.Position = t.basePos + UDim2.fromOffset(18, 0)
					t.page.Visible = true
					TweenService:Create(t.page, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Position = t.basePos}):Play()
				else
					t.page.Visible = on
					if not on and t.basePos then t.page.Position = t.basePos end
				end
				if t.btn then
					TweenService:Create(t.btn, TweenInfo.new(0.15), {
						BackgroundColor3 = on and C.ON_BG or C.ROW,
						BackgroundTransparency = on and 0.2 or 1}):Play()
					TweenService:Create(t.btnLabel, TweenInfo.new(0.15), {TextColor3 = on and C.WHITE or C.TABIDLE}):Play()
					TweenService:Create(t.bar, TweenInfo.new(0.18), {BackgroundTransparency = on and 0 or 1}):Play()
				end
			end
		end
		w.header = header; w.title = title; w.moon = moon
		table.insert(windows, w)
		return w
	end

	-- ---------- controls ----------
	local fireAtFinalize = {}          -- controls whose callback runs once the UI is complete
	local groups = {}
	local function pathKey(section, name) return section.tab.name .. ">" .. section.name .. ">" .. tostring(name) end

	local Section = {}
	Section.__index = Section

	-- one row in the section body; SubOf rows sit indented under their parent
	function Section:_slot(height, subOf)
		local order
		if subOf and subOf._slotInfo then
			subOf._slotInfo.children = subOf._slotInfo.children + 1
			order = subOf._slotInfo.order + subOf._slotInfo.children
		else
			self.count = self.count + 1
			order = self.count * 1000
		end
		local holder = Instance.new("Frame", self.body)
		holder.Size = UDim2.new(1, 0, 0, height)
		holder.BackgroundTransparency = 1
		holder.LayoutOrder = order
		local indent = subOf and 14 or 0
		local row = Instance.new("Frame", holder)
		row.Size = UDim2.new(1, -indent - 6, 1, 0); row.Position = UDim2.new(0, indent, 0, 0)
		row.BackgroundColor3 = C.ROW; row.BackgroundTransparency = 0.35; row.BorderSizePixel = 0
		corner(row, 10); addLivingStroke(row, 1)
		local info = {order = order, children = 0, holder = holder, subs = {}, open = false}
		do
			row.BackgroundTransparency = 0.15
			local edge = Instance.new("Frame", row)
			edge.Name = "Edge"; edge.Size = UDim2.new(0, 3, 1, -12); edge.Position = UDim2.new(0, 0, 0, 6)
			edge.BackgroundColor3 = C.MOON2; edge.BackgroundTransparency = 1; edge.BorderSizePixel = 0
			corner(edge, 2)
			info.edge = edge
		end
		if subOf and subOf._slotInfo then
			table.insert(subOf._slotInfo.subs, holder)
			subOf._refreshSubs()
		end
		return holder, row, info
	end

	local function nameLabel(row, text, width)
		local l = label(row, tostring(text), UDim2.new(1, width or -62, 0, 18), C.WHITE, Enum.Font.GothamBold)
		l.Position = UDim2.new(0, 10, 0, 5); l.TextSize = 10.5; l.TextTruncate = Enum.TextTruncate.AtEnd
		liveGrad(l)
		return l
	end
	local function noteLabel(row, text)
		if not text or text == "" then return end
		local n = label(row, tostring(text), UDim2.new(1, -18, 0, 12), C.DIM, Enum.Font.GothamMedium)
		n.Position = UDim2.new(0, 10, 0, 22); n.TextSize = 8.5; n.TextTruncate = Enum.TextTruncate.AtEnd
	end
	-- parent handles show / hide their SubOf rows (visible while ON or opened by hand)
	local function makeParentLogic(handle, info, getOn)
		local btn
		handle._slotInfo = info
		handle._refreshSubs = function()
			local show = info.open or getOn()
			for _, h in ipairs(info.subs) do h.Visible = show end
			if btn then btn.Visible = #info.subs > 0; btn.Text = ">"; btn.Rotation = show and 90 or 0 end
		end
		handle._setArrow = function(b) btn = b; handle._refreshSubs() end
	end
	local function arrowButton(row, handle, info, x)
		local b = Instance.new("TextButton", row)
		b.Size = UDim2.new(0, 18, 0, 18); b.Position = UDim2.new(1, x, 0, 5)
		b.BackgroundTransparency = 1; b.Text = ">"; b.TextSize = 12; b.TextColor3 = C.DIM
		b.Font = Enum.Font.GothamBold; b.Visible = false
		pressFx(b)
		b.MouseButton1Click:Connect(function() info.open = not info.open; handle._refreshSubs() end)
		handle._setArrow(b)
	end

	local function register(section, cfg, handle, kind)
		handle.Name = cfg.Name
		handle.Kind = kind
		lib.handles[pathKey(section, cfg.Name)] = handle
	end

	function Section:CreateToggle(cfg)
		local key = pathKey(self, cfg.Name)
		local value = cfg.Default == true
		local restored = false
		if store[key] ~= nil then value = store[key] == true; restored = value ~= (cfg.Default == true) end
		local h = {}
		local hasNote = cfg.Note and cfg.Note ~= ""
		local holder, row, info = self:_slot(hasNote and 38 or 28, cfg.SubOf)
		local mainStyle = info.edge ~= nil
		nameLabel(row, cfg.Name, mainStyle and -92 or -84)
		noteLabel(row, cfg.Note)
		local pill, btn, setSwitch
		local function paintRow(on)
			if not mainStyle then return end
			TweenService:Create(row, TweenInfo.new(0.18), {BackgroundColor3 = on and C.ON_BG or C.ROW}):Play()
			TweenService:Create(info.edge, TweenInfo.new(0.18), {BackgroundTransparency = on and 0 or 1}):Play()
		end
		if mainStyle then
			pill, btn, setSwitch = makeCheck(row, value)
			pill.Position = UDim2.new(1, -34, 0.5, -13)
			if value then row.BackgroundColor3 = C.ON_BG; info.edge.BackgroundTransparency = 0 end
		else
			pill, btn, setSwitch = makeSwitch(row, value)
			pill.Position = UDim2.new(1, -52, 0, 4)
		end
		h.Instance = holder
		h._controller = {GetValue = function() return value end}
		local subs = newSignalList()
		local groupRef
		makeParentLogic(h, info, function() return value end)
		arrowButton(row, h, info, mainStyle and -58 or -74)
		function h.Get() return value end
		function h.GetValue() return value end
		function h.Subscribe(_, fn) return subs.Connect(fn) end
		local set
		set = function(_, v, fire)
			v = v == true
			if v == value then return end
			value = v
			setSwitch(v); paintRow(v)
			setStored(key, v)
			h._refreshSubs()
			if v and groupRef then
				local on = {}
				for _, m in ipairs(groupRef.members) do if m ~= h and m.Get() then on[#on + 1] = m end end
				local extra = #on + 1 - (groupRef.max or 1)
				for i = 1, extra do if on[i] then on[i]:Set(false, true) end end
			end
			if fire ~= false and cfg.Callback then task.spawn(cfg.Callback, v) end
			subs.Fire(v)
		end
		h.Set = set
		function h.JoinExclusiveGroup(_, g)
			groupRef = g
			table.insert(g.members, h)
		end
		btn.MouseButton1Click:Connect(function() set(h, not value, true) end)
		register(self, cfg, h, "Toggle")
		if cfg.Callback and (value or restored) then table.insert(fireAtFinalize, function() cfg.Callback(value) end) end
		return h
	end

	function Section:CreateButton(cfg)
		local hasNote = cfg.Note and cfg.Note ~= ""
		local holder, row = self:_slot(hasNote and 38 or 28, cfg.SubOf)
		local bw = cfg.ButtonWidth or 64
		nameLabel(row, cfg.Name, -(bw + 20))
		noteLabel(row, cfg.Note)
		local b = Instance.new("TextButton", row)
		b.Size = UDim2.new(0, bw, 0, 22); b.Position = UDim2.new(1, -(bw + 8), 0.5, -11)
		b.BackgroundColor3 = C.MOON; b.BackgroundTransparency = 0; b.AutoButtonColor = false
		b.Text = ""; b.BorderSizePixel = 0
		corner(b, 7)
		local bg = Instance.new("UIGradient", b)
		bg.Rotation = 90
		bg.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, C.MOON2), ColorSequenceKeypoint.new(1, C.MOON)})
		local bl = label(b, cfg.ButtonText or "Run", UDim2.new(1, 0, 1, 0), C.WHITE, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
		bl.TextSize = 10; bl.ZIndex = 2
		local pulse = pressFx(b)
		local h = {Instance = holder}
		function h.SetText(t) bl.Text = tostring(t) end
		function h.Pulse() pulse() end
		local busy = false
		b.MouseButton1Click:Connect(function()
			pulse()
			bg.Offset = Vector2.new(0, -1)
			TweenService:Create(bg, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Offset = Vector2.new(0, 0)}):Play()
			if cfg.Callback then task.spawn(cfg.Callback) end
			if cfg.ConfirmText and not busy then
				busy = true
				local old = bl.Text
				bl.Text = cfg.ConfirmText
				b.BackgroundColor3 = Color3.fromRGB(34, 140, 90)
				task.delay(1.4, function() bl.Text = old; b.BackgroundColor3 = C.MOON; busy = false end)
			end
		end)
		register(self, cfg, h, "Button")
		return h
	end

	function Section:_createButtonOld(cfg)
		local hasNote = cfg.Note and cfg.Note ~= ""
		local holder, row = self:_slot(hasNote and 38 or 28, cfg.SubOf)
		local bw = cfg.ButtonWidth or 64
		nameLabel(row, cfg.Name, -(bw + 20))
		noteLabel(row, cfg.Note)
		local b = Instance.new("TextButton", row)
		b.Size = UDim2.new(0, bw, 0, 20); b.Position = UDim2.new(1, -(bw + 8), 0, hasNote and 9 or 4)
		b.BackgroundColor3 = C.ROW; b.BackgroundTransparency = 0.35; b.AutoButtonColor = false
		b.Text = ""; b.BorderSizePixel = 0
		corner(b, 8); addLivingStroke(b, 1)
		local bl = label(b, cfg.ButtonText or "Run", UDim2.new(1, 0, 1, 0), C.WHITE, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
		bl.TextSize = 9.5; bl.ZIndex = 2
		liveGrad(bl)
		local pulse = pressFx(b)
		local h = {Instance = holder}
		function h.SetText(t) bl.Text = tostring(t) end
		function h.Pulse() pulse() end
		local busy = false
		b.MouseButton1Click:Connect(function()
			pulse()
			if cfg.Callback then task.spawn(cfg.Callback) end
			if cfg.ConfirmText and not busy then
				busy = true
				local old = bl.Text
				bl.Text = cfg.ConfirmText
				b.BackgroundColor3 = Color3.fromRGB(20, 80, 50)
				task.delay(1.4, function() bl.Text = old; b.BackgroundColor3 = C.ROW; busy = false end)
			end
		end)
		register(self, cfg, h, "Button")
		return h
	end

	function Section:CreateText(cfg)
		local holder = Instance.new("Frame", self.body)
		self.count = self.count + 1
		holder.LayoutOrder = self.count * 1000
		holder.Size = UDim2.new(1, 0, 0, 0); holder.AutomaticSize = Enum.AutomaticSize.Y
		holder.BackgroundTransparency = 1
		local info
		if cfg.SubOf and cfg.SubOf._slotInfo then
			cfg.SubOf._slotInfo.children = cfg.SubOf._slotInfo.children + 1
			holder.LayoutOrder = cfg.SubOf._slotInfo.order + cfg.SubOf._slotInfo.children
			table.insert(cfg.SubOf._slotInfo.subs, holder); cfg.SubOf._refreshSubs()
		end
		local row = Instance.new("Frame", holder)
		row.Size = UDim2.new(1, -6, 0, 0); row.AutomaticSize = Enum.AutomaticSize.Y
		row.BackgroundColor3 = C.ROW; row.BackgroundTransparency = 0.25; row.BorderSizePixel = 0
		corner(row, 10); addLivingStroke(row, 1)
		local rl = Instance.new("UIListLayout", row)
		rl.SortOrder = Enum.SortOrder.LayoutOrder; rl.Padding = UDim.new(0, 1)
		local rp = Instance.new("UIPadding", row)
		rp.PaddingLeft = UDim.new(0, 10); rp.PaddingRight = UDim.new(0, 10); rp.PaddingTop = UDim.new(0, 5); rp.PaddingBottom = UDim.new(0, 6)
		local nm = label(row, string.upper(tostring(cfg.Name or "")), UDim2.new(1, 0, 0, 11), C.MOON2, Enum.Font.GothamBold)
		nm.TextSize = 8.5; nm.LayoutOrder = 1
		local tx = label(row, tostring(cfg.Text or ""), UDim2.new(1, 0, 0, 0), C.SILVER, Enum.Font.GothamMedium)
		tx.TextSize = 10; tx.TextWrapped = true; tx.AutomaticSize = Enum.AutomaticSize.Y
		tx.TextYAlignment = Enum.TextYAlignment.Top; tx.LayoutOrder = 2
		local h = {Instance = holder}
		local text = tostring(cfg.Text or "")
		function h.Set(_, t) text = tostring(t); tx.Text = text end
		function h.Get() return text end
		register(self, cfg, h, "Text")
		return h
	end

	function Section:CreateLabel(cfg)
		return self:CreateText({Name = cfg.Name, Text = cfg.Text, SubOf = cfg.SubOf})
	end

	function Section:CreateSlider(cfg)
		local key = pathKey(self, cfg.Name)
		local minV, maxV = tonumber(cfg.Min) or 0, tonumber(cfg.Max) or 100
		local inc = tonumber(cfg.Increment) or 1
		local value = tonumber(cfg.Default) or minV
		local restored = false
		if type(store[key]) == "number" then value = store[key]; restored = value ~= (tonumber(cfg.Default) or minV) end
		local holder, row = self:_slot(40, cfg.SubOf)
		nameLabel(row, cfg.Name, -96)
		local valBox = Instance.new("TextBox", row)
		valBox.Size = UDim2.new(0, 84, 0, 18); valBox.Position = UDim2.new(1, -92, 0, 4)
		valBox.BackgroundTransparency = 1; valBox.TextColor3 = C.ACCENT2; valBox.Font = Enum.Font.GothamBold
		valBox.TextSize = 10.5; valBox.TextXAlignment = Enum.TextXAlignment.Right; valBox.ClearTextOnFocus = false
		valBox.Text = ""
		local track = Instance.new("Frame", row)
		track.Size = UDim2.new(1, -20, 0, 5); track.Position = UDim2.new(0, 10, 1, -11)
		track.BackgroundColor3 = C.TRACKOFF; track.BorderSizePixel = 0; corner(track, 3)
		local fill = Instance.new("Frame", track)
		fill.Size = UDim2.new(0, 0, 1, 0); fill.BackgroundColor3 = C.ACCENT; fill.BorderSizePixel = 0; corner(fill, 3)
		local fg = Instance.new("UIGradient", fill)
		fg.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, C.DEEP2), ColorSequenceKeypoint.new(1, C.ACCENT2)})
		local thumb = Instance.new("Frame", track)
		thumb.Size = UDim2.new(0, 12, 0, 12); thumb.AnchorPoint = Vector2.new(0.5, 0.5)
		thumb.BackgroundColor3 = C.WHITE; thumb.BorderSizePixel = 0; corner(thumb, 6); stroke(thumb, C.ACCENT, 1.5)
		local h = {Instance = holder}
		local function fmt(v)
			if cfg.ValueFormat then
				local ok, s = pcall(cfg.ValueFormat, v)
				if ok and s then return tostring(s) end
			end
			local s
			if cfg.AllowDecimals or inc % 1 ~= 0 then s = string.format("%g", math.floor(v * 100 + 0.5) / 100) else s = tostring(math.floor(v + 0.5)) end
			if cfg.Unit and cfg.Unit ~= "" then s = s .. " " .. cfg.Unit end
			return s
		end
		local function snap(v)
			v = math.clamp(v, minV, maxV)
			if not cfg.AllowDecimals and inc > 0 then v = minV + math.floor((v - minV) / inc + 0.5) * inc end
			return math.clamp(v, minV, maxV)
		end
		local function paint()
			local t = maxV > minV and (value - minV) / (maxV - minV) or 0
			fill.Size = UDim2.new(t, 0, 1, 0); thumb.Position = UDim2.new(t, 0, 0.5, 0)
			if not valBox:IsFocused() then valBox.Text = fmt(value) end
		end
		local subs = newSignalList()
		local function set(_, v, fire)
			v = snap(tonumber(v) or value)
			if v == value then paint(); return end
			value = v; paint(); setStored(key, v)
			if fire ~= false and cfg.Callback then task.spawn(cfg.Callback, v) end
			subs.Fire(v)
		end
		h.Set = set
		function h.Get() return value end
		function h.GetValue() return value end
		function h.Subscribe(_, fn) return subs.Connect(fn) end
		value = snap(value); paint()
		local dragging = false
		track.InputBegan:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then dragging = true end
		end)
		UIS.InputEnded:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then dragging = false end
		end)
		UIS.InputChanged:Connect(function(inp)
			if not dragging then return end
			if inp.UserInputType ~= Enum.UserInputType.MouseMovement and inp.UserInputType ~= Enum.UserInputType.Touch then return end
			local a, s = track.AbsolutePosition, track.AbsoluteSize
			local rel = math.clamp((inp.Position.X - a.X) / math.max(s.X, 1), 0, 1)
			set(h, minV + (maxV - minV) * rel, true)
		end)
		valBox.FocusLost:Connect(function()
			local n
			if cfg.ValueParse then local ok, r = pcall(cfg.ValueParse, valBox.Text); if ok then n = r end end
			n = n or tonumber(string.match(valBox.Text, "-?%d+%.?%d*"))
			if n then set(h, n, true) else paint() end
		end)
		register(self, cfg, h, "Slider")
		if cfg.Callback then table.insert(fireAtFinalize, function() cfg.Callback(value) end) end
		return h
	end

	function Section:CreateDropdown(cfg)
		local key = pathKey(self, cfg.Name)
		local options = cfg.Options or {}
		local value = cfg.Default
		if type(store[key]) == "string" and table.find(options, store[key]) then value = store[key] end
		if value == nil then value = options[1] end
		local hasNote = cfg.Note and cfg.Note ~= ""
		local holder, row = self:_slot(hasNote and 38 or 28, cfg.SubOf)
		nameLabel(row, cfg.Name, -130)
		noteLabel(row, cfg.Note)
		local box = Instance.new("TextButton", row)
		box.Size = UDim2.new(0, 116, 0, 20); box.Position = UDim2.new(1, -124, 0, 4)
		box.BackgroundColor3 = Color3.fromRGB(12, 18, 32); box.TextColor3 = C.WHITE
		box.Text = tostring(value); box.TextSize = 9.5; box.Font = Enum.Font.GothamBold; box.BorderSizePixel = 0
		box.TextTruncate = Enum.TextTruncate.AtEnd
		corner(box, 6); addLivingStroke(box, 1)
		local h = {Instance = holder}
		local subs = newSignalList()
		local function set(_, v, fire)
			if v == nil or v == value then return end
			value = v; box.Text = tostring(v); setStored(key, v)
			if fire ~= false and cfg.Callback then task.spawn(cfg.Callback, v) end
			subs.Fire(v)
		end
		h.Set = set
		function h.Get() return value end
		function h.GetValue() return value end
		function h.Subscribe(_, fn) return subs.Connect(fn) end
		function h.SetOptions(_, opts, default, fire)
			options = opts or {}
			local nv = default
			if nv == nil or not table.find(options, nv) then nv = table.find(options, value) and value or options[1] end
			value = nil
			set(h, nv, fire == true)
			if value == nil then value = nv; box.Text = tostring(nv) end
		end
		box.MouseButton1Click:Connect(function()
			self.window.Pick({title = tostring(cfg.Name), options = options, multi = false,
				isOn = function(o) return o == value end,
				toggle = function(o) set(h, o, true) end})
		end)
		register(self, cfg, h, "Dropdown")
		if cfg.Callback then table.insert(fireAtFinalize, function() cfg.Callback(value) end) end
		return h
	end

	function Section:CreateMultiDropdown(cfg)
		local key = pathKey(self, cfg.Name)
		local options = cfg.Options or {}
		local selected = {}
		if type(cfg.Default) == "table" then
			for k, v in pairs(cfg.Default) do
				if v == true and type(k) == "string" then selected[k] = true elseif type(v) == "string" then selected[v] = true end
			end
		end
		local restored = false
		if type(store[key]) == "table" then
			selected = {}
			for k, v in pairs(store[key]) do if v == true then selected[k] = true end end
			restored = next(selected) ~= nil
		end
		local hasNote = cfg.Note and cfg.Note ~= ""
		local holder, row = self:_slot(hasNote and 38 or 28, cfg.SubOf)
		nameLabel(row, cfg.Name, -100)
		noteLabel(row, cfg.Note)
		local box = Instance.new("TextButton", row)
		box.Size = UDim2.new(0, 86, 0, 20); box.Position = UDim2.new(1, -94, 0, 4)
		box.BackgroundColor3 = Color3.fromRGB(12, 18, 32); box.TextColor3 = C.WHITE
		box.TextSize = 9.5; box.Font = Enum.Font.GothamBold; box.BorderSizePixel = 0; box.Name = "Value"
		corner(box, 6); addLivingStroke(box, 1)
		local h = {Instance = holder}
		local subs = newSignalList()
		local function count() local n = 0; for _ in pairs(selected) do n = n + 1 end; return n end
		local function paint()
			local n = count()
			if n == 0 then box.Text = "All"
			elseif n == 1 then box.Text = tostring(next(selected))
			else box.Text = n .. " picked" end
		end
		local function copy() local c = {}; for k in pairs(selected) do c[k] = true end; return c end
		local function changed(fire)
			paint(); setStored(key, copy())
			if fire ~= false and cfg.Callback then task.spawn(cfg.Callback, copy()) end
			subs.Fire(copy())
		end
		paint()
		function h.Get() return copy() end
		function h.GetValue() return copy() end
		function h.Subscribe(_, fn) return subs.Connect(fn) end
		function h.Set(_, v, fire)
			selected = {}
			if type(v) == "table" then
				for k, x in pairs(v) do
					if x == true and type(k) == "string" then selected[k] = true elseif type(x) == "string" then selected[x] = true end
				end
			end
			changed(fire)
		end
		function h.SetOptions(_, opts) options = opts or {} end
		box.MouseButton1Click:Connect(function()
			self.window.Pick({title = tostring(cfg.Name), options = options, multi = true,
				isOn = function(o) return selected[o] == true end,
				toggle = function(o) if selected[o] then selected[o] = nil else selected[o] = true end; changed(true) end,
				onClear = function() selected = {}; changed(true) end})
		end)
		register(self, cfg, h, "MultiDropdown")
		if cfg.Callback and (restored or count() > 0) then table.insert(fireAtFinalize, function() cfg.Callback(copy()) end) end
		return h
	end

	function Section:CreateInput(cfg)
		local key = pathKey(self, cfg.Name)
		local value = cfg.Default and tostring(cfg.Default) or ""
		if type(store[key]) == "string" then value = store[key] end
		local holder, row = self:_slot(28, cfg.SubOf)
		nameLabel(row, cfg.Name, -130)
		local tb = Instance.new("TextBox", row)
		tb.Size = UDim2.new(0, 116, 0, 20); tb.Position = UDim2.new(1, -124, 0, 4)
		tb.BackgroundColor3 = Color3.fromRGB(12, 18, 32); tb.TextColor3 = C.WHITE
		tb.PlaceholderText = cfg.Placeholder or ""; tb.PlaceholderColor3 = C.DIM
		tb.Text = value; tb.TextSize = 9.5; tb.Font = Enum.Font.GothamMedium; tb.BorderSizePixel = 0
		tb.ClearTextOnFocus = false
		corner(tb, 6); addLivingStroke(tb, 1)
		local h = {Instance = holder}
		function h.Get() return value end
		function h.GetValue() return value end
		function h.Set(_, v, fire)
			value = tostring(v or ""); tb.Text = value; setStored(key, value)
			if fire ~= false and cfg.Callback then task.spawn(cfg.Callback, value) end
		end
		tb.FocusLost:Connect(function()
			local t = tb.Text
			if cfg.MaxLength then t = string.sub(t, 1, cfg.MaxLength) end
			h.Set(h, t, true)
		end)
		register(self, cfg, h, "Input")
		return h
	end

	-- ---------- sections / tabs ----------
	local EVENT_SECTIONS = {["Dr Scramble Lab & Mech"] = true}
	local HIDDEN_TABS = {Predictor = true, Discord = true}

	local Tab = {}
	Tab.__index = Tab
	function Tab:CreateSection(cfg)
		local target = self
		local win = self.window
		if EVENT_SECTIONS[cfg.Name] and lib.eventsWindow then
			target = lib.eventsWindow.tabs.Events
			win = lib.eventsWindow
		end
		local sec = setmetatable({name = cfg.Name, tab = target, window = win, count = 0}, Section)
		local page = target.page
		target.secCount = (target.secCount or 0) + 1
		local head = Instance.new("TextButton", page)
		head.Size = UDim2.new(1, 0, 0, 28); head.BackgroundTransparency = 1; head.Text = ""
		head.LayoutOrder = target.secCount * 10
		local accent = Instance.new("Frame", head)
		accent.Size = UDim2.new(0, 3, 0, 14); accent.Position = UDim2.new(0, 2, 0.5, -7)
		accent.BackgroundColor3 = C.MOON; accent.BorderSizePixel = 0; corner(accent, 2)
		local lbl = label(head, tostring(cfg.Name), UDim2.new(1, -30, 1, 0), C.WHITE, Enum.Font.GothamBold)
		lbl.TextSize = 12.5; lbl.Position = UDim2.new(0, 12, 0, 0)
		local arrow = label(head, ">", UDim2.new(0, 16, 1, 0), C.DIM, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
		arrow.Position = UDim2.new(1, -18, 0, 0); arrow.TextSize = 10
		local body = Instance.new("Frame", page)
		body.Size = UDim2.new(1, 0, 0, 0); body.AutomaticSize = Enum.AutomaticSize.Y
		body.BackgroundTransparency = 1; body.LayoutOrder = target.secCount * 10 + 1
		local bl = Instance.new("UIListLayout", body)
		bl.Padding = UDim.new(0, 4); bl.SortOrder = Enum.SortOrder.LayoutOrder
		sec.body = body
		local open = cfg.Expanded ~= false
		body.Visible = open; arrow.Rotation = open and 90 or 0
		head.MouseButton1Click:Connect(function()
			open = not open; body.Visible = open; arrow.Rotation = open and 90 or 0
		end)
		return sec
	end
	for _, name in ipairs({"CreateToggle", "CreateButton", "CreateText", "CreateLabel", "CreateSlider", "CreateDropdown", "CreateMultiDropdown", "CreateInput"}) do
		Tab[name] = function(self, cfg)
			self._default = self._default or self:CreateSection({Name = "General", Expanded = true})
			return self._default[name](self._default, cfg)
		end
	end

	-- ---------- extra tool windows (same look/API as the Events window) ----------
	lib.NewToolWindow = function(cfg)
		local main = lib.mainWindow
		local key = cfg.tabName or "Tool"
		local raw = main.tabs[key]
		if not raw then raw = main.AddTab(key, false, cfg.tabTitle or cfg.title) end
		-- a fresh holder and page every time: the logic may tear the panel down and rebuild it
		if raw.holder and raw.holder.Parent then raw.holder:Destroy() end
		if raw.page and raw.page.Parent then raw.page:Destroy() end
		local holder = Instance.new("Frame", main.content)
		holder.Name = "Embed_" .. key
		holder.Size = UDim2.new(1, 0, 1, 0); holder.BackgroundTransparency = 1; holder.ClipsDescendants = true
		holder.Visible = main.current == key
		local page = Instance.new("ScrollingFrame", holder)
		page.Name = key; page.Size = UDim2.new(1, 0, 1, 0)
		page.BackgroundTransparency = 1; page.BorderSizePixel = 0; page.ScrollBarThickness = 3
		page.ScrollBarImageColor3 = C.ACCENT; page.CanvasSize = UDim2.new(0, 0, 0, 0)
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y; page.Visible = main.current == key
		local pl = Instance.new("UIListLayout", page)
		pl.Padding = UDim.new(0, 5); pl.SortOrder = Enum.SortOrder.LayoutOrder
		local pp = Instance.new("UIPadding", page)
		pp.PaddingTop = UDim.new(0, 4); pp.PaddingLeft = UDim.new(0, 6); pp.PaddingRight = UDim.new(0, 6)
		pp.PaddingBottom = UDim.new(0, 10)
		raw.page = page; raw.holder = holder; raw.basePos = nil
		local tab = setmetatable(raw, Tab)
		tab.window = main
		local win = {tab = tab, content = holder, frame = holder, name = cfg.name, title = Instance.new("TextLabel")}
		win.OnClose = newSignalList()
		win.wantOpen = false
		function win.SetOpen(on) win.wantOpen = on == true; win.OnClose.Fire(on == true) end
		function win.IsOpen() return win.wantOpen end
		function win.Select() main.Select(key) end
		return win
	end

	-- ---------- window API ----------
	local Win = {}
	Win.__index = Win
	function Win:GetDefaultTab() return self.defaultTab end
	function Win:CreateTab(cfg)
		local hidden = HIDDEN_TABS[cfg.Name] == true
		local t = self.main.AddTab(cfg.Name, hidden)
		t.window = self.main
		local tab = setmetatable(t, Tab)
		return tab
	end
	function Win:CreateState(cfg)
		local key = "State>" .. tostring(cfg.Name)
		local value = cfg.Default == true
		if store[key] ~= nil then value = store[key] == true end
		local subs = newSignalList()
		local st = {Name = cfg.Name}
		function st.Get() return value end
		function st.Set(_, v)
			v = v == true
			if v == value then return end
			value = v; setStored(key, v); subs.Fire(v)
		end
		function st.Subscribe(_, fn) return subs.Connect(fn) end
		lib.states[cfg.Name] = st
		return st
	end
	function Win:GetState(name) return lib.states[name] end
	function Win:CreateExclusiveGroup(cfg) return {members = {}, max = cfg.MaxActive or 1, Name = cfg.Name} end

	function lib:CreateWindow(cfg)
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)
		local mw = math.min(480, math.max(340, vp.X - 24))
		local mh = math.min(370, math.max(240, vp.Y - 60))
		local main = newWindow({name = "main", frameName = "Main", title = "Sources Hub", subtitle = "discord.gg/sourceshubs", subtitleCopy = "discord.gg/sourceshubs", w = mw, h = mh,
			pos = UDim2.new(0.5, -math.floor(mw / 2), 0.5, -math.floor(mh / 2)), isMain = true, z = 20})
		local events = main
		lib.eventsWindow = main
		lib.newWindow = newWindow
		lib.UI = {C = C, corner = corner, stroke = stroke, label = label, liveGrad = liveGrad,
			addLivingStroke = addLivingStroke, makeSwitch = makeSwitch, gui = gui, Tween = TweenService, drag = drag}
		lib.mainWindow = main
		local w = setmetatable({main = main, events = events}, Win)
		w.defaultTab = setmetatable(main.AddTab(cfg.DefaultTab or "Main"), Tab)
		w.defaultTab.window = main
		main.AddTab("Events", false, "Event")
		return w
	end

	-- ---------- dock (floating quick buttons) ----------
	local function buildDock()
		local SZ, GAP, TOP, RIGHT = 44, 8, 66, 10
		local locked = store["Dock>Locked"] == true
		local defs = {
			{id = "speed", label = "Speed"}, {id = "lock", label = "Lock"},
			
			
		}
		for i, def in ipairs(defs) do
			local col, rw = (i - 1) % 2, math.floor((i - 1) / 2)
			local btn = Instance.new("TextButton", gui)
			btn.Name = "YE_Float_" .. def.id
			btn.Size = UDim2.new(0, SZ, 0, SZ)
			btn.Position = UDim2.new(1, -(SZ * 2 + GAP + RIGHT) + col * (SZ + GAP), 0, TOP + rw * (SZ + GAP))
			btn.BackgroundColor3 = C.ROW; btn.BackgroundTransparency = 0.25; btn.BorderSizePixel = 0
			btn.Text = ""; btn.AutoButtonColor = false; btn.ZIndex = 500; btn.Active = true
			corner(btn, 12); addLivingStroke(btn, 1.5); pressFx(btn)
			local l = Instance.new("TextLabel", btn)
			l.Size = UDim2.new(1, 0, 1, 0); l.BackgroundTransparency = 1; l.Text = def.label
			l.TextColor3 = C.WHITE; l.Font = Enum.Font.GothamBold; l.TextSize = 9; l.TextWrapped = true; l.ZIndex = 501
			liveGrad(l)
			local glow = Instance.new("UIStroke", btn)
			glow.Thickness = 2.5; glow.Color = C.GREEN; glow.Transparency = 1
			glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			local dot = Instance.new("Frame", btn)
			dot.Size = UDim2.new(0, 7, 0, 7); dot.Position = UDim2.new(1, -11, 0, 4)
			dot.BackgroundColor3 = C.GREEN; dot.BorderSizePixel = 0; dot.Visible = false; dot.ZIndex = 502
			corner(dot, 4)
			local function mark(on)
				dot.Visible = on == true
				TweenService:Create(glow, TweenInfo.new(0.25), {Transparency = on == true and 0.45 or 1}):Play()
			end
			local dragging, ds, dp, moved = false, nil, nil, false
			btn.InputBegan:Connect(function(inp)
				if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
					dragging = not locked; ds = inp.Position; dp = btn.Position; moved = false
				end
			end)
			UIS.InputChanged:Connect(function(inp)
				if not dragging then return end
				if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
					local d = inp.Position - ds
					if d.Magnitude > 4 then moved = true end
					btn.Position = UDim2.new(dp.X.Scale, dp.X.Offset + d.X, dp.Y.Scale, dp.Y.Offset + d.Y)
				end
			end)
			UIS.InputEnded:Connect(function(inp)
				if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then dragging = false end
			end)
			btn.MouseButton1Click:Connect(function()
				if moved then return end
				if def.id == "speed" then
					local hd = lib.handles["Player>Movement>Speed Boost"]
					if hd then hd:Set(not hd.Get(), true) end
				elseif def.id == "lock" then
					locked = not locked; setStored("Dock>Locked", locked); mark(locked)
				end
			end)
			if def.id == "speed" then
				task.spawn(function()
					while btn.Parent do
						local hd = lib.handles["Player>Movement>Speed Boost"]
						mark(hd and hd.Get())
						task.wait(0.5)
					end
				end)
			else
				mark(locked)
			end
		end
	end

	local function importConfig(text)
		text = (tostring(text or ""):gsub("^%s+", ""))
		text = (text:gsub("%s+$", ""))
		local body = text:match("^SHCFG1:(.+)$") or text
		local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
		if not ok or type(data) ~= "table" then return nil, "That is not a valid config" end
		local n = 0
		for key, v in pairs(data) do
			if type(key) == "string" and key ~= "GuideSeen" and key ~= "Dock>Locked" then
				local tv = type(v)
				if tv == "boolean" or tv == "number" or tv == "string" or tv == "table" then
					local h = lib.handles[key]
					if key == "Theme" then
						if tv == "string" then pcall(lib.SetTheme, v); n = n + 1 end
					elseif h and type(h.Set) == "function" then
						if pcall(h.Set, h, v, true) then n = n + 1 end
					elseif key:sub(1, 6) == "State>" then
						local st = lib.states[key:sub(7)]
						if st then pcall(st.Set, st, v); n = n + 1 end
					else
						store[key] = v; n = n + 1
					end
				end
			end
		end
		saveSoon()
		return n
	end

	local function buildConfigTab()
		local main = lib.mainWindow
		local raw = main.AddTab("Config", false, "Config")
		raw.window = main
		local tab = setmetatable(raw, Tab)
		local sec = tab:CreateSection({Name = "Share config", Expanded = true})
		sec:CreateText({Name = "How it works", Text = "Press Copy and send the text to a friend. They paste it in the box and press Import: every setting is applied at once."})
		local status
		local function say(t) if status then status:Set(t) end end
		sec:CreateButton({Name = "Copy my config", ButtonText = "Copy", ConfirmText = "Copied", Callback = function()
			local out = {}
			for k, v in pairs(store) do
				if k ~= "GuideSeen" and k ~= "Dock>Locked" then out[k] = v end
			end
			local ok, json = pcall(function() return HttpService:JSONEncode(out) end)
			if not ok then say("Could not read the config"); return end
			local text = "SHCFG1:" .. json
			local copied = pcall(function() setclipboard(text) end)
			say(copied and ("Copied " .. #text .. " characters") or "Clipboard is not available on this executor")
		end})
		local _, row = sec:_slot(56)
		local tb = Instance.new("TextBox", row)
		tb.Name = "ConfigBox"
		tb.Size = UDim2.new(1, -16, 1, -16); tb.Position = UDim2.new(0, 8, 0, 8)
		tb.BackgroundColor3 = C.BG; tb.TextColor3 = C.WHITE
		tb.PlaceholderText = "Paste a shared config here"; tb.PlaceholderColor3 = C.DIM
		tb.Text = ""; tb.TextSize = 10; tb.Font = Enum.Font.GothamMedium; tb.BorderSizePixel = 0
		tb.ClearTextOnFocus = false; tb.TextWrapped = true; tb.MultiLine = true
		tb.TextXAlignment = Enum.TextXAlignment.Left; tb.TextYAlignment = Enum.TextYAlignment.Top
		corner(tb, 6); addLivingStroke(tb, 1)
		sec:CreateButton({Name = "Import pasted config", ButtonText = "Import", ConfirmText = "Done", Callback = function()
			local n, err = importConfig(tb.Text)
			if n then say("Imported " .. n .. " settings"); tb.Text = "" else say(err) end
		end})
		status = sec:CreateText({Name = "Status", Text = "Ready"})
	end

	function lib:Finalize(cfg)
		local main = lib.mainWindow
		buildConfigTab()
		main.Select((cfg and cfg.MainTab and cfg.MainTab.name) or main.order[1])
		main.frame.Visible = true
		buildDock()
		
		task.delay(3, function() lib.ParticlesOn = true end)
		UIS.InputBegan:Connect(function(inp, gp)
			if gp then return end
			if inp.KeyCode == Enum.KeyCode.RightShift then main.SetOpen(not main.IsOpen()) end
		end)
		-- run every callback once now that all controls exist (restores saved state)
		for _, fn in ipairs(fireAtFinalize) do task.spawn(pcall, fn) end
		table.clear(fireAtFinalize)
	end
	lib.CreateWindow = lib.CreateWindow
end
local SourcesLib = lib

return SourcesLib

end
-- Scenarios UI : une seule fenetre (onglets Steal / Event / Config), widgets, themes, partage de config
local passes, failures = 0, 0
local function check(name, cond)
	if cond then passes += 1 else failures += 1; print("FAIL: " .. name) end
end
tick = tick or os.clock
game.IsLoaded = function() return true end
task.delay = function(t, fn, ...) local a = {...}; task.spawn(function() task.wait(t); fn(table.unpack(a)) end) end
Vector2 = {new = function(x, y) return Vector3.new(x, y, 0) end}
NumberSequence = {new = function(...) return {...} end}
NumberSequenceKeypoint = {new = function(t, v) return {Time = t, Value = v} end}
ColorSequence = {new = function(a, b)
	if type(a) == "table" and a[1] and a[1].Time then return {Keypoints = a} end
	return {Keypoints = {{Time = 0, Value = a}, {Time = 1, Value = b or a}}}
end}
local _inew = Instance.new
Instance.new = function(c, p)
	local o = _inew(c, p)
	if c == "UIGradient" then o.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)) end
	return o
end
local udmt = {__add = function(a, b) return a or b end}
local _new, _off = UDim2.new, UDim2.fromOffset
UDim2.new = function(...) return setmetatable(_new(...), udmt) end
UDim2.fromOffset = function(...) return setmetatable(_off(...), udmt) end
local UIS = M.getService(nil, "UserInputService")
UIS.InputBegan = M.signal(); UIS.InputChanged = M.signal(); UIS.InputEnded = M.signal()
local pl = M.newInst("Player"); pl.Character = M.newInst("Model"); pl.PlayerGui = M.newInst("Folder")
M.getService(nil, "Players").LocalPlayer = pl

-- fake JSON: tables are kept in a registry and referenced by a short id
local reg = {}
local Http = M.getService(nil, "HttpService")
Http.JSONEncode = function(_, t) reg[#reg + 1] = t; return "J" .. #reg end
Http.JSONDecode = function(_, s)
	local id = tonumber(tostring(s):match("^J(%d+)$"))
	if id and reg[id] then return reg[id] end
	error("bad json")
end

local files, clip = {}, nil
isfile = function(p) return files[p] ~= nil end
readfile = function(p) return files[p] end
writefile = function(p, c) files[p] = c end
setclipboard = function(s) clip = s end

local function advance(sec) for _ = 1, math.ceil(sec / 0.05) do M.step(0.05) end end
local function find(root, pred) for _, d in ipairs(root:GetDescendants()) do if pred(d) then return d end end end
local function hasText(root, s) return find(root, function(d) return d.ClassName == "TextLabel" and d.Text == s end) ~= nil end

local lib = loadLib()
check("lib loaded", type(lib) == "table" and type(lib.CreateWindow) == "function")

local win = lib:CreateWindow({Name = "Sources Hub", DefaultTab = "Farm"})
local farm = win:GetDefaultTab()
local combat = win:CreateTab({Name = "Combat"})
local sec = farm:CreateSection({Name = "Auto Farming"})
local seen
local tg = sec:CreateToggle({Name = "Auto Steal", Default = false, Note = "demo", Callback = function(v) seen = v end})
sec:CreateToggle({Name = "Sub", Default = true, SubOf = tg})
local clicks = 0
local btn = sec:CreateButton({Name = "Run it", ButtonText = "Go", ConfirmText = "Done", Callback = function() clicks += 1 end})
local sl = sec:CreateSlider({Name = "Speed", Min = 0, Max = 100, Default = 20, Callback = function() end})
local dd = sec:CreateDropdown({Name = "Mode", Options = {"A", "B", "C"}, Default = "A"})
sec:CreateMultiDropdown({Name = "Rarities", Options = {"Common", "Rare"}, Default = {}})
sec:CreateText({Name = "Info", Text = "hello"})
local csec = combat:CreateSection({Name = "Hits"})
csec:CreateToggle({Name = "Hit Aura", Default = true})
-- a section that belongs to the Event tab
local evSec = farm:CreateSection({Name = "Dr Scramble Lab & Mech"})
evSec:CreateToggle({Name = "Auto Lab", Default = false})

-- the steal panel is built by the logic through NewToolWindow: it must become a tab, not a window
local steal = lib.NewToolWindow({name = "steal", tabName = "StealPanel", tabTitle = "Steal", title = "Steal Panel", w = 262, h = 410})
local marker = Instance.new("Frame"); marker.Name = "Hero"; marker.Parent = steal.content
lib:Finalize({MainTab = farm})
advance(0.5)

local gui = lib.Gui
local main = gui:FindFirstChild("Main")
check("main window exists", main ~= nil)
check("main window widened", main.Size.X.Offset >= 400)
check("no separate steal window", gui:FindFirstChild("SourcesHubSteal") == nil)
check("no separate events window", gui:FindFirstChild("SourcesHubEvents") == nil)
check("side tabs exist", find(main, function(d) return d.Name == "SideTabs" end) ~= nil)
check("bg moon image present", find(main, function(d) return d.ClassName == "ImageLabel" and d.Name == "Bg" and d.Image == "rbxassetid://111331179075915" end) ~= nil)
check("header moon icon", find(main, function(d) return d.ClassName == "ImageLabel" and d.Image == "rbxassetid://111331179075915" and d.Name ~= "Bg" end) ~= nil)

-- subtitle is the discord link, click copies it
check("subtitle is the discord link", hasText(main, "discord.gg/sourceshubs"))
check("old subtitle gone", not hasText(main, "Steal An Egg"))
local sub = find(main, function(d) return d.ClassName == "TextLabel" and d.Text == "discord.gg/sourceshubs" end)
local sb = find(sub, function(d) return d.ClassName == "TextButton" end)
sb.MouseButton1Click:Fire(); advance(0.2)
check("discord link copied on click", clip == "discord.gg/sourceshubs")

-- sidebar: Steal, Event and Config tabs with drawn icons, in a sensible order
local side = find(main, function(d) return d.Name == "SideTabs" end)
local function tabBtn(label)
	return find(side, function(d)
		return d.ClassName == "TextButton" and find(d, function(x) return x.ClassName == "TextLabel" and x.Text == label end) ~= nil
	end)
end
local bFarm, bSteal, bEvent, bConfig = tabBtn("Farm"), tabBtn("Steal"), tabBtn("Event"), tabBtn("Config")
check("tabs Farm/Steal/Event/Config present", bFarm and bSteal and bEvent and bConfig)
check("raw names are not shown", not hasText(side, "StealPanel") and not hasText(side, "Events"))
check("order Farm < Steal < Event < Config", bFarm.LayoutOrder < bSteal.LayoutOrder and bSteal.LayoutOrder < bEvent.LayoutOrder and bEvent.LayoutOrder < bConfig.LayoutOrder)
check("steal/event/config buttons have an icon", bSteal:FindFirstChild("Icon") and bEvent:FindFirstChild("Icon") and bConfig:FindFirstChild("Icon"))

-- steal tab content only shows while the tab is selected
check("steal content hidden on Farm", steal.content.Visible == false)
lib.mainWindow.Select("StealPanel"); advance(0.4)
check("steal content shown on Steal tab", steal.content.Visible == true and steal.tab.page.Visible == true)
lib.mainWindow.Select("Farm"); advance(0.4)
check("steal content hidden again", steal.content.Visible == false)
-- the logic can rebuild the panel: no duplicate tab, old holder removed
local steal2 = lib.NewToolWindow({name = "steal", tabName = "StealPanel", tabTitle = "Steal", title = "Steal Panel"})
local n = 0
for _, d in ipairs(side:GetDescendants()) do if d.ClassName == "TextLabel" and d.Text == "Steal" then n += 1 end end
check("rebuild keeps one Steal tab", n == 1)
check("old holder destroyed", steal.content.Parent == nil and steal2.content.Parent ~= nil)
check("steal window api", type(steal2.SetOpen) == "function" and steal2.frame == steal2.content and steal2.OnClose ~= nil)
local opened
steal2.OnClose.Connect(function(on) opened = on end)
steal2.SetOpen(true); advance(0.1)
check("SetOpen fires OnClose", opened == true)

-- event sections land in the Event tab
local evTab = lib.mainWindow.tabs.Events
check("event section placed in Events tab", evSec.body.Parent == evTab.page)

-- toggle: click the check box
local function toggleBtn(h) return find(h.Instance, function(d) return d.ClassName == "TextButton" and d.Text == "" and d.Parent and d.Parent.ClassName == "Frame" and d.Parent.Size and d.Parent.Size.X.Offset == 26 end) end
local tb = toggleBtn(tg)
check("toggle check box found", tb ~= nil)
tb.MouseButton1Click:Fire(); advance(0.4)
check("toggle on + callback", tg.Get() == true and seen == true)
tb.MouseButton1Click:Fire(); advance(0.4)
check("toggle off", tg.Get() == false and seen == false)

local bb = find(btn.Instance, function(d) return d.ClassName == "TextButton" end)
bb.MouseButton1Click:Fire(); advance(0.5)
check("button callback", clicks == 1)

sl:Set(55, true); check("slider value", sl.Get() == 55)
dd:Set("B", true); check("dropdown value", dd.Get() == "B")
local ddBox = find(dd.Instance, function(d) return d.ClassName == "TextButton" end)
ddBox.MouseButton1Click:Fire(); advance(0.2)
local ov = find(main, function(d) return d.ClassName == "Frame" and d.ZIndex == 300 end)
check("picker overlay opens", ov ~= nil and ov.Visible == true)
local cards = 0
for _, d in ipairs(ov:GetDescendants()) do if d.ClassName == "Frame" and d.Size and d.Size.Y.Offset == 30 then cards += 1 end end
check("picker shows 3 flat cards, no tree", cards == 3 and find(ov, function(d) return d.ClassName == "Frame" and d.Size and d.Size.X.Offset == 1 end) == nil)

lib.mainWindow.Select("Combat"); advance(0.4)
check("tab switched", lib.mainWindow.current == "Combat")
lib.mainWindow.Select("Farm"); advance(0.4)

-- config sharing: copy, then import into a "friend's" session
lib.mainWindow.Select("Config"); advance(0.3)
local cfgPage = lib.mainWindow.tabs.Config.page
local function pageButton(text)
	return find(cfgPage, function(d) return d.ClassName == "TextButton" and find(d, function(x) return x.ClassName == "TextLabel" and x.Text == text end) ~= nil end)
end
local copyB, importB = pageButton("Copy"), pageButton("Import")
check("config buttons present", copyB ~= nil and importB ~= nil)
clip = nil
copyB.MouseButton1Click:Fire(); advance(0.3)
check("config copied with SHCFG1 prefix", type(clip) == "string" and clip:sub(1, 7) == "SHCFG1:")
check("copy status shown", find(cfgPage, function(d) return d.ClassName == "TextLabel" and d.Text:find("Copied", 1, true) ~= nil end) ~= nil)

local box = find(cfgPage, function(d) return d.Name == "ConfigBox" end)
reg[#reg + 1] = {["Farm>Auto Farming>Speed"] = 77, ["Farm>Auto Farming>Auto Steal"] = true, ["Some>Other>Key"] = "x"}
box.Text = "SHCFG1:J" .. #reg
importB.MouseButton1Click:Fire(); advance(0.3)
check("import applies the slider live", sl.Get() == 77)
check("import applies the toggle live", tg.Get() == true and seen == true)
check("import reports 3 settings", hasText(cfgPage, "Imported 3 settings"))
check("import box cleared", box.Text == "")
box.Text = "garbage"
importB.MouseButton1Click:Fire(); advance(0.3)
check("invalid import is refused", hasText(cfgPage, "That is not a valid config"))
lib.mainWindow.Select("Farm"); advance(0.3)

-- themes
for _, name in ipairs(lib.ThemeNames) do lib.SetTheme(name); advance(0.2) end
lib.SetTheme("Gold")
check("original theme names kept", #lib.ThemeNames == 4 and lib.ThemeNames[1] == "Gold" and lib.ThemeName == "Gold")

-- main minimise / restore
lib.mainWindow.SetMinimized(true); advance(0.4)
lib.mainWindow.SetMinimized(false); advance(0.4)
check("main restored", main.Visible == true)

lib.Notify("t", "text", 1); lib.Banner("banner", 1); lib.RiskBadge("risk", "txt", 1)
lib.Splash({{Text = "ok", Ok = true}, {Text = "bad", Ok = false}})
advance(1.2)

check("no runtime warnings", #M.warnings == 0)
for _, wmsg in ipairs(M.warnings) do print(wmsg) end
print(string.format("UI: %d ok, %d fail", passes, failures))
if failures > 0 then error("UI tests failed") end
