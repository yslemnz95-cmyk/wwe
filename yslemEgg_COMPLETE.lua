-- ============================================================
-- yslemEgg — Steal An Egg Hub
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
	local old = game:GetService("CoreGui"):FindFirstChild("yslemEggGui")
	if old then old:Destroy() end
	local old2 = LP.PlayerGui:FindFirstChild("yslemEggGui")
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

local _MODULE_NAMES = {
	"EggCmds","Network","Ragdoll","GuardEscapePrediction","GuardChasePolicy",
	"ResolveGuardSpeedRequirement","SpeedPowerProjection","Guards","Areas",
	"AreaEggSlotIdentity","Save","Constants","Bases","Treadmills","Trails","EggState",
	"Assets","Mutations",
}
do
	local lines = {"[yslemEgg] Game module status:"}
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
		print("[yslemEgg] AreaEggSlotIdentity — available keys:\n  "..table.concat(keys, "\n  "))
	end)
end

-- ============================================================
-- CONFIRMED REMOTES (ReplicatedStorage.Packages.Networking)
-- ============================================================
-- The yslemEgg analysis report listed the game's real Remote* instances
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
local _Egg = {}
do
	local function dirEntry(assetCategory)
		local dir = _M.Assets and _M.Assets.Directory
		local e = type(dir) == "table" and dir[tostring(assetCategory)] or nil
		return type(e) == "table" and e or nil
	end
	_Egg.DirEntry = dirEntry
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
				print("[yslemEgg] AskFieldEggSnapshot: unavailable or returned non-table")
			end
		else
			if not _snapshotDebugPrinted then
				_snapshotDebugPrinted = true
				local dumpOk, dump = pcall(function() return HttpService:JSONEncode(snap) end)
				print("[yslemEgg] AskFieldEggSnapshot (first result):")
				print(dumpOk and dump:sub(1, 800) or "<not serializable>")
			end
			-- Seed _fieldEggNet from snap.Records (Chilli Hub format).
			-- snap = {Records = [{Uid, State, BottomCFrame, AssetCategory, AssetScale, AreaId}]}
			local now2 = tick()
			pcall(function()
				local records = type(snap) == "table" and snap.Records or nil
				if type(records) ~= "table" then return end
				for _, record in ipairs(records) do
					if type(record) ~= "table" then continue end
					local uid2 = record.Uid and tostring(record.Uid) or nil
					if not uid2 then continue end
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
						t=now2, enabled=true, farmable=true,
					}
				end
			end)
		end
	end
end)

local _eggScanPromptTotal, _eggScanPromptEnabled = 0, 0
local cachedEggs = {}
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
	instantGrab      = false,
	autoFarm         = false,
	autoHatch        = false,
	autoEquip        = false,
	autoClaim        = false,
	autoUpgradePen   = false,
	autoUpgradeTM    = false,
	autoBuyTrails    = false,
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
	stealPriority    = "Highest Value",
	stealTargetEggs  = {},
	stealTweenPct    = 100,
	stealCarryPct    = 100,

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
	hitTweenPct      = 100,
	hitMaxSpeed      = 90,
	hitLead          = 0,
	hitSweep         = 4,

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
	serverHopMode    = "Manual",
	autoRejoin       = true,
}

-- ============================================================
-- SAVE / LOAD
-- ============================================================
-- Deliberately excluded: Bypass Anti-Cheat (never re-applied alone on
-- load — a risky action on the character) and AimBat (aggressive
-- behavior, must only start on a fresh click).
local CONFIG_FILE = "yslemEgg_Config.json"
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
-- UNIFIED MOVEMENT ENGINE
-- ============================================================
-- [MAJOR FIX] The old version ran TWO separate movement systems side
-- by side: Speed Boost (proxy Part + continuous AssemblyLinearVelocity)
-- and Auto Farm (Tween + one-off PlatformStand). When both were active
-- (Speed Boost staying on across sessions thanks to the save), they
-- fought over character control every frame — Auto Farm's Tween got
-- overwritten by the proxy's continuous writes, causing broken or dead
-- movement. Anti Ragdoll (ChangeState every 0.1s) also cut the swoop's
-- PlatformStand mid-path. A single movement authority per frame,
-- chosen by priority, eliminates these conflicts: AimBat (drives hrp
-- directly, top priority — combat) > Auto Farm (actively pathing to an
-- egg) > Speed Boost (manual WASD movement).
local _aimBatActive = false
local _farmMoving = false
local _farmTargetPos = nil
local _farmSpeed = 40
-- Filled in by the Auto Farm loop further below — exposed here so the
-- "autoFarm" toggle can force a COMPLETE, IMMEDIATE stop on click
-- (instead of waiting up to 0.2s for the next loop pass).
local _farmFullStopRef = function() end

-- (do..end block: these variables are only used by the movement
-- engine — releasing them from the root chunk's local count after
-- "end", same 200-local limit as for the palette, see comment above)
--
-- Auto Farm pathing only (proxy Part + AssemblyLinearVelocity). Speed
-- Boost itself is a SEPARATE system below — matches the game's real
-- Speed Boost technique (direct Humanoid.WalkSpeed override + treadmill
-- dismount + RE/RigSync/AskRigWipe to stop the server correcting it
-- back down), not a velocity proxy.
do
	local _proxy, _ownConn = nil, nil
	local _ownTimer, _ownInterval = 0, 0.8 + math.random()*0.4

	local function _claimOwn(hrp) pcall(function() hrp:SetNetworkOwner(LP) end) end
	local function _cleanProxy()
		if _ownConn then pcall(function() _ownConn:Disconnect() end); _ownConn = nil end
		if _proxy then pcall(function() _proxy:Destroy() end); _proxy = nil end
	end
	local function _ensureProxy(hrp)
		local char = hrp.Parent
		if _proxy and _proxy.Parent == char then return _proxy end
		_cleanProxy()
		local p = Instance.new("Part")
		p.Name = "YE_Proxy"; p.Size = Vector3.new(1,1,1)
		p.Transparency = 1; p.CanCollide = false; p.Massless = true
		p.Parent = char
		local w = Instance.new("Weld", p)
		w.Part0 = hrp; w.Part1 = p; w.C0 = CFrame.new()
		_proxy = p
		_claimOwn(hrp)
		_ownConn = hrp:GetPropertyChangedSignal("ReceiveAge"):Connect(function()
			if _farmMoving then task.defer(function() _claimOwn(hrp) end) end
		end)
		return p
	end

	RunService.RenderStepped:Connect(function(dt)
		local char = LP.Character
		if not char then _cleanProxy(); return end
		if _aimBatActive then return end  -- AimBat drives hrp directly, don't interfere

		local hum = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp then _cleanProxy(); return end

		if not _farmMoving then _cleanProxy(); return end

		local st = hum:GetState()
		if hum.PlatformStand or st == Enum.HumanoidStateType.Physics
			or st == Enum.HumanoidStateType.Ragdoll or st == Enum.HumanoidStateType.FallingDown then
			_cleanProxy(); return
		end

		_ownTimer = _ownTimer + dt
		if _ownTimer >= _ownInterval then
			_claimOwn(hrp); _ownTimer = 0; _ownInterval = 0.8 + math.random()*0.4
		end

		local px = _ensureProxy(hrp)

		if _farmTargetPos then
			local delta = _farmTargetPos - hrp.Position
			local flat = Vector3.new(delta.X, 0, delta.Z)
			if flat.Magnitude > 1 then
				local dir = flat.Unit
				px.AssemblyLinearVelocity = Vector3.new(dir.X*_farmSpeed, hrp.AssemblyLinearVelocity.Y, dir.Z*_farmSpeed)
			else
				px.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
			end
		end
	end)
	LP.CharacterAdded:Connect(function() _cleanProxy() end)
end

-- ============================================================
-- SPEED BOOST — exact Chilli Hub technique: AssemblyLinearVelocity-based
-- (NOT WalkSpeed). Dismount treadmill first (AskDoff x2) + AskRigWipe.
-- On each Heartbeat: project MoveDirection onto XZ plane * speed and set
-- hrp.AssemblyLinearVelocity, preserving Y. Skip during ragdoll / sit /
-- platform-stand. Reset velocity on stop.
-- ============================================================
local startSpeed, stopSpeed
do
	local _speedActive  = false
	local _speedBoosted = false
	local _speedConn    = nil

	local function _dismountTreadmill()
		local r = _getRemote("RF/Treadmill/AskDoff")
		if r and r:IsA("RemoteFunction") then
			for _ = 1, 2 do pcall(function() r:InvokeServer() end) end
		end
	end
	local function _wipeRig()
		local r = _getRemote("RE/RigSync/AskRigWipe")
		if r and r:IsA("RemoteEvent") then pcall(function() r:FireServer() end) end
	end
	local function _resetBoostedVelocity()
		if not _speedBoosted then return end
		_speedBoosted = false
		pcall(function()
			local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
			end
		end)
	end

	startSpeed = function()
		St.speedOn = true
		_speedActive = true
		_dismountTreadmill()
		_wipeRig()
		if _speedConn then _speedConn:Disconnect() end
		_speedConn = RunService.Heartbeat:Connect(function()
			if not _speedActive then return end
			local char = LP.Character
			local hrp  = char and char:FindFirstChild("HumanoidRootPart")
			local hum  = char and char:FindFirstChildOfClass("Humanoid")
			if not hrp or not hum or hum.Sit or hum.PlatformStand then
				_resetBoostedVelocity(); return
			end
			local ragEnd = tonumber(LP:GetAttribute("RagdollEndTime"))
			if ragEnd and ragEnd > workspace:GetServerTimeNow() then
				_resetBoostedVelocity(); return
			end
			local dir = Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z)
			if dir.Magnitude <= 0.001 then
				_resetBoostedVelocity(); return
			end
			local vel = dir.Unit * St.speed
			pcall(function()
				hrp.AssemblyLinearVelocity = Vector3.new(vel.X, hrp.AssemblyLinearVelocity.Y, vel.Z)
			end)
			_speedBoosted = true
		end)
	end
	stopSpeed = function()
		St.speedOn = false
		_speedActive = false
		if _speedConn then _speedConn:Disconnect(); _speedConn = nil end
		_resetBoostedVelocity()
	end
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

