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

local function setNoclip(state)
	local myChar = lp.Character
	if not myChar then return end
	for _, d in ipairs(myChar:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = not state
		end
	end
end

local function flyTo(pos)
	local myChar = lp.Character
	local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if not myHrp or not pos then return end
	local hum = myChar:FindFirstChildOfClass("Humanoid")
	local target = pos + Vector3.new(0, 5, 0)

	local prevPlatformStand = hum and hum.PlatformStand
	if hum then hum.PlatformStand = true end

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

	setNoclip(false)
	if hum then hum.PlatformStand = prevPlatformStand end
end

-- === choix de methode (option utilisateur) ==================================

local tpMethod = "tp" -- "tp" (desync) ou "fly" (velocity + noclip)

local function methodLabel()
	return tpMethod == "fly" and "VOL" or "TP"
end

local function moveTo(pos)
	cancelMove = false
	if tpMethod == "fly" then
		flyTo(pos)
	else
		tpTo(pos)
	end
end

local function stopMove()
	cancelMove = true
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

local function findRanchPos()
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
					warn("[EggTP] Ranch cible (nom d'instance) : " .. d:GetFullName())
					return pos
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
			if p:IsA("BasePart") then return p.Position end
			if p:IsA("BillboardGui") and p.Adornee then
				local pos = getPos(p.Adornee)
				if pos then return pos end
			end
			if p:IsA("Model") then
				local pos = getPos(p)
				if pos then return pos end
			end
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
						local pos = posFromAncestors(d.Parent, root)
						if pos then
							warn("[EggTP] Ranch cible (pancarte '" .. d.Text .. "') : " .. d:GetFullName())
							return pos
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
		local pos = scanRoot(root)
		if pos then return pos end
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

-- === Stand "Food" (hub central) : etape intermediaire avant le ranch =======
-- Le hub central du jeu regroupe plusieurs stands flottants (Gears, Track,
-- Sell, Food), generalement ranges dans Workspace.Stalls. Passer par ce
-- stand avant le plot evite au vol/tp de traverser du relief accidente
-- entre la map et le ranch.

local function isPositionable(inst)
	return inst:IsA("BasePart") or inst:IsA("Model") or inst:IsA("Folder")
end

local function findFoodShopPos()
	local stalls = ws:FindFirstChild("Stalls")
	if stalls then
		for _, d in ipairs(stalls:GetDescendants()) do
			if isPositionable(d) and d.Name:lower():find("food", 1, true) then
				local pos = getPos(d)
				if pos then
					warn("[EggTP] Shop Food cible : " .. d:GetFullName())
					return pos
				end
			end
		end
	end

	-- repli : n'importe quel objet nomme "food" dans tout le Workspace
	for _, d in ipairs(ws:GetDescendants()) do
		if isPositionable(d) and d.Name:lower():find("food", 1, true) then
			local pos = getPos(d)
			if pos then
				warn("[EggTP] Shop Food cible (repli global) : " .. d:GetFullName())
				return pos
			end
		end
	end

	return nil
end

-- Recherche "forcee" : le stand peut mettre un instant a se charger
-- (streaming) - on reessaie jusqu'a ~10 s. Pas de repli "vol direct" : le
-- passage au Food est obligatoire, sinon le trajet est annule (message).
local function findFoodShopPosForced()
	local pos = findFoodShopPos()
	if pos then return pos end
	for _ = 1, 25 do
		task.wait(0.4)
		if cancelMove then return nil end
		pos = findFoodShopPos()
		if pos then return pos end
	end
	warn("[EggTP] Shop Food introuvable apres reessais : trajet annule.")
	return nil
end

-- Lacher l'oeuf au Food. Le code du jeu n'expose aucune fonction de drop :
-- on utilise donc les moyens generiques, dans l'ordre :
--   1) un prompt de depot/lacher proche (ActionText "Drop", "Release", "Put
--      down", "Place", "Poser", "Lacher", "Deposer")
--   2) la touche de drop par defaut de Roblox (Backspace) pour un outil tenu
local DROP_WORDS = {"drop", "release", "put down", "place", "poser", "lacher", "deposer"}

local function dropEgg()
	local myChar = lp.Character
	local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if not myHrp then return end

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

-- Passage FORCE par le Shop Food : on ne lache l'oeuf qu'une fois reellement
-- arrive (a moins de FOOD_ARRIVE_D studs). Si le serveur nous renvoie ailleurs
-- (tp annule), on recommence jusqu'a FOOD_TRIES fois, puis le trajet est annule.
local FOOD_ARRIVE_D = 15
local FOOD_TRIES    = 8

local function forceToFood(shopPos)
	for _ = 1, FOOD_TRIES do
		moveTo(shopPos)
		if cancelMove then return true end
		task.wait(0.15)
		local myHrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
		if myHrp and (myHrp.Position - shopPos).Magnitude <= FOOD_ARRIVE_D then
			return true
		end
	end
	return false
end

-- Derniere etape : un RUN au sol (jamais tp ni vol) a 60% de la vitesse de
-- marche, du Shop Food jusqu'au plot.
local RUN_FRACTION = 0.6

