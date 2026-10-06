-- yslempet_EggTP.lua  (standalone, ultra-compact, theme noir)
-- "Ride a Pet" - Teleportation vers les oeufs de la map
-- PlaceId: 124216119978534
--
-- Carrousel : uniquement les oeufs ramassables presents sur la MAP
-- (Workspace.RenderedEggs, prompt "Pick Up") - jamais les oeufs du Ranch.
-- Swipe/fleches pour parcourir un par un, OU le bouton "v" pour ouvrir une
-- liste et sauter directement sur l'oeuf voulu (evite de tourner longtemps).
-- Toucher la carte / RAMASSER : deplacement -> ramassage -> retour au Ranch
-- (optionnel, bouton "Auto"). Bouton RANCH separe pour y retourner quand on
-- veut. Bouton "-" pour reduire completement l'UI.
--
-- Deux methodes de deplacement au choix (bouton TP/VOL) :
--   - TP   : teleportation instantanee en desync (hors du tick principal),
--            vitesse annulee puis reconfirmee sur quelques frames.
--   - VOL  : deplacement par velocite (AssemblyLinearVelocity sur son
--            propre personnage uniquement) + noclip pendant le trajet pour
--            ne jamais rester bloque sur le terrain, vitesse elevee.
--
-- Le retour au Ranch cible STRICTEMENT le plot appartenant a l'utilisateur
-- (verification proprietaire) : jamais le plot d'un autre joueur, meme s'il
-- est plus proche.
--
-- La liste se rafraichit toute seule en continu (pas de bouton "Scan") pour
-- suivre le renouvellement des oeufs sur la map.
--
-- Icone affichee : image reelle deja utilisee par le jeu si une
-- correspondance EXACTE de nom est trouvee, sinon rendu 3D du vrai modele
-- de l'oeuf (jamais d'icone approximative/fausse).

-- === services ===============================================================
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local ws                = game:GetService("Workspace")

local lp   = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local hrp  = char and char:FindFirstChild("HumanoidRootPart")
if not hrp then
	hrp = char and char:WaitForChild("HumanoidRootPart", 10)
end
if not hrp then return end

-- === helpers position ========================================================

local function getPos(inst)
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Model") then
		if inst.PrimaryPart then return inst.PrimaryPart.Position end
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then return d.Position end
		end
	end
	if inst:IsA("Folder") then
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then return d.Position end
		end
	end
	return nil
end

local function nearest(list)
	local myChar = lp.Character
	local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if not myHrp then return list[1] end
	local best, bestDist = nil, math.huge
	for _, e in ipairs(list) do
		if e.pos then
			local d = (myHrp.Position - e.pos).Magnitude
			if d < bestDist then bestDist = d; best = e end
		end
	end
	return best or list[1]
end

-- Pose le personnage a une position (vitesses annulees) : sert a se replacer
-- sur un oeuf pour le ramasser / reprendre.
local function place(position)
	local h = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	if not h or not position then return end
	h.CFrame = CFrame.new(position)
	h.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
	h.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
end

-- Annule le deplacement (tp ou vol) en cours - pilote par le bouton STOP.
local cancelMove = false

-- === methode 1 : tp desync ===================================================
-- Ecriture CFrame hors du tick principal (contourne la validation de
-- mouvement serveur qui tourne sur le thread synchronise). La vitesse est
-- annulee pour eviter tout rebond, puis le tp est reconfirme sur quelques
-- frames si une correction serveur nous renvoie ailleurs.

local function tpTo(pos)
	local myChar = lp.Character
	local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if not myHrp or not pos then return end
	local target = CFrame.new(pos + Vector3.new(0, 5, 0))

	local function apply()
		myHrp.CFrame                  = target
		myHrp.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
		myHrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end

	local ok = pcall(function()
		task.desynchronize()
		apply()
		task.synchronize()
	end)
	if not ok then apply() end

	for _ = 1, 3 do
		task.wait()
		if cancelMove then break end
		if not (myHrp and myHrp.Parent) then break end
		if (myHrp.Position - target.Position).Magnitude > 6 then
			local ok2 = pcall(function()
				task.desynchronize()
				apply()
				task.synchronize()
			end)
			if not ok2 then apply() end
		end
	end
end

-- === methode 2 : vol par velocite + noclip ===================================
-- AssemblyLinearVelocity applique uniquement sur son propre personnage
-- (jamais sur un autre joueur). Noclip actif pendant le trajet pour ne
-- jamais rester coince sur le decor a haute vitesse.

local FLY_SPEED    = 600
local FLY_ARRIVE_D = 4

