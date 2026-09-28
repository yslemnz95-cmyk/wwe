-- ============================================================
-- MoonEgg — Steal An Egg Hub
-- Complete rebuild — new UI + unified movement engine + anti-detect
-- ============================================================

-- ===================================================================
-- ANTI-DETECTION ENGINE  (chargé en premier, avant tout le reste)
-- ===================================================================
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
local _cr = (typeof(cloneref) == "function") and cloneref or function(x) return x end

if not game:IsLoaded() then game.Loaded:Wait() end

local Players                = _cr(game:GetService("Players"))
local RunService             = _cr(game:GetService("RunService"))
local UIS                    = _cr(game:GetService("UserInputService"))
local TweenService           = _cr(game:GetService("TweenService"))
local HttpService            = _cr(game:GetService("HttpService"))
local Lighting                = _cr(game:GetService("Lighting"))
local ReplicatedStorage       = _cr(game:GetService("ReplicatedStorage"))
local ProximityPromptService  = _cr(game:GetService("ProximityPromptService"))
local LP                      = Players.LocalPlayer
if not LP.Character then LP.CharacterAdded:Wait() end

-- Couche 2 — newcclosure : wrap les fonctions critiques en C-closure.
local _ncc = (typeof(newcclosure) == "function") and newcclosure or function(f) return f end

-- Couche 3 — Noms de Part pseudo-légitimes.
local _PART_NAMES = {
	"Handle","Weld","Attachment","Joint","Motor","Bone",
	"RootConstraint","BasePart","HRP","RootPart"
}
local function _AD_partName()
	local base = _PART_NAMES[math.random(1, #_PART_NAMES)]
	local sfx  = string.format("%04x", math.random(0, 0xFFFF))
	return base .. sfx
end

-- Couche 6 — Jitter helper : casse les patterns de fréquence fixes.
local function _AD_jitter(base, amp)
	amp = amp or base * 0.18
	return math.max(0, base + (math.random() - 0.5) * 2 * amp)
end

-- Couche 7 — Script-source evasion.
pcall(function()
	local scr = getfenv and getfenv(0) and getfenv(0).script or nil
	if not scr then return end
	if typeof(setscriptable) == "function" then
		pcall(function() setscriptable(scr, "Source", true) end)
		pcall(function() scr.Source = "" end)
	end
end)

-- kill previous instance (clean relaunch)
pcall(function()
	local old = game:GetService("CoreGui"):FindFirstChild("MoonEggGui")
	if old then old:Destroy() end
	local old2 = LP.PlayerGui:FindFirstChild("MoonEggGui")
	if old2 then old2:Destroy() end
end)

-- ============================================================
-- GAME MODULE DISCOVERY — by NAME, not a fixed path
-- ============================================================
-- One single pass over all of ReplicatedStorage, indexed by
-- ModuleScript name — regardless of where the game actually placed it
-- (verified: the real folders are Shared.*/Data.*, not
-- Library.*/Directory.* as the original reference source assumed).
-- Each require() is isolated in its own pcall — a broken entry only
-- disables the feature that depends on it, never the others.
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

-- Grouped into ONE table (instead of 16 separate locals) to stay under
-- Luau's 200-active-locals-per-chunk limit now that dozens of extra
-- features share this same root scope.
local _M = {}
_M.EggCmds    = _tryRequire("EggCmds")
_M.Ragdoll    = _tryRequire("Ragdoll")
_M.Network    = _tryRequire("Network")
_M.NM         = _M.Network and _M.Network.NET_MAP
_M.GEP        = _tryRequire("GuardEscapePrediction")
_M.GCP        = _tryRequire("GuardChasePolicy")
_M.RGSR       = _tryRequire("ResolveGuardSpeedRequirement")
_M.SPP        = _tryRequire("SpeedPowerProjection")
_M.GuardsD    = _tryRequire("Guards")
_M.AreasD     = _tryRequire("Areas")
_M.SlotId     = _tryRequire("AreaEggSlotIdentity")
_M.Save       = _tryRequire("Save")
_M.Constants  = _tryRequire("Constants")
_M.Bases      = _tryRequire("Bases")
_M.Treadmills = _tryRequire("Treadmills")
_M.Trails     = _tryRequire("Trails")
_M.EggState   = _tryRequire("EggState")  -- ReplicatedStorage.Client.EggState
_M.Assets     = _tryRequire("Assets")    -- ReplicatedStorage.Data.Assets (rarity/value directory)
_M.Mutations  = _tryRequire("Mutations") -- ReplicatedStorage.Shared.Modules.Mutations (EarningsFor)
_M.TreadmillUtil = _tryRequire("TreadmillUtil")
_M.EggRecords = _tryRequire("EggRecords") -- Shared.Util.EggRecords (WeightKgForScale) -- Shared.Util.TreadmillUtil (SpeedPowerToWalkSpeed)

local _MODULE_NAMES = {
	"EggCmds","Network","Ragdoll","GuardEscapePrediction","GuardChasePolicy",
	"ResolveGuardSpeedRequirement","SpeedPowerProjection","Guards","Areas",
	"AreaEggSlotIdentity","Save","Constants","Bases","Treadmills","Trails","EggState",
	"Assets","Mutations","TreadmillUtil","EggRecords",
}
do
	local lines = {"[MoonEgg] Game module status:"}
	for _, name in ipairs(_MODULE_NAMES) do
		if _ModuleStatus[name] then
			table.insert(lines, "  OK        "..name.."  (".._ModuleFound[name]..")")
		elseif _ModuleFound[name] then
			table.insert(lines, "  FAILED    "..name.."  (found at ".._ModuleFound[name]..", require() failed)")
		else
			table.insert(lines, "  NOT FOUND "..name)
		end
	end
	print(table.concat(lines, "\n"))
end
if _M.SlotId then
	pcall(function()
		local keys = {}
		for k, v in pairs(_M.SlotId) do table.insert(keys, tostring(k).." ("..typeof(v)..")") end
		table.sort(keys)
		print("[MoonEgg] AreaEggSlotIdentity — available keys:\n  "..table.concat(keys, "\n  "))
	end)
end

-- ============================================================
-- CONFIRMED REMOTES (ReplicatedStorage.Packages.Networking)
-- ============================================================
-- The original analysis report listed the game's real Remote* instances
-- live — their Name already contains the full "path" as a slash
-- string (e.g. an instance literally named
-- "RF/AwayEarnings/AskCollect", parented directly under Networking,
-- not a real nested folder hierarchy). Auto Claim confirmed working
-- with this system — far more reliable than the original
-- Library.*/Directory.* modules.
local _NetworkingFolder = ReplicatedStorage:FindFirstChild("Packages")
_NetworkingFolder = _NetworkingFolder and _NetworkingFolder:FindFirstChild("Networking")

-- Accepts either a full name ("RF/Family/Action") or just the action
-- ("Action") — auto-fallback on any child of the folder whose name
-- ENDS with that suffix, so we never have to guess the exact family
-- of a newly discovered action.
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
-- GUARDED ZONES — Speed Power required per zone
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
-- SAFE ZONE — Auto Farm's destination after a successful grab (escape
-- the guards, consistent with the EXIT_DIR/SeparationLine already used
-- above for escape calculations). Dynamic discovery, cached once found
-- (static position):
--   1. Any instance whose name contains "safe" anywhere in workspace
--      (the most reliable option if the game names it explicitly).
--   2. Fallback: a point far from the SeparationLine along the already
--      computed EXIT_DIR (literally "the direction to exit a guarded
--      zone" in this hub).
-- ============================================================
-- Chilli Hub stealHome() exact logic: find the safe base delivery point.
local _STEAL_HOME_PATHS = {
	{Path={"GearGiver_Slap","Podium"}, Offset=Vector3.new(-16.415,21.072,-6.106)},
	{Path={"World","Machines","RiftMachine","Rift","Meshes/VoidPortal_Cube.003"}, Offset=Vector3.new(-26.776,1.75,18.665)},
	{Path={"__OBJECTS","Machines","RiftMachine","Rift","Meshes/VoidPortal_Cube.003"}, Offset=Vector3.new(-26.776,1.75,18.665)},
}
local function _findSafeZonePos()
	local found = nil
	for _, entry in ipairs(_STEAL_HOME_PATHS) do
		local obj = workspace
		for _, name in ipairs(entry.Path) do
			obj = obj and obj:FindFirstChild(name) or nil
		end
		if obj and obj:IsA("BasePart") then
			found = obj.CFrame:PointToWorldSpace(entry.Offset)
			break
		end
	end
	return found or Vector3.new(528.7, 70.57, -364.11)
end

-- ============================================================
-- EGG SCANNER — 3 complementary sources:
--   1. RE/EggWorld/FieldEggShifted  — eggs physically in the world
--      (BoundsCFrame = real position, Mutation = rarity, NestScale =
--      weight proxy); provides the richest, most reliable data.
--   2. AreaEggSlotsClient:GetChildren() — LP's own slots parsed by
--      name (FirstAreaEgg_{userId}_{N}_{Zone}:Slot_{N}) for zone/island.
--   3. ProximityPrompt fallback (other games, eggs on the ground).
-- ============================================================
local _RARE_KEYWORDS = {
	"secret","eternal","divine","divin","mythic","celestial","ancient",
	"rainbow","golden","shiny","radiant","corrupted","void","legendary",
}
-- Used by the own-base-eggs scan (source 2)
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
-- Network cache: uid → {pos,cf,mutation,nestScale,zone,tags,t}
local _fieldEggNet = {}

-- ============================================================
-- ASSET DIRECTORY / RARITY / VALUE — exact Chilli Hub technique
-- (aide_3 ~lines 6927-6972, 2140-2186): ReplicatedStorage.Data.Assets
-- .Directory[AssetCategory] carries {Rarity={RarityNumber,DisplayName},
-- EarningRate}. Egg income = EarningRate * scaleFactor(AssetScale) *
-- mutationMultiplier(Mutations), scaleFactor being the game's own
-- nonlinear curve (not a naive scale*rate estimate).
-- ============================================================
local cachedEggs = {}
local _Egg = {}
do
	local function dirEntry(assetCategory)
		local dir = _M.Assets and _M.Assets.Directory
		local e = type(dir) == "table" and dir[tostring(assetCategory)] or nil
		return type(e) == "table" and e or nil
	end
	_Egg.DirEntry = dirEntry
	function _Egg.WeightKg(assetCategory, scale)
		local er = _M.EggRecords
		if type(er) == "table" and type(er.WeightKgForScale) == "function" then
			local ok, r = pcall(er.WeightKgForScale, assetCategory, scale)
			if ok and type(r) == "number" then return r end
		end
		return nil
	end
	-- rarity colour: Rarity.Color of the game's asset directory
	local _styleCache = {}
	function _Egg.RarityStyle(assetCategory)
		local e = dirEntry(assetCategory)
		local rarity = e and e.Rarity
		local key = type(rarity) == "table" and tostring(rarity._id or rarity.DisplayName or "") or ""
		local st = _styleCache[key]
		if st then return st end
		local col = Color3.fromRGB(255, 255, 255)
		if type(rarity) == "table" and typeof(rarity.Color) == "Color3" then col = rarity.Color end
		st = {color = col}
		_styleCache[key] = st
		return st
	end
	function _Egg.DisplayName(assetCategory)
		local e = dirEntry(assetCategory)
		return tostring(e and e.DisplayName or assetCategory)
	end
	function _Egg.Rarity(assetCategory)
		local e = dirEntry(assetCategory)
		local rarity = e and e.Rarity
		local n = type(rarity) == "table" and tonumber(rarity.RarityNumber or rarity.Rank) or nil
		return n or 0
	end
	function _Egg.RarityName(assetCategory)
		local e = dirEntry(assetCategory)
		local rarity = e and e.Rarity
		if type(rarity) == "table" then
			return tostring(rarity.DisplayName or rarity._id or _Egg.Rarity(assetCategory))
		end
		return "Common"
	end
	-- "N - DisplayName", identical format to RarityDropdownOptions()'s
	-- entries — lets multi-select filters (Place/Fuse Rarities) key off
	-- the same string the picker stored, without a separate id table.
	function _Egg.RarityLabel(assetCategory)
		return string.format("%d - %s", _Egg.Rarity(assetCategory), _Egg.RarityName(assetCategory))
	end
	function _Egg.Value(assetCategory, assetScale, mutations)
		local e = dirEntry(assetCategory)
		local rate = e and tonumber(e.EarningRate) or 0
		local scale = tonumber(assetScale) or 0
		if scale <= 0 then return 0 end
		local scaleFactor = (scale > 5) and ((scale/5)^1.2 * 19.637875755794113) or (scale^1.85)
		local mult = 1
		if _M.Mutations and type(_M.Mutations.EarningsFor) == "function" then
			local ok, result = pcall(_M.Mutations.EarningsFor, type(mutations) == "table" and mutations or {})
			if ok and type(result) == "number" then mult = result end
		end
		return rate * scaleFactor * mult
	end
	-- The egg/pet's own icon, straight from the game's asset directory
	-- (aide_3 ~20756-20760: dir[category].Icon -> rbxassetid://<id>) —
	-- a real id read live from game data, never guessed.
	function _Egg.Icon(assetCategory)
		local e = dirEntry(assetCategory)
		local icon = e and e.Icon
		if icon == nil then return nil end
		icon = tostring(icon)
		if icon == "" then return nil end
		if tonumber(icon) then return "rbxassetid://"..icon end
		if icon:sub(1,4) == "rbx" then return icon end
		return nil
	end
	-- Every species in the game's own asset directory (so the pickers are
	-- never empty when no egg happens to be on the field), plus anything
	-- currently seen that the directory doesn't list.
	function _Egg.SpeciesOptions()
		local seen, opts = {}, {}
		local dir = _M.Assets and _M.Assets.Directory
		if type(dir) == "table" then
			for k in pairs(dir) do
				k = tostring(k)
				if not seen[k] then seen[k] = true; table.insert(opts, k) end
			end
		end
		for _, r in ipairs(cachedEggs) do
			if r.mutation and r.mutation ~= "" and not seen[r.mutation] then
				seen[r.mutation] = true; table.insert(opts, r.mutation)
			end
		end
		table.sort(opts)
		return opts
	end
	-- Builds the "N - DisplayName" rarity dropdown list (Any first),
	-- exactly like Chilli Hub's tbl8/tbl9 pair. Falls back to the fixed
	-- 10-tier list if the Directory hasn't loaded yet.
	function _Egg.RarityDropdownOptions()
		local byNum = {}
		local dir = _M.Assets and _M.Assets.Directory
		if type(dir) == "table" then
			for _, entry in pairs(dir) do
				local rarity = type(entry) == "table" and entry.Rarity or nil
				if type(rarity) == "table" then
					local n = tonumber(rarity.RarityNumber or rarity.Rank)
					if n and not byNum[n] then
						byNum[n] = tostring(rarity.DisplayName or rarity._id or n)
					end
				end
			end
		end
		if next(byNum) == nil then
			local fallback = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Cosmic","Secret","Eternal","Divine"}
			for i, nm in ipairs(fallback) do byNum[i] = nm end
		end
		local nums = {}
		for n in pairs(byNum) do table.insert(nums, n) end
		table.sort(nums)
		local options, valueOf = {"Any"}, {Any = 0}
		for _, n in ipairs(nums) do
			local str = string.format("%d - %s", n, byNum[n])
			table.insert(options, str)
			valueOf[str] = n
		end
		return options, valueOf
	end
end

-- Zone from world position (AREA must be built before this block)
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

-- Source 1: listens to RE/EggWorld/FieldEggShifted
-- Signature observed in the analysis: (slotId?, {BoundsCFrame, BottomCFrame,
-- Mutation, NestScale, HasParasite, ...}) or just ({...}).
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

		-- NEVER invents an id: if no real id is present in the event
		-- (neither as the 1st argument nor as a table field), the egg
		-- still shows in ESP but Auto Farm won't target it
		-- (farmable=false) — a fake id would make AskFieldEggCarry fail
		-- silently, which was the reported "doesn't grab / grabs badly".
		if not realUid then
			for _, k in ipairs(_ID_KEYS) do
				local v = data[k]
				if type(v) == "string" or type(v) == "number" then realUid = tostring(v); break end
			end
		end

		local mutation = type(data.Mutation) == "string" and data.Mutation or nil
		local nestScale = type(data.NestScale) == "number" and data.NestScale or nil
		-- Try direct Zone field first (most reliable, server sends it explicitly).
		local zoneDir = data.Zone or data.Area or data.AreaName or data.Island or data.ZoneName
		local zone = (type(zoneDir)=="string" and zoneDir~="") and zoneDir or _posToZone(pos2)

		local tags = {}
		local low = (mutation or ""):lower()
		for _, kw in ipairs(_RARE_KEYWORDS) do
			if low:find(kw, 1, true) then table.insert(tags, kw) end
		end

		-- Stable cache key even without a real id (rounded position).
		local cacheKey = realUid or string.format("%.0f_%.0f_%.0f", pos2.X, pos2.Y, pos2.Z)
		-- Use BottomCFrame as the physical walk target when available (less elevated than center).
		local walkPos = (typeof(data.BottomCFrame)=="CFrame" and data.BottomCFrame.Position) or pos2
		_fieldEggNet[cacheKey] = {
			pos=walkPos, cf=cf2, mutation=mutation, nestScale=nestScale,
			mutTable=(type(data.Mutations)=="table" and data.Mutations or nil),
			zone=zone, tags=tags, uid=realUid, t=tick(), enabled=true,
			farmable=(realUid ~= nil),
		}
	end)
end)

-- AskFieldEggSnapshot — periodic poll (every 3s while Auto Farm is active).
-- More reliable than FieldEggShifted alone: directly requests the server's
-- current live list of field eggs (with real UIDs), so Auto Farm has valid
-- targets even when the push event doesn't fire.
-- Also printed once on load for diagnostics.
local _snapshotDebugPrinted = false
task.spawn(function()
	while true do
		task.wait(3)
		local ok, snap = _invokeRF("RF/EggWorld/AskFieldEggSnapshot")
		if ok and type(snap) ~= "table" then ok = false end
		if not ok then
			if not _snapshotDebugPrinted then
				_snapshotDebugPrinted = true
				print("[MoonEgg] AskFieldEggSnapshot: unavailable or returned non-table")
			end
		else
			if not _snapshotDebugPrinted then
				_snapshotDebugPrinted = true
				local dumpOk, dump = pcall(function() return HttpService:JSONEncode(snap) end)
				print("[MoonEgg] AskFieldEggSnapshot (first result):")
				print(dumpOk and dump:sub(1, 800) or "<not serializable>")
			end
			-- Seed _fieldEggNet from snap.Records (Chilli Hub format).
			-- snap = {Records = [{Uid, State, BottomCFrame, AssetCategory, AssetScale, AreaId}]}
			local now2 = tick()
			pcall(function()
				local records = type(snap) == "table" and snap.Records or nil
				if type(records) ~= "table" then return end
				local seen = {}
				for _, record in ipairs(records) do
					if type(record) ~= "table" then continue end
					local uid2 = record.Uid and tostring(record.Uid) or nil
					if not uid2 then continue end
					seen[uid2] = true
					local state = record.State
					if state == "Claimed" or state == "Carried" then continue end
					local cf2 = typeof(record.BottomCFrame) == "CFrame" and record.BottomCFrame or nil
					if not cf2 then continue end
					local pos2 = cf2.Position
					local areaId = tostring(record.AreaId or "")
					local assetCategory = tostring(record.AssetCategory or "")
					local zone = (areaId ~= "") and areaId or _posToZone(pos2)
					local tags2 = {}
					local low2 = assetCategory:lower()
					for _, kw in ipairs(_RARE_KEYWORDS) do
						if low2:find(kw,1,true) then table.insert(tags2, kw) end
					end
					_fieldEggNet[uid2] = {
						pos=pos2, cf=cf2, mutation=assetCategory, nestScale=tonumber(record.AssetScale),
						mutTable=(type(record.Mutations)=="table" and record.Mutations or nil),
						zone=zone, tags=tags2, uid=uid2,
						t=now2, enabled=true, farmable=true, fromSnap=true,
					}
				end
				-- eggs that left the server's live list (claimed / carried by
				-- someone else) are dropped right away, like Chilli Hub does
				for k, e in pairs(_fieldEggNet) do
					if e.fromSnap and not seen[k] then _fieldEggNet[k] = nil end
				end
			end)
		end
	end
end)

local _eggScanPromptTotal, _eggScanPromptEnabled = 0, 0
local _ownBaseEggs = {}

-- Exact Chilli Hub source only: _fieldEggNet, fed by RE/EggWorld/FieldEggShifted
-- (push) and RF/EggWorld/AskFieldEggSnapshot (poll — see task.spawn above).
-- No heuristic ProximityPrompt text-guessing: prompts get destroyed and
-- recreated by the game every time an egg is claimed/respawned, which made
-- a text-matched scanner flicker entries in and out every cycle — the
-- exact symptom of "ESP started working then stopped". The snapshot/event
-- data is authoritative and doesn't have that problem.
task.spawn(function()
	while true do
		local eggs = {}
		local total, enabledCount = 0, 0
		local now2 = tick()
		for cacheKey, e in pairs(_fieldEggNet) do
			if now2 - e.t > 60 then
				_fieldEggNet[cacheKey] = nil
			else
				table.insert(eggs, {
					pos=e.pos, cf=e.cf, area=e.zone,
					cat=e.mutation or (e.zone.." Egg"),
					mutation=e.mutation, tags=e.tags, mutTable=e.mutTable,
					weight=nil, scale=e.nestScale,
					rarity=_Egg.Rarity(e.mutation), value=_Egg.Value(e.mutation, e.nestScale, e.mutTable),
					enabled=true, uid=e.uid, farmable=e.farmable,
				})
				total = total + 1; enabledCount = enabledCount + 1
			end
		end

		-- Own base eggs (placed, already growing in your slots) — separate
		-- list for the "ESP Own Base Eggs" toggle only. Never farmed:
		-- AskFieldEggCarry targets a wild field egg's uid, not a slot name.
		local ownEggs = {}
		local slotsRoot = workspace:FindFirstChild("AreaEggSlotsClient", true)
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
					local _, tags2, weight2 = _readEggLabels(slot)
					local cat2 = mutation2 or (tags2[1] and tags2[1]:upper()) or (zone.." Egg")
					table.insert(ownEggs, {
						slot=slot, pos=pos3, cf=cf3, area=zone, cat=cat2,
						mutation=mutation2 or tags2[1], tags=tags2,
						weight=weight2, enabled=true, uid=sname, farmable=false,
					})
				end)
			end
		end

		_eggScanPromptTotal = total
		_eggScanPromptEnabled = enabledCount
		cachedEggs = eggs
		_ownBaseEggs = ownEggs
		task.wait(0.5)
	end
end)

-- ============================================================
-- PALETTE — same as Moon Hub (exact same RGB values, read straight
-- from moon_hub_patched.lua): pure black background, blue accent
-- 90-160-255, same greys/silvers, same 4-tone "living" gradient.
-- ============================================================
-- NOTE: grouped into ONE table (instead of ~25 separate locals) —
-- Lua 5.1 caps a function (so the whole root chunk) at 200 active
-- locals; with ~200 features/handlers in this hub, every local saved
-- counts. Every color stays accessible via C.NAME throughout the file
-- (mechanical replacement of C_NAME -> C.NAME).
local C = {
	BG       = Color3.fromRGB(0,0,0),
	HEADER   = Color3.fromRGB(0,0,0),
	ROW      = Color3.fromRGB(0,0,0),     -- Moon Hub rows: black + 0.35 BackgroundTransparency (not a flat color)
	BORDER   = Color3.fromRGB(40,46,58),
	WHITE    = Color3.fromRGB(255,255,255),
	MOON     = Color3.fromRGB(90,160,255),   -- main accent (= my old C.ACCENT)
	MOON2    = Color3.fromRGB(160,200,255),  -- light accent (= my old C.ACCENT2)
	MOONTEXT = Color3.fromRGB(0,10,20),
	DIM      = Color3.fromRGB(110,120,140),
	TABIDLE  = Color3.fromRGB(160,200,255),
	ON_BG    = Color3.fromRGB(20,45,80),
	OFF_BG   = Color3.fromRGB(0,0,0),
	SILVER   = Color3.fromRGB(210,222,240),
	SILVER2  = Color3.fromRGB(140,165,210),
	RED      = Color3.fromRGB(220,60,60),
	GREEN    = Color3.fromRGB(60,220,120),
	YELLOW   = Color3.fromRGB(230,200,90),   -- not in Moon Hub by default, added for diagnostics
	GOLD     = Color3.fromRGB(255,200,60),   -- same, for ESP's rare mutations
	DEEP1    = Color3.fromRGB(4,7,16),
	DEEP2    = Color3.fromRGB(14,28,58),
	DEEP3    = Color3.fromRGB(40,80,165),
	DEEP4    = Color3.fromRGB(90,150,255),
}
-- Alias for compatibility with the rest of the file (names already used everywhere)
C.ACCENT, C.ACCENT2 = C.MOON, C.MOON2
C.TRACKOFF = C.OFF_BG

