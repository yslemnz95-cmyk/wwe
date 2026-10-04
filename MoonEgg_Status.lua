-- MoonEgg Status: standalone game scanner for Steal An Egg (read-only, no connection to MoonEgg).
-- Press "Game scan" for a single clipboard message, or "Record" to log what the game sends and
-- what your own client sends to the server while you do something by hand (60 s).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local localPlayer = Players.LocalPlayer

local genv = typeof(getgenv) == "function" and getgenv() or _G

if genv.MoonEggStatusClose then
	pcall(genv.MoonEggStatusClose)
end

local ok0, networking = pcall(function()
	return ReplicatedStorage:WaitForChild("Packages", 10):WaitForChild("Networking", 10)
end)

if not ok0 or not networking then
	warn("MoonEgg Status: networking folder not found")
	return
end

local connections = {}

local function keep(c)
	connections[#connections + 1] = c
	return c
end

-- ===================== formatting helpers =====================

local function ser(v, depth)
	depth = depth or 0
	local t = typeof(v)

	if t == "number" then
		return tostring(math.floor(v * 1000 + 0.5) / 1000)
	elseif t == "string" then
		return '"' .. (#v > 120 and (string.sub(v, 1, 120) .. "~") or v) .. '"'
	elseif t == "boolean" or t == "nil" then
		return tostring(v)
	elseif t == "Vector2" then
		return string.format("(%.2f, %.2f)", v.X, v.Y)
	elseif t == "Vector3" then
		return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
	elseif t == "CFrame" then
		local p = v.Position
		return string.format("CF(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
	elseif t == "Instance" then
		return v.ClassName .. ":" .. v.Name
	elseif t == "table" then
		if depth >= 2 then
			return "{...}"
		end
		local parts, n = {}, 0
		for k, val in pairs(v) do
			n += 1
			if n > 8 then
				parts[#parts + 1] = "..."
				break
			end
			parts[#parts + 1] = tostring(k) .. "=" .. ser(val, depth + 1)
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end

	return t
end

local function ascii(text)
	return (string.gsub(text, "[^\n\32-\126]", "?"))
end

local function path(obj)
	local ok, name = pcall(function()
		return obj:GetFullName()
	end)
	return ok and (string.gsub(name, "^Workspace%.", "")) or tostring(obj)
end

local function attrs(obj, limit)
	local list = {}

	for k, v in pairs(obj:GetAttributes()) do
		list[#list + 1] = k .. "=" .. ser(v)
	end

	table.sort(list)
	local text = table.concat(list, ", ")
	return limit and string.sub(text, 1, limit) or text
end

-- children grouped by name with counts
local function compact(container, limit)
	local counts, order = {}, {}

	for _, child in ipairs(container:GetChildren()) do
		local isPlayer = child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") ~= nil and Players:GetPlayerFromCharacter(child) ~= nil
		local key = isPlayer and "<player>" or (child.ClassName .. ":" .. child.Name)

		if not counts[key] then
			counts[key] = 0
			order[#order + 1] = key
		end
		counts[key] += 1
	end

	table.sort(order)
	local parts = {}

	for _, key in ipairs(order) do
		parts[#parts + 1] = counts[key] > 1 and (key .. " x" .. counts[key]) or key
	end

	local text = table.concat(parts, ", ")
	return limit and string.sub(text, 1, limit) or text
end

local function copy(text)
	text = ascii(text)

	if typeof(setclipboard) ~= "function" then
		return false
	end

	return pcall(setclipboard, text)
end

-- ===================== UI =====================

local C = {
	bg = Color3.fromRGB(14, 14, 24),
	panel = Color3.fromRGB(24, 24, 40),
	stroke = Color3.fromRGB(120, 100, 255),
	text = Color3.fromRGB(235, 235, 255),
	dim = Color3.fromRGB(150, 150, 185),
	good = Color3.fromRGB(110, 230, 160),
}

local parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
local gui = Instance.new("ScreenGui")
gui.Name = "MoonEggStatus"
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.Parent = parent

local function round(obj, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = obj
	return c
end

local function outline(obj, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 1
	s.Color = color or C.stroke
	s.Transparency = 0.35
	s.Parent = obj
	return s
end

local function label(parentObj, text, size, color, bold)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color or C.text
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parentObj
	return l
end

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.fromOffset(250, 262)
main.Position = UDim2.new(0, 14, 0.5, -131)
main.BackgroundColor3 = C.bg
main.BorderSizePixel = 0
main.Parent = gui
round(main, 14)
outline(main, 1.5)

local title = label(main, "MoonEgg Status", 15, C.text, true)
title.Position = UDim2.fromOffset(14, 8)
title.Size = UDim2.new(1, -60, 0, 22)

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.fromOffset(24, 24)
closeButton.Position = UDim2.new(1, -34, 0, 8)
closeButton.BackgroundColor3 = C.panel
closeButton.Text = "x"
closeButton.TextColor3 = C.text
closeButton.TextSize = 14
closeButton.Font = Enum.Font.GothamBold
closeButton.AutoButtonColor = false
closeButton.Parent = main
round(closeButton, 12)

local liveBox = Instance.new("Frame")
liveBox.Position = UDim2.fromOffset(12, 40)
liveBox.Size = UDim2.new(1, -24, 0, 88)
liveBox.BackgroundColor3 = C.panel
liveBox.BorderSizePixel = 0
liveBox.Parent = main
round(liveBox, 10)

local liveText = label(liveBox, "...", 12, C.text, false)
liveText.Position = UDim2.fromOffset(10, 6)
liveText.Size = UDim2.new(1, -20, 1, -12)
liveText.TextWrapped = true
liveText.TextYAlignment = Enum.TextYAlignment.Top

local function pill(text, y, note)
	local b = Instance.new("TextButton")
	b.Position = UDim2.fromOffset(12, y)
	b.Size = UDim2.new(1, -24, 0, 38)
	b.BackgroundColor3 = C.panel
	b.Text = ""
	b.AutoButtonColor = false
	b.Parent = main
	round(b, 19)
	outline(b, 1.2)

	local name = label(b, text, 13, C.text, true)
	name.Position = UDim2.fromOffset(16, 3)
	name.Size = UDim2.new(1, -32, 0, 18)

	local sub = label(b, note, 10, C.dim, false)
	sub.Position = UDim2.fromOffset(16, 20)
	sub.Size = UDim2.new(1, -32, 0, 14)

	return b, sub
end

local scanButton, scanSub = pill("Game scan", 138, "1 part, about 8 s, copied to the clipboard")
local recordButton, recordSub = pill("Record 60 s", 184, "log what the game and your client send")

local statusLine = label(main, "ready", 11, C.dim, false)
statusLine.Position = UDim2.fromOffset(14, 230)
statusLine.Size = UDim2.new(1, -28, 0, 20)

local function setStatus(text, good)
	statusLine.Text = text
	statusLine.TextColor3 = good and C.good or C.dim
end

local function press(button)
	pcall(function()
		local tween = TweenService:Create(button, TweenInfo.new(0.08), { Size = UDim2.new(1, -30, 0, 36) })
		tween:Play()
		task.delay(0.1, function()
			TweenService:Create(button, TweenInfo.new(0.12), { Size = UDim2.new(1, -24, 0, 38) }):Play()
		end)
	end)
end

-- drag by the title
do
	local dragging, startPos, startInput

	keep(main.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if input.Position.Y - main.AbsolutePosition.Y < 40 then
				dragging = true
				startPos = main.Position
				startInput = input.Position
			end
		end
	end))

	keep(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - startInput
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))

	keep(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
end

-- ===================== live status =====================

local frameTimes = 0
local frameCount = 0

keep(RunService.RenderStepped:Connect(function(dt)
	frameTimes += dt
	frameCount += 1
end))

local function liveRefresh()
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local fps = frameTimes > 0 and (frameCount / frameTimes) or 0
	frameTimes, frameCount = 0, 0
	local ping = "?"

	pcall(function()
		ping = string.format("%d ms", game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())
	end)

	local stats = localPlayer:FindFirstChild("leaderstats")
	local statText = {}

	if stats then
		for _, s in ipairs(stats:GetChildren()) do
			if s:IsA("ValueBase") then
				statText[#statText + 1] = s.Name .. " " .. tostring(s.Value)
			end
		end
	end

	liveText.Text = string.format(
		"Island: %s\nWalkSpeed: %s\nPosition: %s\n%.0f FPS, %s\n%s",
		tostring(localPlayer:GetAttribute("AreaId")),
		humanoid and string.format("%.1f", humanoid.WalkSpeed) or "?",
		root and ser(root.Position) or "?",
		fps,
		ping,
		table.concat(statText, ", ")
	)
end

task.spawn(function()
	while gui.Parent do
		pcall(liveRefresh)
		task.wait(0.5)
	end
end)

-- ===================== game scan =====================

local function guardObjects()
	local list, seen = {}, {}

	local function consider(obj)
		if seen[obj] or not obj:IsA("Model") then
			return
		end
		if Players:GetPlayerFromCharacter(obj) then
			return
		end
		local lower = string.lower(obj.Name)
		if obj:GetAttribute("GuardState") ~= nil or string.find(lower, "guard", 1, true) or string.find(lower, "sentry", 1, true) then
			seen[obj] = true
			list[#list + 1] = obj
		end
	end

	for _, child in ipairs(workspace:GetChildren()) do
		consider(child)
	end

	local world = workspace:FindFirstChild("World")

	if world then
		for _, name in ipairs({ "Sentries", "Guards" }) do
			local folder = world:FindFirstChild(name)
			if folder then
				for _, o in ipairs(folder:GetDescendants()) do
					consider(o)
				end
			end
		end

		local areas = world:FindFirstChild("Areas")
		local guardAreas = areas and areas:FindFirstChild("GuardAreas")

		if guardAreas then
			for _, o in ipairs(guardAreas:GetDescendants()) do
				if o:IsA("Model") and (o:FindFirstChildOfClass("Humanoid") or o:GetAttribute("GuardState") ~= nil) then
					if not seen[o] then
						seen[o] = true
						list[#list + 1] = o
					end
				end
			end
		end
	end

	for _, folder in ipairs(workspace:GetChildren()) do
		if folder:IsA("Folder") then
			local lower = string.lower(folder.Name)
			if string.find(lower, "guard", 1, true) or string.find(lower, "sentr", 1, true) then
				for _, o in ipairs(folder:GetDescendants()) do
					consider(o)
				end
			end
		end
	end

	return list
end

local scanning = false

local function gameScan()
	local out = {}

	local function add(line)
		out[#out + 1] = line
	end

	local function section(name)
		add("")
		add("## " .. name)
	end

	local function try(label_, fn)
		local ok, err = pcall(fn)

		if not ok then
			add("(" .. label_ .. " failed: " .. string.sub(tostring(err), 1, 90) .. ")")
		end
	end

	add("MoonEgg game scan " .. os.date("%Y-%m-%d %H:%M:%S"))

	-- server events during the whole scan
	local traffic, trafficOrder, trafficConnections = {}, {}, {}

	for _, remote in ipairs(networking:GetChildren()) do
		if remote:IsA("RemoteEvent") then
			pcall(function()
				trafficConnections[#trafficConnections + 1] = remote.OnClientEvent:Connect(function(...)
					local entry = traffic[remote.Name]

					if not entry then
						local parts = {}
						for i, v in ipairs({ ... }) do
							parts[i] = ser(v)
						end
						entry = { n = 0, sample = string.sub(table.concat(parts, ", "), 1, 170) }
						traffic[remote.Name] = entry
						trafficOrder[#trafficOrder + 1] = remote.Name
					end

					entry.n += 1
				end)
			end)
		end
	end

	section("META")
	try("meta", function()
		add(string.format("place %s job %s players %d/%s", tostring(game.PlaceId), tostring(game.JobId), #Players:GetPlayers(), tostring(Players.MaxPlayers)))
		local executor = typeof(identifyexecutor) == "function" and select(1, identifyexecutor()) or "?"
		add("executor " .. tostring(executor))
	end)

	section("PLAYER")
	try("player", function()
		add("area: " .. tostring(localPlayer:GetAttribute("AreaId")))
		add("attributes: " .. attrs(localPlayer, 500))
		local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")

		if humanoid then
			add(string.format("walkspeed=%.2f jump=%.1f state=%s", humanoid.WalkSpeed, humanoid.JumpPower, tostring(humanoid:GetState())))
		end

		local stats = localPlayer:FindFirstChild("leaderstats")

		if stats then
			local parts = {}
			for _, s in ipairs(stats:GetChildren()) do
				parts[#parts + 1] = s.Name .. "=" .. tostring(s.Value)
			end
			add("leaderstats: " .. table.concat(parts, ", "))
		end

		add("backpack: " .. #localPlayer.Backpack:GetChildren() .. " items")
	end)

	section("WORLD")
	try("world", function()
		add("top level: " .. compact(workspace, 700))
		local world = workspace:FindFirstChild("World")

		if world then
			add("World: " .. compact(world, 700))
			local machines = world:FindFirstChild("Machines")
			if machines then
				for _, m in ipairs(machines:GetChildren()) do
					local pos = m:IsA("Model") and ser(m:GetPivot().Position) or ""
					add("machine " .. m.ClassName .. ":" .. m.Name .. " " .. pos)
				end
			end
		end
	end)

	section("ZONES")
	try("zones", function()
		local areas = workspace.World.Areas

		local function dump(folder, indent)
			add(indent .. "Folder:" .. folder.Name .. (next(folder:GetAttributes()) and (" [" .. attrs(folder, 200) .. "]") or ""))

			for _, child in ipairs(folder:GetChildren()) do
				if child:IsA("BasePart") then
					add(indent .. "  Part:" .. child.Name .. " " .. ser(child.Position) .. " size " .. ser(child.Size) .. (next(child:GetAttributes()) and (" [" .. attrs(child, 120) .. "]") or ""))
				elseif child:IsA("Model") then
					add(indent .. "  Model:" .. child.Name .. " " .. ser(child:GetPivot().Position) .. " size " .. ser(child:GetExtentsSize()) .. " [" .. attrs(child, 160) .. "] children: " .. compact(child, 180))
				else
					add(indent .. "  " .. child.ClassName .. ":" .. child.Name)
				end
			end
		end

		for _, name in ipairs({ "EggCarryBounds", "GuardAreas" }) do
			local f = areas:FindFirstChild(name)
			if f then
				dump(f, "")
			end
		end

		for _, name in ipairs({ "Cosmic", "CherryBlossom", "LightDark", "ButterflyBloom" }) do
			local f = areas:FindFirstChild(name)
			if f then
				dump(f, "")
			end
		end

		local hit = workspace.World:FindFirstChild("DeliveryHitbox")
		if hit then
			add("DeliveryHitbox " .. ser(hit.Position) .. " size " .. ser(hit.Size))
		end
	end)

	section("GUARD DATA (game module)")
	try("guard data", function()
		local guards = require(ReplicatedStorage.Data.Guards)
		local directory = guards.Directory
		local names = {}

		for name in pairs(directory) do
			names[#names + 1] = name
		end

		table.sort(names, function(a, b)
			return (directory[a].WalkSpeed or 0) < (directory[b].WalkSpeed or 0)
		end)

		for _, name in ipairs(names) do
			local g = directory[name]
			local parts = {}

			for k, v in pairs(g) do
				if type(v) == "number" or type(v) == "boolean" or (type(v) == "string" and #v < 32 and not string.find(v, "rbx", 1, true)) then
					parts[#parts + 1] = k .. "=" .. ser(v)
				end
			end

			table.sort(parts)
			add(name .. ": " .. string.sub(table.concat(parts, " "), 1, 215))
		end
	end)

	section("GUARDS (live objects, including inside GuardAreas)")
	local guardList = {}
	try("guards", function()
		guardList = guardObjects()
		add(#guardList .. " guard objects")

		for i, g in ipairs(guardList) do
			if i > 25 then
				break
			end
			local humanoid = g:FindFirstChildOfClass("Humanoid")
			add(path(g) .. " at " .. ser(g:GetPivot().Position) .. " | " .. attrs(g, 160) .. (humanoid and (" | ws " .. tostring(humanoid.WalkSpeed)) or "") .. " | " .. compact(g, 140))
		end

		-- the first area model, to see how a guard is built
		local ga = workspace.World.Areas.GuardAreas
		local sample = ga:FindFirstChild("Titan Temple") or ga:GetChildren()[1]

		if sample then
			add("structure of GuardAreas/" .. sample.Name .. ":")
			for _, d in ipairs(sample:GetDescendants()) do
				if #out < 400 and (d:IsA("Model") or d:IsA("Folder") or d:IsA("Humanoid") or d:IsA("Script") or d:IsA("ModuleScript")) then
					add("  " .. d.ClassName .. ":" .. d.Name .. " (" .. string.gsub(path(d), "^.-GuardAreas%.", "") .. ")")
				end
			end
		end
	end)

	section("GUARD MOTION (6 s sample)")
	try("motion", function()
		local samples = {}

		for _, g in ipairs(guardList) do
			samples[g] = { last = g:GetPivot().Position, lastT = os.clock(), max = 0, travelled = 0, states = { tostring(g:GetAttribute("GuardState")) } }
		end

		local startClock = os.clock()

		for _ = 1, 12 do
			task.wait(0.5)

			for g, s in pairs(samples) do
				if g.Parent then
					local now = os.clock()
					local pos = g:GetPivot().Position
					local dt = math.max(now - s.lastT, 0.001)
					local d = (pos - s.last).Magnitude
					s.travelled += d
					s.max = math.max(s.max, d / dt)
					s.last, s.lastT = pos, now
					local st = tostring(g:GetAttribute("GuardState"))

					if st ~= s.states[#s.states] then
						s.states[#s.states + 1] = st
					end
				end
			end
		end

		local me = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
		local elapsed = math.max(os.clock() - startClock, 0.1)

		for g, s in pairs(samples) do
			add(string.format("%s: max %.1f avg %.1f studs/s, states %s, dist to me %s", g.Name, s.max, s.travelled / elapsed, table.concat(s.states, ">"), me and string.format("%.0f", (s.last - me.Position).Magnitude) or "?"))
		end

		if next(samples) == nil then
			add("no guard to observe")
		end
	end)

	for _, c in ipairs(trafficConnections) do
		pcall(function()
			c:Disconnect()
		end)
	end

	section("EVENT OBJECTS (workspace)")
	try("events", function()
		local patterns = { "event", "arena", "boss", "portal", "chest", "rift", "machine", "butterfl", "beanstalk", "monster", "scramble", "bloom", "tree", "stalk", "firefl", "cloud", "giant" }
		local found = {}

		for _, child in ipairs(workspace:GetChildren()) do
			local lower = string.lower(child.Name)
			for _, p in ipairs(patterns) do
				if string.find(lower, p, 1, true) then
					found[#found + 1] = child.ClassName .. ":" .. child.Name .. (next(child:GetAttributes()) and (" [" .. attrs(child, 160) .. "]") or "")
					break
				end
			end
		end

		-- one level deeper in World and Build
		local world = workspace:FindFirstChild("World")
		for _, holder in ipairs({ world, world and world:FindFirstChild("Build") }) do
			if holder then
				for _, child in ipairs(holder:GetChildren()) do
					local lower = string.lower(child.Name)
					for _, p in ipairs(patterns) do
						if string.find(lower, p, 1, true) then
							found[#found + 1] = path(child) .. " (" .. child.ClassName .. ")"
							break
						end
					end
				end
			end
		end

		add(#found > 0 and table.concat(found, "\n") or "none")
	end)

	section("PROMPTS (distinct, up to 60)")
	try("prompts", function()
		local seen, n = {}, 0

		for _, obj in ipairs(workspace:GetDescendants()) do
			if obj:IsA("ProximityPrompt") then
				local key = obj.ActionText .. "|" .. obj.ObjectText .. "|" .. (obj.Parent and obj.Parent.Name or "")

				if not seen[key] and n < 60 then
					seen[key] = true
					n += 1
					local p = obj.Parent
					local pos = p and p:IsA("BasePart") and (" at " .. ser(p.Position)) or ""
					add(string.format("%q / %q hold %.2f dist %.0f | %s%s", obj.ActionText, obj.ObjectText, obj.HoldDuration, obj.MaxActivationDistance, path(obj), pos))
				end
			end
		end

		if n == 0 then
			add("none")
		end
	end)

	section("SERVER EVENTS DURING THE SCAN")
	try("traffic", function()
		table.sort(trafficOrder, function(a, b)
			return traffic[a].n > traffic[b].n
		end)

		for i, name in ipairs(trafficOrder) do
			if i > 25 then
				break
			end
			add(name .. " x" .. traffic[name].n .. " e.g. (" .. traffic[name].sample .. ")")
		end

		if #trafficOrder == 0 then
			add("none")
		end
	end)

	for i, line in ipairs(out) do
		if #line > 230 then
			out[i] = string.sub(line, 1, 230) .. "~"
		end
	end

	local text = table.concat(out, "\n")

	if #text > 22000 then
		text = string.sub(text, 1, 22000) .. "\n...cut..."
	end

	return text
end

keep(scanButton.MouseButton1Click:Connect(function()
	press(scanButton)

	if scanning then
		return
	end

	scanning = true
	setStatus("scanning, about 8 s...", false)

	task.spawn(function()
		local ok, text = pcall(gameScan)
		scanning = false

		if not ok then
			setStatus("scan failed: " .. string.sub(tostring(text), 1, 60), false)
			return
		end

		local copied = copy("[scan 1/1]\n" .. text)
		setStatus(copied and ("copied, " .. #text .. " characters") or "copy failed", copied)
	end)
end))

-- ===================== recorder =====================

local recording = false
local recordLog = {}
local recordCounts = {}
local recordStart = 0
local hooked = false
local ignoreKnownNoise = { CoinsGathered = true, ProfileDelta = true, RenderStateShifted = true }

local function shortName(remote)
	return string.gsub(remote.Name, "^(%a+)/", "%1 ")
end

local function logLine(direction, remote, ...)
	if not recording then
		return
	end

	local name = remote.Name
	local key = direction .. name
	recordCounts[key] = (recordCounts[key] or 0) + 1

	for noise in pairs(ignoreKnownNoise) do
		if string.find(name, noise, 1, true) then
			return
		end
	end

	if recordCounts[key] > 6 or #recordLog > 260 then
		return
	end

	local parts = {}
	for i, v in ipairs({ ... }) do
		parts[i] = ser(v)
	end

	recordLog[#recordLog + 1] = string.format("%5.1fs %s %s(%s)", os.clock() - recordStart, direction, shortName(remote), string.sub(table.concat(parts, ", "), 1, 170))
end

local function installHook()
	if hooked then
		return true
	end

	if typeof(hookmetamethod) ~= "function" or typeof(getnamecallmethod) ~= "function" then
		return false
	end

	local old
	local ok = pcall(function()
		local wrap = typeof(newcclosure) == "function" and newcclosure or function(f) return f end
		old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
			local method = getnamecallmethod()

			if recording and (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" and self.Parent == networking then
				pcall(logLine, "me->server", self, ...)
			end

			return old(self, ...)
		end))
	end)

	hooked = ok
	return ok
end

keep(recordButton.MouseButton1Click:Connect(function()
	press(recordButton)

	if recording then
		return
	end

	local hookOk = installHook()
	recording = true
	recordLog = {}
	recordCounts = {}
	recordStart = os.clock()
	local positions = {}
	local newThings = {}
	local conns = {}

	for _, remote in ipairs(networking:GetChildren()) do
		if remote:IsA("RemoteEvent") then
			pcall(function()
				conns[#conns + 1] = remote.OnClientEvent:Connect(function(...)
					logLine("server->me", remote, ...)
				end)
			end)
		end
	end

	pcall(function()
		conns[#conns + 1] = game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt)
			recordLog[#recordLog + 1] = string.format("%5.1fs TRIGGERED prompt %q / %q %s", os.clock() - recordStart, prompt.ActionText, prompt.ObjectText, path(prompt))
		end)
	end)

	pcall(function()
		conns[#conns + 1] = workspace.DescendantAdded:Connect(function(obj)
			if #newThings < 60 and (obj:IsA("Model") or obj:IsA("ProximityPrompt") or obj:IsA("Tool")) then
				newThings[#newThings + 1] = string.format("%5.1fs new %s %s", os.clock() - recordStart, obj.ClassName, path(obj))
			end
		end)
	end)

	pcall(function()
		conns[#conns + 1] = localPlayer.AttributeChanged:Connect(function(name)
			if #recordLog < 260 and not string.find(name, "CashPack", 1, true) then
				recordLog[#recordLog + 1] = string.format("%5.1fs player attr %s=%s", os.clock() - recordStart, name, ser(localPlayer:GetAttribute(name)))
			end
		end)
	end)

	task.spawn(function()
		local seconds = 60

		for i = seconds, 1, -1 do
			setStatus("recording: " .. i .. " s, play by hand", false)

			local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
			if root and #positions < 70 and i % 2 == 0 then
				positions[#positions + 1] = string.format("%5.1fs %s", os.clock() - recordStart, ser(root.Position))
			end

			task.wait(1)
		end

		recording = false

		for _, c in ipairs(conns) do
			pcall(function()
				c:Disconnect()
			end)
		end

		local out = { "MoonEgg record " .. os.date("%Y-%m-%d %H:%M:%S") .. " (60 s) | client hook " .. (hookOk and "on" or "unavailable") }
		out[#out + 1] = ""
		out[#out + 1] = "## EXCHANGES (first 6 of each remote)"

		for _, l in ipairs(recordLog) do
			out[#out + 1] = l
		end

		if #recordLog == 0 then
			out[#out + 1] = "nothing"
		end

		out[#out + 1] = ""
		out[#out + 1] = "## COUNTS"
		local keys = {}

		for k in pairs(recordCounts) do
			keys[#keys + 1] = k
		end

		table.sort(keys, function(a, b)
			return recordCounts[a] > recordCounts[b]
		end)

		for i, k in ipairs(keys) do
			if i > 25 then
				break
			end
			out[#out + 1] = k .. " x" .. recordCounts[k]
		end

		out[#out + 1] = ""
		out[#out + 1] = "## NEW OBJECTS"

		for _, l in ipairs(newThings) do
			out[#out + 1] = l
		end

		out[#out + 1] = ""
		out[#out + 1] = "## MY PATH"

		for _, l in ipairs(positions) do
			out[#out + 1] = l
		end

		local text = ascii(table.concat(out, "\n"))

		if #text > 22000 then
			text = string.sub(text, 1, 22000) .. "\n...cut..."
		end

		local copied = copy("[record 1/1]\n" .. text)
		setStatus(copied and ("copied, " .. #text .. " characters") or "copy failed", copied)
	end)
end))

local function close()
	for _, c in ipairs(connections) do
		pcall(function()
			c:Disconnect()
		end)
	end

	if gui then
		gui:Destroy()
	end
end

keep(closeButton.MouseButton1Click:Connect(close))
genv.MoonEggStatusClose = close