-- Les valeurs CanCollide d'origine sont memorisees : au retour a la normale on
-- les restaure EXACTEMENT (mettre tout a true bloquait les membres/accessoires
-- dans le sol et empechait d'avancer apres un trajet).
local savedCollide = {}

local function setNoclip(state)
	local myChar = lp.Character
	if not myChar then return end
	if state then
		for _, d in ipairs(myChar:GetDescendants()) do
			if d:IsA("BasePart") then
				if savedCollide[d] == nil then savedCollide[d] = d.CanCollide end
				d.CanCollide = false
			end
		end
	else
		for part, original in pairs(savedCollide) do
			if part and part.Parent then
				part.CanCollide = original
			end
		end
		savedCollide = {}
	end
end

local function flyTo(pos)
	local myChar = lp.Character
	local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if not myHrp or not pos then return end
	local hum = myChar:FindFirstChildOfClass("Humanoid")
	local target = pos + Vector3.new(0, 5, 0)

	if hum then hum.PlatformStand = true end

	pcall(function()
		while myHrp and myHrp.Parent do
			if cancelMove then
				myHrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
				break
			end
			setNoclip(true)
			local diff = target - myHrp.Position
			local dist = diff.Magnitude
			if dist < FLY_ARRIVE_D then
				myHrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
				break
			end
			myHrp.AssemblyLinearVelocity = diff.Unit * math.min(dist * 4 + 50, FLY_SPEED)
			task.wait()
		end
	end)

	setNoclip(false)
	-- on ne rend JAMAIS un personnage fige : PlatformStand toujours remis a faux
	if hum then hum.PlatformStand = false end
end

-- === choix de methode (option utilisateur) ==================================

local tpMethod = "tp" -- "tp" (desync) ou "fly" (velocity + noclip)

local function methodLabel()
	return tpMethod == "fly" and "VOL" or "TP"
end

-- Rend la main au joueur apres un deplacement : plus de noclip, plus de
-- PlatformStand, vitesse nulle, etat de marche retabli (un tp peut laisser
-- l'humanoid en etat Physics/Ragdoll/FallingDown, sans controle).
local function restoreControl()
	setNoclip(false)
	local myChar = lp.Character
	local hum = myChar and myChar:FindFirstChildOfClass("Humanoid")
	local hrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if hum then
		hum.PlatformStand = false
		pcall(function() hum:Move(Vector3.new(0, 0, 0), false) end)
		local st = hum:GetState()
		if st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.Ragdoll or st == Enum.HumanoidStateType.FallingDown or st == Enum.HumanoidStateType.PlatformStanding then
			pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
		end
	end
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end
end

local function moveTo(pos)
	-- le drapeau d'arret n'est PAS remis a zero ici : il l'est seulement au debut
	-- d'un nouveau trajet (sinon un appui sur STOP etait efface par le deplacement suivant)
	if tpMethod == "fly" then
		flyTo(pos)
	else
		tpTo(pos)
	end
	restoreControl()
end

local function stopMove()
	cancelMove = true
	-- rend tout de suite la main au joueur (noclip / PlatformStand / vitesse)
	task.defer(restoreControl)
end

local function tryFire(prompt)
	if not prompt or not prompt.Parent then return end
	pcall(function() fireproximityprompt(prompt) end)
end

local function findPrompt(inst, actionText)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			if actionText == nil or d.ActionText == actionText then
				return d
			end
		end
	end
	return nil
end

-- === scan : uniquement les oeufs ramassables de la map ======================

local function collectEggs()
	local byName = {}
	local rendered = ws:FindFirstChild("RenderedEggs")
	if rendered then
		for _, egg in ipairs(rendered:GetChildren()) do
			local pos = getPos(egg)
			local prompt = findPrompt(egg, "Pick Up")
			if not byName[egg.Name] then byName[egg.Name] = {} end
			table.insert(byName[egg.Name], {inst = egg, prompt = prompt, pos = pos})
		end
	end
	return byName
end

-- === Ranch du joueur : ciblage direct, sans supposer de structure fixe ====
-- Deux methodes essayees dans l'ordre :
--   1) un Model/Folder quelque part dans Workspace nomme exactement comme
--      le joueur (pseudo ou UserId) - tres courant : le plot est souvent
--      son propre conteneur nomme par son proprietaire.
--   2) une pancarte (TextLabel/TextButton) affichant "Your Ranch"/"My Plot"
--      (ou l'equivalent FR) ou le pseudo exact du joueur.
-- Jamais de repli "plot le plus proche" : mieux vaut echouer que de viser
-- le ranch d'un autre joueur. Si rien n'est trouve, un diagnostic est
-- imprime dans la console (F9) pour ajuster la recherche.

local function isAnyCharacter(inst)
	for _, plr in ipairs(Players:GetPlayers()) do
		if inst == plr.Character then return true end
	end
	return inst:FindFirstChildOfClass("Humanoid") ~= nil
end

local function findRanchPosUncached()
	local myName    = lp.Name:lower()
	local myDisplay = (lp.DisplayName ~= "" and lp.DisplayName:lower() ~= myName) and lp.DisplayName:lower() or nil
	local myUserId  = tostring(lp.UserId)

	-- 1) instance nommee directement par le pseudo/UserId du joueur, en
	-- excluant explicitement les personnages (le sien inclus : son propre
	-- Model dans Workspace porte deja son pseudo comme nom).
	for _, d in ipairs(ws:GetDescendants()) do
		if (d:IsA("Model") or d:IsA("Folder")) and not isAnyCharacter(d) then
			local n = d.Name:lower()
			if n == myName or d.Name == myUserId or (myDisplay and n == myDisplay) then
				local pos = getPos(d)
				if pos then
					warn("[EggTP] Ranch cible (nom d'instance) : " .. d:GetFullName()) return pos, d
				end
			end
		end
	end

	-- 2) pancarte "Your Ranch" / "My Plot" (FR/EN) ou pseudo, cherchee dans
	-- Workspace ET PlayerGui (le texte peut etre un overlay 2D projete sur
	-- la position 3D plutot qu'un vrai BillboardGui).
	local function textMatches(text)
		local t = text:lower()
		if t:find("your ranch", 1, true) or t:find("ton ranch", 1, true) or t:find("mon ranch", 1, true) then
			return true
		end
		if t:find("my plot", 1, true) or t:find("ton plot", 1, true) or t:find("mon plot", 1, true) then
			return true
		end
		if t:find(myName, 1, true) then return true end
		if myDisplay and t:find(myDisplay, 1, true) then return true end
		return false
	end

	local function posFromAncestors(inst, stopAt)
		local p = inst
		while p and p ~= stopAt do
			if p:IsA("BasePart") then return p.Position, p end
			if p:IsA("BillboardGui") and p.Adornee then
				local pos = getPos(p.Adornee) if pos then return pos, p.Adornee end
			end
			if p:IsA("Model") then local pos = getPos(p) if pos then return pos, p end end
			p = p.Parent
		end
		return nil
	end

	local diagText = {}
	local diagName = {}

	local function scanRoot(root)
		for _, d in ipairs(root:GetDescendants()) do
			local isSelf = lp.Character and d:IsDescendantOf(lp.Character)
			if not isSelf then
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text and #d.Text > 0 and #d.Text < 80 then
					if textMatches(d.Text) then
						local pos, owner = posFromAncestors(d.Parent, root) if pos then
							warn("[EggTP] Ranch cible (pancarte '" .. d.Text .. "') : " .. d:GetFullName()) return pos, owner
						end
					end
					local lt = d.Text:lower()
					if lt:find("ranch", 1, true) or lt:find("plot", 1, true) then
						table.insert(diagText, d.Text .. "  <" .. d:GetFullName() .. ">")
					end
				end
				if not isAnyCharacter(d) then
					local dn = d.Name:lower()
					if dn:find("ranch", 1, true) or dn:find("plot", 1, true) then
						table.insert(diagName, d.ClassName .. " '" .. d.Name .. "'  <" .. d:GetFullName() .. ">")
					end
				end
			end
		end
		return nil
	end

	local roots = {ws}
	if lp:FindFirstChild("PlayerGui") then table.insert(roots, lp.PlayerGui) end

	for _, root in ipairs(roots) do
		local pos, owner = scanRoot(root) if pos then return pos, owner end
	end

	warn("[EggTP] Ranch introuvable. Diagnostic :")
	warn("[EggTP] -- textes contenant 'ranch'/'plot' --")
	if #diagText == 0 then
		warn("[EggTP]   (aucun)")
	else
		for _, line in ipairs(diagText) do warn("[EggTP]   " .. line) end
	end
	warn("[EggTP] -- objets nommes 'ranch'/'plot' (toutes classes) --")
	if #diagName == 0 then
		warn("[EggTP]   (aucun)")
	else
		for _, line in ipairs(diagName) do warn("[EggTP]   " .. line) end
	end

	return nil
end

-- Le plot ne bouge pas : la recherche (tout Workspace + PlayerGui) n'est faite
-- qu'une fois, puis memorisee tant que l'instance trouvee existe encore.
local ranchCache = nil

local function findRanchPos()
	if ranchCache and ranchCache.inst and ranchCache.inst.Parent and ranchCache.inst:IsDescendantOf(game) then
		return ranchCache.pos, ranchCache.inst
	end
	local pos, inst = findRanchPosUncached()
	if pos and inst then
		ranchCache = {pos = pos, inst = inst}
	end
	return pos, inst
end

-- === Lacher / reprendre l'oeuf devant le ranch ============================
-- Meme principe que yslemEgg devant la ligne : on se met un peu EN ARRIERE du
-- ranch, on lache l'oeuf, on le reprend, puis on entre dans le ranch.

-- Lacher l'oeuf. Dans l'ordre :
--   1) le bouton "DROP" du jeu (a l'ecran) : clic simule au centre du bouton
--   2) un prompt de depot/lacher proche
--   3) la touche de drop par defaut de Roblox (Backspace) pour un outil tenu
local DROP_WORDS = {"drop", "release", "put down", "place", "poser", "lacher", "deposer"}

local function trimLower(t)
	t = (t or ""):lower()
	t = t:gsub("^%s+", "")
	t = t:gsub("%s+$", "")
	return t
end

-- un objet GUI est "affiche" si lui et tous ses parents sont visibles
local function guiShown(obj)
	local p = obj
	while p and p:IsA("GuiObject") do
		if not p.Visible then return false end
		p = p.Parent
	end
	local sg = obj:FindFirstAncestorOfClass("ScreenGui")
	return sg == nil or sg.Enabled
end

-- Tous les objets d'interface qui ressemblent au bouton DROP du jeu (texte
-- "DROP" ou nom drop/dropbutton...), hors de notre propre interface.
local function dropGuiCandidates()
	local list = {}
	local pg = lp:FindFirstChild("PlayerGui")
	if not pg then return list end

	-- chemin exact releve par l'analyse : Main.BasketTracker.Handler.EggFrame.Drop
	local node = pg
	for _, name in ipairs({"Main", "BasketTracker", "Handler", "EggFrame", "Drop"}) do
		node = node and node:FindFirstChild(name)
	end
	if node and node:IsA("GuiObject") then
		table.insert(list, node)
	end
	for _, d in ipairs(pg:GetDescendants()) do
		if d:IsA("GuiObject") and d ~= node and not d:FindFirstAncestor("EggTPGui") then
			local hit = false
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				hit = trimLower(d.Text) == "drop"
			end
			if not hit then
				local n = d.Name:lower()
				hit = (n == "drop" or n == "dropbutton" or n == "dropbtn" or n == "drop_button" or n == "dropegg")
			end
			if hit and d.AbsoluteSize.X > 0 and d.AbsoluteSize.Y > 0 then
				table.insert(list, d)
			end
		end
	end
	return list
end

-- Appui "silencieux" sur un bouton : uniquement ses signaux (firesignal), SANS
-- souris ni toucher simules. Renvoie true si l'executeur sait le faire.
local function pressGuiSilent(obj)
	local btn = obj
	while btn and not btn:IsA("GuiButton") do
		btn = btn.Parent
		if btn and not btn:IsA("GuiObject") then btn = nil end
	end
	if not btn or typeof(firesignal) ~= "function" then return false end
	for _, sig in ipairs({"MouseButton1Down", "MouseButton1Click", "Activated", "MouseButton1Up"}) do
		pcall(function() firesignal(btn[sig]) end)
	end
	return true
end

-- Dernier recours (desactivable avec CLICK_FALLBACK = false) : un clic souris
-- simule au centre du bouton. Jamais de toucher simule (un toucher reste
-- parfois "enfonce" et bloque le joystick).
local CLICK_FALLBACK = true

local function pressGuiClick(obj)
	pcall(function()
		local vim    = game:GetService("VirtualInputManager")
		local inset  = game:GetService("GuiService"):GetGuiInset()
		local screen = obj:FindFirstAncestorOfClass("ScreenGui")
		local dy = (screen and screen.IgnoreGuiInset) and 0 or inset.Y
		local c = obj.AbsolutePosition + obj.AbsoluteSize / 2
		vim:SendMouseButtonEvent(c.X, c.Y + dy, 0, true, game, 0)
		task.wait(0.05)
		vim:SendMouseButtonEvent(c.X, c.Y + dy, 0, false, game, 0)
	end)
end

-- Remotes dont le nom parle de "drop" (dernier recours, sans argument).
local function dropRemotes()
	local list = {}
	-- remote exact du jeu : ReplicatedStorage.Remotes.Game.BasketDrop
	pcall(function()
		local r = ReplicatedStorage.Remotes.Game.BasketDrop
		if r:IsA("RemoteEvent") then table.insert(list, r) end
	end)
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if d:IsA("RemoteEvent") and d.Name:lower():find("drop", 1, true) and d ~= list[1] then
			table.insert(list, d)
		end
	end
	return list
