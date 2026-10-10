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

-- Monde simule : oeuf porte, ligne de separation, base ; le serveur valide la livraison a l'arrivee
local passes, failures = 0, 0
local function check(name, cond)
	if cond then passes += 1 else failures += 1; print("FAIL: " .. name) end
end
tick = tick or os.clock
task.delay = function(t, fn, ...) local a = {...}; task.spawn(function() task.wait(t); fn(table.unpack(a)) end) end
game.IsLoaded = function() return true end

local RunService = M.getService(nil, "RunService")
local workspace_ = workspace

local remotesRef = {}
local function newWorld(opts)
	-- character
	local char = M.newInst("Model"); char.Name = "Character"
	local hrp = M.newInst("Part"); hrp.Name = "HumanoidRootPart"; hrp.Parent = char
	hrp.CFrame = CFrame.new(Vector3.new(opts.startX or 900, 70, -350))
	local hum = M.newInst("Humanoid"); hum.Parent = char
	local localPlayer = M.newInst("Player"); localPlayer.Character = char
	-- the carried egg, welded to the character
	local egg = M.newInst("Model"); egg.Name = "EGG1"; egg.Parent = workspace_
	local weld = M.newInst("WeldConstraint"); weld.Parent = egg
	weld.Part0 = hrp
	local eggAt = nil
	egg.GetPivot = function() return eggAt and CFrame.new(eggAt) or hrp.CFrame end

	local carry = M.signal()
	local state = {carrying = true, verdicts = 0, drops = 0, grabs = 0}
	local EggState = {
		CarryChanged = carry,
		CarryFieldEgg = function(uid) state.grabs += 1; state.carrying = true; weld.Part0 = hrp; eggAt = nil; carry:Fire({IsCarrying = true, Uid = uid, SpeedMultiplier = 1}) end,
		DropFieldEgg = function()
			state.drops += 1
			local wasCarrying = state.carrying
			state.carrying = false; weld.Part0 = nil; eggAt = hrp.Position
			carry:Fire({IsCarrying = false})
			-- putting the egg down on the base is accepted by the server
			local p = hrp.Position
			if wasCarrying and Vector3.new(p.X - 528.7, 0, p.Z + 364.11).Magnitude < 6 then
				state.verdicts += 1
				state.verdictFired = true
				remotesRef["RE/EggWorld/FieldEggRedeemVerdict"].OnClientEvent:Fire()
			end
		end,
	}
	local remotes = {
		["RE/EggWorld/FieldEggRedeemVerdict"] = {OnClientEvent = M.signal()},
		["RE/RigSync/Refresh"] = {OnClientEvent = M.signal()},
	}
	remotesRef = remotes
	local networking = {FindFirstChild = function(_, name) return remotes[name] end}
	local tbl = {EggState = EggState}
	local tbl4 = {
		Root = function() return hrp end,
		WalkSpeed = function() return 20 end,
		SafeCarry = {TpFpsCap = true},
		Steal = {Carrying = true, CarryUid = "EGG1"},
		AntiGuard = {Enabled = false},
	}
	return {char = char, hrp = hrp, egg = egg, weld = weld, localPlayer = localPlayer, remotes = remotes, networking = networking,
		tbl = tbl, tbl4 = tbl4, state = state, EggState = EggState, carry = carry}
end

