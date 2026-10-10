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

local loadScan = function()
-- yslem GameScan : analyse a la demande, a integrer dans CHAQUE projet.
-- Colle le bloc entre les marqueurs START / END dans le script (il a besoin de
-- Players, ReplicatedStorage et Workspace, deja declares dans les projets) :
--   local report = GameScan.run()          -- texte complet (peut prendre 1-3 s)
--   GameScan.copy(report)                  -- presse-papier si l'executeur le permet
--   GameScan.copy(GameScan.snapshot())     -- "Game update" : inventaire complet et stable a comparer (tools/gamediff.py)
-- Il ne MODIFIE rien : il lit et decrit (contexte, securite, boutons, prompts,
-- remotes, monde, inventaire, scripts).

-- ==== yslem GameScan (START) ================================================
local GameScan = {}

do
	local Players_           = game:GetService("Players")
	local ReplicatedStorage_ = game:GetService("ReplicatedStorage")
	local Workspace_         = game:GetService("Workspace")
	local lp_                = Players_.LocalPlayer

	local MAX_YIELD = 1500 -- on rend la main tous les N elements (pas de gel)

	local function path(inst)
		local ok, p = pcall(function() return inst:GetFullName() end)
		return ok and p or tostring(inst)
	end

	local function walk(root, fn)
		local n = 0
		for _, d in ipairs(root:GetDescendants()) do
			fn(d)
			n = n + 1
			if n % MAX_YIELD == 0 then task.wait() end
		end
	end

	local function shown(obj)
		local p = obj
		while p and p:IsA("GuiObject") do
			if not p.Visible then return false end
			p = p.Parent
		end
		local sg = obj:FindFirstAncestorOfClass("ScreenGui")
		return sg == nil or sg.Enabled
	end

	local function addLines(out, title, lines, limit)
		table.insert(out, "== " .. title .. " (" .. #lines .. ") ==")
		for i, l in ipairs(lines) do
			if i > (limit or 40) then
				table.insert(out, "  ... +" .. (#lines - (limit or 40)) .. " autres")
				break
			end
			table.insert(out, "  " .. l)
		end
		if #lines == 0 then table.insert(out, "  (aucun)") end
	end

	-- 1) contexte -------------------------------------------------------------
	local function sectionContext(out)
		local lines = {}
		local name = "?"
		pcall(function()
			name = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
		end)
		table.insert(lines, "jeu: " .. tostring(name) .. "  PlaceId=" .. game.PlaceId .. "  GameId=" .. game.GameId)
		table.insert(lines, "serveur: " .. #Players_:GetPlayers() .. " joueurs  streaming=" .. tostring(Workspace_.StreamingEnabled))
		table.insert(lines, "joueur: " .. lp_.Name .. " (" .. lp_.UserId .. ")  age compte=" .. lp_.AccountAge .. "j")
		local ch = lp_.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hum then
			table.insert(lines, string.format("humanoid: vie %.0f/%.0f  vitesse %.1f  saut %.1f  etat=%s", hum.Health, hum.MaxHealth, hum.WalkSpeed, hum.UseJumpPower and hum.JumpPower or hum.JumpHeight, tostring(hum:GetState())))
		end
		if hrp then
			table.insert(lines, string.format("position: %.0f, %.0f, %.0f", hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
		end
		local caps = {}
		for _, fname in ipairs({"firesignal", "fireproximityprompt", "setclipboard", "gethui", "setfpscap", "getconnections", "hookfunction", "getgenv", "queue_on_teleport", "writefile", "readfile"}) do
			local okf, fv = pcall(function() return getfenv()[fname] end)
			table.insert(caps, fname .. "=" .. ((okf and type(fv) == "function") and "oui" or "non"))
		end
		pcall(function()
			game:GetService("VirtualInputManager")
			table.insert(caps, "VirtualInputManager=oui")
		end)
		table.insert(lines, "executeur: " .. table.concat(caps, " "))
		addLines(out, "CONTEXTE", lines, 20)
	end

	-- 2) securite : seulement des observations (noms suspects), rien n'est touche
	local SEC_WORDS = {"anticheat", "anti_cheat", "anti-cheat", "cheat", "exploit", "ban", "kick", "detect", "monitor", "security", "verify", "validate", "flag", "violation", "suspicious", "sanity", "integrity"}

	local function secName(n)
		n = n:lower()
		for _, w in ipairs(SEC_WORDS) do
			if n:find(w, 1, true) then return w end
		end
		return nil
	end

	local function sectionSecurity(out)
		local lines = {}
		local function scan(root, label)
			if not root then return end
			walk(root, function(d)
				if #lines >= 60 then return end
				local w = secName(d.Name)
				if w and (d:IsA("LuaSourceContainer") or d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("BindableEvent") or d:IsA("Folder") or d:IsA("ValueBase")) then
					table.insert(lines, label .. " [" .. d.ClassName .. "] " .. path(d) .. "  (mot: " .. w .. ")")
				end
			end)
		end
		scan(ReplicatedStorage_, "RS")
		scan(lp_:FindFirstChild("PlayerScripts"), "PlayerScripts")
		scan(lp_:FindFirstChild("PlayerGui"), "PlayerGui")
		scan(game:GetService("StarterPlayer"), "StarterPlayer")
		for _, c in ipairs(Workspace_:GetChildren()) do
			local w = secName(c.Name)
			if w then table.insert(lines, "Workspace [" .. c.ClassName .. "] " .. c.Name .. "  (mot: " .. w .. ")") end
		end
		-- attributs du joueur / personnage (minuteries, drapeaux)
		local attrs = {}
		for k, v in pairs(lp_:GetAttributes()) do table.insert(attrs, "joueur." .. k .. "=" .. tostring(v)) end
		if lp_.Character then
			for k, v in pairs(lp_.Character:GetAttributes()) do table.insert(attrs, "perso." .. k .. "=" .. tostring(v)) end
		end
		if #attrs > 0 then table.insert(lines, "attributs: " .. table.concat(attrs, ", ")) end
		addLines(out, "SECURITE (observations : noms evocateurs, rien n'est modifie)", lines, 60)
	end

	-- 3) boutons ---------------------------------------------------------------
	local function sectionButtons(out)
		local lines = {}
		local pg = lp_:FindFirstChild("PlayerGui")
		if pg then
			walk(pg, function(d)
				if #lines >= 80 then return end
				if (d:IsA("TextButton") or d:IsA("ImageButton")) and shown(d) and d.AbsoluteSize.X > 0 then
					local txt = ""
					if d:IsA("TextButton") then
						txt = d.Text
					else
						for _, c in ipairs(d:GetDescendants()) do
							if c:IsA("TextLabel") and c.Text ~= "" then txt = c.Text break end
						end
					end
					table.insert(lines, string.format("%s '%s' texte='%s' pos=(%.0f,%.0f) taille=(%.0f,%.0f) <%s>", d.ClassName, d.Name, txt, d.AbsolutePosition.X, d.AbsolutePosition.Y, d.AbsoluteSize.X, d.AbsoluteSize.Y, path(d)))
				end
			end)
		end
		addLines(out, "BOUTONS VISIBLES (PlayerGui)", lines, 50)
	end

	-- 4) prompts ---------------------------------------------------------------
	local function sectionPrompts(out)
		local groups, order = {}, {}
		local hrp = lp_.Character and lp_.Character:FindFirstChild("HumanoidRootPart")
		walk(Workspace_, function(d)
			if d:IsA("ProximityPrompt") then
				local key = (d.ActionText or "") .. " | " .. (d.ObjectText or "")
				local g = groups[key]
				if not g then
					g = {count = 0, near = math.huge, hold = d.HoldDuration, ex = path(d)}
					groups[key] = g
					table.insert(order, key)
				end
				g.count = g.count + 1
				local par = d.Parent
				if hrp and par then
					local pos = par:IsA("BasePart") and par.Position or (par:IsA("Model") and par:GetPivot().Position) or nil
					if pos then g.near = math.min(g.near, (pos - hrp.Position).Magnitude) end
				end
			end
		end)
		local lines = {}
		for _, key in ipairs(order) do
			local g = groups[key]
			table.insert(lines, string.format("'%s' x%d  maintien=%.1fs  plus proche=%s  ex: %s", key, g.count, g.hold, g.near == math.huge and "?" or string.format("%.0f", g.near), g.ex))
		end
		addLines(out, "PROMPTS (ActionText | ObjectText)", lines, 30)
	end

	-- 5) remotes ---------------------------------------------------------------
	local function sectionRemotes(out)
		local byParent, order = {}, {}
		walk(ReplicatedStorage_, function(d)
			if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") then
				local parent = path(d.Parent)
				if not byParent[parent] then byParent[parent] = {} table.insert(order, parent) end
				table.insert(byParent[parent], (d:IsA("RemoteFunction") and "RF:" or "RE:") .. d.Name)
			end
		end)
		local lines = {}
		for _, parent in ipairs(order) do
			table.insert(lines, parent .. " -> " .. table.concat(byParent[parent], ", "))
		end
		addLines(out, "REMOTES (ReplicatedStorage)", lines, 25)
	end

	-- 6) monde -----------------------------------------------------------------
	local function sectionWorld(out)
		local lines = {}
		for _, c in ipairs(Workspace_:GetChildren()) do
			if not c:IsA("Terrain") and not Players_:GetPlayerFromCharacter(c) and c ~= Workspace_.CurrentCamera then
				table.insert(lines, c.ClassName .. " '" .. c.Name .. "' (" .. #c:GetChildren() .. " enfants)")
			end
		end
		table.sort(lines)
		addLines(out, "MONDE (Workspace, premier niveau)", lines, 45)
	end

	-- 7) inventaire / stats -----------------------------------------------------
	local function sectionInventory(out)
		local lines = {}
		local bp = lp_:FindFirstChildOfClass("Backpack")
		if bp then
			local names = {}
			for _, t in ipairs(bp:GetChildren()) do table.insert(names, t.Name) end
			table.insert(lines, "sac: " .. (#names > 0 and table.concat(names, ", ") or "vide"))
		end
		if lp_.Character then
			for _, t in ipairs(lp_.Character:GetChildren()) do
				if t:IsA("Tool") then table.insert(lines, "en main: " .. t.Name) end
			end
		end
		local ls = lp_:FindFirstChild("leaderstats")
		if ls then
			for _, v in ipairs(ls:GetChildren()) do
				if v:IsA("ValueBase") then table.insert(lines, "stat " .. v.Name .. " = " .. tostring(v.Value)) end
			end
		end
		addLines(out, "INVENTAIRE / STATS", lines, 25)
	end

	-- 8) scripts ---------------------------------------------------------------
	local function sectionScripts(out)
		local lines = {}
		local function count(root, label)
			if not root then return end
			local scripts, modules = 0, 0
			local sample = {}
			walk(root, function(d)
				if d:IsA("LocalScript") then
					scripts = scripts + 1
					if #sample < 12 then table.insert(sample, d.Name) end
				elseif d:IsA("ModuleScript") then
					modules = modules + 1
					if #sample < 12 then table.insert(sample, d.Name) end
				end
			end)
			table.insert(lines, label .. ": " .. scripts .. " LocalScript, " .. modules .. " ModuleScript  (" .. table.concat(sample, ", ") .. ")")
		end
		count(lp_:FindFirstChild("PlayerScripts"), "PlayerScripts")
		count(ReplicatedStorage_, "ReplicatedStorage")
		count(lp_:FindFirstChild("PlayerGui"), "PlayerGui")
		addLines(out, "SCRIPTS", lines, 10)
	end

	-- rapport complet ---------------------------------------------------------
	function GameScan.run(sections)
		sections = sections or {}
		local out = {"##### yslem GameScan " .. os.date("%Y-%m-%d %H:%M:%S") .. " #####"}
		local steps = {
			{"context", sectionContext}, {"security", sectionSecurity}, {"buttons", sectionButtons},
			{"prompts", sectionPrompts}, {"remotes", sectionRemotes}, {"world", sectionWorld},
			{"inventory", sectionInventory}, {"scripts", sectionScripts},
		}
		for _, step in ipairs(steps) do
			if sections[step[1]] ~= false then
				local ok, err = pcall(step[2], out)
				if not ok then table.insert(out, "== " .. step[1] .. " : erreur " .. tostring(err)) end
			end
		end
		return table.concat(out, "\n")
	end

	-- Recherche ciblee : tout ce qui contient un mot (boutons/textes d'interface,
	-- remotes, prompts, objets du monde). Exemple : GameScan.find("drop").
	function GameScan.find(keyword)
		keyword = tostring(keyword or ""):lower()
		local out = {"##### yslem GameScan.find '" .. keyword .. "' #####"}
		local function check(label, root)
			if not root then return end
			walk(root, function(d)
				if #out > 80 then return end
				local hit = d.Name:lower():find(keyword, 1, true)
				if not hit and (d:IsA("TextLabel") or d:IsA("TextButton")) then hit = (d.Text or ""):lower():find(keyword, 1, true) end
				if not hit and d:IsA("ProximityPrompt") then hit = ((d.ActionText or "") .. (d.ObjectText or "")):lower():find(keyword, 1, true) end
				if hit then
					local extra = ""
					if d:IsA("TextLabel") or d:IsA("TextButton") then extra = " texte='" .. d.Text .. "'" end
					if d:IsA("ProximityPrompt") then extra = " action='" .. d.ActionText .. "' objet='" .. d.ObjectText .. "'" end
					table.insert(out, label .. " [" .. d.ClassName .. "]" .. extra .. " <" .. path(d) .. ">")
				end
			end)
		end
		check("GUI", lp_:FindFirstChild("PlayerGui"))
		check("RS", ReplicatedStorage_)
		check("WS", Workspace_)
		if #out == 1 then table.insert(out, "(rien trouve)") end
		return table.concat(out, "\n")
	end

	-- Game update : inventaire COMPLET et STABLE (pas de limite, pas de valeurs qui bougent) a comparer avec un
	-- inventaire plus ancien (python3 tools/gamediff.py ancien.txt nouveau.txt). Une ligne = KIND|classe|chemin|extra|n
	-- (les noms avec identifiants/nombres sont normalises, les doublons regroupes dans n).
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

	function GameScan.snapshot()
		local counts, order = {}, {}
		local function add(kind, class, p, extra)
			local key = kind .. "|" .. class .. "|" .. p .. "|" .. (extra or "")
			if counts[key] then counts[key] = counts[key] + 1 else counts[key] = 1; table.insert(order, key) end
		end
		local name = "?"
		pcall(function() name = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name end)
		local pgui = lp_:FindFirstChild("PlayerGui")
		local pscripts = lp_:FindFirstChild("PlayerScripts")

		-- remotes / bindables / scripts de ReplicatedStorage et ReplicatedFirst
		for _, pair in ipairs({{ReplicatedStorage_, "RS"}, {game:GetService("ReplicatedFirst"), "RF"}}) do
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
		-- interface : boutons (nom + texte), tous les ecrans
		if pgui then
			for _, sg in ipairs(pgui:GetChildren()) do
				add("SCREEN", sg.ClassName, "GUI/" .. norm(sg.Name))
			end
			walk(pgui, function(d)
				if d:IsA("TextButton") or d:IsA("ImageButton") then
					local t = d:IsA("TextButton") and norm(d.Text) or ""
					add("BUTTON", d.ClassName, rel(d, pgui, "GUI"), t)
				end
			end)
		end
		-- monde : 3 niveaux sous Workspace (sans les personnages des joueurs), prompts et remotes partout
		local Players = Players_
		local function skip(inst)
			return inst:IsA("Model") and Players:GetPlayerFromCharacter(inst) ~= nil
		end
		local function level(parent, depth)
			for _, c in ipairs(parent:GetChildren()) do
				if not skip(c) then
					add("WORLD", c.ClassName, rel(c, Workspace_, "WS"))
					if depth < 3 then level(c, depth + 1) end
				end
			end
		end
		pcall(level, Workspace_, 1)
		walk(Workspace_, function(d)
			if d:IsA("ProximityPrompt") then
				add("PROMPT", "ProximityPrompt", rel(d, Workspace_, "WS"), norm(d.ActionText) .. " / " .. norm(d.ObjectText) .. " / hold=" .. tostring(d.HoldDuration))
			elseif d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
				add("REMOTE", d.ClassName, rel(d, Workspace_, "WS"))
			end
		end)
		-- stats et attributs (noms seulement)
		local ls = lp_:FindFirstChild("leaderstats")
		if ls then
			for _, v in ipairs(ls:GetChildren()) do add("STAT", v.ClassName, "leaderstats/" .. norm(v.Name)) end
		end
		for k in pairs(lp_:GetAttributes()) do add("ATTR", "Player", "player/" .. norm(k)) end
		local ch = lp_.Character
		if ch then
			for k in pairs(ch:GetAttributes()) do add("ATTR", "Character", "character/" .. norm(k)) end
		end

		table.sort(order)
		local out = {
			"#SNAPSHOT v1",
			"#GAME " .. tostring(name) .. " PlaceId=" .. tostring(game.PlaceId) .. " GameId=" .. tostring(game.GameId),
			"#DATE " .. os.date("%Y-%m-%d %H:%M:%S"),
		}
		for _, key in ipairs(order) do table.insert(out, key .. "|" .. counts[key]) end
		return table.concat(out, "\n")
	end

	function GameScan.save(text, fileName)
		fileName = fileName or ("yslem_snapshot_" .. tostring(game.PlaceId) .. ".txt")
		local ok = pcall(function() writefile(fileName, text) end)
		return ok, fileName
	end

	function GameScan.copy(text)
		local ok = pcall(function() setclipboard(text) end)
		return ok
	end
end
-- ==== yslem GameScan (END) ==================================================

return GameScan

end
local passes, failures = 0, 0
local function check(name, cond) if cond then passes += 1 else failures += 1; print("FAIL: " .. name) end end
local Players = M.getService(nil, "Players")
local pl = M.newInst("Player"); pl.Name = "Tester"; pl.UserId = 1
pl.PlayerGui = M.newInst("Folder"); pl.PlayerGui.Name = "PlayerGui"; pl.PlayerGui.Parent = pl
pl.Parent = Players
Players.LocalPlayer = pl
Players.GetPlayers = function() return {pl} end
local RS = M.getService(nil, "ReplicatedStorage")
local function mk(class, name, parent) local o = M.newInst(class); o.Name = name; o.Parent = parent; return o end
local remotes = mk("Folder", "Remotes", RS)
mk("RemoteEvent", "BasketDrop", mk("Folder", "Game", remotes))
mk("RemoteEvent", "Egg_12345", remotes); mk("RemoteEvent", "Egg_98765", remotes)
local sg = mk("ScreenGui", "Main", pl.PlayerGui)
local b = mk("TextButton", "Drop", sg); b.Text = "DROP 12"
local WS = M.getService(nil, "Workspace")
local plots = mk("Folder", "Plots", WS); mk("Model", "Plot", plots)
local pr = mk("ProximityPrompt", "Prompt", mk("Part", "Egg", WS)); pr.ActionText = "Pick Up"; pr.ObjectText = "Dino"; pr.HoldDuration = 0.2

local GameScan = loadScan()
local snap = GameScan.snapshot()
check("header", snap:find("#SNAPSHOT v1", 1, true) ~= nil and snap:find("#GAME", 1, true) ~= nil)
check("remote listed with a stable path", snap:find("REMOTE|RemoteEvent|RS/Remotes/Game/BasketDrop||1", 1, true) ~= nil)
check("ids normalised and duplicates counted", snap:find("REMOTE|RemoteEvent|RS/Remotes/Egg_#||2", 1, true) ~= nil)
check("button with normalised text", snap:find("BUTTON|TextButton|GUI/Main/Drop|DROP #|1", 1, true) ~= nil)
check("prompt with action, object and hold", snap:find("PROMPT|ProximityPrompt|WS/Egg/Prompt|Pick Up / Dino / hold=0.2|1", 1, true) ~= nil)
check("world levels", snap:find("WORLD|Folder|WS/Plots|", 1, true) ~= nil and snap:find("WORLD|Model|WS/Plots/Plot|", 1, true) ~= nil)
local lines = {}
for l in snap:gmatch("[^\n]+") do if l:sub(1, 1) ~= "#" then lines[#lines + 1] = l end end
local sorted = true
for i = 2, #lines do if lines[i - 1] > lines[i] then sorted = false end end
check("lines sorted (stable output)", sorted)
check("no player name in the snapshot", snap:find("Tester", 1, true) == nil)
print(string.format("Scan: %d ok, %d fail", passes, failures))
if failures > 0 then error("scan tests failed") end