end

-- niveau 1 : signaux du bouton DROP (silencieux) ; niveau 2 : remotes drop,
-- prompts de depot proches et touche de drop par defaut (Backspace) ;
-- niveau 3 : clic souris simule (seulement si CLICK_FALLBACK).
local function dropEgg(level)
	local myChar = lp.Character
	local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if not myHrp then return end

	if level == 1 then
		local n = 0
		for _, obj in ipairs(dropGuiCandidates()) do
			if guiShown(obj) then
				pressGuiSilent(obj)
				n = n + 1
				if n >= 3 then break end
			end
		end
		return
	end

	if level == 3 then
		if not CLICK_FALLBACK then return end
		for _, obj in ipairs(dropGuiCandidates()) do
			if guiShown(obj) then
				pressGuiClick(obj)
				return
			end
		end
		return
	end

	for _, r in ipairs(dropRemotes()) do
		pcall(function() r:FireServer() end)
	end

	pcall(function()
		for _, d in ipairs(ws:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Parent and not d:IsDescendantOf(myChar) then
				local at = (d.ActionText or ""):lower()
				for _, w in ipairs(DROP_WORDS) do
					if at:find(w, 1, true) then
						local pos = getPos(d.Parent)
						if pos and (pos - myHrp.Position).Magnitude <= 40 then
							tryFire(d)
						end
						break
					end
				end
			end
		end
	end)

	pcall(function()
		local vim = game:GetService("VirtualInputManager")
		vim:SendKeyEvent(true, Enum.KeyCode.Backspace, false, game)
		task.wait(0.05)
		vim:SendKeyEvent(false, Enum.KeyCode.Backspace, false, game)
	end)
end

-- Etat "on porte un oeuf" : la barre "Egg Will Break" du jeu est affichee.
-- Renvoie true / false, ou nil si la barre n'existe pas encore.
local breakLabel = nil
local function isCarrying()
	if not (breakLabel and breakLabel.Parent) then
		breakLabel = nil
		local pg = lp:FindFirstChild("PlayerGui")
		if pg then
			for _, d in ipairs(pg:GetDescendants()) do
				if d:IsA("TextLabel") and d.Text and d.Text:lower():find("egg will break", 1, true) then
					breakLabel = d
					break
				end
			end
		end
	end
	if not breakLabel then return nil end
	return guiShown(breakLabel)
end

-- Prompts de ramassage proches de nous (pour reperer l'oeuf une fois lache).
local lastHeavyScan = 0

local function isPickupPrompt(d)
	local at = (d.ActionText or ""):lower()
	return at:find("pick", 1, true) or at:find("grab", 1, true) or at:find("take", 1, true)
end

local function nearbyPickups(radius)
	local list = {}
	local myHrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	if not myHrp then return list end
	local center = myHrp.Position

	-- 1) requete spatiale : seulement les pieces autour de nous (rapide)
	pcall(function()
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {lp.Character}
		for _, part in ipairs(ws:GetPartBoundsInRadius(center, radius, params)) do
			for _, c in ipairs(part:GetChildren()) do
				if c:IsA("ProximityPrompt") then
					if isPickupPrompt(c) then list[c] = true end
				elseif c:IsA("Attachment") then
					for _, cc in ipairs(c:GetChildren()) do
						if cc:IsA("ProximityPrompt") and isPickupPrompt(cc) then list[cc] = true end
					end
				end
			end
		end
	end)

	-- 2) filet de securite : parcours complet, au plus toutes les 0,6 s, seulement
	-- si la requete spatiale n'a rien trouve (pieces non interrogeables, etc.)
	if next(list) == nil and os.clock() - lastHeavyScan > 0.6 then
		lastHeavyScan = os.clock()
		for _, d in ipairs(ws:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Parent and isPickupPrompt(d) then
				local pos = getPos(d.Parent)
				if pos and (pos - center).Magnitude <= radius then
					list[d] = true
				end
			end
		end
	end
	return list
end

-- Marge entre le bord du plot et le point d'attente (on reste DEHORS du ranch).
local STAGE_BACK  = 20
local STAGE_TRIES = 5
local MAX_PLOT    = 300 -- un conteneur plus grand n'est pas le plot

-- Boite englobante (axes du monde) de toutes les pieces d'une instance, sans
-- les personnages. Renvoie min, max ou nil.
local function instBounds(inst)
	local minV, maxV = nil, nil
	local count = 0
	local function addPart(part)
		local cf, size = part.CFrame, part.Size
		local r = cf - cf.Position
		local ex = r:VectorToWorldSpace(Vector3.new(size.X / 2, 0, 0))
		local ey = r:VectorToWorldSpace(Vector3.new(0, size.Y / 2, 0))
		local ez = r:VectorToWorldSpace(Vector3.new(0, 0, size.Z / 2))
		local half = Vector3.new(
			math.abs(ex.X) + math.abs(ey.X) + math.abs(ez.X),
			math.abs(ex.Y) + math.abs(ey.Y) + math.abs(ez.Y),
			math.abs(ex.Z) + math.abs(ey.Z) + math.abs(ez.Z))
		local lo, hi = cf.Position - half, cf.Position + half
		if not minV then
			minV, maxV = lo, hi
		else
			minV = Vector3.new(math.min(minV.X, lo.X), math.min(minV.Y, lo.Y), math.min(minV.Z, lo.Z))
			maxV = Vector3.new(math.max(maxV.X, hi.X), math.max(maxV.Y, hi.Y), math.max(maxV.Z, hi.Z))
		end
	end
	local function isPlayerPart(part)
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.Character and part:IsDescendantOf(plr.Character) then return true end
		end
		return false
	end
	if inst:IsA("BasePart") then
		addPart(inst)
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") and not isPlayerPart(d) then
			addPart(d)
			count = count + 1
			if count > 4000 then break end
		end
	end
	return minV, maxV
end

-- Le plot entier : on remonte du repere trouve (piece / pancarte) jusqu'au plus
-- grand conteneur qui reste de la taille d'un plot.
local boundsCache = {}

local function plotBounds(inst)
	if not inst then return nil end
	local cached = boundsCache[inst]
	if cached and os.clock() - cached.at < 20 then return cached.lo, cached.hi end
	local bestMin, bestMax = instBounds(inst)
	local p = inst.Parent
	while p and p ~= ws and (p:IsA("Model") or p:IsA("Folder")) do
		local lo, hi = instBounds(p)
		if not lo then break end
		if (hi.X - lo.X) > MAX_PLOT or (hi.Z - lo.Z) > MAX_PLOT then break end
		bestMin, bestMax = lo, hi
		p = p.Parent
	end
	boundsCache[inst] = {lo = bestMin, hi = bestMax, at = os.clock()}
	return bestMin, bestMax
end

-- Point d'attente : le point du bord du plot le plus proche de nous, repousse de
-- STAGE_BACK studs vers l'exterieur (donc devant le ranch, jamais dedans).
local plotLo, plotHi, plotCenter = nil, nil, nil

local function stagePoint(ppos, inst)
	local myHrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	if not myHrp then return nil end
	local me = myHrp.Position

	local lo, hi = plotBounds(inst)
	plotLo, plotHi = lo, hi
	plotCenter = lo and Vector3.new((lo.X + hi.X) / 2, ppos.Y, (lo.Z + hi.Z) / 2) or ppos
	if not lo then
		-- repere inconnu : on retombe sur la direction ranch -> nous
		local flat = Vector3.new(me.X - ppos.X, 0, me.Z - ppos.Z)
		local dir  = flat.Magnitude > 1 and flat.Unit or Vector3.new(0, 0, 1)
		return ppos + dir * (STAGE_BACK + 25)
	end

	local cx = math.clamp(me.X, lo.X, hi.X)
	local cz = math.clamp(me.Z, lo.Z, hi.Z)
	local away = Vector3.new(me.X - cx, 0, me.Z - cz)
	if away.Magnitude < 1 then
		-- on est deja dans la boite : sortir par le bord le plus proche
		local dists = {
			{me.X - lo.X, Vector3.new(-1, 0, 0)},
			{hi.X - me.X, Vector3.new(1, 0, 0)},
			{me.Z - lo.Z, Vector3.new(0, 0, -1)},
			{hi.Z - me.Z, Vector3.new(0, 0, 1)},
		}
		table.sort(dists, function(a, b) return a[1] < b[1] end)
		away = dists[1][2]
		cx = math.clamp(me.X + away.X * dists[1][1], lo.X, hi.X)
		cz = math.clamp(me.Z + away.Z * dists[1][1], lo.Z, hi.Z)
	end
	return Vector3.new(cx, ppos.Y, cz) + away.Unit * STAGE_BACK
end

-- Derniere etape : VOL a 700% de la vitesse de marche (jauge yslemEgg : 100% =
-- WalkSpeed), au-dessus de la cloture, puis pose au sol dans le ranch.
local FLY_FRACTION = 7.0 -- 700% de la vitesse de marche
local FLY_HEIGHT   = 40
local RANCH_DEEPER = 15 -- studs de plus apres le centre du ranch

-- Vol par vitesse (jamais un tp) : monte au-dessus du ranch, avance a
-- WalkSpeed x FLY_FRACTION, puis pose le personnage au sol quand il est dans le
-- plot. PlatformStand + noclip pendant le vol, TOUJOURS restaures ensuite.
local function flyIntoRanch(pos, abortFn)
	local myChar = lp.Character
	local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
	local hum    = myChar and myChar:FindFirstChildOfClass("Humanoid")
	if not myHrp or not hum or not pos then return end

	local cruiseY = pos.Y + FLY_HEIGHT
	local aborted = false
	hum.PlatformStand = true

	pcall(function()
		local started = os.clock()
		local dt = 1 / 60
		while not cancelMove and myHrp.Parent and os.clock() - started < 40 do
			setNoclip(true)
			if abortFn and abortFn() then aborted = true break end
			-- on va jusqu'au CENTRE du ranch (pas seulement son bord)
			local flat = Vector3.new(pos.X - myHrp.Position.X, 0, pos.Z - myHrp.Position.Z)
			if flat.Magnitude < 6 then break end

			local speed = math.max(hum.WalkSpeed * FLY_FRACTION, 8)
			-- meme repartition que le vol de yslemEgg : la vitesse totale reste = speed
			local vy = math.clamp((cruiseY - myHrp.Position.Y) / 0.12, -speed * 0.5, speed * 0.5)
			local horizontal = math.sqrt(math.max(speed * speed - vy * vy, 0))
			local v = flat.Unit * math.min(horizontal, flat.Magnitude / math.max(dt, 1 / 240))
			myHrp.AssemblyLinearVelocity = Vector3.new(v.X, vy, v.Z)
			dt = RunService.Heartbeat:Wait()
		end

		-- pose au sol dans le ranch (pas si le vol a ete interrompu : oeuf perdu)
		if not cancelMove and not aborted and myHrp.Parent then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = {myChar}
			params.IgnoreWater = true
			local origin = Vector3.new(myHrp.Position.X, myHrp.Position.Y + 5, myHrp.Position.Z)
			local hit = ws:Raycast(origin, Vector3.new(0, -400, 0), params)
			if hit then
				myHrp.CFrame = CFrame.new(hit.Position + Vector3.new(0, 4, 0)) * myHrp.CFrame.Rotation
			end
		end
	end)

	setNoclip(false)
	hum.PlatformStand = false
	restoreControl()
	return not aborted
end

-- Reprise de l'oeuf lache : tire le prompt de ramassage jusqu'a CONFIRMER qu'on
-- le porte de nouveau (barre "Egg Will Break" de retour). On ne se contente
-- jamais de "le prompt a disparu" quand la barre existe : c'etait la cause du
-- vol vers le ranch sans l'oeuf. Si l'oeuf a roule loin de nous, on se place
-- sur lui avant de tirer le prompt.
local function retakeEgg(before, hint, timeout, needCarry)
	local t0 = os.clock()
	while os.clock() - t0 < timeout and not cancelMove do
		if needCarry and isCarrying() == true then return true end

		local h = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
		if not h then return false end

		local pr = (hint and hint.Parent and hint:IsDescendantOf(ws)) and hint or nil
		if not pr then
			-- le nouvel objet de ramassage le plus proche (a defaut le plus proche tout court)
			local best, bestScore = nil, math.huge
			for prompt in pairs(nearbyPickups(60)) do
				local pos = getPos(prompt.Parent)
				if pos then
					local score = (pos - h.Position).Magnitude - (before[prompt] and 0 or 1000)
					if score < bestScore then best, bestScore = prompt, score end
				end
			end
			pr = best
		end

		if pr then
			local pos = getPos(pr.Parent)
			if pos and (pos - h.Position).Magnitude > 8 then
				place(pos + Vector3.new(0, 3, 0))
			end
			tryFire(pr)
		elseif not needCarry then
			return true -- plus rien a ramasser et pas de barre pour confirmer
		end
		task.wait(0.06)
	end
	return needCarry and isCarrying() == true or false
end

-- Retour au ranch : tp (ou vol, selon le bouton) devant le plot (a l'exterieur),
-- drop de l'oeuf, reprise, puis VOL a 100% jusque dans le ranch. Renvoie
-- (false) si on n'a pas pu se placer, sinon (true, dropFailed).
local function goToRanchPos(ppos, pinst)
	local myHrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	if not myHrp then return false end

	-- point d'attente : devant le ranch, a l'exterieur de son bord
	local stage = stagePoint(ppos, pinst)
	if not stage then return false end

	-- on s'assure d'etre vraiment arrive (le serveur peut renvoyer ailleurs)
	local arrived = false
	for _ = 1, STAGE_TRIES do
		moveTo(stage)
		if cancelMove then return true, false end
		task.wait(0.15)
		local h = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
		if h and (Vector3.new(h.Position.X - stage.X, 0, h.Position.Z - stage.Z)).Magnitude <= 12 then
			arrived = true
			break
		end
	end
	if not arrived then return false end

	-- drop : succes si un nouvel objet de ramassage apparait OU si la barre
	-- "Egg Will Break" disparait
	local carriedAtStart = isCarrying() == true
	local before = nearbyPickups(30)
	local dropped, droppedPrompt = false, nil
	for level = 1, 3 do
		dropEgg(level)
		local waited = 0
		while waited < (level == 1 and 0.7 or 1.1) and not cancelMove do
			for prompt in pairs(nearbyPickups(30)) do
				if not before[prompt] then droppedPrompt = prompt; break end
			end
			if droppedPrompt or (carriedAtStart and not isCarrying()) then
				dropped = true
				break
			end
			task.wait(0.05)
			waited = waited + 0.05
		end
		if dropped or cancelMove then break end
	end
	if cancelMove then return true, false end

	local dropFailed = not dropped
	if dropFailed then
		warn("[EggTP] Drop non detecte : l'oeuf reste dans les mains, on continue vers le ranch.")
	else
		-- reprise CONFIRMEE : on ne part pas tant que l'oeuf n'est pas repris
		if not retakeEgg(before, droppedPrompt, 6, carriedAtStart) then
			if cancelMove then return true, false, false end
			warn("[EggTP] Reprise de l'oeuf non confirmee : on ne part pas sans l'oeuf.")
			return true, false, true
		end
	end
	if cancelMove then return true, dropFailed, false end

	-- vol jusque dans le ranch ; si l'oeuf est perdu en route on s'arrete, on le
	-- reprend, puis on repart (3 essais)
	local function lost()
		return carriedAtStart and isCarrying() ~= true
	end
	-- on s'enfonce un peu plus dans le ranch que son centre (RANCH_DEEPER studs
	-- dans la direction d'arrivee), sans sortir de la boite du plot
	local aim = plotCenter or ppos
	local toward = Vector3.new(aim.X - stage.X, 0, aim.Z - stage.Z)
	if toward.Magnitude > 1 then
		aim = aim + toward.Unit * RANCH_DEEPER
	end
	if plotLo and plotHi then
		aim = Vector3.new(
			math.clamp(aim.X, plotLo.X + 6, math.max(plotLo.X + 6, plotHi.X - 6)),
			aim.Y,
			math.clamp(aim.Z, plotLo.Z + 6, math.max(plotLo.Z + 6, plotHi.Z - 6)))
	end

	local retakeFailed = false
	for _ = 1, 3 do
		if cancelMove then break end
		if lost() and not retakeEgg(before, nil, 5, true) then
			retakeFailed = true
			break
		end
		if flyIntoRanch(aim, lost) then break end
	end
	return true, dropFailed, retakeFailed
end

-- === icones : uniquement une correspondance EXACTE avec l'UI du jeu =========

local iconCache = {}
local iconCacheBuilt = false

local function buildIconCache()
	if iconCacheBuilt then return end
	iconCacheBuilt = true
	iconCache = {}

	local roots = {}
	if lp:FindFirstChild("PlayerGui") then table.insert(roots, lp.PlayerGui) end
	table.insert(roots, ReplicatedStorage)

	local scanned = 0
	for _, root in ipairs(roots) do
		pcall(function()
			for _, d in ipairs(root:GetDescendants()) do
				scanned = scanned + 1
				if scanned > 6000 then return end
				if d:IsA("ImageLabel") or d:IsA("ImageButton") then
					local img = d.Image
					if img and img ~= "" then
						local key = d.Name:lower()
						if not iconCache[key] then iconCache[key] = img end
						local parent = d.Parent
						if parent then
							for _, sib in ipairs(parent:GetChildren()) do
								if sib:IsA("TextLabel") or sib:IsA("TextButton") then
									local t = sib.Text
									if t and #t > 0 and #t < 40 then
										local tk = t:lower()
										if not iconCache[tk] then iconCache[tk] = img end
									end
								end
							end
						end
					end
				end
			end
		end)
	end
end

-- Correspondance EXACTE uniquement (Name ou texte voisin == nom de l'oeuf).
local function findEggIcon(name)
	buildIconCache()
	return iconCache[name:lower()]
end

-- === repli : rendu 3D du vrai modele de l'oeuf ==============================

local function buildViewport(modelInst, parent)
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.new(1, 0, 1, 0)
	vp.BackgroundColor3 = Color3.fromRGB(4, 4, 4)
	vp.BackgroundTransparency = 0
	vp.Parent = parent
	Instance.new("UICorner", vp).CornerRadius = UDim.new(0, 8)

	local clone = modelInst:Clone()
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
			d:Destroy()
		elseif d:IsA("Sound") then
			d.Playing = false
		end
	end
	clone.Parent = vp

	local cam = Instance.new("Camera")
	cam.Parent = vp
	vp.CurrentCamera = cam

	local okBB, cf, size = false, nil, nil
	if clone:IsA("Model") then
		okBB, cf, size = pcall(function() return clone:GetBoundingBox() end)
	end
	if okBB and cf and size then
		local dist = math.max(size.X, size.Y, size.Z, 2) * 1.7
		cam.CFrame = CFrame.new(cf.Position + Vector3.new(dist * 0.6, dist * 0.45, dist * 0.6), cf.Position)
	end

	return vp
end

-- === UI (ultra-compacte, theme noir) ========================================

local existing = lp.PlayerGui:FindFirstChild("EggTPGui")
if existing then existing:Destroy() end

local sg = Instance.new("ScreenGui")
sg.Name           = "EggTPGui"
sg.ResetOnSpawn   = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent         = lp.PlayerGui

local FULL_SIZE   = UDim2.new(0, 224, 0, 122)
local TITLE_H     = 20

local main = Instance.new("Frame")
main.Name             = "Main"
main.Size             = FULL_SIZE
main.Position         = UDim2.new(0.5, -112, 0.6, -61)
main.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
main.BorderSizePixel  = 0
main.ClipsDescendants = true
main.Parent           = sg
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 11)

local mainGradient = Instance.new("UIGradient")
mainGradient.Rotation = 60
mainGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 20, 20)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(2, 2, 2)),
})
mainGradient.Parent = main

