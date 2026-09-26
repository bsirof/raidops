--[[
  splittest.lua - behavioural tests for Perf and Groups.

  Three layers, deliberately separated:

    1. Groups.Balance and Groups.PlanMoves are pure, so they are called directly with
       known inputs and the answers are checked arithmetically.
    2. The move plan is then REPLAYED against the stub's raid, whose SetRaidSubgroup
       reproduces the real silent failure on a full subgroup. A plan that looks valid
       but orders the moves wrongly fails here and nowhere else.
    3. The Perf collector is driven against a fake C_DamageMeter.

  DESIGN.md constraint 4: every check in here has been verified to fail against a
  deliberately broken implementation. If you add one, break the thing on purpose first.

  Usage: lua5.1 tools/splittest.lua <addon directory>
]]

local addonDir = (...) or "."
local toolsDir = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = toolsDir .. "/?.lua;" .. package.path

local stub = require("wowstub")
local harness = require("harness")

local pass, fail = 0, 0
local function check(label, cond, detail)
  if cond then pass = pass + 1; io.write(("  ok    %s\n"):format(label))
  else fail = fail + 1; io.write(("  FAIL  %s%s\n"):format(label, detail and ("  -- " .. tostring(detail)) or "")) end
end
local function section(name) io.write(("\n-- %s\n"):format(name)) end

local h = harness.load(addonDir, stub)
local RO = h.RO

