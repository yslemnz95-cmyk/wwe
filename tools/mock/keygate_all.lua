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
	o.ChildAdded = signal()
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

local loadModule = function()
-- yslem KeyGate : fenetre de cle + verification aupres du bot (POST /v1/verify)
-- A coller en haut d'un script, puis : if not KeyGate.require("yslemEgg", {onInvalid = stopEverything}) then return end
-- ===== yslem KeyGate START =====
local KeyGate = (function()
	local CFG = {
		API_URL = "https://REPLACE_ME",
		INVITE  = "https://discord.gg/REPLACE_ME",
		CHANNEL = "#key",
		FILE    = "yslem_key.txt",
		RECHECK = 900,
		MAX_RECHECK_ERRORS = 3,
	}

	local Players          = game:GetService("Players")
	local HttpService      = game:GetService("HttpService")
	local RunService       = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")
	local LP = Players.LocalPlayer

	local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request

	local FINAL_BAD = {invalid = true, expired = true, revoked = true, banned = true}
	local KNOWN = {valid = true, invalid = true, expired = true, revoked = true, banned = true}
	local MESSAGES = {
		valid       = "Key accepted",
		invalid     = "Invalid key",
		expired     = "Key expired - use /key reset",
		revoked     = "Key revoked",
		banned      = "Access denied",
		ratelimited = "Too many tries, wait a minute",
		error       = "Server unreachable, try again",
		noapi       = "Your executor cannot make web requests",
		badformat   = "This does not look like a key",
		empty       = "Paste your key first",
	}

	local function cleanKey(raw)
		raw = tostring(raw or "")
		return (raw:gsub("%s+", ""))
	end

	local function keyLooksValid(key)
		return #key >= 28 and #key <= 128 and key:match("^YSL%-[%w_%-]+$") ~= nil
	end

	local function readSaved()
		local ok, key = pcall(function()
			if isfile and readfile and isfile(CFG.FILE) then return readfile(CFG.FILE) end
		end)
		if ok and type(key) == "string" then
			key = cleanKey(key)
			if keyLooksValid(key) then return key end
		end
		return nil
	end

	local function saveKey(key)
		pcall(function() if writefile then writefile(CFG.FILE, key) end end)
	end

	local function clearSaved()
		pcall(function()
			if isfile and isfile(CFG.FILE) then
				if delfile then delfile(CFG.FILE) elseif writefile then writefile(CFG.FILE, "") end
			end
		end)
	end

	local function callVerify(key, scriptName)
		if not httpRequest then return "noapi" end
		local okE, body = pcall(function()
			return HttpService:JSONEncode({key = key, robloxUserId = LP.UserId, script = scriptName, v = 1})
		end)
		if not okE then return "error" end
		local ok, res = pcall(httpRequest, {
			Url = CFG.API_URL .. "/v1/verify",
			Method = "POST",
			Headers = {["Content-Type"] = "application/json"},
			Body = body,
		})
		if not ok or type(res) ~= "table" then return "error" end
		local code = res.StatusCode or res.status_code
		if code == 429 then return "ratelimited" end
		if code ~= 200 then return "error" end
		local okD, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
		if not okD or type(data) ~= "table" or not KNOWN[data.status] then return "error" end
		return data.status
	end

	local function startRecheck(key, scriptName, opts)
		task.spawn(function()
			local errors = 0
			while true do
				task.wait(CFG.RECHECK)
				local st = callVerify(key, scriptName)
				if st == "valid" then
					errors = 0
				elseif FINAL_BAD[st] then
					clearSaved()
					if opts.onInvalid then pcall(opts.onInvalid, st) end
					return
				else
					errors = errors + 1
					if errors >= CFG.MAX_RECHECK_ERRORS then
						if opts.onInvalid then pcall(opts.onInvalid, "error") end
						return
					end
				end
			end
		end)
	end

	-- === UI (yslemStyle) =====================================================
	local WHITE, SILVER, STEEL = Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 156), Color3.fromRGB(70, 70, 76)

	local function bands(a, b)
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(0.25, b), ColorSequenceKeypoint.new(0.5, a),
			ColorSequenceKeypoint.new(0.75, b), ColorSequenceKeypoint.new(1, a),
		})
	end

	local function buildUI(living)
		local parent
		pcall(function() parent = (gethui and gethui()) end)
		parent = parent or game:GetService("CoreGui")

		local gui = Instance.new("ScreenGui")
		gui.Name = "YslemKeyGate"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 999
		gui.Parent = parent

		local function corner(inst, r)
			local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = inst
		end
		local function stroke(inst, th)
			local st = Instance.new("UIStroke")
			st.Thickness = th; st.Color = WHITE; st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Parent = inst
			local g = Instance.new("UIGradient")
			g.Rotation = 45; g.Color = bands(WHITE, STEEL); g.Parent = st
			table.insert(living, g)
		end
		local function textGradient(inst)
			local g = Instance.new("UIGradient")
			g.Color = bands(WHITE, SILVER); g.Parent = inst
			table.insert(living, g)
		end
		local function label(text, size, pos, parentInst, textSize)
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1; l.Text = text; l.Size = size; l.Position = pos
			l.TextColor3 = WHITE; l.Font = Enum.Font.GothamMedium; l.TextSize = textSize or 12
			l.TextXAlignment = Enum.TextXAlignment.Left; l.TextWrapped = true; l.Parent = parentInst
			return l
		end
		local function button(text, pos, parentInst)
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(1, -24, 0, 30); b.Position = pos
			b.BackgroundColor3 = Color3.fromRGB(0, 0, 0); b.Text = text; b.TextColor3 = WHITE
			b.Font = Enum.Font.GothamBold; b.TextSize = 13; b.AutoButtonColor = true; b.Parent = parentInst
			corner(b, 8); stroke(b, 1); textGradient(b)
			return b
		end

		local frame = Instance.new("Frame")
		frame.Name = "Main"
		frame.Size = UDim2.new(0, 280, 0, 262)
		frame.Position = UDim2.new(0.5, -140, 0.5, -131)
		frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		frame.BorderSizePixel = 0
		frame.Parent = gui
		corner(frame, 14); stroke(frame, 1.4)

		local titleBar = Instance.new("Frame")
		titleBar.Size = UDim2.new(1, 0, 0, 28)
		titleBar.BackgroundColor3 = WHITE
		titleBar.BorderSizePixel = 0
		titleBar.Parent = frame
		corner(titleBar, 14)
		local tg = Instance.new("UIGradient"); tg.Color = bands(WHITE, SILVER); tg.Parent = titleBar
		table.insert(living, tg)

		local title = label("yslem  |  KEY", UDim2.new(1, -40, 1, 0), UDim2.new(0, 12, 0, 0), titleBar, 13)
		title.TextColor3 = Color3.fromRGB(0, 0, 0); title.Font = Enum.Font.GothamBold

		local close = Instance.new("TextButton")
		close.Size = UDim2.new(0, 22, 0, 20); close.Position = UDim2.new(1, -28, 0, 4)
		close.BackgroundColor3 = Color3.fromRGB(0, 0, 0); close.Text = "X"; close.TextColor3 = WHITE
		close.Font = Enum.Font.GothamBold; close.TextSize = 12; close.Parent = titleBar
		corner(close, 6); stroke(close, 1); textGradient(close)

		local steps = label(
			"1. Join our Discord server\n2. In " .. CFG.CHANNEL .. " type:  /key " .. tostring(LP.Name) .. "\n3. Paste the key the bot sends you",
			UDim2.new(1, -24, 0, 54), UDim2.new(0, 12, 0, 36), frame, 12)
		textGradient(steps)

		local invite = button("Copy Discord invite", UDim2.new(0, 12, 0, 96), frame)

		local box = Instance.new("TextBox")
		box.Size = UDim2.new(1, -24, 0, 30); box.Position = UDim2.new(0, 12, 0, 136)
		box.BackgroundColor3 = Color3.fromRGB(12, 12, 12); box.Text = ""; box.PlaceholderText = "Paste your key here"
		box.PlaceholderColor3 = SILVER; box.TextColor3 = WHITE; box.Font = Enum.Font.Gotham; box.TextSize = 12
		box.ClearTextOnFocus = false; box.Parent = frame
		corner(box, 8); stroke(box, 1)

		local verify = button("Verify", UDim2.new(0, 12, 0, 176), frame)

		local status = label("", UDim2.new(1, -24, 0, 36), UDim2.new(0, 12, 0, 214), frame, 12)
		status.TextXAlignment = Enum.TextXAlignment.Center
		status.TextColor3 = SILVER

		return {gui = gui, frame = frame, titleBar = titleBar, close = close, invite = invite, box = box, verify = verify, status = status}
	end

	local function makeDraggable(ui)
		local dragging, dragStart, startPos = false, nil, nil
		ui.titleBar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true; dragStart = input.Position; startPos = ui.frame.Position
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local d = input.Position - dragStart
				ui.frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
		end)
	end

	local function showGate(scriptName, prefill, firstMessage)
		local living = {}
		local ui = buildUI(living)
		makeDraggable(ui)
		if prefill then ui.box.Text = prefill end
		if firstMessage then ui.status.Text = firstMessage end

		local clock, tick = 0, 0
		local fx = RunService.Heartbeat:Connect(function(dt)
			clock = clock + dt; tick = tick + 1
			if tick % 2 ~= 0 then return end
			local rot = (clock * 72) % 360
			for i = #living, 1, -1 do
				local g = living[i]
				if g.Parent then
					g.Rotation = g.Parent:IsA("UIStroke") and (45 + rot) % 360 or rot
				else
					table.remove(living, i)
				end
			end
		end)

		local result, finished, busy = nil, false, false
		local function finish(r)
			if finished then return end
			finished = true; result = r
			fx:Disconnect()
			ui.gui:Destroy()
		end

		ui.close.MouseButton1Click:Connect(function() finish(false) end)

		ui.invite.MouseButton1Click:Connect(function()
			local ok = pcall(function() setclipboard(CFG.INVITE) end)
			ui.invite.Text = ok and "Copied!" or CFG.INVITE
		end)

		ui.verify.MouseButton1Click:Connect(function()
			if busy or finished then return end
			local key = cleanKey(ui.box.Text)
			if key == "" then ui.status.Text = MESSAGES.empty; return end
			if not keyLooksValid(key) then ui.status.Text = MESSAGES.badformat; return end
			busy = true
			ui.status.Text = "Checking..."
			task.spawn(function()
				local st = callVerify(key, scriptName)
				busy = false
				if finished then return end
				if st == "valid" then
					saveKey(key)
					ui.status.Text = MESSAGES.valid
					task.wait(0.4)
					finish({key = key})
				else
					if FINAL_BAD[st] then clearSaved() end
					ui.status.Text = MESSAGES[st] or MESSAGES.error
				end
			end)
		end)

		while not finished do task.wait(0.1) end
		return result
	end

	local KG = {CFG = CFG}

	function KG.require(scriptName, opts)
		opts = opts or {}
		scriptName = scriptName or "yslem"
		local saved = readSaved()
		local firstMessage
		if saved then
			local st = callVerify(saved, scriptName)
			if st == "valid" then
				startRecheck(saved, scriptName, opts)
				return true
			end
			if FINAL_BAD[st] then clearSaved(); saved = nil end
			firstMessage = MESSAGES[st] or MESSAGES.error
		end
		local result = showGate(scriptName, saved, firstMessage)
		if result and result.key then
			startRecheck(result.key, scriptName, opts)
			return true
		end
		return false
	end

	return KG
