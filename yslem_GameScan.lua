-- yslem GameScan : analyse a la demande, a integrer dans CHAQUE projet.
-- Colle le bloc entre les marqueurs START / END dans le script (il a besoin de
-- Players, ReplicatedStorage et Workspace, deja declares dans les projets) :
--   local report = GameScan.run()          -- texte complet (peut prendre 1-3 s)
--   GameScan.copy(report)                  -- presse-papier si l'executeur le permet
--   GameScan.copy(GameScan.snapshot())     -- "Game update" : inventaire complet et stable a comparer (tools/gamediff.py)
-- Il ne MODIFIE rien : il lit et decrit (contexte, securite, boutons, prompts,
-- remotes, monde, inventaire, scripts).

-- ==== yslem GameScan (START) ================================================
local GameScan = {}

do
	local Players_           = game:GetService("Players")
	local ReplicatedStorage_ = game:GetService("ReplicatedStorage")
	local Workspace_         = game:GetService("Workspace")
	local lp_                = Players_.LocalPlayer

	local MAX_YIELD = 1500 -- on rend la main tous les N elements (pas de gel)

	local function path(inst)
		local ok, p = pcall(function() return inst:GetFullName() end)
		return ok and p or tostring(inst)
	end

	local function walk(root, fn)
		local n = 0
		for _, d in ipairs(root:GetDescendants()) do
			fn(d)
			n = n + 1
			if n % MAX_YIELD == 0 then task.wait() end
		end
	end

	local function shown(obj)
		local p = obj
		while p and p:IsA("GuiObject") do
			if not p.Visible then return false end
			p = p.Parent
		end
		local sg = obj:FindFirstAncestorOfClass("ScreenGui")
		return sg == nil or sg.Enabled
	end

	local function addLines(out, title, lines, limit)
		table.insert(out, "== " .. title .. " (" .. #lines .. ") ==")
		for i, l in ipairs(lines) do
			if i > (limit or 40) then
				table.insert(out, "  ... +" .. (#lines - (limit or 40)) .. " autres")
				break
			end
			table.insert(out, "  " .. l)
		end
		if #lines == 0 then table.insert(out, "  (aucun)") end
	end

	-- 1) contexte -------------------------------------------------------------
	local function sectionContext(out)
		local lines = {}
		local name = "?"
		pcall(function()
			name = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
		end)
		table.insert(lines, "jeu: " .. tostring(name) .. "  PlaceId=" .. game.PlaceId .. "  GameId=" .. game.GameId)
		table.insert(lines, "serveur: " .. #Players_:GetPlayers() .. " joueurs  streaming=" .. tostring(Workspace_.StreamingEnabled))
		table.insert(lines, "joueur: " .. lp_.Name .. " (" .. lp_.UserId .. ")  age compte=" .. lp_.AccountAge .. "j")
		local ch = lp_.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hum then
			table.insert(lines, string.format("humanoid: vie %.0f/%.0f  vitesse %.1f  saut %.1f  etat=%s", hum.Health, hum.MaxHealth, hum.WalkSpeed, hum.UseJumpPower and hum.JumpPower or hum.JumpHeight, tostring(hum:GetState())))
		end
		if hrp then
			table.insert(lines, string.format("position: %.0f, %.0f, %.0f", hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
		end
		local caps = {}
		for _, fname in ipairs({"firesignal", "fireproximityprompt", "setclipboard", "gethui", "setfpscap", "getconnections", "hookfunction", "getgenv", "queue_on_teleport", "writefile", "readfile"}) do
			local okf, fv = pcall(function() return getfenv()[fname] end)
			table.insert(caps, fname .. "=" .. ((okf and type(fv) == "function") and "oui" or "non"))
		end
		pcall(function()
			game:GetService("VirtualInputManager")
			table.insert(caps, "VirtualInputManager=oui")
		end)
		table.insert(lines, "executeur: " .. table.concat(caps, " "))
		addLines(out, "CONTEXTE", lines, 20)
	end

	-- 2) securite : seulement des observations (noms suspects), rien n'est touche
	local SEC_WORDS = {"anticheat", "anti_cheat", "anti-cheat", "cheat", "exploit", "ban", "kick", "detect", "monitor", "security", "verify", "validate", "flag", "violation", "suspicious", "sanity", "integrity"}

	local function secName(n)
		n = n:lower()
		for _, w in ipairs(SEC_WORDS) do
			if n:find(w, 1, true) then return w end
		end
		return nil
	end

	local function sectionSecurity(out)
		local lines = {}
		local function scan(root, label)
			if not root then return end
			walk(root, function(d)
				if #lines >= 60 then return end
				local w = secName(d.Name)
				if w and (d:IsA("LuaSourceContainer") or d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("BindableEvent") or d:IsA("Folder") or d:IsA("ValueBase")) then
					table.insert(lines, label .. " [" .. d.ClassName .. "] " .. path(d) .. "  (mot: " .. w .. ")")
				end
			end)
		end
		scan(ReplicatedStorage_, "RS")
		scan(lp_:FindFirstChild("PlayerScripts"), "PlayerScripts")
		scan(lp_:FindFirstChild("PlayerGui"), "PlayerGui")
		scan(game:GetService("StarterPlayer"), "StarterPlayer")
		for _, c in ipairs(Workspace_:GetChildren()) do
			local w = secName(c.Name)
			if w then table.insert(lines, "Workspace [" .. c.ClassName .. "] " .. c.Name .. "  (mot: " .. w .. ")") end
		end
		-- attributs du joueur / personnage (minuteries, drapeaux)
		local attrs = {}
		for k, v in pairs(lp_:GetAttributes()) do table.insert(attrs, "joueur." .. k .. "=" .. tostring(v)) end
		if lp_.Character then
			for k, v in pairs(lp_.Character:GetAttributes()) do table.insert(attrs, "perso." .. k .. "=" .. tostring(v)) end
		end
		if #attrs > 0 then table.insert(lines, "attributs: " .. table.concat(attrs, ", ")) end
		addLines(out, "SECURITE (observations : noms evocateurs, rien n'est modifie)", lines, 60)
	end

	-- 3) boutons ---------------------------------------------------------------
	local function sectionButtons(out)
		local lines = {}
		local pg = lp_:FindFirstChild("PlayerGui")
		if pg then
			walk(pg, function(d)
				if #lines >= 80 then return end
				if (d:IsA("TextButton") or d:IsA("ImageButton")) and shown(d) and d.AbsoluteSize.X > 0 then
					local txt = ""
					if d:IsA("TextButton") then
						txt = d.Text
					else
						for _, c in ipairs(d:GetDescendants()) do
							if c:IsA("TextLabel") and c.Text ~= "" then txt = c.Text break end
						end
					end
					table.insert(lines, string.format("%s '%s' texte='%s' pos=(%.0f,%.0f) taille=(%.0f,%.0f) <%s>", d.ClassName, d.Name, txt, d.AbsolutePosition.X, d.AbsolutePosition.Y, d.AbsoluteSize.X, d.AbsoluteSize.Y, path(d)))
				end
			end)
		end
		addLines(out, "BOUTONS VISIBLES (PlayerGui)", lines, 50)
	end

	-- 4) prompts ---------------------------------------------------------------
	local function sectionPrompts(out)
		local groups, order = {}, {}
		local hrp = lp_.Character and lp_.Character:FindFirstChild("HumanoidRootPart")
		walk(Workspace_, function(d)
			if d:IsA("ProximityPrompt") then
				local key = (d.ActionText or "") .. " | " .. (d.ObjectText or "")
				local g = groups[key]
				if not g then
					g = {count = 0, near = math.huge, hold = d.HoldDuration, ex = path(d)}
					groups[key] = g
					table.insert(order, key)
				end
				g.count = g.count + 1
				local par = d.Parent
				if hrp and par then
					local pos = par:IsA("BasePart") and par.Position or (par:IsA("Model") and par:GetPivot().Position) or nil
					if pos then g.near = math.min(g.near, (pos - hrp.Position).Magnitude) end
				end
			end
		end)
		local lines = {}
		for _, key in ipairs(order) do
			local g = groups[key]
			table.insert(lines, string.format("'%s' x%d  maintien=%.1fs  plus proche=%s  ex: %s", key, g.count, g.hold, g.near == math.huge and "?" or string.format("%.0f", g.near), g.ex))
		end
		addLines(out, "PROMPTS (ActionText | ObjectText)", lines, 30)
	end

	-- 5) remotes ---------------------------------------------------------------
	local function sectionRemotes(out)
		local byParent, order = {}, {}
		walk(ReplicatedStorage_, function(d)
			if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") then
				local parent = path(d.Parent)
				if not byParent[parent] then byParent[parent] = {} table.insert(order, parent) end
				table.insert(byParent[parent], (d:IsA("RemoteFunction") and "RF:" or "RE:") .. d.Name)
			end
		end)
		local lines = {}
		for _, parent in ipairs(order) do
			table.insert(lines, parent .. " -> " .. table.concat(byParent[parent], ", "))
		end
		addLines(out, "REMOTES (ReplicatedStorage)", lines, 25)
	end

	-- 6) monde -----------------------------------------------------------------
	local function sectionWorld(out)
		local lines = {}
		for _, c in ipairs(Workspace_:GetChildren()) do
			if not c:IsA("Terrain") and not Players_:GetPlayerFromCharacter(c) and c ~= Workspace_.CurrentCamera then
				table.insert(lines, c.ClassName .. " '" .. c.Name .. "' (" .. #c:GetChildren() .. " enfants)")
			end
		end
		table.sort(lines)
		addLines(out, "MONDE (Workspace, premier niveau)", lines, 45)
	end

	-- 7) inventaire / stats -----------------------------------------------------
	local function sectionInventory(out)
		local lines = {}
		local bp = lp_:FindFirstChildOfClass("Backpack")
		if bp then
			local names = {}
			for _, t in ipairs(bp:GetChildren()) do table.insert(names, t.Name) end
			table.insert(lines, "sac: " .. (#names > 0 and table.concat(names, ", ") or "vide"))
		end
		if lp_.Character then
			for _, t in ipairs(lp_.Character:GetChildren()) do
				if t:IsA("Tool") then table.insert(lines, "en main: " .. t.Name) end
			end
		end
		local ls = lp_:FindFirstChild("leaderstats")
		if ls then
			for _, v in ipairs(ls:GetChildren()) do
				if v:IsA("ValueBase") then table.insert(lines, "stat " .. v.Name .. " = " .. tostring(v.Value)) end
			end
		end
		addLines(out, "INVENTAIRE / STATS", lines, 25)
	end

	-- 8) scripts ---------------------------------------------------------------
	local function sectionScripts(out)
		local lines = {}
		local function count(root, label)
			if not root then return end
			local scripts, modules = 0, 0
			local sample = {}
			walk(root, function(d)
				if d:IsA("LocalScript") then
					scripts = scripts + 1
					if #sample < 12 then table.insert(sample, d.Name) end
				elseif d:IsA("ModuleScript") then
					modules = modules + 1
					if #sample < 12 then table.insert(sample, d.Name) end
				end
			end)
			table.insert(lines, label .. ": " .. scripts .. " LocalScript, " .. modules .. " ModuleScript  (" .. table.concat(sample, ", ") .. ")")
		end
		count(lp_:FindFirstChild("PlayerScripts"), "PlayerScripts")
		count(ReplicatedStorage_, "ReplicatedStorage")
		count(lp_:FindFirstChild("PlayerGui"), "PlayerGui")
		addLines(out, "SCRIPTS", lines, 10)
	end

	-- rapport complet ---------------------------------------------------------
	function GameScan.run(sections)
		sections = sections or {}
		local out = {"##### yslem GameScan " .. os.date("%Y-%m-%d %H:%M:%S") .. " #####"}
		local steps = {
			{"context", sectionContext}, {"security", sectionSecurity}, {"buttons", sectionButtons},
			{"prompts", sectionPrompts}, {"remotes", sectionRemotes}, {"world", sectionWorld},
			{"inventory", sectionInventory}, {"scripts", sectionScripts},
		}
		for _, step in ipairs(steps) do
			if sections[step[1]] ~= false then
				local ok, err = pcall(step[2], out)
				if not ok then table.insert(out, "== " .. step[1] .. " : erreur " .. tostring(err)) end
			end
		end
		return table.concat(out, "\n")
	end

	-- Recherche ciblee : tout ce qui contient un mot (boutons/textes d'interface,
	-- remotes, prompts, objets du monde). Exemple : GameScan.find("drop").
	function GameScan.find(keyword)
		keyword = tostring(keyword or ""):lower()
		local out = {"##### yslem GameScan.find '" .. keyword .. "' #####"}
		local function check(label, root)
			if not root then return end
			walk(root, function(d)
				if #out > 80 then return end
				local hit = d.Name:lower():find(keyword, 1, true)
				if not hit and (d:IsA("TextLabel") or d:IsA("TextButton")) then hit = (d.Text or ""):lower():find(keyword, 1, true) end
				if not hit and d:IsA("ProximityPrompt") then hit = ((d.ActionText or "") .. (d.ObjectText or "")):lower():find(keyword, 1, true) end
				if hit then
					local extra = ""
					if d:IsA("TextLabel") or d:IsA("TextButton") then extra = " texte='" .. d.Text .. "'" end
					if d:IsA("ProximityPrompt") then extra = " action='" .. d.ActionText .. "' objet='" .. d.ObjectText .. "'" end
					table.insert(out, label .. " [" .. d.ClassName .. "]" .. extra .. " <" .. path(d) .. ">")
				end
			end)
		end
		check("GUI", lp_:FindFirstChild("PlayerGui"))
		check("RS", ReplicatedStorage_)
		check("WS", Workspace_)
		if #out == 1 then table.insert(out, "(rien trouve)") end
		return table.concat(out, "\n")
	end

	-- Game update : inventaire COMPLET et STABLE (pas de limite, pas de valeurs qui bougent) a comparer avec un
	-- inventaire plus ancien (python3 tools/gamediff.py ancien.txt nouveau.txt). Une ligne = KIND|classe|chemin|extra|n
	-- (les noms avec identifiants/nombres sont normalises, les doublons regroupes dans n).
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

	function GameScan.snapshot()
		local counts, order = {}, {}
		local function add(kind, class, p, extra)
			local key = kind .. "|" .. class .. "|" .. p .. "|" .. (extra or "")
			if counts[key] then counts[key] = counts[key] + 1 else counts[key] = 1; table.insert(order, key) end
		end
		local name = "?"
		pcall(function() name = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name end)
		local pgui = lp_:FindFirstChild("PlayerGui")
		local pscripts = lp_:FindFirstChild("PlayerScripts")

		-- remotes / bindables / scripts de ReplicatedStorage et ReplicatedFirst
		for _, pair in ipairs({{ReplicatedStorage_, "RS"}, {game:GetService("ReplicatedFirst"), "RF"}}) do
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
		-- interface : boutons (nom + texte), tous les ecrans
		if pgui then
			for _, sg in ipairs(pgui:GetChildren()) do
				add("SCREEN", sg.ClassName, "GUI/" .. norm(sg.Name))
			end
			walk(pgui, function(d)
				if d:IsA("TextButton") or d:IsA("ImageButton") then
					local t = d:IsA("TextButton") and norm(d.Text) or ""
					add("BUTTON", d.ClassName, rel(d, pgui, "GUI"), t)
				end
			end)
		end
		-- monde : 3 niveaux sous Workspace (sans les personnages des joueurs), prompts et remotes partout
		local Players = Players_
		local function skip(inst)
			return inst:IsA("Model") and Players:GetPlayerFromCharacter(inst) ~= nil
		end
		local function level(parent, depth)
			for _, c in ipairs(parent:GetChildren()) do
				if not skip(c) then
					add("WORLD", c.ClassName, rel(c, Workspace_, "WS"))
					if depth < 3 then level(c, depth + 1) end
				end
			end
		end
		pcall(level, Workspace_, 1)
		walk(Workspace_, function(d)
			if d:IsA("ProximityPrompt") then
				add("PROMPT", "ProximityPrompt", rel(d, Workspace_, "WS"), norm(d.ActionText) .. " / " .. norm(d.ObjectText) .. " / hold=" .. tostring(d.HoldDuration))
			elseif d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
				add("REMOTE", d.ClassName, rel(d, Workspace_, "WS"))
			end
		end)
		-- stats et attributs (noms seulement)
		local ls = lp_:FindFirstChild("leaderstats")
		if ls then
			for _, v in ipairs(ls:GetChildren()) do add("STAT", v.ClassName, "leaderstats/" .. norm(v.Name)) end
		end
		for k in pairs(lp_:GetAttributes()) do add("ATTR", "Player", "player/" .. norm(k)) end
		local ch = lp_.Character
		if ch then
			for k in pairs(ch:GetAttributes()) do add("ATTR", "Character", "character/" .. norm(k)) end
		end

		table.sort(order)
		local out = {
			"#SNAPSHOT v1",
			"#GAME " .. tostring(name) .. " PlaceId=" .. tostring(game.PlaceId) .. " GameId=" .. tostring(game.GameId),
			"#DATE " .. os.date("%Y-%m-%d %H:%M:%S"),
		}
		for _, key in ipairs(order) do table.insert(out, key .. "|" .. counts[key]) end
		return table.concat(out, "\n")
	end

	function GameScan.save(text, fileName)
		fileName = fileName or ("yslem_snapshot_" .. tostring(game.PlaceId) .. ".txt")
		local ok = pcall(function() writefile(fileName, text) end)
		return ok, fileName
	end

	function GameScan.copy(text)
		local ok = pcall(function() setclipboard(text) end)
		return ok
	end
end
-- ==== yslem GameScan (END) ==================================================

return GameScan
