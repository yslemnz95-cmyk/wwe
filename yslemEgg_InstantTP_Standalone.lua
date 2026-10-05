-- yslemEgg | Instant TP
-- Pick a pet (icon + value), press Steal: taken and delivered with the Instant TP logic only.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local localPlayer = Players.LocalPlayer

------------------------------------------------------------------ settings (same values as the hub)
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
	ApproachSpeed = 400, -- studs/s towards the egg
	RegrabFar = 40, -- egg further than this: teleport onto it, otherwise run to it
	Height = 70, -- the safe-zone run starts above the base and comes down (same as the hub)
	ClimbShare = 0.5,
	CarryRatio = 0.9,
	EasyRatio = 1.3,
}
local FPS = { 60, 30, 0.15 }

------------------------------------------------------------------ game handles
local function safeRequire(getter)
	local ok, result = pcall(function()
		return require(getter())
	end)
	return ok and result or nil
end

local networkingFolder = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Networking")
local EggState = safeRequire(function() return ReplicatedStorage.Client.EggState end)
local Assets = safeRequire(function() return ReplicatedStorage.Data.Assets end)
local Mutations = safeRequire(function() return ReplicatedStorage.Shared.Modules.Mutations end)

local function remote(name)
	return networkingFolder:FindFirstChild(name)
end

local function root()
	local character = localPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function walkSpeed()
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local speed = humanoid and humanoid.WalkSpeed or 16
	local ok, result = pcall(function()
		local stat = localPlayer:FindFirstChild("leaderstats")
		stat = stat and stat:FindFirstChild("Speed")
		local util = require(ReplicatedStorage.Shared.Util.TreadmillUtil)
		return stat and util.SpeedPowerToWalkSpeed(stat.Value) or nil
	end)
	if ok and type(result) == "number" and result > 0 then
		speed = math.max(speed, result)
	end
	return speed
end

------------------------------------------------------------------ carry / delivery state
local state = { Carrying = false, Uid = nil, Delivered = 0, Busy = false, Cancel = false, Mult = 1, PulledAt = 0 }

if type(EggState) == "table" and type(EggState.CarryChanged) == "table" and type(EggState.CarryChanged.Connect) == "function" then
	EggState.CarryChanged:Connect(function(arg)
		local carrying = type(arg) == "table" and arg.IsCarrying == true
		if carrying and arg.GuardDisabled == true then
			carrying = false
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
	remote("RE/EggWorld/FieldEggRedeemVerdict").OnClientEvent:Connect(function()
		state.Delivered = os.clock()
	end)
end)

