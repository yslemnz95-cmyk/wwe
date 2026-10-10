-- yslem Game Update v2 (UN fichier). Execute-le dans le jeu :
--   1 Scan       : il analyse le jeu (se lance tout seul) et compare avec la reference enregistree
--   2 Changements: badges NOUVEAU / SUPPRIME / DEPLACE / MODIFIE (touche un badge pour filtrer)
--   3 Copier     : copie le rapport + l'inventaire complet, a coller dans le chat
-- "Nouvelle ref." = le jeu actuel devient la reference (a faire quand tout est adapte).
-- Il ne modifie rien dans le jeu : il lit des noms et ecrit 3 petits fichiers texte. Aucun reseau.

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
	name = name:gsub("%x%x%x%x%x%x%x%x+", "<id>")
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
	-- monde : on ne descend pas dans les objets a identifiant (oeufs, pets rendus...) ni dans les dossiers de plus de 40 enfants
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
		"#SNAPSHOT v2",
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

-- ces categories bougent tout le temps (oeufs, pets, boutons generes) : un simple changement de nombre n'est pas une mise a jour
local DYNAMIC = {WORLD = true, PROMPT = true, BUTTON = true}

local function diff(oldRows, newRows)
	local added, removed, changed, moved = {}, {}, {}, {}
	for k, v in pairs(newRows) do
		local o = oldRows[k]
		if not o then
			table.insert(added, v)
		elseif o.class ~= v.class or o.extra ~= v.extra or (o.n ~= v.n and not DYNAMIC[v.kind]) then
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

-- categories : add (nouveau), del (supprime), mov (deplace), chg (modifie)
local COLORS = {
	add = Color3.fromRGB(90, 220, 140), del = Color3.fromRGB(255, 90, 90),
	mov = Color3.fromRGB(255, 200, 90), chg = Color3.fromRGB(120, 180, 255), info = Color3.fromRGB(255, 176, 176),
	dim = Color3.fromRGB(150, 110, 110),
}
local CATS = {
	{id = "add", label = "NOUVEAU"}, {id = "del", label = "SUPPRIME"},
	{id = "mov", label = "DEPLACE"}, {id = "chg", label = "MODIFIE"},
}
local KINDS = {REMOTE = "Remote", SCRIPT = "Script", SCREEN = "Ecran", BUTTON = "Bouton", PROMPT = "Prompt", WORLD = "Objet", STAT = "Stat", ATTR = "Attribut"}

