-- yslem Game Update v2 : TOUT EN UN FICHIER (analyse + comparaison + fenetre yslemStyle).
-- Execute-le dans le jeu : il scanne, compare avec la reference de ce jeu (sauvegardee dans le dossier de l'executeur),
-- montre tout ce qui a change (+ ajoute, - supprime, > deplace, ~ modifie) et copie le rapport pour qu'on l'adapte.
-- Il ne MODIFIE rien dans le jeu : il lit des noms et ecrit seulement 3 petits fichiers texte. Aucun acces reseau.
--   Scan     : relance l'analyse (se lance deja a l'ouverture)
--   Copy     : copie le rapport + l'inventaire complet (a coller dans le chat)
--   Baseline : remplace la reference par le dernier inventaire (a faire quand tout est adapte)

local VERSION = 2

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local lp = Players.LocalPlayer

local genv = typeof(getgenv) == "function" and getgenv() or _G
if type(genv.YslemGameUpdateStop) == "function" then pcall(genv.YslemGameUpdateStop) end

-------------------------------------------------------------------------------------------------- inventaire
local MAX_YIELD = 1500

local function walk(root, fn)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		fn(d)
		n += 1
		if n % MAX_YIELD == 0 then task.wait() end
	end
end

-- noms stables : identifiants et nombres remplaces, separateurs retires
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

