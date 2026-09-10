--[[
  loadtest.lua - headless load smoke test for a WoW addon.

  Usage:  lua5.1 tools/loadtest.lua <addon directory> [TocFile.toc]

  Reads the TOC, executes every listed Lua file in order with the same
  (addonName, addonTable) varargs the game passes, then fires ADDON_LOADED,
  PLAYER_LOGIN and PLAYER_ENTERING_WORLD, drains pending C_Timer callbacks,
  and runs one OnUpdate tick.

  Exit code 0 = the addon loaded and initialised without a Lua error.
]]

local addonDir = ...
local tocArg = select(2, ...)
if not addonDir then
  io.stderr:write("usage: lua5.1 loadtest.lua <addon directory> [TocFile.toc]\n")
  os.exit(2)
end
addonDir = addonDir:gsub("/$", "")

local toolsDir = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = toolsDir .. "/?.lua;" .. package.path
local stub = require("wowstub")

------------------------------------------------------------------ helpers

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

local function findToc()
  if tocArg then return addonDir .. "/" .. tocArg end
  local name = addonDir:match("([^/]+)$")
  for _, candidate in ipairs({ name .. ".toc", name .. "-Mainline.toc" }) do
    if exists(addonDir .. "/" .. candidate) then return addonDir .. "/" .. candidate end
  end
  -- fall back to any .toc via a directory listing
  local p = io.popen('ls "' .. addonDir .. '"/*.toc 2>/dev/null')
  if p then
    local first = p:read("*l")
    p:close()
    if first then return first end
  end
  return nil
end