local mainStroke = Instance.new("UIStroke", main)
mainStroke.Color     = Color3.fromRGB(255, 255, 255)
mainStroke.Thickness = 1.2

local borderGradient = Instance.new("UIGradient")
borderGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(70, 70, 70)),
	ColorSequenceKeypoint.new(1,   Color3.fromRGB(255, 255, 255)),
})
borderGradient.Parent = mainStroke

-- barre de titre ----------------------------------------------------------

local titleBar = Instance.new("Frame")
titleBar.Size             = UDim2.new(1, 0, 0, TITLE_H)
titleBar.BackgroundColor3 = Color3.fromRGB(14, 14, 14)
titleBar.BorderSizePixel  = 0
titleBar.Parent           = main
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 11)

local titleGradient = Instance.new("UIGradient")
titleGradient.Rotation = 0
titleGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 24, 24)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(6, 6, 6)),
})
titleGradient.Parent = titleBar

local titleLbl = Instance.new("TextLabel")
titleLbl.Size                   = UDim2.new(1, -26, 1, 0)
titleLbl.Position               = UDim2.new(0, 6, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.TextColor3             = Color3.fromRGB(255, 255, 255)
titleLbl.Font                   = Enum.Font.GothamBold
titleLbl.TextSize               = 11
titleLbl.TextXAlignment         = Enum.TextXAlignment.Left
titleLbl.Text                   = "EGG TP"
titleLbl.Parent                 = titleBar

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size             = UDim2.new(0, 15, 0, 15)
minimizeBtn.Position         = UDim2.new(1, -21, 0.5, -7)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
minimizeBtn.BorderSizePixel  = 0
minimizeBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
minimizeBtn.Font             = Enum.Font.GothamBold
minimizeBtn.TextSize         = 12
minimizeBtn.Text             = "-"
minimizeBtn.AutoButtonColor  = false
minimizeBtn.Parent           = titleBar
Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 5)