-- the server pulling us back ("Relocate") is noted so the hop is simply repeated
pcall(function()
	remote("RE/RigSync/Refresh").OnClientEvent:Connect(function(arg)
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

local function fireNearestPrompt(radius)
	local r = root()
	if not r or typeof(fireproximityprompt) ~= "function" then
		return
	end
	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name == "SmartPromptPart" and child:IsA("BasePart") and (child.Position - r.Position).Magnitude <= radius then
			local prompt = child:FindFirstChild("CarryAreaEgg")
			if prompt and prompt:IsA("ProximityPrompt") then
				pcall(fireproximityprompt, prompt)
			end
		end
	end
end

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

------------------------------------------------------------------ egg info for the list (icon, name, value)
local function describe(record)
	local directory = type(Assets) == "table" and Assets.Directory or nil
	local entry = type(directory) == "table" and directory[tostring(record.AssetCategory)] or nil
	local info = { Uid = record.Uid, Category = tostring(record.AssetCategory), Name = tostring(record.AssetCategory), Icon = "", Rarity = 0, Value = 0 }

	if type(entry) == "table" then
		info.Name = tostring(entry.DisplayName or record.AssetCategory)
		local icon = entry.Icon
		if icon ~= nil and tostring(icon) ~= "" then
			icon = tostring(icon)
			info.Icon = tonumber(icon) and ("rbxassetid://" .. icon) or icon
		end
		if type(entry.Rarity) == "table" then
			info.Rarity = tonumber(entry.Rarity.RarityNumber or entry.Rarity.Rank) or 0
		end

		local scale = tonumber(record.AssetScale) or 1
		local factor = scale > 5 and (scale / 5) ^ 1.2 * 19.637875755794113 or scale ^ 1.85
		local mutation = 1
		if type(Mutations) == "table" and type(Mutations.EarningsFor) == "function" then
			local okM, resM = pcall(Mutations.EarningsFor, type(record.Mutations) == "table" and record.Mutations or {})
			if okM and type(resM) == "number" then
				mutation = resM
			end
		end
		info.Value = (tonumber(entry.EarningRate) or 0) * factor * mutation
	end

	return info
end

local function money(value)
	local units = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
	for _, u in ipairs(units) do
		if value >= u[1] then
			return string.format("$%.2f%s/s", value / u[1], u[2])
		end
	end
	return string.format("$%d/s", math.floor(value + 0.5))
end

------------------------------------------------------------------ Instant TP logic
local status = function(text) end

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
	if typeof(setfpscap) ~= "function" then
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

-- fast approach to the egg (position stepping), used before the first grab
local function approach(target)
	local timeout = 0
	while timeout < 25 and not state.Cancel do
		local r = root()
		if not r then
			return false
		end
		local delta = target - r.Position
		if delta.Magnitude <= 4 then
			return true
		end
		local dt = RunService.Heartbeat:Wait()
		timeout += dt
		local step = math.min(CFG.ApproachSpeed * dt, delta.Magnitude)
		pcall(function()
			r.CFrame = CFrame.new(r.Position + delta.Unit * step) * r.CFrame.Rotation
			r.AssemblyLinearVelocity = Vector3.zero
		end)
	end
	return false
end

-- take the egg that lies next to us (also used to take it back after the drop)
local function grab(uid, timeout)
	local waited = 0
	while not state.Carrying and waited < timeout and not state.Cancel do
		takeEgg(uid)
		fireNearestPrompt(10)
		waited += task.wait(CFG.GrabInterval)
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
local function carrySpeed()
	local ws = walkSpeed()
	local base = ws * math.min(CFG.CarryRatio, CFG.SpeedCap) * state.Mult
	return math.max(base, math.min(base * CFG.EasyRatio, ws * CFG.SpeedCap))
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

	-- rise above the base first (no horizontal move), like the hub
	local r = root()
	if r and character and height > 0.5 and home.Y + height - 2 > r.Position.Y then
		pcall(function()
			character:PivotTo(CFrame.new(Vector3.new(r.Position.X, home.Y + height, r.Position.Z)) * r.CFrame.Rotation)
			r.AssemblyLinearVelocity = Vector3.zero
			r.AssemblyAngularVelocity = Vector3.zero
		end)
	end

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
		local flat = Vector3.new(target.X - r.Position.X, 0, target.Z - r.Position.Z)
		if toHome and flat.Magnitude < 2 then
			break
		end

		local speed = carrySpeed()
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
	releaseCamera()

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
		status("Instant TP: taking the egg back")
		if not grab(uid, 3) and not regrab(uid) then
			fpsOff()
			status("Could not take the egg back")
			return false
		end
	end

	-- straight to the safe zone
	local ok = false
	if state.Carrying then
		ok = runHome(lineX, laneZ)
	end
	fpsOff()
	return ok or state.Delivered >= started
end

local function stealAndDeliver(uid)
	if state.Busy then
		return
	end
	state.Busy = true
	state.Cancel = false
	task.spawn(function()
		local ok, err = pcall(function()
			status("Looking for the egg")
			local egg = eggPosition(uid)
			if not egg then
				status("That egg is gone")
				return
			end
			fpsOn()
			status("Going to the egg")
			if not approach(egg + Vector3.new(0, 3, 0)) then
				fpsOff()
				status("Could not reach the egg")
				return
			end
			status("Taking the egg")
			if not grab(uid, 4) then
				fpsOff()
				status("The egg would not come free")
				return
			end
			local delivered = instantTP(uid)
			status(delivered and "Delivered" or "Delivery failed")
		end)
		fpsOff()
		if not ok then
			status("Error: " .. tostring(err))
		end
		state.Busy = false
	end)
end

------------------------------------------------------------------ UI (gold, shining strokes)
local GOLD = Color3.fromRGB(255, 196, 61)
local GOLD_DARK = Color3.fromRGB(150, 100, 20)
local SHINE = Color3.fromRGB(255, 244, 200)
local BG = Color3.fromRGB(16, 14, 10)
local CARD = Color3.fromRGB(27, 23, 15)
local MUTED = Color3.fromRGB(170, 158, 132)
local RARITY_COLORS = {
	Color3.fromRGB(190, 190, 190), Color3.fromRGB(110, 210, 110), Color3.fromRGB(90, 160, 255),
	Color3.fromRGB(190, 110, 255), Color3.fromRGB(255, 170, 50), Color3.fromRGB(255, 80, 80),
	Color3.fromRGB(255, 90, 200), Color3.fromRGB(80, 235, 235),
}

local function parentGui()
	if typeof(gethui) == "function" then
		local ok, result = pcall(gethui)
		if ok and typeof(result) == "Instance" then
			return result
		end
	end
	return CoreGui
end

local function make(class, props)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	return inst
end

-- every stroke gets a bright band that keeps sweeping around it
local shines = {}
local function stroke(parent, thickness, shining)
	local s = make("UIStroke", { Thickness = thickness or 1, Color = shining and Color3.new(1, 1, 1) or GOLD_DARK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	s.Parent = parent
	local g = make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, GOLD_DARK),
			ColorSequenceKeypoint.new(0.42, GOLD),
			ColorSequenceKeypoint.new(0.5, SHINE),
			ColorSequenceKeypoint.new(0.58, GOLD),
			ColorSequenceKeypoint.new(1, GOLD_DARK),
		}),
		Enabled = shining == true,
	})
	g.Parent = s
	shines[#shines + 1] = g
	return s, g
end

local function corner(parent, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius or 6) }).Parent = parent
end

