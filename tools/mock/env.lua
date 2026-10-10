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

return M