-- un element = {cat, title (court), sub (detail), text (ligne du rapport copie)}
local function items(d)
	local out = {}
	local function add(cat, v, sub, text)
		out[#out + 1] = {cat = cat, title = (KINDS[v.kind] or v.kind) .. " : " .. leaf(v.path), sub = sub, text = text}
	end
	for _, v in ipairs(d.removed) do add("del", v, v.path, "- " .. describe(v)) end
	for _, m in ipairs(d.moved) do add("mov", m.from, m.from.path .. "  ->  " .. m.to.path, "> [" .. m.from.kind .. "] " .. m.from.path .. "  ->  " .. m.to.path) end
	for _, v in ipairs(d.added) do add("add", v, v.path .. (v.extra ~= "" and ("  (" .. v.extra .. ")") or ""), "+ " .. describe(v)) end
	for _, c in ipairs(d.changed) do add("chg", c.row, c.text, "~ [" .. c.row.kind .. "] " .. c.row.path .. " : " .. c.text) end
	return out
end

local function reportText(meta1, meta2, d, list)
	local out = {
		"##### yslem Game Update v" .. VERSION .. " #####",
		"ancien : " .. tostring(meta1.GAME or "?") .. " (" .. tostring(meta1.DATE or "?") .. ")",
		"nouveau : " .. tostring(meta2.GAME or "?") .. " (" .. tostring(meta2.DATE or "?") .. ")",
		string.format("ajoutes %d  supprimes %d  deplaces %d  modifies %d", #d.added, #d.removed, #d.moved, #d.changed),
	}
	for _, l in ipairs(list) do out[#out + 1] = l.text end
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
local state = {snap = nil, report = nil, busy = false, items = {}, filter = nil, step = 1}
local GameUpdate = {Version = VERSION, snapshot = snapshot, parse = parse, diff = diff}

local ui = {}

local function setStatus(text, color)
	if ui.status then
		ui.status.Text = text
		ui.status.TextColor3 = color or COLORS.info
	end
end

-- etapes : 1 Scan, 2 Changements, 3 Copier (rond plein = en cours, coche = fait)
local function setStep(n)
	state.step = n
	for i, b in ipairs(ui.steps or {}) do
		local done, current = i < n, i == n
		b.num.Text = done and "OK" or tostring(i)
		b.num.BackgroundColor3 = done and COLORS.add or (current and Color3.fromRGB(220, 40, 40) or Color3.fromRGB(40, 14, 14))
		b.num.TextColor3 = (done or current) and Color3.fromRGB(20, 0, 0) or COLORS.dim
		b.label.TextColor3 = (done or current) and Color3.fromRGB(255, 255, 255) or COLORS.dim
	end
end

local function setChips(counts)
	for _, c in ipairs(ui.chips or {}) do
		local n = counts and counts[c.id] or 0
		c.btn.Text = c.label .. "  " .. n
		c.btn.TextColor3 = n > 0 and COLORS[c.id] or COLORS.dim
		c.stroke.Transparency = (state.filter == c.id) and 0 or (n > 0 and 0.45 or 0.8)
	end
end

local function showItems()
	if not ui.list then return end
	for _, c in ipairs(ui.list:GetChildren()) do
		if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end
	end
	local shown = 0
	for _, it in ipairs(state.items) do
		if not state.filter or it.cat == state.filter then
			shown += 1
			if shown > 300 then break end
			local row = Instance.new("Frame")
			row.BackgroundColor3 = Color3.fromRGB(20, 4, 4); row.BorderSizePixel = 0
			row.Size = UDim2.new(1, -8, 0, 0); row.AutomaticSize = Enum.AutomaticSize.Y; row.LayoutOrder = shown
			row.Parent = ui.list
			local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 8); rc.Parent = row
			local lay = Instance.new("UIListLayout"); lay.SortOrder = Enum.SortOrder.LayoutOrder; lay.Parent = row
			local pd = Instance.new("UIPadding"); pd.PaddingLeft = UDim.new(0, 10); pd.PaddingTop = UDim.new(0, 4); pd.PaddingBottom = UDim.new(0, 5); pd.PaddingRight = UDim.new(0, 6); pd.Parent = row
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1; t.Size = UDim2.new(1, 0, 0, 15); t.LayoutOrder = 1
			t.Font = Enum.Font.GothamBold; t.TextSize = 12; t.TextXAlignment = Enum.TextXAlignment.Left
			t.TextColor3 = COLORS[it.cat]; t.Text = it.title; t.TextTruncate = Enum.TextTruncate.AtEnd
			t.Parent = row
			local sub = Instance.new("TextLabel")
			sub.BackgroundTransparency = 1; sub.Size = UDim2.new(1, 0, 0, 0); sub.AutomaticSize = Enum.AutomaticSize.Y; sub.LayoutOrder = 2
			sub.Font = Enum.Font.GothamMedium; sub.TextSize = 10; sub.TextWrapped = true; sub.TextXAlignment = Enum.TextXAlignment.Left
			sub.TextYAlignment = Enum.TextYAlignment.Top; sub.TextColor3 = COLORS.dim; sub.Text = it.sub
			sub.Parent = row
		end
	end
	if shown == 0 then
		local e = Instance.new("TextLabel")
		e.BackgroundTransparency = 1; e.Size = UDim2.new(1, -8, 0, 40); e.Font = Enum.Font.GothamMedium; e.TextSize = 12
		e.TextWrapped = true; e.TextXAlignment = Enum.TextXAlignment.Left; e.TextColor3 = COLORS.info
		e.Text = ui.emptyText or "Rien a afficher."
		e.Parent = ui.list
	end
end

local function scan()
	if state.busy then return end
	state.busy = true
	setStep(1)
	setStatus("Etape 1 : analyse du jeu...")
	local ok, err = pcall(function()
		local text, count = snapshot()
		local meta2, rows2 = parse(text)
		local pid = tostring(game.PlaceId)
		local baseText = loadFile(pid .. "_baseline.txt")
		state.snap = text
		state.filter = nil
		save(pid .. "_latest.txt", text)
		save(pid .. "_" .. os.date("%Y-%m-%d_%H%M%S") .. ".txt", text)
		local oldFormat = false
		if baseText then
			local bm = parse(baseText)
			oldFormat = bm.SNAPSHOT ~= "v2"
		end
		if not baseText or oldFormat then
			save(pid .. "_baseline.txt", text)
			state.items = {}
			state.report = "##### yslem Game Update v" .. VERSION .. " #####\nPremiere analyse : reference enregistree (" .. count .. " entrees)."
			ui.emptyText = (oldFormat and "Ancienne reference remplacee (nouveau format, plus propre). " or "") .. "Reference enregistree (" .. count .. " elements).\nApres la prochaine mise a jour du jeu, relance ce script : je te montre ce qui a change."
			setChips(nil)
			showItems()
			setStatus("Reference creee.", COLORS.add)
			setStep(3)
		else
			local meta1, rows1 = parse(baseText)
			local d = diff(rows1, rows2)
			state.items = items(d)
			state.report = reportText(meta1, meta2, d, state.items)
			local total = #state.items
			ui.emptyText = "Rien n'a change depuis la reference."
			setChips({add = #d.added, del = #d.removed, mov = #d.moved, chg = #d.changed})
			showItems()
			setStatus(total == 0 and "Aucun changement." or (total .. " changement" .. (total > 1 and "s" or "") .. " - touche un badge pour filtrer"), total == 0 and COLORS.add or COLORS.mov)
			setStep(2)
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
	setStatus(ok and "Copie : colle-le dans le chat." or "Presse-papiers indisponible (fichiers dans " .. DIR .. ").", ok and COLORS.add or COLORS.mov)
	if ok then setStep(3) end
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
	local function stroke(inst, th, color)
		local s = Instance.new("UIStroke"); s.Thickness = th; s.Color = color or Color3.fromRGB(255, 255, 255)
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = inst
		if not color then gradient(s, Color3.fromRGB(70, 10, 10), Color3.fromRGB(255, 90, 90)) end
		return s
	end
	local function label(parentInst, text, x, y, w, h, size, font, color)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1; l.Position = UDim2.new(0, x, 0, y); l.Size = UDim2.new(0, w, 0, h)
		l.Font = font or Enum.Font.GothamMedium; l.TextSize = size or 12; l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = color or Color3.fromRGB(255, 255, 255); l.Text = text
		l.Parent = parentInst
		return l
	end

	local frame = Instance.new("Frame")
	frame.Name = "Window"; frame.Size = UDim2.fromOffset(340, 420)
	frame.Position = UDim2.new(0.5, -170, 0.5, -210)
	frame.BackgroundColor3 = Color3.fromRGB(5, 0, 0); frame.BorderSizePixel = 0; frame.Active = true
	frame.Parent = gui
	corner(frame, 14); stroke(frame, 1.6)

	local title = label(frame, "Game Update v" .. VERSION, 14, 8, 240, 20, 16, Enum.Font.GothamBold)
	gradient(title, Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 200, 200))
	local gname = "?"
	pcall(function() gname = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name end)
	label(frame, tostring(gname), 14, 28, 250, 14, 10, nil, COLORS.dim)

	local close = Instance.new("TextButton")
	close.Size = UDim2.fromOffset(24, 24); close.Position = UDim2.new(1, -34, 0, 10)
	close.BackgroundColor3 = Color3.fromRGB(58, 20, 20); close.BorderSizePixel = 0; close.AutoButtonColor = false
	close.Font = Enum.Font.GothamBold; close.TextSize = 12; close.TextColor3 = Color3.fromRGB(255, 90, 90); close.Text = "X"
	close.Parent = frame
	corner(close, 8); stroke(close, 1)
	close.MouseButton1Click:Connect(function() if genv.YslemGameUpdateStop then genv.YslemGameUpdateStop() end end)
	ui.close = close

	-- 3 etapes en badges
	ui.steps = {}
	local stepNames = {"Scan", "Changements", "Copier"}
	for i, name in ipairs(stepNames) do
		local x = 12 + (i - 1) * 108
		local num = Instance.new("TextLabel")
		num.Size = UDim2.fromOffset(22, 22); num.Position = UDim2.new(0, x, 0, 50)
		num.BackgroundColor3 = Color3.fromRGB(40, 14, 14); num.BorderSizePixel = 0
		num.Font = Enum.Font.GothamBold; num.TextSize = 10; num.TextColor3 = COLORS.dim; num.Text = tostring(i)
		num.Parent = frame
		corner(num, 11)
		local lab = label(frame, name, x + 27, 50, 78, 22, 11, Enum.Font.GothamBold, COLORS.dim)
		ui.steps[i] = {num = num, label = lab}
	end

	-- badges de categories (touche = filtre)
	ui.chips = {}
	for i, cat in ipairs(CATS) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, 76, 0, 24); b.Position = UDim2.new(0, 10 + (i - 1) * 80, 0, 80)
		b.BackgroundColor3 = Color3.fromRGB(20, 4, 4); b.BorderSizePixel = 0; b.AutoButtonColor = false
		b.Font = Enum.Font.GothamBold; b.TextSize = 9; b.TextColor3 = COLORS.dim; b.Text = cat.label .. "  0"
		b.Parent = frame
		corner(b, 12)
		local st = stroke(b, 1.2, COLORS[cat.id])
		st.Transparency = 0.8
		b.MouseButton1Click:Connect(function()
			state.filter = (state.filter ~= cat.id) and cat.id or nil
			local counts = {}
			for _, it in ipairs(state.items) do counts[it.cat] = (counts[it.cat] or 0) + 1 end
			setChips(counts)
			showItems()
		end)
		ui.chips[i] = {id = cat.id, label = cat.label, btn = b, stroke = st}
	end

	local status = label(frame, "", 14, 110, 312, 16, 11, Enum.Font.GothamBold, COLORS.info)
	ui.status = status

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"; list.Position = UDim2.new(0, 10, 0, 130); list.Size = UDim2.new(1, -20, 1, -182)
	list.BackgroundColor3 = Color3.fromRGB(12, 2, 2); list.BorderSizePixel = 0; list.ScrollBarThickness = 3
	list.CanvasSize = UDim2.new(0, 0, 0, 0); list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = frame
	corner(list, 10)
	local layout = Instance.new("UIListLayout"); layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.Padding = UDim.new(0, 4); layout.Parent = list
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 6); pad.PaddingTop = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 4); pad.Parent = list
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
	ui.scan = button("1  Scan", 10, 96, function() task.spawn(scan) end)
	ui.copy = button("3  Copier", 114, 96, copyAll)
	ui.baseline = button("Nouvelle ref.", 218, 112, setBaseline)

	setStep(1)
	setChips(nil)

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