local function runTo(pos, fraction)
	local myChar = lp.Character
	local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
	local hum    = myChar and myChar:FindFirstChildOfClass("Humanoid")
	if not myHrp or not hum or not pos then return end

	local started   = os.clock()
	local lastCheck = os.clock()
	local lastPos   = myHrp.Position

	while not cancelMove and myHrp.Parent and os.clock() - started < 120 do
		local flat = Vector3.new(pos.X - myHrp.Position.X, 0, pos.Z - myHrp.Position.Z)
		if flat.Magnitude < 4 then break end

		local unit  = flat.Unit
		local speed = hum.WalkSpeed * fraction
		local v     = unit * math.min(speed, flat.Magnitude / 0.05)
		myHrp.AssemblyLinearVelocity = Vector3.new(v.X, myHrp.AssemblyLinearVelocity.Y, v.Z)
		hum:Move(unit, false)

		-- bloque sur le decor : saut
		if os.clock() - lastCheck >= 1.5 then
			if (myHrp.Position - lastPos).Magnitude < 3 and flat.Magnitude > 10 then
				hum.Jump = true
			end
			lastPos, lastCheck = myHrp.Position, os.clock()
		end

		RunService.Heartbeat:Wait()
	end

	myHrp.AssemblyLinearVelocity = Vector3.new(0, myHrp.AssemblyLinearVelocity.Y, 0)
	hum:Move(Vector3.new(0, 0, 0), false)
end

-- Retour au ranch en 2 temps : Shop Food d'abord (passage force, l'oeuf est
-- lache a l'arrivee), puis RUN a 60% jusqu'au plot. Renvoie false si le Food
-- est introuvable ou inatteignable.
local function goToRanchPos(ppos)
	cancelMove = false
	local shopPos = findFoodShopPosForced()
	if cancelMove then return true end
	if not shopPos then return false end

	if not forceToFood(shopPos) then return false end
	if cancelMove then return true end

	dropEgg()
	task.wait(0.6)
	if cancelMove then return true end

	runTo(ppos, RUN_FRACTION)
	return true
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

-- === effets (glow anime + pulsation + intro) ================================

local uiClock = 0
local fxConn
fxConn = RunService.Heartbeat:Connect(function(dt)
	uiClock = uiClock + dt
	borderGradient.Rotation = (borderGradient.Rotation + dt * 45) % 360
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

modeBtn.MouseButton1Click:Connect(function()
	tpMethod = (tpMethod == "fly") and "tp" or "fly"
	modeBtn.Text = methodLabel()
end)

-- === etat "occupe" (deplacement en cours) + bouton RAMASSER/STOP ===========
-- Declare ici (avant goToRanch/doPickup) car les deux s'en servent pour
-- pouvoir etre interrompus via le bouton STOP.

local busy = false

local function setBusy(state)
	busy = state
	if state then
		grabBtn.Text = "STOP"
		grabBtn.BackgroundColor3 = Color3.fromRGB(190, 50, 50)
	else
		grabBtn.Text = "RAMASSER"
		grabBtn.BackgroundColor3 = Color3.fromRGB(35, 165, 80)
	end
end

-- === Ranch : option auto-retour + bouton manuel =============================

local autoReturnRanch = true

autoBtn.MouseButton1Click:Connect(function()
	autoReturnRanch = not autoReturnRanch
	local targetPos   = autoReturnRanch and UDim2.new(1, -11, 0.5, -5) or UDim2.new(0, 1, 0.5, -5)
	local targetColor = autoReturnRanch and Color3.fromRGB(35, 165, 80) or Color3.fromRGB(55, 55, 60)
	TweenService:Create(autoKnob, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Position = targetPos}):Play()
	TweenService:Create(autoBtn, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {BackgroundColor3 = targetColor}):Play()
end)

local function goToRanch()
	if busy then
		stopMove()
		return
	end
	local ppos = findRanchPos()
	if not ppos then
		statusLbl.Text = "Ranch introuvable"
		return
	end

	setBusy(true)
	statusLbl.Text = methodLabel() .. " -> Shop Food -> Ranch"
	local reached = goToRanchPos(ppos)
	setBusy(false)
	if not reached then
		statusLbl.Text = "Shop Food inatteignable"
	else
		statusLbl.Text = cancelMove and "Arrete" or "Ranch atteint"
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
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

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

local function doPickup()
	if busy then return end
	if #eggOrder == 0 then
		statusLbl.Text = "Aucun oeuf disponible"
		return
	end

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
	task.wait(0.5)
	tryFire(e.prompt)
	task.wait(0.7)

	if autoReturnRanch then
		local ppos = findRanchPos()
		if ppos then
			statusLbl.Text = pickedName .. " -> Shop Food -> Ranch"
			local reached = goToRanchPos(ppos)
			if not reached then
				statusLbl.Text = "Shop Food inatteignable (oeuf garde)"
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
			statusLbl.Text = pickedName .. " recupere (Ranch)"
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