-- ============================================================
-- STATE — all of St is persisted (simple values only)
-- ============================================================
local St = {
	stayOnTreadmill  = true,
	instantSteal     = false,
	winSteal         = false,
	winEvents        = false,
	autoRerollLab    = false,
	autoFarm         = false,
	autoHatch        = false,
	autoEquip        = false,
	autoClaim        = false,
	autoUpgradeTM    = false,
	autoRunTreadmill = false,
	antiRagdoll      = false,
	fly              = false,
	esp              = false,
	antiAFK          = false,
	antiTrap         = false,
	fullbright       = false,
	fpsBoost         = false,
	clickTp          = false,
	infJump          = false,
	speedOn          = false,
	floatLocked      = false,
	speed            = 350,
	flySpeed         = 50,
	fov              = 70,
	guiVisible       = true,
	farmZone         = "",
	-- New automation features
	autoPlace        = false,
	autoTreadmill2   = false,
	autoSellPet      = false,
	autoSellEgg      = false,
	autoFuse         = false,
	autoFavorite     = false,
	autoLab          = false,
	autoMech         = false,
	autoBuyTrail     = false,
	autoUpgradeBase  = false,
	antiGuard        = false,
	instantPrompts   = false,
	invisibility     = false,
	espGuards        = false,
	espPlayers       = false,
	autoHitNearest   = false,
	autoHitAura      = false,
	keepMutatedSell  = true,
	skipMutatedFuse  = true,

	-- Auto Steal filters (Chilli Hub "Auto Steal" section)
	stealMinRarity   = 0,
	stealMinValueK   = 0,
	stealPriority     = "Best Rarity",
	stealTargetEggs  = {},
	stealTweenPct    = 100,
	stealCarryPct    = 100,
	showFarmPath     = true,
	stealMissingLab  = false,

	-- Dr Scramble Event (Auto Use Scrambled Mutation)
	autoUseScrambled = false,
	mutationMinRarity = 0,
	mutationMinValueK = 0,
	mutationPriority = "Highest Value",
	mutationTargetEggs = {},

	-- Auto Place Egg filters
	placeRule        = "Always",
	placeOrder       = "Highest Value",
	placeRarities    = {},
	placeSpecificEggs = {},
	placeMinValueK   = 0,

	-- Auto Hatch filters
	hatchMinRarity   = 0,
	hatchMinValueK   = 0,
	hatchSpecificEggs = {},

	-- Auto Sell filters
	sellPetRule      = "Rarity Only",
	sellPetMaxRarity = 0,
	sellPetValueK    = 0,
	sellPetBlacklist = {},
	sellEggRule      = "Rarity Only",
	sellEggMaxRarity = 0,
	sellEggValueK    = 0,
	sellEggBlacklist = {},

	-- Auto Fuse filters
	fusePriorityMode = "Lowest Rarity First",
	fusePetsToUse    = "Lowest To Highest",
	fuseMaxRarity    = 0,
	fuseSpecificSpecies = {},
	fuseEjectIncomplete = true,

	-- Auto Favorite filters
	favoriteRule     = "Match All",
	favoriteMinRarity = 0,
	favoriteMutations = {},
	favoriteMinValueK = 0,
	favoriteAlwaysSpecies = {},
	autoFavoriteEquipped = false,
	autoUnfavoriteEquipped = false,

	-- Combat
	hitSweep         = 20,

	-- ESP
	espFixedSize     = false,
	espOwnBase       = true,
	espMinRarity     = 0,
	espShowInfo      = {Icon=true, Name=true, Value=true},
	espMinValueK     = 0,
	espEggSizePct    = 75,
	espGuardSizePct  = 100,
	espLostParts     = false,
	espPlayerInfo    = false,
	espPlayerSizePct = 100,

	-- Misc
	fpsCap           = 0,
	optimizer        = false,
	fpsPingHud       = false,
	serverHopMode    = "Least Players",
	autoRejoin       = true,
}

-- ============================================================
-- SAVE / LOAD
-- ============================================================
-- Invisibility is never re-applied on load (it resets the character).
local CONFIG_FILE = "MoonEgg_Config.json"
local function loadConfig()
	local ok, raw = pcall(function()
		if isfile and isfile(CONFIG_FILE) then return readfile(CONFIG_FILE) end
		return nil
	end)
	if not ok or not raw then return nil end
	local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
	if ok2 and type(data) == "table" then return data end
	return nil
end
local _savedConfig = loadConfig()
if _savedConfig then
	for k, v in pairs(_savedConfig) do
		if St[k] ~= nil and type(v) == type(St[k]) then St[k] = v end
	end
end
local _toggleRegistry = {}
local _saveDebounce = false
local function saveConfig()
	if _saveDebounce then return end
	_saveDebounce = true
	task.delay(0.5, function()
		pcall(function() if writefile then writefile(CONFIG_FILE, HttpService:JSONEncode(St)) end end)
		_saveDebounce = false
	end)
end

-- ============================================================
-- MOVEMENT CORE — ported from Chilli Hub (aide_3), same techniques:
--   MV.WalkSpeed  ~1120  legit pace = Humanoid.WalkSpeed capped by the
--                        Speed-power stat (TreadmillUtil), never faster
--   MV.Step       ~3083  velocity steering (3D, gravity-compensated,
--                        stuck nudge) run on RunService.PreSimulation
--   MV.GodMode    ~1795  noclip + no ragdoll/fall states during a steal
--   MV.carry      ~8067  EggState.CarryChanged (IsCarrying/Uid/
--                        SpeedMultiplier), FieldEggRedeemVerdict
--   MV.Shield     ~1002  Humanoid Swap, reference-counted by reason
--   Speed Boost   ~15277 Heartbeat velocity boost
-- Auto Steal speeds are ratios of the legit pace (Tween Speed 50-120 %,
-- Carry Speed 80-120 %) — the old flat 40-350 studs/s got the delivery
-- "rewound" by the server, which is the going-backwards symptom.
-- ============================================================
local _farmMoving = false
local _farmTargetPos = nil
local _labNeeds = {}
local MV = {farming = false, riding = false}
local Steal = {force = nil, skip = {}, status = "Idle", detail = "", eggName = nil, lastCarryUid = nil}

function MV.Root()
	local ch = LP.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return r and r:IsDescendantOf(workspace) and r or nil
end
function MV.Hum()
	local ch = LP.Character
	return ch and ch:FindFirstChildOfClass("Humanoid")
end
function MV.Ragdolled()
	local num = tonumber(LP:GetAttribute("RagdollEndTime"))
	if num and num > workspace:GetServerTimeNow() then return true end
	local hum = MV.Hum()
	if hum then
		local s = hum:GetState()
		return s == Enum.HumanoidStateType.Physics or s == Enum.HumanoidStateType.Ragdoll or s == Enum.HumanoidStateType.FallingDown
	end
	return false
end

MV.swap = {Original = nil, Clone = nil, Links = {}}
function MV.WalkSpeed()
	local hum = MV.Hum()
	local ws = hum and hum.WalkSpeed or 16
	local orig = MV.swap.Original
	if orig and orig.Health > 0 then ws = math.min(ws, orig.WalkSpeed) end
	local ok, res = pcall(function()
		local ls = LP:FindFirstChild("leaderstats")
		ls = ls and ls:FindFirstChild("Speed")
		return ls and _M.TreadmillUtil and _M.TreadmillUtil.SpeedPowerToWalkSpeed(ls.Value) or nil
	end)
	if ok and tonumber(res) and res > 0 then return math.min(ws, res) end
	return ws
end

-- exact port of Chilli Hub's velocity step (returns true once within 0.5 stud)
function MV.Step(root, target, speed, dt, st)
	local delta = target - root.Position
	local mag = delta.Magnitude
	local step = math.max(dt, 1/240)
	local vel = Vector3.zero
	if mag > 0.01 then vel = delta.Unit * math.min(speed, mag / step) end
	local av = vel + Vector3.new(0, workspace.Gravity * step * 0.5, 0)
	if mag > 2 then
		if not st.mark then st.mark = mag; st.clock = 0 end
		st.clock = st.clock + dt
		if st.clock >= 0.4 then
			if st.mark - mag < speed * 0.1 then
				pcall(function() root.CFrame = root.CFrame + delta.Unit * math.min(mag, speed * step) end)
			end
			st.mark = mag; st.clock = 0
		end
	else
		st.mark = nil
	end
	pcall(function()
		root.AssemblyLinearVelocity = av
		root.AssemblyAngularVelocity = Vector3.zero
	end)
	return mag <= 0.5
end
function MV.Stop()
	local r = MV.Root()
	if r then pcall(function() r.AssemblyLinearVelocity = Vector3.zero; r.AssemblyAngularVelocity = Vector3.zero end) end
end

do
	local godStates = {
		Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Physics,
		Enum.HumanoidStateType.Seated, Enum.HumanoidStateType.PlatformStanding,
	}
	local saved, on = {}, false
	function MV.GodMode(enable)
		local ch = LP.Character
		local hum = MV.Hum()
		if not ch or not hum then return end
		if enable then
			on = true
			for _, s in ipairs(godStates) do pcall(function() hum:SetStateEnabled(s, false) end) end
			pcall(function() hum.BreakJointsOnDeath = false end)
			for _, d in ipairs(ch:GetDescendants()) do
				if d:IsA("BasePart") and saved[d] == nil then
					saved[d] = d.CanCollide
					pcall(function() d.CanCollide = false end)
				end
			end
		elseif on then
			on = false
			for _, s in ipairs(godStates) do pcall(function() hum:SetStateEnabled(s, true) end) end
			for part, cc in pairs(saved) do
				if part and part.Parent then pcall(function() part.CanCollide = cc end) end
			end
			table.clear(saved)
		end
	end
end

-- carry state (EggState.CarryChanged, exactly like Chilli Hub)
MV.carry = {on = false, uid = nil, mult = 1, area = nil, tracked = false, lastDelivered = 0, lastFailed = 0}
pcall(function()
	local cc = _M.EggState and _M.EggState.CarryChanged
	if type(cc) == "table" and type(cc.Connect) == "function" then
		cc:Connect(function(arg)
			local carrying = type(arg) == "table" and arg.IsCarrying == true
			MV.carry.on = carrying
			if carrying and type(arg.Uid) == "string" then
				MV.carry.uid = arg.Uid
				MV.carry.area = arg.AreaId
				local mult = tonumber(arg.SpeedMultiplier)
				if mult and mult > 0 then MV.carry.mult = mult end
			end
		end)
		MV.carry.tracked = true
	end
end)
pcall(function()
	local v = _getRemote("RE/EggWorld/FieldEggRedeemVerdict")
	if v and v:IsA("RemoteEvent") then v.OnClientEvent:Connect(function() MV.carry.lastDelivered = os.clock() end) end
	local a = _getRemote("RE/Alerts/Raise")
	if a and a:IsA("RemoteEvent") then
		a.OnClientEvent:Connect(function(arg)
			if type(arg) == "table" and type(arg.Text) == "string" and string.find(arg.Text, "Delivery failed", 1, true) then
				MV.carry.lastFailed = os.clock()
			end
		end)
	end
end)

-- Shield = Humanoid Swap (Chilli Hub's default shield method): the live
-- Humanoid is replaced by a clone so the speed boost is not tied to the
-- original one. Reference-counted by reason; undone when the last reason
-- goes away. Internal only — no toggle.
do
	local S = MV.swap
	local reasons, hbConn, charConn, acc = {}, nil, nil, 0
	local hooks = {}
	function MV.OnHumanoid(fn) table.insert(hooks, fn) end
	local function fireHooks() for _, fn in ipairs(hooks) do task.defer(function() pcall(fn) end) end end
	local function setControls(h)
		pcall(function()
			local ps = LP:FindFirstChild("PlayerScripts")
			local pm = ps and ps:FindFirstChild("PlayerModule")
			if pm then
				local controls = require(pm):GetControls()
				if type(controls) == "table" then controls.humanoid = h end
			end
		end)
	end
	local function refreshAnimate(ch)
		local a = ch and ch:FindFirstChild("Animate")
		if a and a:IsA("LocalScript") then task.spawn(function() a.Enabled = false; task.wait(); a.Enabled = true end) end
	end
	local function dropLinks()
		for _, l in ipairs(S.Links) do pcall(function() l:Disconnect() end) end
		table.clear(S.Links)
	end
	function MV.UndoSwap()
		dropLinks()
		local ch, orig, clone = LP.Character, S.Original, S.Clone
		S.Original = nil; S.Clone = nil
		if orig and clone and ch and orig.Parent == nil and clone.Parent == ch then
			orig.Parent = ch
			workspace.CurrentCamera.CameraSubject = orig
			setControls(orig)
			pcall(function() clone:Destroy() end)
			refreshAnimate(ch)
			fireHooks()
		end
	end
	local groundedStates = {
		[Enum.HumanoidStateType.Running] = true, [Enum.HumanoidStateType.RunningNoPhysics] = true, [Enum.HumanoidStateType.Landed] = true,
	}
	local function grounded(h)
		if not h or h.Health <= 0 or h.FloorMaterial == Enum.Material.Air then return false end
		return groundedStates[h:GetState()] == true
	end
	local function doSwap()
		local ch = LP.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end
		if S.Clone and S.Clone.Parent == ch then return end
		if not grounded(hum) then return end
		local clone = hum:Clone()
		hum.Parent = nil
		clone.Parent = ch
		workspace.CurrentCamera.CameraSubject = clone
		setControls(clone)
		refreshAnimate(ch)
		S.Original = hum; S.Clone = clone
		fireHooks()
		table.insert(S.Links, hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			if clone.Parent ~= nil then clone.WalkSpeed = hum.WalkSpeed end
		end))
		local animator, animator2 = hum:FindFirstChildOfClass("Animator"), clone:FindFirstChildOfClass("Animator")
		if animator and animator2 then
			table.insert(S.Links, animator.AnimationPlayed:Connect(function(track)
				local anim = track.Animation
				if not anim or clone.Parent == nil then return end
				local ok, t2 = pcall(function() return animator2:LoadAnimation(anim) end)
				if not ok or not t2 then return end
				pcall(function()
					t2.Priority = track.Priority; t2.Looped = track.Looped
					t2:Play(0.05, math.max(track.WeightTarget, 0.01), track.Speed)
				end)
				local c3
				c3 = track.Stopped:Connect(function() c3:Disconnect(); pcall(function() t2:Stop(0.1) end) end)
			end))
		end
		table.insert(S.Links, clone.Died:Connect(function()
			dropLinks()
			S.Original = nil; S.Clone = nil
			local ch2 = LP.Character
			if ch2 and hum.Parent == nil then
				hum.Parent = ch2
				workspace.CurrentCamera.CameraSubject = hum
				setControls(hum)
				fireHooks()
			end
			pcall(function() clone:Destroy() end)
			hum.Health = 0
		end))
	end
	local function stopShield()
		if hbConn then hbConn:Disconnect(); hbConn = nil end
		if charConn then charConn:Disconnect(); charConn = nil end
		MV.UndoSwap()
	end
	local function startShield()
		doSwap()
		acc = 0
		hbConn = RunService.Heartbeat:Connect(function(dt)
			acc = acc + dt
			local ch = LP.Character
			local placed = S.Clone and ch and S.Clone.Parent == ch
			if MV.ShieldPaused then acc = 0
			elseif (placed and 3 or 0.25) <= acc then acc = 0; doSwap() end
		end)
		charConn = LP.CharacterAdded:Connect(function(ch)
			dropLinks(); S.Original = nil; S.Clone = nil
			task.spawn(function()
				ch:WaitForChild("Humanoid", 10)
				task.wait(1)
				if hbConn and LP.Character == ch then doSwap() end
			end)
		end)
	end
	function MV.Shield(name, enable)
		reasons[name] = enable == true or nil
		if next(reasons) == nil then stopShield(); return end
		if hbConn then return end
		startShield()
	end
end

-- ============================================================
-- AUTO FARM PATH — visual trajectory beam to whatever Auto Steal is
-- currently walking toward (egg while approaching, home while carrying).
-- ============================================================
do
	local marker, att0, att1, beam = nil, nil, nil, nil
	local function ensurePathParts()
		if beam and beam.Parent then return end
		marker = Instance.new("Part")
		marker.Name = "YE_PathMarker"; marker.Size = Vector3.new(0.2,0.2,0.2)
		marker.Anchored = true; marker.CanCollide = false; marker.CanQuery = false
		marker.Transparency = 1; marker.Parent = workspace
		att1 = Instance.new("Attachment", marker)
		att0 = Instance.new("Attachment")
		att0.Name = "YE_PathOrigin"
		beam = Instance.new("Beam")
		beam.Attachment0 = att0; beam.Attachment1 = att1
		beam.Width0 = 0.35; beam.Width1 = 0.12
		beam.Color = ColorSequence.new(C.MOON2, C.MOON)
		beam.Transparency = NumberSequence.new(0.25)
		beam.FaceCamera = true
		beam.Parent = marker
	end
	RunService.Heartbeat:Connect(function()
		if not (St.showFarmPath and _farmMoving and _farmTargetPos) then
			if beam then beam.Enabled = false end
			return
		end
		local hrp = MV.Root()
		if not hrp then if beam then beam.Enabled = false end return end
		ensurePathParts()
		if att0.Parent ~= hrp then att0.Parent = hrp end
		marker.CFrame = CFrame.new(_farmTargetPos)
		beam.Enabled = true
	end)
end

-- ============================================================
-- SPEED BOOST — Chilli Hub (aide_3 ~15277-15357), unchanged logic:
-- Heartbeat, XZ velocity = MoveDirection.Unit * speed (Y kept); idle
-- input falls back to the normal walk-speed velocity; inactive while
-- stealing / riding the treadmill / sitting / ragdolled.
-- ============================================================
local startSpeed, stopSpeed
do
	local conn, boosted = nil, false
	local function resetBoost()
		if not boosted then return end
		boosted = false
		local root, hum = MV.Root(), MV.Hum()
		if not root or not hum or hum.Health <= 0 then return end
		local v = root.AssemblyLinearVelocity
		local md = hum.MoveDirection
		local flat = Vector3.new(md.X, 0, md.Z)
		local walk = flat.Magnitude > 0.001 and flat.Unit * hum.WalkSpeed or Vector3.zero
		pcall(function() root.AssemblyLinearVelocity = Vector3.new(walk.X, v.Y, walk.Z) end)
	end
	startSpeed = function()
		St.speedOn = true
		MV.Shield("speed", true)
		if conn then return end
		conn = RunService.Heartbeat:Connect(function()
			if MV.farming or MV.riding then boosted = false; return end
			local root, hum = MV.Root(), MV.Hum()
			if not root or not hum or hum.Health <= 0 or hum.Sit or hum.PlatformStand then boosted = false; return end
			local num = tonumber(LP:GetAttribute("RagdollEndTime"))
			if num and num > workspace:GetServerTimeNow() then boosted = false; return end
			local md = hum.MoveDirection
			local flat = Vector3.new(md.X, 0, md.Z)
			if flat.Magnitude <= 0.001 then resetBoost(); return end
			local vel = flat.Unit * St.speed
			local cur = root.AssemblyLinearVelocity
			pcall(function() root.AssemblyLinearVelocity = Vector3.new(vel.X, cur.Y, vel.Z) end)
			boosted = true
		end)
	end
	stopSpeed = function()
		St.speedOn = false
		if conn then conn:Disconnect(); conn = nil end
		resetBoost()
		MV.Shield("speed", false)
	end
end

-- ============================================================
-- AUTO STEAL ENGINE — target choice + run, following Chilli Hub's flow
-- (aide_3 ~6239-6490): pick target -> approach -> grab (prompt, then
-- EggState.CarryFieldEgg) -> carry home -> settle.
-- ============================================================
function Steal.Zone(area)
	if St.farmZone == "" then return true end
	if not area or area == "?" then return false end
	if area == St.farmZone then return true end
	local al, fz = area:lower(), St.farmZone:lower()
	return al:find(fz, 1, true) ~= nil or fz:find(al, 1, true) ~= nil
end

-- Sorted plan of eggs to steal (also what the Steal Panel lists).
function Steal.Plan(myPos, limit)
	local now = os.clock()
	local minVal = St.stealMinValueK * 1000
	local hasTargets = next(St.stealTargetEggs) ~= nil
	local list, forced = {}, nil
	for _, r in ipairs(cachedEggs) do
		if r.enabled and r.farmable ~= false and r.uid then
			if Steal.force and r.uid == Steal.force then
				forced = r
			elseif (Steal.skip[r.uid] or 0) <= now and Steal.Zone(r.area)
				and (r.rarity or 0) >= St.stealMinRarity and (r.value or 0) >= minVal
				and (not hasTargets or St.stealTargetEggs[r.mutation or ""] or (St.stealMissingLab and _labNeeds[r.mutation or ""])) then
				table.insert(list, r)
			end
		end
	end
	local pr = St.stealPriority
	table.sort(list, function(a, b)
		local av, bv
		if pr == "Best Rarity" then av, bv = a.rarity or 0, b.rarity or 0
		elseif pr == "Biggest Weight" then av, bv = a.scale or 0, b.scale or 0
		elseif pr == "Best Mutation" then av, bv = (a.mutTable and next(a.mutTable) and 1 or 0) + (a.tags and #a.tags or 0), (b.mutTable and next(b.mutTable) and 1 or 0) + (b.tags and #b.tags or 0)
		elseif pr == "Lowest Value" then av, bv = -(a.value or 0), -(b.value or 0)
		else av, bv = a.value or 0, b.value or 0 end
		if av ~= bv then return av > bv end
		if (a.value or 0) ~= (b.value or 0) then return (a.value or 0) > (b.value or 0) end
		if myPos then return (a.pos - myPos).Magnitude < (b.pos - myPos).Magnitude end
		return false
	end)
	if forced then table.insert(list, 1, forced) end
	if limit and #list > limit then for i = #list, limit + 1, -1 do list[i] = nil end end
	return list
end
function Steal.StealNow(uid) Steal.force = uid; Steal.skip[uid] = nil end
function Steal.Skip(uid, secs) Steal.skip[uid] = os.clock() + (secs or 30); if Steal.force == uid then Steal.force = nil end end
function Steal.Prioritize(uid) Steal.force = uid end

do
	local function setStatus2(s, d) Steal.status = s; Steal.detail = d or "" end

	local function findCarryPrompt(eggPos, maxDist)
		maxDist = maxDist or 14
		local best, bestDist = nil, maxDist
		for _, child in ipairs(workspace:GetChildren()) do
			if child.Name == "SmartPromptPart" and child:IsA("BasePart") then
				local p = child:FindFirstChild("CarryAreaEgg")
				if p and p:IsA("ProximityPrompt") then
					local d = (child.Position - eggPos).Magnitude
					if d < bestDist then bestDist = d; best = p end
				end
			end
		end
		return best
	end

	-- move until arrive/timeout/stop; runs on PreSimulation like Chilli Hub
	local function moveTo(target, getSpeed, timeout, arrive, stopFn)
		local st, done, elapsed = {}, nil, 0
		local sig = RunService.PreSimulation or RunService.Heartbeat
		local conn = sig:Connect(function(dt)
			if done ~= nil then return end
			elapsed = elapsed + dt
			local root = MV.Root()
			if not root or elapsed > timeout or not St.autoFarm or MV.Ragdolled() then done = false; return end
			if stopFn and stopFn() then done = false; return end
			_farmTargetPos = target
			local reached = MV.Step(root, target, getSpeed(), dt, st)
			if reached or (root.Position - target).Magnitude <= arrive then done = true end
		end)
		while done == nil do RunService.Heartbeat:Wait() end
		conn:Disconnect()
		return done
	end

	-- Chilli Hub grab (aide_3 ~3406-3458): prompt every 0.06s, else CarryFieldEgg
	local function grab(egg)
		local t, acc, miss = 0, 1, 0
		while t < 1.5 do
			if not St.autoFarm then return false end
			if MV.carry.on then return true end
			if acc >= 0.06 then
				acc = 0
				local prompt = findCarryPrompt(egg.pos)
				if prompt then
					miss = 0
					pcall(function() prompt.HoldDuration = 0 end)
					if fireproximityprompt then pcall(fireproximityprompt, prompt) end
				else
					miss = miss + 1
					if miss >= 4 then return MV.carry.on end
					local es = _M.EggState
					if type(es) == "table" and type(es.CarryFieldEgg) == "function" then pcall(es.CarryFieldEgg, egg.uid) end
				end
			end
			local dt = RunService.Heartbeat:Wait()
			t = t + dt; acc = acc + dt
		end
		return MV.carry.on or not MV.carry.tracked
	end

	-- Instant Steal (Chilli Hub "Line Drop" idea, simplified): short hops of
	-- one walk-pace-or-40 studs to the safe-zone line, then step over it
	local function instantHop()
		local root = MV.Root()
		if not root then return end
		local w = workspace:FindFirstChild("World") or workspace:FindFirstChild("__OBJECTS")
		w = w and w:FindFirstChild("Areas")
		w = w and w:FindFirstChild("SeparationLine")
		local isLine = w and w:IsA("BasePart")
		local lineX = isLine and w.Position.X or 552
		local lineY = isLine and w.Position.Y or 67.67
		local home = _findSafeZonePos()
		local sgn = home.X < root.Position.X and -1 or 1
		local stopX = lineX - sgn * 6
		local z = math.clamp(root.Position.Z, -425, -300)
		local hop = math.max(MV.WalkSpeed(), 40)
		local x2 = root.Position.X
		local hopY = root.Position.Y + 4
		local function place(x, y)
			local r = MV.Root()
			if not r then return end
			pcall(function()
				r.CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, math.pi / 2, 0)
				r.AssemblyLinearVelocity = Vector3.zero; r.AssemblyAngularVelocity = Vector3.zero
			end)
		end
		while math.abs(x2 - stopX) > hop and MV.carry.on and St.autoFarm do
			x2 = x2 + sgn * hop
			setStatus2("Instant Steal", "hopping home")
			local t = 0
			while t < 0.1 do place(x2, hopY); t = t + RunService.Heartbeat:Wait() end
		end
		if MV.carry.on then place(stopX, lineY + 3.35) end
	end

	local function endRun()
		_farmMoving = false; _farmTargetPos = nil
		MV.farming = false
		Steal.current = nil
		MV.Stop()
		MV.GodMode(false)
		MV.Shield("farm", false)
		local hum = MV.Hum()
		if hum then hum.PlatformStand = false end
	end
	function Steal.Abort()
		if MV.farming then endRun() end
	end

	local function runSteal(egg)
		MV.farming = true; _farmMoving = true
		MV.Shield("farm", true)
		MV.GodMode(true)
		Steal.eggName = egg.cat
	Steal.current = egg.uid
		local startedAt = os.clock()
		setStatus2("Approaching", tostring(egg.cat or "egg"))
		local walkApproach = function() return math.max(MV.WalkSpeed() * (St.stealTweenPct / 100), 16) end
		local near = moveTo(egg.pos, walkApproach, 25, 6, function() return _fieldEggNet[egg.uid] == nil and not MV.carry.on end)
		if near and St.autoFarm then
			setStatus2("Taking the egg", tostring(egg.cat or "egg"))
			if grab(egg) then
				local ag = Steal.ag
				if ag and ag.Enabled and not St.instantSteal then
					-- Chilli Hub: let Anti Guard slip past the guard first
					setStatus2("Anti Guard", "slipping past the guard")
					local w = 0
					while not ag.Busy and w < 1 and St.autoFarm do w = w + RunService.Heartbeat:Wait() end
					w = 0
					while ag.Busy and w < 30 and St.autoFarm do w = w + RunService.Heartbeat:Wait() end
				elseif St.instantSteal then
					pcall(instantHop)
				end
				-- carry it home (Chilli Hub CarryRatio 0.9 * egg SpeedMultiplier,
				-- EasyRatio 1.3, scaled by the Carry Speed slider)
				local home = _findSafeZonePos()
				local carrySpeed = function()
					local base = MV.WalkSpeed() * 0.9 * (MV.carry.mult or 1)
					return math.max(base * 1.3, 8) * (St.stealCarryPct / 100)
				end
				setStatus2("Carrying home", tostring(egg.cat or "egg"))
				local arrived = moveTo(home, carrySpeed, 45, 6, function() return MV.carry.tracked and not MV.carry.on end)
				if arrived then
					local w = 0
					while MV.carry.on and w < 3 and St.autoFarm do w = w + RunService.Heartbeat:Wait() end
				end
				setStatus2("Delivered", tostring(egg.cat or "egg"))
			else
				setStatus2("Could not take it", tostring(egg.cat or "egg"))
				Steal.skip[egg.uid] = os.clock() + 20
			end
		else
			setStatus2("Egg gone", tostring(egg.cat or "egg"))
		end
		if Steal.force == egg.uid then Steal.force = nil end
		if egg.uid then _fieldEggNet[egg.uid] = nil end
		endRun()
	end

	task.spawn(function()
		while true do
			task.wait(0.2)
			if not St.autoFarm then
				if MV.farming then endRun() end
				if Steal.status ~= "Idle" then setStatus2("Idle", "") end
			elseif not MV.farming and not MV.Ragdolled() then
				local root = MV.Root()
				if root then
					local plan = Steal.Plan(root.Position, 1)
					if plan[1] then
						local ok, err = pcall(runSteal, plan[1])
						if not ok then endRun(); setStatus2("Error", tostring(err):sub(1, 60)) end
					else
						setStatus2("Waiting", "no egg matches")
					end
				end
			end
		end
	end)