-- corps (tout ce qui disparait quand on reduit) ----------------------------

local body = Instance.new("Frame")
body.Size                = UDim2.new(1, 0, 1, -TITLE_H)
body.Position            = UDim2.new(0, 0, 0, TITLE_H)
body.BackgroundTransparency = 1
body.Parent              = main

-- ligne de controle : RANCH + methode TP/VOL + toggle Auto -------------------

local ranchBtn = Instance.new("TextButton")
ranchBtn.Size             = UDim2.new(0, 40, 0, 14)
ranchBtn.Position         = UDim2.new(0, 4, 0, 3)
ranchBtn.BackgroundColor3 = Color3.fromRGB(130, 95, 25)
ranchBtn.BorderSizePixel  = 0
ranchBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
ranchBtn.Font             = Enum.Font.GothamBold
ranchBtn.TextSize         = 8
ranchBtn.Text             = "RANCH"
ranchBtn.AutoButtonColor  = false
ranchBtn.Parent           = body
Instance.new("UICorner", ranchBtn).CornerRadius = UDim.new(0, 5)

local modeBtn = Instance.new("TextButton")
modeBtn.Size             = UDim2.new(0, 32, 0, 14)
modeBtn.Position         = UDim2.new(0, 47, 0, 3)
modeBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
modeBtn.BorderSizePixel  = 0
modeBtn.TextColor3       = Color3.fromRGB(230, 230, 230)
modeBtn.Font             = Enum.Font.GothamBold
modeBtn.TextSize         = 8
modeBtn.Text             = methodLabel()
modeBtn.AutoButtonColor  = false
modeBtn.Parent           = body
Instance.new("UICorner", modeBtn).CornerRadius = UDim.new(0, 5)

local autoLbl = Instance.new("TextLabel")
autoLbl.Size                   = UDim2.new(0, 24, 0, 14)
autoLbl.Position               = UDim2.new(1, -62, 0, 3)
autoLbl.BackgroundTransparency = 1
autoLbl.TextColor3             = Color3.fromRGB(190, 190, 190)
autoLbl.Font                   = Enum.Font.Gotham
autoLbl.TextSize               = 8
autoLbl.TextXAlignment         = Enum.TextXAlignment.Right
autoLbl.Text                   = "Auto"
autoLbl.Parent                 = body

local autoBtn = Instance.new("TextButton")
autoBtn.Size             = UDim2.new(0, 26, 0, 12)
autoBtn.Position         = UDim2.new(1, -30, 0, 4)
autoBtn.BackgroundColor3 = Color3.fromRGB(35, 165, 80)
autoBtn.BorderSizePixel  = 0
autoBtn.Text             = ""
autoBtn.AutoButtonColor  = false
autoBtn.Parent           = body
Instance.new("UICorner", autoBtn).CornerRadius = UDim.new(1, 0)

local autoKnob = Instance.new("Frame")
autoKnob.Size             = UDim2.new(0, 10, 0, 10)
autoKnob.Position         = UDim2.new(1, -11, 0.5, -5)
autoKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
autoKnob.BorderSizePixel  = 0
autoKnob.Parent           = autoBtn
Instance.new("UICorner", autoKnob).CornerRadius = UDim.new(1, 0)

-- carrousel -----------------------------------------------------------------

local leftArrow = Instance.new("TextButton")
leftArrow.Size             = UDim2.new(0, 16, 0, 44)
leftArrow.Position         = UDim2.new(0, 2, 0, 19)
leftArrow.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
leftArrow.BorderSizePixel  = 0
leftArrow.TextColor3       = Color3.fromRGB(215, 215, 215)
leftArrow.Font             = Enum.Font.GothamBold
leftArrow.TextSize         = 14
leftArrow.Text             = "<"
leftArrow.AutoButtonColor  = false
leftArrow.Parent           = body
Instance.new("UICorner", leftArrow).CornerRadius = UDim.new(0, 6)

local rightArrow = Instance.new("TextButton")
rightArrow.Size             = UDim2.new(0, 16, 0, 44)
rightArrow.Position         = UDim2.new(1, -18, 0, 19)
rightArrow.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
rightArrow.BorderSizePixel  = 0
rightArrow.TextColor3       = Color3.fromRGB(215, 215, 215)
rightArrow.Font             = Enum.Font.GothamBold
rightArrow.TextSize         = 14
rightArrow.Text             = ">"
rightArrow.AutoButtonColor  = false
rightArrow.Parent           = body
Instance.new("UICorner", rightArrow).CornerRadius = UDim.new(0, 6)

local cardZone = Instance.new("Frame")
cardZone.Size                   = UDim2.new(1, -40, 0, 44)
cardZone.Position               = UDim2.new(0, 20, 0, 19)
cardZone.BackgroundTransparency = 1
cardZone.Parent                 = body

local cardInner = Instance.new("Frame")
cardInner.Size                   = UDim2.new(1, 0, 1, 0)
cardInner.BackgroundTransparency = 1
cardInner.Parent                 = cardZone

local iconHolder = Instance.new("Frame")
iconHolder.Size             = UDim2.new(0, 40, 0, 40)
iconHolder.Position         = UDim2.new(0, 0, 0, 2)
iconHolder.BackgroundColor3 = Color3.fromRGB(4, 4, 4)
iconHolder.BorderSizePixel  = 0
iconHolder.Parent           = cardInner
Instance.new("UICorner", iconHolder).CornerRadius = UDim.new(0, 7)
local iconHolderStroke = Instance.new("UIStroke", iconHolder)
iconHolderStroke.Color = Color3.fromRGB(65, 65, 65)
iconHolderStroke.Thickness = 1

