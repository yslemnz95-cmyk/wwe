-- MoonEgg | Instant TP standalone
-- Pick a pet (icon + value) in the small panel, press Steal: the egg is taken and delivered with the Instant TP logic only.
-- No Anti Guard, no Delivery Stop, no external requests.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local localPlayer = Players.LocalPlayer

------------------------------------------------------------------ settings (same values as the hub)
local CFG = {
	SpeedCap = 1.15, -- no speed above 115%
	HopRatio = 1.515, -- hop distance = walk speed * ratio (a distance, not a speed)
	HopMin = 40,
	HopGap = 0.06, -- seconds between two hops
	HopLift = 42, -- height of the hops above the start
	LandOffset = 14, -- landing spot in front of the line
	LandSettle = 0.08,
	DropDelay = 0.05,
	GrabInterval = 0.03,
	ApproachSpeed = 400, -- studs/s towards the egg
	RegrabFar = 40, -- egg further than this: teleport onto it, otherwise run to it
	FpsHigh = 60,
	FpsLow = 30,
	FpsFlip = 0.15,
}

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
local state = { Carrying = false, Uid = nil, Delivered = 0, Busy = false, Cancel = false }

if type(EggState) == "table" and type(EggState.CarryChanged) == "table" and type(EggState.CarryChanged.Connect) == "function" then
	EggState.CarryChanged:Connect(function(arg)
		local carrying = type(arg) == "table" and arg.IsCarrying == true
		if carrying and arg.GuardDisabled == true then
			carrying = false
		end
		if carrying and type(arg.Uid) == "string" then
			state.Uid = arg.Uid
		end
		state.Carrying = carrying
	end)
end

pcall(function()
	remote("RE/EggWorld/FieldEggRedeemVerdict").OnClientEvent:Connect(function()
		state.Delivered = os.clock()
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

-- 60 / 30 FPS flip while the steal runs
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
			pcall(setfpscap, high and CFG.FpsHigh or CFG.FpsLow)
			high = not high
			task.wait(CFG.FpsFlip)
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

-- run in a straight line at `speed` (velocity based) until close or `stop()` is true
local function runTo(target, speed, timeout, stop)
	local elapsed = 0
	while elapsed < timeout and not state.Cancel do
		local r = root()
		if not r then
			return false
		end
		if stop and stop() then
			return true
		end
		local flat = Vector3.new(target.X - r.Position.X, 0, target.Z - r.Position.Z)
		if flat.Magnitude < 2.5 then
			return true
		end
		local v = flat.Unit * math.min(speed, flat.Magnitude / 0.05)
		pcall(function()
			r.AssemblyLinearVelocity = Vector3.new(v.X, r.AssemblyLinearVelocity.Y, v.Z)
		end)
		elapsed += RunService.Heartbeat:Wait()
	end
	return false
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

-- safe zone: checkpoint 7 studs past the line, then the base
local function runHome(lineX, laneZ)
	local ratio = math.min(CFG.SpeedCap, 1)
	local started = os.clock()
	local home = homePoint()
	local speed = walkSpeed() * ratio
	local function done()
		return state.Delivered >= started or not state.Carrying
	end
	status("Safe zone: checkpoint")
	runTo(Vector3.new(lineX - 7, home.Y, laneZ), speed, 6, done)
	if state.Carrying and state.Delivered < started then
		status("Safe zone: home")
		runTo(home, walkSpeed() * ratio, 6, done)
	end
	local settle = 0
	while settle < 2 and state.Delivered < started and state.Carrying and not state.Cancel do
		settle += RunService.Heartbeat:Wait()
	end
	local r = root()
	if r then
		pcall(function()
			r.AssemblyLinearVelocity = Vector3.zero
		end)
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

	-- hops towards the line
	local hopStep = math.max(walkSpeed() * CFG.HopRatio, CFG.HopMin)
	local hopY = r.Position.Y + CFG.HopLift
	local x = r.Position.X
	local releaseCamera = frozenCamera()
	fpsOn()

	while x - hopStep > landing.X and state.Carrying and not state.Cancel do
		x -= hopStep
		status(string.format("Instant TP: hopping home, X %d", math.floor(x)))
		local held = 0
		while held < CFG.HopGap do
			place(Vector3.new(x, hopY, laneZ))
			held += RunService.Heartbeat:Wait()
		end
		if not state.Carrying and not state.Cancel then
			-- the server let go of the egg on the way: take it back right away
			if not regrab(uid) then
				break
			end
			local current = root()
			if current then
				x = math.min(x, current.Position.X)
			end
		end
	end

	-- landing in front of the line
	status("Instant TP: landing next to the line")
	landing = Vector3.new(landing.X, groundY(landing, landing.Y), landing.Z)
	place(landing)
	for attempt = 1, 3 do
		local settle = 0
		while settle < CFG.LandSettle and not state.Cancel do
			settle += RunService.Heartbeat:Wait()
		end
		local landed = root()
		if state.Carrying and landed and (landed.Position.X - landing.X > 12 or landed.Position.Y < landing.Y - 25) then
			status("Instant TP: landing retry " .. attempt)
			place(landing)
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

------------------------------------------------------------------ UI (gold, with strokes)
local GOLD = Color3.fromRGB(255, 196, 61)
local GOLD_DARK = Color3.fromRGB(176, 118, 24)
local BG = Color3.fromRGB(16, 14, 10)
local CARD = Color3.fromRGB(27, 23, 15)
local TEXT = Color3.fromRGB(246, 238, 220)
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

local function make(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	return inst
end

local function stroke(parent, thickness, color)
	local s = make("UIStroke", { Thickness = thickness or 1.5, Color = color or GOLD, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	s.Parent = parent
	return s
end

local function corner(parent, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius or 8) }).Parent = parent
end

local old = parentGui():FindFirstChild("MoonEggInstantTP")
if old then
	old:Destroy()
end

local gui = make("ScreenGui", { Name = "MoonEggInstantTP", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true })
gui.Parent = parentGui()

local window = make("Frame", { Size = UDim2.fromOffset(300, 380), Position = UDim2.new(0.5, -150, 0.5, -190), BackgroundColor3 = BG, BorderSizePixel = 0 })
window.Parent = gui
corner(window, 12)
local windowStroke = stroke(window, 2, GOLD)
make("UIGradient", { Color = ColorSequence.new(GOLD, GOLD_DARK), Rotation = 45 }).Parent = windowStroke

-- the stroke slowly breathes
task.spawn(function()
	while gui.Parent do
		TweenService:Create(windowStroke, TweenInfo.new(1.4, Enum.EasingStyle.Sine), { Transparency = 0.45 }):Play()
		task.wait(1.4)
		TweenService:Create(windowStroke, TweenInfo.new(1.4, Enum.EasingStyle.Sine), { Transparency = 0 }):Play()
		task.wait(1.4)
	end
end)

local header = make("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1 })
header.Parent = window
make("TextLabel", {
	Size = UDim2.new(1, -70, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack, TextSize = 14, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, Text = "MoonEgg  |  Instant TP",
}).Parent = header

local function headerButton(text, offset)
	local b = make("TextButton", { Size = UDim2.fromOffset(24, 22), Position = UDim2.new(1, offset, 0.5, -11), BackgroundColor3 = CARD, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = GOLD, Text = text, AutoButtonColor = true })
	b.Parent = header
	corner(b, 6)
	stroke(b, 1, GOLD_DARK)
	return b
end
local minimize = headerButton("-", -56)
local close = headerButton("x", -28)

local body = make("Frame", { Size = UDim2.new(1, -16, 1, -44), Position = UDim2.fromOffset(8, 38), BackgroundTransparency = 1 })
body.Parent = window

local list = make("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -78), BackgroundColor3 = CARD, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = GOLD,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
})
list.Parent = body
corner(list, 8)
stroke(list, 1, GOLD_DARK)
make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }).Parent = list
make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 6) }).Parent = list

