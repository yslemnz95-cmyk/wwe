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
	cancelMove = false
	if tpMethod == "fly" then
		flyTo(pos)
	else
		tpTo(pos)
	end
	restoreControl()
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

-- Diagnostic si le drop n'est pas detecte : ce qu'on a trouve (ou pas) comme
-- bouton DROP / remote drop. Copie dans le presse-papier si possible.
local lastDropDiag = ""
local function dropDiagnostic()
	local lines = {}
	for _, obj in ipairs(dropGuiCandidates()) do
		table.insert(lines, obj.ClassName .. (guiShown(obj) and "" or " (cache)") .. " <" .. obj:GetFullName() .. ">")
		if #lines >= 8 then break end
	end
	if #lines == 0 then table.insert(lines, "aucun bouton DROP trouve dans PlayerGui") end
	for _, r in ipairs(dropRemotes()) do
		table.insert(lines, "Remote <" .. r:GetFullName() .. ">")
		if #lines >= 12 then break end
	end
	return table.concat(lines, " | ")
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
local function nearbyPickups(radius)
	local list = {}
	local myHrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	if not myHrp then return list end
	for _, d in ipairs(ws:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Parent then
			local at = (d.ActionText or ""):lower()
			if at:find("pick", 1, true) or at:find("grab", 1, true) or at:find("take", 1, true) then
				local pos = getPos(d.Parent)
				if pos and (pos - myHrp.Position).Magnitude <= radius then
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
local function plotBounds(inst)
	if not inst then return nil end
	local bestMin, bestMax = instBounds(inst)
	local p = inst.Parent
	while p and p ~= ws and (p:IsA("Model") or p:IsA("Folder")) do
		local lo, hi = instBounds(p)
		if not lo then break end
		if (hi.X - lo.X) > MAX_PLOT or (hi.Z - lo.Z) > MAX_PLOT then break end
		bestMin, bestMax = lo, hi
		p = p.Parent
	end
	return bestMin, bestMax
end

-- Point d'attente : le point du bord du plot le plus proche de nous, repousse de
-- STAGE_BACK studs vers l'exterieur (donc devant le ranch, jamais dedans).
local plotLo, plotHi = nil, nil

local function stagePoint(ppos, inst)
	local myHrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	if not myHrp then return nil end
	local me = myHrp.Position

	local lo, hi = plotBounds(inst)
	plotLo, plotHi = lo, hi
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

local function insidePlot()
	local h = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	if not h or not plotLo then return false end
	return h.Position.X >= plotLo.X and h.Position.X <= plotHi.X and h.Position.Z >= plotLo.Z and h.Position.Z <= plotHi.Z
end

-- Vol par vitesse (jamais un tp) : monte au-dessus du ranch, avance a
-- WalkSpeed x FLY_FRACTION, puis pose le personnage au sol quand il est dans le
-- plot. PlatformStand + noclip pendant le vol, TOUJOURS restaures ensuite.
local function flyIntoRanch(pos)
	local myChar = lp.Character
	local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
	local hum    = myChar and myChar:FindFirstChildOfClass("Humanoid")
	if not myHrp or not hum or not pos then return end

	local cruiseY = pos.Y + FLY_HEIGHT
	hum.PlatformStand = true

	pcall(function()
		local started = os.clock()
		local dt = 1 / 60
		while not cancelMove and myHrp.Parent and os.clock() - started < 40 do
			setNoclip(true)
			if insidePlot() then break end
			local flat = Vector3.new(pos.X - myHrp.Position.X, 0, pos.Z - myHrp.Position.Z)
			if flat.Magnitude < 4 then break end

			local speed = math.max(hum.WalkSpeed * FLY_FRACTION, 8)
			-- meme repartition que le vol de yslemEgg : la vitesse totale reste = speed
			local vy = math.clamp((cruiseY - myHrp.Position.Y) / 0.12, -speed * 0.5, speed * 0.5)
			local horizontal = math.sqrt(math.max(speed * speed - vy * vy, 0))
			local v = flat.Unit * math.min(horizontal, flat.Magnitude / math.max(dt, 1 / 240))
			myHrp.AssemblyLinearVelocity = Vector3.new(v.X, vy, v.Z)
			dt = RunService.Heartbeat:Wait()
		end

		-- pose au sol dans le ranch
		if not cancelMove and myHrp.Parent then
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
end

-- Analyse automatique (definie plus bas avec GameScan) : appelee quand quelque
-- chose echoue pour copier le rapport complet.
local scanHook = nil

-- Retour au ranch : tp (ou vol, selon le bouton) devant le plot (a l'exterieur),
-- drop de l'oeuf, reprise, puis VOL a 100% jusque dans le ranch. Renvoie
-- (false) si on n'a pas pu se placer, sinon (true, dropFailed).
local function goToRanchPos(ppos, pinst)
	cancelMove = false
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
		lastDropDiag = dropDiagnostic()
		warn("[EggTP] Drop non detecte. " .. lastDropDiag)
		pcall(function() setclipboard("Drop non detecte. " .. lastDropDiag) end)
		if scanHook then task.spawn(scanHook, "drop") end
	else
		-- reprise : on tire le prompt de l'oeuf lache jusqu'a ce qu'on le porte de nouveau
		local t = 0
		while t < 3 and not cancelMove do
			if carriedAtStart and isCarrying() then break end
			local pr = droppedPrompt
			if not pr then
				local best, bd = nil, math.huge
				for prompt in pairs(nearbyPickups(30)) do
					local pos = getPos(prompt.Parent)
					local h = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
					if pos and h and (pos - h.Position).Magnitude < bd then
						best, bd = prompt, (pos - h.Position).Magnitude
					end
				end
				pr = best
			end
			if not pr or not pr.Parent or not pr:IsDescendantOf(ws) then break end
			tryFire(pr)
			task.wait(0.06)
			t = t + 0.06
		end
	end
	if cancelMove then return true, dropFailed end

	-- vol a 100% jusque dans le ranch, pose au sol
	flyIntoRanch(ppos)
	return true, dropFailed
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

	function GameScan.copy(text)
		local ok = pcall(function() setclipboard(text) end)
		return ok
	end
end
-- ==== yslem GameScan (END) ==================================================

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
	local ppos, pinst = findRanchPos()
	if not ppos then
		statusLbl.Text = "Ranch introuvable"
		return
	end

	setBusy(true)
	statusLbl.Text = methodLabel() .. " -> Ranch (drop + reprise)"
	local reached, dropFailed = goToRanchPos(ppos, pinst)
	setBusy(false)
	if not reached then
		statusLbl.Text = "Placement avant ranch impossible"
	elseif dropFailed then
		statusLbl.Text = "Drop non detecte (analyse copiee)"
	else
		statusLbl.Text = cancelMove and "Arrete" or "Ranch atteint"
	end
end

ranchBtn.MouseButton1Click:Connect(goToRanch)


-- === analyse a la demande (bouton "i") ======================================
-- Rapport complet sur le jeu : contexte, securite (observations), boutons,
-- prompts, remotes, monde, inventaire, scripts. Affiche dans un panneau et
-- copie dans le presse-papier. Lance aussi automatiquement si le drop echoue.

local scanBtn = Instance.new("TextButton")
scanBtn.Size             = UDim2.new(0, 15, 0, 15)
scanBtn.Position         = UDim2.new(1, -40, 0.5, -7)
scanBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
scanBtn.BorderSizePixel  = 0
scanBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
scanBtn.Font             = Enum.Font.GothamBold
scanBtn.TextSize         = 10
scanBtn.Text             = "i"
scanBtn.AutoButtonColor  = false
scanBtn.Parent           = titleBar
Instance.new("UICorner", scanBtn).CornerRadius = UDim.new(0, 5)
addPressFX(scanBtn)

local scanPanel = Instance.new("Frame")
scanPanel.Size             = UDim2.new(0, 300, 0, 230)
scanPanel.Position         = UDim2.new(0.5, -150, 0.5, -115)
scanPanel.BackgroundColor3 = Color3.fromRGB(6, 6, 6)
scanPanel.BorderSizePixel  = 0
scanPanel.Visible          = false
scanPanel.ZIndex           = 30
scanPanel.Parent           = sg
Instance.new("UICorner", scanPanel).CornerRadius = UDim.new(0, 10)
local scanStroke = Instance.new("UIStroke", scanPanel)
scanStroke.Color = Color3.fromRGB(255, 255, 255)
scanStroke.Thickness = 1.2

local scanTitle = Instance.new("TextLabel")
scanTitle.Size = UDim2.new(1, -90, 0, 18)
scanTitle.Position = UDim2.new(0, 8, 0, 3)
scanTitle.BackgroundTransparency = 1
scanTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
scanTitle.Font = Enum.Font.GothamBold
scanTitle.TextSize = 10
scanTitle.TextXAlignment = Enum.TextXAlignment.Left
scanTitle.Text = "ANALYSE DU JEU"
scanTitle.ZIndex = 31
scanTitle.Parent = scanPanel

local function panelButton(text, offsetX)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 36, 0, 15)
	b.Position = UDim2.new(1, offsetX, 0, 4)
	b.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	b.BorderSizePixel = 0
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 8
	b.Text = text
	b.AutoButtonColor = false
	b.ZIndex = 31
	b.Parent = scanPanel
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
	return b
end
local scanCopyBtn  = panelButton("COPIER", -78)
local scanCloseBtn = panelButton("X", -38)

local scanScroll = Instance.new("ScrollingFrame")
scanScroll.Size = UDim2.new(1, -10, 1, -30)
scanScroll.Position = UDim2.new(0, 5, 0, 25)
scanScroll.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
scanScroll.BorderSizePixel = 0
scanScroll.ScrollBarThickness = 3
scanScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scanScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scanScroll.ZIndex = 31
scanScroll.Parent = scanPanel
Instance.new("UICorner", scanScroll).CornerRadius = UDim.new(0, 6)

local scanText = Instance.new("TextLabel")
scanText.Size = UDim2.new(1, -8, 0, 0)
scanText.AutomaticSize = Enum.AutomaticSize.Y
scanText.Position = UDim2.new(0, 4, 0, 2)
scanText.BackgroundTransparency = 1
scanText.TextColor3 = Color3.fromRGB(215, 215, 215)
scanText.Font = Enum.Font.Code
scanText.TextSize = 8
scanText.TextWrapped = true
scanText.TextXAlignment = Enum.TextXAlignment.Left
scanText.TextYAlignment = Enum.TextYAlignment.Top
scanText.Text = ""
scanText.ZIndex = 32
scanText.Parent = scanScroll

local lastReport = ""
local scanning = false

local function runScan(reason)
	if scanning then return end
	scanning = true
	scanPanel.Visible = true
	scanTitle.Text = "ANALYSE DU JEU" .. (reason and (" (" .. reason .. ")") or "")
	scanText.Text = "Analyse en cours..."
	local ok, report = pcall(GameScan.run)
	if not ok then report = "Erreur d'analyse : " .. tostring(report) end
	lastReport = report
	local copied = GameScan.copy(report)
	-- une Label accepte ~16000 caracteres : le reste est dans le presse-papier
	local shown = #report > 15000 and (report:sub(1, 15000) .. "\n... (suite dans le presse-papier)") or report
	scanText.Text = shown
	scanTitle.Text = "ANALYSE" .. (copied and " - copiee" or " - copie impossible")
	scanning = false
end

scanHook = function(reason)
	pcall(runScan, reason)
end

scanBtn.MouseButton1Click:Connect(function() task.spawn(runScan) end)
scanCopyBtn.MouseButton1Click:Connect(function()
	if lastReport ~= "" then GameScan.copy(lastReport) end
end)
scanCloseBtn.MouseButton1Click:Connect(function() scanPanel.Visible = false end)

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
		local ppos, pinst = findRanchPos()
		if ppos then
			statusLbl.Text = pickedName .. " -> Ranch (drop + reprise)"
			local reached, dropFailed = goToRanchPos(ppos, pinst)
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
			statusLbl.Text = pickedName .. (dropFailed and " (Ranch, drop non detecte - analyse copiee)" or " recupere (Ranch)")
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