local infoCol = Instance.new("Frame")
infoCol.Size                   = UDim2.new(1, -46, 1, 0)
infoCol.Position               = UDim2.new(0, 46, 0, 0)
infoCol.BackgroundTransparency = 1
infoCol.Parent                 = cardInner

local nameLbl = Instance.new("TextLabel")
nameLbl.Size                   = UDim2.new(1, -16, 0, 14)
nameLbl.Position               = UDim2.new(0, 0, 0, 4)
nameLbl.BackgroundTransparency = 1
nameLbl.TextColor3             = Color3.fromRGB(235, 235, 235)
nameLbl.Font                   = Enum.Font.GothamBold
nameLbl.TextSize               = 10
nameLbl.TextXAlignment         = Enum.TextXAlignment.Left
nameLbl.TextTruncate           = Enum.TextTruncate.AtEnd
nameLbl.Text                   = "Scan..."
nameLbl.Parent                 = infoCol

local countLbl = Instance.new("TextLabel")
countLbl.Size                   = UDim2.new(1, -16, 0, 10)
countLbl.Position               = UDim2.new(0, 0, 0, 20)
countLbl.BackgroundTransparency = 1
countLbl.TextColor3             = Color3.fromRGB(145, 145, 145)
countLbl.Font                   = Enum.Font.Gotham
countLbl.TextSize               = 7
countLbl.TextXAlignment         = Enum.TextXAlignment.Left
countLbl.Text                   = ""
countLbl.Parent                 = infoCol

local listToggleBtn = Instance.new("TextButton")
listToggleBtn.Size             = UDim2.new(0, 14, 0, 14)
listToggleBtn.Position         = UDim2.new(1, -14, 0, 2)
listToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
listToggleBtn.BorderSizePixel  = 0
listToggleBtn.TextColor3       = Color3.fromRGB(215, 215, 215)
listToggleBtn.Font             = Enum.Font.GothamBold
listToggleBtn.TextSize         = 9
listToggleBtn.Text             = "v"
listToggleBtn.AutoButtonColor  = false
listToggleBtn.Parent           = infoCol
Instance.new("UICorner", listToggleBtn).CornerRadius = UDim.new(0, 4)

local liveDot = Instance.new("Frame")
liveDot.Size             = UDim2.new(0, 6, 0, 6)
liveDot.Position         = UDim2.new(0, 4, 1, -14)
liveDot.BackgroundColor3 = Color3.fromRGB(90, 230, 130)
liveDot.BorderSizePixel  = 0
liveDot.Parent           = body
Instance.new("UICorner", liveDot).CornerRadius = UDim.new(1, 0)

local statusLbl = Instance.new("TextLabel")
statusLbl.Size                   = UDim2.new(1, -70, 0, 14)
statusLbl.Position               = UDim2.new(0, 12, 1, -16)
statusLbl.BackgroundTransparency = 1
statusLbl.TextColor3             = Color3.fromRGB(185, 185, 185)
statusLbl.Font                   = Enum.Font.Gotham
statusLbl.TextSize               = 8
statusLbl.TextXAlignment         = Enum.TextXAlignment.Left
statusLbl.TextTruncate           = Enum.TextTruncate.AtEnd
statusLbl.Text                   = "Scan en cours..."
statusLbl.Parent                 = body

local grabBtn = Instance.new("TextButton")
grabBtn.Size             = UDim2.new(0, 52, 0, 14)
grabBtn.Position         = UDim2.new(1, -56, 1, -16)
grabBtn.BackgroundColor3 = Color3.fromRGB(35, 165, 80)
grabBtn.BorderSizePixel  = 0
grabBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
grabBtn.Font             = Enum.Font.GothamBold
grabBtn.TextSize         = 7
grabBtn.Text             = "RAMASSER"
grabBtn.AutoButtonColor  = false
grabBtn.Parent           = body
Instance.new("UICorner", grabBtn).CornerRadius = UDim.new(0, 5)

-- liste rapide (pour ne pas devoir tourner longtemps) ------------------------

local quickList = Instance.new("Frame")
quickList.Size             = UDim2.new(1, -8, 1, -21)
quickList.Position         = UDim2.new(0, 4, 0, 17)
quickList.BackgroundColor3 = Color3.fromRGB(6, 6, 6)
quickList.BorderSizePixel  = 0
quickList.Visible          = false
quickList.ZIndex           = 5
quickList.Parent           = body
Instance.new("UICorner", quickList).CornerRadius = UDim.new(0, 7)
local quickListStroke = Instance.new("UIStroke", quickList)
quickListStroke.Color = Color3.fromRGB(65, 65, 65)
quickListStroke.Thickness = 1

local quickScroll = Instance.new("ScrollingFrame")
quickScroll.Size                = UDim2.new(1, -6, 1, -6)
quickScroll.Position            = UDim2.new(0, 3, 0, 3)
quickScroll.BackgroundTransparency = 1
quickScroll.BorderSizePixel     = 0
quickScroll.ScrollBarThickness  = 3
quickScroll.ScrollBarImageColor3 = Color3.fromRGB(110, 110, 110)
quickScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
quickScroll.CanvasSize          = UDim2.new(0, 0, 0, 0)
quickScroll.ZIndex              = 5
quickScroll.Parent              = quickList

local quickListLayout = Instance.new("UIListLayout")
quickListLayout.Padding   = UDim.new(0, 2)
quickListLayout.SortOrder = Enum.SortOrder.LayoutOrder
quickListLayout.Parent    = quickScroll

-- === yslemStyle ============================================================
-- Contours et textes en degrade qui tourne en continu, theme noir, barre de
-- titre claire a titre noir, formes arrondies.

local Y_WHITE  = Color3.fromRGB(255, 255, 255)
local Y_SILVER = Color3.fromRGB(150, 150, 156)
local Y_STEEL  = Color3.fromRGB(70, 70, 76)
local yLiving  = {}

local function yBands(a, b)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(0.25, b), ColorSequenceKeypoint.new(0.5, a),
		ColorSequenceKeypoint.new(0.75, b), ColorSequenceKeypoint.new(1, a),
	})
end

-- contour vivant (bandes qui tournent autour de la bordure)
local function livingStroke(inst, thickness, bright)
	local old = inst:FindFirstChild("YslemStroke")
	if old then old:Destroy() end
	local st = Instance.new("UIStroke")
	st.Name = "YslemStroke"
	st.Thickness = thickness or 1
	st.Color = Y_WHITE
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = inst
	local g = Instance.new("UIGradient")
	g.Rotation = 45
	g.Color = yBands(bright and Y_WHITE or Y_SILVER, Y_STEEL)
	g.Parent = st
	table.insert(yLiving, g)
	return st, g
end

-- texte vivant (bandes qui traversent les lettres)
local function livingText(inst)
	if inst:FindFirstChild("YslemText") then return end
	local g = Instance.new("UIGradient")
	g.Name = "YslemText"
	g.Color = yBands(Y_WHITE, Y_SILVER)
	g.Parent = inst
	table.insert(yLiving, g)
end

local function darkButton(btn, radius)
	btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	btn.TextColor3 = Y_WHITE
	local c = btn:FindFirstChildOfClass("UICorner")
	if c and radius then c.CornerRadius = UDim.new(0, radius) end
	livingStroke(btn, 1, true)
	livingText(btn)
end

-- fenetre : le contour existant devient le contour vivant
mainStroke.Thickness = 1.4
borderGradient.Color = yBands(Y_WHITE, Y_STEEL)
borderGradient.Rotation = 45
table.insert(yLiving, borderGradient)
main.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
mainGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 14, 14)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
})
main:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 14)

-- barre de titre : bande claire vivante, titre noir
titleBar.BackgroundColor3 = Y_WHITE
titleGradient.Rotation = 0
titleGradient.Color = yBands(Y_WHITE, Y_SILVER)
table.insert(yLiving, titleGradient)
titleLbl.TextColor3 = Color3.fromRGB(0, 0, 0)
titleBar:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 14)

darkButton(minimizeBtn, 7)
darkButton(ranchBtn, 7)
darkButton(modeBtn, 7)
darkButton(leftArrow, 8)
darkButton(rightArrow, 8)
darkButton(grabBtn, 7)
darkButton(listToggleBtn, 6)

livingText(autoLbl)
livingText(nameLbl)
livingText(countLbl)
livingText(statusLbl)

iconHolderStroke.Thickness = 1
livingStroke(iconHolder, 1, false)
iconHolderStroke.Enabled = false
quickListStroke.Enabled = false
livingStroke(quickList, 1, false)

-- === effets (glow anime + pulsation + intro) ================================

local uiClock = 0
local yTick = 0
local fxConn
fxConn = RunService.Heartbeat:Connect(function(dt)
	uiClock = uiClock + dt
	yTick = yTick + 1
	if yTick % 2 == 0 then
		local rot = (uiClock * 72) % 360
		for i = #yLiving, 1, -1 do
			local g = yLiving[i]
			if g.Parent then
				g.Rotation = g.Parent:IsA("UIStroke") and (45 + rot) % 360 or rot
			else
				table.remove(yLiving, i)
			end
		end
	end
	liveDot.BackgroundTransparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(uiClock * 3))