-- Section header — visual grouping for a block of rows.
local function sectionHeader(page, text)
	local wrap = Instance.new("Frame", page)
	wrap.Size = UDim2.new(1,-12,0,18)
	wrap.BackgroundTransparency = 1
	local lbl = label(wrap, text:upper(), UDim2.new(1,-8,1,0), C.DIM, Enum.Font.GothamBold)
	lbl.TextSize = 9
	lbl.Position = UDim2.new(0,4,0,0)
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
gui.Name = "yslemEggGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = LP.PlayerGui end

-- Main window — compact size (reduced from the original 300x340), spawns centered on screen.
local main = Instance.new("Frame", gui)
main.Name = "Main"
main.Size = UDim2.new(0,248,0,268)
main.Position = UDim2.new(0.5,-124,0.5,-134)
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

local titleLbl = Instance.new("TextLabel", header)
titleLbl.BackgroundTransparency = 1
titleLbl.Size = UDim2.new(1,-50,1,0)
titleLbl.Position = UDim2.new(0,12,0,0)
titleLbl.Text = "yslemEgg"
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
local tabBtns, tabFlashes = {}, {}
for _, name in ipairs(TABS) do
	local btn = Instance.new("TextButton", tabBar)
	btn.Size = UDim2.new(0,40,0,24)
	btn.BackgroundColor3 = Color3.fromRGB(18,22,30)
	btn.BackgroundTransparency = 0.5
	btn.Text = name; btn.TextSize = 10
	btn.TextColor3 = C.TABIDLE; btn.Font = Enum.Font.GothamBold
	btn.BorderSizePixel = 0
	corner(btn, 9)
	addLivingStroke(btn, 1)
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
-- Mutations/Species). yslemEgg_1.lua's design system has no
-- multi-select primitive, so this adds one reusable overlay in the
-- same visual language (rows, living stroke, corner radius) instead
-- of a one-off per feature.
-- ============================================================
local _msOverlay, _msTitle, _msList
local function _ensureMultiSelectOverlay()
	if _msOverlay then return end
	local ov = Instance.new("Frame", main)
	ov.Name = "MultiSelectOverlay"
	ov.Size = UDim2.new(1,0,1,-CONTENT_Y)
	ov.Position = UDim2.new(0,0,0,CONTENT_Y)
	ov.BackgroundColor3 = C.BG
	ov.BorderSizePixel = 0
	ov.Visible = false
	ov.ZIndex = 300
	_msOverlay = ov

	local head = Instance.new("Frame", ov)
	head.Size = UDim2.new(1,0,0,26)
	head.BackgroundTransparency = 1
	head.ZIndex = 301
	_msTitle = label(head, "", UDim2.new(1,-56,1,0), C.WHITE, Enum.Font.GothamBold)
	_msTitle.Position = UDim2.new(0,6,0,0)
	_msTitle.ZIndex = 301
	_msTitle.TextSize = 11.5

	local closeBtn = Instance.new("TextButton", head)
	closeBtn.Size = UDim2.new(0,46,0,20)
	closeBtn.Position = UDim2.new(1,-50,0,2)
	closeBtn.BackgroundColor3 = C.MOON
	closeBtn.Text = "Done"
	closeBtn.TextColor3 = C.MOONTEXT
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 10.5
	closeBtn.BorderSizePixel = 0
	closeBtn.ZIndex = 301
	corner(closeBtn, 6)
	closeBtn.MouseButton1Click:Connect(function() _msOverlay.Visible = false end)

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
	_msList = list
end

-- getOptionsFn(): -> array of option strings, re-evaluated on every open
-- (covers dynamic lists: live area names, the egg Directory, etc.).
-- selectedSet: caller-owned table, key=option -> true when selected.
-- Empty selectedSet means "match everything" — same fallback Chilli Hub
-- uses for its MultiDropdowns (`if next(sel) == nil then` -> select all).
local function makeMultiSelect(page, displayName, getOptionsFn, selectedSet, onChange)
	_ensureMultiSelectOverlay()
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
		_msTitle.Text = displayName
		for _, c in ipairs(_msList:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		local opts = getOptionsFn() or {}
		for i, opt in ipairs(opts) do
			local r = Instance.new("Frame", _msList)
			r.Size = UDim2.new(1,0,0,26)
			r.BackgroundColor3 = C.ROW
			r.BackgroundTransparency = 0.35
			r.BorderSizePixel = 0
			r.ZIndex = 301
			r.LayoutOrder = i
			corner(r, 6)
			local olbl = label(r, opt, UDim2.new(1,-40,1,0), C.SILVER, Enum.Font.GothamMedium)
			olbl.Position = UDim2.new(0,8,0,0)
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
		_msOverlay.Visible = true
	end)

	return refreshCount
end

-- ============================================================
-- FARM TAB
-- ============================================================
local farmPage = pages["Farm"]

sectionHeader(farmPage, "Grab")

-- Instant Grab
local _instaGrabConn = nil
local _instaGrabOriginal = setmetatable({}, {__mode = "k"})
local function setInstantGrab(on)
	St.instantGrab = on
	if on then
		if _instaGrabConn then return end
		_instaGrabConn = ProximityPromptService.PromptShown:Connect(function(prompt)
			if not St.instantGrab then return end
			if _instaGrabOriginal[prompt] == nil then _instaGrabOriginal[prompt] = prompt.HoldDuration end
			prompt.HoldDuration = 0
		end)
	else
		if _instaGrabConn then _instaGrabConn:Disconnect(); _instaGrabConn = nil end
		for prompt, orig in pairs(_instaGrabOriginal) do
			pcall(function() if prompt and prompt.Parent then prompt.HoldDuration = orig end end)
		end
	end
end
makeRow(farmPage, "instantGrab", "Instant Grab", function(on) setInstantGrab(on) end)

