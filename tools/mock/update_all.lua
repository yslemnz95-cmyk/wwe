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
Color3 = {fromRGB = function(r,g,b) return {R=r/255,G=g/255,B=b/255} end, new = function(r,g,b) return {R=r,G=g,B=b} end}
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
	o.ChildAdded = signal(); o.FocusLost = signal(); o.Focused = signal(); o.MouseEnter = signal()
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

local loadUpdate = function()
-- yslem Game Update v2 : TOUT EN UN FICHIER (analyse + comparaison + fenetre yslemStyle).
-- Execute-le dans le jeu : il scanne, compare avec la reference de ce jeu (sauvegardee dans le dossier de l'executeur),
-- montre tout ce qui a change (+ ajoute, - supprime, > deplace, ~ modifie) et copie le rapport pour qu'on l'adapte.
-- Il ne MODIFIE rien dans le jeu : il lit des noms et ecrit seulement 3 petits fichiers texte. Aucun acces reseau.
--   Scan     : relance l'analyse (se lance deja a l'ouverture)
--   Copy     : copie le rapport + l'inventaire complet (a coller dans le chat)
--   Baseline : remplace la reference par le dernier inventaire (a faire quand tout est adapte)

local VERSION = 2

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local lp = Players.LocalPlayer

local genv = typeof(getgenv) == "function" and getgenv() or _G
if type(genv.YslemGameUpdateStop) == "function" then pcall(genv.YslemGameUpdateStop) end

-------------------------------------------------------------------------------------------------- inventaire
local MAX_YIELD = 1500

local function walk(root, fn)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		fn(d)
		n += 1
		if n % MAX_YIELD == 0 then task.wait() end
	end
end

-- noms stables : identifiants et nombres remplaces, separateurs retires
local function norm(name)
	name = tostring(name)
	name = name:gsub("[|\r\n]", " ")
	name = name:gsub("%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x", "<guid>")
	name = name:gsub("%d%d+", "#")
	return name
end

local function rel(inst, root, label)
	local parts = {}
	local p = inst
	while p and p ~= root and p ~= game do
		table.insert(parts, 1, norm(p.Name))
		p = p.Parent
	end
	return label .. "/" .. table.concat(parts, "/")
end

local function snapshot()
	local counts, order = {}, {}
	local function add(kind, class, p, extra)
		local key = kind .. "|" .. class .. "|" .. p .. "|" .. (extra or "")
		if counts[key] then counts[key] += 1 else counts[key] = 1; table.insert(order, key) end
	end
	local gname = "?"
	pcall(function() gname = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name end)
	local pgui = lp:FindFirstChild("PlayerGui")
	local pscripts = lp:FindFirstChild("PlayerScripts")

	for _, pair in ipairs({{ReplicatedStorage, "RS"}, {game:GetService("ReplicatedFirst"), "RF"}}) do
		walk(pair[1], function(d)
			if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") or d:IsA("BindableEvent") or d:IsA("BindableFunction") then
				add("REMOTE", d.ClassName, rel(d, pair[1], pair[2]))
			elseif d:IsA("ModuleScript") or d:IsA("LocalScript") then
				add("SCRIPT", d.ClassName, rel(d, pair[1], pair[2]))
			end
		end)
	end
	if pscripts then
		walk(pscripts, function(d)
			if d:IsA("ModuleScript") or d:IsA("LocalScript") then add("SCRIPT", d.ClassName, rel(d, pscripts, "PS")) end
		end)
	end
	if pgui then
		for _, sg in ipairs(pgui:GetChildren()) do
			if sg.Name ~= "YslemGameUpdate" then add("SCREEN", sg.ClassName, "GUI/" .. norm(sg.Name)) end
		end
		walk(pgui, function(d)
			if d:IsA("TextButton") or d:IsA("ImageButton") then
				local sg = d:FindFirstAncestorOfClass("ScreenGui")
				if sg and sg.Name == "YslemGameUpdate" then return end
				add("BUTTON", d.ClassName, rel(d, pgui, "GUI"), d:IsA("TextButton") and norm(d.Text) or "")
			end
		end)
	end
	local function skip(inst)
		return inst:IsA("Model") and Players:GetPlayerFromCharacter(inst) ~= nil
	end
	local function level(parent, depth)
		for _, c in ipairs(parent:GetChildren()) do
			if not skip(c) then
				add("WORLD", c.ClassName, rel(c, Workspace, "WS"))
				if depth < 3 then level(c, depth + 1) end
			end
		end
	end
	pcall(level, Workspace, 1)
	walk(Workspace, function(d)
		if d:IsA("ProximityPrompt") then
			add("PROMPT", "ProximityPrompt", rel(d, Workspace, "WS"), norm(d.ActionText) .. " / " .. norm(d.ObjectText) .. " / hold=" .. tostring(d.HoldDuration))
		elseif d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
			add("REMOTE", d.ClassName, rel(d, Workspace, "WS"))
		end
	end)
	local ls = lp:FindFirstChild("leaderstats")
	if ls then
		for _, v in ipairs(ls:GetChildren()) do add("STAT", v.ClassName, "leaderstats/" .. norm(v.Name)) end
	end
	for k in pairs(lp:GetAttributes()) do add("ATTR", "Player", "player/" .. norm(k)) end
	if lp.Character then
		for k in pairs(lp.Character:GetAttributes()) do add("ATTR", "Character", "character/" .. norm(k)) end
	end

	table.sort(order)
	local out = {
		"#SNAPSHOT v1",
		"#GAME " .. tostring(gname) .. " PlaceId=" .. tostring(game.PlaceId) .. " GameId=" .. tostring(game.GameId),
		"#DATE " .. os.date("%Y-%m-%d %H:%M:%S"),
	}
	for _, key in ipairs(order) do table.insert(out, key .. "|" .. counts[key]) end
	return table.concat(out, "\n"), #order