end

-- ============================================================
-- UI — DESIGN SYSTEM
-- ============================================================
local function corner(inst, r) local c = Instance.new("UICorner", inst); c.CornerRadius = UDim.new(0, r or 8); return c end
local function stroke(inst, col, th, tr)
	local s = Instance.new("UIStroke", inst)
	s.Color = col or C.BORDER; s.Thickness = th or 1; s.Transparency = tr or 0
	return s
end
local function label(parent, text, size, color, font, ax, ay)
	local l = Instance.new("TextLabel", parent)
	l.BackgroundTransparency = 1
	l.Size = size or UDim2.new(1,0,1,0)
	l.Text = text or ""; l.TextSize = 13
	l.TextColor3 = color or C.WHITE
	l.Font = font or Enum.Font.GothamMedium
	l.TextXAlignment = ax or Enum.TextXAlignment.Left
	l.TextYAlignment = ay or Enum.TextYAlignment.Center
	return l
end

-- "Living" gradients/strokes — same as Moon Hub: continuous rotation,
-- EVERY OTHER FRAME (perf), doubled increment (1.2) to compensate for
-- the half-rate and keep the same perceived speed (~0.6/frame average).
local _liveGrads, _liveStrokes = {}, {}
local _livingFrameToggle = false
RunService.RenderStepped:Connect(function()
	_livingFrameToggle = not _livingFrameToggle
	if not _livingFrameToggle then return end
	for _, g in ipairs(_liveGrads) do
		if g and g.Parent then g.Rotation = (g.Rotation + 1.2) % 360 end
	end
	for _, g in ipairs(_liveStrokes) do
		if g and g.Parent then g.Rotation = (g.Rotation + 1.2) % 360 end
	end
end)
-- Moon Hub's addLivingTextGradient: DEEP4 -> DEEP3 -> DEEP4 -> DEEP3 -> DEEP4
local function liveGrad(inst)
	local g = Instance.new("UIGradient", inst)
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    C.DEEP4), ColorSequenceKeypoint.new(0.25, C.DEEP3),
		ColorSequenceKeypoint.new(0.5,  C.DEEP4), ColorSequenceKeypoint.new(0.75, C.DEEP3),
		ColorSequenceKeypoint.new(1,    C.DEEP4),
	})
	table.insert(_liveGrads, g); return g
end
-- Moon Hub's addLivingStroke: DEEP3 base stroke + inner gradient
-- DEEP1 -> DEEP2 -> DEEP1 -> DEEP2 -> DEEP1
local function addLivingStroke(parent, thickness)
	local s = Instance.new("UIStroke", parent)
	s.Color = C.DEEP3; s.Thickness = thickness or 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local g = Instance.new("UIGradient", s)
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    C.DEEP1), ColorSequenceKeypoint.new(0.25, C.DEEP2),
		ColorSequenceKeypoint.new(0.5,  C.DEEP1), ColorSequenceKeypoint.new(0.75, C.DEEP2),
		ColorSequenceKeypoint.new(1,    C.DEEP1),
	})
	table.insert(_liveStrokes, g); return s
end
-- Moon Hub's makeDivider: 1px DEEP3 line + living gradient, between every row
local function makeDivider(page)
	local d = Instance.new("Frame", page)
	d.Size = UDim2.new(1,-12,0,1)
	d.BackgroundColor3 = C.DEEP3
	d.BorderSizePixel = 0
	liveGrad(d)
	return d
end

-- Section header — visual grouping for a block of rows, collapsible
-- like Chilli Hub's own CreateSection({Expanded=...}). With as many
-- widgets as the full filter set now has per tab, an accordion is
-- what keeps the panel scannable instead of one long scroll.
-- Members are collected via page.ChildAdded from the moment a header
-- is created until the next one replaces it — every widget helper
-- (makeRow/makeSlider/makeCarousel/makeMultiSelect/makeButton/
-- makeDivider) already parents its root Frame straight to `page`, so
-- no call site elsewhere needs to change for this to work.
local _sectionCollectors = {}
local function sectionHeader(page, text, startCollapsed)
	local prev = _sectionCollectors[page]
	if prev and prev.conn then prev.conn:Disconnect() end

	local wrap = Instance.new("Frame", page)
	wrap.Size = UDim2.new(1,-12,0,20)
	wrap.BackgroundTransparency = 1

	local accent = Instance.new("Frame", wrap)
	accent.Size = UDim2.new(0,3,0,11)
	accent.Position = UDim2.new(0,2,0.5,-5)
	accent.BackgroundColor3 = C.MOON
	accent.BorderSizePixel = 0
	corner(accent, 2)

	local lbl = label(wrap, text:upper(), UDim2.new(1,-30,1,0), C.DIM, Enum.Font.GothamBold)
	lbl.TextSize = 9
	lbl.Position = UDim2.new(0,12,0,0)

	local arrow = label(wrap, "▾", UDim2.new(0,16,1,0), C.DIM, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
	arrow.Position = UDim2.new(1,-18,0,0)
	arrow.TextSize = 10

	local btn = Instance.new("TextButton", wrap)
	btn.Size = UDim2.new(1,0,1,0); btn.BackgroundTransparency = 1; btn.Text = ""

	local members = {}
	local collector = { members = members }
	collector.conn = page.ChildAdded:Connect(function(child)
		table.insert(members, child)
	end)
	_sectionCollectors[page] = collector

	local collapsed = startCollapsed == true
	local function apply()
		for _, m in ipairs(members) do
			pcall(function() m.Visible = not collapsed end)
		end
		arrow.Text = collapsed and "▸" or "▾"
	end
	btn.MouseButton1Click:Connect(function()
		collapsed = not collapsed
		apply()
	end)
	if collapsed then task.defer(apply) end

	return wrap
end

-- "Pill" switch: pill 40x20 (ON = C.ON_BG, OFF = C.OFF_BG, 0.1
-- transparency) + living stroke + 14x14 knob (ON = C.WHITE on the
-- right, OFF = C.SILVER2 on the left) + breathing glow (UIStroke
-- thickness 2.5, C.MOON color, Transparency oscillating 0.35<->0.85
-- every 0.9s, active only when ON).
local function makeSwitch(parent, initial)
	local pill = Instance.new("Frame", parent)
	pill.Size = UDim2.new(0,40,0,20)
	pill.BackgroundColor3 = initial and C.ON_BG or C.OFF_BG
	pill.BackgroundTransparency = 0.1
	pill.BorderSizePixel = 0
	corner(pill, 10)
	addLivingStroke(pill, 1)

	local glow = Instance.new("UIStroke", pill)
	glow.Thickness = 2.5; glow.Color = C.MOON; glow.Transparency = 1
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local _glowTween = nil
	local function stopGlow()
		if _glowTween then _glowTween:Cancel(); _glowTween = nil end
		glow.Transparency = 1
	end
	local function startGlow()
		if _glowTween then return end
		glow.Transparency = 0.35
		_glowTween = TweenService:Create(glow,
			TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{Transparency = 0.85})
		_glowTween:Play()
	end

	local knob = Instance.new("Frame", pill)
	knob.Size = UDim2.new(0,14,0,14)
	knob.Position = initial and UDim2.new(1,-17,0.5,-7) or UDim2.new(0,3,0.5,-7)
	knob.BackgroundColor3 = initial and C.WHITE or C.SILVER2
	knob.BorderSizePixel = 0
	corner(knob, 7)

	local btn = Instance.new("TextButton", pill)
	btn.Size = UDim2.new(1,0,1,0); btn.BackgroundTransparency = 1; btn.Text = ""

	local function setState(on)
		TweenService:Create(pill, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{BackgroundColor3 = on and C.ON_BG or C.OFF_BG}):Play()
		TweenService:Create(knob, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{Position = on and UDim2.new(1,-17,0.5,-7) or UDim2.new(0,3,0.5,-7),
			 BackgroundColor3 = on and C.WHITE or C.SILVER2}):Play()
		if on then startGlow() else stopGlow() end
	end
	if initial then startGlow() end
	return pill, btn, setState
end

-- Toggle row (dark background + 0.35 transparency, 0.15 on hover;
-- living stroke; living-gradient label; knob + breathing glow; a
-- divider after each row). Registers itself for post-load
-- restoration/activation (_toggleRegistry) and saves on every click.
local function makeRow(page, key, displayName, onToggle)
	local row = Instance.new("Frame", page)
	row.Size = UDim2.new(1,-12,0,28)
	row.BackgroundColor3 = C.ROW
	row.BackgroundTransparency = 0.35
	row.BorderSizePixel = 0
	corner(row, 10)
	addLivingStroke(row, 1)
	local pad = Instance.new("UIPadding", row)
	pad.PaddingLeft = UDim.new(0,10); pad.PaddingRight = UDim.new(0,10)

	row.MouseEnter:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.1), {BackgroundTransparency = 0.15}):Play()
	end)
	row.MouseLeave:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.1), {BackgroundTransparency = 0.35}):Play()
	end)

	local nameLbl = label(row, displayName, UDim2.new(1,-62,1,0), C.WHITE, Enum.Font.GothamBold)
	nameLbl.TextSize = 10.5
	liveGrad(nameLbl)

	local pill, btn, setSwitch = makeSwitch(row, key and St[key] or false)
	pill.Position = UDim2.new(1,-54,0.5,-10)
	pill.AnchorPoint = Vector2.new(0,0)

	local function refresh() setSwitch(St[key]) end
	refresh()

	if key then _toggleRegistry[key] = onToggle end

	btn.MouseButton1Click:Connect(function()
		St[key] = not St[key]
		refresh()
		if onToggle then pcall(onToggle, St[key]) end
		saveConfig()
	end)
	makeDivider(page)
	return row, btn, refresh
end

-- Slider — gradient track + thumb, value shown in a tabular-ish format.
local function makeSlider(page, key, displayName, minV, maxV, fmt)
	local row = Instance.new("Frame", page)
	row.Size = UDim2.new(1,-12,0,40)
	row.BackgroundColor3 = C.ROW
	row.BackgroundTransparency = 0.35
	row.BorderSizePixel = 0; corner(row, 10)
	addLivingStroke(row, 1)
	local pad = Instance.new("UIPadding", row)
	pad.PaddingLeft = UDim.new(0,10); pad.PaddingRight = UDim.new(0,10)

	local nameLbl = label(row, displayName, UDim2.new(0.6,0,0,18), C.WHITE, Enum.Font.GothamMedium)
	nameLbl.TextSize = 11; nameLbl.Position = UDim2.new(0,0,0,3)

	local valLbl = label(row, "", UDim2.new(0.4,0,0,18), C.ACCENT2, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
	valLbl.TextSize = 11; valLbl.Position = UDim2.new(0.6,0,0,3)

	local track = Instance.new("Frame", row)
	track.Size = UDim2.new(1,0,0,5)
	track.Position = UDim2.new(0,0,1,-11)
	track.BackgroundColor3 = C.TRACKOFF
	track.BorderSizePixel = 0; corner(track, 3)

	local fill = Instance.new("Frame", track)
	fill.Size = UDim2.new(0,0,1,0)
	fill.BackgroundColor3 = C.ACCENT
	fill.BorderSizePixel = 0; corner(fill, 3)
	local fillGrad = Instance.new("UIGradient", fill)
	fillGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, C.DEEP2), ColorSequenceKeypoint.new(1, C.ACCENT2)})

	local thumb = Instance.new("Frame", track)
	thumb.Size = UDim2.new(0,12,0,12)
	thumb.AnchorPoint = Vector2.new(0.5,0.5)
	thumb.BackgroundColor3 = C.WHITE
	thumb.BorderSizePixel = 0; corner(thumb, 6)
	stroke(thumb, C.ACCENT, 1.5)

	local function setVal(v, skipSave)
		v = math.clamp(math.floor(v), minV, maxV)
		St[key] = v
		local t = (v-minV)/(maxV-minV)
		fill.Size = UDim2.new(t,0,1,0)
		thumb.Position = UDim2.new(t,0,0.5,0)
		valLbl.Text = fmt and string.format(fmt, v) or tostring(v)
		if not skipSave then saveConfig() end
	end
	setVal(St[key] or minV, true)

	local dragging = false
	track.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end)
	UIS.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	UIS.InputChanged:Connect(function(inp)
		if not dragging then return end
		if inp.UserInputType ~= Enum.UserInputType.MouseMovement and inp.UserInputType ~= Enum.UserInputType.Touch then return end
		local abs, sz = track.AbsolutePosition, track.AbsoluteSize
		local rel = math.clamp((inp.Position.X - abs.X) / sz.X, 0, 1)
		setVal(minV + (maxV-minV)*rel)
	end)
	makeDivider(page)
	return row, setVal
end

-- Simple action button (no toggle, just a click) — same row dressing
-- as makeRow (0.35 transparency, rounded corners, living stroke) for a
-- consistent look throughout.
local function makeButton(page, displayName, btnText, onClick, danger)
	local row = Instance.new("Frame", page)
	row.Size = UDim2.new(1,-12,0,28)
	row.BackgroundColor3 = C.ROW; row.BackgroundTransparency = 0.35
	row.BorderSizePixel = 0; corner(row, 10)
	addLivingStroke(row, 1)
	local pad = Instance.new("UIPadding", row)
	pad.PaddingLeft = UDim.new(0,10); pad.PaddingRight = UDim.new(0,10)
	label(row, displayName, UDim2.new(1,-60,1,0), C.WHITE, Enum.Font.GothamMedium).TextSize = 11
	local btn = Instance.new("TextButton", row)
	btn.Size = UDim2.new(0,52,0,18)
	btn.Position = UDim2.new(1,-52,0.5,-9)
	btn.BackgroundColor3 = danger and Color3.fromRGB(58,20,20) or Color3.fromRGB(20,32,54)
	btn.TextColor3 = danger and C.RED or C.ACCENT2
	btn.Text = btnText; btn.TextSize = 9.5; btn.Font = Enum.Font.GothamBold
	btn.BorderSizePixel = 0; corner(btn, 6)
	if onClick then btn.MouseButton1Click:Connect(onClick) end
	makeDivider(page)
	return row, btn
end

-- Swipeable option carousel: a centered card showing the current choice,
-- with previous/next arrow buttons, real drag-to-swipe (touch or mouse),
-- and a dot-page indicator underneath. Used to pick one of many named
-- options (islands, rarity tiers) without a cramped button grid.
local function makeCarousel(parent, titleText, options, labels, initialValue, onChange)
	local titleLbl2 = label(parent, titleText:upper(), UDim2.new(1,0,0,12), C.DIM, Enum.Font.GothamBold)
	titleLbl2.TextSize = 9

	local wrap = Instance.new("Frame", parent)
	wrap.Size = UDim2.new(1,0,0,30)
	wrap.Position = UDim2.new(0,0,0,13)
	wrap.BackgroundTransparency = 1

	local idx = 1
	for i, v in ipairs(options) do if v == initialValue then idx = i; break end end

	local function arrowBtn(dir)
		local b = Instance.new("TextButton", wrap)
		b.Size = UDim2.new(0,22,1,0)
		b.Position = dir < 0 and UDim2.new(0,0,0,0) or UDim2.new(1,-22,0,0)
		b.BackgroundColor3 = Color3.fromRGB(12,18,32)
		b.Text = dir < 0 and "<" or ">"
		b.TextColor3 = C.ACCENT2; b.TextSize = 13; b.Font = Enum.Font.GothamBold
		b.BorderSizePixel = 0; corner(b, 6)
		return b
	end
	local prevBtn = arrowBtn(-1)
	local nextBtn = arrowBtn(1)

	local card = Instance.new("Frame", wrap)
	card.Size = UDim2.new(1,-52,1,0)
	card.Position = UDim2.new(0,26,0,0)
	card.BackgroundColor3 = Color3.fromRGB(12,18,32)
	card.BorderSizePixel = 0
	corner(card, 6)
	addLivingStroke(card, 1)
	local cardLbl = label(card, labels[idx], UDim2.new(1,0,1,0), C.WHITE, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	cardLbl.TextSize = 11

	local dots = Instance.new("Frame", parent)
	dots.Size = UDim2.new(1,0,0,6)
	dots.Position = UDim2.new(0,0,0,45)
	dots.BackgroundTransparency = 1
	local dotList = Instance.new("UIListLayout", dots)
	dotList.FillDirection = Enum.FillDirection.Horizontal
	dotList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dotList.Padding = UDim.new(0,3)
	local dotObjs = {}
	for i in ipairs(options) do
		local d = Instance.new("Frame", dots)
		d.Size = UDim2.new(0,4,0,4)
		d.BackgroundColor3 = C.DIM
		d.BorderSizePixel = 0; corner(d, 2)
		dotObjs[i] = d
	end

	local function refresh()
		cardLbl.Text = labels[idx]
		for i, d in ipairs(dotObjs) do
			d.BackgroundColor3 = (i == idx) and C.MOON or C.DIM
		end
	end
	refresh()

	local function goTo(newIdx)
		idx = ((newIdx - 1) % #options) + 1
		refresh()
		if onChange then onChange(options[idx]) end
	end
	prevBtn.MouseButton1Click:Connect(function() goTo(idx - 1) end)
	nextBtn.MouseButton1Click:Connect(function() goTo(idx + 1) end)

	-- Real drag-swipe on the card itself.
	local dragging, startX, baseX = false, 0, 0
	card.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			dragging = true; startX = inp.Position.X; baseX = card.Position.X.Offset
		end
	end)
	UIS.InputChanged:Connect(function(inp)
		if not dragging then return end
		if inp.UserInputType ~= Enum.UserInputType.MouseMovement and inp.UserInputType ~= Enum.UserInputType.Touch then return end
		local delta = inp.Position.X - startX
		card.Position = UDim2.new(0, baseX + math.clamp(delta, -30, 30), 0, 0)
	end)
	UIS.InputEnded:Connect(function(inp)
		if not dragging then return end
		if inp.UserInputType ~= Enum.UserInputType.MouseButton1 and inp.UserInputType ~= Enum.UserInputType.Touch then return end
		dragging = false
		local delta = inp.Position.X - startX
		card.Position = UDim2.new(0, baseX, 0, 0)
		if delta > 28 then goTo(idx - 1)
		elseif delta < -28 then goTo(idx + 1) end
	end)

	return wrap
end

-- ============================================================
-- CONSTRUCTION DE L'INTERFACE
-- ============================================================
local gui = Instance.new("ScreenGui")
gui.Name = "MoonEggGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = LP.PlayerGui end

-- Main window — widened/heightened from the original compact 248x268:
-- the full Chilli Hub filter set (rarity dropdowns, multi-selects,
-- value sliders) needs more breathing room per row and a lot more
-- rows overall than the base yslemEgg feature set did. Still small
-- enough for a phone screen, scrolls for the rest. Spawns centered.
local WIN_W, WIN_H = 268, 340
local main = Instance.new("Frame", gui)
main.Name = "Main"
main.Size = UDim2.new(0,WIN_W,0,WIN_H)
main.Position = UDim2.new(0.5,-WIN_W/2,0.5,-WIN_H/2)
main.BackgroundColor3 = C.BG
main.BorderSizePixel = 0
main.ClipsDescendants = true
corner(main, 20)
stroke(main, C.BORDER, 1.5)
local mainShadow = Instance.new("UIStroke", main)
mainShadow.Color = C.ACCENT; mainShadow.Thickness = 1; mainShadow.Transparency = 0.85

-- Header
local header = Instance.new("Frame", main)
header.Size = UDim2.new(1,0,0,42)
header.BackgroundColor3 = C.BG
header.BorderSizePixel = 0
corner(header, 20)

-- Moon badge — procedural crescent (a moon-colored disc with a
-- darker disc offset over it), not an external image: no asset id to
-- go stale or fail to load, same trick the rest of the UI already
-- uses for every other visual (gradients/strokes, no images at all).
do
	local moonBadge = Instance.new("Frame", header)
	moonBadge.Size = UDim2.new(0,20,0,20)
	moonBadge.Position = UDim2.new(0,12,0.5,-10)
	moonBadge.BackgroundColor3 = C.MOON2
	moonBadge.BorderSizePixel = 0
	moonBadge.ClipsDescendants = true
	corner(moonBadge, 10)
	local moonShade = Instance.new("Frame", moonBadge)
	moonShade.Size = UDim2.new(0,20,0,20)
	moonShade.Position = UDim2.new(0,6,0,-4)
	moonShade.BackgroundColor3 = C.BG
	moonShade.BorderSizePixel = 0
	corner(moonShade, 10)
end

local titleLbl = Instance.new("TextLabel", header)
titleLbl.BackgroundTransparency = 1
titleLbl.Size = UDim2.new(1,-72,1,0)
titleLbl.Position = UDim2.new(0,38,0,0)
titleLbl.Text = "MoonEgg"
titleLbl.TextSize = 14
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.TextYAlignment = Enum.TextYAlignment.Center
liveGrad(titleLbl)

local closeBtn = Instance.new("TextButton", header)
closeBtn.Size = UDim2.new(0,20,0,20)
closeBtn.Position = UDim2.new(1,-28,0.5,-10)
closeBtn.BackgroundColor3 = Color3.fromRGB(58,20,20)
closeBtn.Text = "✕"; closeBtn.TextSize = 11
closeBtn.TextColor3 = C.RED; closeBtn.Font = Enum.Font.GothamBold
closeBtn.BorderSizePixel = 0; corner(closeBtn, 6)

local minBtn = Instance.new("TextButton", header)
minBtn.Size = UDim2.new(0,20,0,20)
minBtn.Position = UDim2.new(1,-52,0.5,-10)
minBtn.BackgroundColor3 = Color3.fromRGB(24,26,35)
minBtn.Text = "–"; minBtn.TextSize = 13
minBtn.TextColor3 = C.ACCENT2; minBtn.Font = Enum.Font.GothamBold
minBtn.BorderSizePixel = 0; corner(minBtn, 6)

local sep = Instance.new("Frame", main)
sep.Size = UDim2.new(1,-24,0,1)
sep.Position = UDim2.new(0,12,0,42)
sep.BackgroundColor3 = C.BORDER; sep.BorderSizePixel = 0

-- Tab bar — full pill for the active tab (C.MOON / C.MOONTEXT text),
-- semi-transparent for inactive ones (18,22,30 @ 0.5 / C.TABIDLE text),
-- living stroke, click flash transition.
local TAB_Y = 48
local tabBar = Instance.new("Frame", main)
tabBar.Size = UDim2.new(1,0,0,28)
tabBar.Position = UDim2.new(0,0,0,TAB_Y)
tabBar.BackgroundTransparency = 1
local tabList = Instance.new("UIListLayout", tabBar)
tabList.FillDirection = Enum.FillDirection.Horizontal
tabList.HorizontalAlignment = Enum.HorizontalAlignment.Center
tabList.VerticalAlignment = Enum.VerticalAlignment.Center
tabList.Padding = UDim.new(0,6)

local TABS = {"Farm","Speed","Visual","Misc"}
-- Small procedural accent dot per tab (no image assets) — just enough
-- to give each tab a distinct identity at a glance.
local TAB_DOT = {Farm = C.GREEN, Speed = C.MOON, Visual = C.GOLD, Misc = C.SILVER2}
local tabBtns, tabFlashes = {}, {}
for _, name in ipairs(TABS) do
	local btn = Instance.new("TextButton", tabBar)
	btn.Size = UDim2.new(0,46,0,24)
	btn.BackgroundColor3 = Color3.fromRGB(18,22,30)
	btn.BackgroundTransparency = 0.5
	btn.Text = name; btn.TextSize = 10
	btn.TextColor3 = C.TABIDLE; btn.Font = Enum.Font.GothamBold
	btn.BorderSizePixel = 0
	corner(btn, 9)
	addLivingStroke(btn, 1)
	local dot = Instance.new("Frame", btn)
	dot.Size = UDim2.new(0,5,0,5)
	dot.Position = UDim2.new(0.5,9,0.5,-9)
	dot.BackgroundColor3 = TAB_DOT[name] or C.MOON
	dot.BorderSizePixel = 0
	corner(dot, 3)
	local flash = Instance.new("Frame", btn)
	flash.Size = UDim2.new(1,0,1,0)
	flash.BackgroundColor3 = C.WHITE
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = btn.ZIndex + 1
	corner(flash, 9)
	tabBtns[name] = btn
	tabFlashes[name] = flash
end

local CONTENT_Y = TAB_Y + 28 + 6
local contentArea = Instance.new("Frame", main)
contentArea.Size = UDim2.new(1,0,1,-CONTENT_Y)
contentArea.Position = UDim2.new(0,0,0,CONTENT_Y)
contentArea.BackgroundTransparency = 1
contentArea.ClipsDescendants = true

local pages = {}
for _, name in ipairs(TABS) do
	local pg = Instance.new("ScrollingFrame", contentArea)
	pg.Name = name
	pg.Size = UDim2.new(1,0,1,0)
	pg.BackgroundTransparency = 1
	pg.BorderSizePixel = 0
	pg.ScrollBarThickness = 3
	pg.ScrollBarImageColor3 = C.ACCENT
	pg.CanvasSize = UDim2.new(0,0,0,0)
	pg.AutomaticCanvasSize = Enum.AutomaticSize.Y
	pg.Visible = false
	local list = Instance.new("UIListLayout", pg)
	list.Padding = UDim.new(0,5)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	local pad = Instance.new("UIPadding", pg)
	pad.PaddingTop = UDim.new(0,4); pad.PaddingLeft = UDim.new(0,6); pad.PaddingRight = UDim.new(0,6)
	pages[name] = pg
end

-- Tab switch transition: full pill + fading flash + a slight slide-in
-- of the content.
local activeTab = nil
local function switchTab(name)
	if activeTab == name then return end
	activeTab = name
	for _, n in ipairs(TABS) do
		local on = n == name
		local btn, flash = tabBtns[n], tabFlashes[n]
		if on then
			pages[n].Visible = true
			pages[n].Position = UDim2.new(0,8,0,0)
			TweenService:Create(pages[n], TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{Position = UDim2.new(0,0,0,0)}):Play()
			TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = C.MOON, BackgroundTransparency = 0, TextColor3 = C.MOONTEXT}):Play()
			flash.BackgroundTransparency = 0.5
			TweenService:Create(flash, TweenInfo.new(0.25), {BackgroundTransparency = 1}):Play()
		else
			pages[n].Visible = false
			TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(18,22,30), BackgroundTransparency = 0.5, TextColor3 = C.TABIDLE}):Play()
		end
	end