end)

do
	local openSize = main.Size
	main.Size = UDim2.new(0, 40, 0, 18)
	main.BackgroundTransparency = 1
	mainStroke.Transparency = 1
	TweenService:Create(main, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Size = openSize, BackgroundTransparency = 0}):Play()
	TweenService:Create(mainStroke, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {Transparency = 0}):Play()
end

local function addPressFX(btn)
	local orig = btn.Size
	local shrink = UDim2.new(orig.X.Scale, orig.X.Offset - 4, orig.Y.Scale, orig.Y.Offset - 2)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.08, Enum.EasingStyle.Quad), {Size = shrink}):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = orig}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {Size = orig}):Play()
	end)
end

addPressFX(minimizeBtn)
addPressFX(ranchBtn)
addPressFX(modeBtn)
addPressFX(leftArrow)
addPressFX(rightArrow)
addPressFX(grabBtn)
addPressFX(listToggleBtn)

-- minimiser / restaurer -------------------------------------------------------

local minimized = false

local function setMinimized(state)
	minimized = state
	minimizeBtn.Text = state and "+" or "-"
	if state then
		quickList.Visible = false
		listToggleBtn.Text = "v"
		local t = TweenService:Create(main, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{Size = UDim2.new(FULL_SIZE.X.Scale, FULL_SIZE.X.Offset, 0, TITLE_H)})
		t:Play()
		t.Completed:Connect(function()
			if minimized then body.Visible = false end
		end)
	else
		body.Visible = true
		TweenService:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Size = FULL_SIZE}):Play()
	end
end

minimizeBtn.MouseButton1Click:Connect(function() setMinimized(not minimized) end)

-- === methode de deplacement : toggle TP / VOL ===============================

local saveConfig = function() end -- definie plus bas (apres l'etat "Auto")

modeBtn.MouseButton1Click:Connect(function()
	tpMethod = (tpMethod == "fly") and "tp" or "fly"
	modeBtn.Text = methodLabel()
	saveConfig()
end)

-- === etat "occupe" (deplacement en cours) + bouton RAMASSER/STOP ===========
-- Declare ici (avant goToRanch/doPickup) car les deux s'en servent pour
-- pouvoir etre interrompus via le bouton STOP.

local busy = false

local function setBusy(state)
	busy = state
	if state then
		grabBtn.Text = "STOP"
		grabBtn.BackgroundColor3 = Color3.fromRGB(70, 12, 12)
	else
		grabBtn.Text = "RAMASSER"
		grabBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	end
end

-- === Ranch : option auto-retour + bouton manuel =============================

local autoReturnRanch = true

local function setAuto(value, animated)
	autoReturnRanch = value
	local targetPos   = autoReturnRanch and UDim2.new(1, -11, 0.5, -5) or UDim2.new(0, 1, 0.5, -5)
	local targetColor = autoReturnRanch and Color3.fromRGB(35, 165, 80) or Color3.fromRGB(55, 55, 60)
	if animated then
		TweenService:Create(autoKnob, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Position = targetPos}):Play()
		TweenService:Create(autoBtn, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {BackgroundColor3 = targetColor}):Play()
	else
		autoKnob.Position = targetPos
		autoBtn.BackgroundColor3 = targetColor
	end
end

autoBtn.MouseButton1Click:Connect(function()
	setAuto(not autoReturnRanch, true)
	saveConfig()
end)

-- Reglages memorises entre deux lancements : methode TP/VOL et retour auto au
-- ranch (fichier local, seulement si l'executeur a readfile / writefile).
local CONFIG_FILE = "yslempet_EggTP.json"

saveConfig = function()
	pcall(function()
		if typeof(writefile) == "function" then
			writefile(CONFIG_FILE, game:GetService("HttpService"):JSONEncode({method = tpMethod, auto = autoReturnRanch}))
		end
	end)
end

pcall(function()
	if typeof(isfile) == "function" and typeof(readfile) == "function" and isfile(CONFIG_FILE) then
		local data = game:GetService("HttpService"):JSONDecode(readfile(CONFIG_FILE))
		if type(data) == "table" then
			if data.method == "fly" or data.method == "tp" then
				tpMethod = data.method
				modeBtn.Text = methodLabel()
			end
			if type(data.auto) == "boolean" then
				setAuto(data.auto, false)
			end
		end
	end
end)

local function goToRanchInner()
	if busy then
		stopMove()
		return
	end
	local ppos, pinst = findRanchPos()
	if not ppos then
		statusLbl.Text = "Ranch introuvable"
		return
	end

	cancelMove = false
	setBusy(true)
	statusLbl.Text = methodLabel() .. " -> Ranch (drop + reprise)"
	local reached, dropFailed, retakeFailed = goToRanchPos(ppos, pinst)
	setBusy(false)
	if not reached then
		statusLbl.Text = "Placement avant ranch impossible"
	elseif retakeFailed then
		statusLbl.Text = "Oeuf non repris (reste devant le ranch)"
	elseif dropFailed then
		statusLbl.Text = "Drop non detecte"
	else
		statusLbl.Text = cancelMove and "Arrete" or "Ranch atteint"
	end
end

local function goToRanch()
	if busy then
		stopMove()
		return
	end
	local ok, err = pcall(goToRanchInner)
	if not ok then
		warn("[EggTP] erreur : " .. tostring(err))
		statusLbl.Text = "Erreur (voir console)"
		setBusy(false)
		restoreControl()
	end
end

ranchBtn.MouseButton1Click:Connect(goToRanch)


-- === drag (barre de titre) ===================================================

do
	local dragging   = false
	local dragStart  = nil
	local frameStart = nil

	titleBar.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or
		   inp.UserInputType == Enum.UserInputType.Touch then
			dragging   = true
			dragStart  = inp.Position
			frameStart = main.Position
		end
	end)
	titleBar.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or
		   inp.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(inp)
		if not dragging then return end
		if inp.UserInputType == Enum.UserInputType.MouseMovement or
		   inp.UserInputType == Enum.UserInputType.Touch then
			local delta = inp.Position - dragStart
			main.Position = UDim2.new(
				frameStart.X.Scale, frameStart.X.Offset + delta.X,
				frameStart.Y.Scale, frameStart.Y.Offset + delta.Y
			)
		end
	end)
end

-- === carrousel : donnees + rendu =============================================

local eggOrder     = {}
local currentIndex = 1
local autoRunning  = true

local function computeEggOrder()
	local data  = collectEggs()
	local names = {}
	for n in pairs(data) do table.insert(names, n) end
	table.sort(names)
	local order = {}
	for _, n in ipairs(names) do
		table.insert(order, {name = n, list = data[n]})
	end
	return order
end

local function showEmptyState()
	for _, c in ipairs(iconHolder:GetChildren()) do
		if not c:IsA("UICorner") and not c:IsA("UIStroke") then c:Destroy() end
	end
	nameLbl.Text  = "Aucun oeuf"
	countLbl.Text = "sur la map"
end

local function renderCardContent(entry)
	for _, c in ipairs(iconHolder:GetChildren()) do
		if not c:IsA("UICorner") and not c:IsA("UIStroke") then c:Destroy() end
	end

	local iconUrl = findEggIcon(entry.name)
	if iconUrl then
		local img = Instance.new("ImageLabel")
		img.Size                   = UDim2.new(1, -6, 1, -6)
		img.Position               = UDim2.new(0, 3, 0, 3)
		img.BackgroundTransparency = 1
		img.Image                  = iconUrl
		img.ScaleType              = Enum.ScaleType.Fit
		img.Parent                 = iconHolder
	else
		local e = entry.list[1]
		if e and e.inst then buildViewport(e.inst, iconHolder) end
	end

	nameLbl.Text  = entry.name
	countLbl.Text = "x" .. #entry.list .. " sur la map"
end

local function buildQuickList()
	for _, c in ipairs(quickScroll:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	for i, entry in ipairs(eggOrder) do
		local row = Instance.new("TextButton")
		row.Size             = UDim2.new(1, -4, 0, 26)
		row.BackgroundColor3 = (i == currentIndex) and Color3.fromRGB(42, 42, 42) or Color3.fromRGB(18, 18, 18)
		row.BorderSizePixel  = 0
		row.Text             = ""
		row.LayoutOrder      = i
		row.AutoButtonColor  = false
		row.ZIndex           = 6
		row.Parent           = quickScroll
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)
		livingStroke(row, 1, false)

		local iconBox = Instance.new("Frame")
		iconBox.Size             = UDim2.new(0, 22, 0, 22)
		iconBox.Position         = UDim2.new(0, 2, 0, 2)
		iconBox.BackgroundColor3 = Color3.fromRGB(4, 4, 4)
		iconBox.BorderSizePixel  = 0
		iconBox.ZIndex           = 6
		iconBox.Parent           = row
		Instance.new("UICorner", iconBox).CornerRadius = UDim.new(0, 5)

		local iconUrl = findEggIcon(entry.name)
		if iconUrl then
			local img = Instance.new("ImageLabel")
			img.Size                   = UDim2.new(1, -3, 1, -3)
			img.Position               = UDim2.new(0, 1, 0, 1)
			img.BackgroundTransparency = 1
			img.Image                  = iconUrl
			img.ScaleType              = Enum.ScaleType.Fit
			img.ZIndex                 = 7
			img.Parent                 = iconBox
		end

		local rowLbl = Instance.new("TextLabel")
		rowLbl.Size                   = UDim2.new(1, -30, 1, 0)
		rowLbl.Position               = UDim2.new(0, 28, 0, 0)
		rowLbl.BackgroundTransparency = 1
		rowLbl.TextColor3             = Color3.fromRGB(220, 220, 220)
		rowLbl.Font                   = Enum.Font.Gotham
		rowLbl.TextSize               = 8
		rowLbl.TextXAlignment         = Enum.TextXAlignment.Left
		rowLbl.TextTruncate           = Enum.TextTruncate.AtEnd
		rowLbl.Text                   = entry.name .. "  x" .. #entry.list
		rowLbl.ZIndex                 = 6
		rowLbl.Parent                 = row
		livingText(rowLbl)

		row.MouseButton1Click:Connect(function()
			currentIndex = i
			renderCardContent(eggOrder[currentIndex])
			quickList.Visible = false
			listToggleBtn.Text = "v"
		end)
	end