--> Chat goes into a buffer so tests can assert on what the user would have been told.
local chat = {}
rawset(_G, "print", function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  chat[#chat + 1] = table.concat(parts, " ")
end)
local function chatHas(needle)
  for _, line in ipairs(chat) do if line:find(needle, 1, true) then return line end end
end

local NOW = 1700000000
rawset(_G, "time", function() return NOW end)

harness.start(h)

local Perf   = RO:GetModule("Perf")
local Groups = RO:GetModule("Groups")
assert(Perf and Groups, "modules did not register")

------------------------------------------------------------------ fixtures

--> Healers are deliberately lopsided: 1000 / 300 / 300 / 300. A pure lowest-total
--> greedy hands the 1000 healer his own side and piles the other three opposite him,
--> 1 against 3. Only the count-first tie-break keeps it 2 and 2, so this shape is what
--> proves that rule is present rather than incidental.
local RAID = {
  { name = "Tankone",  role = "TANK",    dps = 900000 },
  { name = "Tanktwo",  role = "TANK",    dps = 850000 },
  { name = "Healone",  role = "HEALER",  hps = 1000000 },
  { name = "Healtwo",  role = "HEALER",  hps = 300000 },
  { name = "Healthree",role = "HEALER",  hps = 300000 },
  { name = "Healfour", role = "HEALER",  hps = 300000 },
  { name = "Dpsa", role = "DAMAGER", dps = 2000000 }, { name = "Dpsb", role = "DAMAGER", dps = 1900000 },
  { name = "Dpsc", role = "DAMAGER", dps = 1800000 }, { name = "Dpsd", role = "DAMAGER", dps = 1700000 },
  { name = "Dpse", role = "DAMAGER", dps = 1600000 }, { name = "Dpsf", role = "DAMAGER", dps = 1500000 },
  { name = "Dpsg", role = "DAMAGER", dps = 1400000 }, { name = "Dpsh", role = "DAMAGER", dps = 1300000 },
  { name = "Dpsi", role = "DAMAGER", dps = 1200000 }, { name = "Dpsj", role = "DAMAGER", dps = 1100000 },
  { name = "Dpsk", role = "DAMAGER", dps = 1000000 }, { name = "Dpsl", role = "DAMAGER", dps =  900000 },
  --> No recorded data. These two are what the median fill exists for.
  { name = "Dpsm", role = "DAMAGER" }, { name = "Dpsn", role = "DAMAGER" },
}
local BY_NAME = {}
for _, p in ipairs(RAID) do BY_NAME[p.name] = p end

local function rosterOf(list)
  local out = {}
  for _, p in ipairs(list) do out[#out + 1] = { name = p.name, role = p.role, class = "MONK" } end
  return out
end

local function scoreFromFixture(name, role)
  local p = BY_NAME[name]
  if not p then return nil end
  if role == "HEALER" then return p.hps or p.dps end
  return p.dps or p.hps
end

------------------------------------------------------------------ 1. balance

section("Balance")

local assign, report = Groups.Balance(rosterOf(RAID), 2, 2, scoreFromFixture)
check("returns an assignment", type(assign) == "table", report)

local placed, dupes = {}, 0
for _, side in ipairs(report.sides) do
  for _, p in ipairs(side.members) do
    if placed[p.name] then dupes = dupes + 1 end
    placed[p.name] = true
  end
end
local lost = 0
for _, p in ipairs(RAID) do if not placed[p.name] then lost = lost + 1 end end
check("everyone placed exactly once", dupes == 0 and lost == 0, ("dupes=%d lost=%d"):format(dupes, lost))

local a, b = report.sides[1], report.sides[2]
check("tanks even", a.count.TANK == 1 and b.count.TANK == 1, ("%d/%d"):format(a.count.TANK, b.count.TANK))
check("healers even", a.count.HEALER == 2 and b.count.HEALER == 2, ("%d/%d"):format(a.count.HEALER, b.count.HEALER))
check("damage even", a.count.DAMAGER == 7 and b.count.DAMAGER == 7, ("%d/%d"):format(a.count.DAMAGER, b.count.DAMAGER))

--> With counts pinned at 2 and 2, {1000,300} against {300,300} is the best partition
--> available. Asserting the exact pair keeps this from passing on an arrangement that
--> merely looks reasonable.
local hiH = math.max(a.total.HEALER, b.total.HEALER)
local loH = math.min(a.total.HEALER, b.total.HEALER)
check("healing is the best split even counts allow", hiH == 1300000 and loH == 600000,
  ("%d vs %d"):format(hiH, loH))

--> Measured totals only. The two unknowns are median guesses and would otherwise
--> flatter the comparison.
local spread = math.abs(a.measured.DAMAGER - b.measured.DAMAGER) / math.max(a.measured.DAMAGER, b.measured.DAMAGER)
check("measured damage balanced within 3%", spread < 0.03,
  ("%.2f%% (%d vs %d)"):format(spread * 100, a.measured.DAMAGER, b.measured.DAMAGER))

check("unknowns reported", #report.estimated == 2
  and (report.estimated[1] == "Dpsm" or report.estimated[2] == "Dpsm"), table.concat(report.estimated, ","))

--> Scored at the role median an unknown sits mid-pack, so known players are assigned
--> after him. Scored at zero he would always be last on his side. That is the only
--> observable difference between the two, so it is what gets asserted.
local function knownFollows(name)
  for _, side in ipairs(report.sides) do
    local at
    for i, p in ipairs(side.members) do if p.name == name then at = i end end
    if at then
      for i = at + 1, #side.members do
        if side.members[i].measured and side.members[i].bucket == "DAMAGER" then return true end
      end
      return false
    end
  end
end
check("unknowns scored at the role median, not zero", knownFollows("Dpsm") and knownFollows("Dpsn"))

--> Subgroup geometry: side 1 owns groups 1-2, side 2 owns 3-4, five to a group.
local perGroup, sideOf = {}, {}
for name, g in pairs(assign) do
  perGroup[g] = (perGroup[g] or 0) + 1
  sideOf[name] = g <= 2 and 1 or 2
end
local overfull = false
for g, n in pairs(perGroup) do if n > 5 then overfull = true end end
check("no subgroup over five", not overfull)
local sideMatches = true
for i, side in ipairs(report.sides) do
  for _, p in ipairs(side.members) do if sideOf[p.name] ~= i then sideMatches = false end end
end
check("subgroups match the side they were assigned to", sideMatches)

-- no data at all
local flatAssign, flatReport = Groups.Balance(rosterOf(RAID), 2, 2, function() return nil end)
check("no data still produces a split", type(flatAssign) == "table", flatReport)
check("no data reports nothing was scored", flatReport and flatReport.scored == 0)
check("no data still splits roles evenly",
  flatReport and flatReport.sides[1].count.HEALER == 2 and flatReport.sides[1].count.DAMAGER == 7)

-- geometry failures
local bad, why = Groups.Balance(rosterOf(RAID), 4, 3, scoreFromFixture)
check("rejects more subgroups than a raid has", bad == nil and tostring(why):find("subgroups"), tostring(why))
local big = rosterOf(RAID)
for i = 1, 20 do big[#big + 1] = { name = "Extra" .. i, role = "DAMAGER" } end
local bad2, why2 = Groups.Balance(big, 2, 2, scoreFromFixture)
check("rejects a roster that will not fit", bad2 == nil and tostring(why2):find("not fit"), tostring(why2))

------------------------------------------------------------------ 2. moves

section("PlanMoves")

local function layout(spec)
  local t = {}
  for g, names in pairs(spec) do for _, n in ipairs(names) do t[n] = g end end
  return t
end

local same = layout({ [1] = { "a", "b" } })
local noMoves = Groups.PlanMoves(same, layout({ [1] = { "a", "b" } }))
check("nothing to do when already correct", noMoves and #noMoves == 0)

local simple = Groups.PlanMoves(layout({ [1] = { "a" }, [2] = {} }), layout({ [2] = { "a" } }))
check("a free destination is a plain move",
  simple and #simple == 1 and simple[1].kind == "set" and simple[1].group == 2)

--> The case the whole solver exists for: both groups full, everyone in the wrong one.
--> A move is impossible; only swaps work.
local fullA = { "a1", "a2", "a3", "a4", "a5" }
local fullB = { "b1", "b2", "b3", "b4", "b5" }
local cur = layout({ [1] = fullA, [2] = fullB })
local want = layout({ [1] = fullB, [2] = fullA })
local swapPlan, swapWhy = Groups.PlanMoves(cur, want)
check("full groups produce a plan", type(swapPlan) == "table", tostring(swapWhy))
local allSwaps = true
for _, m in ipairs(swapPlan or {}) do if m.kind ~= "swap" then allSwaps = false end end
check("full-group exchange uses swaps only", allSwaps)

local overfull, ofWhy = Groups.PlanMoves(cur, layout({ [1] = { "a1","a2","a3","a4","a5","b1" } }))
check("rejects a target with six in a group", overfull == nil and tostring(ofWhy):find("6 players"), tostring(ofWhy))

local missing, misWhy = Groups.PlanMoves(layout({ [1] = { "a" } }), layout({ [1] = { "ghost" } }))
check("rejects a target naming someone not in the raid",
  missing == nil and tostring(misWhy):find("not in the raid"), tostring(misWhy))

------------------------------------------------------- 3. replay against the stub

section("Move replay (stub reproduces the silent failure on a full group)")

--> A plan can be internally consistent and still be wrong, because the real API
--> refuses a move into a full subgroup without saying so. Replaying against a stub
--> that behaves the same way is the only check that catches a bad ORDERING.
local function replay(startLayout, target)
  local order = {}
  for name, g in pairs(startLayout) do order[#order + 1] = { name = name, subgroup = g } end
  table.sort(order, function(x, y) return x.name < y.name end)
  stub.setRaid(order)
  local index = {}
  for i, m in ipairs(stub.raid.members) do index[m.name] = i end

  local moves, why = Groups.PlanMoves(startLayout, target)
  if not moves then return nil, why end
  for _, m in ipairs(moves) do
    if m.kind == "set" then SetRaidSubgroup(index[m.name], m.group)
    else SwapRaidSubgroup(index[m.a], index[m.b]) end
  end
  local final, wrong = stub.raidLayout(), {}
  for name, g in pairs(target) do
    if final[name] ~= g then wrong[#wrong + 1] = ("%s in %s wanted %d"):format(name, tostring(final[name]), g) end
  end
  return #wrong == 0, table.concat(wrong, "; "), #moves
end

local ok1, why1, n1 = replay(cur, want)
check("full-group exchange lands correctly", ok1, why1)
check("and does it in a sane number of moves", n1 and n1 <= 10, tostring(n1))

--> A three-way rotation across full groups: the case where a naive "swap the two that
--> want each other's seats" never finds a pair.
local rot = layout({
  [1] = { "x1", "x2", "x3", "x4", "x5" },
  [2] = { "y1", "y2", "y3", "y4", "y5" },
  [3] = { "z1", "z2", "z3", "z4", "z5" },
})
local rotWant = layout({
  [1] = { "z1", "z2", "z3", "z4", "z5" },
  [2] = { "x1", "x2", "x3", "x4", "x5" },
  [3] = { "y1", "y2", "y3", "y4", "y5" },
})
local ok2, why2 = replay(rot, rotWant)
check("three-way rotation across full groups lands correctly", ok2, why2)

--> Partially full groups, a mixture of moves and swaps.
local mixed = layout({
  [1] = { "m1", "m2", "m3", "m4", "m5" },
  [2] = { "m6", "m7" },
  [3] = { "m8", "m9", "m10" },
})
local mixedWant = layout({
  [1] = { "m6", "m7", "m8", "m9", "m10" },
  [2] = { "m1", "m2", "m3" },
  [3] = { "m4", "m5" },
})
local ok3, why3 = replay(mixed, mixedWant)
check("mixed moves and swaps land correctly", ok3, why3)

--> The stub must actually refuse a full destination, or every check above is vacuous.
stub.setRaid({
  { name = "f1", subgroup = 1 }, { name = "f2", subgroup = 1 }, { name = "f3", subgroup = 1 },
  { name = "f4", subgroup = 1 }, { name = "f5", subgroup = 1 }, { name = "f6", subgroup = 2 },
})
SetRaidSubgroup(6, 1)
check("stub refuses a move into a full subgroup, silently", stub.raidLayout()["f6"] == 2,
  tostring(stub.raidLayout()["f6"]))

------------------------------------------------------------------ 4. collector

section("Perf collector")

check("meter reports available", (Perf:Available()))

stub.setMeter({
  { id = 101, duration = 300, name = "Boss One",
    dps = {
      { name = "Gray-Illidan", class = "MONK", rate = 1000000 },
      { name = "Alpha", class = "WARRIOR", rate = 800000 },
      { name = "Gray's Pet", class = nil, rate = 50000 },        -- no class: a pet
    },
    hps = { { name = "Healer", class = "PRIEST", rate = 400000 } } },
})
--> One source with no amountPerSecond, so the rate has to come from total / duration.
stub.meter.data[101][1].combatSources[#stub.meter.data[101][1].combatSources + 1] =
  { name = "Derived", classFilename = "MAGE", totalAmount = 600000 }

local n = Perf:FoldSession(101, "Boss One", 300)
check("fold returns a sample count", n == 4, tostring(n))

local snap = Perf:Snapshot()
check("pets and NPCs excluded", snap["gray's pet"] == nil)
check("raider recorded", snap["gray"] and snap["gray"].dps == 1000000)
check("realm stripped from the key", snap["gray"] and snap["gray"].name == "Gray-Illidan")
check("rate derived when amountPerSecond is missing",
  snap["derived"] and math.abs(snap["derived"].dps - 2000) < 0.01,
  snap["derived"] and snap["derived"].dps)
check("healer has hps and no dps", snap["healer"] and snap["healer"].hps == 400000 and snap["healer"].dps == nil)
check("refolding the same session is refused", Perf:FoldSession(101, "x", 300) == nil)

stub.meter.sessions[#stub.meter.sessions + 1] = { sessionID = 102, durationSeconds = 300, name = "Boss Two" }
stub.meter.data[102] = {
  [1] = { durationSeconds = 300, combatSources = {
    { name = "Gray", classFilename = "MONK", amountPerSecond = 2000000 } } },
  [2] = { durationSeconds = 300, combatSources = {} },
}
check("CollectLatest folds the newest session", Perf:CollectLatest() == 1)
check("it averages the night rather than replacing",
  math.abs(Perf:Snapshot()["gray"].dps - 1500000) < 0.01, Perf:Snapshot()["gray"].dps)

stub.meter.sessions[#stub.meter.sessions + 1] = { sessionID = 103, durationSeconds = 5, name = "Trash" }
stub.meter.data[103] = {
  [1] = { durationSeconds = 5, combatSources = {
    { name = "Gray", classFilename = "MONK", amountPerSecond = 9000000 } } },
  [2] = { durationSeconds = 5, combatSources = {} },
}
local shortN, shortWhy = Perf:CollectLatest()
check("a short pull is skipped", shortN == nil and tostring(shortWhy):find("minimum"), tostring(shortWhy))
check("and does not move the average", math.abs(Perf:Snapshot()["gray"].dps - 1500000) < 0.01)
check("and is marked consumed", select(2, Perf:CollectLatest()) == "no new combat session found")

NOW = NOW + 9 * 3600
check("samples age out of the window", next(Perf:Snapshot()) == nil)
NOW = NOW - 9 * 3600

local savedMeter = _G.C_DamageMeter
rawset(_G, "C_DamageMeter", nil)
local av, avWhy = Perf:Available()
check("missing C_DamageMeter degrades rather than erroring", av == false and type(avWhy) == "string")
check("Sessions returns empty without the API", #Perf:Sessions() == 0)
check("Snapshot still works without the API", (pcall(function() return Perf:Snapshot() end)))
rawset(_G, "C_DamageMeter", savedMeter)

stub.meter.data[104] = { [1] = "not a table" }
stub.meter.sessions[#stub.meter.sessions + 1] = { sessionID = 104, durationSeconds = 300, name = "Garbage" }
local okG, nG = pcall(Perf.CollectLatest, Perf)
check("a malformed API response is handled", okG and nG == nil, tostring(nG))

------------------------------------------------------------- 5. end to end

section("End to end through /roa split")

Perf:Reset()
local raidMembers = {}
for i, p in ipairs(RAID) do
  raidMembers[i] = { name = p.name, subgroup = math.floor((i - 1) / 5) + 1, role = p.role }
end
stub.setRaid(raidMembers)

--> Feed the fixture in as one recorded fight so the live path reads real stored data
--> rather than a test hook.
local dpsSrc, hpsSrc = {}, {}
for _, p in ipairs(RAID) do
  if p.dps then dpsSrc[#dpsSrc + 1] = { name = p.name, class = "MONK", rate = p.dps } end
  if p.hps then hpsSrc[#hpsSrc + 1] = { name = p.name, class = "PRIEST", rate = p.hps } end
end
stub.setMeter({ { id = 500, duration = 300, name = "Fixture", dps = dpsSrc, hps = hpsSrc } })
check("fixture folded in", Perf:CollectLatest() ~= nil)

chat = {}
SlashCmdList["ROALPHA"]("split")
check("preview names both sides", chatHas("Side 1") and chatHas("Side 2"), table.concat(chat, " | "))
check("preview flags the players with no data", chatHas("Dpsm") and chatHas("no fight data"))
check("preview does not move anyone", stub.raidLayout()["Dpsa"] == raidMembers[7].subgroup)
check("a plan is held for apply", Groups.plan ~= nil)

local planned = Groups.plan
chat = {}
SlashCmdList["ROALPHA"]("split apply")
stub.runTimers(200)

local final, wrong = stub.raidLayout(), {}
for name, want in pairs(planned.assign) do
  if final[name] ~= want then wrong[#wrong + 1] = ("%s in %s wanted %d"):format(name, tostring(final[name]), want) end
end
check("apply puts the raid where the plan said", #wrong == 0, table.concat(wrong, "; "))
check("apply reports success", chatHas("raid matches the plan"), table.concat(chat, " | "))

chat = {}
stub.raid.lead = false
local leadOk, leadWhy = Groups:Apply(planned)
check("refuses to move people without lead or assist",
  leadOk == nil and tostring(leadWhy):find("lead or assist"), tostring(leadWhy))
stub.raid.lead = true

chat = {}
rawset(_G, "InCombatLockdown", function() return true end)
local combatOk, combatWhy = Groups:Apply(planned)
check("refuses to move people in combat", combatOk == nil and tostring(combatWhy):find("combat"), tostring(combatWhy))
rawset(_G, "InCombatLockdown", function() return false end)

stub.setRaid({})
chat = {}
SlashCmdList["ROALPHA"]("split")
check("out of a raid it says so rather than erroring", chatHas("not in a raid"), table.concat(chat, " | "))

------------------------------------------------------------------ done

io.write(("\n  %d passed, %d failed\n\n"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