end
for _, name in ipairs(TABS) do
	tabBtns[name].MouseButton1Click:Connect(function() switchTab(name) end)
end

-- Status bar removed — all setStatus calls are silent no-ops.
local function setStatus(_txt, _col) end

-- ============================================================
-- MULTI-SELECT OVERLAY — matches Chilli Hub's CreateMultiDropdown
-- widgets (Target Areas, Target/Place/Hatch Specific Eggs, ESP Show
-- Info, Blacklist Sell, Specific Species to Fuse, Favorite
-- Mutations/Species). The base design system has no multi-select
-- primitive, so this adds one reusable overlay in the
-- same visual language (rows, living stroke, corner radius) instead
-- of a one-off per feature.
-- ============================================================
-- Each window / tab area that can host a multi-select registers its page
-- here; the overlay is built lazily inside that host, so a picker opened in
-- the Steal Panel covers the Steal Panel (not the main window).
local _msHosts = {}
local _msOf = {}
local function _ensureMultiSelectOverlay(page)
	local h = _msHosts[page] or {frame = main, topY = CONTENT_Y}
	if _msOf[h.frame] then return _msOf[h.frame] end
	local obj = {}
	local ov = Instance.new("Frame", h.frame)
	ov.Name = "MultiSelectOverlay"
	ov.Size = UDim2.new(1,0,1,-h.topY)
	ov.Position = UDim2.new(0,0,0,h.topY)
	ov.BackgroundColor3 = C.BG
	ov.BorderSizePixel = 0
	ov.Visible = false
	ov.ZIndex = 300
	obj.ov = ov

	local head = Instance.new("Frame", ov)
	head.Size = UDim2.new(1,0,0,26)
	head.BackgroundTransparency = 1
	head.ZIndex = 301
	obj.title = label(head, "", UDim2.new(1,-56,1,0), C.WHITE, Enum.Font.GothamBold)
	obj.title.Position = UDim2.new(0,6,0,0)
	obj.title.ZIndex = 301
	obj.title.TextSize = 11.5

	local doneBtn = Instance.new("TextButton", head)
	doneBtn.Size = UDim2.new(0,46,0,20)
	doneBtn.Position = UDim2.new(1,-50,0,2)
	doneBtn.BackgroundColor3 = C.MOON
	doneBtn.Text = "Done"
	doneBtn.TextColor3 = C.MOONTEXT
	doneBtn.Font = Enum.Font.GothamBold
	doneBtn.TextSize = 10.5
	doneBtn.BorderSizePixel = 0
	doneBtn.ZIndex = 301
	corner(doneBtn, 6)
	doneBtn.MouseButton1Click:Connect(function() ov.Visible = false end)

	local list = Instance.new("ScrollingFrame", ov)
	list.Size = UDim2.new(1,0,1,-30)
	list.Position = UDim2.new(0,0,0,28)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 3
	list.ScrollBarImageColor3 = C.ACCENT
	list.CanvasSize = UDim2.new(0,0,0,0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ZIndex = 301
	local ll = Instance.new("UIListLayout", list)
	ll.Padding = UDim.new(0,3)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	obj.list = list
	_msOf[h.frame] = obj
	return obj
end


-- getOptionsFn(): -> array of option strings, re-evaluated on every open
-- (covers dynamic lists: live area names, the egg Directory, etc.).
-- selectedSet: caller-owned table, key=option -> true when selected.
-- Empty selectedSet means "match everything" — same fallback Chilli Hub
-- uses for its MultiDropdowns (`if next(sel) == nil then` -> select all).
local function makeMultiSelect(page, displayName, getOptionsFn, selectedSet, onChange, getIconFn)
	local M = _ensureMultiSelectOverlay(page)
	local row = Instance.new("Frame", page)
	row.Size = UDim2.new(1,0,0,30)
	row.BackgroundColor3 = C.ROW
	row.BackgroundTransparency = 0.35
	row.BorderSizePixel = 0
	corner(row, 8)
	addLivingStroke(row, 1)
	local lbl = label(row, displayName, UDim2.new(1,-70,1,0), C.WHITE, Enum.Font.GothamMedium)
	lbl.Position = UDim2.new(0,10,0,0)
	lbl.TextSize = 11.5
	local countLbl = label(row, "All", UDim2.new(0,56,1,0), C.MOON2, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
	countLbl.Position = UDim2.new(1,-64,0,0)
	countLbl.TextSize = 10.5

	local btn = Instance.new("TextButton", row)
	btn.Size = UDim2.new(1,0,1,0)
	btn.BackgroundTransparency = 1
	btn.Text = ""

	local function refreshCount()
		local n = 0
		for _ in pairs(selectedSet) do n = n + 1 end
		countLbl.Text = (n == 0) and "All" or tostring(n)
	end
	refreshCount()

	btn.MouseButton1Click:Connect(function()
		M.title.Text = displayName
		for _, c in ipairs(M.list:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		local opts = getOptionsFn() or {}
		for i, opt in ipairs(opts) do
			local r = Instance.new("Frame", M.list)
			r.Size = UDim2.new(1,0,0,26)
			r.BackgroundColor3 = C.ROW
			r.BackgroundTransparency = 0.35
			r.BorderSizePixel = 0
			r.ZIndex = 301
			r.LayoutOrder = i
			corner(r, 6)
			-- Real per-option icon (pet/egg image from the game's own
			-- asset directory) when the caller provides one — makes a
			-- species list scannable at a glance instead of text-only.
			local iconOff = 0
			if getIconFn then
				local iconId = getIconFn(opt)
				if iconId then
					local img = Instance.new("ImageLabel", r)
					img.Size = UDim2.fromOffset(20,20)
					img.Position = UDim2.new(0,6,0.5,-10)
					img.BackgroundTransparency = 1
					img.Image = iconId
					img.ZIndex = 302
					iconOff = 24
				end
			end
			local olbl = label(r, opt, UDim2.new(1,-40-iconOff,1,0), C.SILVER, Enum.Font.GothamMedium)
			olbl.Position = UDim2.new(0,8+iconOff,0,0)
			olbl.TextSize = 10.5
			olbl.ZIndex = 302
			local check = Instance.new("Frame", r)
			check.Size = UDim2.new(0,16,0,16)
			check.Position = UDim2.new(1,-26,0.5,-8)
			check.BackgroundColor3 = selectedSet[opt] and C.MOON or Color3.fromRGB(10,14,22)
			check.BorderSizePixel = 0
			check.ZIndex = 302
			corner(check, 4)
			addLivingStroke(check, 1)
			local rbtn = Instance.new("TextButton", r)
			rbtn.Size = UDim2.new(1,0,1,0)
			rbtn.BackgroundTransparency = 1
			rbtn.Text = ""
			rbtn.ZIndex = 303
			rbtn.MouseButton1Click:Connect(function()
				if selectedSet[opt] then selectedSet[opt] = nil else selectedSet[opt] = true end
				check.BackgroundColor3 = selectedSet[opt] and C.MOON or Color3.fromRGB(10,14,22)
				refreshCount()
				if onChange then onChange(selectedSet) end
			end)
		end
		M.ov.Visible = true
	end)

	return refreshCount
end

-- ============================================================
-- WINDOWS — the Auto Steal panel and the Events panel are their own
-- draggable / minimizable / closable windows, separate from the main
-- window. Same look as the main window (header, living stroke, pages).
-- ============================================================
local Win = {}
do
	local zTop = 20
	local HEADER_H = 32

	-- drag on the header: touch or mouse, works while the window is minimized
	function Win.Drag(handle, target)
		local dragging, dragStart, startPos = false, nil, nil
		handle.InputBegan:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
				dragging = true; dragStart = inp.Position; startPos = target.Position
			end
		end)
		UIS.InputChanged:Connect(function(inp)
			if not dragging then return end
			if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
				local d = inp.Position - dragStart
				target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end)
		UIS.InputEnded:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
	end

	-- cfg: name, title, w, h, pos (UDim2), flag (St key holding open/closed)
	function Win.Make(cfg)
		local cam = workspace.CurrentCamera
		local vpY = cam and cam.ViewportSize.Y or 600
		cfg.h = math.min(cfg.h, math.max(220, vpY - 70))
		local frame = Instance.new("Frame", gui)
		frame.Name = cfg.name
		frame.Size = UDim2.new(0, cfg.w, 0, cfg.h)
		frame.Position = cfg.pos
		frame.BackgroundColor3 = C.BG
		frame.BorderSizePixel = 0
		frame.ClipsDescendants = true
		frame.Active = true
		frame.ZIndex = zTop
		corner(frame, 16)
		stroke(frame, C.BORDER, 1.5)
		local glow = Instance.new("UIStroke", frame)
		glow.Color = C.ACCENT; glow.Thickness = 1; glow.Transparency = 0.85

		local hdr = Instance.new("Frame", frame)
		hdr.Size = UDim2.new(1, 0, 0, HEADER_H)
		hdr.BackgroundColor3 = C.BG
		hdr.BorderSizePixel = 0
		corner(hdr, 16)

		local dot = Instance.new("Frame", hdr)
		dot.Size = UDim2.new(0, 8, 0, 8)
		dot.Position = UDim2.new(0, 12, 0.5, -4)
		dot.BackgroundColor3 = cfg.dot or C.MOON
		dot.BorderSizePixel = 0
		corner(dot, 4)

		local title = Instance.new("TextLabel", hdr)
		title.BackgroundTransparency = 1
		title.Size = UDim2.new(1, -88, 1, 0)
		title.Position = UDim2.new(0, 28, 0, 0)
		title.Text = cfg.title
		title.TextSize = 12
		title.Font = Enum.Font.GothamBold
		title.TextXAlignment = Enum.TextXAlignment.Left
		liveGrad(title)

		local close = Instance.new("TextButton", hdr)
		close.Size = UDim2.new(0, 20, 0, 20)
		close.Position = UDim2.new(1, -26, 0.5, -10)
		close.BackgroundColor3 = Color3.fromRGB(58, 20, 20)
		close.Text = "✕"; close.TextSize = 11
		close.TextColor3 = C.RED; close.Font = Enum.Font.GothamBold
		close.BorderSizePixel = 0; corner(close, 6)

		local mini = Instance.new("TextButton", hdr)
		mini.Size = UDim2.new(0, 20, 0, 20)
		mini.Position = UDim2.new(1, -50, 0.5, -10)
		mini.BackgroundColor3 = Color3.fromRGB(24, 26, 35)
		mini.Text = "–"; mini.TextSize = 13
		mini.TextColor3 = C.ACCENT2; mini.Font = Enum.Font.GothamBold
		mini.BorderSizePixel = 0; corner(mini, 6)

		local sep = Instance.new("Frame", frame)
		sep.Size = UDim2.new(1, -24, 0, 1)
		sep.Position = UDim2.new(0, 12, 0, HEADER_H)
		sep.BackgroundColor3 = C.BORDER; sep.BorderSizePixel = 0

		local page = Instance.new("ScrollingFrame", frame)
		page.Name = "Page"
		page.Size = UDim2.new(1, 0, 1, -(HEADER_H + 4))
		page.Position = UDim2.new(0, 0, 0, HEADER_H + 4)
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.ScrollBarThickness = 3
		page.ScrollBarImageColor3 = C.ACCENT
		page.CanvasSize = UDim2.new(0, 0, 0, 0)
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		local list = Instance.new("UIListLayout", page)
		list.Padding = UDim.new(0, 5)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		local pad = Instance.new("UIPadding", page)
		pad.PaddingTop = UDim.new(0, 4); pad.PaddingLeft = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 6)
		pad.PaddingBottom = UDim.new(0, 8)

		local win = {frame = frame, page = page, header = hdr, listeners = {}, minimized = false, full = cfg.h}
		_msHosts[page] = {frame = frame, topY = HEADER_H + 4}

		function win.Raise()
			zTop = zTop + 1
			frame.ZIndex = zTop
		end
		function win.SetOpen(on)
			on = on == true
			frame.Visible = on
			if cfg.flag then St[cfg.flag] = on; saveConfig() end
			if on then win.Raise() end
			for _, fn in ipairs(win.listeners) do pcall(fn, on) end
		end
		function win.IsOpen() return frame.Visible end
		function win.OnChange(fn) table.insert(win.listeners, fn) end

		mini.MouseButton1Click:Connect(function()
			win.minimized = not win.minimized
			if win.minimized then
				TweenService:Create(frame, TweenInfo.new(0.2), {Size = UDim2.new(0, cfg.w, 0, HEADER_H)}):Play()
				page.Visible = false; sep.Visible = false
				mini.Text = "+"
			else
				TweenService:Create(frame, TweenInfo.new(0.2), {Size = UDim2.new(0, cfg.w, 0, win.full)}):Play()
				page.Visible = true; sep.Visible = true
				mini.Text = "–"
			end
		end)
		close.MouseButton1Click:Connect(function() win.SetOpen(false) end)
		hdr.InputBegan:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then win.Raise() end
		end)
		Win.Drag(hdr, frame)

		frame.Visible = cfg.flag and St[cfg.flag] == true or false
		return win
	end
end


-- ============================================================
-- STEAL PANEL — Chilli Hub's steal panel (aide_3 ~20860-22450): a HUD
-- panel with a red title bar + "Sort: ..." button, an "Auto Steal" and an
-- "Instant Steal" button, and one row per egg (picture, name in its rarity
-- colour, $/s, scale and weight, Steal / star buttons). Drag it by the bar.
-- ============================================================
local HUDF = Enum.Font.GothamBlack
local function hudText(parent, text, size, col, ax)
	local l = Instance.new("TextLabel", parent)
	l.BackgroundTransparency = 1
	l.Text = text; l.TextSize = size; l.Font = HUDF
	l.TextColor3 = col or C.WHITE
	l.TextXAlignment = ax or Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	local s = Instance.new("UIStroke", l)
	s.Color = Color3.new(0, 0, 0); s.Thickness = 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	return l
end
local HUD_GREEN, HUD_RED, HUD_GRAY = Color3.fromRGB(110, 235, 70), Color3.fromRGB(225, 55, 55), Color3.fromRGB(150, 150, 165)
local function hudBtn(parent, text, col, size)
	local b = Instance.new("TextButton", parent)
	b.BackgroundColor3 = col; b.BorderSizePixel = 0
	b.Text = text; b.TextSize = size or 12; b.Font = HUDF
	b.TextColor3 = C.WHITE; b.AutoButtonColor = true
	corner(b, 6)
	local st = Instance.new("UIStroke", b)
	st.Color = Color3.fromRGB(20, 60, 20); st.Thickness = 2
	local ts = Instance.new("UIStroke", b)
	ts.Color = Color3.new(0, 0, 0); ts.Thickness = 1.5
	ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ts.Name = "TextStroke"
	return b
end