end

local function updateStatusSummary()
	if #eggOrder == 0 then
		statusLbl.Text = "Aucun oeuf sur la map"
		return
	end
	local total = 0
	for _, e in ipairs(eggOrder) do total = total + #e.list end
	statusLbl.Text = #eggOrder .. " types - " .. total .. " oeufs"
end

local function rebuildEggList(preserveSelection, silent)
	local prevName = nil
	if preserveSelection and eggOrder[currentIndex] then
		prevName = eggOrder[currentIndex].name
	end

	eggOrder = computeEggOrder()

	if #eggOrder == 0 then
		currentIndex = 1
		showEmptyState()
		buildQuickList()
		if not silent then statusLbl.Text = "Aucun oeuf sur la map" end
		return
	end

	if prevName then
		local found = nil
		for i, e in ipairs(eggOrder) do
			if e.name == prevName then found = i; break end
		end
		currentIndex = found or 1
	else
		currentIndex = math.clamp(currentIndex, 1, #eggOrder)
	end

	renderCardContent(eggOrder[currentIndex])
	buildQuickList()
	if not silent then updateStatusSummary() end
end

local function renderCard(index, dir)
	local entry = eggOrder[index]
	if not entry then return end

	local outOffset = (dir == -1) and 50 or -50
	local outTween = TweenService:Create(cardInner,
		TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{Position = UDim2.new(0, outOffset, 0, 0)})
	outTween:Play()
	outTween.Completed:Connect(function()
		renderCardContent(entry)
		cardInner.Position = UDim2.new(0, -outOffset, 0, 0)
		TweenService:Create(cardInner,
			TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Position = UDim2.new(0, 0, 0, 0)}):Play()
	end)
end

local function showIndex(newIndex, dir)
	if #eggOrder == 0 then return end
	local n = #eggOrder
	currentIndex = ((newIndex - 1) % n) + 1
	renderCard(currentIndex, dir)
end

-- Prise de l'oeuf de la map CONFIRMEE : on tire le prompt (maintien a 0) jusqu'a
-- ce que la barre "Egg Will Break" apparaisse, en se replacant sur l'oeuf s'il
-- est loin. Sans barre (detection impossible) on accepte quand le prompt a
-- disparu. On ne part JAMAIS vers le ranch sans avoir confirme la prise.
local function grabEgg(e, timeout)
	local t0 = os.clock()
	while os.clock() - t0 < timeout and not cancelMove do
		if isCarrying() == true then return true end

		local prompt = e.prompt
		if not (prompt and prompt.Parent and prompt:IsDescendantOf(ws)) then
			-- le prompt a disparu : pris (ou pris par un autre) ; la barre tranche
			task.wait(0.15)
			return isCarrying() == true or (isCarrying() == nil and true or false)
		end

		local h   = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
		local pos = getPos(prompt.Parent) or e.pos
		if h and pos and (pos - h.Position).Magnitude > 10 then
			place(pos + Vector3.new(0, 3, 0))
		end
		pcall(function() prompt.HoldDuration = 0 end)
		tryFire(prompt)
		task.wait(0.08)
	end
	return isCarrying() == true
end

local function doPickupInner()
	if busy then return end
	if #eggOrder == 0 then
		statusLbl.Text = "Aucun oeuf disponible"
		return
	end

	cancelMove = false
	setBusy(true)
	local sel = eggOrder[currentIndex]

	local fresh     = collectEggs()
	local freshList = fresh[sel.name]
	if not freshList or #freshList == 0 then
		statusLbl.Text = sel.name .. " n'est plus disponible"
		setBusy(false)
		rebuildEggList(true, false)
		return
	end

	local e = nearest(freshList)
	if not e or not e.pos then
		statusLbl.Text = "Oeuf introuvable"
		setBusy(false)
		return
	end

	local pickedName = sel.name
	moveTo(e.pos)
	if cancelMove then
		statusLbl.Text = "Arrete"
		setBusy(false)
		return
	end
	statusLbl.Text = methodLabel() .. " -> " .. pickedName
	task.wait(0.15)
	if not grabEgg(e, 6) then
		statusLbl.Text = cancelMove and "Arrete" or (pickedName .. " non pris")
		setBusy(false)
		rebuildEggList(true, true)
		return
	end

	if autoReturnRanch then
		local ppos, pinst = findRanchPos()
		if ppos then
			statusLbl.Text = pickedName .. " -> Ranch (drop + reprise)"
			local reached, dropFailed, retakeFailed = goToRanchPos(ppos, pinst)
			if not reached then
				statusLbl.Text = "Placement avant ranch impossible"
				setBusy(false)
				rebuildEggList(true, true)
				return
			end
			if cancelMove then
				statusLbl.Text = pickedName .. " (arrete avant le ranch)"
				setBusy(false)
				rebuildEggList(true, true)
				return
			end
			statusLbl.Text = retakeFailed and (pickedName .. ": oeuf non repris (devant le ranch)") or (pickedName .. (dropFailed and " (Ranch, drop non detecte)" or " recupere (Ranch)"))
		else
			statusLbl.Text = pickedName .. " recupere (Ranch inconnu)"
		end
	else
		statusLbl.Text = pickedName .. " recupere"
	end

	task.wait(0.4)
	setBusy(false)
	rebuildEggList(true, true)
end

local function doPickup()
	if busy then return end
	local ok, err = pcall(doPickupInner)
	if not ok then
		warn("[EggTP] erreur : " .. tostring(err))
		statusLbl.Text = "Erreur (voir console)"
		setBusy(false)
		restoreControl()
	end
end

leftArrow.MouseButton1Click:Connect(function() showIndex(currentIndex - 1, -1) end)
rightArrow.MouseButton1Click:Connect(function() showIndex(currentIndex + 1, 1) end)

grabBtn.MouseButton1Click:Connect(function()
	if busy then
		stopMove()
	else
		doPickup()
	end
end)

listToggleBtn.MouseButton1Click:Connect(function()
	quickList.Visible = not quickList.Visible
	listToggleBtn.Text = quickList.Visible and "^" or "v"
end)

sg.Destroying:Connect(function()
	autoRunning = false
	if fxConn then fxConn:Disconnect() end
end)

-- swipe tactile / souris sur la carte -----------------------------------------

do
	local touchStart  = nil
	local touchMoved  = false

	cardZone.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or
		   inp.UserInputType == Enum.UserInputType.Touch then
			touchStart = inp.Position
			touchMoved = false
		end
	end)

	cardZone.InputChanged:Connect(function(inp)
		if not touchStart then return end
		if inp.UserInputType == Enum.UserInputType.MouseMovement or
		   inp.UserInputType == Enum.UserInputType.Touch then
			local delta = inp.Position - touchStart
			if math.abs(delta.X) > 10 or math.abs(delta.Y) > 10 then
				touchMoved = true
			end
		end
	end)

	cardZone.InputEnded:Connect(function(inp)
		if inp.UserInputType ~= Enum.UserInputType.MouseButton1 and
		   inp.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if not touchStart then return end
		local delta = inp.Position - touchStart
		touchStart = nil

		if math.abs(delta.X) > 40 and math.abs(delta.X) > math.abs(delta.Y) then
			if delta.X < 0 then
				showIndex(currentIndex + 1, 1)
			else
				showIndex(currentIndex - 1, -1)
			end
		elseif not touchMoved then
			doPickup()
		end
	end)
end

-- === boucle d'auto-rafraichissement (remplace le bouton Scan) ===============
-- Les oeufs de la map se renouvellent automatiquement dans le jeu (cycle
-- jour/nuit). Sans nom d'evenement confirme pour ce renouvellement, on relit
-- Workspace.RenderedEggs en continu (leger) pour rester a jour en toutes
-- circonstances.

local function autoRefreshLoop()
	while autoRunning do
		task.wait(5)
		if not busy then
			pcall(function() rebuildEggList(true, false) end)
		end
	end
end
coroutine.resume(coroutine.create(autoRefreshLoop))

rebuildEggList(false, false)
