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

local loadAnalyzer = function()
-- yslem Game Analyzer (UN fichier, 2 etapes). Execute-le dans le jeu :
--   Etape 1 (structure) : remotes, scripts, ecrans, boutons, prompts, monde, stats  -> copie dans le presse-papier, colle dans le chat
--   Etape 2 (contenu)   : donnees du jeu (pets, raretes, zones, events, produits...) + tous les textes -> copie, colle dans le chat
-- Un badge en bas a droite dit quand chaque etape est faite. Le texte copie commence par le message pour Claude.
-- Il lit des noms, des textes et les modules de donnees du jeu (ReplicatedStorage.Data, deja charges par le jeu). Aucun reseau.
-- Il n'ecrit que des fichiers texte dans le dossier de l'executeur (yslem_analyzer).

local VERSION = 3

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local lp = Players.LocalPlayer

local genv = typeof(getgenv) == "function" and getgenv() or _G
if type(genv.YslemAnalyzerStop) == "function" then pcall(genv.YslemAnalyzerStop) end

-------------------------------------------------------------------------------------------------- outils
local function walk(root, fn)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		fn(d)
		n += 1
		if n % 1500 == 0 then task.wait() end
	end
end

-- noms stables : identifiants et nombres remplaces, separateurs retires
local function norm(name)
	name = tostring(name)
	name = name:gsub("[|\r\n]", " ")
	name = name:gsub("%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x", "<guid>")
	name = name:gsub("%x%x%x%x%x%x%x%x+", "<id>")
	name = name:gsub("%d%d+", "#")
	return name
end

local function clean(text, max)
	text = tostring(text):gsub("[|\r\n]", " ")
	if #text > max then text = text:sub(1, max) .. "..." end
	return text
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