local stealWin = {listeners = {}, minimized = false}
local stealSetSort
do
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
	local W, H = 300, math.min(400, math.max(230, vp.Y - 90))
	local frame = Instance.new("Frame", gui)
	frame.Name = "MoonEggSteal"
	frame.Size = UDim2.new(0, W, 0, H)
	frame.Position = UDim2.new(1, -(W + 104), 0, 60)
	frame.BackgroundColor3 = Color3.fromRGB(58, 60, 80)
	frame.BorderSizePixel = 0
	frame.Active = true
	frame.ZIndex = 20
	corner(frame, 12)
	local fst = Instance.new("UIStroke", frame)
	fst.Color = Color3.fromRGB(26, 26, 38); fst.Thickness = 3
	stealWin.frame = frame

	local hdr = Instance.new("Frame", frame)
	hdr.Size = UDim2.new(1, 0, 0, 44)
	hdr.BackgroundColor3 = Color3.fromRGB(215, 50, 50)
	hdr.BorderSizePixel = 0
	corner(hdr, 12)
	local hg = Instance.new("UIGradient", hdr)
	hg.Color = ColorSequence.new(Color3.fromRGB(235, 70, 70), Color3.fromRGB(165, 30, 40))
	hg.Rotation = 90
	local title = hudText(hdr, "Steal Panel", 20, C.WHITE)
	title.Size = UDim2.new(0.5, -8, 1, 0); title.Position = UDim2.new(0, 12, 0, 0)
	local sortBtn = hudBtn(hdr, "Sort: " .. St.stealPriority, HUD_GREEN, 13)
	sortBtn.Size = UDim2.new(0.5, -14, 0, 30); sortBtn.Position = UDim2.new(0.5, 6, 0.5, -15)

	local topRow = Instance.new("Frame", frame)
	topRow.Size = UDim2.new(1, -16, 0, 34); topRow.Position = UDim2.new(0, 8, 0, 50)
	topRow.BackgroundTransparency = 1
	local autoBtn = hudBtn(topRow, "Auto Steal: OFF", HUD_RED, 12)
	autoBtn.Size = UDim2.new(0.5, -3, 1, 0)
	local instBtn = hudBtn(topRow, "Instant Steal: OFF", HUD_RED, 12)
	instBtn.Size = UDim2.new(0.5, -3, 1, 0); instBtn.Position = UDim2.new(0.5, 3, 0, 0)

	local info = hudText(frame, "", 10, C.SILVER)
	info.Size = UDim2.new(1, -16, 0, 14); info.Position = UDim2.new(0, 10, 0, 88)

	local list = Instance.new("ScrollingFrame", frame)
	list.Size = UDim2.new(1, -12, 1, -108); list.Position = UDim2.new(0, 6, 0, 104)
	list.BackgroundTransparency = 1; list.BorderSizePixel = 0
	list.ScrollBarThickness = 4; list.ScrollBarImageColor3 = Color3.fromRGB(140, 140, 165)
	list.CanvasSize = UDim2.new(0, 0, 0, 0); list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	local ll = Instance.new("UIListLayout", list)
	ll.Padding = UDim.new(0, 5); ll.SortOrder = Enum.SortOrder.LayoutOrder
	local emptyLbl = hudText(list, "No egg matches your filters", 12, C.SILVER, Enum.TextXAlignment.Center)
	emptyLbl.Size = UDim2.new(1, 0, 0, 30); emptyLbl.LayoutOrder = 1e6

	Win.Drag(hdr, frame)
	hdr.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			frame.ZIndex = 60
		end
	end)

	function stealWin.IsOpen() return frame.Visible end
	function stealWin.OnChange(fn) table.insert(stealWin.listeners, fn) end
	function stealWin.SetOpen(on)
		frame.Visible = on == true
		St.winSteal = on == true
		saveConfig()
		for _, fn in ipairs(stealWin.listeners) do pcall(fn, on == true) end
	end
	frame.Visible = St.winSteal == true
	if (_savedConfig == nil or _savedConfig.winSteal == nil) and vp.X >= 700 then
		frame.Visible = true; St.winSteal = true
	end

	-- Sort button cycles Steal Priority (same 5 options as Chilli Hub)
	local SORTS = {"Best Rarity", "Biggest Weight", "Best Mutation", "Highest Value", "Lowest Value"}
	stealSetSort = function(v)
		St.stealPriority = v; saveConfig()
		sortBtn.Text = "Sort: " .. v
	end
	sortBtn.MouseButton1Click:Connect(function()
		local idx = table.find(SORTS, St.stealPriority) or 0
		stealSetSort(SORTS[idx % #SORTS + 1])
	end)

	local function paintToggle(btn, on, text)
		btn.Text = text .. (on and ": ON" or ": OFF")
		btn.BackgroundColor3 = on and HUD_GREEN or HUD_RED
	end
	autoBtn.MouseButton1Click:Connect(function()
		St.autoFarm = not St.autoFarm
		if not St.autoFarm then Steal.Abort() end
		saveConfig()
	end)
	instBtn.MouseButton1Click:Connect(function()
		St.instantSteal = not St.instantSteal
		saveConfig()
	end)

	local function short(n)
		n = tonumber(n) or 0
		local a = math.abs(n)
		if a >= 1e12 then return string.format("%.1fT", n / 1e12) end
		if a >= 1e9 then return string.format("%.1fB", n / 1e9) end
		if a >= 1e6 then return string.format("%.1fM", n / 1e6) end
		if a >= 1e3 then return string.format("%.0fK", n / 1e3) end
		return string.format("%d", n)
	end
	local function commas(n)
		local s = string.format("%.0f", n)
		local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
		return (out:gsub("^,", ""))
	end
	local function weightText(cat, scale)
		local kg = _Egg.WeightKg(cat, scale)
		if not kg then return "" end
		return (kg >= 1000 and commas(kg) or string.format("%.2f", kg)) .. " Kg"
	end

	local rows = {}
	local function buildRow()
		local r = {}
		local f = Instance.new("Frame", list)
		f.Size = UDim2.new(1, -6, 0, 64)
		f.BackgroundColor3 = Color3.fromRGB(72, 74, 96)
		f.BorderSizePixel = 0
		corner(f, 8)
		r.stroke = Instance.new("UIStroke", f)
		r.stroke.Color = Color3.fromRGB(28, 28, 42); r.stroke.Thickness = 2
		r.frame = f
		r.icon = Instance.new("ImageLabel", f)
		r.icon.Size = UDim2.fromOffset(52, 52); r.icon.Position = UDim2.new(0, 6, 0.5, -26)
		r.icon.BackgroundTransparency = 1; r.icon.ScaleType = Enum.ScaleType.Fit
		r.name = hudText(f, "", 14, C.WHITE)
		r.name.Size = UDim2.new(1, -170, 0, 18); r.name.Position = UDim2.new(0, 64, 0, 5)
		r.value = hudText(f, "", 12, Color3.fromRGB(120, 255, 90))
		r.value.Size = UDim2.new(1, -170, 0, 16); r.value.Position = UDim2.new(0, 64, 0, 24)
		r.detail = hudText(f, "", 11, Color3.fromRGB(95, 170, 255))
		r.detail.Size = UDim2.new(1, -170, 0, 16); r.detail.Position = UDim2.new(0, 64, 0, 41)
		r.steal = hudBtn(f, "Steal", HUD_GREEN, 15)
		r.steal.Size = UDim2.new(0, 68, 0, 34); r.steal.Position = UDim2.new(1, -108, 0.5, -17)
		r.star = hudBtn(f, utf8.char(9733), HUD_GRAY, 16)
		r.star.Size = UDim2.new(0, 34, 0, 34); r.star.Position = UDim2.new(1, -38, 0.5, -17)
		r.star.TextColor3 = C.WHITE
		r.skip = Instance.new("TextButton", f)
		r.skip.Size = UDim2.new(0, 16, 0, 16); r.skip.Position = UDim2.new(1, -20, 0, 2)
		r.skip.BackgroundTransparency = 1; r.skip.Text = "x"; r.skip.TextSize = 12
		r.skip.Font = HUDF; r.skip.TextColor3 = HUD_RED
		r.steal.MouseButton1Click:Connect(function()
			if r.uid then Steal.StealNow(r.uid); St.autoFarm = true; saveConfig() end
		end)
		r.star.MouseButton1Click:Connect(function() if r.uid then Steal.Prioritize(r.uid) end end)
		r.skip.MouseButton1Click:Connect(function() if r.uid then Steal.Skip(r.uid, 90) end end)
		return r
	end

	local function refresh()
		local root = MV.Root()
		local plan = Steal.Plan(root and root.Position, 25)
		local seen = {}
		for i, egg in ipairs(plan) do
			local r = rows[egg.uid]
			if not r then r = buildRow(); rows[egg.uid] = r end
			seen[egg.uid] = true
			r.uid = egg.uid
			r.frame.LayoutOrder = i
			local img = _Egg.Icon(egg.cat)
			if img and r.icon.Image ~= img then r.icon.Image = img end
			local rs = _Egg.RarityStyle(egg.cat)
			r.name.Text = _Egg.DisplayName(egg.cat)
			r.name.TextColor3 = rs.color
			r.value.Text = "$" .. short(egg.value) .. "/s"
			local wt = weightText(egg.cat, egg.scale)
			r.detail.Text = string.format("x%.2f%s", egg.scale or 1, wt ~= "" and ("  ·  " .. wt) or "")
			local now = Steal.current == egg.uid
			local forced = Steal.force == egg.uid
			r.stroke.Color = (now or forced) and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(28, 28, 42)
			r.steal.Text = now and "Now" or "Steal"
			r.star.BackgroundColor3 = forced and Color3.fromRGB(255, 190, 40) or HUD_GRAY
		end
		for uid, r in pairs(rows) do
			if not seen[uid] then r.frame:Destroy(); rows[uid] = nil end
		end
		emptyLbl.Visible = next(seen) == nil
	end

	task.spawn(function()
		while true do
			task.wait(0.4)
			paintToggle(autoBtn, St.autoFarm == true, "Auto Steal")
			paintToggle(instBtn, St.instantSteal == true, "Instant Steal")
			if frame.Visible then
				pcall(refresh)
				info.Text = St.autoFarm and (Steal.status .. (Steal.detail ~= "" and (" · " .. Steal.detail) or "")) or (#cachedEggs .. " eggs in the world")
			end
		end
	end)
end

-- ============================================================
-- ANTI GUARD — Chilli Hub's card (bottom-left, above the hotbar) and its
-- method (aide_3 ~26905-28200): when you start carrying an egg (or a guard
-- welds itself to you), the character "slips past the guard" with a quick
-- series of hops to the safe zone (frozen velocity, camera held in place),
-- then hops back to where it started. Stroke flashes green/red at the end.
-- ============================================================
local AG = {Enabled = St.antiGuard == true, Busy = false, Active = false, BusySince = 0,
	SignalCarrying = false, WeldCarrying = false, Carrying = false, AreaId = nil}
Steal.ag = AG
do
	local function buildSteps(count, startAt, gap, finalAt, releaseAt, busyLimit)
		local steps = {}
		for i = 1, count do steps[i] = {At = startAt + (i - 1) * gap, To = "home"} end
		steps[#steps + 1] = {At = finalAt, To = "start"}
		return {Target = "home", LineOffset = 8, Height = 0, OffsetX = 0, OffsetZ = 0, Jitter = 0, Limp = false,
			Facing = "Zero", Freeze = true, StartAt = 0, HopRandom = 0.085, HoldRandom = 0.395,
			Steps = steps, ReleaseAt = releaseAt, BusyLimit = busyLimit}
	end
	local CFG = {
		Default = buildSteps(25, 0, 0.05, 1.27, 1.52, 2.5),
		LightDark = {Target = "line", LineOffset = 8, Height = 45, OffsetX = -90, OffsetZ = -35, Jitter = 0, Limp = true,
			Facing = "Zero", Freeze = false, StartAt = 0, HopRandom = 0, HoldRandom = 0,
			Steps = {{At = 0.1, To = "home"}, {At = 0.33, To = "home"}, {At = 0.75, To = "start"}},
			ReleaseAt = 0.8, BusyLimit = 2.5},
	}
	local function cfgFor(area)
		local k = tostring(area or ""):gsub("[^%a]", ""):lower()
		return k == "lightdark" and CFG.LightDark or CFG.Default
	end
	local function separationLine()
		local w = workspace:FindFirstChild("World") or workspace:FindFirstChild("__OBJECTS")
		w = w and w:FindFirstChild("Areas")
		w = w and w:FindFirstChild("SeparationLine")
		return w and w:IsA("BasePart") and w or nil
	end
	local function target(cfg, startPos)
		local base = _findSafeZonePos()
		if cfg.Target == "line" then
			local line = separationLine()
			if line then
				local cf = line.CFrame
				local axis = line.Size.X >= line.Size.Z and cf.RightVector or cf.LookVector
				local dir = Vector3.new(0, 1, 0):Cross(axis)
				dir = Vector3.new(dir.X, 0, dir.Z)
				if dir.Magnitude > 0.001 then
					dir = dir.Unit
					local side = ((startPos - cf.Position):Dot(dir) >= 0) and -dir or dir
					local p = cf.Position + side * (cfg.LineOffset or 8)
					base = Vector3.new(p.X, cf.Position.Y, p.Z)
				end
			end
		end
		return base + Vector3.new(cfg.OffsetX or 0, cfg.Height or 0, cfg.OffsetZ or 0)
	end
	local function rnd(a) a = math.max(tonumber(a) or 0, 0); return a <= 0 and 0 or (math.random() * 2 - 1) * a end
	local function timeline(cfg)
		local out, last, acc = {}, 0, 0
		for i, st in ipairs(cfg.Steps) do
			local at = math.max(tonumber(st.At) or 0, 0)
			acc = math.max(acc + math.max(at - last, 0) + rnd(st.To == "start" and cfg.HoldRandom or cfg.HopRandom), cfg.StartAt or 0)
			out[i] = {At = acc, To = st.To}
			last = at
		end
		return out, acc + math.max((cfg.ReleaseAt or 0) - last, 0)
	end

	local flash -- set by the card below
	local function releaseCamera(saved)
		if not saved then return end
		pcall(function() saved.cam.CameraType = saved.type end)
	end
	local function run(area)
		local ch, root, hum = LP.Character, MV.Root(), MV.Hum()
		if not ch or not root or not hum then AG.Busy = false; AG.Active = false; if flash then flash(false) end return end
		local alive = function() return AG.Enabled and root.Parent ~= nil and hum.Parent ~= nil and hum.Health > 0 end
		local cfg = cfgFor(area)
		local steps, releaseAt = timeline(cfg)
		local startPos, startRot = root.Position, root.CFrame.Rotation
		local rot = cfg.Facing == "Zero" and CFrame.new() or startRot
		local home = target(cfg, startPos)
		local wasPS = hum.PlatformStand
		local cam, savedCam = workspace.CurrentCamera, nil
		if cam then
			savedCam = {cam = cam, type = cam.CameraType}
			local cf = cam.CFrame
			pcall(function() cam.CameraType = Enum.CameraType.Scriptable; cam.CFrame = cf end)
		end
		local t0 = os.clock()
		local function tp(pos, r)
			pcall(function() ch:PivotTo(CFrame.new(pos) * r) end)
			if (root.Position - pos).Magnitude > 3 then pcall(function() root.CFrame = CFrame.new(pos) * r end) end
			if cfg.Freeze then
				for _, d in ipairs(ch:GetDescendants()) do
					if d:IsA("BasePart") then pcall(function() d.AssemblyLinearVelocity = Vector3.zero; d.AssemblyAngularVelocity = Vector3.zero end) end
				end
			end
		end
		local function waitUntil(t)
			while alive() and os.clock() - t0 < t do
				RunService.Heartbeat:Wait()
				if cfg.Freeze then pcall(function() root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero end) end
			end
			return alive()
		end
		if waitUntil(cfg.StartAt or 0) and cfg.Limp then hum.PlatformStand = true end
		for _, st in ipairs(steps) do
			if not waitUntil(st.At) then break end
			tp(st.To == "start" and startPos or home, st.To == "start" and rot or rot)
			RunService.PreSimulation:Wait()
		end
		waitUntil(releaseAt)
		pcall(function() hum.PlatformStand = wasPS end)
		releaseCamera(savedCam)
		AG.Busy = false; AG.Active = false
		if flash then flash(alive() and AG.Carrying) end
	end
	local function trigger()
		if AG.Enabled and AG.Carrying and not AG.Active then
			AG.Active = true; AG.Busy = true; AG.BusySince = os.clock()
			local area = AG.AreaId or MV.carry.area
			task.spawn(function()
				local ok = pcall(run, area)
				if not ok then
					AG.Busy = false; AG.Active = false
					local h = MV.Hum(); if h then pcall(function() h.PlatformStand = false end) end
					local cam = workspace.CurrentCamera
					if cam and cam.CameraType == Enum.CameraType.Scriptable then pcall(function() cam.CameraType = Enum.CameraType.Custom end) end
					if flash then flash(false) end
				end
			end)
		end
	end
	local function setCarrying()
		local prev = AG.Carrying
		AG.Carrying = AG.SignalCarrying or AG.WeldCarrying
		if AG.Carrying and not prev then trigger() end
	end
	pcall(function()
		local cc = _M.EggState and _M.EggState.CarryChanged
		if type(cc) == "table" and type(cc.Connect) == "function" then
			cc:Connect(function(arg)
				local on = type(arg) == "table" and arg.IsCarrying == true
				if on and type(arg.AreaId) == "string" then AG.AreaId = arg.AreaId end
				if not on then AG.AreaId = nil end
				AG.SignalCarrying = on
				setCarrying()
			end)
		end
	end)
	-- a guard that grabbed you is a Model with a "Hitbox" welded to your body
	local function guardHolding()
		local root = MV.Root()
		if not root then return false end
		for _, m in ipairs(workspace:GetChildren()) do
			if m:IsA("Model") and m:FindFirstChild("Hitbox") then
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("RigidConstraint") then
						local ok, a, b = pcall(function() return d.Part0, d.Part1 end)
						if ok and (a == root or b == root) then return true end
					end
				end
			end
		end
		return false
	end
	task.spawn(function()
		while true do
			task.wait(0.1)
			if AG.Busy and os.clock() - AG.BusySince > 4 then
				AG.Busy = false; AG.Active = false
				local h = MV.Hum(); if h then pcall(function() h.PlatformStand = false end) end
			end
			if AG.Enabled then
				local w = guardHolding()
				if w ~= AG.WeldCarrying then AG.WeldCarrying = w; setCarrying() end
			end
		end
	end)

	-- the card
	local card = Instance.new("Frame", gui)
	card.Name = "MoonEggAntiGuard"
	card.Size = UDim2.new(0, 210, 0, 48)
	card.Position = UDim2.new(0, 12, 0.7, 0)
	card.BackgroundColor3 = Color3.fromRGB(38, 44, 28)
	card.BorderSizePixel = 0
	card.Active = true
	card.ZIndex = 30
	corner(card, 14)
	local cst = Instance.new("UIStroke", card)
	cst.Color = Color3.fromRGB(48, 46, 56); cst.Thickness = 2
	local ico = Instance.new("Frame", card)
	ico.Size = UDim2.fromOffset(30, 30); ico.Position = UDim2.new(0, 8, 0.5, -15)
	ico.BackgroundColor3 = C.MOON2; ico.BorderSizePixel = 0; ico.ClipsDescendants = true
	corner(ico, 15)
	local shade = Instance.new("Frame", ico)
	shade.Size = UDim2.fromOffset(30, 30); shade.Position = UDim2.fromOffset(9, -6)
	shade.BackgroundColor3 = Color3.fromRGB(38, 44, 28); shade.BorderSizePixel = 0
	corner(shade, 15)
	local brand = Instance.new("TextLabel", card)
	brand.BackgroundTransparency = 1; brand.Text = "MoonEgg"; brand.TextSize = 11
	brand.Font = Enum.Font.GothamBold; brand.TextColor3 = Color3.fromRGB(255, 170, 130)
	brand.TextXAlignment = Enum.TextXAlignment.Left
	brand.Size = UDim2.new(1, -110, 0, 14); brand.Position = UDim2.new(0, 46, 0, 8)
	local nm = Instance.new("TextLabel", card)
	nm.BackgroundTransparency = 1; nm.Text = "Anti Guard"; nm.TextSize = 15
	nm.Font = Enum.Font.GothamBlack; nm.TextColor3 = C.WHITE
	nm.TextXAlignment = Enum.TextXAlignment.Left
	nm.Size = UDim2.new(1, -110, 0, 18); nm.Position = UDim2.new(0, 46, 0, 22)
	local track = Instance.new("TextButton", card)
	track.Size = UDim2.fromOffset(48, 24); track.Position = UDim2.new(1, -58, 0.5, -12)
	track.Text = ""; track.AutoButtonColor = false; track.BorderSizePixel = 0
	corner(track, 12)
	local knob = Instance.new("Frame", track)
	knob.Size = UDim2.fromOffset(18, 18); knob.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
	knob.BorderSizePixel = 0; corner(knob, 9)
	local flashing = false
	local function render()
		track.BackgroundColor3 = AG.Enabled and Color3.fromRGB(255, 72, 72) or Color3.fromRGB(70, 70, 82)
		knob.Position = AG.Enabled and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
		if not flashing then cst.Color = AG.Enabled and Color3.fromRGB(255, 110, 70) or Color3.fromRGB(48, 46, 56) end
	end
	render()
	flash = function(good)
		flashing = true
		cst.Color = good and Color3.fromRGB(80, 220, 140) or Color3.fromRGB(255, 70, 70)
		task.delay(1.6, function() flashing = false; render() end)
	end
	track.MouseButton1Click:Connect(function()
		AG.Enabled = not AG.Enabled
		St.antiGuard = AG.Enabled
		if not AG.Enabled then AG.Busy = false; AG.Active = false end
		render(); saveConfig()
	end)
	Win.Drag(card, card)
	AG.Render = render
	_toggleRegistry["antiGuard"] = function(on) AG.Enabled = on; render() end
end

-- filters live in the main window's Farm tab (Chilli Hub keeps them in its menu)
local function buildStealSettings(page)
	sectionHeader(page, "Auto Steal")
	local _, panelBtn = makeButton(page, "Steal Panel", stealWin.IsOpen() and "Close" or "Open", function() stealWin.SetOpen(not stealWin.IsOpen()) end)
	stealWin.OnChange(function(on) panelBtn.Text = on and "Close" or "Open" end)
	makeRow(page, "autoFarm", "Auto Steal", function(on) if not on then Steal.Abort() end end)
	makeRow(page, "instantSteal", "Instant Steal", function(on) end)
	makeRow(page, "antiGuard", "Anti Guard", function(on) AG.Enabled = on; AG.Render() end)
	local rarityOptions, rarityValueOf = _Egg.RarityDropdownOptions()
	local curRar = rarityOptions[1]
	for _, o in ipairs(rarityOptions) do if (rarityValueOf[o] or 0) == St.stealMinRarity then curRar = o end end
	makeCarousel(page, "Min Rarity", rarityOptions, rarityOptions, curRar, function(v)
		St.stealMinRarity = rarityValueOf[v] or 0; saveConfig()
	end)
	local FARM_ZONES = {"", "Forest", "Desert", "Prehistoric", "Abyss Ocean", "Snow", "Cosmic", "Lake", "Volcano", "Cherry Blossom", "Jungle", "Titan Temple"}
	local FARM_LABELS = {"All Islands", "Forest", "Desert", "Prehistoric", "Abyss Ocean", "Snow", "Cosmic", "Lake", "Volcano", "Cherry Blossom", "Jungle", "Titan Temple"}
	makeCarousel(page, "Target Island", FARM_ZONES, FARM_LABELS, St.farmZone, function(zv) St.farmZone = zv; saveConfig() end)
	local SORTS = {"Best Rarity", "Biggest Weight", "Best Mutation", "Highest Value", "Lowest Value"}
	makeCarousel(page, "Steal Priority", SORTS, SORTS, St.stealPriority, function(v) stealSetSort(v) end)
	makeMultiSelect(page, "Target Specific Eggs", _Egg.SpeciesOptions, St.stealTargetEggs, function() saveConfig() end, _Egg.Icon)
	makeSlider(page, "stealMinValueK", "Min Steal Value", 0, 50000, "%dk")
	makeSlider(page, "stealTweenPct", "Tween Speed", 50, 120, "%d%%")
	makeSlider(page, "stealCarryPct", "Carry Speed", 80, 120, "%d%%")
	makeRow(page, "showFarmPath", "Show Farm Path", function(on) end)
	makeRow(page, "stealMissingLab", "Steal Missing Lab Eggs", function(on) end)
end


-- ============================================================
-- EVENTS WINDOW — Dr Scramble (Lab, Mech boss, Scrambled Mutation).
-- The rows are filled further down, where their helpers live.
-- ============================================================
local eventsWin = Win.Make({name = "MoonEggEvents", title = "Events · Dr Scramble", w = 252, h = 360,
	pos = UDim2.new(1, -260, 0, 56), flag = "winEvents", dot = C.GOLD})
local eventsPage = eventsWin.page


-- ============================================================
-- FARM TAB
-- ============================================================
local farmPage = pages["Farm"]

buildStealSettings(farmPage)
sectionHeader(farmPage, "Events")
do
	local _, b2 = makeButton(farmPage, "Events · Dr Scramble", eventsWin.IsOpen() and "Close" or "Open", function() eventsWin.SetOpen(not eventsWin.IsOpen()) end)
	eventsWin.OnChange(function(on) b2.Text = on and "Close" or "Open" end)
end



task.spawn(function()
	local lastHatch = 0
	while true do
		task.wait(1)
		if St.autoHatch and (os.clock()-lastHatch) >= 3 then
			lastHatch = os.clock()
			-- Chilli Hub: AskHatch → wait 0.35s → AskFinishHatch for each ready egg
						pcall(function()
				if type(_M.EggState) == "table" and type(_M.EggState.ReadOwnerEggs) == "function" and type(_M.EggState.IsReadyToHatch) == "function" then
					local ok, result = pcall(_M.EggState.ReadOwnerEggs, LP.UserId)
					if ok and type(result) == "table" then
						local hasEggSet = next(St.hatchSpecificEggs) ~= nil
						local minVal = St.hatchMinValueK * 1000
						for uid, rec in pairs(result) do
							if type(rec) == "table" and rec.Placement ~= nil then
								if _Egg.Rarity(rec.AssetCategory) >= St.hatchMinRarity
									and (not hasEggSet or St.hatchSpecificEggs[tostring(rec.AssetCategory)])
									and (minVal <= 0 or _Egg.Value(rec.AssetCategory, rec.AssetScale, rec.Mutations) >= minVal) then
									local ok2, ready = pcall(_M.EggState.IsReadyToHatch, uid)
									if ok2 and ready then
										_invokeRF("RF/EggWorld/AskHatch", uid)
										task.wait(0.35)
										_invokeRF("RF/EggWorld/AskFinishHatch", uid)
										task.wait(0.2)
									end
								end
							end
						end
					end
				end
			end)
		end
	end
end)
sectionHeader(farmPage, "Auto Hatch & Equip")
makeRow(farmPage, "autoHatch", "Auto Hatch", function(on) end)
do
	local rarityOptions, rarityValueOf = _Egg.RarityDropdownOptions()
	makeCarousel(farmPage, "Hatch Min Rarity", rarityOptions, rarityOptions, rarityOptions[1], function(v)
		St.hatchMinRarity = rarityValueOf[v] or 0; saveConfig()
	end)
	makeSlider(farmPage, "hatchMinValueK", "Min Hatch Value", 0, 50000, "%dk")
	makeMultiSelect(farmPage, "Hatch Specific Eggs", _Egg.SpeciesOptions, St.hatchSpecificEggs, function() saveConfig() end, _Egg.Icon)
end

-- Auto Equip Best — Chilli Hub (aide_3 ~8830-8870): RF/Haul/FetchWearBestStatus
-- says whether a better loadout exists, then RF/Haul/WearBest equips it.
task.spawn(function()
	while true do
		task.wait(4)
		if St.autoEquip then
			pcall(function()
				local ok, res = _invokeRF("RF/Haul/FetchWearBestStatus")
				if ok and res ~= false and res ~= nil then _invokeRF("RF/Haul/WearBest") end
			end)
		end
	end
end)
makeRow(farmPage, "autoEquip", "Auto Equip Best", function(on) end)

-- Auto Claim — confirmed remotes, no cost (collects earnings already owed)
task.spawn(function()
	local lastClaim = 0
	while true do
		task.wait(1)
		if St.autoClaim and (os.clock()-lastClaim) >= 5 then
			lastClaim = os.clock()
			_invokeRF("RF/AwayEarnings/AskCollect")
			_invokeRF("RF/Codex/AskRedeemAll")
			_invokeRF("RF/GroupPerk/RedeemPerk")
		end
	end
end)
makeRow(farmPage, "autoClaim", "Auto Claim", function(on) end)

sectionHeader(farmPage, "Upgrades")


task.spawn(function()
	local lastTM = 0
	while true do
		task.wait(1.5)
		if St.autoUpgradeTM and (os.clock()-lastTM) >= 2 then
			lastTM = os.clock()
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
makeRow(farmPage, "autoUpgradeTM", "Auto Upgrade Treadmill", function(on) end)

local function _collectUids(container, nameFilter)
	local out = {}
	if not container then return out end
	for _, inst in ipairs(container:GetChildren()) do
		local uid = inst:GetAttribute("Uid") or inst:GetAttribute("UID") or inst:GetAttribute("Id") or inst:GetAttribute("EggUid")
		if uid and (not nameFilter or nameFilter(inst)) then
			table.insert(out, {uid = tostring(uid), inst = inst})
		end
	end
	return out
end
local function _isMutated(inst)
	local m = inst:GetAttribute("Mutation")
	return type(m) == "string" and m ~= ""
end

-- Chilli Hub: eggState.ReadOwnerEggs(userId) → {[uid] = {Placement, AssetCategory, AssetScale, Mutations}}
-- Returns array of {uid, rec} for items in inventory (Placement==nil) passing filterFn.
local function _readOwnerEggs(filterFn)
	local out = {}
	if type(_M.EggState) == "table" and type(_M.EggState.ReadOwnerEggs) == "function" then
		local ok, result = pcall(_M.EggState.ReadOwnerEggs, LP.UserId)
		if ok and type(result) == "table" then
			local equippedUid = nil
			pcall(function()
				local tool = LP.Character and LP.Character:FindFirstChildWhichIsA("Tool")
				equippedUid = tool and (tool:GetAttribute("UID") or tool:GetAttribute("Uid")) or nil
				if equippedUid then equippedUid = tostring(equippedUid) end
			end)
			for uid, rec in pairs(result) do
				if type(rec) == "table" and rec.Placement == nil and tostring(uid) ~= equippedUid then
					if not filterFn or filterFn(rec) then
						table.insert(out, {uid = tostring(uid), rec = rec})
					end
				end
			end
			return out
		end
	end
	return nil  -- nil = module unavailable, caller should use Backpack fallback
end

sectionHeader(farmPage, "Auto Place Egg")
-- Chilli Hub: AskPlaceEgg with inventory egg uids, gated by Place Egg
-- Rule and filtered/ordered exactly like aide_3 ~7118-7285 (Place Egg
-- Rule/Order, Place Rarities, Place Specific Eggs, Min Place Value).
task.spawn(function()
	while true do
		task.wait(_AD_jitter(1.5))
		if St.autoPlace then
			pcall(function()
				local rule = St.placeRule
				local gateOk = true
				if rule == "Steal Idle" or rule == "After Steal" then
					gateOk = not St.autoFarm or not _farmMoving
				elseif rule == "Night Only" then
					local ok2, ct = pcall(function() return game:GetService("Lighting").ClockTime end)
					gateOk = ok2 and (ct < 6 or ct > 18)
				end
				if not gateOk then return end

				local hasRaritySet = next(St.placeRarities) ~= nil
				local hasEggSet = next(St.placeSpecificEggs) ~= nil
				local minVal = St.placeMinValueK * 1000
				local items = _readOwnerEggs(function(rec)
					if rec.Placement ~= nil then return false end
					local cat = rec.AssetCategory
					if hasRaritySet and not St.placeRarities[_Egg.RarityLabel(cat)] then return false end
					if hasEggSet and not St.placeSpecificEggs[tostring(cat)] then return false end
					if minVal > 0 and _Egg.Value(cat, rec.AssetScale, rec.Mutations) < minVal then return false end
					return true
				end)
				local list = {}
				if items then
					for _, it in ipairs(items) do table.insert(list, it) end
				else
					for _, it in ipairs(_collectUids(LP:FindFirstChild("Backpack"), nil)) do
						table.insert(list, {uid = it.uid, rec = {}})
					end
				end

				local order = St.placeOrder
				if order ~= "Backpack Order" then
					table.sort(list, function(a, b)
						if order == "Highest Value" then
							return _Egg.Value(a.rec.AssetCategory, a.rec.AssetScale, a.rec.Mutations)
								> _Egg.Value(b.rec.AssetCategory, b.rec.AssetScale, b.rec.Mutations)
						end
						local av, bv = tonumber(a.rec.AssetScale) or 0, tonumber(b.rec.AssetScale) or 0
						if order == "Smallest Size" then return av < bv end
						return av > bv
					end)
				end

				for _, it in ipairs(list) do
					if not St.autoPlace then break end
					_invokeRF("RF/EggWorld/AskPlaceEgg", it.uid, CFrame.new())
					task.wait(_AD_jitter(0.5))
				end
			end)
		end
	end
end)
makeRow(farmPage, "autoPlace", "Auto Place Egg", function(on) end)
do
	local PLACE_RULE = {"Always","Steal Idle","After Steal","Night Only"}
	makeCarousel(farmPage, "Place Egg Rule", PLACE_RULE, PLACE_RULE, St.placeRule, function(v)
		St.placeRule = v; saveConfig()
	end)
	local PLACE_ORDER = {"Biggest Size","Highest Value","Smallest Size","Backpack Order"}
	makeCarousel(farmPage, "Place Egg Order", PLACE_ORDER, PLACE_ORDER, St.placeOrder, function(v)
		St.placeOrder = v; saveConfig()
	end)
	makeMultiSelect(farmPage, "Place Rarities", function()
		local opts = _Egg.RarityDropdownOptions()
		local out = {}
		for i = 2, #opts do table.insert(out, opts[i]) end
		return out
	end, St.placeRarities, function() saveConfig() end)
	makeMultiSelect(farmPage, "Place Specific Eggs", _Egg.SpeciesOptions, St.placeSpecificEggs, function() saveConfig() end, _Egg.Icon)
	makeSlider(farmPage, "placeMinValueK", "Min Place Value", 0, 50000, "%dk")
end

sectionHeader(farmPage, "Auto Treadmill")
-- Stay mounted continuously
-- Auto Treadmill / Stay On Treadmill — Chilli Hub (aide_3 ~8290-8390):
-- wear the treadmill; with "Stay On Treadmill" it is re-worn whenever you
-- come off it. Never while Auto Steal is running (the belt would drag the
-- character backwards mid-steal).
task.spawn(function()
	local worn = false
	while true do
		task.wait(_AD_jitter(2.0))
		if St.autoTreadmill2 and not MV.farming then
			if St.stayOnTreadmill or not worn then
				_invokeRF("RF/Treadmill/AskWearStill")
				worn = true
			end
		else
			worn = false
		end
	end
end)
makeRow(farmPage, "autoTreadmill2", "Auto Treadmill", function(on)
	if not on then _invokeRF("RF/Treadmill/AskDoff") end
end)
makeRow(farmPage, "stayOnTreadmill", "Stay On Treadmill", function(on) end)

sectionHeader(farmPage, "Auto Sell")
-- Chilli Hub exact rule set (aide_3 ~8901, 9280-9470):
-- Sell Rule combines a rarity check (<= Max Rarity) and a value check
-- (< Value Threshold) via Rarity Only / Value Only / Rarity And Value /
-- Rarity Or Value. 0 = that check is off (always passes).
function _Egg.SellRulePass(rule, rarity, maxRarity, value, valueThreshold)
	local passRarity = (maxRarity <= 0) or (rarity <= maxRarity)
	local passValue = (valueThreshold <= 0) or (value < valueThreshold)
	if rule == "Value Only" then return passValue end
	if rule == "Rarity And Value" then return passRarity and passValue end
	if rule == "Rarity Or Value" then return passRarity or passValue end
	return passRarity
end

task.spawn(function()
	while true do
		task.wait(_AD_jitter(3.0))
		if St.autoSellPet then
			pcall(function()
				local hasMut = St.keepMutatedSell
				local maxRarity, valThresh = St.sellPetMaxRarity, St.sellPetValueK * 1000
				local items = _readOwnerEggs(function(rec)
					if hasMut and type(rec.Mutations) == "table" and next(rec.Mutations) then return false end
					if St.sellPetBlacklist[tostring(rec.AssetCategory)] then return false end
					local value = _Egg.Value(rec.AssetCategory, rec.AssetScale, rec.Mutations)
					return _Egg.SellRulePass(St.sellPetRule, _Egg.Rarity(rec.AssetCategory), maxRarity, value, valThresh)
				end)
				local uids = {}
				if items then
					for _, it in ipairs(items) do table.insert(uids, it.uid) end
				else
					for _, it in ipairs(_collectUids(LP:FindFirstChild("Backpack"), function(i)
						return not _isMutated(i)
					end)) do table.insert(uids, it.uid) end
				end
				if #uids > 0 then
					_fireRE("RE/PetSatchel/SellSelection", {Eggs = {}, Assets = uids})
				end
			end)
		end
	end
end)
makeRow(farmPage, "autoSellPet", "Auto Sell Pet", function(on) end)
do
	local SELL_RULE = {"Rarity Only","Value Only","Rarity And Value","Rarity Or Value"}
	makeCarousel(farmPage, "Sell Pet Rule", SELL_RULE, SELL_RULE, St.sellPetRule, function(v)
		St.sellPetRule = v; saveConfig()
	end)
	local rarityOptions, rarityValueOf = _Egg.RarityDropdownOptions()
	makeCarousel(farmPage, "Pet Max Rarity", rarityOptions, rarityOptions, rarityOptions[1], function(v)
		St.sellPetMaxRarity = rarityValueOf[v] or 0; saveConfig()
	end)
	makeSlider(farmPage, "sellPetValueK", "Pet Sell Value", 0, 50000, "%dk")
	makeMultiSelect(farmPage, "Blacklist Sell Pets", _Egg.SpeciesOptions, St.sellPetBlacklist, function() saveConfig() end, _Egg.Icon)
end

task.spawn(function()
	while true do
		task.wait(_AD_jitter(3.0))
		if St.autoSellEgg then
			pcall(function()
				local hasMut = St.keepMutatedSell
				local maxRarity, valThresh = St.sellEggMaxRarity, St.sellEggValueK * 1000
				local items = _readOwnerEggs(function(rec)
					if hasMut and type(rec.Mutations) == "table" and next(rec.Mutations) then return false end
					if St.sellEggBlacklist[tostring(rec.AssetCategory)] then return false end
					local value = _Egg.Value(rec.AssetCategory, rec.AssetScale, rec.Mutations)
					return _Egg.SellRulePass(St.sellEggRule, _Egg.Rarity(rec.AssetCategory), maxRarity, value, valThresh)
				end)
				local uids = {}
				if items then
					for _, it in ipairs(items) do table.insert(uids, it.uid) end
				else
					for _, it in ipairs(_collectUids(LP:FindFirstChild("Backpack"), function(i)
						return not _isMutated(i)
					end)) do table.insert(uids, it.uid) end
				end
				if #uids > 0 then
					_fireRE("RE/PetSatchel/SellSelection", {Eggs = uids, Assets = {}})
				end
			end)
		end
	end
end)
makeRow(farmPage, "autoSellEgg", "Auto Sell Egg", function(on) end)
do
	local SELL_RULE = {"Rarity Only","Value Only","Rarity And Value","Rarity Or Value"}
	makeCarousel(farmPage, "Sell Egg Rule", SELL_RULE, SELL_RULE, St.sellEggRule, function(v)
		St.sellEggRule = v; saveConfig()
	end)
	local rarityOptions, rarityValueOf = _Egg.RarityDropdownOptions()
	makeCarousel(farmPage, "Egg Max Rarity", rarityOptions, rarityOptions, rarityOptions[1], function(v)
		St.sellEggMaxRarity = rarityValueOf[v] or 0; saveConfig()
	end)
	makeSlider(farmPage, "sellEggValueK", "Egg Sell Value", 0, 50000, "%dk")
	makeMultiSelect(farmPage, "Blacklist Sell Eggs", _Egg.SpeciesOptions, St.sellEggBlacklist, function() saveConfig() end, _Egg.Icon)
end

sectionHeader(farmPage, "Auto Fuse Machine")
-- Chilli Hub: fuses 3 SAME-SPECIES pets (aide_3 ~9702-9908:
-- groups inventory by Category, needs #group>=3). LoadPet x3 → BeginFuse
-- → wait → FinishFuse, EjectPet on failure if the machine can't finish.
task.spawn(function()
	while true do
		task.wait(_AD_jitter(4.0))
		if St.autoFuse then
			pcall(function()
				local hasSpeciesSet = next(St.fuseSpecificSpecies) ~= nil
				local maxRarity = St.fuseMaxRarity
				local items = _readOwnerEggs(function(rec)
					if St.skipMutatedFuse and type(rec.Mutations) == "table" and next(rec.Mutations) then return false end
					if hasSpeciesSet and not St.fuseSpecificSpecies[tostring(rec.AssetCategory)] then return false end
					if maxRarity > 0 and _Egg.Rarity(rec.AssetCategory) > maxRarity then return false end
					return true
				end)
				local pool = {}
				if items then
					for _, it in ipairs(items) do table.insert(pool, it) end
				else
					for _, it in ipairs(_collectUids(LP:FindFirstChild("Backpack"), function(i)
						if St.skipMutatedFuse then return not _isMutated(i) end
						return true
					end)) do
						local cat = it.inst:GetAttribute("Category") or it.inst:GetAttribute("EggType") or it.inst.Name
						table.insert(pool, {uid = it.uid, rec = {
							AssetCategory = cat, AssetScale = it.inst:GetAttribute("Scale"),
						}})
					end
				end

				local groups = {}
				for _, it in ipairs(pool) do
					local cat = tostring(it.rec.AssetCategory or "?")
					groups[cat] = groups[cat] or {}
					table.insert(groups[cat], it)
				end

				local candidates = {}
				for cat, list in pairs(groups) do
					if #list >= 3 then table.insert(candidates, {cat=cat, list=list}) end
				end
				if #candidates == 0 then return end

				local mode = St.fusePriorityMode
				table.sort(candidates, function(a, b)
					if mode == "Highest Rarity First" then
						local ar, br = _Egg.Rarity(a.cat), _Egg.Rarity(b.cat)
						if ar ~= br then return ar > br end
					elseif mode == "Most Copies First" then
						if #a.list ~= #b.list then return #a.list > #b.list end
					elseif mode == "Lowest Value First" then
						local av = _Egg.Value(a.cat, a.list[1].rec.AssetScale, a.list[1].rec.Mutations)
						local bv = _Egg.Value(b.cat, b.list[1].rec.AssetScale, b.list[1].rec.Mutations)
						if av ~= bv then return av < bv end
					else
						local ar, br = _Egg.Rarity(a.cat), _Egg.Rarity(b.cat)
						if ar ~= br then return ar < br end
					end
					return a.cat < b.cat
				end)
				local chosen = candidates[1]

				-- Pets To Use: which 3 copies of the chosen species get consumed
				table.sort(chosen.list, function(a, b)
					local av = _Egg.Value(chosen.cat, a.rec.AssetScale, a.rec.Mutations)
					local bv = _Egg.Value(chosen.cat, b.rec.AssetScale, b.rec.Mutations)
					if St.fusePetsToUse == "Highest To Lowest" then return av > bv end
					return av < bv
				end)

				_invokeRF("RF/Fusery/LoadPet", chosen.list[1].uid)
				task.wait(_AD_jitter(0.35))
				_invokeRF("RF/Fusery/LoadPet", chosen.list[2].uid)
				task.wait(_AD_jitter(0.35))
				_invokeRF("RF/Fusery/LoadPet", chosen.list[3].uid)
				task.wait(_AD_jitter(0.35))
				local ok = _invokeRF("RF/Fusery/BeginFuse")
				if ok then
					task.wait(_AD_jitter(2.0))
					_invokeRF("RF/Fusery/FinishFuse")
				elseif St.fuseEjectIncomplete then
					_invokeRF("RF/Fusery/EjectPet", chosen.list[1].uid)
					_invokeRF("RF/Fusery/EjectPet", chosen.list[2].uid)
					_invokeRF("RF/Fusery/EjectPet", chosen.list[3].uid)
				end
			end)
		end
	end
end)
makeRow(farmPage, "autoFuse", "Auto Fuse", function(on) end)
do
	local FUSE_PRIORITY = {"Lowest Rarity First","Highest Rarity First","Most Copies First","Lowest Value First"}
	makeCarousel(farmPage, "Fuse Priority Mode", FUSE_PRIORITY, FUSE_PRIORITY, St.fusePriorityMode, function(v)
		St.fusePriorityMode = v; saveConfig()
	end)
	local PETS_TO_USE = {"Lowest To Highest","Highest To Lowest"}
	makeCarousel(farmPage, "Pets To Use", PETS_TO_USE, PETS_TO_USE, St.fusePetsToUse, function(v)
		St.fusePetsToUse = v; saveConfig()
	end)
	local rarityOptions, rarityValueOf = _Egg.RarityDropdownOptions()
	makeCarousel(farmPage, "Max Rarity to Fuse", rarityOptions, rarityOptions, rarityOptions[1], function(v)
		St.fuseMaxRarity = rarityValueOf[v] or 0; saveConfig()
	end)
	makeMultiSelect(farmPage, "Specific Species to Fuse", _Egg.SpeciesOptions, St.fuseSpecificSpecies, function() saveConfig() end, _Egg.Icon)
	makeRow(farmPage, "fuseEjectIncomplete", "Eject Incomplete Slots", function(on) end)
end

sectionHeader(farmPage, "Auto Favorite")
-- Chilli Hub exact rule set (aide_3 ~10497-10615): each
-- of Min Rarity / Mutations / Min Value is an independent check that can
-- be off (0 or empty = skip); Favorite Rule combines the active ones via
-- Match Any / Match All. Always Favorite Species bypasses the rule.
function _Egg.MutationCheck(mutSet, mutations)
	if next(mutSet) == nil then return true end
	local hasMut = type(mutations) == "table" and next(mutations) ~= nil
	if mutSet["Any Mutation"] and hasMut then return true end
	if mutSet["No Mutation"] and not hasMut then return true end
	if type(mutations) == "table" then
		for name in pairs(mutations) do
			if mutSet[tostring(name)] then return true end
		end
	end
	return false
end
task.spawn(function()
	while true do
		task.wait(_AD_jitter(3.5))
		if St.autoFavoriteEquipped or St.autoUnfavoriteEquipped then
			pcall(function()
				local tool = LP.Character and LP.Character:FindFirstChildWhichIsA("Tool")
				local equippedUid = tool and (tool:GetAttribute("UID") or tool:GetAttribute("Uid"))
				if equippedUid then
					if St.autoFavoriteEquipped then
						_fireRE("RE/PetSatchel/WriteFavourite", tostring(equippedUid), true)
					elseif St.autoUnfavoriteEquipped then
						_fireRE("RE/PetSatchel/WriteFavourite", tostring(equippedUid), false)
					end
				end
			end)
		end
		if St.autoFavorite then
			pcall(function()
				local items = _readOwnerEggs(function(rec)
					local cat = rec.AssetCategory
					local rarityActive = St.favoriteMinRarity > 0
					local rarityPass = rarityActive and (_Egg.Rarity(cat) >= St.favoriteMinRarity)
					local mutActive = next(St.favoriteMutations) ~= nil
					local mutPass = mutActive and _Egg.MutationCheck(St.favoriteMutations, rec.Mutations)
					local valActive = St.favoriteMinValueK > 0
					local valPass = valActive and (_Egg.Value(cat, rec.AssetScale, rec.Mutations) >= St.favoriteMinValueK * 1000)

					local matched
					if not (rarityActive or mutActive or valActive) then
						matched = false
					elseif St.favoriteRule == "Match Any" then
						matched = (rarityActive and rarityPass) or (mutActive and mutPass) or (valActive and valPass)
					else
						matched = (not rarityActive or rarityPass) and (not mutActive or mutPass) and (not valActive or valPass)
					end

					local alwaysFav = St.favoriteAlwaysSpecies[tostring(cat)] == true
					return matched or alwaysFav
				end)
				local uids = {}
				if items then
					for _, it in ipairs(items) do table.insert(uids, it.uid) end
				else
					for _, it in ipairs(_collectUids(LP:FindFirstChild("Backpack"), function(i)
						return _isMutated(i)
					end)) do table.insert(uids, it.uid) end
				end
				for _, uid in ipairs(uids) do
					if not St.autoFavorite then break end
					_fireRE("RE/PetSatchel/WriteFavourite", uid, true)
					task.wait(_AD_jitter(0.3))
				end
			end)
		end
	end
end)
makeRow(farmPage, "autoFavorite", "Auto Favorite", function(on) end)
do
	local FAV_RULE = {"Match Any","Match All"}
	makeCarousel(farmPage, "Favorite Rule", FAV_RULE, FAV_RULE, St.favoriteRule, function(v)
		St.favoriteRule = v; saveConfig()
	end)
	local rarityOptions, rarityValueOf = _Egg.RarityDropdownOptions()
	local favRarityOpts = {"Off"}
	for i = 1, #rarityOptions do table.insert(favRarityOpts, rarityOptions[i]) end
	makeCarousel(farmPage, "Favorite Min Rarity", favRarityOpts, favRarityOpts, "Off", function(v)
		St.favoriteMinRarity = (v == "Off") and 0 or (rarityValueOf[v] or 0); saveConfig()
	end)
	makeMultiSelect(farmPage, "Favorite Mutations", function()
		return {"Any Mutation", "No Mutation"}
	end, St.favoriteMutations, function() saveConfig() end)
	makeSlider(farmPage, "favoriteMinValueK", "Min Favorite Value", 0, 50000, "%dk")
	makeMultiSelect(farmPage, "Always Favorite Species", _Egg.SpeciesOptions, St.favoriteAlwaysSpecies, function() saveConfig() end, _Egg.Icon)
	makeRow(farmPage, "autoFavoriteEquipped", "Auto Favorite Equipped", function(on) end)
	makeRow(farmPage, "autoUnfavoriteEquipped", "Auto Unfavorite Equipped", function(on) end)
end

-- ============================================================
-- EVENTS WINDOW CONTENT — Dr Scramble (Chilli Hub's Lab / Mech / Scrambled
-- Mutation rows). Everything below is parented to the Events window.
-- ============================================================
do
	local ev = eventsPage
	local function statusRow(text)
		local f = Instance.new("Frame", ev)
		f.Size = UDim2.new(1, -12, 0, 34)
		f.BackgroundColor3 = C.ROW; f.BackgroundTransparency = 0.25
		f.BorderSizePixel = 0
		corner(f, 9); addLivingStroke(f, 1)
		local l = label(f, text, UDim2.new(1, -16, 1, -6), C.SILVER, Enum.Font.GothamMedium)
		l.Position = UDim2.new(0, 8, 0, 3); l.TextSize = 9.5; l.TextWrapped = true
		l.TextYAlignment = Enum.TextYAlignment.Center
		makeDivider(ev)
		return l
	end

	-- ---------- Dr Scramble Lab (Chilli Hub ~11480-11780) ----------
	sectionHeader(ev, "Lab Trade-In")
	local labStatus = statusRow("Loading Lab data...")
	local Lab = {state = nil, at = 0, note = "", busy = false}

	local function assetName(cat)
		local e = _Egg.DirEntry(cat)
		return tostring(type(e) == "table" and e.DisplayName or cat)
	end
	local function labState(force)
		if not force and Lab.state and os.clock() - Lab.at < 4 then return Lab.state end
		local ok, res = _invokeRF("RF/ScrambleTradeIn/AskState")
		if ok and type(res) == "table" then Lab.state = res; Lab.at = os.clock() end
		return Lab.state
	end
	-- picks one owned, unfavourited, unfused, unequipped pet per requirement
	-- (mutated ones first, smallest scale first), exactly like Chilli Hub
	local function labPick(state, data)
		local reqs = state and state.Requirements
		if type(reqs) ~= "table" or #reqs == 0 then return nil, "No active recipe" end
		local equipped = {}
		if type(data.EquippedAssets) == "table" then
			for _, uid in pairs(data.EquippedAssets) do equipped[uid] = true end
		end
		local byCat = {}
		for _, r in ipairs(reqs) do byCat[tostring(r)] = {} end
		for uid, it in pairs(data.Inventory or {}) do
			local bucket = type(it) == "table" and byCat[tostring(it.Category)] or nil
			if bucket and it.InFuse ~= true and it.IsFavorite ~= true and not equipped[uid] then
				table.insert(bucket, {Uid = uid, Scale = tonumber(it.Scale) or 0,
					Mutated = type(it.Mutations) == "table" and next(it.Mutations) ~= nil})
			end
		end
		for _, b in pairs(byCat) do
			table.sort(b, function(a, c)
				if a.Mutated ~= c.Mutated then return c.Mutated end
				return a.Scale < c.Scale
			end)
		end
		local out, used = {}, {}
		for _, r in ipairs(reqs) do
			local pick
			for _, c in ipairs(byCat[tostring(r)]) do
				if not used[c.Uid] then pick = c; break end
			end
			if not pick then return nil, "Missing " .. assetName(r) end
			used[pick.Uid] = true
			table.insert(out, pick.Uid)
		end
		return out
	end
	local function labText()
		local s = Lab.state
		if type(s) ~= "table" then return "Lab status unknown" end
		if s.Unlocked ~= true then return "Lab is locked on this account" end
		local names = {}
		for _, r in ipairs(s.Requirements or {}) do table.insert(names, assetName(r)) end
		local left = math.max(0, (tonumber(s.SecondsUntilRotation) or 0) - (os.clock() - Lab.at))
		local txt = string.format("needs %s  ·  free rerolls %s  ·  rotates in %d:%02d",
			#names > 0 and table.concat(names, ", ") or "-", tostring(s.FreeRefreshesRemaining or 0),
			math.floor(left / 60), math.floor(left % 60))
		if Lab.note ~= "" then txt = txt .. "  ·  " .. Lab.note end
		return txt
	end
	local function labTick()
		local s = labState(true)
		if type(s) ~= "table" or s.Unlocked ~= true then return end
		if s.PendingReward ~= nil and s.PendingReward ~= false then
			local ok, res = _invokeRF("RF/ScrambleTradeIn/AskFinishaide")
			Lab.note = (ok and res ~= false) and "Reward claimed" or "Reward claim failed"
			return
		end
		local okSave, data = pcall(function() return _M.Save and _M.Save.Get and _M.Save.Get() end)
		if not okSave or type(data) ~= "table" then return end
		local uids, why = labPick(s, data)
		if not uids then
			Lab.note = why or "Recipe not ready"
			if St.autoRerollLab and (tonumber(s.FreeRefreshesRemaining) or 0) > 0 then
				local ok, res = _invokeRF("RF/ScrambleTradeIn/AskRefresh")
				Lab.note = (ok and res ~= false) and "Recipe rerolled" or tostring(res or "Reroll rejected")
			end
			return
		end
		if St.autoLab then
			local ok, res = _invokeRF("RF/ScrambleTradeIn/AskTradeIn", uids)
			Lab.note = (ok and res ~= false) and "Trade-in sent" or tostring(res or "Trade rejected")
		else
			Lab.note = "Ready to trade in"
		end
	end
	task.spawn(function()
		while true do
			task.wait((St.autoLab or St.autoRerollLab) and 5 or 30)
			if (St.autoLab or St.autoRerollLab) and not Lab.busy then
				Lab.busy = true
				pcall(labTick)
				Lab.busy = false
			else
				pcall(labState, true)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if eventsWin.frame.Visible and not eventsWin.minimized then
				pcall(function() labStatus.Text = labText() end)
			end
		end
	end)
	makeRow(ev, "autoLab", "Auto Lab Trade-In", function(on) end)
	makeRow(ev, "autoRerollLab", "Auto Reroll Lab Recipe", function(on) end)

	-- Steal Missing Lab Eggs feeds the Auto Steal target choice (_labNeeds)
	task.spawn(function()
		while true do
			task.wait(30)
			if St.stealMissingLab then
				pcall(function()
					local state = labState(true)
					if type(state) == "table" and type(state.Requirements) == "table" then
						local owned = {}
						local items = _readOwnerEggs(nil)
						if items then
							for _, it in ipairs(items) do owned[tostring(it.rec.AssetCategory)] = true end
						end
						local okSave, data = pcall(function() return _M.Save.Get() end)
						if okSave and type(data) == "table" then
							for _, it in pairs(data.Inventory or {}) do
								if type(it) == "table" and it.Category then owned[tostring(it.Category)] = true end
							end
						end
						local needs = {}
						for _, cat in ipairs(state.Requirements) do
							if not owned[tostring(cat)] then needs[tostring(cat)] = true end
						end
						_labNeeds = needs
					end
				end)
			elseif next(_labNeeds) ~= nil then
				_labNeeds = {}
			end
		end
	end)

	-- ---------- Mech boss ----------
	sectionHeader(ev, "Mech Boss")
	local mechStatus = statusRow("Idle")
	local _mechConn = nil
	local function stopMech()
		if _mechConn then _mechConn:Disconnect(); _mechConn = nil end
		mechStatus.Text = "Off"
	end
	local function startMech()
		stopMech()
		mechStatus.Text = "Entering the arena..."
		task.spawn(function() pcall(function() _invokeRF("RF/ScrambleBoss/EnterArena") end) end)
		local t = 0
		_mechConn = RunService.Heartbeat:Connect(function(dt)
			if not St.autoMech then return end
			t = t + dt; if t < 0.5 then return end; t = 0
			pcall(function()
				local boss = workspace:FindFirstChild("ScrambleBoss", true) or workspace:FindFirstChild("Mech", true)
				local bossHRP = boss and (boss:IsA("Model") and boss.PrimaryPart or boss:FindFirstChild("HumanoidRootPart"))
				if bossHRP then
					mechStatus.Text = "Fighting the boss"
					_fireRE("RE/BatSwing/Trigger", {serverTime = workspace:GetServerTimeNow(), targetCFrame = bossHRP.CFrame})
				else
					mechStatus.Text = "Waiting for the boss"
				end
			end)
		end)
	end
	makeRow(ev, "autoMech", "Auto Mech Boss", function(on)
		if on then startMech() else stopMech() end
	end)

	-- ---------- Scrambled Mutation (Chilli Hub ~14685-15090) ----------
	sectionHeader(ev, "Dr Scramble Event")
	local scrStatus = statusRow("Off")
	task.spawn(function()
		while true do
			task.wait(_AD_jitter(3.0))
			if St.autoUseScrambled then
				pcall(function()
					local hasTargetSet = next(St.mutationTargetEggs) ~= nil
					local minVal = St.mutationMinValueK * 1000
					local items = _readOwnerEggs(function(rec)
						if rec.Placement ~= nil then return false end
						if type(rec.Mutations) == "table" and next(rec.Mutations) then return false end
						local cat = rec.AssetCategory
						if _Egg.Rarity(cat) < St.mutationMinRarity then return false end
						if hasTargetSet and not St.mutationTargetEggs[tostring(cat)] then return false end
						if minVal > 0 and _Egg.Value(cat, rec.AssetScale, rec.Mutations) < minVal then return false end
						return true
					end)
					if items and #items > 0 then
						local priority = St.mutationPriority
						table.sort(items, function(a, b)
							if priority == "Best Rarity" then
								return _Egg.Rarity(a.rec.AssetCategory) > _Egg.Rarity(b.rec.AssetCategory)
							elseif priority == "Biggest Size" then
								return (tonumber(a.rec.AssetScale) or 0) > (tonumber(b.rec.AssetScale) or 0)
							end
							return _Egg.Value(a.rec.AssetCategory, a.rec.AssetScale, a.rec.Mutations)
								> _Egg.Value(b.rec.AssetCategory, b.rec.AssetScale, b.rec.Mutations)
						end)
						local ok, res = _invokeRF("RF/BossMastery/AskUseMutationConsumable", items[1].uid)
						scrStatus.Text = (ok and res ~= false) and ("Used on " .. assetName(items[1].rec.AssetCategory))
							or "No Scrambled Mutation left (buy one in the event shop)"
					else
						scrStatus.Text = "No egg matches the filters"
					end
				end)
			else
				scrStatus.Text = "Off"
			end
		end
	end)
	makeRow(ev, "autoUseScrambled", "Auto Use Scrambled Mutation", function(on) end)
	do
		local rarityOptions, rarityValueOf = _Egg.RarityDropdownOptions()
		makeCarousel(ev, "Mutation Min Rarity", rarityOptions, rarityOptions, rarityOptions[1], function(v)
			St.mutationMinRarity = rarityValueOf[v] or 0; saveConfig()
		end)
		makeSlider(ev, "mutationMinValueK", "Min Mutation Value", 0, 50000, "%dk")
		local MUTATION_PRIORITY = {"Highest Value","Best Rarity","Biggest Size"}
		makeCarousel(ev, "Mutation Priority", MUTATION_PRIORITY, MUTATION_PRIORITY, St.mutationPriority, function(v)
			St.mutationPriority = v; saveConfig()
		end)
		makeMultiSelect(ev, "Mutation Target Eggs", _Egg.SpeciesOptions, St.mutationTargetEggs, function() saveConfig() end, _Egg.Icon)
	end
end


sectionHeader(farmPage, "Progression")
-- Auto Buy Trail
task.spawn(function()
	while true do
		task.wait(_AD_jitter(6.0))
		if St.autoBuyTrail and _M.Trails then
			pcall(function()
				local list = _M.Trails.TRAILS or _M.Trails.List or _M.Trails
				if type(list) == "table" then
					local money = 0
					pcall(function() local d = _M.Save and _M.Save.Get and _M.Save.Get(); money = d and d.Money or 0 end)
					for id, cfg in pairs(list) do
						if not St.autoBuyTrail then break end
						if type(cfg) == "table" and cfg.Price and cfg.Price <= money then
							_invokeRF("RF/Trailwear/AskPurchase", id)
							task.wait(_AD_jitter(0.5))
						end
					end
				end
			end)
		end
	end
end)
makeRow(farmPage, "autoBuyTrail", "Auto Buy Trail", function(on) end)

-- Auto Upgrade Base
task.spawn(function()
	while true do
		task.wait(_AD_jitter(3.0))
		if St.autoUpgradeBase then
			pcall(function()
				local d = _M.Save and _M.Save.Get and _M.Save.Get()
				if d then
					local nextLevel = (d.BaseUpgradeLevel or 0) + 1
					local cfg = _M.Bases and _M.Bases.BASES and _M.Bases.BASES[nextLevel]
					if cfg and d.Money and d.Money >= (cfg.Cost or math.huge) then
						_fireRE("RE/Homestead/AskBaseTierRaise")
					end
				end
			end)
		end
	end
end)
makeRow(farmPage, "autoUpgradeBase", "Auto Upgrade Base", function(on) end)


-- ============================================================
-- SPEED TAB
-- ============================================================
local speedPage = pages["Speed"]

sectionHeader(speedPage, "Movement")
local speedRow, speedBtn, speedRefresh = makeRow(speedPage, "speedOn", "Speed Boost", function(on)
	if on then startSpeed() else stopSpeed() end
end)
makeSlider(speedPage, "speed", "Boost Speed", 20, 1000, "%d")

-- Infinite Jump — Chilli Hub (aide_3 ~15471-15500): JumpRequest -> Jumping
-- state, with the Humanoid Swap shield held while it is on.
local _ijConn = nil
makeRow(speedPage, "infJump", "Infinite Jump", function(on)
	if _ijConn then _ijConn:Disconnect(); _ijConn = nil end
	MV.Shield("jump", on)
	if on then
		_ijConn = UIS.JumpRequest:Connect(function()
			local h = MV.Hum()
			if h then pcall(function() h:ChangeState(Enum.HumanoidStateType.Jumping) end) end
		end)
	end
end)

-- Anti Ragdoll — module override + reactive safety net
local _ragdollOriginal = {}
local function _applyRagdollModuleOverride(on)
	if not _M.Ragdoll then return end
	if on then
		if _ragdollOriginal.Ragdoll == nil then
			_ragdollOriginal.Ragdoll = _M.Ragdoll.Ragdoll
			_ragdollOriginal.IsRagdolled = _M.Ragdoll.IsRagdolled
			_ragdollOriginal.NpcRagdoll = _M.Ragdoll.NpcRagdoll
		end
		pcall(function()
			_M.Ragdoll.Ragdoll = function() end
			_M.Ragdoll.IsRagdolled = function() return false end
			_M.Ragdoll.NpcRagdoll = function() end
		end)
	else
		if _ragdollOriginal.Ragdoll ~= nil then
			pcall(function()
				_M.Ragdoll.Ragdoll = _ragdollOriginal.Ragdoll
				_M.Ragdoll.IsRagdolled = _ragdollOriginal.IsRagdolled
				_M.Ragdoll.NpcRagdoll = _ragdollOriginal.NpcRagdoll
			end)
		end
	end
end
-- Anti-Ragdoll — exact Chilli Hub technique:
-- 1. BreakJointsOnDeath=false, RequiresNeck=false, disable Dead state
-- 2. HealthChanged → immediately restore MaxHealth
-- 3. StateChanged(Dead) → re-apply protection
-- 4. RagdollEndTime attr → snap state back to Running
-- 5. Heartbeat every 0.1s → restore health, repair Motor6D, cancel states
local _ragConn, _ragAttrConn, _ragHealthConn, _ragStateConn = nil, nil, nil, nil
local _ragdollSavedProps = nil

local function _applyHumanoidProtection(hum, on)
	if not hum or not hum.Parent then return end
	if on then
		_ragdollSavedProps = {
			BreakJointsOnDeath = hum.BreakJointsOnDeath,
			RequiresNeck = hum.RequiresNeck,
			DeadEnabled = hum:GetStateEnabled(Enum.HumanoidStateType.Dead),
		}
		pcall(function()
			hum.BreakJointsOnDeath = false
			hum.RequiresNeck = false
			hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
		end)
	else
		if _ragdollSavedProps then
			pcall(function()
				hum.BreakJointsOnDeath = _ragdollSavedProps.BreakJointsOnDeath
				hum.RequiresNeck = _ragdollSavedProps.RequiresNeck
				hum:SetStateEnabled(Enum.HumanoidStateType.Dead, _ragdollSavedProps.DeadEnabled)
			end)
			_ragdollSavedProps = nil
		end
	end
end

local function _ragdollCounter()
	if not St.antiRagdoll then return end
	local char = LP.Character; if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
	pcall(function()
		if hum.MaxHealth > 0 and hum.MaxHealth ~= math.huge then
			if hum.Health < hum.MaxHealth then hum.Health = hum.MaxHealth end
		end
	end)
	local st = hum:GetState()
	if st==Enum.HumanoidStateType.Physics or st==Enum.HumanoidStateType.Ragdoll
		or st==Enum.HumanoidStateType.FallingDown then
		pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
	end
end
local function stopAntiRag()
	if _ragConn then _ragConn:Disconnect(); _ragConn = nil end
	if _ragAttrConn then _ragAttrConn:Disconnect(); _ragAttrConn = nil end
	if _ragHealthConn then _ragHealthConn:Disconnect(); _ragHealthConn = nil end
	if _ragStateConn then _ragStateConn:Disconnect(); _ragStateConn = nil end
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then _applyHumanoidProtection(hum, false) end
	_applyRagdollModuleOverride(false)
end
local function startAntiRag()
	stopAntiRag()
	_applyRagdollModuleOverride(true)
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		_applyHumanoidProtection(hum, true)
		_ragHealthConn = hum.HealthChanged:Connect(function() _ragdollCounter() end)
		_ragStateConn = hum.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Dead then
				_applyHumanoidProtection(hum, true)
				_ragdollCounter()
			end
		end)
	end
	_ragAttrConn = LP:GetAttributeChangedSignal("RagdollEndTime"):Connect(_ragdollCounter)
	local _t = 0
	_ragConn = RunService.Heartbeat:Connect(function()
		if not St.antiRagdoll then return end
		local now = tick(); if now-_t < 0.1 then return end; _t = now
		_ragdollCounter()
		local ch = LP.Character; if not ch then return end
		for _, obj in ipairs(ch:GetDescendants()) do
			if obj:IsA("Motor6D") and not obj.Enabled then obj.Enabled = true end
		end
	end)
end
sectionHeader(speedPage, "Character")
makeRow(speedPage, "antiRagdoll", "Anti Ragdoll", function(on)
	if on then startAntiRag() else stopAntiRag() end
end)


-- Anti Trap — Chilli Hub (aide_3 ~16460-16540): every part of another
-- player's PlacedTrap gets CanTouch = false, so it can't catch you.
local _trapLinks, _trapSaved = {}, {}
local CollectionService = game:GetService("CollectionService")
local function _trapOff(p)
	if p:IsA("BasePart") and _trapSaved[p] == nil then
		_trapSaved[p] = p.CanTouch
		pcall(function() p.CanTouch = false end)
	end
end
local function _trapDisarm(inst)
	if not St.antiTrap or not inst.Parent then return end
	if inst:GetAttribute("Owner") == LP.Name then return end
	_trapOff(inst)
	for _, d in ipairs(inst:GetDescendants()) do _trapOff(d) end
	table.insert(_trapLinks, inst.DescendantAdded:Connect(function(d) if St.antiTrap then _trapOff(d) end end))
end
local function stopAntiTrap()
	for _, l in ipairs(_trapLinks) do pcall(function() l:Disconnect() end) end
	table.clear(_trapLinks)
	for p, was in pairs(_trapSaved) do
		if p.Parent then pcall(function() p.CanTouch = was end) end
	end
	table.clear(_trapSaved)
end
local function startAntiTrap()
	stopAntiTrap()
	for _, t in ipairs(CollectionService:GetTagged("PlacedTrap")) do _trapDisarm(t) end
	table.insert(_trapLinks, CollectionService:GetInstanceAddedSignal("PlacedTrap"):Connect(function(t)
		task.defer(_trapDisarm, t)
	end))
end
makeRow(speedPage, "antiTrap", "Anti Trap", function(on)
	if on then startAntiTrap() else stopAntiTrap() end
end)

-- Instant Prompts — Chilli Hub (aide_3 ~16700-16860): HoldDuration -> 0 on
-- every shown prompt and on the egg-carry prompts (SmartPromptPart >
-- CarryAreaEgg) the moment they spawn; ClaimLostPart is left alone.
local _ipHold = {}
local _ipConns = {}
local function _ipApply(p)
	if not p:IsA("ProximityPrompt") or p.Name == "ClaimLostPart" then return end
	if _ipHold[p] == nil then
		if p.HoldDuration <= 0 and p.Name ~= "CarryAreaEgg" then return end
		_ipHold[p] = p.HoldDuration
	end
	if p.HoldDuration ~= 0 then pcall(function() p.HoldDuration = 0 end) end
end
local function _ipCarryPrompt(part)
	if part.Name ~= "SmartPromptPart" then return nil end
	local p = part:FindFirstChild("CarryAreaEgg")
	return p and p:IsA("ProximityPrompt") and p or nil
end
local function stopInstantPrompts()
	for _, c in ipairs(_ipConns) do pcall(function() c:Disconnect() end) end
	table.clear(_ipConns)
	for p, orig in pairs(_ipHold) do
		if p.Parent then pcall(function() p.HoldDuration = orig end) end
	end
	table.clear(_ipHold)
end
local function startInstantPrompts()
	stopInstantPrompts()
	table.insert(_ipConns, ProximityPromptService.PromptShown:Connect(function(p)
		if St.instantPrompts then _ipApply(p) end
	end))
	for _, child in ipairs(workspace:GetChildren()) do
		local p = _ipCarryPrompt(child)
		if p then _ipApply(p) end
	end
	table.insert(_ipConns, workspace.ChildAdded:Connect(function(child)
		if child.Name ~= "SmartPromptPart" then return end
		task.defer(function()
			local p = child:FindFirstChild("CarryAreaEgg") or child:WaitForChild("CarryAreaEgg", 2)
			if p and p:IsA("ProximityPrompt") and St.instantPrompts then _ipApply(p) end
		end)
	end))
end
makeRow(speedPage, "instantPrompts", "Instant Prompts", function(on)
	if on then startInstantPrompts() else stopInstantPrompts() end
end)


-- Invisibility — Chilli Hub (aide_3 ~15914-16376): the character is reset,
-- and on the fresh one the joints are broken server-side, every accessory
-- and limb is removed on the client and HipHeight is pushed up, keeping
-- only the root part (+ a tiny fake RightHand so tools can still be held).
-- The other players stop seeing you. Speed Boost is forced on while it is
-- active (a limbless rig walks with the boost velocity only). Experimental.
local Invis = {on = false, applying = false, prevSpeed = false}
do
	local HIP = 999
	local function hum(ch) return ch and ch:FindFirstChildOfClass("Humanoid") end
	local function applied(ch) return ch ~= nil and ch:GetAttribute("InvisApplied") == true end
	local function rigWipe(ch)
		local r = _getRemote("RE/RigSync/AskRigWipe")
		if r and r:IsA("RemoteEvent") then pcall(function() r:FireServer(ch) end) end
	end
	local function doff()
		local r = _getRemote("RF/Treadmill/AskDoff")
		if r and r:IsA("RemoteFunction") then for _ = 1, 2 do pcall(function() r:InvokeServer() end) end end
	end
	local function killChar(ch)
		local h = hum(ch)
		if not h then return end
		doff()
		pcall(function()
			h:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
			h.BreakJointsOnDeath = true; h.RequiresNeck = true; h.Health = 0
		end)
		pcall(function() h:ChangeState(Enum.HumanoidStateType.Dead) end)
		pcall(function() ch:BreakJoints() end)
		rigWipe(ch)
	end
	local function applyTo(ch)
		if Invis.applying then return false end
		Invis.applying = true
		local h = hum(ch)
		local deadline = os.clock() + 10
		while Invis.on and ch.Parent and os.clock() < deadline do
			h = h or hum(ch)
			if h and ch:FindFirstChild("HumanoidRootPart") and ch:FindFirstChild("Head") then break end
			task.wait()
		end
		local root = ch:FindFirstChild("HumanoidRootPart")
		if not Invis.on or not h or not root or not ch:FindFirstChild("Head") then Invis.applying = false; return false end
		task.wait(0.05)
		if not Invis.on or not ch.Parent then Invis.applying = false; return false end
		for _ = 1, 2 do pcall(h.UnequipTools, h) end
		if type(replicatesignal) == "function" then
			for _ = 1, 2 do pcall(replicatesignal, h.ServerBreakJoints) end
		end
		pcall(function() h.HipHeight = HIP end)
		for _, c in ipairs(ch:GetChildren()) do
			if c:IsA("Accessory") or (c:IsA("BasePart") and c ~= root) then pcall(function() c.Parent = nil end) end
		end
		task.wait(0.12)
		if not Invis.on or not ch.Parent then Invis.applying = false; return false end
		local wrist = Instance.new("Motor6D")
		wrist.Name = "RightWrist"; wrist.C0 = CFrame.new(1.2, 0, 0); wrist.C1 = CFrame.new()
		wrist.Part0 = root; wrist.Parent = root
		local hand = Instance.new("Part")
		hand.Name = "RightHand"; hand.Size = Vector3.new(0.2, 0.2, 0.2)
		hand.Transparency = 1; hand.CanCollide = false; hand.CanTouch = false; hand.CanQuery = false; hand.Massless = true
		hand.CFrame = root.CFrame * wrist.C0
		wrist.Part1 = hand; hand.Parent = ch
		pcall(function() root.CanCollide = false end)
		ch:SetAttribute("InvisApplied", true)
		task.delay(0.2, function() if root.Parent then pcall(function() root.CanCollide = true end) end end)
		local keep
		keep = ch.ChildAdded:Connect(function(c)
			if c:IsA("Humanoid") then task.defer(function() pcall(function() c.HipHeight = HIP end) end) end
		end)
		ch.AncestryChanged:Connect(function(_, p) if p == nil and keep then keep:Disconnect() end end)
		Invis.applying = false
		return true
	end
	local function forceSpeed(on)
		if on then
			Invis.prevSpeed = St.speedOn == true
			if not St.speedOn then startSpeed() end
		else
			if not Invis.prevSpeed and St.speedOn then stopSpeed() end
		end
	end
	function Invis.Set(on)
		Invis.on = on == true
		if Invis.on then
			forceSpeed(true)
			MV.ShieldPaused = true
			pcall(MV.UndoSwap)
			task.spawn(function()
				local ch = LP.Character
				if ch and not applied(ch) then killChar(ch) end
			end)
		else
			forceSpeed(false)
			MV.ShieldPaused = false
			local ch = LP.Character
			if ch and applied(ch) then killChar(ch) end
		end
	end
	LP.CharacterAdded:Connect(function(ch)
		if not Invis.on then return end
		task.spawn(function()
			ch:WaitForChild("Humanoid", 10)
			applyTo(ch)
		end)
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if Invis.on then
				local ch = LP.Character
				local h = hum(ch)
				if ch and h and h.Health > 0 and not applied(ch) and not Invis.applying then
					task.spawn(applyTo, ch)
				end
			end
		end
	end)
end
St.invisibility = false -- never restored: it resets the character
makeRow(speedPage, "invisibility", "Invisibility", function(on) Invis.Set(on) end)


-- ============================================================
-- VISUAL TAB
-- ============================================================
local visualPage = pages["Visual"]

local function _shortNum(n)
	if not n then return "?" end
	local a = math.abs(n)
	if a >= 1e12 then return string.format("%.1fT", n/1e12) end
	if a >= 1e9  then return string.format("%.1fB", n/1e9)  end
	if a >= 1e6  then return string.format("%.1fM", n/1e6)  end
	if a >= 1e3  then return string.format("%.1fK", n/1e3)  end
	return string.format("%d", n)
end

local _espParts = {}
local _espConn = nil
local _espStatsLbl = nil
local function clearESP()
	for _, p in ipairs(_espParts) do pcall(function() p:Destroy() end) end
	_espParts = {}
end
local function stopESP()
	if _espConn then _espConn:Disconnect(); _espConn = nil end
	clearESP()
	if _espStatsLbl then _espStatsLbl.Text = "ESP inactive" end
end
local function startESP()
	stopESP()
	local _t = 0
	_espConn = RunService.Heartbeat:Connect(function()
		if not St.esp then return end
		local now = tick(); if now-_t < 1 then return end; _t = now
		clearESP()

		local myPos = nil
		do
			local mc = LP.Character
			local mr = mc and mc:FindFirstChild("HumanoidRootPart")
			myPos = mr and mr.Position
		end

		-- ESP Own Base Eggs: merge in the separately-scanned own-slot list.
		local pool = cachedEggs
		if St.espOwnBase and #_ownBaseEggs > 0 then
			pool = {}
			for _, r in ipairs(cachedEggs) do table.insert(pool, r) end
			for _, r in ipairs(_ownBaseEggs) do table.insert(pool, r) end
		end

		-- ESP Min Rarity / Min Value filters (Chilli Hub exact fields).
		local minVal = St.espMinValueK * 1000
		local filtered = {}
		for _, r in ipairs(pool) do
			if (r.rarity or _Egg.Rarity(r.mutation)) >= St.espMinRarity
				and (r.value or _Egg.Value(r.mutation, r.scale, r.mutTable)) >= minVal then
				table.insert(filtered, r)
			end
		end

		local total, readyCount, rareCount, lockedCount = #filtered, 0, 0, 0
		for _, r in ipairs(filtered) do
			if r.enabled then readyCount = readyCount + 1 end
			if r.tags and #r.tags > 0 then rareCount = rareCount + 1 end
			if not areaUnlocked(r.area) then lockedCount = lockedCount + 1 end
		end

		-- Only show the closest ones: past a certain number of billboards
		-- on screen at once, the text overlaps and becomes unreadable
		-- (this is what made the ESP "ugly, can't see anything"). Sort by
		-- distance and cap the render — the counters above still count
		-- ALL eggs regardless.
		local ESP_MAX_SHOWN, ESP_MAX_DIST = 20, 220
		local shown = {}
		if myPos then
			for _, r in ipairs(filtered) do
				local d = (r.pos - myPos).Magnitude
				if d <= ESP_MAX_DIST then table.insert(shown, {r=r, d=d}) end
			end
			table.sort(shown, function(a,b) return a.d < b.d end)
		else
			for _, r in ipairs(filtered) do shown[#shown+1] = {r=r, d=0} end
		end

		local sizePct = St.espFixedSize and 100 or St.espEggSizePct
		local sizeMul = sizePct / 100
		local info = St.espShowInfo

		for i = 1, math.min(ESP_MAX_SHOWN, #shown) do
			local r = shown[i].r
			pcall(function()
				local unlocked = areaUnlocked(r.area)
				local hasRareTag = r.tags and #r.tags > 0
				local notReady = r.enabled == false
				local col = notReady and C.DIM or (not unlocked) and C.RED or (hasRareTag and C.GOLD or C.GREEN)

				local part = r.part
				local p = Instance.new("Part")
				p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.Transparency = 1
				p.Size = (part and part:IsA("BasePart") and part.Size.Magnitude > 0.5) and part.Size or Vector3.new(3.5,3.5,3.5)
				p.CFrame = r.cf
				p.Parent = workspace

				local bb = Instance.new("BillboardGui")
				bb.Size = UDim2.fromOffset(180*sizeMul, 48*sizeMul); bb.AlwaysOnTop = true; bb.MaxDistance = ESP_MAX_DIST
				bb.Parent = p

				-- ESP Show Info's "Icon" is the egg's real icon image,
				-- read live from the game's own asset directory (never a
				-- guessed asset id) — aide_3 ~20756-20760.
				local iconId = info.Icon and _Egg.Icon(r.mutation) or nil
				local textXOff = 0
				if iconId then
					local iconSz = 22 * sizeMul
					local img = Instance.new("ImageLabel", bb)
					img.Size = UDim2.fromOffset(iconSz, iconSz)
					img.Position = UDim2.new(0,0,0,1)
					img.BackgroundTransparency = 1
					img.Image = iconId
					img.ZIndex = 2
					textXOff = iconSz + 4
				end

				-- ESP Show Info picks which lines render, exactly like
				-- Chilli Hub's field list (Icon/Name/Rarity/Mutation/
				-- Value/Weight/Size/Sell Price/Distance/Area/State).
				local lines = {}
				if info.Name then
					table.insert(lines, {text = tostring(r.cat or "Egg"), color = col, size = 12, bold = true})
				end
				if info.Rarity then
					table.insert(lines, {text = _Egg.RarityName(r.mutation), color = C.SILVER, size = 10})
				end
				if info.Mutation and r.mutTable and next(r.mutTable) then
					local names = {}
					for k in pairs(r.mutTable) do table.insert(names, tostring(k)) end
					table.insert(lines, {text = table.concat(names, ", "), color = C.GOLD, size = 10})
				end
				if info.State then
					if notReady then table.insert(lines, {text = "GROWING", color = C.WHITE, size = 10})
					elseif not unlocked then
						local A = AREA[r.area]
						table.insert(lines, {text = "LOCKED ".._shortNum(A and A.reqSP), color = C.RED, size = 10})
					else table.insert(lines, {text = "READY", color = C.WHITE, size = 10}) end
				end
				local metaParts = {}
				if info.Weight and r.weight then table.insert(metaParts, r.weight.."kg") end
				if info.Size and r.scale then table.insert(metaParts, string.format("%.1fx", r.scale)) end
				if info.Value and r.value and r.value > 0 then table.insert(metaParts, _shortNum(r.value).."/s") end
				if info.Distance and myPos then table.insert(metaParts, math.floor((r.pos - myPos).Magnitude).."m") end
				if info.Area then table.insert(metaParts, tostring(r.area or "?")) end
				if #metaParts > 0 then
					table.insert(lines, {text = table.concat(metaParts, "  ·  "), color = C.SILVER, size = 9})
				end
				if #lines == 0 then
					table.insert(lines, {text = tostring(r.cat or "Egg"), color = col, size = 12, bold = true})
				end

				local y = 0
				for _, ln in ipairs(lines) do
					local h = ln.size + 6
					local lbl = Instance.new("TextLabel", bb)
					lbl.Size = UDim2.new(1,-textXOff,0,h); lbl.Position = UDim2.new(0,textXOff,0,y)
					lbl.BackgroundTransparency = 1
					lbl.Font = ln.bold and Enum.Font.GothamBold or Enum.Font.Gotham
					lbl.TextSize = ln.size; lbl.TextStrokeTransparency = 0
					lbl.TextColor3 = ln.color; lbl.Text = ln.text
					lbl.TextTruncate = Enum.TextTruncate.AtEnd
					y = y + h
				end
				bb.Size = UDim2.fromOffset(180*sizeMul, math.max(y, 22*sizeMul))

				table.insert(_espParts, p)
			end)
		end

		if _espStatsLbl then
			_espStatsLbl.Text = string.format(
				"Total %d  ·  Ready %d  ·  Rare %d  ·  Locked %d",
				total, readyCount, rareCount, lockedCount)
		end
	end)
end
sectionHeader(visualPage, "Egg ESP")
makeRow(visualPage, "esp", "Egg ESP", function(on) if on then startESP() else stopESP() end end)

-- Small live recap under the ESP toggle — totals refreshed at the same
-- cadence as the billboards (1x/s).
do
	local row = Instance.new("Frame", visualPage)
	row.Size = UDim2.new(1,-12,0,24)
	row.BackgroundColor3 = C.ROW; row.BackgroundTransparency = 0.5
	row.BorderSizePixel = 0; corner(row, 10); addLivingStroke(row, 1)
	local pad = Instance.new("UIPadding", row)
	pad.PaddingLeft = UDim.new(0,10); pad.PaddingRight = UDim.new(0,10)
	_espStatsLbl = label(row, "ESP inactive", UDim2.new(1,0,1,0), C.DIM, Enum.Font.Gotham)
	_espStatsLbl.TextSize = 10.5
	makeDivider(visualPage)
end

-- ESP filter/display widgets — exact Chilli Hub set (aide_3 ~19423-19620).
do
	makeRow(visualPage, "espFixedSize", "ESP Fixed Size", function(on) end)
	makeRow(visualPage, "espOwnBase", "ESP Own Base Eggs", function(on) end)
	local rarityOptions, rarityValueOf = _Egg.RarityDropdownOptions()
	makeCarousel(visualPage, "ESP Min Rarity", rarityOptions, rarityOptions, rarityOptions[1], function(v)
		St.espMinRarity = rarityValueOf[v] or 0; saveConfig()
	end)
	local ESP_INFO_FIELDS = {"Icon","Name","Rarity","Mutation","Value","Weight","Size","Distance","Area","State"}
	makeMultiSelect(visualPage, "ESP Show Info", function() return ESP_INFO_FIELDS end, St.espShowInfo, function() saveConfig() end)
	makeSlider(visualPage, "espMinValueK", "Min ESP Value", 0, 50000, "%dk")
	makeSlider(visualPage, "espEggSizePct", "ESP Egg Size", 50, 200, "%d%%")
end



local function applyFpsBoost()
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


local _afkConn = nil
local function stopAntiAFK() if _afkConn then _afkConn:Disconnect(); _afkConn = nil end end
local function startAntiAFK()
	stopAntiAFK()
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

-- ESP Guards
local _espGuardParts = {}
local _espGuardConn = nil
local function clearEspGuards()
	for _, h in ipairs(_espGuardParts) do pcall(function() h:Destroy() end) end
	_espGuardParts = {}
end
local function stopEspGuards() if _espGuardConn then _espGuardConn:Disconnect(); _espGuardConn = nil end; clearEspGuards() end
local function startEspGuards()
	stopEspGuards()
	local _t = 0
	_espGuardConn = RunService.Heartbeat:Connect(function(dt)
		if not St.espGuards then return end
		_t = _t + dt; if _t < 2 then return end; _t = 0
		clearEspGuards()
		pcall(function()
			local folder = workspace:FindFirstChild("__OBJECTS")
			folder = folder and folder:FindFirstChild("Areas")
			folder = folder and folder:FindFirstChild("GuardAreas")
			if not folder then return end
			local sizeMul = St.espGuardSizePct / 100
			for _, a in ipairs(folder:GetChildren()) do
				local guard = a:FindFirstChild("Guard")
				if guard then
					local h = Instance.new("Highlight")
					h.FillColor = C.RED; h.OutlineColor = C.WHITE
					h.FillTransparency = 0.6
					h.Parent = guard
					table.insert(_espGuardParts, h)

					local gp = guard:FindFirstChildWhichIsA("BasePart", true)
					if gp then
						local bb = Instance.new("BillboardGui")
						bb.Size = UDim2.fromOffset(90*sizeMul, 16*sizeMul)
						bb.StudsOffset = Vector3.new(0,3,0); bb.AlwaysOnTop = true
						bb.Parent = gp
						local l = Instance.new("TextLabel", bb)
						l.Size = UDim2.new(1,0,1,0); l.BackgroundTransparency = 1
						l.Text = "GUARD"; l.TextColor3 = C.RED; l.Font = Enum.Font.GothamBold
						l.TextSize = 11*sizeMul; l.TextStrokeTransparency = 0
						table.insert(_espGuardParts, bb)
					end
				elseif St.espLostParts then
					-- "Lost Parts": mark guard areas whose Guard is currently
					-- absent (despawned/on cooldown) — shows where one will
					-- reappear, dimmer than an active guard marker.
					local ap = a:FindFirstChildWhichIsA("BasePart", true)
					if ap then
						local bb = Instance.new("BillboardGui")
						bb.Size = UDim2.fromOffset(90,16); bb.StudsOffset = Vector3.new(0,3,0); bb.AlwaysOnTop = true
						bb.Parent = ap
						local l = Instance.new("TextLabel", bb)
						l.Size = UDim2.new(1,0,1,0); l.BackgroundTransparency = 1
						l.Text = "(no guard)"; l.TextColor3 = C.DIM; l.Font = Enum.Font.Gotham
						l.TextSize = 10; l.TextStrokeTransparency = 0.2
						table.insert(_espGuardParts, bb)
					end
				end
			end
		end)
	end)
end
sectionHeader(visualPage, "Guard ESP")
makeRow(visualPage, "espGuards", "ESP Guards", function(on)
	if on then startEspGuards() else stopEspGuards() end
end)
do
	makeSlider(visualPage, "espGuardSizePct", "ESP Guard Size", 50, 200, "%d%%")
	makeRow(visualPage, "espLostParts", "ESP Lost Parts", function(on) end)
end

-- ESP Players
local _espPlayerParts = {}
local _espPlayerConn = nil
local function clearEspPlayers()
	for _, b in ipairs(_espPlayerParts) do pcall(function() b:Destroy() end) end
	_espPlayerParts = {}
end
local function stopEspPlayers() if _espPlayerConn then _espPlayerConn:Disconnect(); _espPlayerConn = nil end; clearEspPlayers() end
local function startEspPlayers()
	stopEspPlayers()
	local _t = 0
	local _espAvatarCache = {}
	_espPlayerConn = RunService.Heartbeat:Connect(function(dt)
		if not St.espPlayers then return end
		_t = _t + dt; if _t < 2 then return end; _t = 0
		clearEspPlayers()
		local sizeMul = St.espPlayerSizePct / 100
		local myPos = nil
		do
			local mc = LP.Character
			local mr = mc and mc:FindFirstChild("HumanoidRootPart")
			myPos = mr and mr.Position
		end
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LP and plr.Character then
				local head = plr.Character:FindFirstChild("Head")
				if head then
					local text = plr.Name
					if St.espPlayerInfo and myPos then
						local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
						if hrp then text = text .. "  ·  " .. math.floor((hrp.Position - myPos).Magnitude) .. "m" end
					end
					local avaSz = 18 * sizeMul
					local bb = Instance.new("BillboardGui")
					bb.Size = UDim2.fromOffset(140*sizeMul + avaSz, 20*sizeMul)
					bb.StudsOffset = Vector3.new(0,2,0)
					bb.AlwaysOnTop = true
					bb.Parent = head
					-- Real avatar headshot thumbnail (Players:GetUserThumbnailAsync),
					-- cached per userId so it's fetched once, not every 2s tick.
					if St.espPlayerInfo then
						local cached = _espAvatarCache[plr.UserId]
						if cached == nil then
							_espAvatarCache[plr.UserId] = false
							task.spawn(function()
								local ok, content = pcall(Players.GetUserThumbnailAsync, Players, plr.UserId,
									Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
								if ok then _espAvatarCache[plr.UserId] = content end
							end)
						elseif cached then
							local img = Instance.new("ImageLabel", bb)
							img.Size = UDim2.fromOffset(avaSz, avaSz)
							img.Position = UDim2.new(0,0,0,0)
							img.BackgroundTransparency = 1
							img.Image = cached
							corner(img, avaSz/2)
						end
					end
					local l = Instance.new("TextLabel", bb)
					l.Size = UDim2.new(1,-avaSz,1,0); l.Position = UDim2.new(0,avaSz,0,0)
					l.BackgroundTransparency = 1
					l.Text = text; l.TextColor3 = C.WHITE; l.Font = Enum.Font.GothamBold
					l.TextSize = 12*sizeMul; l.TextStrokeTransparency = 0
					table.insert(_espPlayerParts, bb)
				end
			end
		end
	end)
end
sectionHeader(visualPage, "Player ESP")
makeRow(visualPage, "espPlayers", "ESP Players", function(on)
	if on then startEspPlayers() else stopEspPlayers() end
end)
do
	makeRow(visualPage, "espPlayerInfo", "ESP Player Info", function(on) end)
	makeSlider(visualPage, "espPlayerSizePct", "ESP Player Size", 50, 200, "%d%%")
end

-- ============================================================
-- MISC TAB
-- ============================================================
local miscPage = pages["Misc"]


local hopServer
sectionHeader(miscPage, "Session")
makeButton(miscPage, "Server Hop", "Hop", function() hopServer() end)
makeButton(miscPage, "Rejoin Server", "Rejoin", function()
	pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId, LP) end)
end, true)

makeButton(miscPage, "Copy Current Job ID", "Copy", function()
	pcall(function()
		setclipboard(tostring(game.JobId))
		setStatus("Job ID copied", C.GREEN)
		task.delay(2, function() setStatus("Idle", C.DIM) end)
	end)
end)

do
	local SERVER_HOP_MODE = {"Most Players","Random","Least Players"}
	makeCarousel(miscPage, "Server Hop Mode", SERVER_HOP_MODE, SERVER_HOP_MODE, St.serverHopMode, function(v)
		St.serverHopMode = v; saveConfig()
	end)
end

makeRow(miscPage, "autoRejoin", "Auto Rejoin When Disconnect", function(on) end)
sectionHeader(miscPage, "Utility")
makeRow(miscPage, "antiAFK", "Anti AFK", function(on) if on then startAntiAFK() else stopAntiAFK() end end)
-- Auto Rejoin — Chilli Hub's exact detection (aide_3 ~25429-25560): the
-- client can't use BindToClose (server-only), so it waits for Roblox's own
-- disconnect ErrorPrompt / GuiService.ErrorMessageChanged, ignores
-- teleports, bans and duplicate-login kicks, then rejoins the same server
-- (2 tries) or any server if it was shut down.
do
	local GuiService = game:GetService("GuiService")
	local CoreGui = game:GetService("CoreGui")
	local TeleportService = game:GetService("TeleportService")
	local teleportingAt, fired = 0, false
	pcall(function()
		LP.OnTeleport:Connect(function(state)
			if state == Enum.TeleportState.Failed then teleportingAt = 0 else teleportingAt = os.clock() end
		end)
	end)
	local function promptShown()
		local g = CoreGui:FindFirstChild("RobloxPromptGui")
		g = g and g:FindFirstChild("promptOverlay")
		return g ~= nil and g:FindFirstChild("ErrorPrompt") ~= nil
	end
	local function onDisconnect(msg)
		if fired or not St.autoRejoin then return end
		if teleportingAt > 0 and os.clock() - teleportingAt < 60 then return end
		local low = string.lower(tostring(msg or ""))
		if low == "" or low:find("teleport", 1, true) then return end
		local code
		pcall(function() code = GuiService:GetErrorCode() end)
		if code == Enum.ConnectionError.DisconnectDuplicatePlayer or low:find("banned", 1, true) or low:find("same account", 1, true) then return end
		fired = true
		local placeId, jobId = game.PlaceId, tostring(game.JobId or "")
		local closed = low:find("shut", 1, true) or low:find("no longer", 1, true) or low:find("closed", 1, true)
		task.spawn(function()
			local n = 0
			while true do
				n = n + 1
				local sameServer = not closed and jobId ~= "" and n <= 2
				pcall(function()
					if sameServer then TeleportService:TeleportToPlaceInstance(placeId, jobId, LP)
					else TeleportService:Teleport(placeId, LP) end
				end)
				task.wait(sameServer and 4 or 5)
			end
		end)
	end
	pcall(function()
		GuiService.ErrorMessageChanged:Connect(function(msg)
			task.wait(0.3)
			if promptShown() then onDisconnect(msg) end
		end)
	end)
	task.spawn(function()
		local pg = CoreGui:WaitForChild("RobloxPromptGui", 30)
		pg = pg and pg:WaitForChild("promptOverlay", 30)
		if not pg then return end
		pg.ChildAdded:Connect(function(child)
			if child.Name ~= "ErrorPrompt" then return end
			task.wait(0.2)
			local text = ""
			for _, d in ipairs(child:GetDescendants()) do
				if d:IsA("TextLabel") and d.Name == "ErrorMessage" then text = d.Text end
			end
			if text == "" then pcall(function() text = GuiService:GetErrorMessage() end) end
			onDisconnect(text ~= "" and text or "disconnected")
		end)
	end)
end

-- FPS Cap — 0 = uncapped (executor default)
do
	sectionHeader(miscPage, "Performance")
	local row, setVal = makeSlider(miscPage, "fpsCap", "FPS Cap", 0, 240, "%d")
	local last = St.fpsCap
	task.spawn(function()
		while true do
			if St.fpsCap ~= last then
				last = St.fpsCap
				pcall(function() setfpscap(last <= 0 and 9999 or last) end)
			end
			task.wait(0.2)
		end
	end)
end

-- Optimizer — same effect-stripping technique as visual tab's FPS
-- Boost, exposed here under Chilli Hub's own name (aide_3 ~26461).
makeRow(miscPage, "optimizer", "Optimizer", function(on) if on then applyFpsBoost() end end)

-- FPS and Ping HUD
do
	local hud = Instance.new("Frame", gui)
	hud.Name = "YE_FpsPingHud"
	hud.Size = UDim2.new(0,86,0,34)
	hud.Position = UDim2.new(0,8,0,8)
	hud.BackgroundColor3 = C.BG; hud.BackgroundTransparency = 0.15
	hud.BorderSizePixel = 0; hud.Visible = false
	corner(hud, 8); addLivingStroke(hud, 1)
	local fpsLbl = label(hud, "FPS --", UDim2.new(1,-8,0,16), C.GREEN, Enum.Font.GothamBold)
	fpsLbl.Position = UDim2.new(0,4,0,2); fpsLbl.TextSize = 11
	local pingLbl = label(hud, "Ping --ms", UDim2.new(1,-8,0,14), C.SILVER, Enum.Font.Gotham)
	pingLbl.Position = UDim2.new(0,4,0,18); pingLbl.TextSize = 9.5

	local frames, lastT = 0, os.clock()
	RunService.RenderStepped:Connect(function()
		if not St.fpsPingHud then return end
		frames = frames + 1
		local now = os.clock()
		if now - lastT >= 1 then
			fpsLbl.Text = string.format("FPS %d", math.floor(frames / (now - lastT)))
			frames = 0; lastT = now
			local ok, ping = pcall(function()
				return math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())
			end)
			pingLbl.Text = ok and string.format("Ping %dms", ping) or "Ping --ms"
		end
	end)
	makeRow(miscPage, "fpsPingHud", "FPS and Ping HUD", function(on) hud.Visible = on end)
end


-- Auto Hit Nearest / Auto Hit Aura — Chilli Hub's exclusive combat
-- target group (CreateExclusiveGroup MaxActive=1, aide_3 ~17855-17894):
-- turning one on switches the other off. Forward-declared so each
-- toggle's callback can stop+resync the other.
local stopHitNearest, startHitNearest, stopHitAura, startHitAura
local _hitRefresh = {}

local _hitNearestConn = nil
function stopHitNearest() if _hitNearestConn then _hitNearestConn:Disconnect(); _hitNearestConn = nil end end
function startHitNearest()
	stopHitNearest()
	local _t = 0
	_hitNearestConn = RunService.Heartbeat:Connect(function(dt)
		if not St.autoHitNearest then return end
		_t = _t + dt; if _t < 0.3 then return end; _t = 0
		pcall(function()
			local char = LP.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			local best, bestD = nil, math.huge
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= LP and plr.Character then
					local h = plr.Character:FindFirstChild("HumanoidRootPart")
					if h then
						local d = (h.Position - hrp.Position).Magnitude
						if d < bestD then bestD = d; best = h end
					end
				end
			end
			if best then
				_fireRE("RE/BatSwing/Trigger", {serverTime = workspace:GetServerTimeNow(), targetCFrame = best.CFrame})
			end
		end)
	end)
end
sectionHeader(miscPage, "Combat")
do
	local _, _, refresh = makeRow(miscPage, "autoHitNearest", "Auto Hit Nearest", function(on)
		if on then
			if St.autoHitAura then St.autoHitAura = false; stopHitAura(); if _hitRefresh.Aura then _hitRefresh.Aura() end end
			startHitNearest()
		else stopHitNearest() end
	end)
	_hitRefresh.Nearest = refresh
end

local _hitAuraConn = nil
function stopHitAura() if _hitAuraConn then _hitAuraConn:Disconnect(); _hitAuraConn = nil end end
function startHitAura()
	stopHitAura()
	local _t = 0
	_hitAuraConn = RunService.Heartbeat:Connect(function(dt)
		if not St.autoHitAura then return end
		_t = _t + dt; if _t < 0.3 then return end; _t = 0
		pcall(function()
			local char = LP.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= LP and plr.Character then
					local h = plr.Character:FindFirstChild("HumanoidRootPart")
					if h and (h.Position - hrp.Position).Magnitude <= St.hitSweep then
						_fireRE("RE/BatSwing/Trigger", {serverTime = workspace:GetServerTimeNow(), targetCFrame = h.CFrame})
					end
				end
			end
		end)
	end)
end
do
	local _, _, refresh = makeRow(miscPage, "autoHitAura", "Auto Hit Aura", function(on)
		if on then
			if St.autoHitNearest then St.autoHitNearest = false; stopHitNearest(); if _hitRefresh.Nearest then _hitRefresh.Nearest() end end
			startHitAura()
		else stopHitAura() end
	end)
	_hitRefresh.Aura = refresh
	makeSlider(miscPage, "hitSweep", "Hit Sweep", 0, 100, "%d studs")
end


-- ============================================================
-- HOPPER — switch servers (Server Hop)
-- ============================================================
-- Goes through the public Roblox API (list of servers for the same
-- PlaceId) via an HTTP function provided by the executor
-- (request/http_request/syn.request) to pick a server DIFFERENT from
-- the current JobId, then TeleportToPlaceInstance onto it. If no HTTP
-- function is available, falls back to a plain Teleport (rejoin — no
-- guarantee of a different server, but never crashes).
local function _getHttpFn()
	if type(request) == "function" then return request end
	if type(http_request) == "function" then return http_request end
	if type(syn) == "table" and type(syn.request) == "function" then return syn.request end
	if type(fluxus) == "table" and type(fluxus.request) == "function" then return fluxus.request end
	return nil
end
hopServer = function()
	local placeId = game.PlaceId
	local httpFn = _getHttpFn()
	if not httpFn then
		setStatus("Hopper: plain rejoin (no HTTP available)", C.YELLOW)
		pcall(function() game:GetService("TeleportService"):Teleport(placeId, LP) end)
		return
	end
	setStatus("Hopper: searching...", C.ACCENT2)
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
						table.insert(candidates, srv)
					end
				end
			end
		end)
		if #candidates > 0 then
			-- Server Hop Mode (Chilli Hub exact options, aide_3 ~25201-25208)
			local mode = St.serverHopMode
			if mode == "Most Players" then
				table.sort(candidates, function(a,b) return a.playing > b.playing end)
			elseif mode == "Least Players" then
				table.sort(candidates, function(a,b) return a.playing < b.playing end)
			end
			local pick = (mode == "Random") and candidates[math.random(1, #candidates)].id or candidates[1].id
			setStatus("Hopper -> new server", C.GREEN)
			pcall(function() game:GetService("TeleportService"):TeleportToPlaceInstance(placeId, pick, LP) end)
		else
			setStatus("Hopper: no free server, rejoining", C.YELLOW)
			pcall(function() game:GetService("TeleportService"):Teleport(placeId, LP) end)
		end
	end)
end
-- ============================================================
-- FLOATING DOCK — Speed / Steal Panel / Events / Lock
-- ============================================================
do
local FLOAT_SZ, FLOAT_GAP, FLOAT_TOP, FLOAT_RIGHT_OFF = 38, 6, 66, 10
local _floatDefs = {
	{ id="speed",  label="Speed" }, { id="lock", label="Lock" },
	{ id="steal",  label="Steal\nPanel" }, { id="events", label="Events" },
}
local _floatBtns = {}

local function makeFloatBtn(defIdx, def)
	local col = (defIdx-1) % 2
	local row = math.floor((defIdx-1)/2)
	local xOff = -(FLOAT_SZ*2 + FLOAT_GAP + FLOAT_RIGHT_OFF) + col*(FLOAT_SZ+FLOAT_GAP)
	local yOff = FLOAT_TOP + row*(FLOAT_SZ+FLOAT_GAP)

	local btn = Instance.new("TextButton", gui)
	btn.Name = "YE_Float_"..def.id
	btn.Size = UDim2.new(0,FLOAT_SZ,0,FLOAT_SZ)
	btn.Position = UDim2.new(1,xOff,0,yOff)
	btn.BackgroundColor3 = C.ROW; btn.BorderSizePixel = 0
	btn.Text = ""; btn.AutoButtonColor = false
	btn.ZIndex = 500; btn.Active = true
	corner(btn, 11)
	local st2 = stroke(btn, C.BORDER, 1.5)
	local stGrad = Instance.new("UIGradient", st2)
	stGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,C.DEEP1), ColorSequenceKeypoint.new(0.5,C.DEEP2), ColorSequenceKeypoint.new(1,C.DEEP1),
	})
	table.insert(_liveGrads, stGrad)

	local lbl2 = Instance.new("TextLabel", btn)
	lbl2.Size = UDim2.new(1,0,1,0); lbl2.BackgroundTransparency = 1
	lbl2.Text = def.label; lbl2.TextColor3 = C.WHITE; lbl2.Font = Enum.Font.GothamBold
	lbl2.TextSize = 8; lbl2.TextWrapped = true; lbl2.ZIndex = btn.ZIndex+1
	local lPad = Instance.new("UIPadding", lbl2)
	lPad.PaddingLeft = UDim.new(0,3); lPad.PaddingRight = UDim.new(0,3)

	local dot = Instance.new("Frame", btn)
	dot.Size = UDim2.new(0,7,0,7); dot.Position = UDim2.new(1,-10,0,3)
	dot.BackgroundColor3 = C.GREEN; dot.BorderSizePixel = 0; dot.Visible = false
	dot.ZIndex = lbl2.ZIndex+1
	corner(dot, 4)

	local function setActive(on)
		TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = on and Color3.fromRGB(18,30,50) or C.ROW}):Play()
		dot.Visible = on
	end

	-- drag (unless locked); a drag past a few pixels does not count as a click
	local drag2, dStart, dPos2, moved = false, nil, nil, false
	btn.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			drag2 = not St.floatLocked; dStart = inp.Position; dPos2 = btn.Position; moved = false
		end
	end)
	UIS.InputChanged:Connect(function(inp)
		if not drag2 then return end
		if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
			local delta = inp.Position - dStart
			if delta.Magnitude > 4 then moved = true end
			btn.Position = UDim2.new(dPos2.X.Scale, dPos2.X.Offset+delta.X, dPos2.Y.Scale, dPos2.Y.Offset+delta.Y)
		end
	end)
	UIS.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			drag2 = false
		end
	end)

	_floatBtns[def.id] = { btn = btn, setActive = setActive, wasDragged = function() return moved end }
	return btn, setActive