end)()
-- ===== yslem KeyGate END =====

return KeyGate

end
-- Scenarios KeyGate : faux serveur /v1/verify + faux executeur (fichiers, presse-papiers, requetes)
local passes, failures = 0, 0
local function check(name, cond)
	if cond then passes += 1 else failures += 1; print("FAIL: " .. name) end
end

local Players = M.getService(nil, "Players")
local CoreGui = M.getService(nil, "CoreGui")
local UIS = M.getService(nil, "UserInputService")
UIS.InputChanged = M.signal(); UIS.InputEnded = M.signal()
local Http = M.getService(nil, "HttpService")
local lastBody
Http.JSONEncode = function(_, t) lastBody = t; return "ENC" end
Http.JSONDecode = function(_, s) return s end

local me = M.newInst("Player")
me.UserId = 4242; me.Name = "TestUser"
Players.LocalPlayer = me

local files, clip = {}, nil
isfile = function(p) return files[p] ~= nil end
readfile = function(p) return files[p] end
writefile = function(p, c) files[p] = c end
delfile = function(p) files[p] = nil end
setclipboard = function(s) clip = s end

local GOOD = "YSL-" .. string.rep("a", 24)
local OTHER = "YSL-" .. string.rep("b", 24)
local server

local function fakeRequest(opts)
	server.calls += 1
	server.lastBody = lastBody
	if server.mode == "down" then error("connection failed") end
	if server.mode == "429" then return {StatusCode = 429, Body = ""} end
	if server.mode == "500" then return {StatusCode = 500, Body = ""} end
	if server.mode == "garbage" then return {StatusCode = 200, Body = {status = "hacked"}} end
	if opts.Url ~= "https://REPLACE_ME/v1/verify" or opts.Method ~= "POST" then return {StatusCode = 404, Body = ""} end
	local rec = server.keys[lastBody.key]
	local st = "invalid"
	if rec and rec.uid == lastBody.robloxUserId then st = rec.status end
	return {StatusCode = 200, Body = {status = st, expiresAt = 1790000000}}
