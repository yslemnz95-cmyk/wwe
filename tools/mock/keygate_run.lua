-- Scenarios KeyGate : faux serveur /v1/verify + faux executeur (fichiers, presse-papiers, requetes)
local passes, failures = 0, 0
local function check(name, cond)
	if cond then passes += 1 else failures += 1; print("FAIL: " .. name) end
end

local Players = M.getService(nil, "Players")
local CoreGui = M.getService(nil, "CoreGui")
local UIS = M.getService(nil, "UserInputService")
UIS.InputChanged = M.signal(); UIS.InputEnded = M.signal()
local Http = M.getService(nil, "HttpService")
local lastBody
Http.JSONEncode = function(_, t) lastBody = t; return "ENC" end
Http.JSONDecode = function(_, s) return s end

local me = M.newInst("Player")
me.UserId = 4242; me.Name = "TestUser"
Players.LocalPlayer = me

local files, clip = {}, nil
isfile = function(p) return files[p] ~= nil end
readfile = function(p) return files[p] end
writefile = function(p, c) files[p] = c end
delfile = function(p) files[p] = nil end
setclipboard = function(s) clip = s end

local GOOD = "YSL-" .. string.rep("a", 24)
local OTHER = "YSL-" .. string.rep("b", 24)
local server

local function fakeRequest(opts)
	server.calls += 1
	server.lastBody = lastBody
	if server.mode == "down" then error("connection failed") end
	if server.mode == "429" then return {StatusCode = 429, Body = ""} end
	if server.mode == "500" then return {StatusCode = 500, Body = ""} end
	if server.mode == "garbage" then return {StatusCode = 200, Body = {status = "hacked"}} end
	if opts.Url ~= "https://REPLACE_ME/v1/verify" or opts.Method ~= "POST" then return {StatusCode = 404, Body = ""} end
	local rec = server.keys[lastBody.key]
	local st = "invalid"
	if rec and rec.uid == lastBody.robloxUserId then st = rec.status end
	return {StatusCode = 200, Body = {status = st, expiresAt = 1790000000}}
end

local function fresh(noRequest)
	files = {}; clip = nil
	server = {keys = {}, mode = "ok", calls = 0}
	request = (not noRequest) and fakeRequest or nil
	for _, c in ipairs(CoreGui:GetChildren()) do c:Destroy() end
	return loadModule()
end

local function start(KG, onInvalid)
	local r = {done = false}
	task.spawn(function()
		r.value = KG.require("test", {onInvalid = onInvalid})
		r.done = true
	end)
	return r
end

local function advance(sec) for _ = 1, math.ceil(sec / 0.05) do M.step(0.05) end end
local function find(root, pred) for _, d in ipairs(root:GetDescendants()) do if pred(d) then return d end end end
local function gate() return CoreGui:FindFirstChild("YslemKeyGate") end
local function btn(text) return find(gate(), function(d) return d.ClassName == "TextButton" and d.Text == text end) end
local function box() return find(gate(), function(d) return d.ClassName == "TextBox" end) end
local function hasText(s)
	local g = gate(); if not g then return false end
	return find(g, function(d) return d.ClassName == "TextLabel" and type(d.Text) == "string" and d.Text:find(s, 1, true) ~= nil end) ~= nil
end
local function submit(key)
	box().Text = key
	btn("Verify").MouseButton1Click:Fire()
	advance(0.3)
end

-- 1. cle sauvegardee valide : pas d'UI, une seule requete avec les 4 champs
do
	local KG = fresh()
	files["yslem_key.txt"] = GOOD
	server.keys[GOOD] = {status = "valid", uid = 4242}
	local r = start(KG)
	advance(1)
	check("saved valid: returns true", r.done and r.value == true)
	check("saved valid: no UI", gate() == nil)
	check("saved valid: one request", server.calls == 1)
	local b = server.lastBody
	check("body: only 4 fields", b.key == GOOD and b.robloxUserId == 4242 and b.script == "test" and b.v == 1)
	local n = 0; for _ in pairs(b) do n += 1 end
	check("body: exactly 4 keys", n == 4)
end

