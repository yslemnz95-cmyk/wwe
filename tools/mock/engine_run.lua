-- Monde simule : oeuf porte, ligne de separation, base ; le serveur valide la livraison a l'arrivee
local passes, failures = 0, 0
local function check(name, cond)
	if cond then passes += 1 else failures += 1; print("FAIL: " .. name) end
end
tick = tick or os.clock
task.delay = function(t, fn, ...) local a = {...}; task.spawn(function() task.wait(t); fn(table.unpack(a)) end) end
game.IsLoaded = function() return true end

local RunService = M.getService(nil, "RunService")
local workspace_ = workspace

local remotesRef = {}
local function newWorld(opts)
	-- character
	local char = M.newInst("Model"); char.Name = "Character"
	local hrp = M.newInst("Part"); hrp.Name = "HumanoidRootPart"; hrp.Parent = char
	hrp.CFrame = CFrame.new(Vector3.new(opts.startX or 900, 70, -350))
	local hum = M.newInst("Humanoid"); hum.Parent = char
	local localPlayer = M.newInst("Player"); localPlayer.Character = char
	-- the carried egg, welded to the character
	local egg = M.newInst("Model"); egg.Name = "EGG1"; egg.Parent = workspace_
	local weld = M.newInst("WeldConstraint"); weld.Parent = egg
	weld.Part0 = hrp
	local eggAt = nil
	egg.GetPivot = function() return eggAt and CFrame.new(eggAt) or hrp.CFrame end

	local carry = M.signal()
	local state = {carrying = true, verdicts = 0, drops = 0, grabs = 0}
	local EggState = {
		CarryChanged = carry,
		CarryFieldEgg = function(uid) state.grabs += 1; state.carrying = true; weld.Part0 = hrp; eggAt = nil; carry:Fire({IsCarrying = true, Uid = uid, SpeedMultiplier = 1}) end,
		DropFieldEgg = function()
			state.drops += 1
			local wasCarrying = state.carrying
			state.carrying = false; weld.Part0 = nil; eggAt = hrp.Position
			carry:Fire({IsCarrying = false})
			-- putting the egg down on the base is accepted by the server
			local p = hrp.Position
			if wasCarrying and Vector3.new(p.X - 528.7, 0, p.Z + 364.11).Magnitude < 6 then
				state.verdicts += 1
				state.verdictFired = true
				remotesRef["RE/EggWorld/FieldEggRedeemVerdict"].OnClientEvent:Fire()
			end
		end,
	}
	local remotes = {
		["RE/EggWorld/FieldEggRedeemVerdict"] = {OnClientEvent = M.signal()},
		["RE/RigSync/Refresh"] = {OnClientEvent = M.signal()},
	}
	remotesRef = remotes
	local networking = {FindFirstChild = function(_, name) return remotes[name] end}
	local tbl = {EggState = EggState}
	local tbl4 = {
		Root = function() return hrp end,
		WalkSpeed = function() return 20 end,
		SafeCarry = {TpFpsCap = true},
		Steal = {Carrying = true, CarryUid = "EGG1"},
		AntiGuard = {Enabled = false},
	}
	return {char = char, hrp = hrp, egg = egg, weld = weld, localPlayer = localPlayer, remotes = remotes, networking = networking,
		tbl = tbl, tbl4 = tbl4, state = state, EggState = EggState, carry = carry}
end

local function runScenario(name, opts)
	local W = newWorld(opts or {})
	local localPlayer, networking, tbl, tbl4 = W.localPlayer, W.networking, W.tbl, W.tbl4
	local str2 = ""
	local unload = {}
	local function slicedfn4(fn) unload[#unload + 1] = fn end
	local slicedfn13 = function() return false end
	local InstantEngine
	do
		--ENGINE--
		InstantEngine = InstantEngine
	end
	-- server: validates the delivery when we stand on the base
	local home = Vector3.new(528.7, 70.57, -364.11)
	local verdictFired = false
	task.spawn(function()
		while not verdictFired and not W.state.verdictFired do
			task.wait(1 / 60)
			local p = W.hrp.Position
			if W.state.carrying and Vector3.new(p.X - home.X, 0, p.Z - home.Z).Magnitude < 3 then
				verdictFired = true
				W.state.verdicts += 1
				W.remotes["RE/EggWorld/FieldEggRedeemVerdict"].OnClientEvent:Fire()
			end
		end
	end)
	-- optional: the server pulls us back during the third hop
	local pulled = 0
	if opts and opts.pullBack then
		task.spawn(function()
			local lastX = W.hrp.Position.X
			while not verdictFired do
				task.wait(1 / 60)
				local x = W.hrp.Position.X
				if pulled < opts.pullBack and x < 800 and x > 560 and math.abs(x - lastX) > 20 then
					pulled += 1
					W.hrp.CFrame = CFrame.new(Vector3.new(lastX + 10, W.hrp.Position.Y, W.hrp.Position.Z))
					W.remotes["RE/RigSync/Refresh"].OnClientEvent:Fire({Action = "Relocate"})
				end
				lastX = W.hrp.Position.X
			end
		end)
	end
	local result, done = nil, false
	local cancelAt = opts and opts.cancelAfter
	local cancelled = false
	task.spawn(function()
		result = InstantEngine.deliver("EGG1", function() return cancelled end)
		done = true
	end)
	if cancelAt then task.spawn(function() task.wait(cancelAt); cancelled = true end) end
	for i = 1, 60 * 60 do
		M.step(1 / 60)
		if opts and opts.trace and i % 20 == 0 then print(i, string.format("%.0f %.0f %.0f", W.hrp.Position.X, W.hrp.Position.Y, W.hrp.Position.Z), str2, W.state.carrying) end
		if done then break end
	end
	return W, result, done, pulled, str2
end

local W, ok, done, _, why = runScenario("clean")
if ok ~= true then print("clean debug:", tostring(why), W.hrp.Position.X, W.hrp.Position.Y, W.hrp.Position.Z, W.state.drops, W.state.grabs, W.state.verdicts) end
check("clean: engine finished", done)
check("clean: delivery succeeded", ok == true)
check("clean: server verdict received", W.state.verdicts == 1)
check("clean: dropped at the line then took it back", W.state.drops >= 1 and W.state.grabs >= 1)
check("clean: ends over the base", Vector3.new(W.hrp.Position.X - 528.7, 0, W.hrp.Position.Z + 364.11).Magnitude < 40)
check("clean: no stray clone left", workspace_:FindFirstChild("Clone") == nil)

local W2, ok2, done2, pulled2 = runScenario("pulled", {pullBack = 2})
check("pulled: engine finished", done2)
check("pulled: server pulled us back twice", pulled2 == 2)
check("pulled: still delivered", ok2 == true and W2.state.verdicts == 1)

local W3, ok3, done3 = runScenario("cancel", {cancelAfter = 0.3})
check("cancel: engine stops", done3)
check("cancel: reported as not delivered", ok3 == false)
check("cancel: no verdict", W3.state.verdicts == 0)

check("no runtime warnings", #M.warnings == 0)
for _, w in ipairs(M.warnings) do print(w) end
print(string.format("Engine: %d ok, %d fail", passes, failures))
if failures > 0 then error("engine tests failed") end
