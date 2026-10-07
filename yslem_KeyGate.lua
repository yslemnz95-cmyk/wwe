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