local function snapshot()
	local counts, order = {}, {}
	local function add(kind, class, p, extra)
		local key = kind .. "|" .. class .. "|" .. p .. "|" .. (extra or "")
		if counts[key] then counts[key] += 1 else counts[key] = 1; table.insert(order, key) end
	end
	local gname = "?"
	pcall(function() gname = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name end)
	local pgui = lp:FindFirstChild("PlayerGui")
	local pscripts = lp:FindFirstChild("PlayerScripts")

	for _, pair in ipairs({{ReplicatedStorage, "RS"}, {game:GetService("ReplicatedFirst"), "RF"}}) do
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
	if pgui then
		for _, sg in ipairs(pgui:GetChildren()) do
			if sg.Name ~= "YslemGameUpdate" then add("SCREEN", sg.ClassName, "GUI/" .. norm(sg.Name)) end
		end
		walk(pgui, function(d)
			if d:IsA("TextButton") or d:IsA("ImageButton") then
				local sg = d:FindFirstAncestorOfClass("ScreenGui")
				if sg and sg.Name == "YslemGameUpdate" then return end
				add("BUTTON", d.ClassName, rel(d, pgui, "GUI"), d:IsA("TextButton") and norm(d.Text) or "")
			end
		end)
	end
	local function skip(inst)
		return inst:IsA("Model") and Players:GetPlayerFromCharacter(inst) ~= nil
	end
	local function level(parent, depth)
		for _, c in ipairs(parent:GetChildren()) do
			if not skip(c) then
				add("WORLD", c.ClassName, rel(c, Workspace, "WS"))
				if depth < 3 then level(c, depth + 1) end
			end
		end
	end
	pcall(level, Workspace, 1)
	walk(Workspace, function(d)
		if d:IsA("ProximityPrompt") then
			add("PROMPT", "ProximityPrompt", rel(d, Workspace, "WS"), norm(d.ActionText) .. " / " .. norm(d.ObjectText) .. " / hold=" .. tostring(d.HoldDuration))
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

	table.sort(order)
	local out = {
		"#SNAPSHOT v1",
		"#GAME " .. tostring(gname) .. " PlaceId=" .. tostring(game.PlaceId) .. " GameId=" .. tostring(game.GameId),
		"#DATE " .. os.date("%Y-%m-%d %H:%M:%S"),
	}
	for _, key in ipairs(order) do table.insert(out, key .. "|" .. counts[key]) end
	return table.concat(out, "\n"), #order
end

-------------------------------------------------------------------------------------------------- comparaison
local function parse(text)
	local meta, rows = {}, {}
	for line in tostring(text):gmatch("[^\r\n]+") do
		if line:sub(1, 1) == "#" then
			local k, v = line:match("^#(%S+)%s*(.*)$")
			if k then meta[k] = v end
		else
			local parts = {}
			for piece in (line .. "|"):gmatch("(.-)|") do parts[#parts + 1] = piece end
			if #parts >= 5 then
				local n = tonumber(parts[#parts]) or 1
				local extra = table.concat(parts, "|", 4, #parts - 1)
				rows[parts[1] .. "|" .. parts[3]] = {kind = parts[1], class = parts[2], path = parts[3], extra = extra, n = n}
			end
		end
	end
	return meta, rows
end

local function leaf(p) return p:match("([^/]*)$") or p end

local function diff(oldRows, newRows)
	local added, removed, changed, moved = {}, {}, {}, {}
	for k, v in pairs(newRows) do
		local o = oldRows[k]
		if not o then
			table.insert(added, v)
		elseif o.class ~= v.class or o.extra ~= v.extra or o.n ~= v.n then
			local bits = {}
			if o.class ~= v.class then bits[#bits + 1] = "class " .. o.class .. " -> " .. v.class end
			if o.extra ~= v.extra then bits[#bits + 1] = "'" .. o.extra .. "' -> '" .. v.extra .. "'" end
			if o.n ~= v.n then bits[#bits + 1] = "x" .. o.n .. " -> x" .. v.n end
			table.insert(changed, {row = v, text = table.concat(bits, "; ")})
		end
	end
	for k, v in pairs(oldRows) do
		if not newRows[k] then table.insert(removed, v) end
	end
	local function byPath(a, b) return a.path < b.path end
	table.sort(added, byPath); table.sort(removed, byPath)
	table.sort(changed, function(a, b) return a.row.path < b.row.path end)
	-- deplaces : meme type + meme nom de feuille (sans nombres), dossier different
	local remBy = {}
	for i, v in ipairs(removed) do
		local key = v.kind .. "|" .. leaf(v.path)
		if not leaf(v.path):find("#", 1, true) then remBy[key] = remBy[key] or {}; table.insert(remBy[key], i) end
	end
	local dropAdded, dropRemoved = {}, {}
	for i, v in ipairs(added) do
		local list = remBy[v.kind .. "|" .. leaf(v.path)]
		if list and #list > 0 and not leaf(v.path):find("#", 1, true) then
			local ri = table.remove(list, 1)
			table.insert(moved, {from = removed[ri], to = v})
			dropAdded[i] = true; dropRemoved[ri] = true
		end
	end
	local a2, r2 = {}, {}
	for i, v in ipairs(added) do if not dropAdded[i] then a2[#a2 + 1] = v end end
	for i, v in ipairs(removed) do if not dropRemoved[i] then r2[#r2 + 1] = v end end
	return {added = a2, removed = r2, moved = moved, changed = changed}
end

local function describe(v)
	return "[" .. v.kind .. "] " .. v.path .. (v.extra ~= "" and (" (" .. v.extra .. ")") or "")
end

-- lignes du rapport : {texte, couleur}
local COLORS = {
	add = Color3.fromRGB(90, 220, 140), del = Color3.fromRGB(255, 90, 90),
	mov = Color3.fromRGB(255, 200, 90), chg = Color3.fromRGB(255, 200, 90), info = Color3.fromRGB(255, 176, 176),
}

local function reportLines(d)
	local out = {}
	local function add(color, text) out[#out + 1] = {text = text, color = color} end
	for _, v in ipairs(d.removed) do add("del", "- " .. describe(v)) end
	for _, m in ipairs(d.moved) do add("mov", "> [" .. m.from.kind .. "] " .. m.from.path .. "  ->  " .. m.to.path) end
	for _, v in ipairs(d.added) do add("add", "+ " .. describe(v)) end
	for _, c in ipairs(d.changed) do add("chg", "~ [" .. c.row.kind .. "] " .. c.row.path .. " : " .. c.text) end
	return out
end

local function reportText(meta1, meta2, d, lines)
	local out = {
		"##### yslem Game Update v" .. VERSION .. " #####",
		"ancien : " .. tostring(meta1.GAME or "?") .. " (" .. tostring(meta1.DATE or "?") .. ")",
		"nouveau : " .. tostring(meta2.GAME or "?") .. " (" .. tostring(meta2.DATE or "?") .. ")",
		string.format("ajoutes %d  supprimes %d  deplaces %d  modifies %d", #d.added, #d.removed, #d.moved, #d.changed),
	}
	for _, l in ipairs(lines) do out[#out + 1] = l.text end
	return table.concat(out, "\n")
end

-------------------------------------------------------------------------------------------------- fichiers
local DIR = "yslem_gameupdate"
local haveFiles = typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"

local function path(name)
	if typeof(makefolder) == "function" and typeof(isfolder) == "function" then
		pcall(function() if not isfolder(DIR) then makefolder(DIR) end end)
		return DIR .. "/" .. name
	end
	return DIR .. "_" .. name
end

local function save(name, text)
	if not haveFiles then return false end
	return pcall(writefile, path(name), text)
end

local function loadFile(name)
	if not haveFiles then return nil end
	local ok, exists = pcall(isfile, path(name))
	if not ok or not exists then return nil end
	local ok2, text = pcall(readfile, path(name))
	return ok2 and text or nil
end

-------------------------------------------------------------------------------------------------- etat
local state = {snap = nil, report = nil, busy = false}
local GameUpdate = {Version = VERSION, snapshot = snapshot, parse = parse, diff = diff}

local ui = {}

local function setStatus(text, color)
	if ui.status then
		ui.status.Text = text
		ui.status.TextColor3 = color or COLORS.info
	end
end

local function showLines(lines)
	if not ui.list then return end
	for _, c in ipairs(ui.list:GetChildren()) do
		if c:IsA("TextLabel") then c:Destroy() end
	end
	if #lines == 0 then lines = {{text = "Rien n'a change depuis la reference.", color = "info"}} end
	for i, l in ipairs(lines) do
		if i > 400 then
			local more = Instance.new("TextLabel")
			more.BackgroundTransparency = 1; more.Size = UDim2.new(1, -8, 0, 16); more.LayoutOrder = i
			more.Font = Enum.Font.GothamMedium; more.TextSize = 11; more.TextXAlignment = Enum.TextXAlignment.Left
			more.TextColor3 = COLORS.info; more.Text = "... +" .. (#lines - 400) .. " autres (voir Copy)"
			more.Parent = ui.list
			break
		end
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1; t.Size = UDim2.new(1, -8, 0, 0); t.AutomaticSize = Enum.AutomaticSize.Y
		t.LayoutOrder = i; t.Font = Enum.Font.GothamMedium; t.TextSize = 11; t.TextWrapped = true
		t.TextXAlignment = Enum.TextXAlignment.Left; t.TextYAlignment = Enum.TextYAlignment.Top
		t.TextColor3 = COLORS[l.color] or COLORS.info; t.Text = l.text
		t.Parent = ui.list
	end
end

local function scan()
	if state.busy then return end
	state.busy = true
	setStatus("Analyse en cours...")
	local ok, err = pcall(function()
		local text, count = snapshot()
		local meta2, rows2 = parse(text)
		local pid = tostring(game.PlaceId)
		local baseText = loadFile(pid .. "_baseline.txt")
		state.snap = text
		save(pid .. "_latest.txt", text)
		save(pid .. "_" .. os.date("%Y-%m-%d_%H%M%S") .. ".txt", text)
		if not baseText then
			save(pid .. "_baseline.txt", text)
			state.report = "##### yslem Game Update v" .. VERSION .. " #####\nPremiere analyse : reference enregistree (" .. count .. " entrees)."
			showLines({{text = "Premiere analyse : reference enregistree (" .. count .. " entrees).", color = "add"}})
			setStatus("Reference creee. Relance Scan apres la prochaine mise a jour.", COLORS.add)
		else
			local meta1, rows1 = parse(baseText)
			local d = diff(rows1, rows2)
			local lines = reportLines(d)
			state.report = reportText(meta1, meta2, d, lines)
			showLines(lines)
			local total = #d.added + #d.removed + #d.moved + #d.changed
			setStatus(total == 0 and "Aucun changement." or string.format("+%d  -%d  >%d  ~%d", #d.added, #d.removed, #d.moved, #d.changed),
				total == 0 and COLORS.add or COLORS.mov)
		end
		GameUpdate.lastReport = state.report
		GameUpdate.lastSnapshot = state.snap
	end)
	if not ok then setStatus("Erreur : " .. tostring(err), COLORS.del) end
	state.busy = false
end

local function copyAll()
	if not state.snap then return end
	local text = (state.report or "") .. "\n\n===== INVENTAIRE COMPLET =====\n" .. state.snap
	local ok = typeof(setclipboard) == "function" and pcall(setclipboard, text)
	setStatus(ok and "Rapport + inventaire copies." or "Presse-papiers indisponible (fichiers dans " .. DIR .. ").", ok and COLORS.add or COLORS.mov)
end

local function setBaseline()
	if not state.snap then return end
	local ok = save(tostring(game.PlaceId) .. "_baseline.txt", state.snap)
	setStatus(ok and "Nouvelle reference enregistree." or "Impossible d'ecrire le fichier.", ok and COLORS.add or COLORS.del)
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
		if c.Name == "YslemGameUpdate" then c:Destroy() end
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "YslemGameUpdate"; gui.ResetOnSpawn = false; gui.DisplayOrder = 50
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

	local frame = Instance.new("Frame")
	frame.Name = "Window"; frame.Size = UDim2.fromOffset(340, 400)
	frame.Position = UDim2.new(0.5, -170, 0.5, -200)
	frame.BackgroundColor3 = Color3.fromRGB(5, 0, 0); frame.BorderSizePixel = 0; frame.Active = true
	frame.Parent = gui
	corner(frame, 14); stroke(frame, 1.6)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1; title.Position = UDim2.new(0, 14, 0, 8); title.Size = UDim2.new(1, -60, 0, 20)
	title.Font = Enum.Font.GothamBold; title.TextSize = 16; title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 255, 255); title.Text = "Game Update v" .. VERSION
	title.Parent = frame
	gradient(title, Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 200, 200))

	local gname = "?"
	pcall(function() gname = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name end)
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1; sub.Position = UDim2.new(0, 14, 0, 28); sub.Size = UDim2.new(1, -60, 0, 14)
	sub.Font = Enum.Font.GothamMedium; sub.TextSize = 10; sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextColor3 = Color3.fromRGB(150, 110, 110); sub.Text = tostring(gname) .. "  -  " .. tostring(game.PlaceId)
	sub.Parent = frame

	local close = Instance.new("TextButton")
	close.Size = UDim2.fromOffset(24, 24); close.Position = UDim2.new(1, -34, 0, 10)
	close.BackgroundColor3 = Color3.fromRGB(58, 20, 20); close.BorderSizePixel = 0; close.AutoButtonColor = false
	close.Font = Enum.Font.GothamBold; close.TextSize = 12; close.TextColor3 = Color3.fromRGB(255, 90, 90); close.Text = "X"
	close.Parent = frame
	corner(close, 8); stroke(close, 1)
	close.MouseButton1Click:Connect(function() if genv.YslemGameUpdateStop then genv.YslemGameUpdateStop() end end)
	ui.close = close

	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1; status.Position = UDim2.new(0, 14, 0, 48); status.Size = UDim2.new(1, -28, 0, 16)
	status.Font = Enum.Font.GothamBold; status.TextSize = 12; status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextColor3 = COLORS.info; status.Text = ""
	status.Parent = frame
	ui.status = status

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"; list.Position = UDim2.new(0, 10, 0, 70); list.Size = UDim2.new(1, -20, 1, -128)
	list.BackgroundColor3 = Color3.fromRGB(12, 2, 2); list.BorderSizePixel = 0; list.ScrollBarThickness = 3
	list.CanvasSize = UDim2.new(0, 0, 0, 0); list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = frame
	corner(list, 10)
	local layout = Instance.new("UIListLayout"); layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.Padding = UDim.new(0, 3); layout.Parent = list
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 8); pad.PaddingTop = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 4); pad.Parent = list
	ui.list = list

	local function button(text, x, w, fn)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, w, 0, 30); b.Position = UDim2.new(0, x, 1, -40)
		b.BackgroundColor3 = Color3.fromRGB(20, 4, 4); b.BorderSizePixel = 0; b.AutoButtonColor = false
		b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.TextColor3 = Color3.fromRGB(255, 255, 255); b.Text = text
		b.Parent = frame
		corner(b, 10); stroke(b, 1.2); gradient(b, Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 190, 190))
		b.MouseButton1Click:Connect(fn)
		return b
	end
	ui.scan = button("Scan", 10, 96, function() task.spawn(scan) end)
	ui.copy = button("Copy", 122, 96, copyAll)
	ui.baseline = button("Baseline", 234, 96, setBaseline)

	-- deplacement par l'en-tete
	local dragging, startPos, startInput
	table.insert(connections, frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if input.Position.Y - frame.AbsolutePosition.Y < 44 then
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

	-- degrade anime
	local t0 = os.clock()
	table.insert(connections, RunService.RenderStepped:Connect(function()
		local rot = ((os.clock() - t0) * 60) % 360
		for _, g in ipairs(grads) do
			if g.Parent then g.Rotation = rot end
		end
	end))
end

genv.YslemGameUpdateStop = function()
	for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
	table.clear(connections)
	if ui.gui then pcall(function() ui.gui:Destroy() end) end
	genv.YslemGameUpdateStop = nil
end
genv.YslemGameUpdate = GameUpdate

buildUI()
task.spawn(scan)

return GameUpdate
