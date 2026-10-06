local M = dofile("/tmp/mock/env.lua")
local newInst = M.newInst
local ws = M.workspace

local carrying = false
setclipboard = function() end
gethui = nil
setfpscap = function() end
isfile = function() return false end
writefile = function() end
readfile = function() return "{}" end
fireproximityprompt = function(prompt)
	if prompt.ActionText == "Pick Up" and prompt.Parent and not carrying then
		carrying = true
		M.picked = (M.picked or 0) + 1
		M.label.Visible = true
		prompt.Parent.Parent = nil
	end
end
local function dropNow()
	carrying = false
	M.dropped = (M.dropped or 0) + 1
	M.label.Visible = false
	local hrp = M.hrp
	local part = newInst("Part", ws); part.Name = "DroppedEgg"
	part.CFrame = CFrame.new(hrp.CFrame.Position + Vector3.new(3, 0, 2))
	local pr = newInst("ProximityPrompt", part); pr.ActionText = "Pick Up"
end
firesignal = function(sig)
	if SCENARIO == "remote" then return end
	if carrying and M.dropButtonSignals[sig] then dropNow() end
end
if SCENARIO == "remote" or SCENARIO == "click" then firesignal = nil end

local rs = M.getService(nil, "ReplicatedStorage")
local remotes = newInst("Folder", rs); remotes.Name = "Remotes"
local rg = newInst("Folder", remotes); rg.Name = "Game"
local bd = newInst("RemoteEvent", rg); bd.Name = "BasketDrop"
M.onFire = function(o) if o == bd then M.remoteDrop = (M.remoteDrop or 0) + 1; if SCENARIO == "remote" and carrying then dropNow() end end end

local rendered = newInst("Folder", ws); rendered.Name = "RenderedEggs"
local egg = newInst("Model", rendered); egg.Name = "Blackhole Egg"
local ep = newInst("Part", egg); ep.Name = "Handle"; ep.CFrame = CFrame.new(Vector3.new(3500, 100, 900))
local epr = newInst("ProximityPrompt", ep); epr.ActionText = "Pick Up"; epr.ObjectText = "Blackhole Egg"

local plots = newInst("Folder", ws); plots.Name = "Plots"
local plot = newInst("Model", plots); plot.Name = "1200_unknown"
for i, off in ipairs({{0,0},{60,0},{0,60},{60,60}}) do
	local pp = newInst("Part", plot); pp.Name = "Floor" .. i
	pp.CFrame = CFrame.new(Vector3.new(-200 + off[1], 40, 300 + off[2])); pp.Size = Vector3.new(50, 2, 50)
end

local lp = newInst("Folder"); lp.Name = "1200_unknown"; lp.UserId = 5575410002; lp.DisplayName = "1200_unknown"; lp.AccountAge = 900
lp.ClassName = "Player"
local ch = newInst("Model", ws); ch.Name = "1200_unknown"
local hrp = newInst("Part", ch); hrp.Name = "HumanoidRootPart"; hrp.CFrame = CFrame.new(Vector3.new(-100, 40, 500))
local hum = newInst("Humanoid", ch)
lp.Character = ch; M.hrp = hrp; M.hum = hum
lp.CharacterAdded = M.signal()
local pg = newInst("Folder", lp); pg.Name = "PlayerGui"
local main = newInst("Folder", pg); main.Name = "Main"
local bt = newInst("Folder", main); bt.Name = "BasketTracker"
local h = newInst("Folder", bt); h.Name = "Handler"
local ef = newInst("Frame", h); ef.Name = "EggFrame"
local drop = newInst("ImageButton", ef); drop.Name = "Drop"
M.dropButtonSignals = {[drop.MouseButton1Click] = true, [drop.Activated] = true}
local label = newInst("TextLabel", bt); label.Text = "Egg Will Break"; label.Visible = false
M.label = label
M.players = {lp}
M.Players.LocalPlayer = lp

local code = io.open("/home/user/wwe/yslempet_EggTP.lua"):read("*a")
local fn, err = load(code, "yslempet")
assert(fn, err)
local co = coroutine.create(fn)
local ok, e = coroutine.resume(co)
if not ok then print("LOAD ERROR", e, debug.traceback(co)) os.exit(1) end

for _, w in ipairs(M.warnings) do print("[load warn]", w) end
M.warnings = {}

local grab
for _, o in ipairs(M.all) do if o.ClassName == "TextButton" and o.Text == "RAMASSER" then grab = o end end
assert(grab, "no RAMASSER button")

for i = 1, 60 do M.step(1/30) end
print("scenario:", SCENARIO)
if SCENARIO == "vol" then
	for _, o in ipairs(M.all) do if o.ClassName == "TextButton" and o.Text == "TP" then o.MouseButton1Click:Fire() end end
end
grab.MouseButton1Click:Fire()
local t = 0
if SCENARIO == "stop" then
	for i = 1, tonumber(STOP_AT) * 30 do M.step(1/30) end
	print("pressing STOP, button text:", grab.Text)
	grab.MouseButton1Click:Fire()
	for i = 1, 30 * 10 do M.step(1/30) end
	print("after stop: button", grab.Text, "PlatformStand", M.hum.PlatformStand, "vel", M.hrp.AssemblyLinearVelocity.X, M.hrp.AssemblyLinearVelocity.Y, M.hrp.AssemblyLinearVelocity.Z, "HRP.CanCollide", M.hrp.CanCollide)
elseif SCENARIO == "lose" then
	local lost = false
	while t < 120 do
		M.step(1/30); t = t + 1/30
		if not lost and carrying and (M.picked or 0) >= 2 and M.hrp.CFrame.Position.Y > 70 then
			lost = true
			print("egg lost mid-flight at", M.hrp.CFrame.Position.X, M.hrp.CFrame.Position.Y, M.hrp.CFrame.Position.Z)
			dropNow()
		end
	end
else
	while t < 90 do M.step(1/30); t = t + 1/30 end
end
if SCENARIO == "click" then print("mouse clicks used as last resort:", M.mouseClicks) end

print("picked", M.picked, "dropped", M.dropped, "remoteDrop", M.remoteDrop, "mouseClicks", M.mouseClicks, "keys", M.keys)
print("carrying at end", carrying, "label visible", M.label.Visible)
print("player at", hrp.CFrame.Position.X, hrp.CFrame.Position.Y, hrp.CFrame.Position.Z)
for _, w in ipairs(M.warnings) do print("[warn]", w) end