local statusLabel = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -72), BackgroundTransparency = 1,
	Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "Pick a pet",
})
statusLabel.Parent = body
status = function(text)
	statusLabel.Text = tostring(text)
end

local function bigButton(text, position, size)
	local b = make("TextButton", { Size = size, Position = position, BackgroundColor3 = CARD, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = GOLD, Text = text, AutoButtonColor = true })
	b.Parent = body
	corner(b, 8)
	stroke(b, 1.5, GOLD)
	return b
end
local refreshButton = bigButton("Refresh", UDim2.new(0, 0, 1, -48), UDim2.new(0.32, -3, 0, 32))
local stealButton = bigButton("Steal Selected", UDim2.new(0.32, 3, 1, -48), UDim2.new(0.68, -3, 0, 32))
local hint = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -14), BackgroundTransparency = 1,
	Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = MUTED, Text = "Instant TP only  -  max 115%  -  60 / 30 FPS flip",
})
hint.Parent = body

local selectedUid = nil
local rows = {}

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

	if selectedUid then
		local still = false
		for _, info in ipairs(infos) do
			still = still or info.Uid == selectedUid
		end
		if not still then
			selectedUid = nil
		end
	end

	for index, info in ipairs(infos) do
		local frame = make("TextButton", { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = BG, LayoutOrder = index, Text = "", AutoButtonColor = true })
		frame.Parent = list
		corner(frame, 8)
		local rowStroke = stroke(frame, 1.5, GOLD_DARK)

		local icon = make("ImageLabel", { Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(4, 4), BackgroundTransparency = 1, Image = info.Icon, ScaleType = Enum.ScaleType.Fit })
		icon.Parent = frame
		make("TextLabel", {
			Size = UDim2.new(1, -52, 0, 20), Position = UDim2.fromOffset(46, 3), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 13,
			TextColor3 = RARITY_COLORS[math.clamp(info.Rarity, 1, #RARITY_COLORS)] or TEXT, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = info.Name,
		}).Parent = frame
		make("TextLabel", {
			Size = UDim2.new(1, -52, 0, 16), Position = UDim2.fromOffset(46, 23), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 12,
			TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, Text = money(info.Value),
		}).Parent = frame

		rows[info.Uid] = { Frame = frame, Stroke = rowStroke }
		frame.MouseButton1Click:Connect(function()
			selectedUid = info.Uid
			for uid, row in pairs(rows) do
				row.Stroke.Color = uid == selectedUid and GOLD or GOLD_DARK
				row.Stroke.Thickness = uid == selectedUid and 2.5 or 1.5
			end
			status("Selected: " .. info.Name .. "  " .. money(info.Value))
		end)
		if info.Uid == selectedUid then
			rowStroke.Color = GOLD
			rowStroke.Thickness = 2.5
		end
	end

	if #infos == 0 then
		status("No egg on the field right now")
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
		status("Pick a pet first")
		return
	end
	stealButton.Text = "Cancel"
	stealAndDeliver(selectedUid)
end)

task.spawn(function()
	while gui.Parent do
		task.wait(0.25)
		stealButton.Text = state.Busy and "Cancel" or "Steal Selected"
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
	window.Size = minimized and UDim2.fromOffset(300, 34) or UDim2.fromOffset(300, 380)
end)

close.MouseButton1Click:Connect(function()
	state.Cancel = true
	fpsOff()
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