-- 2. parcours complet : guide, invitation, mauvais format, cle inconnue, cle bonne
do
	local KG = fresh()
	local r = start(KG)
	advance(0.3)
	check("gate shown", gate() ~= nil and not r.done)
	check("guide has /key pseudo:<name>", hasText("/key pseudo:TestUser"))
	btn("Copy Discord invite").MouseButton1Click:Fire()
	check("invite copied", clip == "https://discord.gg/REPLACE_ME")
	submit("")
	check("empty message", hasText("Paste your key first"))
	submit("hello")
	check("bad format message", hasText("does not look like a key"))
	check("bad format never sent", server.calls == 0)
	submit(OTHER)
	check("unknown key -> Invalid key", hasText("Invalid key"))
	check("unknown key sent once", server.calls == 1)
	check("unknown key not saved", files["yslem_key.txt"] == nil)
	server.keys[GOOD] = {status = "valid", uid = 4242}
	submit(GOOD)
	advance(1)
	check("good key returns true", r.done and r.value == true)
	check("good key saved", files["yslem_key.txt"] == GOOD)
	check("UI closed", gate() == nil)
end

-- 3. cle liee a un autre compte Roblox
do
	local KG = fresh()
	server.keys[GOOD] = {status = "valid", uid = 9999}
	local r = start(KG); advance(0.3)
	submit(GOOD)
	check("other userId -> Invalid key", hasText("Invalid key") and not r.done)
	check("other userId not saved", files["yslem_key.txt"] == nil)
end

-- 4. erreurs reseau / limite / reponse incoherente : on refuse mais on garde la fenetre
for _, mode in ipairs({"down", "500", "garbage"}) do
	local KG = fresh()
	server.mode = mode
	local r = start(KG); advance(0.3)
	submit(GOOD)
	check("mode " .. mode .. " -> unreachable", hasText("Server unreachable") and not r.done)
end
do
	local KG = fresh()
	server.mode = "429"
	local r = start(KG); advance(0.3)
	submit(GOOD)
	check("429 -> wait message", hasText("Too many tries") and not r.done)
end

-- 5. cle sauvegardee revoquee : fichier efface, fenetre affichee, fermer -> false
do
	local KG = fresh()
	files["yslem_key.txt"] = GOOD
	server.keys[GOOD] = {status = "revoked", uid = 4242}
	local r = start(KG); advance(0.5)
	check("revoked saved: gate shown", gate() ~= nil and not r.done)
	check("revoked saved: file cleared", files["yslem_key.txt"] == nil)
	check("revoked saved: message", hasText("Key revoked"))
	find(gate(), function(d) return d.ClassName == "TextButton" and d.Text == "X" end).MouseButton1Click:Fire()
	advance(0.3)
	check("close returns false", r.done and r.value == false)
	check("close removes UI", gate() == nil)
end

-- 6. serveur injoignable avec une cle sauvegardee : on la garde et on la prefille
do
	local KG = fresh()
	files["yslem_key.txt"] = GOOD
	server.mode = "down"
	local r = start(KG); advance(0.5)
	check("down+saved: gate shown", gate() ~= nil and not r.done)
	check("down+saved: file kept", files["yslem_key.txt"] == GOOD)
	check("down+saved: prefilled", box().Text == GOOD)
end

-- 7. recheck : la cle est revoquee pendant que le script tourne
do
	local KG = fresh()
	files["yslem_key.txt"] = GOOD
	server.keys[GOOD] = {status = "valid", uid = 4242}
	local got
	start(KG, function(st) got = st end); advance(1)
	check("recheck: still running at start", got == nil)
	server.keys[GOOD].status = "revoked"
	advance(901)
	check("recheck: onInvalid revoked", got == "revoked")
	check("recheck: file cleared", files["yslem_key.txt"] == nil)
end

-- 8. recheck : 2 erreurs reseau tolerees, 3 d'affilee arretent le script
do
	local KG = fresh()
	files["yslem_key.txt"] = GOOD
	server.keys[GOOD] = {status = "valid", uid = 4242}
	local got
	start(KG, function(st) got = st end); advance(1)
	server.mode = "down"
	advance(900); advance(900)
	check("recheck: 2 errors tolerated", got == nil)
	server.mode = "ok"; advance(900)
	check("recheck: recovery resets counter", got == nil)
	server.mode = "down"
	advance(900); advance(900)
	check("recheck: 2 more errors tolerated", got == nil)
	advance(900)
	check("recheck: 3 errors stop", got == "error")
end

-- 9. executeur sans requete web
do
	local KG = fresh(true)
	local r = start(KG); advance(0.3)
	submit(GOOD)
	check("no request fn -> message", hasText("cannot make web requests") and not r.done)
end

print(string.format("KeyGate: %d ok, %d fail", passes, failures))
if failures > 0 then error("KeyGate tests failed") end
