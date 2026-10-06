local M = dofile("/tmp/mock/env.lua")
local newInst = M.newInst
local ws = M.workspace
local V3, CFn = Vector3, CFrame

local carrying = false
-- the mock's Parent setter only works once per object: detach by hand
local function detach(o)
	local par = rawget(o, "Parent")
	if par then for i, c in ipairs(par.Children) do if c == o then table.remove(par.Children, i) break end end end
	rawset(o, "Parent", nil)
end
setclipboard = function() end
gethui = nil
local statuses = {}
local rs = M.getService(nil, "ReplicatedStorage")
local remotes = newInst("Folder", rs); remotes.Name = "Remotes"
local rg = newInst("Folder", remotes); rg.Name = "Game"
local bd = newInst("RemoteEvent", rg); bd.Name = "BasketDrop"
local ep = newInst("RemoteEvent", rg); ep.Name = "EggPickup"

local rendered = newInst("Folder", ws); rendered.Name = "RenderedEggs"
local function makeEgg(name, pos, dropped)
	local egg = newInst("Model", rendered); egg.Name = name
	egg.CFrame = CFrame.new(pos)
	local h = newInst("Part", egg); h.Name = "Handle"; h.CFrame = CFrame.new(pos)
	local pr = newInst("ProximityPrompt", h); pr.ActionText = "Pick Up"; pr.ObjectText = name
	if dropped then egg:SetAttribute("OriginPosition", pos); egg:SetAttribute("Position", pos) end
	return egg
end
local mapEgg = makeEgg("Blackhole Egg", Vector3.new(3500, 100, 900), false)

local plots = newInst("Folder", ws); plots.Name = "Plots"
local plot = newInst("Model", plots); plot.Name = "7"
local data = newInst("Folder", plot); data.Name = "Data"
local owner = newInst("ObjectValue", data); owner.Name = "Owner"
local base = newInst("Part", plot); base.Name = "Baseplate"; base.CFrame = CFrame.new(Vector3.new(-200, 40, 300)); base.Size = Vector3.new(100, 2, 100)

local lp = newInst("Folder"); lp.Name = "friend"; lp.UserId = 1; lp.DisplayName = "friend"; lp.ClassName = "Player"
owner.Value = lp
local ch = newInst("Model", ws); ch.Name = "friend"
local hrp = newInst("Part", ch); hrp.Name = "HumanoidRootPart"; hrp.CFrame = CFrame.new(Vector3.new(-100, 40, 500))
local hum = newInst("Humanoid", ch)
lp.Character = ch; M.hrp = hrp; M.hum = hum
lp.CharacterAdded = M.signal()
local basket = newInst("Folder", lp); basket.Name = "Basket"
local pg = newInst("Folder", lp); pg.Name = "PlayerGui"
local main = newInst("Folder", pg); main.Name = "Main"
local bt = newInst("Folder", main); bt.Name = "BasketTracker"
local h = newInst("Folder", bt); h.Name = "Handler"
local ef = newInst("Frame", h); ef.Name = "EggFrame"
local drop = newInst("ImageButton", ef); drop.Name = "Drop"
drop.AbsoluteSize = {X = 100, Y = 40}
local label = newInst("TextLabel", bt); label.Text = "Egg Will Break"; label.Visible = false
M.players = {lp}; M.Players.LocalPlayer = lp

local function takeIntoBasket(name)
	carrying = true; M.picked = (M.picked or 0) + 1
	label.Visible = true
	local item = newInst("Folder", basket); item.Name = "Item"; item:SetAttribute("Egg", name)
end
local function dropNow()
	if not carrying then return end
	carrying = false; M.dropped = (M.dropped or 0) + 1
	label.Visible = false
	for _, c in ipairs(basket:GetChildren()) do detach(c) end
	makeEgg("Blackhole Egg", hrp.CFrame.Position + Vector3.new(3, 0, 2), true)
end
fireproximityprompt = function(prompt)
	if prompt.ActionText == "Pick Up" and prompt.Parent and not carrying then
		local egg = prompt.Parent.Parent
		local pos = prompt.Parent.CFrame.Position
		if (pos - hrp.CFrame.Position).Magnitude <= 15 then
			takeIntoBasket(egg.Name)
			detach(egg)
		end
	end
end
firesignal = function(sig)
	if SCENARIO == "remote" then return end
	if carrying and (sig == drop.MouseButton1Click or sig == drop.Activated) then dropNow() end
end
if SCENARIO == "remote" then firesignal = nil end
if SCENARIO == "nodrop" then firesignal = nil end
M.onFire = function(o, nm)
	if o == bd then
		M.remoteDrop = (M.remoteDrop or 0) + 1
		if SCENARIO ~= "nodrop" then dropNow() end
	elseif o == ep then
		for _, e in ipairs(rendered:GetChildren()) do
			if e.Name == nm and e:GetAttribute("OriginPosition") ~= nil and not carrying then
				if (e:GetAttribute("Position") - hrp.CFrame.Position).Magnitude <= 20 then
					takeIntoBasket(e.Name); detach(e); break
				end
			end
		end
	end
end

local code = projectFn
local co = coroutine.create(code)
local ok, api = coroutine.resume(co)
if not ok then print("LOAD ERROR", api, debug.traceback(co)) os.exit(1) end
local logic = api
logic.setStatus(function(t) statuses[#statuses + 1] = t end)
for _, w in ipairs(M.warnings) do print("[load warn]", w) end
M.warnings = {}

for i = 1, 30 do M.step(1/30) end
print("scenario:", SCENARIO)
local runco = task.spawn(logic.run, mapEgg)
local t = 0
if SCENARIO == "stop" then
	for i = 1, tonumber(STOP_AT) * 30 do M.step(1/30) end
	logic.stop()
	for i = 1, 30 * 10 do M.step(1/30) end
	print("after stop: running", logic.isRunning(), "PlatformStand", hum.PlatformStand, "vel", hrp.AssemblyLinearVelocity.X, hrp.AssemblyLinearVelocity.Y, hrp.AssemblyLinearVelocity.Z)
elseif SCENARIO == "lose" then
	local lost = false
	while t < 120 do
		M.step(1/30); t = t + 1/30
		if not lost and carrying and (M.picked or 0) >= 2 and hrp.CFrame.Position.Y > 70 then
			lost = true
			print("egg lost mid-flight at", hrp.CFrame.Position.X, hrp.CFrame.Position.Y, hrp.CFrame.Position.Z)
			dropNow()
		end
	end
else
	while t < 90 and (logic.isRunning() or t < 2) do M.step(1/30); t = t + 1/30 end
end
print("picked", M.picked, "dropped", M.dropped, "remoteDrop", M.remoteDrop, "mouse", M.mouseClicks, "keys", M.keys)
print("carrying at end", carrying, "label", label.Visible, "basket", #basket:GetChildren())
local p = hrp.CFrame.Position
print("player at", p.X, p.Y, p.Z, "(plot x -250..-150, z 250..350)")
print("statuses:", table.concat(statuses, " > "))
for _, w in ipairs(M.warnings) do print("[warn]", w) end
