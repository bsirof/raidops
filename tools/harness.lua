--[[
  harness.lua - load the addon headlessly and hand back its namespace.

  tools/loadtest.lua answers "does it start". Behavioural tests need to reach inside
  afterwards, so the loading itself lives here and both use it.

  Returns { RO, ns, stub, addonName }.
]]

local M = {}

function M.load(addonDir, stub)
  addonDir = (addonDir or "."):gsub("/$", "")

  local function exists(p) local f = io.open(p) if f then f:close() return true end end

  local tocPath
  local name = addonDir:match("([^/]+)$")
  for _, c in ipairs({ "RaidOpsAlpha.toc", (name or "") .. ".toc" }) do
    if exists(addonDir .. "/" .. c) then tocPath = addonDir .. "/" .. c break end
  end
  assert(tocPath, "no .toc found in " .. addonDir)

  local files, meta = {}, {}
  for line in io.lines(tocPath) do
    line = line:gsub("\r", "")
    local k, v = line:match("^##%s*([^:]+):%s*(.*)$")
    if k then meta[k] = v
    elseif line ~= "" and not line:match("^%s*#") then
      files[#files + 1] = (line:gsub("%s*%[.-%]%s*$", ""):gsub("%s+$", ""))
    end
  end

  local addonName = tocPath:match("([^/]+)%.toc$")

  stub.install()

  --> Saved variables must read as genuinely nil, or "DB = DB or {}" keeps a stub and
  --> every default silently lands on it.
  for sv in tostring(meta.SavedVariables or ""):gmatch("[^,%s]+") do
    rawset(_G, sv, nil)
    stub.nilGlobals[sv] = true
  end

  local ns = {}
  for _, rel in ipairs(files) do
    local full = addonDir .. "/" .. rel:gsub("\\", "/")
    assert(exists(full), "missing file: " .. full)
    assert(loadfile(full))(addonName, ns)
  end

  return { RO = ns.RO, ns = ns, stub = stub, addonName = addonName, savedVariables = meta.SavedVariables }
end

--- Fire the lifecycle events that bring the addon up.
function M.start(h)
  h.stub.fireEvent("ADDON_LOADED", h.addonName)
  h.stub.fireEvent("PLAYER_LOGIN")
  h.stub.runTimers(4)
end

return M