end

-------------------------------------------------------------------------------------------------- comparaison
local function parse(text)
	local meta, rows = {}, {}
	for line in tostring(text):gmatch("[^\r\n]+") do
		if line:sub(1, 1) == "#" then
			local k, v = line:match("^#(%S+)%s*(.*)$")
			if k then meta[k] = v end
		else
			local parts = {}
			for piece in (line .. "|"):gmatch("(.-)|") do parts[#parts + 1] = piece end
			if #parts >= 5 then
				local n = tonumber(parts[#parts]) or 1
				local extra = table.concat(parts, "|", 4, #parts - 1)
				rows[parts[1] .. "|" .. parts[3]] = {kind = parts[1], class = parts[2], path = parts[3], extra = extra, n = n}
			end
		end
	end
	return meta, rows
end

local function leaf(p) return p:match("([^/]*)$") or p end

local function diff(oldRows, newRows)
	local added, removed, changed, moved = {}, {}, {}, {}
	for k, v in pairs(newRows) do
		local o = oldRows[k]
		if not o then
			table.insert(added, v)
		elseif o.class ~= v.class or o.extra ~= v.extra or o.n ~= v.n then
			local bits = {}
			if o.class ~= v.class then bits[#bits + 1] = "class " .. o.class .. " -> " .. v.class end
			if o.extra ~= v.extra then bits[#bits + 1] = "'" .. o.extra .. "' -> '" .. v.extra .. "'" end
			if o.n ~= v.n then bits[#bits + 1] = "x" .. o.n .. " -> x" .. v.n end
			table.insert(changed, {row = v, text = table.concat(bits, "; ")})
		end
	end
	for k, v in pairs(oldRows) do
		if not newRows[k] then table.insert(removed, v) end
	end
	local function byPath(a, b) return a.path < b.path end
	table.sort(added, byPath); table.sort(removed, byPath)
	table.sort(changed, function(a, b) return a.row.path < b.row.path end)
	-- deplaces : meme type + meme nom de feuille (sans nombres), dossier different
	local remBy = {}
	for i, v in ipairs(removed) do
		local key = v.kind .. "|" .. leaf(v.path)
		if not leaf(v.path):find("#", 1, true) then remBy[key] = remBy[key] or {}; table.insert(remBy[key], i) end
	end
	local dropAdded, dropRemoved = {}, {}
	for i, v in ipairs(added) do
		local list = remBy[v.kind .. "|" .. leaf(v.path)]
		if list and #list > 0 and not leaf(v.path):find("#", 1, true) then
			local ri = table.remove(list, 1)
			table.insert(moved, {from = removed[ri], to = v})
			dropAdded[i] = true; dropRemoved[ri] = true
		end
	end
	local a2, r2 = {}, {}
	for i, v in ipairs(added) do if not dropAdded[i] then a2[#a2 + 1] = v end end
	for i, v in ipairs(removed) do if not dropRemoved[i] then r2[#r2 + 1] = v end end
	return {added = a2, removed = r2, moved = moved, changed = changed}
end

local function describe(v)
	return "[" .. v.kind .. "] " .. v.path .. (v.extra ~= "" and (" (" .. v.extra .. ")") or "")
end

-- lignes du rapport : {texte, couleur}
local COLORS = {
	add = Color3.fromRGB(90, 220, 140), del = Color3.fromRGB(255, 90, 90),
	mov = Color3.fromRGB(255, 200, 90), chg = Color3.fromRGB(255, 200, 90), info = Color3.fromRGB(255, 176, 176),
}

local function reportLines(d)
	local out = {}
	local function add(color, text) out[#out + 1] = {text = text, color = color} end
	for _, v in ipairs(d.removed) do add("del", "- " .. describe(v)) end
	for _, m in ipairs(d.moved) do add("mov", "> [" .. m.from.kind .. "] " .. m.from.path .. "  ->  " .. m.to.path) end
	for _, v in ipairs(d.added) do add("add", "+ " .. describe(v)) end
	for _, c in ipairs(d.changed) do add("chg", "~ [" .. c.row.kind .. "] " .. c.row.path .. " : " .. c.text) end
	return out
end

local function reportText(meta1, meta2, d, lines)
	local out = {
		"##### yslem Game Update v" .. VERSION .. " #####",
		"ancien : " .. tostring(meta1.GAME or "?") .. " (" .. tostring(meta1.DATE or "?") .. ")",
		"nouveau : " .. tostring(meta2.GAME or "?") .. " (" .. tostring(meta2.DATE or "?") .. ")",
		string.format("ajoutes %d  supprimes %d  deplaces %d  modifies %d", #d.added, #d.removed, #d.moved, #d.changed),
	}
	for _, l in ipairs(lines) do out[#out + 1] = l.text end
	return table.concat(out, "\n")
end

-------------------------------------------------------------------------------------------------- fichiers
local DIR = "yslem_gameupdate"
local haveFiles = typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"

local function path(name)
	if typeof(makefolder) == "function" and typeof(isfolder) == "function" then
		pcall(function() if not isfolder(DIR) then makefolder(DIR) end end)
		return DIR .. "/" .. name
	end
	return DIR .. "_" .. name
end

local function save(name, text)
	if not haveFiles then return false end
	return pcall(writefile, path(name), text)
end

local function loadFile(name)
	if not haveFiles then return nil end
	local ok, exists = pcall(isfile, path(name))
	if not ok or not exists then return nil end
	local ok2, text = pcall(readfile, path(name))
	return ok2 and text or nil
end

-------------------------------------------------------------------------------------------------- etat
local state = {snap = nil, report = nil, busy = false}
local GameUpdate = {Version = VERSION, snapshot = snapshot, parse = parse, diff = diff}

local ui = {}

local function setStatus(text, color)
	if ui.status then
		ui.status.Text = text
		ui.status.TextColor3 = color or COLORS.info
	end
end

local function showLines(lines)
	if not ui.list then return end
	for _, c in ipairs(ui.list:GetChildren()) do
		if c:IsA("TextLabel") then c:Destroy() end
	end
	if #lines == 0 then lines = {{text = "Rien n'a change depuis la reference.", color = "info"}} end
	for i, l in ipairs(lines) do
		if i > 400 then
			local more = Instance.new("TextLabel")
			more.BackgroundTransparency = 1; more.Size = UDim2.new(1, -8, 0, 16); more.LayoutOrder = i
			more.Font = Enum.Font.GothamMedium; more.TextSize = 11; more.TextXAlignment = Enum.TextXAlignment.Left
			more.TextColor3 = COLORS.info; more.Text = "... +" .. (#lines - 400) .. " autres (voir Copy)"
			more.Parent = ui.list
			break
		end
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1; t.Size = UDim2.new(1, -8, 0, 0); t.AutomaticSize = Enum.AutomaticSize.Y
		t.LayoutOrder = i; t.Font = Enum.Font.GothamMedium; t.TextSize = 11; t.TextWrapped = true
		t.TextXAlignment = Enum.TextXAlignment.Left; t.TextYAlignment = Enum.TextYAlignment.Top
		t.TextColor3 = COLORS[l.color] or COLORS.info; t.Text = l.text
		t.Parent = ui.list
	end
end

local function scan()
	if state.busy then return end
	state.busy = true
	setStatus("Analyse en cours...")
	local ok, err = pcall(function()
		local text, count = snapshot()
		local meta2, rows2 = parse(text)
		local pid = tostring(game.PlaceId)
		local baseText = loadFile(pid .. "_baseline.txt")
		state.snap = text
		save(pid .. "_latest.txt", text)
		save(pid .. "_" .. os.date("%Y-%m-%d_%H%M%S") .. ".txt", text)
		if not baseText then
			save(pid .. "_baseline.txt", text)
			state.report = "##### yslem Game Update v" .. VERSION .. " #####\nPremiere analyse : reference enregistree (" .. count .. " entrees)."
			showLines({{text = "Premiere analyse : reference enregistree (" .. count .. " entrees).", color = "add"}})
			setStatus("Reference creee. Relance Scan apres la prochaine mise a jour.", COLORS.add)
		else
			local meta1, rows1 = parse(baseText)
			local d = diff(rows1, rows2)
			local lines = reportLines(d)
			state.report = reportText(meta1, meta2, d, lines)
			showLines(lines)
			local total = #d.added + #d.removed + #d.moved + #d.changed
			setStatus(total == 0 and "Aucun changement." or string.format("+%d  -%d  >%d  ~%d", #d.added, #d.removed, #d.moved, #d.changed),
				total == 0 and COLORS.add or COLORS.mov)
		end
		GameUpdate.lastReport = state.report
		GameUpdate.lastSnapshot = state.snap
	end)
	if not ok then setStatus("Erreur : " .. tostring(err), COLORS.del) end
	state.busy = false
end

local function copyAll()
	if not state.snap then return end
	local text = (state.report or "") .. "\n\n===== INVENTAIRE COMPLET =====\n" .. state.snap
	local ok = typeof(setclipboard) == "function" and pcall(setclipboard, text)
	setStatus(ok and "Rapport + inventaire copies." or "Presse-papiers indisponible (fichiers dans " .. DIR .. ").", ok and COLORS.add or COLORS.mov)
end

local function setBaseline()
	if not state.snap then return end
	local ok = save(tostring(game.PlaceId) .. "_baseline.txt", state.snap)
	setStatus(ok and "Nouvelle reference enregistree." or "Impossible d'ecrire le fichier.", ok and COLORS.add or COLORS.del)
end

-------------------------------------------------------------------------------------------------- fenetre yslemStyle
local connections = {}

local function buildUI()
	local parent
	pcall(function() parent = typeof(gethui) == "function" and gethui() or nil end)
	if not parent then
		local ok = pcall(function() parent = game:GetService("CoreGui") end)
		if not ok or not parent then parent = lp:WaitForChild("PlayerGui") end
	end
	for _, c in ipairs(parent:GetChildren()) do
		if c.Name == "YslemGameUpdate" then c:Destroy() end
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "YslemGameUpdate"; gui.ResetOnSpawn = false; gui.DisplayOrder = 50
	gui.Parent = parent
	ui.gui = gui

	local grads = {}
	local function gradient(inst, a, b)
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(0.5, b), ColorSequenceKeypoint.new(1, a)})
		g.Parent = inst
		grads[#grads + 1] = g
		return g
	end
	local function corner(inst, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = inst end
	local function stroke(inst, th)
		local s = Instance.new("UIStroke"); s.Thickness = th; s.Color = Color3.fromRGB(255, 255, 255)
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = inst
		gradient(s, Color3.fromRGB(70, 10, 10), Color3.fromRGB(255, 90, 90))
		return s
	end

	local frame = Instance.new("Frame")
	frame.Name = "Window"; frame.Size = UDim2.fromOffset(340, 400)
	frame.Position = UDim2.new(0.5, -170, 0.5, -200)
	frame.BackgroundColor3 = Color3.fromRGB(5, 0, 0); frame.BorderSizePixel = 0; frame.Active = true
	frame.Parent = gui
	corner(frame, 14); stroke(frame, 1.6)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1; title.Position = UDim2.new(0, 14, 0, 8); title.Size = UDim2.new(1, -60, 0, 20)
	title.Font = Enum.Font.GothamBold; title.TextSize = 16; title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 255, 255); title.Text = "Game Update v" .. VERSION
	title.Parent = frame
	gradient(title, Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 200, 200))

	local gname = "?"
	pcall(function() gname = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name end)
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1; sub.Position = UDim2.new(0, 14, 0, 28); sub.Size = UDim2.new(1, -60, 0, 14)
	sub.Font = Enum.Font.GothamMedium; sub.TextSize = 10; sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextColor3 = Color3.fromRGB(150, 110, 110); sub.Text = tostring(gname) .. "  -  " .. tostring(game.PlaceId)
	sub.Parent = frame

	local close = Instance.new("TextButton")
	close.Size = UDim2.fromOffset(24, 24); close.Position = UDim2.new(1, -34, 0, 10)
	close.BackgroundColor3 = Color3.fromRGB(58, 20, 20); close.BorderSizePixel = 0; close.AutoButtonColor = false
	close.Font = Enum.Font.GothamBold; close.TextSize = 12; close.TextColor3 = Color3.fromRGB(255, 90, 90); close.Text = "X"
	close.Parent = frame
	corner(close, 8); stroke(close, 1)
	close.MouseButton1Click:Connect(function() if genv.YslemGameUpdateStop then genv.YslemGameUpdateStop() end end)
	ui.close = close

	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1; status.Position = UDim2.new(0, 14, 0, 48); status.Size = UDim2.new(1, -28, 0, 16)
	status.Font = Enum.Font.GothamBold; status.TextSize = 12; status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextColor3 = COLORS.info; status.Text = ""
	status.Parent = frame
	ui.status = status

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"; list.Position = UDim2.new(0, 10, 0, 70); list.Size = UDim2.new(1, -20, 1, -128)
	list.BackgroundColor3 = Color3.fromRGB(12, 2, 2); list.BorderSizePixel = 0; list.ScrollBarThickness = 3
	list.CanvasSize = UDim2.new(0, 0, 0, 0); list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = frame
	corner(list, 10)
	local layout = Instance.new("UIListLayout"); layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.Padding = UDim.new(0, 3); layout.Parent = list
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 8); pad.PaddingTop = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 4); pad.Parent = list
	ui.list = list

	local function button(text, x, w, fn)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, w, 0, 30); b.Position = UDim2.new(0, x, 1, -40)
		b.BackgroundColor3 = Color3.fromRGB(20, 4, 4); b.BorderSizePixel = 0; b.AutoButtonColor = false
		b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.TextColor3 = Color3.fromRGB(255, 255, 255); b.Text = text
		b.Parent = frame
		corner(b, 10); stroke(b, 1.2); gradient(b, Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 190, 190))
		b.MouseButton1Click:Connect(fn)
		return b
	end
	ui.scan = button("Scan", 10, 96, function() task.spawn(scan) end)
	ui.copy = button("Copy", 122, 96, copyAll)
	ui.baseline = button("Baseline", 234, 96, setBaseline)

	-- deplacement par l'en-tete
	local dragging, startPos, startInput
	table.insert(connections, frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if input.Position.Y - frame.AbsolutePosition.Y < 44 then
				dragging, startPos, startInput = true, frame.Position, input.Position
			end
		end
	end))
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - startInput
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end))

	-- degrade anime
	local t0 = os.clock()
	table.insert(connections, RunService.RenderStepped:Connect(function()
		local rot = ((os.clock() - t0) * 60) % 360
		for _, g in ipairs(grads) do
			if g.Parent then g.Rotation = rot end
		end
	end))
end

genv.YslemGameUpdateStop = function()
	for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
	table.clear(connections)
	if ui.gui then pcall(function() ui.gui:Destroy() end) end
	genv.YslemGameUpdateStop = nil
end
genv.YslemGameUpdate = GameUpdate

buildUI()
task.spawn(scan)

return GameUpdate

end
local passes, failures = 0, 0
local function check(name, cond) if cond then passes += 1 else failures += 1; print("FAIL: " .. name) end end
tick = tick or os.clock
Vector2 = {new = function(x, y) return Vector3.new(x, y, 0) end}
ColorSequence = {new = function(a, b)
	if type(a) == "table" and a[1] and a[1].Time then return {Keypoints = a} end
	return {Keypoints = {{Time = 0, Value = a}, {Time = 1, Value = b or a}}}
end}
ColorSequenceKeypoint = ColorSequenceKeypoint or {new = function(t, v) return {Time = t, Value = v} end}
local udmt = {__add = function(a, b) return a or b end}
local _new, _off = UDim2.new, UDim2.fromOffset
UDim2.new = function(...) return setmetatable(_new(...), udmt) end
UDim2.fromOffset = function(...) return setmetatable(_off(...), udmt) end
UDim = UDim or {new = function(s, o) return {Scale = s, Offset = o} end}
local UIS = M.getService(nil, "UserInputService")
UIS.InputBegan = M.signal(); UIS.InputChanged = M.signal(); UIS.InputEnded = M.signal()
M.getService(nil, "ReplicatedFirst")
M.getService(nil, "MarketplaceService").GetProductInfo = function() return {Name = "Mock Game"} end
local function advance(sec) for _ = 1, math.ceil(sec / 0.05) do M.step(0.05) end end
local function find(root, pred) for _, d in ipairs(root:GetDescendants()) do if pred(d) then return d end end end

-- fichiers et presse-papiers
local files, clip = {}, nil
isfile = function(p) return files[p] ~= nil end
readfile = function(p) return files[p] end
writefile = function(p, c) files[p] = c end
setclipboard = function(s) clip = s end
local genvT = {}; getgenv = function() return genvT end

-- monde
local Players = M.getService(nil, "Players")
local pl = M.newInst("Player"); pl.Name = "Tester"; pl.UserId = 1
pl.PlayerGui = M.newInst("Folder"); pl.PlayerGui.Name = "PlayerGui"; pl.PlayerGui.Parent = pl
pl.Parent = Players; Players.LocalPlayer = pl; Players.GetPlayers = function() return {pl} end
local RS = M.getService(nil, "ReplicatedStorage")
local function mk(class, name, parent) local o = M.newInst(class); o.Name = name; o.Parent = parent; return o end
local remotes = mk("Folder", "Remotes", RS)
local gameF = mk("Folder", "Game", remotes)
mk("RemoteEvent", "BasketDrop", gameF); mk("RemoteEvent", "Teleporting", gameF)
local sg = mk("ScreenGui", "Main", pl.PlayerGui)
local drop = mk("TextButton", "Drop", sg); drop.Text = "DROP"
local WS = M.getService(nil, "Workspace")
local egg = mk("Part", "Egg", WS)
local pr = mk("ProximityPrompt", "Prompt", egg); pr.ActionText = "Pick Up"; pr.ObjectText = "Dino"; pr.HoldDuration = 0.2

local U = loadUpdate()
advance(0.5)
local pid = tostring(game.PlaceId)
check("module returns version 2", U.Version == 2)
check("first run saves the baseline, latest and a dated copy", files["yslem_gameupdate_" .. pid .. "_baseline.txt"] ~= nil and files["yslem_gameupdate_" .. pid .. "_latest.txt"] ~= nil)
local dated = 0 for k in pairs(files) do if k:find("%d%d%d%d%-%d%d%-%d%d_%d+%.txt$") then dated += 1 end end
check("dated copy written", dated >= 1)
local gui = find(pl.PlayerGui, function(d) return d.Name == "YslemGameUpdate" end) or find(M.getService(nil, "CoreGui"), function(d) return d.Name == "YslemGameUpdate" end)
check("window built", gui ~= nil)
local function labels(root) local t = {} for _, d in ipairs(root:GetDescendants()) do if d.ClassName == "TextLabel" then t[#t + 1] = d.Text end end return t end
local function anyText(root, s) for _, t in ipairs(labels(root)) do if t:find(s, 1, true) then return true end end return false end
check("status: reference created", gui and anyText(gui, "Reference creee"))

-- le jeu change : drop deplace, Teleporting supprime, nouveau remote, bouton renomme, prompt plus long
local basket = find(RS, function(d) return d.Name == "BasketDrop" end); basket.Parent = mk("Folder", "Basket", remotes)
find(RS, function(d) return d.Name == "Teleporting" end):Destroy()
mk("RemoteEvent", "NewThing", gameF)
drop.Text = "DROP EGG"; pr.HoldDuration = 0.5
local scanBtn = find(gui, function(d) return d.ClassName == "TextButton" and d.Text == "Scan" end)
scanBtn.MouseButton1Click:Fire(); advance(0.5)
local texts = labels(gui)
local function has(prefix) for _, t in ipairs(texts) do if t:sub(1, #prefix) == prefix then return t end end end
check("removed remote listed (-)", has("- [REMOTE] RS/Remotes/Game/Teleporting") ~= nil)
check("moved remote listed (>)", (has("> [REMOTE] RS/Remotes/Game/BasketDrop") or ""):find("RS/Remotes/Basket/BasketDrop", 1, true) ~= nil)
check("added remote listed (+)", has("+ [REMOTE] RS/Remotes/Game/NewThing") ~= nil)
check("button text change (~)", (has("~ [BUTTON]") or ""):find("'DROP' -> 'DROP EGG'", 1, true) ~= nil)
check("prompt hold change (~)", (has("~ [PROMPT]") or ""):find("hold=0.5", 1, true) ~= nil)
check("status shows the counters", anyText(gui, "+1  -1  >1  ~2"))

-- copie
find(gui, function(d) return d.ClassName == "TextButton" and d.Text == "Copy" end).MouseButton1Click:Fire()
check("copy: report + full inventory", clip ~= nil and clip:find("Game Update v2", 1, true) ~= nil and clip:find("INVENTAIRE COMPLET", 1, true) ~= nil and clip:find("#SNAPSHOT v1", 1, true) ~= nil)

-- nouvelle reference puis plus de changement
find(gui, function(d) return d.ClassName == "TextButton" and d.Text == "Baseline" end).MouseButton1Click:Fire()
check("baseline replaced by the latest scan", files["yslem_gameupdate_" .. pid .. "_baseline.txt"] == files["yslem_gameupdate_" .. pid .. "_latest.txt"])
scanBtn.MouseButton1Click:Fire(); advance(0.5)
check("after baseline: no change", anyText(gui, "Aucun changement"))

-- logique pure
local m1, r1 = U.parse("#GAME A\nREMOTE|RemoteEvent|RS/X/Foo||1\nBUTTON|TextButton|GUI/B|a|b|2")
check("parse keeps '|' inside the extra text", r1["BUTTON|GUI/B"] and r1["BUTTON|GUI/B"].extra == "a|b" and r1["BUTTON|GUI/B"].n == 2)
check("player name never in the inventory", not U.lastSnapshot:find("Tester", 1, true))

-- fermeture
check("stop function registered", type(genvT.YslemGameUpdateStop) == "function")
genvT.YslemGameUpdateStop()
check("window closed", gui.Parent == nil)
print(string.format("Update: %d ok, %d fail", passes, failures))
if failures > 0 then error("update tests failed") end