end

for i, def in ipairs(_floatDefs) do
	local _, setAct = makeFloatBtn(i, def)
	local fb = _floatBtns[def.id]
	if def.id == "speed" then
		setAct(St.speedOn)
		fb.btn.MouseButton1Click:Connect(function()
			if fb.wasDragged() then return end
			if St.speedOn then stopSpeed() else startSpeed() end
			setAct(St.speedOn)
			speedRefresh()
			saveConfig()
		end)
	elseif def.id == "steal" then
		setAct(stealWin.IsOpen())
		stealWin.OnChange(setAct)
		fb.btn.MouseButton1Click:Connect(function()
			if fb.wasDragged() then return end
			stealWin.SetOpen(not stealWin.IsOpen())
		end)
	elseif def.id == "events" then
		setAct(eventsWin.IsOpen())
		eventsWin.OnChange(setAct)
		fb.btn.MouseButton1Click:Connect(function()
			if fb.wasDragged() then return end
			eventsWin.SetOpen(not eventsWin.IsOpen())
		end)
	elseif def.id == "lock" then
		setAct(St.floatLocked)
		fb.btn.MouseButton1Click:Connect(function()
			St.floatLocked = not St.floatLocked
			setAct(St.floatLocked)
			saveConfig()
		end)
	end
end
end