local function newCollector()
	local counts, order = {}, {}
	local function add(kind, class, path, extra)
		local key = kind .. "|" .. class .. "|" .. path .. "|" .. (extra or "")
		if counts[key] then counts[key] += 1 else counts[key] = 1; table.insert(order, key) end
	end
	return add, function()
		table.sort(order)
		local out = {}
		for _, key in ipairs(order) do out[#out + 1] = key .. "|" .. counts[key] end
		return out
	end
end

local function gameName()
	local name = "?"
	pcall(function() name = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name end)
	return name
end

local function header(step)
	return {
		"#SNAPSHOT v" .. VERSION,
		"#STEP " .. step .. "/2",
		"#GAME " .. gameName() .. " PlaceId=" .. tostring(game.PlaceId) .. " GameId=" .. tostring(game.GameId),
		"#DATE " .. os.date("%Y-%m-%d %H:%M:%S"),
	}
end

-- bibliotheques tierces : une seule ligne par dossier (sinon des milliers de lignes inutiles)
local function libraryRoot(path)
	for _, prefix in ipairs({"RS/Packages/_Index", "RS/UserGenerated", "RS/CmdrClient/Types", "RS/CmdrClient/Shared", "RS/CmdrClient/CmdrInterface"}) do
		if path:sub(1, #prefix) == prefix then return prefix end
	end
	return nil
end

-------------------------------------------------------------------------------------------------- etape 1 : structure
local function collectStructure()
	local add, finish = newCollector()
	local pgui = lp:FindFirstChild("PlayerGui")
	local pscripts = lp:FindFirstChild("PlayerScripts")

	for _, pair in ipairs({{ReplicatedStorage, "RS"}, {game:GetService("ReplicatedFirst"), "RF"}}) do
		walk(pair[1], function(d)
			if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") or d:IsA("BindableEvent") or d:IsA("BindableFunction") then
				add("REMOTE", d.ClassName, rel(d, pair[1], pair[2]))
			elseif d:IsA("ModuleScript") or d:IsA("LocalScript") then
				local p = rel(d, pair[1], pair[2])
				local lib = libraryRoot(p)
				if lib then add("LIBRARY", "Scripts", lib) else add("SCRIPT", d.ClassName, p) end
			elseif d:IsA("ValueBase") then
				local vp = rel(d, pair[1], pair[2])
				local noisy = nil
				for _, prefix in ipairs({"RS/CutsceneAssets", "RS/Assets", "RS/Controllers"}) do
					if vp:sub(1, #prefix) == prefix then noisy = prefix break end
				end
				if noisy then
					add("LIBRARY", "Values", noisy)
				else
					local extra = ""
					if d:IsA("StringValue") or d:IsA("BoolValue") then extra = clean(d.Value, 60) end
					add("VALUE", d.ClassName, vp, extra)
				end
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
			if sg.Name ~= "YslemAnalyzer" then add("SCREEN", sg.ClassName, "GUI/" .. norm(sg.Name)) end
		end
		walk(pgui, function(d)
			if d:IsA("TextButton") or d:IsA("ImageButton") then
				local sg = d:FindFirstAncestorOfClass("ScreenGui")
				if sg and sg.Name == "YslemAnalyzer" then return end
				add("BUTTON", d.ClassName, rel(d, pgui, "GUI"), d:IsA("TextButton") and norm(d.Text) or "")
			end
		end)
	end

	local function skip(inst)
		return inst:IsA("Model") and Players:GetPlayerFromCharacter(inst) ~= nil
	end
	local function level(parent, depth)
		local kids = parent:GetChildren()
		for _, c in ipairs(kids) do
			if not skip(c) then
				add("WORLD", c.ClassName, rel(c, Workspace, "WS"))
				if depth < 3 and #kids <= 40 and not norm(c.Name):find("<id>", 1, true) then level(c, depth + 1) end
			end
		end
	end
	pcall(level, Workspace, 1)
	walk(Workspace, function(d)
		if d:IsA("ProximityPrompt") then
			add("PROMPT", "ProximityPrompt", rel(d, Workspace, "WS"), clean(norm(d.ActionText) .. " / " .. norm(d.ObjectText) .. " / hold=" .. tostring(d.HoldDuration), 90))
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
	-- attributs des racines (drapeaux d'events, versions...) : nom + valeur simple
	for _, pair in ipairs({{Workspace, "WS"}, {ReplicatedStorage, "RS"}, {game:GetService("Lighting"), "Lighting"}}) do
		pcall(function()
			for k, v in pairs(pair[1]:GetAttributes()) do
				local t = type(v)
				add("ATTR", pair[2], pair[2] .. "/" .. norm(k), (t == "string" or t == "boolean") and clean(v, 60) or "")
			end
		end)
	end
	return finish()
end

-------------------------------------------------------------------------------------------------- etape 2 : contenu
local function ser(v, depth, seen)
	local t = typeof(v)
	if t == "string" then
		return '"' .. clean(v, 60) .. '"'
	elseif t == "number" then
		return string.format("%.4g", v)
	elseif t == "boolean" or t == "nil" then
		return tostring(v)
	elseif t == "table" then
		if depth <= 0 then return "{..}" end
		if seen[v] then return "{cycle}" end
		seen[v] = true
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		local parts = {}
		for i, k in ipairs(keys) do
			if i > 40 then parts[#parts + 1] = "+" .. (#keys - 40); break end
			local val = v[k]
			if type(val) ~= "function" then parts[#parts + 1] = tostring(k) .. "=" .. ser(val, depth - 1, seen) end
		end
		seen[v] = nil
		return "{" .. table.concat(parts, ",") .. "}"
	elseif t == "Instance" then
		return "<" .. v.ClassName .. ":" .. clean(v.Name, 30) .. ">"
	elseif t == "Color3" then
		return string.format("rgb(%d,%d,%d)", math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5))
	elseif t == "Vector3" then
		return string.format("v3(%.4g,%.4g,%.4g)", v.X, v.Y, v.Z)
	elseif t == "function" then
		return "fn"
	end
	return clean(tostring(v), 40)
end

local timeouts = 0
local function safeRequire(m)
	if timeouts >= 8 then return false, "skipped" end -- trop de modules qui bloquent : on n'insiste plus
	local done, ok, res = false, false, nil
	task.spawn(function()
		ok, res = pcall(require, m)
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < 0.7 do task.wait(0.03) end
	if not done then timeouts += 1; return false, "timeout" end
	return ok, res
end

local function collectContent(progress)
	local add, finish = newCollector()
	local pgui = lp:FindFirstChild("PlayerGui")

	-- tous les textes affiches (ecrans du jeu + panneaux du monde) : noms d'events, de boutiques, de quetes...
	local function texts(root, label)
		walk(root, function(d)
			if d:IsA("TextLabel") and d.Text ~= "" then
				local sg = d:FindFirstAncestorOfClass("ScreenGui")
				if sg and sg.Name == "YslemAnalyzer" then return end
				add("TEXT", "TextLabel", rel(d, root, label), clean(norm(d.Text), 90))
			end
		end)
	end
	if pgui then texts(pgui, "GUI") end
	texts(Workspace, "WS")

	-- donnees du jeu : chaque module de ReplicatedStorage.Data (+ Flags) resume sur une ligne
	local roots = {}
	local data = ReplicatedStorage:FindFirstChild("Data")
	if data then roots[#roots + 1] = {data, "RS/Data"} end
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local flags = shared and shared:FindFirstChild("Flags")
	if flags then roots[#roots + 1] = {flags, "RS/Shared/Flags"} end
	local mods = {}
	for _, r in ipairs(roots) do
		for _, d in ipairs(r[1]:GetDescendants()) do
			if d:IsA("ModuleScript") then mods[#mods + 1] = {d, rel(d, ReplicatedStorage, "RS")} end
		end
	end
	for i, m in ipairs(mods) do
		local ok, res = safeRequire(m[1])
		local text
		if not ok then
			text = "ERR " .. clean(res, 40)
		elseif type(res) == "table" then
			text = clean(ser(res, 3, {}), 700)
		else
			text = clean(ser(res, 1, {}), 200)
		end
		add("DATA", "Module", m[2], text)
		if progress and i % 25 == 0 then progress(i, #mods) end
	end
	return finish()
end

-------------------------------------------------------------------------------------------------- etat + fichiers
local DIR = "yslem_analyzer"
local haveFiles = typeof(writefile) == "function"

local function savePath(name)
	if typeof(makefolder) == "function" and typeof(isfolder) == "function" then
		pcall(function() if not isfolder(DIR) then makefolder(DIR) end end)
		return DIR .. "/" .. name
	end
	return DIR .. "_" .. name
end

local PROMPTS = {
	"GAME UPDATE - etape 1/2 (structure du jeu). Analyse TOUT ce qui est nouveau ou change : nouveaux pets, events, remotes, boutons, prompts, zones, objets, ecrans, scripts. "
		.. "Compare avec les analyses precedentes de docs/scans/ si elles existent, liste toutes les nouveautes, puis adapte les scripts (yslemHub, SourcesHub...) avec les vrais noms uniquement. "
		.. "Attends l'etape 2 avant de conclure. Voici l'etape 1 :",
	"GAME UPDATE - etape 2/2 (contenu du jeu : donnees des modules + tous les textes). Tu as maintenant les deux etapes : fais l'analyse COMPLETE et dis-moi tout ce qui est nouveau "
		.. "(pets, raretes, zones, events, boutiques, produits, quetes), ce qui a change, et ce que tu adaptes dans les scripts. Voici l'etape 2 :",
}

local state = {busy = false, done = {false, false}}
local GameAnalyzer = {Version = VERSION, collectStructure = collectStructure, collectContent = collectContent}
local ui = {}

local COLORS = {
	ok = Color3.fromRGB(90, 220, 140), work = Color3.fromRGB(255, 200, 90), bad = Color3.fromRGB(255, 90, 90),
	info = Color3.fromRGB(255, 176, 176), dim = Color3.fromRGB(150, 110, 110),
}

local function badge(text, color)
	if ui.badge then
		ui.badge.Text = text
		ui.badge.TextColor3 = color or COLORS.info
		ui.badgeFrame.Visible = true
	end
end

local function markStep(i, status)
	local b = ui.steps and ui.steps[i]
	if not b then return end
	b.num.Text = status == "ok" and "OK" or tostring(i)
	b.num.BackgroundColor3 = status == "ok" and COLORS.ok or (status == "work" and COLORS.work or Color3.fromRGB(220, 40, 40))
	b.num.TextColor3 = Color3.fromRGB(20, 0, 0)
end

local function run(step)
	if state.busy then return end
	state.busy = true
	markStep(step, "work")
	badge("Etape " .. step .. " en cours...", COLORS.work)
	local ok, err = pcall(function()
		local lines
		if step == 1 then
			lines = collectStructure()
		else
			lines = collectContent(function(i, total) badge("Etape 2 en cours... " .. i .. "/" .. total, COLORS.work) end)
		end
		local head = header(step)
		local text = table.concat(head, "\n") .. "\n" .. table.concat(lines, "\n")
		local clip = PROMPTS[step] .. "\n\n" .. text
		if haveFiles then pcall(writefile, savePath(tostring(game.PlaceId) .. "_etape" .. step .. ".txt"), text) end
		GameAnalyzer["step" .. step] = text
		local copied = typeof(setclipboard) == "function" and pcall(setclipboard, clip)
		state.done[step] = true
		markStep(step, "ok")
		if copied then
			badge("Etape " .. step .. " faite - copie-colle dans le chat", COLORS.ok)
		else
			badge("Etape " .. step .. " faite - presse-papiers indisponible (fichier " .. DIR .. ")", COLORS.work)
		end
		if ui.hint then
			ui.hint.Text = state.done[1] and state.done[2] and "Les 2 etapes sont faites." or (step == 1 and "Colle dans le chat, puis clique Etape 2." or "Colle dans le chat, puis clique Etape 1.")
		end
	end)
	if not ok then
		markStep(step, "idle")
		badge("Erreur etape " .. step .. " : " .. tostring(err), COLORS.bad)
	end
	state.busy = false
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
		if c.Name == "YslemAnalyzer" then c:Destroy() end
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "YslemAnalyzer"; gui.ResetOnSpawn = false; gui.DisplayOrder = 50
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
	local function label(p, text, x, y, w, h, size, font, color)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1; l.Position = UDim2.new(0, x, 0, y); l.Size = UDim2.new(0, w, 0, h)
		l.Font = font or Enum.Font.GothamMedium; l.TextSize = size or 12; l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = color or Color3.fromRGB(255, 255, 255); l.Text = text
		l.Parent = p
		return l
	end

	local frame = Instance.new("Frame")
	frame.Name = "Window"; frame.Size = UDim2.fromOffset(300, 196)
	frame.Position = UDim2.new(0.5, -150, 0.5, -98)
	frame.BackgroundColor3 = Color3.fromRGB(5, 0, 0); frame.BorderSizePixel = 0; frame.Active = true
	frame.Parent = gui
	corner(frame, 14); stroke(frame, 1.6)

	local title = label(frame, "Game Analyzer", 14, 8, 220, 22, 17, Enum.Font.GothamBold)
	gradient(title, Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 200, 200))
	label(frame, gameName(), 14, 30, 240, 14, 10, nil, COLORS.dim)

	local close = Instance.new("TextButton")
	close.Size = UDim2.fromOffset(24, 24); close.Position = UDim2.new(1, -34, 0, 10)
	close.BackgroundColor3 = Color3.fromRGB(58, 20, 20); close.BorderSizePixel = 0; close.AutoButtonColor = false
	close.Font = Enum.Font.GothamBold; close.TextSize = 12; close.TextColor3 = Color3.fromRGB(255, 90, 90); close.Text = "X"
	close.Parent = frame
	corner(close, 8); stroke(close, 1)
	close.MouseButton1Click:Connect(function() if genv.YslemAnalyzerStop then genv.YslemAnalyzerStop() end end)
	ui.close = close

	ui.steps = {}
	local names = {"Etape 1  -  Structure", "Etape 2  -  Contenu"}
	for i, name in ipairs(names) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, -28, 0, 44); b.Position = UDim2.new(0, 14, 0, 54 + (i - 1) * 54)
		b.BackgroundColor3 = Color3.fromRGB(20, 4, 4); b.BorderSizePixel = 0; b.AutoButtonColor = false
		b.Font = Enum.Font.GothamBold; b.TextSize = 14; b.TextColor3 = Color3.fromRGB(255, 255, 255)
		b.Text = "          " .. name; b.TextXAlignment = Enum.TextXAlignment.Left
		b.Parent = frame
		corner(b, 12); stroke(b, 1.3); gradient(b, Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 190, 190))
		local num = Instance.new("TextLabel")
		num.Size = UDim2.fromOffset(26, 26); num.Position = UDim2.new(0, 10, 0.5, -13)
		num.BackgroundColor3 = Color3.fromRGB(220, 40, 40); num.BorderSizePixel = 0
		num.Font = Enum.Font.GothamBold; num.TextSize = 11; num.TextColor3 = Color3.fromRGB(20, 0, 0); num.Text = tostring(i)
		num.Parent = b
		corner(num, 13)
		b.MouseButton1Click:Connect(function() task.spawn(run, i) end)
		ui.steps[i] = {btn = b, num = num}
	end
	ui.hint = label(frame, "Clique Etape 1, colle dans le chat, puis Etape 2.", 14, 166, 272, 16, 10, nil, COLORS.dim)

	-- badge en bas a droite de l'ecran
	local bf = Instance.new("Frame")
	bf.Name = "Badge"; bf.AnchorPoint = Vector2.new(1, 1); bf.Position = UDim2.new(1, -14, 1, -14)
	bf.Size = UDim2.fromOffset(300, 34); bf.BackgroundColor3 = Color3.fromRGB(12, 2, 2); bf.BorderSizePixel = 0
	bf.Visible = false; bf.Parent = gui
	corner(bf, 17); stroke(bf, 1.4)
	local bl = Instance.new("TextLabel")
	bl.BackgroundTransparency = 1; bl.Size = UDim2.new(1, -20, 1, 0); bl.Position = UDim2.new(0, 12, 0, 0)
	bl.Font = Enum.Font.GothamBold; bl.TextSize = 12; bl.TextXAlignment = Enum.TextXAlignment.Left
	bl.TextColor3 = COLORS.info; bl.Text = ""; bl.TextTruncate = Enum.TextTruncate.AtEnd
	bl.Parent = bf
	ui.badge, ui.badgeFrame = bl, bf

	local dragging, startPos, startInput
	table.insert(connections, frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if input.Position.Y - frame.AbsolutePosition.Y < 46 then
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

	local t0 = os.clock()
	table.insert(connections, RunService.RenderStepped:Connect(function()
		local rot = ((os.clock() - t0) * 60) % 360
		for _, g in ipairs(grads) do
			if g.Parent then g.Rotation = rot end
		end
	end))
end

genv.YslemAnalyzerStop = function()
	for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
	table.clear(connections)
	if ui.gui then pcall(function() ui.gui:Destroy() end) end
	genv.YslemAnalyzerStop = nil
end
genv.YslemAnalyzer = GameAnalyzer

buildUI()

return GameAnalyzer

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
M.getService(nil, "ReplicatedFirst"); M.getService(nil, "Lighting")
M.getService(nil, "MarketplaceService").GetProductInfo = function() return {Name = "Mock Game"} end
local function advance(sec) for _ = 1, math.ceil(sec / 0.05) do M.step(0.05) end end
local function find(root, pred) for _, d in ipairs(root:GetDescendants()) do if pred(d) then return d end end end

local files, clip = {}, nil
writefile = function(p, c) files[p] = c end
setclipboard = function(s) clip = s end
local genvT = {}; getgenv = function() return genvT end
require = function(m) return m._data end

local Players = M.getService(nil, "Players")
local pl = M.newInst("Player"); pl.Name = "Tester"; pl.UserId = 1
pl.PlayerGui = M.newInst("Folder"); pl.PlayerGui.Name = "PlayerGui"; pl.PlayerGui.Parent = pl
pl.Parent = Players; Players.LocalPlayer = pl; Players.GetPlayers = function() return {pl} end
local RS = M.getService(nil, "ReplicatedStorage")
local function mk(class, name, parent) local o = M.newInst(class); o.Name = name; o.Parent = parent; return o end
mk("RemoteEvent", "BasketDrop", mk("Folder", "Game", mk("Folder", "Remotes", RS)))
local data = mk("Folder", "Data", RS)
local pets = mk("Folder", "Configs", mk("Folder", "Assets", data))
local dino = mk("ModuleScript", "Dino", pets); dino._data = {EarningRate = 12.5, Rarity = "Epic", Name = "Dino", Tags = {"a", "b"}}
local newpet = mk("ModuleScript", "Phoenix", pets); newpet._data = {EarningRate = 99, Rarity = "Secret"}
local bad = mk("ModuleScript", "Broken", data); bad._data = nil
require = function(m) if m.Name == "Broken" then error("boom") end return m._data end
local sg = mk("ScreenGui", "Main", pl.PlayerGui)
local drop = mk("TextButton", "Drop", sg); drop.Text = "DROP 12"
local ev = mk("TextLabel", "EventTitle", sg); ev.Text = "Halloween Dimension 2026"
local WS = M.getService(nil, "Workspace")
local egg = mk("Part", "Egg", WS)
local pr = mk("ProximityPrompt", "Prompt", egg); pr.ActionText = "Steal"; pr.ObjectText = "Egg"; pr.HoldDuration = 0

local A = loadAnalyzer()
advance(0.3)
local gui = find(pl.PlayerGui, function(d) return d.Name == "YslemAnalyzer" end) or find(M.getService(nil, "CoreGui"), function(d) return d.Name == "YslemAnalyzer" end)
check("window built", gui ~= nil)
local function btn(prefix) return find(gui, function(d) return d.ClassName == "TextButton" and d.Text:find(prefix, 1, true) ~= nil end) end
local function anyText(s) return find(gui, function(d) return d.ClassName == "TextLabel" and d.Text:find(s, 1, true) ~= nil end) ~= nil end
check("two step buttons", btn("Etape 1") ~= nil and btn("Etape 2") ~= nil)

-- etape 1
btn("Etape 1").MouseButton1Click:Fire(); advance(0.5)
check("step 1: prompt for Claude comes first", clip ~= nil and clip:sub(1, 26) == "GAME UPDATE - etape 1/2 (s")
check("step 1: structure inventory", clip:find("#SNAPSHOT v3", 1, true) and clip:find("#STEP 1/2", 1, true) and clip:find("REMOTE|RemoteEvent|RS/Remotes/Game/BasketDrop||1", 1, true) ~= nil)
check("step 1: button + prompt", clip:find("BUTTON|TextButton|GUI/Main/Drop|DROP #|1", 1, true) and clip:find("PROMPT|ProximityPrompt|WS/Egg/Prompt|Steal / Egg / hold=0|1", 1, true) ~= nil)
check("step 1: module names listed (new pets show up)", clip:find("SCRIPT|ModuleScript|RS/Data/Assets/Configs/Phoenix||1", 1, true) ~= nil)
check("step 1: badge says step 1 done", anyText("Etape 1 faite"))
check("step 1: file saved", files["yslem_analyzer_" .. game.PlaceId .. "_etape1.txt"] ~= nil)

-- etape 2
btn("Etape 2").MouseButton1Click:Fire(); advance(1)
check("step 2: prompt for Claude", clip:sub(1, 26) == "GAME UPDATE - etape 2/2 (c")
check("step 2: module data content", clip:find('DATA|Module|RS/Data/Assets/Configs/Dino|{EarningRate=12.5,Name="Dino",Rarity="Epic",Tags={1="a",2="b"}}|1', 1, true) ~= nil)
check("step 2: new pet data", clip:find('RS/Data/Assets/Configs/Phoenix|{EarningRate=99,Rarity="Secret"}', 1, true) ~= nil)
check("step 2: broken module reported, not fatal", clip:find("RS/Data/Broken|ERR", 1, true) ~= nil)
check("step 2: all texts (events)", clip:find("TEXT|TextLabel|GUI/Main/EventTitle|Halloween Dimension #|1", 1, true) ~= nil)
check("step 2: badge says step 2 done", anyText("Etape 2 faite"))
check("both steps done hint", anyText("Les 2 etapes sont faites"))
check("no player name in the dump", not A.step1:find("Tester", 1, true) and not A.step2:find("Tester", 1, true))

-- fermeture
check("stop function registered", type(genvT.YslemAnalyzerStop) == "function")
genvT.YslemAnalyzerStop()
check("window closed", gui.Parent == nil)
print(string.format("Analyzer: %d ok, %d fail", passes, failures))
if failures > 0 then error("analyzer tests failed") end