end

local function fresh(noRequest)
	files = {}; clip = nil
	server = {keys = {}, mode = "ok", calls = 0}
	request = (not noRequest) and fakeRequest or nil
	for _, c in ipairs(CoreGui:GetChildren()) do c:Destroy() end
	return loadModule()
end

local function start(KG, onInvalid)
	local r = {done = false}
	task.spawn(function()
		r.value = KG.require("test", {onInvalid = onInvalid})
		r.done = true
	end)
	return r
end

local function advance(sec) for _ = 1, math.ceil(sec / 0.05) do M.step(0.05) end end
local function find(root, pred) for _, d in ipairs(root:GetDescendants()) do if pred(d) then return d end end end
local function gate() return CoreGui:FindFirstChild("YslemKeyGate") end
local function btn(text) return find(gate(), function(d) return d.ClassName == "TextButton" and d.Text == text end) end
local function box() return find(gate(), function(d) return d.ClassName == "TextBox" end) end
local function hasText(s)
	local g = gate(); if not g then return false end
	return find(g, function(d) return d.ClassName == "TextLabel" and type(d.Text) == "string" and d.Text:find(s, 1, true) ~= nil end) ~= nil
end
local function submit(key)
	box().Text = key
	btn("Verify").MouseButton1Click:Fire()
	advance(0.3)