-- ============================================================
-- MINIMIZE / CLOSE / KEYBIND (main window; drag = Win.Drag)
-- ============================================================
Win.Drag(header, main)

local minimized, fullHeight = false, WIN_H
minBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	if minimized then
		TweenService:Create(main, TweenInfo.new(0.2), {Size=UDim2.new(0,WIN_W,0,42)}):Play()
		contentArea.Visible = false; sep.Visible = false; tabBar.Visible = false
		minBtn.Text = "+"
	else
		TweenService:Create(main, TweenInfo.new(0.2), {Size=UDim2.new(0,WIN_W,0,fullHeight)}):Play()
		contentArea.Visible = true; sep.Visible = true; tabBar.Visible = true
		minBtn.Text = "–"
	end
end)
closeBtn.MouseButton1Click:Connect(function()
	pcall(function() St.autoFarm = false; Steal.Abort(); if St.speedOn then stopSpeed() end end)
	gui:Destroy()
end)

UIS.InputBegan:Connect(function(inp, gp)
	if gp then return end
	if inp.KeyCode == Enum.KeyCode.RightShift then
		St.guiVisible = not St.guiVisible
		main.Visible = St.guiVisible
	end
end)

switchTab("Farm")

-- ============================================================
-- RESTORED TOGGLE ACTIVATION
-- ============================================================
if _savedConfig then
	for key, onToggle in pairs(_toggleRegistry) do
		if St[key] == true and onToggle then pcall(onToggle, true) end
	end
	if St.speedOn then startSpeed(); if speedRefresh then speedRefresh() end end
end

print("[MoonEgg] Loaded — RightShift hides/shows the main window | Dock: Speed, Lock, Steal Panel, Events")