local old = parentGui():FindFirstChild("yslemEgg")
if old then
	old:Destroy()
end

local gui = make("ScreenGui", { Name = "yslemEgg", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true })
gui.Parent = parentGui()

local W, H, HEADER = 190, 214, 22
local window = make("Frame", { Size = UDim2.fromOffset(W, H), Position = UDim2.new(0.5, -W / 2, 0.5, -H / 2), BackgroundColor3 = BG, BorderSizePixel = 0 })
window.Parent = gui
corner(window, 8)
stroke(window, 1.5, true)

local angle = 0
local shineConnection = RunService.Heartbeat:Connect(function(dt)
	angle = (angle + dt * 120) % 360
	for _, g in ipairs(shines) do
		if g.Enabled then
			g.Rotation = angle
		end
	end
end)

local header = make("Frame", { Size = UDim2.new(1, 0, 0, HEADER), BackgroundTransparency = 1 })
header.Parent = window
make("TextLabel", {
	Size = UDim2.new(1, -50, 1, 0), Position = UDim2.fromOffset(8, 0), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack, TextSize = 11, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, Text = "yslemEgg",
}).Parent = header

local function headerButton(text, offset)
	local b = make("TextButton", { Size = UDim2.fromOffset(16, 14), Position = UDim2.new(1, offset, 0.5, -7), BackgroundColor3 = CARD, Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = GOLD, Text = text, AutoButtonColor = true })
	b.Parent = header
	corner(b, 4)
	stroke(b, 1, true)
	return b
end
local minimize = headerButton("-", -38)
local close = headerButton("x", -20)

local body = make("Frame", { Size = UDim2.new(1, -10, 1, -(HEADER + 6)), Position = UDim2.fromOffset(5, HEADER + 2), BackgroundTransparency = 1 })
body.Parent = window

local list = make("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -50), BackgroundColor3 = CARD, BorderSizePixel = 0, ScrollBarThickness = 2, ScrollBarImageColor3 = GOLD,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
})
list.Parent = body
corner(list, 6)
stroke(list, 1, false)
make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }).Parent = list
make("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3), PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 4) }).Parent = list

local statusLabel = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -46), BackgroundTransparency = 1,
	Font = Enum.Font.Gotham, TextSize = 9, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "Pick a pet",
})
statusLabel.Parent = body

-- the panel only shows what happens to the egg, never timings or internals
local PUBLIC = { ["Pick a pet"] = true, ["Looking for the egg"] = true, ["Going to the egg"] = true, ["Taking the egg"] = true, ["Delivered"] = true, ["Delivery failed"] = true, ["That egg is gone"] = true, ["Could not reach the egg"] = true, ["The egg would not come free"] = true, ["Cancelling"] = true }
status = function(text)
	text = tostring(text)
	if PUBLIC[text] then
		statusLabel.Text = text
	elseif string.sub(text, 1, 9) == "Selected:" then
		statusLabel.Text = text
	elseif string.sub(text, 1, 5) == "Error" then
		statusLabel.Text = "Something went wrong"
	elseif state.Busy then
		statusLabel.Text = "Delivering"
	end