end

-- 1. cle sauvegardee valide : pas d'UI, une seule requete avec les 4 champs
do
	local KG = fresh()
	files["yslem_key.txt"] = GOOD
	server.keys[GOOD] = {status = "valid", uid = 4242}
	local r = start(KG)
	advance(1)
	check("saved valid: returns true", r.done and r.value == true)
	check("saved valid: no UI", gate() == nil)
	check("saved valid: one request", server.calls == 1)
	local b = server.lastBody
	check("body: only 4 fields", b.key == GOOD and b.robloxUserId == 4242 and b.script == "test" and b.v == 1)
	local n = 0; for _ in pairs(b) do n += 1 end
	check("body: exactly 4 keys", n == 4)
end

-- 2. parcours complet : guide, invitation, mauvais format, cle inconnue, cle bonne
do
	local KG = fresh()
	local r = start(KG)
	advance(0.3)
	check("gate shown", gate() ~= nil and not r.done)
	check("guide has /key <name>", hasText("/key TestUser"))
	btn("Copy Discord invite").MouseButton1Click:Fire()
	check("invite copied", clip == "https://discord.gg/REPLACE_ME")
	submit("")
	check("empty message", hasText("Paste your key first"))
	submit("hello")
	check("bad format message", hasText("does not look like a key"))
	check("bad format never sent", server.calls == 0)
	submit(OTHER)
	check("unknown key -> Invalid key", hasText("Invalid key"))
	check("unknown key sent once", server.calls == 1)
	check("unknown key not saved", files["yslem_key.txt"] == nil)
	server.keys[GOOD] = {status = "valid", uid = 4242}
	submit(GOOD)
	advance(1)
	check("good key returns true", r.done and r.value == true)
	check("good key saved", files["yslem_key.txt"] == GOOD)
	check("UI closed", gate() == nil)