-- Auto Farm — unified engine (no more Tween fighting Speed
-- Boost/Anti Ragdoll). Safety timeout per trip: never stuck forever
-- even if the trip fails. After a grab, runs to the safe zone (escape
-- the guards) instead of standing idle on the egg. EVERYTHING stops
-- immediately (movement + spam) as soon as Auto Farm is disabled —
-- checked live inside every wait loop AND forced on click via
-- _farmFullStopRef (see makeRow further below). Runs silently — no
-- status spam that would drown out other features' status messages.
task.spawn(function()
	local isFarmingEgg = false
	local function _farmFullStop()
		_farmMoving = false
		_farmTargetPos = nil
		isFarmingEgg = false
	end
	_farmFullStopRef = _farmFullStop

	-- Tollbox grab engine: mirrors yslem_hub AutoSteal approach.
	-- Per-prompt data is cached on first encounter: extract internal
	-- PromptButtonHoldBegan / Triggered handlers via getconnections()
	-- so we can fire them directly (most reliable), then fall through to
	-- fireproximityprompt → InputHoldBegin/End as progressively coarser
	-- fallbacks.
	local _stealData  = {}
	local _HOLD_DUR   = 0.12  -- seconds, matches typical hold-prompt threshold

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
			if #d.hold > 0 or #d.trigger > 0 then
				d.useFallback = false
			end
		end)
	end

	-- Find the CarryAreaEgg ProximityPrompt on the nearest SmartPromptPart
	-- within maxDist studs of eggPos (Chilli Hub exact technique).
	local function _findCarryPrompt(eggPos, maxDist)
		maxDist = maxDist or 14
		local best, bestDist = nil, maxDist
		for _, child in ipairs(workspace:GetChildren()) do
			if child.Name == "SmartPromptPart" and child:IsA("BasePart") then
				local carryAreaEgg = child:FindFirstChild("CarryAreaEgg")
				if carryAreaEgg and carryAreaEgg:IsA("ProximityPrompt") then
					local d = (child.Position - eggPos).Magnitude
					if d < bestDist then bestDist = d; best = carryAreaEgg end
				end
			end
		end
		return best
	end

	local function _tryGrab(target)
		pcall(function()
			-- Primary: CarryAreaEgg on nearest SmartPromptPart (Chilli Hub technique).
			local carryPrompt = _findCarryPrompt(target.pos)
			if carryPrompt then
				pcall(function() carryPrompt.HoldDuration = 0 end)
				if fireproximityprompt then pcall(fireproximityprompt, carryPrompt) end
			end
			-- Fallback: explicit prompt from source-3 scan.
			if target.prompt and target.prompt ~= carryPrompt then
				pcall(function() target.prompt.HoldDuration = 0 end)
				if fireproximityprompt then pcall(fireproximityprompt, target.prompt) end
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
			-- Only target READY and FARMABLE eggs (never your own eggs
			-- already in a slot — see scanner source 2), island filter applied.
			local myPos = rootPart.Position
			-- Fuzzy zone match: exact → case-insensitive substring both ways.
			-- Handles AREA key names that differ in case or carry a suffix
			-- vs the FARM_ZONES canonical names (e.g. "ForestArea" vs "Forest").
			local fzLow = St.farmZone:lower()
			local function _zoneOk(area)
				if St.farmZone == "" then return true end
				if not area or area == "?" then return false end
				if area == St.farmZone then return true end
				local al = area:lower()
				return al:find(fzLow,1,true)~=nil or fzLow:find(al,1,true)~=nil
			end
			-- Chilli Hub exact filters: Min Rarity, Min Steal Value, Target
			-- Specific Eggs (empty selection = match every species).
			local minVal = St.stealMinValueK * 1000
			local hasTargetSet = next(St.stealTargetEggs) ~= nil
			local candidates = {}
			for _, r in ipairs(cachedEggs) do
				if r.enabled and r.farmable ~= false and _zoneOk(r.area)
					and (r.rarity or 0) >= St.stealMinRarity
					and (r.value or 0) >= minVal
					and (not hasTargetSet or St.stealTargetEggs[r.mutation or ""]) then
					table.insert(candidates, r)
				end
			end
			-- Steal Priority (Chilli Hub tbl5, exact 5 modes): sorts the
			-- filtered pool; distance is always the final tiebreaker.
			local priority = St.stealPriority
			table.sort(candidates, function(a, b)
				local av, bv
				if priority == "Best Rarity" then av, bv = a.rarity or 0, b.rarity or 0
				elseif priority == "Biggest Weight" then av, bv = a.scale or 0, b.scale or 0
				elseif priority == "Best Mutation" then av, bv = (a.tags and #a.tags or 0), (b.tags and #b.tags or 0)
				elseif priority == "Lowest Value" then av, bv = -(a.value or 0), -(b.value or 0)
				else av, bv = a.value or 0, b.value or 0 end
				if av ~= bv then return av > bv end
				return (a.pos - myPos).Magnitude < (b.pos - myPos).Magnitude
			end)
			local best = candidates[1]

			if best then
				isFarmingEgg = true
				_farmMoving = true
				_farmTargetPos = best.pos
				_farmSpeed = math.max(St.speed, 40) * (St.stealTweenPct / 100)

				-- Remove the target from the network cache right away:
				-- avoids re-selecting the same egg in a loop if the world
				-- takes time to confirm the grab.
				if best.uid then _fieldEggNet[best.uid] = nil end

				-- Grab attempts, moderate rate throughout the approach —
				-- fast enough to catch the window, not so fast it risks
				-- being ignored/rate-limited by the server.
				local spamming = true
				task.spawn(function()
					while spamming do
						_tryGrab(best)
						task.wait(0.2)
					end
				end)

				local t0 = os.clock()
				while St.autoFarm and _farmMoving and (os.clock()-t0) < 6 do
					local hrp2 = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
					if not hrp2 then break end
					if (hrp2.Position - best.pos).Magnitude < 4 then break end
					task.wait(0.1)
				end
				_farmMoving = false

				-- Linger near the egg, still attempting the grab, in case
				-- the server takes a moment to process it.
				local t0b = os.clock()
				while St.autoFarm and (os.clock()-t0b) < 1.5 do task.wait(0.1) end
				spamming = false

				if St.autoFarm then
					-- Run to the safe zone to secure the egg (escape the
					-- guards) — if no safe zone is found, just resume
					-- farming instead of getting stuck.
					local safePos = _findSafeZonePos()
					if safePos then
						_farmMoving = true
						_farmTargetPos = safePos
						_farmSpeed = math.max(St.speed, 40) * (St.stealCarryPct / 100)

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
makeRow(farmPage, "autoFarm", "Auto Farm Eggs", function(on)
	if not on then _farmFullStopRef() end
end)

-- ============================================================
-- ISLAND PICKER (swipeable, always visible under Auto Farm)
-- ============================================================
do
	local FARM_ZONES = {
		"","Forest","Desert","Prehistoric","Abyss Ocean","Snow",
		"Cosmic","Lake","Volcano","Cherry Blossom","Jungle","Titan Temple",
	}
	local FARM_ZONE_LABELS = {
		"All Islands","Forest","Desert","Prehistoric","Abyss Ocean","Snow",
		"Cosmic","Lake","Volcano","Cherry Blossom","Jungle","Titan Temple",
	}

	local selOuter = Instance.new("Frame", farmPage)
	selOuter.Size = UDim2.new(1,-12,0,51)
	selOuter.BackgroundColor3 = C.ROW
	selOuter.BackgroundTransparency = 0.25
	selOuter.BorderSizePixel = 0
	corner(selOuter, 10)
	addLivingStroke(selOuter, 1)
	local selPad = Instance.new("UIPadding", selOuter)
	selPad.PaddingLeft = UDim.new(0,8); selPad.PaddingRight = UDim.new(0,8)
	selPad.PaddingTop = UDim.new(0,6); selPad.PaddingBottom = UDim.new(0,6)

	local zoneCarousel = Instance.new("Frame", selOuter)
	zoneCarousel.Size = UDim2.new(1,0,0,51)
	zoneCarousel.BackgroundTransparency = 1
	makeCarousel(zoneCarousel, "Target Island", FARM_ZONES, FARM_ZONE_LABELS, St.farmZone, function(zv)
		St.farmZone = zv
		saveConfig()
	end)

	makeDivider(farmPage)
end

-- ============================================================
-- AUTO STEAL FILTERS — exact Chilli Hub widget set (aide_3 ~2078-2629):
-- Min Rarity, Target Specific Eggs, Steal Priority, Min Steal Value,
-- Tween/Carry Speed. Target Areas is covered by the Island Picker above.
-- ============================================================
do
	local rarityOptions, rarityValueOf = _Egg.RarityDropdownOptions()
	makeCarousel(farmPage, "Min Rarity", rarityOptions, rarityOptions, rarityOptions[1], function(v)
		St.stealMinRarity = rarityValueOf[v] or 0
		saveConfig()
	end)

	makeMultiSelect(farmPage, "Target Specific Eggs", function()
		local seen, opts = {}, {}
		for _, r in ipairs(cachedEggs) do
			if r.mutation and r.mutation ~= "" and not seen[r.mutation] then
				seen[r.mutation] = true
				table.insert(opts, r.mutation)
			end
		end
		table.sort(opts)
		return opts
	end, St.stealTargetEggs, function() saveConfig() end)

	local STEAL_PRIORITY = {"Best Rarity","Biggest Weight","Best Mutation","Highest Value","Lowest Value"}
	makeCarousel(farmPage, "Steal Priority", STEAL_PRIORITY, STEAL_PRIORITY, St.stealPriority, function(v)
		St.stealPriority = v
		saveConfig()
	end)

	makeSlider(farmPage, "stealMinValueK", "Min Steal Value", 0, 50000, "%dk")
	makeSlider(farmPage, "stealTweenPct", "Tween Speed", 50, 120, "%d%%")
	makeSlider(farmPage, "stealCarryPct", "Carry Speed", 80, 120, "%d%%")
end

-- Auto Hatch / Auto Equip — directly clicks the game's real UI buttons
-- ("Grow All", "Equip Best", confirmed by screenshot) via firesignal —
-- independent of any broken module.
local _guiClickWarned = false
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
	if not _guiClickWarned then
		_guiClickWarned = true
		setStatus("UI click unavailable (missing firesignal)", C.RED)
	end
	return false
end

task.spawn(function()
	local lastHatch = 0
	while true do
		task.wait(1)
		if St.autoHatch and (os.clock()-lastHatch) >= 3 then
			lastHatch = os.clock()
			-- Chilli Hub: AskHatch → wait 0.35s → AskFinishHatch for each ready egg
			local hatched = false
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
										hatched = true
									end
								end
							end
						end
					end
				end
			end)
			-- Fallback: UI button click
			if not hatched then
				_clickGuiButtonByText(function(t) return t:lower():find("grow all", 1, true) ~= nil end)
			end
		end
	end
end)
makeRow(farmPage, "autoHatch", "Auto Hatch", function(on) end)
do
	local rarityOptions, rarityValueOf = _Egg.RarityDropdownOptions()
	makeCarousel(farmPage, "Hatch Min Rarity", rarityOptions, rarityOptions, rarityOptions[1], function(v)
		St.hatchMinRarity = rarityValueOf[v] or 0; saveConfig()
	end)
	makeSlider(farmPage, "hatchMinValueK", "Min Hatch Value", 0, 50000, "%dk")
	makeMultiSelect(farmPage, "Hatch Specific Eggs", function()
		local seen, opts = {}, {}
		for _, r in ipairs(cachedEggs) do
			if r.mutation and r.mutation ~= "" and not seen[r.mutation] then
				seen[r.mutation] = true
				table.insert(opts, r.mutation)
			end
		end
		table.sort(opts)
		return opts
	end, St.hatchSpecificEggs, function() saveConfig() end)
end

task.spawn(function()
	local lastEquip = 0
	while true do
		task.wait(2)
		if St.autoEquip and (os.clock()-lastEquip) >= 4 then
			lastEquip = os.clock()
			_clickGuiButtonByText(function(t) return t:lower():find("equip best", 1, true) ~= nil end)
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

-- Auto Upgrade Pen/Treadmill — real money check (Save.Get confirmed
-- correct) + confirmed real remotes (AskBaseTierRaise, not the
-- wrongly guessed AskWearLimit from an earlier pass).
task.spawn(function()
	local lastPen = 0
	while true do
		task.wait(1.5)
		if St.autoUpgradePen and (os.clock()-lastPen) >= 2 then
			lastPen = os.clock()
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
makeRow(farmPage, "autoUpgradePen", "Auto Upgrade Pen", function(on) end)

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

-- Auto Buy Trails — deliberately disabled (mixed $/Robux prices seen
-- in the Trail Shop, risk of spending real Robux)
local buyTrailsRefresh
local _, _, _btr = makeRow(farmPage, "autoBuyTrails", "Auto Buy Trails", function(on)
	if on then
		setStatus("Buy Trails: disabled for safety (Robux price)", C.YELLOW)
		St.autoBuyTrails = false
		if buyTrailsRefresh then buyTrailsRefresh() end
	end
end)
buyTrailsRefresh = _btr

-- Auto Run Treadmill — disables "Slow Mode" (confirmed by screenshot)
task.spawn(function()
	while true do
		if St.autoRunTreadmill then _invokeRF("RF/Treadmill/AskSlowToggleSet", false) end
		task.wait(10)
	end
end)
makeRow(farmPage, "autoRunTreadmill", "Auto Run Treadmill", function(on) end)

-- ============================================================
-- NOUVELLES FEATURES D'AUTOMATISATION
-- ============================================================
sectionHeader(farmPage, "Auto Actions")

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

-- Auto Place Egg — Chilli Hub: AskPlaceEgg with inventory egg uids,
-- gated by Place Egg Rule and filtered/ordered exactly like aide_3
-- ~7118-7285 (Place Egg Rule/Order, Place Rarities, Place Specific
-- Eggs, Min Place Value).
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
	makeMultiSelect(farmPage, "Place Specific Eggs", function()
		local seen, opts = {}, {}
		for _, r in ipairs(cachedEggs) do
			if r.mutation and r.mutation ~= "" and not seen[r.mutation] then
				seen[r.mutation] = true
				table.insert(opts, r.mutation)
			end
		end
		table.sort(opts)
		return opts
	end, St.placeSpecificEggs, function() saveConfig() end)
	makeSlider(farmPage, "placeMinValueK", "Min Place Value", 0, 50000, "%dk")
end

-- Auto Treadmill (stay mounted continuously)
task.spawn(function()
	while true do
		task.wait(_AD_jitter(2.0))
		if St.autoTreadmill2 then _invokeRF("RF/Treadmill/AskWearStill") end
	end
end)
makeRow(farmPage, "autoTreadmill2", "Auto Treadmill", function(on)
	if not on then _invokeRF("RF/Treadmill/AskDoff") end
end)

-- Auto Sell Pet/Egg — Chilli Hub exact rule set (aide_3 ~8901, 9280-9470):
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
	makeMultiSelect(farmPage, "Blacklist Sell Pets", function()
		local seen, opts = {}, {}
		for _, r in ipairs(cachedEggs) do
			if r.mutation and r.mutation ~= "" and not seen[r.mutation] then
				seen[r.mutation] = true
				table.insert(opts, r.mutation)
			end
		end
		table.sort(opts)
		return opts
	end, St.sellPetBlacklist, function() saveConfig() end)
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
	makeMultiSelect(farmPage, "Blacklist Sell Eggs", function()
		local seen, opts = {}, {}
		for _, r in ipairs(cachedEggs) do
			if r.mutation and r.mutation ~= "" and not seen[r.mutation] then
				seen[r.mutation] = true
				table.insert(opts, r.mutation)
			end
		end
		table.sort(opts)
		return opts
	end, St.sellEggBlacklist, function() saveConfig() end)
end

-- Auto Fuse — Chilli Hub: fuses 3 SAME-SPECIES pets (aide_3 ~9702-9908:
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
	makeMultiSelect(farmPage, "Specific Species to Fuse", function()
		local seen, opts = {}, {}
		for _, r in ipairs(cachedEggs) do
			if r.mutation and r.mutation ~= "" and not seen[r.mutation] then
				seen[r.mutation] = true
				table.insert(opts, r.mutation)
			end
		end
		table.sort(opts)
		return opts
	end, St.fuseSpecificSpecies, function() saveConfig() end)
	makeRow(farmPage, "fuseEjectIncomplete", "Eject Incomplete Slots", function(on) end)
end

-- Auto Favorite — Chilli Hub exact rule set (aide_3 ~10497-10615): each
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
	makeMultiSelect(farmPage, "Always Favorite Species", function()
		local seen, opts = {}, {}
		for _, r in ipairs(cachedEggs) do
			if r.mutation and r.mutation ~= "" and not seen[r.mutation] then
				seen[r.mutation] = true
				table.insert(opts, r.mutation)
			end
		end
		table.sort(opts)
		return opts
	end, St.favoriteAlwaysSpecies, function() saveConfig() end)
	makeRow(farmPage, "autoFavoriteEquipped", "Auto Favorite Equipped", function(on) end)
	makeRow(farmPage, "autoUnfavoriteEquipped", "Auto Unfavorite Equipped", function(on) end)
end

-- Auto Lab Trade-In
task.spawn(function()
	while true do
		task.wait(_AD_jitter(5.0))
		if St.autoLab then
			pcall(function()
				local ok, state = _invokeRF("RF/ScrambleTradeIn/AskState")
				if ok and type(state) == "table" then
					if state.Complete or state.Ready then
						_invokeRF("RF/ScrambleTradeIn/AskTradeIn", state.RecipeId)
					elseif state.Stuck then
						_invokeRF("RF/ScrambleTradeIn/AskRefresh")
					end
				end
			end)
		end
	end
end)
makeRow(farmPage, "autoLab", "Auto Lab Trade-In", function(on) end)

-- Auto Mech Boss
local _mechConn = nil
local function stopMech() if _mechConn then _mechConn:Disconnect(); _mechConn = nil end end
local function startMech()
	stopMech()
	pcall(function() _invokeRF("RF/ScrambleBoss/EnterArena") end)
	local _t = 0
	_mechConn = RunService.Heartbeat:Connect(function(dt)
		if not St.autoMech then return end
		_t = _t + dt; if _t < 0.5 then return end; _t = 0
		pcall(function()
			local boss = workspace:FindFirstChild("ScrambleBoss", true) or workspace:FindFirstChild("Mech", true)
			local bossHRP = boss and (boss:IsA("Model") and boss.PrimaryPart or boss:FindFirstChild("HumanoidRootPart"))
			if bossHRP then
				_fireRE("RE/BatSwing/Trigger", {serverTime = workspace:GetServerTimeNow(), targetCFrame = bossHRP.CFrame})
			end
		end)
	end)
end
makeRow(farmPage, "autoMech", "Auto Mech Boss", function(on)
	if on then startMech() else stopMech() end
end)

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

-- Anti-Guard — exact Chilli Hub technique: react to RagdollEndTime
-- attribute. When a guard hits the player the server sets this attribute.
-- We detect the change instantly and teleport past the guard line before
-- the physics-ragdoll animation finishes, so the player arrives on the
-- safe side with the egg still in hand.
local _antiGuardLink = nil
local function stopAntiGuard()
	if _antiGuardLink then _antiGuardLink:Disconnect(); _antiGuardLink = nil end
end
local function startAntiGuard()
	stopAntiGuard()
	_antiGuardLink = LP:GetAttributeChangedSignal("RagdollEndTime"):Connect(function()
		if not St.antiGuard then return end
		local num = tonumber(LP:GetAttribute("RagdollEndTime"))
		if not num or num <= workspace:GetServerTimeNow() then return end
		task.defer(function()
			pcall(function()
				local char = LP.Character
				local hrp  = char and char:FindFirstChild("HumanoidRootPart")
				if not hrp then return end
				local folder = workspace:FindFirstChild("__OBJECTS")
				folder = folder and folder:FindFirstChild("Areas")
				folder = folder and folder:FindFirstChild("GuardAreas")
				local nearGuardPos = nil
				local nearDist = math.huge
				if folder then
					for _, area in ipairs(folder:GetChildren()) do
						local guard = area:FindFirstChild("Guard")
						if guard then
							local ok, gp = pcall(function() return guard:GetPivot().Position end)
							if ok then
								local d = (gp - hrp.Position).Magnitude
								if d < nearDist then nearDist = d; nearGuardPos = gp end
							end
						end
					end
				end
				local dest
				if nearGuardPos then
					local awayDir = (hrp.Position - nearGuardPos)
					awayDir = Vector3.new(awayDir.X, 0, awayDir.Z)
					if awayDir.Magnitude > 0.1 then
						awayDir = awayDir.Unit
					else
						awayDir = EXIT_DIR
					end
					dest = hrp.Position + awayDir * (nearDist + 8)
				else
					dest = hrp.Position + EXIT_DIR * 30
				end
				hrp.CFrame = CFrame.new(dest)
				hrp.AssemblyLinearVelocity = Vector3.zero
				hrp.AssemblyAngularVelocity = Vector3.zero
			end)
		end)
	end)
end
makeRow(farmPage, "antiGuard", "Anti-Guard", function(on)
	if on then startAntiGuard() else stopAntiGuard() end
end)

-- ============================================================
-- SPEED TAB
-- ============================================================
local speedPage = pages["Speed"]

local speedRow, speedBtn, speedRefresh = makeRow(speedPage, "speedOn", "Speed Boost", function(on)
	if on then startSpeed() else stopSpeed() end
end)
makeSlider(speedPage, "speed", "Boost Speed", 20, 1000, "%d")

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
makeRow(speedPage, "antiRagdoll", "Anti Ragdoll", function(on)
	if on then startAntiRag() else stopAntiRag() end
end)

-- Fly
local _flyConn, _flyBP = nil, nil
local function stopFly()
	if _flyConn then _flyConn:Disconnect(); _flyConn = nil end
	pcall(function() if _flyBP then _flyBP:Destroy(); _flyBP = nil end end)
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum.PlatformStand = false end
end
local function startFly()
	stopFly()
	local char = LP.Character; if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
	local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
	hum.PlatformStand = true
	_flyBP = Instance.new("BodyPosition")
	_flyBP.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	_flyBP.P = 1e4; _flyBP.D = 500
	_flyBP.Position = hrp.Position
	_flyBP.Parent = hrp
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
makeRow(speedPage, "fly", "Fly (WASD + Space)", function(on)
	if on then startFly() else stopFly() end
end)
makeSlider(speedPage, "flySpeed", "Fly Speed", 5, 300, "%d")

-- Anti Trap
local _trapConn, _lastPos, _stuckSince = nil, Vector3.zero, 0
local function stopAntiTrap() if _trapConn then _trapConn:Disconnect(); _trapConn = nil end end
local function startAntiTrap()
	stopAntiTrap()
	local _t = 0
	_trapConn = RunService.Heartbeat:Connect(function()
		if not St.antiTrap then return end
		local now = tick(); if now-_t < 0.5 then return end; _t = now
		local char = LP.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then _lastPos = Vector3.zero; _stuckSince = now; return end
		local moved = (hrp.Position - _lastPos).Magnitude
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
		_lastPos = hrp.Position
	end)
end
makeRow(speedPage, "antiTrap", "Anti Trap", function(on)
	if on then startAntiTrap() else stopAntiTrap() end
end)

-- Instant Prompts
local _ipConn = nil
local _ipOriginal = setmetatable({}, {__mode = "k"})
local function stopInstantPrompts()
	if _ipConn then _ipConn:Disconnect(); _ipConn = nil end
	for prompt, orig in pairs(_ipOriginal) do
		pcall(function() if prompt and prompt.Parent then prompt.HoldDuration = orig end end)
	end
end
local function startInstantPrompts()
	stopInstantPrompts()
	_ipConn = ProximityPromptService.PromptShown:Connect(function(prompt)
		if not St.instantPrompts then return end
		if _ipOriginal[prompt] == nil then _ipOriginal[prompt] = prompt.HoldDuration end
		prompt.HoldDuration = 0
	end)
end
makeRow(speedPage, "instantPrompts", "Instant Prompts", function(on)
	if on then startInstantPrompts() else stopInstantPrompts() end
end)

-- Invisibility
local _invisConn = nil
local function stopInvisibility()
	if _invisConn then _invisConn:Disconnect(); _invisConn = nil end
	local char = LP.Character
	if char then
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") then p.LocalTransparencyModifier = 0 end
		end
	end
end
local function startInvisibility()
	stopInvisibility()
	_invisConn = RunService.RenderStepped:Connect(function()
		if not St.invisibility then return end
		local char = LP.Character
		if not char then return end
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") then p.LocalTransparencyModifier = 1 end
		end
	end)
end
makeRow(speedPage, "invisibility", "Invisibility", function(on)
	if on then startInvisibility() else stopInvisibility() end
end)

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

				-- ESP Show Info picks which lines render, exactly like
				-- Chilli Hub's field list (Icon/Name/Rarity/Mutation/
				-- Value/Weight/Size/Sell Price/Distance/Area/State).
				local lines = {}
				if info.Name or info.Icon then
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
					lbl.Size = UDim2.new(1,0,0,h); lbl.Position = UDim2.new(0,0,0,y)
					lbl.BackgroundTransparency = 1
					lbl.Font = ln.bold and Enum.Font.GothamBold or Enum.Font.Gotham
					lbl.TextSize = ln.size; lbl.TextStrokeTransparency = 0
					lbl.TextColor3 = ln.color; lbl.Text = ln.text
					lbl.TextTruncate = Enum.TextTruncate.AtEnd
					y = y + h
				end
				bb.Size = UDim2.fromOffset(180*sizeMul, math.max(y, 18))

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

local _origBright = nil
local function startFullbright()
	_origBright = Lighting.Brightness
	Lighting.Brightness = 2; Lighting.GlobalShadows = false
	Lighting.Ambient = Color3.fromRGB(200,200,200); Lighting.OutdoorAmbient = Color3.fromRGB(200,200,200)
end
local function stopFullbright()
	Lighting.Brightness = _origBright or 1; Lighting.GlobalShadows = true
	Lighting.Ambient = Color3.fromRGB(70,70,70); Lighting.OutdoorAmbient = Color3.fromRGB(100,100,100)
end
makeRow(visualPage, "fullbright", "Fullbright", function(on) if on then startFullbright() else stopFullbright() end end)

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
makeRow(visualPage, "fpsBoost", "FPS Boost", function(on) if on then applyFpsBoost() end end)

do
	makeSlider(visualPage, "fov", "FOV", 30, 130, "%d°")
	-- makeSlider is generic (doesn't know about the camera) — applies FOV
	-- separately, once immediately then via a small loop watching St.fov
	-- (covers both dragging AND restoring it on load).
	pcall(function() workspace.CurrentCamera.FieldOfView = St.fov end)
	task.spawn(function()
		local last = St.fov
		while true do
			if St.fov ~= last then
				last = St.fov
				pcall(function() workspace.CurrentCamera.FieldOfView = St.fov end)
			end
			task.wait(0.1)
		end
	end)
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
makeRow(visualPage, "antiAFK", "Anti AFK", function(on) if on then startAntiAFK() else stopAntiAFK() end end)

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
					local bb = Instance.new("BillboardGui")
					bb.Size = UDim2.fromOffset(140*sizeMul, 20*sizeMul)
					bb.StudsOffset = Vector3.new(0,2,0)
					bb.AlwaysOnTop = true
					bb.Parent = head
					local l = Instance.new("TextLabel", bb)
					l.Size = UDim2.new(1,0,1,0); l.BackgroundTransparency = 1
					l.Text = text; l.TextColor3 = C.WHITE; l.Font = Enum.Font.GothamBold
					l.TextSize = 12*sizeMul; l.TextStrokeTransparency = 0
					table.insert(_espPlayerParts, bb)
				end
			end
		end
	end)
end
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

-- Bypass Anti-Cheat — a real ON/OFF toggle
local _bypassActive, _bypassCooldown, _bypassOn = false, 0, false
local _bypassPillRefresh, _bypassFloatRefresh = nil, nil
local BYPASS_COOLDOWN_S = 5

local function applyBypass()
	if _bypassActive then return false end
	local now = tick()
	if now - _bypassCooldown < BYPASS_COOLDOWN_S then
		setStatus("Bypass: wait "..math.ceil(BYPASS_COOLDOWN_S-(now-_bypassCooldown)).."s", C.DIM)
		return false
	end
	local char = LP.Character
	local oldHum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not oldHum then setStatus("Bypass: no character", C.RED); return false end
	_bypassActive = true
	local ok = pcall(function()
		local cam = workspace.CurrentCamera
		local wasSubject = cam and cam.CameraSubject == oldHum
		local clone = oldHum:Clone()
		clone.Parent = char
		oldHum:Destroy()
		if cam and wasSubject then cam.CameraSubject = clone end
		pcall(function()
			local pm = LP:FindFirstChild("PlayerScripts")
			local cm = pm and pm:FindFirstChild("PlayerModule")
			if cm then require(cm:FindFirstChild("ControlModule")):Enable() end
		end)
	end)
	_bypassActive = false
	_bypassCooldown = tick()
	setStatus(ok and "Bypass applied" or "Bypass failed — see console", ok and C.GREEN or C.RED)
	task.delay(3, function() if not _bypassActive then setStatus("Idle", C.DIM) end end)
	return ok
end

-- Removing the Bypass: there's nothing to properly "undo" — the clone
-- applyBypass() drops in is a perfectly normal Humanoid once in place
-- (same stats, same behavior). Forcing it to die (hum.Health = 0) to
-- "go back" only caused an unwanted, jarring respawn (reported: "it
-- resets me, doesn't work"). OFF = a simple, honest state flag: the
-- swap already done stays in place until the next natural respawn
-- (death, teleport, Rejoin...) — nothing is destroyed or recreated here.
local function removeBypass()
	setStatus("Bypass disabled (already applied until next respawn)", C.DIM)
	task.delay(3, function() if not _bypassActive then setStatus("Idle", C.DIM) end end)
	return true
end

do
	local row = Instance.new("Frame", miscPage)
	row.Size = UDim2.new(1,-12,0,32)
	row.BackgroundColor3 = C.ROW; row.BorderSizePixel = 0; corner(row, 8)
	local pad = Instance.new("UIPadding", row)
	pad.PaddingLeft = UDim.new(0,10); pad.PaddingRight = UDim.new(0,10)
	label(row, "Bypass Anti-Cheat", UDim2.new(1,-46,1,0), C.WHITE, Enum.Font.GothamMedium).TextSize = 12
	local track, btn, setSwitch = makeSwitch(row, false)
	track.Position = UDim2.new(1,-38,0.5,-10)
	local function refresh() setSwitch(_bypassOn) end
	refresh()
	_bypassPillRefresh = refresh
	btn.MouseButton1Click:Connect(function()
		if not _bypassOn then
			if applyBypass() then _bypassOn = true; refresh() end
		else
			if removeBypass() then _bypassOn = false; refresh() end
		end
	end)
	LP.CharacterAdded:Connect(function()
		_bypassOn = false; refresh()
		if _bypassFloatRefresh then _bypassFloatRefresh(false) end
	end)
end

makeButton(miscPage, "TP to Spawn", "Go", function()
	pcall(function()
		local char = LP.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local spawn = workspace:FindFirstChild("SpawnLocation")
		if hrp and spawn then hrp.CFrame = spawn.CFrame + Vector3.new(0,5,0) end
	end)
end)

-- Go To Main Stand / Stop Movement
local _mainStandTween = nil
do
	local MAIN_STAND_CF = CFrame.new(544.577637, 92.0762939, -364.869049, -1,0,0, 0,1,0, 0,0,-1)
	makeButton(miscPage, "Go To Main Stand", "Go", function()
		local char = LP.Character
		local rootPart = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not rootPart then return end
		if _mainStandTween then _mainStandTween:Cancel() end
		local dist = (rootPart.Position - MAIN_STAND_CF.Position).Magnitude
		local travelTime = math.max(dist/350, 0.1)
		_mainStandTween = TweenService:Create(rootPart, TweenInfo.new(travelTime, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {CFrame = MAIN_STAND_CF})
		_mainStandTween.Completed:Connect(function()
			if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Landed); hum.PlatformStand = false end) end
		end)
		_mainStandTween:Play()
		setStatus("Heading to spawn...", C.ACCENT2)
	end)
	makeButton(miscPage, "Stop Movement", "Stop", function()
		if _mainStandTween then
			_mainStandTween:Cancel(); _mainStandTween = nil
			local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
			if hum then hum.PlatformStand = false end
			setStatus("Movement stopped", C.DIM)
		end
	end, true)
end

-- Infinite Jump — via makeRow (correctly persisted in St.infJump +
-- saveConfig() + re-enabled on load, unlike the old version which used
-- a local `_on` that was never saved)
local _ijConn = nil
makeRow(miscPage, "infJump", "Infinite Jump", function(on)
	if on then
		if _ijConn then _ijConn:Disconnect() end
		_ijConn = UIS.JumpRequest:Connect(function()
			local char = LP.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
		end)
	else
		if _ijConn then _ijConn:Disconnect(); _ijConn = nil end
	end
end)

makeButton(miscPage, "Rejoin Server", "Rejoin", function()
	pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId, LP) end)
end, true)

makeButton(miscPage, "Copy Player ID", "Copy", function()
	pcall(function()
		setclipboard(tostring(LP.UserId))
		setStatus("ID copied: "..LP.UserId, C.GREEN)
		task.delay(2, function() setStatus("Idle", C.DIM) end)
	end)
end)

-- Click TP
do
	local row = Instance.new("Frame", miscPage)
	row.Size = UDim2.new(1,-12,0,32)
	row.BackgroundColor3 = C.ROW; row.BorderSizePixel = 0; corner(row, 8)
	local pad = Instance.new("UIPadding", row)
	pad.PaddingLeft = UDim.new(0,10); pad.PaddingRight = UDim.new(0,10)
	label(row, "Click TP", UDim2.new(1,-46,1,0), C.WHITE, Enum.Font.GothamMedium).TextSize = 12
	local track, btn, setSwitch = makeSwitch(row, St.clickTp)
	track.Position = UDim2.new(1,-38,0.5,-10)
	local function refresh() setSwitch(St.clickTp) end

	local _clickTpConn = nil
	local function stopClickTp() if _clickTpConn then _clickTpConn:Disconnect(); _clickTpConn = nil end end
	local function startClickTp()
		stopClickTp()
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
			setStatus("Click TP -> teleported", C.GREEN)
		end)
	end
	_toggleRegistry["clickTp"] = function(on) if on then startClickTp() else stopClickTp() end end

	btn.MouseButton1Click:Connect(function()
		St.clickTp = not St.clickTp
		refresh()
		if St.clickTp then startClickTp() else stopClickTp(); setStatus("Click TP OFF", C.DIM) end
		saveConfig()
	end)