local function readTocFiles(tocPath)
  local files, meta = {}, {}
  for line in io.lines(tocPath) do
    line = line:gsub("\r", "")
    local key, value = line:match("^##%s*([^:]+):%s*(.*)$")
    if key then
      meta[key] = value
    elseif line ~= "" and not line:match("^%s*#") then
      -- strip TOC conditional suffixes like [AllowLoadGameType classic]
      local entry = line:gsub("%s*%[.-%]%s*$", ""):gsub("%s+$", "")
      if entry ~= "" then files[#files + 1] = entry end
    end
  end
  return files, meta
end

local function expandXml(xmlPath, baseDir, out)
  local fh = io.open(xmlPath, "r")
  if not fh then
    out[#out + 1] = { path = xmlPath, missing = true }
    return
  end
  local body = fh:read("*a")
  fh:close()
  for rel in body:gmatch('[Ss]cript%s+file="([^"]+)"') do
    out[#out + 1] = { path = baseDir .. "/" .. rel:gsub("\\", "/") }
  end
  for rel in body:gmatch('[Ii]nclude%s+file="([^"]+)"') do
    local nested = baseDir .. "/" .. rel:gsub("\\", "/")
    expandXml(nested, nested:match("^(.*)/[^/]+$") or baseDir, out)
  end
end

------------------------------------------------------------------ run

local tocPath = findToc()
if not tocPath then
  io.stderr:write("no .toc found in " .. addonDir .. "\n")
  os.exit(2)
end

local entries, meta = readTocFiles(tocPath)
local addonName = tocPath:match("([^/]+)%.toc$")

stub.install()

-- Saved variables start empty, exactly like a first-ever login.
--
-- Clearing the raw slot is not enough on its own: the stub's __index hands back a
-- universal stub for any global it does not know, so the next read would quietly
-- succeed and a file-scope database access would look fine. Registering the name in
-- nilGlobals is what actually makes it read nil, which is the whole point - that is
-- the bug class this harness exists to catch.
for sv in tostring(meta.SavedVariables or ""):gmatch("[^,%s]+") do
  rawset(_G, sv, nil)
  stub.nilGlobals[sv] = true
end

local addonTable = {}
local loadList = {}
for _, entry in ipairs(entries) do
  local rel = entry:gsub("\\", "/")
  local full = addonDir .. "/" .. rel
  if rel:match("%.xml$") then
    expandXml(full, full:match("^(.*)/[^/]+$") or addonDir, loadList)
  else
    loadList[#loadList + 1] = { path = full }
  end
end

print(("== load test: %s (%s)"):format(addonName, tocPath:match("([^/]+)$")))
print(("   interface %s, %d toc entries, %d lua files"):format(
  meta.Interface or "?", #entries, #loadList))
print("")

--[[
  Optional localization coverage. Modules cache "local L = ns.L" at file scope, where
  ns is the addon table passed as the second vararg, so the proxy has to be swapped in
  after the last localization file loads and before the first module file, or nothing
  would see it.
]]
local trackL = os.getenv("RAIDOPS_TRACK_L")
local Lreads = {}
local lastLocalizationIndex = 0
for i, item in ipairs(loadList) do
  if item.path:find("localization") then lastLocalizationIndex = i end
end

local function installLProxy()
  local real = rawget(addonTable, "L")
  if type(real) ~= "table" then return false end
  local proxy = setmetatable({}, {
    __index = function(_, k)
      Lreads[k] = (Lreads[k] or 0) + 1
      return real[k]
    end,
    __newindex = function(_, k, v) real[k] = v end,
    __pairs = function() return pairs(real) end,
  })
  rawset(addonTable, "L", proxy)
  rawset(addonTable, "__Lreal", real)
  return true
end

local failures = 0
for i, item in ipairs(loadList) do
  local short = item.path:gsub("^" .. addonDir:gsub("(%W)", "%%%1") .. "/", "")
  if item.missing then
    print(("  FAIL  %-46s referenced but not on disk"):format(short))
    failures = failures + 1
  elseif not exists(item.path) then
    print(("  FAIL  %-46s not on disk"):format(short))
    failures = failures + 1
  else
    local chunk, syntaxErr = loadfile(item.path)
    if not chunk then
      print(("  FAIL  %-46s %s"):format(short, syntaxErr))
      failures = failures + 1
    else
      local ok, runErr = pcall(chunk, addonName, addonTable)
      if ok then
        print(("  ok    %-46s"):format(short))
      else
        print(("  FAIL  %-46s %s"):format(short, tostring(runErr)))
        failures = failures + 1
      end
    end
  end
  if trackL and i == lastLocalizationIndex then installLProxy() end
end

--[[
  Core pcalls every module handler on purpose, so one broken module cannot take the
  addon down. That is correct in the game and blinding in a test: a module whose
  OnEnable throws prints a line and the run still ends "loaded clean, no Lua errors".
  Core exposes RO.onModuleError as the seam. Anything reported through it is a failure.
]]
local moduleErrors = {}
local RO = rawget(addonTable, "RO")
do
  if type(RO) == "table" then
    RO.onModuleError = function(context, err)
      moduleErrors[#moduleErrors + 1] = ("%s: %s"):format(tostring(context), tostring(err))
    end
  else
    print("  WARN  addonTable.RO not found; module errors will not be visible")
  end
end

print("")
local function phase(label, fn)
  local ok, err = pcall(fn)
  if ok then
    print(("  ok    %s"):format(label))
  else
    print(("  FAIL  %s: %s"):format(label, tostring(err)))
    failures = failures + 1
  end
end

phase("ADDON_LOADED", function() stub.fireEvent("ADDON_LOADED", addonName) end)
phase("PLAYER_LOGIN", function() stub.fireEvent("PLAYER_LOGIN") end)
phase("PLAYER_ENTERING_WORLD", function() stub.fireEvent("PLAYER_ENTERING_WORLD", true, false) end)
phase("GROUP_ROSTER_UPDATE", function() stub.fireEvent("GROUP_ROSTER_UPDATE") end)
phase("pending C_Timer callbacks", function() stub.runTimers(4) end)
phase("OnUpdate tick", function() stub.runOnUpdate(0.2) end)

--[[
  Building each module's options pane is where most module UI code actually runs, so a
  run that never opens the config window barely tests a module at all.

  This block used to look for addonTable.Modules, which is the stable build's shape, not
  this one. It was always nil here, so every pane phase silently skipped and the run
  still reported success - a whole section of the harness that could not fail.

  Config.lua builds a pane the first time its tab is opened, and opening the window only
  builds tab 1. Clicking every tab is the closest headless equivalent of a user going
  through the window. A pane that throws is caught by Config and reported through
  RO.moduleError, so it lands in moduleErrors rather than failing a phase here.
]]
if type(RO) == "table" and RO.OpenConfig then
  phase("open config window", function() RO:OpenConfig() end)

  local cfg = RO.configFrame
  if cfg and cfg.tabs then
    local function clickTab(i)
      local tab = cfg.tabs[i]
      local onClick = tab and stub.scriptStore[tab] and stub.scriptStore[tab].OnClick
      if not onClick then return false end
      onClick(tab)
      return true
    end

    for i, module in ipairs(RO.modules) do
      local label = tostring(module.title or module.name)
      phase(("options pane: %s"):format(label), function()
        if not clickTab(i) then error("tab " .. i .. " is missing or has no OnClick") end
      end)
    end

    -- A pane is built once and afterwards only shown again, which is a different path
    -- through select() and breaks in its own ways.
    phase("second pass over option panes", function()
      for i in ipairs(RO.modules) do clickTab(i) end
    end)
  else
    print("  FAIL  config window built no tabs")
    failures = failures + 1
  end
elseif type(RO) == "table" then
  print("  FAIL  RO.OpenConfig is missing; option panes were not exercised")
  failures = failures + 1
end

--[[
  Self-owned globals check.

  The stub auto-creates any global the addon reads, which is what keeps deep UI code
  running, but it also means a global the addon FAILED to export looks fine. That is
  exactly how a real bug slipped through: upstream exports _G.ELib only when the addon
  folder is named "MRT", so renaming the folder silently killed it, and the harness
  happily handed out a stub instead.

  So: every global the addon assigns through _G in its own source must NOT have been
  auto-stubbed during the run. If it was, the export did not happen on a path that
  mattered. Globals assigned inside functions that never ran are never read either, so
  they do not produce false positives.
]]
local selfOwned = {}
for _, item in ipairs(loadList) do
  local fh = io.open(item.path, "r")
  if fh then
    local body = fh:read("*a")
    fh:close()
    for name in body:gmatch("_G%.([%a_][%w_]*)%s*=[^=]") do selfOwned[name] = item.path end
    for name in body:gmatch('_G%["([%a_][%w_]*)"%]%s*=[^=]') do selfOwned[name] = item.path end
  end
end

-- State, not timing. A read before the owning file loads is normal (version guards do
-- exactly that), so what matters is whether the global holds a real value at the end.
-- If it is still a stub, the assignment never ran.
local leaked = {}
for name, src in pairs(selfOwned) do
  if stub.isStub(rawget(_G, name)) then
    leaked[#leaked + 1] = { name = name, src = src }
  end
end
table.sort(leaked, function(a, b) return a.name < b.name end)

if #leaked > 0 then
  print("")
  for _, e in ipairs(leaked) do
    local short = e.src:gsub("^" .. addonDir:gsub("(%W)", "%%%1") .. "/", "")
    print(("  FAIL  global '%s' is assigned in %s but never got a real value")
      :format(e.name, short))
    failures = failures + 1
  end
end

print("")
print(("  frames created:      %d"):format(#stub.frames))
local slashCount = 0
for _ in pairs(stub.slash) do slashCount = slashCount + 1 end
print(("  slash handlers:      %d"):format(slashCount))
local evCount = 0
for _, evs in pairs(stub.eventFrames) do for _ in pairs(evs) do evCount = evCount + 1 end end
print(("  event registrations: %d"):format(evCount))

local names = {}
for k in pairs(stub.unknownGlobals) do names[#names + 1] = k end
table.sort(names)
print(("  stubbed globals:     %d (see --apis to list)"):format(#names))

if trackL then
  local hit = 0
  for _ in pairs(Lreads) do hit = hit + 1 end
  print(("  localization keys read: %d"):format(hit))
  local outPath = os.getenv("RAIDOPS_TRACK_L")
  if outPath ~= "1" and outPath ~= "" then
    local fh = io.open(outPath, "w")
    if fh then
      local keys = {}
      for k in pairs(Lreads) do keys[#keys + 1] = k end
      table.sort(keys)
      for _, k in ipairs(keys) do fh:write(k, "\n") end
      fh:close()
      print(("  wrote key list to       %s"):format(outPath))
    end
  end
end

local dumpPath = os.getenv("RAIDOPS_DUMP_GLOBALS")
if dumpPath then
  local all = {}
  for k in pairs(_G) do if type(k) == "string" then all[k] = true end end
  for k in pairs(stub.unknownGlobals) do all[k] = true end
  local list = {}
  for k in pairs(all) do list[#list + 1] = k end
  table.sort(list)
  local fh = io.open(dumpPath, "w")
  if fh then
    for _, k in ipairs(list) do fh:write(k, "\n") end
    fh:close()
    print(("  wrote %d global names to %s"):format(#list, dumpPath))
  end
end

if os.getenv("RAIDOPS_LIST_APIS") then
  print("")
  print("  APIs resolved through the universal stub:")
  for _, n in ipairs(names) do
    print(("    %-42s x%d"):format(n, stub.unknownGlobals[n]))
  end
end

if #moduleErrors > 0 then
  print("")
  for _, e in ipairs(moduleErrors) do
    print(("  FAIL  module error  %s"):format(e))
    failures = failures + 1
  end
end

print("")
if failures == 0 then
  print("RESULT: loaded clean, no Lua errors")
  os.exit(0)
else
  print(("RESULT: %d failure(s)"):format(failures))
  os.exit(1)
end