end

-- 3. cle liee a un autre compte Roblox
do
	local KG = fresh()
	server.keys[GOOD] = {status = "valid", uid = 9999}
	local r = start(KG); advance(0.3)
	submit(GOOD)
	check("other userId -> Invalid key", hasText("Invalid key") and not r.done)
	check("other userId not saved", files["yslem_key.txt"] == nil)
end

-- 4. erreurs reseau / limite / reponse incoherente : on refuse mais on garde la fenetre
for _, mode in ipairs({"down", "500", "garbage"}) do
	local KG = fresh()
	server.mode = mode
	local r = start(KG); advance(0.3)
	submit(GOOD)
	check("mode " .. mode .. " -> unreachable", hasText("Server unreachable") and not r.done)
end
do
	local KG = fresh()
	server.mode = "429"
	local r = start(KG); advance(0.3)
	submit(GOOD)
	check("429 -> wait message", hasText("Too many tries") and not r.done)
end

-- 5. cle sauvegardee revoquee : fichier efface, fenetre affichee, fermer -> false
do
	local KG = fresh()
	files["yslem_key.txt"] = GOOD
	server.keys[GOOD] = {status = "revoked", uid = 4242}
	local r = start(KG); advance(0.5)
	check("revoked saved: gate shown", gate() ~= nil and not r.done)
	check("revoked saved: file cleared", files["yslem_key.txt"] == nil)
	check("revoked saved: message", hasText("Key revoked"))
	find(gate(), function(d) return d.ClassName == "TextButton" and d.Text == "X" end).MouseButton1Click:Fire()
	advance(0.3)
	check("close returns false", r.done and r.value == false)
	check("close removes UI", gate() == nil)
end

-- 6. serveur injoignable avec une cle sauvegardee : on la garde et on la prefille
do
	local KG = fresh()
	files["yslem_key.txt"] = GOOD
	server.mode = "down"
	local r = start(KG); advance(0.5)
	check("down+saved: gate shown", gate() ~= nil and not r.done)
	check("down+saved: file kept", files["yslem_key.txt"] == GOOD)
	check("down+saved: prefilled", box().Text == GOOD)
end

-- 7. recheck : la cle est revoquee pendant que le script tourne
do
	local KG = fresh()
	files["yslem_key.txt"] = GOOD
	server.keys[GOOD] = {status = "valid", uid = 4242}
	local got
	start(KG, function(st) got = st end); advance(1)
	check("recheck: still running at start", got == nil)
	server.keys[GOOD].status = "revoked"
	advance(901)
	check("recheck: onInvalid revoked", got == "revoked")
	check("recheck: file cleared", files["yslem_key.txt"] == nil)
end

-- 8. recheck : 2 erreurs reseau tolerees, 3 d'affilee arretent le script
do
	local KG = fresh()
	files["yslem_key.txt"] = GOOD
	server.keys[GOOD] = {status = "valid", uid = 4242}
	local got
	start(KG, function(st) got = st end); advance(1)
	server.mode = "down"
	advance(900); advance(900)
	check("recheck: 2 errors tolerated", got == nil)
	server.mode = "ok"; advance(900)
	check("recheck: recovery resets counter", got == nil)
	server.mode = "down"
	advance(900); advance(900)
	check("recheck: 2 more errors tolerated", got == nil)
	advance(900)
	check("recheck: 3 errors stop", got == "error")
end

-- 9. executeur sans requete web
do
	local KG = fresh(true)
	local r = start(KG); advance(0.3)
	submit(GOOD)
	check("no request fn -> message", hasText("cannot make web requests") and not r.done)
end

print(string.format("KeyGate: %d ok, %d fail", passes, failures))
if failures > 0 then error("KeyGate tests failed") end