local function runScenario(name, opts)
	local W = newWorld(opts or {})
	local localPlayer, networking, tbl, tbl4 = W.localPlayer, W.networking, W.tbl, W.tbl4
	local str2 = ""
	local unload = {}
	local function slicedfn4(fn) unload[#unload + 1] = fn end
	local slicedfn13 = function() return false end
	local InstantEngine
	do
		InstantEngine = (function()
				local conns, alive = {}, true
				local EggState = tbl.EggState
				local function remote(name)
					return networking:FindFirstChild(name)
				end
				local function root()
					return tbl4.Root()
				end
				local function walkSpeed()
					return tbl4.WalkSpeed()
				end

local CFG = {
	SpeedCap = 1.15, -- never above 115% of the walk speed
	HopRatio = 1.515, -- hop distance = walk speed * ratio (a distance, not a speed)
	HopMin = 40,
	HopGap = 0.06, -- seconds between two hops (learned: grows after a pull-back, shrinks after a clean hop)
	HopGapMin = 0.06,
	HopGapMax = 0.2,
	HopRetries = 6,
	HopLift = 42, -- height of the hops above the start
	LandOffset = 14, -- landing spot in front of the line
	LandSettle = 0.08,
	DropDelay = 0.05,
	GrabInterval = 0.03,
	RegrabFar = 40, -- egg further than this: teleport onto it, otherwise run to it
	Height = 70, -- the safe-zone run starts above the base and comes down (same as the hub)
	ClimbShare = 0.5,
	CarryRatio = 0.9,
	EasyRatio = 1.3,
}
local FPS = { 60, 30, 0.15 }

local state = { Carrying = false, Uid = nil, Delivered = 0, Busy = false, Cancel = false, Mult = 1, PulledAt = 0, HeldSeen = 0, GuessedDrop = false }

if type(EggState) == "table" and type(EggState.CarryChanged) == "table" and type(EggState.CarryChanged.Connect) == "function" then
	conns[#conns + 1] = EggState.CarryChanged:Connect(function(arg)
		local carrying = type(arg) == "table" and arg.IsCarrying == true
		if carrying and arg.GuardDisabled == true then
			carrying = false
		end
		state.GuessedDrop = false
		if carrying then
			state.HeldSeen = os.clock()
		end
		if carrying and type(arg.Uid) == "string" then
			state.Uid = arg.Uid
			local mult = tonumber(arg.SpeedMultiplier)
			if mult and mult > 0 then
				state.Mult = mult
			end
		end
		state.Carrying = carrying
	end)
end

pcall(function()
	conns[#conns + 1] = remote("RE/EggWorld/FieldEggRedeemVerdict").OnClientEvent:Connect(function()
		state.Delivered = os.clock()
	end)
end)

-- the server pulling us back ("Relocate") is noted so the hop is simply repeated
pcall(function()
	conns[#conns + 1] = remote("RE/RigSync/Refresh").OnClientEvent:Connect(function(arg)
		if type(arg) == "table" and arg.Action == "Relocate" then
			state.PulledAt = os.clock()
		end
	end)
end)

local function takeEgg(uid)
	if type(uid) == "string" and type(EggState) == "table" and type(EggState.CarryFieldEgg) == "function" then
		pcall(EggState.CarryFieldEgg, uid)
	end
end

local function dropEgg()
	if type(EggState) == "table" and type(EggState.DropFieldEgg) == "function" then
		pcall(EggState.DropFieldEgg, "PlayerRequest")
	end
end

-- the prompt of the egg itself (nearest egg prompt to the egg's position), never one of another egg
local function promptNear(position, radius)
	local best, bestDistance = nil, radius
	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name == "SmartPromptPart" and child:IsA("BasePart") then
			local prompt = child:FindFirstChild("CarryAreaEgg")
			if prompt and prompt:IsA("ProximityPrompt") then
				local distance = (child.Position - position).Magnitude
				if distance < bestDistance then
					best, bestDistance = prompt, distance
				end
			end
		end
	end
	return best
end

-- the carried egg is welded to the character: used to catch a missed carry signal (same check as the hub)
local function heldByMe(uid)
	local character = localPlayer.Character
	if type(uid) ~= "string" or not character then
		return false
	end
	local egg = workspace:FindFirstChild(uid)
	if not egg then
		return false
	end
	for _, d in ipairs(egg:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("JointInstance") then
			local ok, a, b = pcall(function()
				return d.Part0, d.Part1
			end)
			if ok and ((a and a:IsDescendantOf(character)) or (b and b:IsDescendantOf(character))) then
				return true
			end
		end
	end
	return false
end

task.spawn(function()
	while alive do
		task.wait(0.2)
		if not state.Carrying then
			if state.GuessedDrop and heldByMe(state.Uid) then
				state.GuessedDrop, state.Carrying, state.HeldSeen = false, true, os.clock()
			end
		elseif heldByMe(state.Uid) then
			state.HeldSeen = os.clock()
		elseif os.clock() - state.HeldSeen > 0.8 then
			state.Carrying, state.GuessedDrop = false, true
		end
	end
end)

local function snapshot()
	local list = {}
	local ok, result = pcall(function()
		return remote("RF/EggWorld/AskFieldEggSnapshot"):InvokeServer()
	end)
	local records = ok and type(result) == "table" and result.Records or nil
	if type(records) ~= "table" then
		return list
	end
	for _, record in pairs(records) do
		if type(record) == "table" and type(record.Uid) == "string" and (record.State == "Slot" or record.State == "Dropped") and typeof(record.BottomCFrame) == "CFrame" then
			list[#list + 1] = record
		end
	end
	return list
end

local function eggPosition(uid)
	for _, record in ipairs(snapshot()) do
		if record.Uid == uid then
			return record.BottomCFrame.Position
		end
	end
	return nil
end

local function status(text)
	str2 = text
end

local function frozenCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		return function() end
	end
	local oldType = camera.CameraType
	local frame = camera.CFrame
	pcall(function()
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = frame
	end)
	return function()
		pcall(function()
			camera.CameraType = oldType
		end)
	end
end

local fpsGen = 0
local function fpsOn()
	if typeof(setfpscap) ~= "function" or tbl4.SafeCarry.TpFpsCap == false then
		return
	end
	fpsGen += 1
	local mine = fpsGen
	task.spawn(function()
		local high = true
		local started = os.clock()
		while fpsGen == mine and os.clock() - started < 60 do
			pcall(setfpscap, high and FPS[1] or FPS[2])
			high = not high
			task.wait(FPS[3])
		end
	end)
end

local function fpsOff()
	fpsGen += 1
	if typeof(setfpscap) == "function" then
		pcall(setfpscap, 240)
	end
end

-- a still copy of the player stays where the egg was taken during the flight; removed on arrival
local stealClone = nil
local function dropClone()
	local copy = stealClone
	stealClone = nil
	if copy then
		pcall(function()
			copy:Destroy()
		end)
	end
end

local function postClone()
	dropClone()
	local character = localPlayer.Character
	if not character then
		return
	end
	local was = character.Archivable
	character.Archivable = true
	local copy = character:Clone()
	character.Archivable = was
	if copy then
		for _, d in ipairs(copy:GetDescendants()) do
			if d:IsA("LuaSourceContainer") or d:IsA("Humanoid") then
				pcall(function()
					d:Destroy()
				end)
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
			end
		end
		copy.Name = "Clone"
		copy.Parent = workspace
		stealClone = copy
	end
end

local function lineInfo()
	local world = workspace:FindFirstChild("World") or workspace:FindFirstChild("__OBJECTS")
	world = world and world:FindFirstChild("Areas")
	world = world and world:FindFirstChild("SeparationLine")
	local ok = world and world:IsA("BasePart")
	return ok and world.Position.X or 552.2, ok and world.Position.Y or 67.67
end

local function homePoint()
	for _, def in ipairs({
		{ { "GearGiver_Slap", "Podium" }, Vector3.new(-16.415, 21.072, -6.106) },
		{ { "World", "Machines", "RiftMachine", "Rift", "Meshes/VoidPortal_Cube.003" }, Vector3.new(-26.776, 1.75, 18.665) },
		{ { "__OBJECTS", "Machines", "RiftMachine", "Rift", "Meshes/VoidPortal_Cube.003" }, Vector3.new(-26.776, 1.75, 18.665) },
	}) do
		local node = workspace
		for _, name in ipairs(def[1]) do
			node = node and node:FindFirstChild(name) or nil
		end
		if node and node:IsA("BasePart") then
			return node.CFrame:PointToWorldSpace(def[2])
		end
	end
	return Vector3.new(528.7, 70.57, -364.11)
end

local function place(position)
	local r = root()
	if not r then
		return
	end
	pcall(function()
		r.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0)
		r.AssemblyLinearVelocity = Vector3.zero
		r.AssemblyAngularVelocity = Vector3.zero
	end)
end

-- portals / arenas / teleporters are walked around (same list as the hub)
local dangerCache, dangerAt = {}, 0
local function dangers()
	if os.clock() - dangerAt < 1 then
		return dangerCache
	end
	dangerAt = os.clock()
	local list = {}
	local function add(inst)
		local ok, cf, size = pcall(function()
			if inst:IsA("Model") then
				return inst:GetBoundingBox()
			elseif inst:IsA("BasePart") then
				return inst.CFrame, inst.Size
			end
		end)
		if ok and cf and size then
			local half = Vector3.new(math.abs(size.X), 0, math.abs(size.Z)) * 0.5
			local rot = (cf - cf.Position):VectorToWorldSpace(half)
			local rx = math.max(math.abs(rot.X), half.X, half.Z)
			local rz = math.max(math.abs(rot.Z), half.X, half.Z)
			list[#list + 1] = { MinX = cf.Position.X - rx, MaxX = cf.Position.X + rx, MinZ = cf.Position.Z - rz, MaxZ = cf.Position.Z + rz }
		end
	end
	local function bad(name)
		if name == "ScrambleLocalVisuals" or name == "DrScrambleEvent" then
			return false
		end
		name = string.lower(name)
		return string.find(name, "portal", 1, true) or string.find(name, "teleport", 1, true) or string.find(name, "mech", 1, true) or string.find(name, "arena", 1, true) or string.find(name, "scramble", 1, true)
	end
	for _, child in ipairs(workspace:GetChildren()) do
		if (child:IsA("Model") or child:IsA("BasePart") or child:IsA("Folder")) and bad(child.Name) then
			if child:IsA("Folder") then
				for _, inner in ipairs(child:GetChildren()) do
					add(inner)
				end
			else
				add(child)
			end
		end
	end
	local build = workspace:FindFirstChild("World")
	build = build and build:FindFirstChild("Build")
	if build then
		for _, child in ipairs(build:GetChildren()) do
			if bad(child.Name) then
				for _, inner in ipairs(child:GetChildren()) do
					add(inner)
				end
			end
		end
	end
	dangerCache = list
	return list
end

-- if the straight line crosses a danger zone, aim at the corner of it instead
local function avoid(from, to)
	for _, d in ipairs(dangers()) do
		local x0, x1, z0, z1 = d.MinX - 12, d.MaxX + 12, d.MinZ - 12, d.MaxZ + 12
		local inside = from.X >= x0 and from.X <= x1 and from.Z >= z0 and from.Z <= z1
		if not inside then
			local t0, t1, hit = 0, 1, true
			for _, axis in ipairs({ { from.X, to.X - from.X, x0, x1 }, { from.Z, to.Z - from.Z, z0, z1 } }) do
				local pos, delta, lo, hi = axis[1], axis[2], axis[3], axis[4]
				if math.abs(delta) < 1e-6 then
					if pos < lo or pos > hi then
						hit = false
					end
				else
					local ta, tb = (lo - pos) / delta, (hi - pos) / delta
					if ta > tb then
						ta, tb = tb, ta
					end
					t0, t1 = math.max(t0, ta), math.min(t1, tb)
					if t0 > t1 then
						hit = false
					end
				end
			end
			if hit then
				local zLow, zHigh = z0 - 2, z1 + 2
				local z = math.abs(from.Z - zLow) <= math.abs(from.Z - zHigh) and zLow or zHigh
				if z < -440 or z > -290 then
					z = z == zLow and zHigh or zLow
				end
				local x = math.abs(from.X - x0) <= math.abs(from.X - x1) and x0 or x1
				if math.abs(from.Z - z) < 3 then
					x = math.abs(to.X - x0) <= math.abs(to.X - x1) and x0 or x1
				end
				return Vector3.new(x, to.Y, z)
			end
		end
	end
	return to
end

-- the hub's "Run" way to the egg: straight on the ground at 115% of the walk speed (never faster).
-- From the base side it first walks out to the safe-zone point, like the hub does.
local function runToEgg(uid, egg)
	local lineX = lineInfo()
	local home = homePoint()
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		if character:FindFirstChildWhichIsA("Tool") then
			pcall(function()
				humanoid:UnequipTools()
			end)
		end
	end

	local r = root()
	if not r then
		return false
	end
	local stage = "field"
	if r.Position.X < lineX - 2 and Vector3.new(r.Position.X - home.X, 0, r.Position.Z - home.Z).Magnitude > 20 then
		stage = "safe"
	end

	local started, lastCheck, lastPos, lastTake = os.clock(), os.clock(), r.Position, 0
	while os.clock() - started < 120 and not state.Cancel do
		r = root()
		if not r then
			return false
		end
		local flatEgg = Vector3.new(egg.X - r.Position.X, 0, egg.Z - r.Position.Z)
		if stage == "field" and flatEgg.Magnitude <= 2.5 then
			break
		end
		local target = egg
		if stage == "safe" then
			if Vector3.new(home.X - r.Position.X, 0, home.Z - r.Position.Z).Magnitude <= 6 then
				stage = "field"
			else
				target = home
			end
		end

		local waypoint = avoid(r.Position, target)
		local flat = Vector3.new(waypoint.X - r.Position.X, 0, waypoint.Z - r.Position.Z)
		local unit = flat.Magnitude > 0.01 and flat.Unit or Vector3.zero
		local speed = math.max(walkSpeed() * CFG.SpeedCap, 8)
		local v = unit * math.min(speed, flat.Magnitude / 0.05)
		pcall(function()
			r.AssemblyLinearVelocity = Vector3.new(v.X, r.AssemblyLinearVelocity.Y, v.Z)
			if humanoid and unit.Magnitude > 0 then
				humanoid:Move(unit, false)
			end
		end)

		-- stuck on something: jump
		if os.clock() - lastCheck >= 1.5 then
			if (r.Position - lastPos).Magnitude < 3 and humanoid and flatEgg.Magnitude > 15 then
				pcall(function()
					humanoid.Jump = true
				end)
			end
			lastPos, lastCheck = r.Position, os.clock()
		end

		-- close enough for the prompt: ask for the egg while arriving
		if stage == "field" and flatEgg.Magnitude <= 9 and os.clock() - lastTake > 0.1 then
			lastTake = os.clock()
			takeEgg(uid)
		end
		RunService.Heartbeat:Wait()
	end

	r = root()
	if r then
		pcall(function()
			r.AssemblyLinearVelocity = Vector3.new(0, r.AssemblyLinearVelocity.Y, 0)
			if humanoid then
				humanoid:Move(Vector3.zero, false)
			end
		end)
	end
	return state.Carrying or (r ~= nil and Vector3.new(egg.X - r.Position.X, 0, egg.Z - r.Position.Z).Magnitude <= 6)
end

-- current position of an egg lying in the world (cheap), with the snapshot as fallback
local function eggNow(uid, cache)
	local node = workspace:FindFirstChild(uid)
	local slots = workspace:FindFirstChild("AreaEggSlotsClient")
	node = node or (slots and slots:FindFirstChild(uid))
	if node then
		local ok, pos = pcall(function()
			return node:GetPivot().Position
		end)
		if ok and pos then
			cache.Pos, cache.At = pos, os.clock()
			return pos
		end
	end
	if os.clock() - cache.At >= 0.5 then
		cache.At = os.clock()
		cache.Pos = eggPosition(uid) or cache.Pos
	end
	return cache.Pos
end

-- take the egg that lies next to us (also used to take it back after the drop): follow it, fire its prompt and send the request
local function grab(uid, timeout)
	local cache = { At = 0 }
	local waited, since = 0, 1
	while not state.Carrying and waited < timeout and not state.Cancel do
		local r = root()
		local egg = eggNow(uid, cache)
		local dt = math.max(RunService.Heartbeat:Wait(), 1 / 240)
		waited += dt
		since += dt
		if r and egg then
			local delta = egg - r.Position
			if delta.Magnitude > 2 then
				local pace = math.max(walkSpeed() * CFG.SpeedCap, 16)
				local v = delta / math.max(0.08, dt)
				if v.Magnitude > pace then
					v = v.Unit * pace
				end
				pcall(function()
					r.AssemblyLinearVelocity = v + Vector3.new(0, workspace.Gravity * dt * 0.5, 0)
					r.AssemblyAngularVelocity = Vector3.zero
				end)
			end
			if since >= CFG.GrabInterval then
				since = 0
				local prompt = promptNear(egg - Vector3.new(0, 3, 0), 10)
				if prompt and typeof(fireproximityprompt) == "function" then
					pcall(function()
						prompt.HoldDuration = 0
					end)
					pcall(fireproximityprompt, prompt)
				end
				task.spawn(takeEgg, uid)
			end
		elseif since >= CFG.GrabInterval then
			since = 0
			task.spawn(takeEgg, uid)
		end
	end
	local r = root()
	if r then
		pcall(function()
			r.AssemblyLinearVelocity = Vector3.zero
		end)
	end
	return state.Carrying and state.Uid == uid
end

local function regrab(uid)
	if state.Carrying then
		return true
	end
	local r = root()
	local egg = eggPosition(uid)
	if r and egg and Vector3.new(r.Position.X - egg.X, 0, r.Position.Z - egg.Z).Magnitude > CFG.RegrabFar then
		status("The egg fell far behind, teleporting onto it")
		place(egg + Vector3.new(0, 3, 0))
	else
		status("The egg fell close, taking it back")
	end
	return grab(uid, 3)
end

local function groundY(position, fallback)
	local y = fallback
	pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { localPlayer.Character }
		params.IgnoreWater = true
		local hit = workspace:Raycast(position + Vector3.new(0, 60, 0), Vector3.new(0, -140, 0), params)
		if hit and hit.Material ~= Enum.Material.Water and math.abs(hit.Position.Y - fallback) < 40 then
			y = hit.Position.Y + 3.5
		end
	end)
	return y
end

-- safe zone: same route as the Normal mode: checkpoint 7 studs past the line, then the base.
-- Speed = the hub's carry plan (never above 115% of the walk speed), the run starts above the base and comes down.
local function carrySpeed(distance)
	local ws = walkSpeed()
	local base = ws * math.min(CFG.CarryRatio, CFG.SpeedCap) * state.Mult
	local fast = base * 1.5 -- SpeedRatio
	local excess = 5.5 * base -- ExcessSeconds
	local limit = fast
	if distance and distance > excess then
		limit = math.min(fast, base * distance / (distance - excess))
	end
	return math.min(math.max(math.min(base * CFG.EasyRatio, limit), base), math.max(ws * CFG.SpeedCap, base))
end

local function runHome(lineX, laneZ)
	local started = os.clock()
	local home = homePoint()
	local checkpoint = lineX - 7
	local height = CFG.Height
	local share = math.clamp(CFG.ClimbShare, 0.1, 0.9)
	local descent = height * math.sqrt(1 - share * share) / share
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end

	-- rise above the base first (no horizontal move), like the hub
	local r = root()
	if r and character and height > 0.5 and home.Y + height - 2 > r.Position.Y then
		pcall(function()
			character:PivotTo(CFrame.new(Vector3.new(r.Position.X, home.Y + height, r.Position.Z)) * r.CFrame.Rotation)
			r.AssemblyLinearVelocity = Vector3.zero
			r.AssemblyAngularVelocity = Vector3.zero
		end)
	end

	-- the speed is planned once, at the start, from the distance still to go (the hub does the same)
	local start = root()
	local speed = carrySpeed(start and (Vector3.new(start.Position.X - home.X, 0, start.Position.Z - home.Z).Magnitude + math.max(0, height) * 2) or nil)

	local last = os.clock()
	local timeout = 0
	status("Safe zone")
	while state.Carrying and state.Delivered < started and not state.Cancel and timeout < 25 do
		r = root()
		if not r then
			return false
		end
		local now = os.clock()
		local dt = math.max(now - last, 1 / 240)
		last = now
		timeout += dt

		local toHome = r.Position.X <= checkpoint + 2
		local target = toHome and home or Vector3.new(checkpoint, home.Y, laneZ)
		if toHome and Vector3.new(home.X - r.Position.X, 0, home.Z - r.Position.Z).Magnitude < 2 then
			break
		end
		local aim = avoid(r.Position, target)
		local flat = Vector3.new(aim.X - r.Position.X, 0, aim.Z - r.Position.Z)
		local remaining = toHome and 0 or math.max(0, r.Position.X - checkpoint)
		local wantY = home.Y + height
		if toHome or remaining <= descent then
			wantY = home.Y + height * math.clamp(remaining / math.max(descent, 1), 0, 1)
		end
		local vy = math.clamp((wantY - r.Position.Y) / 0.12, -speed * share, speed * share)
		local horizontal = math.sqrt(math.max(speed * speed - vy * vy, 0))
		local v = flat.Magnitude > 0.01 and flat.Unit * math.min(horizontal, flat.Magnitude / 0.05) or Vector3.zero
		pcall(function()
			r.AssemblyLinearVelocity = Vector3.new(v.X, vy, v.Z)
		end)
		RunService.Heartbeat:Wait()
	end

	if humanoid then
		pcall(function()
			humanoid:Move(Vector3.zero, false)
		end)
	end

	local settle = 0
	while settle < 2 and state.Delivered < started and state.Carrying and not state.Cancel do
		settle += RunService.Heartbeat:Wait()
	end
	-- still in the hands at home: put it down so the base takes it
	if state.Carrying and state.Delivered < started and not state.Cancel then
		task.wait(0.2)
		dropEgg()
		local waited = 0
		while state.Delivered < started and waited < 1 do
			waited += RunService.Heartbeat:Wait()
		end
	end
	return state.Delivered >= started
end

local function instantTP(uid)
	local started = os.clock()
	local lineX, lineY = lineInfo()
	local r = root()
	if not r then
		return false
	end
	local laneZ = math.clamp(r.Position.Z, -425, -300)
	local landing = Vector3.new(lineX + CFG.LandOffset, lineY + 3.35, laneZ)

	-- hops towards the line; a pull-back repeats the same hop with a longer pause (the pause is learned)
	local hopStep = math.max(walkSpeed() * CFG.HopRatio, CFG.HopMin)
	local hopY = r.Position.Y + CFG.HopLift
	local x = r.Position.X
	local retries = 0
	local releaseCamera = frozenCamera()
	state.ReleaseCamera = releaseCamera
	pcall(postClone)
	fpsOn()

	while x - hopStep > landing.X and not state.Cancel do
		if not state.Carrying then
			-- the server let go of the egg on the way: take it back right away
			if not regrab(uid) then
				break
			end
			local current = root()
			if current then
				x = math.min(x, current.Position.X)
			end
			continue
		end

		local nextX = x - hopStep
		status(string.format("Instant TP: hopping home, X %d", math.floor(nextX)))
		local pulledBefore = state.PulledAt
		local held = 0
		while held < CFG.HopGap do
			place(Vector3.new(nextX, hopY, laneZ))
			held += RunService.Heartbeat:Wait()
		end

		local check = root()
		local pulled = state.PulledAt > pulledBefore or (check ~= nil and (check.Position.X - nextX > 10 or check.AssemblyLinearVelocity.Magnitude > 150))
		if pulled and state.Carrying and not state.Cancel then
			retries += 1
			CFG.HopGap = math.min(CFG.HopGapMax, CFG.HopGap + 0.02)
			if retries > CFG.HopRetries then
				break
			end
			status(string.format("Instant TP: pulled back, retry %d/%d", retries, CFG.HopRetries))
			local settle = 0
			while settle < 0.12 and not state.Cancel do
				place(Vector3.new(x, hopY, laneZ))
				settle += RunService.Heartbeat:Wait()
			end
		else
			x = nextX
			CFG.HopGap = math.max(CFG.HopGapMin, CFG.HopGap - 0.01)
		end
	end

	-- landing in front of the line
	status("Instant TP: landing next to the line")
	landing = Vector3.new(landing.X, groundY(landing, landing.Y), landing.Z)
	local function land()
		local current = root()
		-- never jump backwards: if we are already closer to the line than the landing spot, stay
		if current and current.Position.X <= landing.X + 1 and current.Position.Y > landing.Y - 25 then
			pcall(function()
				current.AssemblyLinearVelocity = Vector3.zero
			end)
			return
		end
		place(landing)
	end
	land()
	for attempt = 1, 3 do
		local settle = 0
		while settle < CFG.LandSettle and not state.Cancel do
			settle += RunService.Heartbeat:Wait()
		end
		local landed = root()
		if state.Carrying and landed and (landed.Position.X - landing.X > 12 or landed.Position.Y < landing.Y - 25) then
			status("Instant TP: landing retry " .. attempt)
			land()
		else
			break
		end
	end
	dropClone()

	-- drop at the line, take it back
	if state.Carrying and not state.Cancel then
		local delay = 0
		while delay < CFG.DropDelay do
			delay += RunService.Heartbeat:Wait()
		end
		status("Instant TP: dropping the egg")
		dropEgg()
		local waited = 0
		while state.Carrying and waited < 1 and not state.Cancel do
			waited += RunService.Heartbeat:Wait()
		end
		local current = root()
		if current then
			pcall(function()
				current.AssemblyLinearVelocity = Vector3.zero
				current.AssemblyAngularVelocity = Vector3.zero
			end)
		end
		-- egg is down: let go of the camera and the copy, then take it back
		releaseCamera()
		dropClone()
		status("Instant TP: taking the egg back")
		if not grab(uid, 3) and not regrab(uid) then
			fpsOff()
			status("Could not take the egg back")
			return false
		end
		dropClone()
	end
	releaseCamera()

	-- straight to the safe zone
	local ok = false
	if state.Carrying then
		ok = runHome(lineX, laneZ)
	end
	fpsOff()
	return ok or state.Delivered >= started
end


				local E = {}

				function E.deliver(uid, cancelFn)
					state.Cancel = false
					state.Uid = uid
					if tbl4.Steal.Carrying == true and not state.Carrying then
						state.Carrying, state.HeldSeen, state.GuessedDrop = true, os.clock(), false
					end
					local running = true
					task.spawn(function()
						while running do
							if cancelFn and cancelFn() then
								state.Cancel = true
							end
							task.wait(0.05)
						end
					end)
					local ok, result = pcall(instantTP, uid)
					running = false
					pcall(dropClone)
					if state.ReleaseCamera then
						pcall(state.ReleaseCamera)
						state.ReleaseCamera = nil
					end
					pcall(fpsOff)
					if not ok then
						status("Instant TP error: " .. tostring(result))
						return false
					end
					return result == true
				end

				slicedfn4(function()
					alive = false
					for _, c in ipairs(conns) do
						pcall(function()
							c:Disconnect()
						end)
					end
				end)
				return E
			end)()

			
		InstantEngine = InstantEngine
	end
	-- server: validates the delivery when we stand on the base
	local home = Vector3.new(528.7, 70.57, -364.11)
	local verdictFired = false
	task.spawn(function()
		while not verdictFired and not W.state.verdictFired do
			task.wait(1 / 60)
			local p = W.hrp.Position
			if W.state.carrying and Vector3.new(p.X - home.X, 0, p.Z - home.Z).Magnitude < 3 then
				verdictFired = true
				W.state.verdicts += 1
				W.remotes["RE/EggWorld/FieldEggRedeemVerdict"].OnClientEvent:Fire()
			end
		end
	end)
	-- optional: the server pulls us back during the third hop
	local pulled = 0
	if opts and opts.pullBack then
		task.spawn(function()
			local lastX = W.hrp.Position.X
			while not verdictFired do
				task.wait(1 / 60)
				local x = W.hrp.Position.X
				if pulled < opts.pullBack and x < 800 and x > 560 and math.abs(x - lastX) > 20 then
					pulled += 1
					W.hrp.CFrame = CFrame.new(Vector3.new(lastX + 10, W.hrp.Position.Y, W.hrp.Position.Z))
					W.remotes["RE/RigSync/Refresh"].OnClientEvent:Fire({Action = "Relocate"})
				end
				lastX = W.hrp.Position.X
			end
		end)
	end
	local result, done = nil, false
	local cancelAt = opts and opts.cancelAfter
	local cancelled = false
	task.spawn(function()
		result = InstantEngine.deliver("EGG1", function() return cancelled end)
		done = true
	end)
	if cancelAt then task.spawn(function() task.wait(cancelAt); cancelled = true end) end
	for i = 1, 60 * 60 do
		M.step(1 / 60)
		if opts and opts.trace and i % 20 == 0 then print(i, string.format("%.0f %.0f %.0f", W.hrp.Position.X, W.hrp.Position.Y, W.hrp.Position.Z), str2, W.state.carrying) end
		if done then break end
	end
	return W, result, done, pulled, str2
end

local W, ok, done, _, why = runScenario("clean")
if ok ~= true then print("clean debug:", tostring(why), W.hrp.Position.X, W.hrp.Position.Y, W.hrp.Position.Z, W.state.drops, W.state.grabs, W.state.verdicts) end
check("clean: engine finished", done)
check("clean: delivery succeeded", ok == true)
check("clean: server verdict received", W.state.verdicts == 1)
check("clean: dropped at the line then took it back", W.state.drops >= 1 and W.state.grabs >= 1)
check("clean: ends over the base", Vector3.new(W.hrp.Position.X - 528.7, 0, W.hrp.Position.Z + 364.11).Magnitude < 40)
check("clean: no stray clone left", workspace_:FindFirstChild("Clone") == nil)

local W2, ok2, done2, pulled2 = runScenario("pulled", {pullBack = 2})
check("pulled: engine finished", done2)
check("pulled: server pulled us back twice", pulled2 == 2)
check("pulled: still delivered", ok2 == true and W2.state.verdicts == 1)

local W3, ok3, done3 = runScenario("cancel", {cancelAfter = 0.3})
check("cancel: engine stops", done3)
check("cancel: reported as not delivered", ok3 == false)
check("cancel: no verdict", W3.state.verdicts == 0)

check("no runtime warnings", #M.warnings == 0)
for _, w in ipairs(M.warnings) do print(w) end
print(string.format("Engine: %d ok, %d fail", passes, failures))
if failures > 0 then error("engine tests failed") end