end

-- Auto Hit Nearest
local _hitNearestConn = nil
local function stopHitNearest() if _hitNearestConn then _hitNearestConn:Disconnect(); _hitNearestConn = nil end end
local function startHitNearest()
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
makeRow(miscPage, "autoHitNearest", "Auto Hit Nearest", function(on)
	if on then startHitNearest() else stopHitNearest() end
end)

-- Auto Hit Aura
local _hitAuraConn = nil
local function stopHitAura() if _hitAuraConn then _hitAuraConn:Disconnect(); _hitAuraConn = nil end end
local function startHitAura()
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
					if h and (h.Position - hrp.Position).Magnitude <= 20 then
						_fireRE("RE/BatSwing/Trigger", {serverTime = workspace:GetServerTimeNow(), targetCFrame = h.CFrame})
					end
				end
			end
		end)
	end)
end
makeRow(miscPage, "autoHitAura", "Auto Hit Aura", function(on)
	if on then startHitAura() else stopHitAura() end
end)

-- ============================================================
-- FLING — proximity neutralisation of NPCs / guards
-- ============================================================
-- _flingRunning is at root scope so the float-dock button handler
-- (outside the do block) can read it. All other locals stay inside
-- the do block to stay within the 200-local root-chunk limit.
local _flingRunning = false
local startFling, stopFling
do
	local FLING_RADIUS = 25   -- stud radius to trigger on a model
	local FLING_FORCE  = 220  -- outward launch speed (studs/s)
	local _flingConn   = nil
	local _flingHB     = 0
	local _flingScanT  = 0
	-- Each entry: {hrp, hum, model, savedWS, savedJP}
	local _flingNpcs   = {}
	-- LP-bump restore sentinel (prevents overlapping restores)
	local _lpBumping   = false

	local function _isPlayerChar(model)
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.Character == model then return true end
		end
		return false
	end

	-- Scan workspace for any NPC-like model:
	-- primary = Humanoid inside direct child of workspace
	-- fallback = Humanoid anywhere, parent must not be a player char
	local function _scanNpcs()
		local found = {}
		local seen  = {}
		-- Pass 1 — direct children of workspace (fastest, most common)
		for _, child in ipairs(workspace:GetChildren()) do
			local hum = child:FindFirstChildOfClass("Humanoid")
			local hrp = child:FindFirstChild("HumanoidRootPart")
			if hum and hrp and not _isPlayerChar(child) then
				seen[child] = true
				found[#found+1] = {hrp=hrp, hum=hum, model=child}
			end
		end
		-- Pass 2 — deeper descendants (NPCs parented to sub-folders)
		for _, desc in ipairs(workspace:GetDescendants()) do
			if desc:IsA("Humanoid") then
				local mdl = desc.Parent
				if mdl and not seen[mdl] and not _isPlayerChar(mdl) then
					local h = mdl:FindFirstChild("HumanoidRootPart")
					if h then
						seen[mdl] = true
						found[#found+1] = {hrp=h, hum=desc, model=mdl}
					end
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

		local dir = mag > 0.1
			and diff.Unit
			or Vector3.new(math.random()-0.5, 0.5, math.random()-0.5).Unit
		local outVel = dir * FLING_FORCE + Vector3.new(0, 50, 0)

		-- A: setnworkowner (exploit func) + AssemblyLinearVelocity.
		-- Grants full physics authority → velocity replicates to server.
		pcall(function()
			if setnworkowner then
				for _, p in ipairs(model:GetDescendants()) do
					if p:IsA("BasePart") then pcall(setnworkowner, p, LP) end
				end
				setnworkowner(hrp, LP)
			end
			hrp.AssemblyLinearVelocity = outVel
		end)

		-- B: BodyVelocity (legacy mover) — replace any existing one,
		-- persists 0.3 s; replicates on some games via mixed ownership.
		pcall(function()
			local old = hrp:FindFirstChildOfClass("BodyVelocity")
			if old then old:Destroy() end
			local bv = Instance.new("BodyVelocity")
			bv.Velocity = outVel
			bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
			bv.P        = 1e6
			bv.Parent   = hrp
			task.delay(0.3, function() pcall(function() bv:Destroy() end) end)
		end)

		-- C: Humanoid state — freeze + ragdoll.  Server-side scripts will
		-- override quickly but each 0.05 s tick re-applies it, creating a
		-- persistent interrupt to the NPC's pathfinding / chase logic.
		pcall(function()
			if not hum or not hum.Parent then return end
			if not entry.savedWS then
				entry.savedWS = hum.WalkSpeed
				entry.savedJP = hum.JumpPower
			end
			hum.WalkSpeed     = 0
			hum.JumpPower     = 0
			hum.PlatformStand = true
			hum:ChangeState(Enum.HumanoidStateType.FallingDown)
		end)

		-- D: Kill — if the server doesn't protect NPC health this removes
		-- the threat instantly without any physics requirement.
		pcall(function()
			if hum and hum.Parent and hum.Health > 0 then
				hum.Health = 0
			end
		end)

		-- E: Direct CFrame push — works on executors / games that don't
		-- enforce server authority on NPC CFrame writes.
		pcall(function()
			hrp.CFrame = hrp.CFrame + dir * 25
		end)

		-- F: LP-character bump — LP ALWAYS owns their own character, so
		-- giving LP a brief velocity toward the NPC causes a real server-
		-- side physics collision that pushes the NPC outward.
		-- Rate-limited to one active bump at a time; LP position restored
		-- after one frame so the teleport is imperceptible.
		if myHRP and not _lpBumping then
			_lpBumping = true
			pcall(function()
				local savedCF = myHRP.CFrame
				-- Nudge LP toward the NPC so physics engine registers impact.
				myHRP.AssemblyLinearVelocity = dir * (FLING_FORCE * 1.5)
					+ Vector3.new(0, 25, 0)
				task.delay(0.06, function()
					pcall(function()
						myHRP.CFrame = savedCF
						myHRP.AssemblyLinearVelocity = Vector3.zero
					end)
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

	startFling = function()
		if _flingConn then _flingConn:Disconnect(); _flingConn = nil end
		_flingRunning = true; _flingHB = 0; _flingScanT = 0
		_flingNpcs = {}; _lpBumping = false
		_flingConn = RunService.Heartbeat:Connect(function(dt)
			if not _flingRunning then return end

			-- Rebuild NPC list every 0.5 s.
			_flingScanT = _flingScanT + dt
			if _flingScanT >= 0.5 then
				_flingScanT = 0
				for _, e in ipairs(_flingNpcs) do
					if not (e.hrp and e.hrp.Parent) then _restoreNpc(e) end
				end
				_flingNpcs = _scanNpcs()
			end

			-- Fling pass every 0.05 s.
			_flingHB = _flingHB + dt
			if _flingHB < 0.05 then return end
			_flingHB = 0
			local myChar = LP.Character
			local myHRP  = myChar and myChar:FindFirstChild("HumanoidRootPart")
			if not myHRP then return end
			local myPos  = myHRP.Position
			for _, e in ipairs(_flingNpcs) do _applyNpc(e, myPos, myHRP) end
		end)
	end

	stopFling = function()
		_flingRunning = false
		if _flingConn then _flingConn:Disconnect(); _flingConn = nil end
		for _, e in ipairs(_flingNpcs) do _restoreNpc(e) end
		_flingNpcs = {}; _lpBumping = false
	end
end

-- ============================================================
-- ANTI-DETECT — Full Moon Hub port
-- • Anti-Kick         : swallows :Kick() on LP
-- • Anti-Shutdown     : swallows game:Shutdown()
-- • Telemetry spoof   : replaces FPS<30 values on keyword-matching remotes
-- • OnClientInvoke    : returns a spoofed FPS if the server asks
-- • Anti-Teleport     : logs unrequested teleports (non-blocking, for
--                       diagnosing zone ejections)
-- Everything is passive — installs on load, no toggle, no button.
-- ============================================================
do
local _adSupported = (type(getrawmetatable) == "function")
	and (type(setreadonly) == "function")
	and (type(getnamecallmethod) == "function")

local _adActive     = false
local _adOrigNC     = nil
local _adIntercepts = 0
local _AD_KW = {"fps","perf","stat","telemetry","framerate","clientinfo",
                "diagnostic","speed","velocity","ping","report","metric"}

local function _adSpoofArgs(args)
	for i, v in ipairs(args) do
		if type(v) == "number" and v < 30 then
			args[i] = 55 + math.random()*6
		elseif type(v) == "table" then
			for k2, v2 in pairs(v) do
				if type(k2) == "string" then
					local kl = k2:lower()
					local kwMatch = false
					for _, kw in ipairs(_AD_KW) do if kl:find(kw,1,true) then kwMatch=true;break end end
					if kwMatch and type(v2)=="number" and v2<30 then v[k2]=55+math.random()*6 end
				end
				if type(v2)=="number" and v2<30 then v[k2]=55+math.random()*6 end
			end
		end
	end
	return args
end

local function _adHookOnClientInvokes()
	-- Hooks OnClientInvoke on every known telemetry RF (the server asks
	-- the client → we return a spoofed FPS)
	local sources = {_NetworkingFolder, ReplicatedStorage}
	for _, src in ipairs(sources) do
		if src then
			pcall(function()
				for _, rf in ipairs(src:GetDescendants()) do
					if rf:IsA("RemoteFunction") then
						local rname = rf.Name:lower()
						for _, k in ipairs(_AD_KW) do
							if rname:find(k, 1, true) then
								pcall(function()
									rf.OnClientInvoke = function(...)
										_adIntercepts = _adIntercepts + 1
										return 60 + math.random()*5, "normal", true
									end
								end)
								break
							end
						end
					end
				end
			end)
		end
	end
end

local function _adStart()
	if _adActive or not _adSupported then return end
	local ok, mt = pcall(getrawmetatable, game)
	if not ok then return end
	pcall(setreadonly, mt, false)
	local _origNC = mt.__namecall
	_adOrigNC = _origNC

	local _hook = function(self, ...)
		local method = getnamecallmethod()

		-- Anti-Kick: swallows :Kick() aimed at the LocalPlayer
		if method == "Kick" and typeof(self)=="Instance" and self:IsA("Player") and self==LP then
			_adIntercepts = _adIntercepts + 1
			setStatus("Anti-Kick x".._adIntercepts, C.GREEN)
			return
		end

		-- Anti-Shutdown: swallows game:Shutdown() (anti-cheat that kills the game)
		if method == "Shutdown" and typeof(self)=="Instance"
			and (self==game or (pcall(function() return self:IsA("DataModel") end) and true)) then
			_adIntercepts = _adIntercepts + 1
			setStatus("Anti-Shutdown x".._adIntercepts, C.GREEN)
			return
		end

		-- Telemetry spoof: replaces FPS<30 on sensitive remotes
		if (method=="FireServer" or method=="InvokeServer") and typeof(self)=="Instance" then
			local rname = (self.Name or ""):lower()
			for _, k in ipairs(_AD_KW) do
				if rname:find(k, 1, true) then
					_adIntercepts = _adIntercepts + 1
					local args = _adSpoofArgs({...})
					return _origNC(self, table.unpack(args))
				end
			end
		end

		-- Unexpected teleport (log only — doesn't block legitimate teleports)
		if (method=="Teleport" or method=="TeleportToPlaceInstance") and typeof(self)=="Instance" then
			local sclass = ""
			pcall(function() sclass = self.ClassName end)
			if sclass == "TeleportService" then
				-- Let it through: our own hopServer() uses this same path
				-- setStatus("Teleport detected ("..method..")", C.YELLOW)
			end
		end

		return _origNC(self, ...)
	end

	local wrapped = type(newcclosure)=="function" and newcclosure(_hook) or _hook
	mt.__namecall = wrapped
	pcall(setreadonly, mt, true)
	_adActive = true

	-- Hook OnClientInvoke after installing __namecall
	task.delay(1, _adHookOnClientInvokes)
	-- Periodic re-hook (the game may recreate RFs dynamically)
	task.spawn(function()
		while _adActive do task.wait(30); pcall(_adHookOnClientInvokes) end
	end)

	setStatus("Anti-Detect active", C.GREEN)
end

local function _adStop()
	if not _adActive or not _adOrigNC then return end
	local ok2, mt2 = pcall(getrawmetatable, game)
	if ok2 then
		pcall(setreadonly, mt2, false)
		mt2.__namecall = _adOrigNC
		pcall(setreadonly, mt2, true)
	end
	_adActive = false; _adOrigNC = nil
	setStatus("Anti-Detect OFF", C.DIM)
end

-- Passive — no button, no toggle. Immediate protection on load.
_adStart()
end

-- ============================================================
-- AIM BAT — Moon Hub port (AB / Bat Aimbot V1), speed tied to St.speed
-- ============================================================
local startAimBat, stopAimBat
do
local AB_HEIGHT, AB_HIT_DIST, AB_HIT_CD = 3.7, 5, false
local BAT_NAMES = {
	"Bat","Slap","Iron Slap","Gold Slap","Diamond Slap","Emerald Slap",
	"Ruby Slap","Dark Matter Slap","Flame Slap","Nuclear Slap",
	"Galaxy Slap","Glitched Slap","FieldBat","Field Bat",
}
local function _abIsBatName(name)
	if not name then return false end
	for _, n in ipairs(BAT_NAMES) do if name == n then return true end end
	local lower = name:lower()
	return lower:find("bat", 1, true) ~= nil or lower:find("slap", 1, true) ~= nil
end
local function _abGetBat()
	local char = LP.Character; if not char then return nil end
	for _, name in ipairs(BAT_NAMES) do
		local t = char:FindFirstChild(name); if t and t:IsA("Tool") then return t end
	end
	local bp = LP:FindFirstChildOfClass("Backpack")
	if bp then
		for _, name in ipairs(BAT_NAMES) do
			local t = bp:FindFirstChild(name); if t and t:IsA("Tool") then return t end
		end
	end
	for _, t in ipairs(char:GetChildren()) do
		if t:IsA("Tool") and _abIsBatName(t.Name) then return t end
	end
	if bp then
		for _, t in ipairs(bp:GetChildren()) do
			if t:IsA("Tool") and _abIsBatName(t.Name) then return t end
		end
	end
	return nil
end
local function _abTryHit()
	if AB_HIT_CD then return end
	AB_HIT_CD = true
	pcall(function()
		local bat = _abGetBat(); if not bat then return end
		local char = LP.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if bat.Parent ~= char and hum then pcall(function() hum:EquipTool(bat) end) end
		pcall(function() bat:Activate() end)
	end)
	task.delay(0.2, function() AB_HIT_CD = false end)
end
local function _abGetClosest()
	local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
	if not root then return nil, math.huge end
	local closest, minDist = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP and plr.Character then
			local tr = plr.Character:FindFirstChild("HumanoidRootPart")
			local hum = plr.Character:FindFirstChildOfClass("Humanoid")
			if tr and hum and hum.Health > 0 then
				local d = (tr.Position - root.Position).Magnitude
				if d < minDist then minDist = d; closest = plr end
			end
		end
	end
	return closest, minDist
end
local _aimBatConn = nil
startAimBat = function()
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
		if not (equipped and _abIsBatName(equipped.Name)) then
			local bat = _abGetBat(); if bat then pcall(function() hum:EquipTool(bat) end) end
		end
		local target, dist = _abGetClosest()
		if not target or not target.Character then return end
		local tr = target.Character:FindFirstChild("HumanoidRootPart"); if not tr then return end

		local targetVel = tr.AssemblyLinearVelocity
		local myPos, targetPos = root.Position, tr.Position
		local predictPos = targetPos + targetVel*0.14 + tr.CFrame.LookVector*0.3
		local direction = predictPos - myPos
		local flatDir = Vector3.new(direction.X, 0, direction.Z).Unit
		local desiredHeight = targetPos.Y + AB_HEIGHT
		local yVel = (desiredHeight - myPos.Y)*19.5 + targetVel.Y*0.8
		if hum.FloorMaterial ~= Enum.Material.Air then yVel = math.max(yVel, 13) end
		yVel = math.clamp(yVel, -70, 110)
		local pursuitSpeed = St.speed
		local desiredVel = Vector3.new(flatDir.X*pursuitSpeed, yVel, flatDir.Z*pursuitSpeed)
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
			root.AssemblyAngularVelocity = root.CFrame:VectorToWorldSpace(Vector3.new(rx*42, ry*42, rz*42))
		end
		if dist <= AB_HIT_DIST then _abTryHit() end
	end)
end
stopAimBat = function()
	_aimBatActive = false
	if _aimBatConn then _aimBatConn:Disconnect(); _aimBatConn = nil end
	AB_HIT_CD = false
	local char = LP.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if root then root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero end
	if hum then hum.AutoRotate = true end
end
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
local function hopServer()
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
						table.insert(candidates, srv.id)
					end
				end
			end
		end)
		if #candidates > 0 then
			local pick = candidates[math.random(1, #candidates)]
			setStatus("Hopper -> new server", C.GREEN)
			pcall(function() game:GetService("TeleportService"):TeleportToPlaceInstance(placeId, pick, LP) end)
		else
			setStatus("Hopper: no free server, rejoining", C.YELLOW)
			pcall(function() game:GetService("TeleportService"):Teleport(placeId, LP) end)
		end
	end)
end

-- ============================================================
-- FLOATING DOCK — Speed / AimBat / Bypass / Fling / Hopper / Lock
-- ============================================================
do
local FLOAT_SZ, FLOAT_GAP, FLOAT_TOP, FLOAT_RIGHT_OFF = 38, 6, 66, 10
local _floatDefs = {
	{ id="speed",  label="Speed" }, { id="aimbat", label="Aim\nBat" },
	{ id="bypass", label="Bypass" }, { id="fling",  label="Fling" },
	{ id="hopper", label="Hop" },    { id="lock",   label="Lock" },
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

	local _active = false
	local function setActive(on)
		_active = on
		TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = on and Color3.fromRGB(18,30,50) or C.ROW}):Play()
		dot.Visible = on
	end

	local drag2, dStart, dPos2 = false, nil, nil
	btn.InputBegan:Connect(function(inp)
		if St.floatLocked then return end
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			drag2 = true; dStart = inp.Position; dPos2 = btn.Position
		end
	end)
	UIS.InputChanged:Connect(function(inp)
		if not drag2 then return end
		if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
			local delta = inp.Position - dStart
			btn.Position = UDim2.new(dPos2.X.Scale, dPos2.X.Offset+delta.X, dPos2.Y.Scale, dPos2.Y.Offset+delta.Y)
		end
	end)
	UIS.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			drag2 = false
		end
	end)

	_floatBtns[def.id] = { btn = btn, setActive = setActive }
	return btn, setActive
end

for i, def in ipairs(_floatDefs) do
	local _, setAct = makeFloatBtn(i, def)
	if def.id == "speed" then
		setAct(St.speedOn)
		_floatBtns["speed"].btn.MouseButton1Click:Connect(function()
			St.speedOn = not St.speedOn
			if St.speedOn then startSpeed() else stopSpeed() end
			setAct(St.speedOn)
			speedRefresh()
			saveConfig()
		end)
	elseif def.id == "aimbat" then
		_floatBtns["aimbat"].btn.MouseButton1Click:Connect(function()
			_aimBatActive = not _aimBatActive
			setAct(_aimBatActive)
			if _aimBatActive then startAimBat() else stopAimBat() end
		end)
	elseif def.id == "bypass" then
		_bypassFloatRefresh = setAct
		_floatBtns["bypass"].btn.MouseButton1Click:Connect(function()
			if not _bypassOn then
				if applyBypass() then _bypassOn = true; if _bypassPillRefresh then _bypassPillRefresh() end end
			else
				if removeBypass() then _bypassOn = false; if _bypassPillRefresh then _bypassPillRefresh() end end
			end
			setAct(_bypassOn)
		end)
	elseif def.id == "fling" then
		-- Persistent toggle: green dot = actively held in the air.
		-- Click once → launch + hold aloft. Click again → release, fall normally.
		_floatBtns["fling"].btn.MouseButton1Click:Connect(function()
			if _flingRunning then
				stopFling(); setAct(false)
			else
				startFling(); setAct(true)
			end
		end)
	elseif def.id == "hopper" then
		-- One-off action (not a persistent on/off): flash the green dot
		-- for the duration of the search/teleport.
		_floatBtns["hopper"].btn.MouseButton1Click:Connect(function()
			setAct(true)
			hopServer()
			task.delay(1.2, function() setAct(false) end)
		end)
	elseif def.id == "lock" then
		setAct(St.floatLocked)
		_floatBtns["lock"].btn.MouseButton1Click:Connect(function()
			St.floatLocked = not St.floatLocked
			setAct(St.floatLocked)
			setStatus(St.floatLocked and "Buttons locked" or "Buttons unlocked", C.ACCENT2)
			saveConfig()
		end)
	end
end
end

-- ============================================================
-- DRAG / MINIMIZE / CLOSE / KEYBIND
-- ============================================================
do
	local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
	header.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			dragging = true; dragStart = inp.Position; startPos = main.Position
			inp.Changed:Connect(function() if inp.UserInputState == Enum.UserInputState.End then dragging = false end end)
		end
	end)
	header.InputChanged:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
			dragInput = inp
		end
	end)
	UIS.InputChanged:Connect(function(inp)
		if inp == dragInput and dragging then
			local delta = inp.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+delta.X, startPos.Y.Scale, startPos.Y.Offset+delta.Y)
		end
	end)
end

local minimized, fullHeight = false, 268
minBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	if minimized then
		TweenService:Create(main, TweenInfo.new(0.2), {Size=UDim2.new(0,248,0,42)}):Play()
		contentArea.Visible = false; sep.Visible = false; tabBar.Visible = false
		minBtn.Text = "+"
	else
		TweenService:Create(main, TweenInfo.new(0.2), {Size=UDim2.new(0,248,0,fullHeight)}):Play()
		contentArea.Visible = true; sep.Visible = true; tabBar.Visible = true
		minBtn.Text = "–"
	end
end)
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

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
-- Deliberately excluded: Bypass Anti-Cheat and AimBat (never
-- re-applied alone on load).
if _savedConfig then
	for key, onToggle in pairs(_toggleRegistry) do
		if St[key] == true and onToggle then pcall(onToggle, true) end
	end
	if St.speedOn then startSpeed(); if speedRefresh then speedRefresh() end end
end

print("[yslemEgg] Loaded — full rebuild — RightShift hide/show | Dock: Speed, AimBat, Bypass, Lock")
