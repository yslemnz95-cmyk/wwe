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