end

local function bigButton(text, position, size)
	local b = make("TextButton", { Size = size, Position = position, BackgroundColor3 = CARD, Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = GOLD, Text = text, AutoButtonColor = true })
	b.Parent = body
	corner(b, 6)
	stroke(b, 1, true)
	return b
end
local refreshButton = bigButton("Refresh", UDim2.new(0, 0, 1, -30), UDim2.new(0.34, -2, 0, 24))
local stealButton = bigButton("Steal", UDim2.new(0.34, 2, 1, -30), UDim2.new(0.66, -2, 0, 24))

local selectedUid = nil
local rows = {}

local function setSelected(uid)
	selectedUid = uid
	for rowUid, row in pairs(rows) do
		local on = rowUid == uid
		row.Gradient.Enabled = on
		row.Stroke.Color = on and Color3.new(1, 1, 1) or GOLD_DARK
		row.Stroke.Thickness = on and 1.5 or 1
	end
end

local function rebuild()
	for _, row in pairs(rows) do
		row.Frame:Destroy()
	end
	table.clear(rows)

	local infos = {}
	for _, record in ipairs(snapshot()) do
		infos[#infos + 1] = describe(record)
	end
	table.sort(infos, function(a, b)
		return a.Value > b.Value
	end)

	local still = false
	for index, info in ipairs(infos) do
		still = still or info.Uid == selectedUid
		local frame = make("TextButton", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = BG, LayoutOrder = index, Text = "", AutoButtonColor = true })
		frame.Parent = list
		corner(frame, 5)
		local rowStroke, rowGradient = stroke(frame, 1, false)

		make("ImageLabel", { Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(3, 3), BackgroundTransparency = 1, Image = info.Icon, ScaleType = Enum.ScaleType.Fit }).Parent = frame
		make("TextLabel", {
			Size = UDim2.new(1, -34, 0, 14), Position = UDim2.fromOffset(31, 2), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 10,
			TextColor3 = RARITY_COLORS[math.clamp(info.Rarity, 1, #RARITY_COLORS)] or GOLD, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = info.Name,
		}).Parent = frame
		make("TextLabel", {
			Size = UDim2.new(1, -34, 0, 12), Position = UDim2.fromOffset(31, 16), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 9,
			TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, Text = money(info.Value),
		}).Parent = frame

		rows[info.Uid] = { Frame = frame, Stroke = rowStroke, Gradient = rowGradient }
		frame.MouseButton1Click:Connect(function()
			setSelected(info.Uid)
			status("Selected: " .. info.Name)
		end)
	end

	setSelected(still and selectedUid or nil)
	if #infos == 0 then
		status("Pick a pet")
	end
end

refreshButton.MouseButton1Click:Connect(function()
	if not state.Busy then
		rebuild()
	end
end)

stealButton.MouseButton1Click:Connect(function()
	if state.Busy then
		state.Cancel = true
		status("Cancelling")
		return
	end
	if not selectedUid then
		status("Pick a pet")
		return
	end
	stealAndDeliver(selectedUid)
end)

task.spawn(function()
	while gui.Parent do
		task.wait(0.25)
		stealButton.Text = state.Busy and "Cancel" or "Steal"
	end
end)

-- drag
do
	local dragging, startPos, startInput
	header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, startPos, startInput = true, window.Position, input.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - startInput
			window.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

local minimized = false
minimize.MouseButton1Click:Connect(function()
	minimized = not minimized
	body.Visible = not minimized
	window.Size = minimized and UDim2.fromOffset(W, HEADER) or UDim2.fromOffset(W, H)
end)

close.MouseButton1Click:Connect(function()
	state.Cancel = true
	fpsOff()
	shineConnection:Disconnect()
	gui:Destroy()
end)

rebuild()
task.spawn(function()
	while gui.Parent do
		task.wait(4)
		if not state.Busy and body.Visible then
			rebuild()
		end
	end
end)
