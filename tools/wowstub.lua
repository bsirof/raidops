--[[
  wowstub.lua - a deliberately shallow World of Warcraft API stub.

  Purpose: let addon files execute under plain Lua 5.1 far enough to surface
  real load-time errors (nil arithmetic, bad concat, indexing a nil field on a
  real table, malformed control flow). It is a smoke test, not an emulator.

  Anything the addon asks for that is not defined here resolves to a universal
  stub object that is callable, indexable and chainable, and every such access
  is recorded so the harness can report which APIs the addon actually touches.
]]

local M = {}

M.unknownGlobals = {}   -- name -> read count
M.frames = {}
M.eventFrames = {}      -- frame -> { event -> true }
M.slash = {}
M.nilGlobals = {}

------------------------------------------------------------------ universal stub

local stubMT = {}
local function newStub(name)
  return setmetatable({ __stubname = name or "?" }, stubMT)
end
M.newStub = newStub

function M.isStub(v)
  return type(v) == "table" and getmetatable(v) == stubMT
end

stubMT.__index = function(t, k)
  if type(k) ~= "string" then return nil end
  if k:sub(1, 2) == "__" then return nil end
  local child = newStub((rawget(t, "__stubname") or "?") .. "." .. tostring(k))
  rawset(t, k, child)
  return child
end
stubMT.__call = function(t, ...) return newStub(rawget(t, "__stubname") .. "()") end
stubMT.__tostring = function(t) return "<stub:" .. tostring(rawget(t, "__stubname")) .. ">" end
stubMT.__concat = function(a, b) return tostring(a) .. tostring(b) end
stubMT.__len = function() return 0 end

--[[
  A stub only ever appears where the addon called an API this harness does not model.
  Treating it as 0 in arithmetic keeps deep UI code running instead of dying on a
  bogus "arithmetic on a table value". Genuine nil arithmetic still errors, because
  nil never becomes a stub.
]]
local function stubnum(v) return type(v) == "number" and v or 0 end
stubMT.__add = function(a, b) return stubnum(a) + stubnum(b) end
stubMT.__sub = function(a, b) return stubnum(a) - stubnum(b) end
stubMT.__mul = function(a, b) return stubnum(a) * stubnum(b) end
stubMT.__div = function(a, b) local d = stubnum(b) return d == 0 and 0 or stubnum(a) / d end
stubMT.__mod = function(a, b) local d = stubnum(b) return d == 0 and 0 or stubnum(a) % d end
stubMT.__pow = function(a, b) return stubnum(a) ^ stubnum(b) end
stubMT.__unm = function() return 0 end

------------------------------------------------------------------ frames

local frameMT = {}
local scriptStore = setmetatable({}, { __mode = "k" })

local realFrameMethods = {}

function realFrameMethods:SetScript(handler, fn)
  scriptStore[self] = scriptStore[self] or {}
  scriptStore[self][handler] = fn
  return self
end
function realFrameMethods:GetScript(handler)
  return scriptStore[self] and scriptStore[self][handler]
end
function realFrameMethods:HookScript(handler, fn)
  return realFrameMethods.SetScript(self, handler, fn)
end
function realFrameMethods:RegisterEvent(ev)
  M.eventFrames[self] = M.eventFrames[self] or {}
  M.eventFrames[self][ev] = true
  return self
end
function realFrameMethods:RegisterUnitEvent(ev)
  return realFrameMethods.RegisterEvent(self, ev)
end
function realFrameMethods:UnregisterEvent(ev)
  if M.eventFrames[self] then M.eventFrames[self][ev] = nil end
  return self
end
function realFrameMethods:UnregisterAllEvents()
  M.eventFrames[self] = nil
  return self
end
function realFrameMethods:IsEventRegistered(ev)
  return M.eventFrames[self] and M.eventFrames[self][ev] or false
end
function realFrameMethods:GetName() return rawget(self, "__name") end
function realFrameMethods:GetObjectType() return rawget(self, "__ftype") or "Frame" end
function realFrameMethods:GetParent() return rawget(self, "__parent") end
function realFrameMethods:IsShown() return rawget(self, "__shown") and true or false end
function realFrameMethods:IsVisible() return rawget(self, "__shown") and true or false end
function realFrameMethods:Show() rawset(self, "__shown", true) return self end
function realFrameMethods:Hide() rawset(self, "__shown", false) return self end
function realFrameMethods:SetShown(v) rawset(self, "__shown", v and true or false) return self end
function realFrameMethods:GetWidth() return rawget(self, "__w") or 100 end
function realFrameMethods:GetHeight() return rawget(self, "__h") or 100 end
function realFrameMethods:SetWidth(v) rawset(self, "__w", v) return self end
function realFrameMethods:SetHeight(v) rawset(self, "__h", v) return self end
function realFrameMethods:SetSize(w, h) rawset(self, "__w", w) rawset(self, "__h", h) return self end
function realFrameMethods:GetEffectiveScale() return 1 end
function realFrameMethods:GetScale() return 1 end
function realFrameMethods:GetLeft() return 0 end
function realFrameMethods:GetRight() return 100 end
function realFrameMethods:GetTop() return 100 end
function realFrameMethods:GetBottom() return 0 end
function realFrameMethods:GetCenter() return 50, 50 end
function realFrameMethods:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function realFrameMethods:GetNumPoints() return 1 end
function realFrameMethods:GetText() return rawget(self, "__text") or "" end
function realFrameMethods:SetText(v) rawset(self, "__text", v) return self end
function realFrameMethods:GetStringWidth() return 50 end
function realFrameMethods:GetStringHeight() return 12 end
function realFrameMethods:GetChecked() return rawget(self, "__checked") and true or false end
function realFrameMethods:SetChecked(v) rawset(self, "__checked", v and true or false) return self end
function realFrameMethods:GetValue() return rawget(self, "__value") or 0 end
function realFrameMethods:SetValue(v) rawset(self, "__value", v) return self end
function realFrameMethods:GetNumber() return tonumber(rawget(self, "__text")) or 0 end
function realFrameMethods:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function realFrameMethods:GetRegions() return end
function realFrameMethods:GetChildren() return end
function realFrameMethods:GetNumChildren() return 0 end
function realFrameMethods:IsMouseOver() return false end
function realFrameMethods:IsMovable() return false end
function realFrameMethods:IsForbidden() return false end
function realFrameMethods:IsProtected() return false end
function realFrameMethods:IsObjectType() return true end
function realFrameMethods:GetID() return rawget(self, "__id") or 0 end
function realFrameMethods:SetID(v) rawset(self, "__id", v) return self end
function realFrameMethods:GetAttribute(k) return rawget(self, "__attr") and self.__attr[k] end
function realFrameMethods:SetAttribute(k, v)
  rawset(self, "__attr", rawget(self, "__attr") or {})
  self.__attr[k] = v
  return self
end
function realFrameMethods:CreateTexture(name, layer) return M.CreateFrame("Texture", name, self) end
function realFrameMethods:CreateFontString(name) return M.CreateFrame("FontString", name, self) end
function realFrameMethods:CreateMaskTexture(name) return M.CreateFrame("MaskTexture", name, self) end
function realFrameMethods:CreateAnimationGroup(name) return M.CreateFrame("AnimationGroup", name, self) end
function realFrameMethods:CreateLine(name) return M.CreateFrame("Line", name, self) end
function realFrameMethods:CreateAnimation(atype, name) return M.CreateFrame(atype or "Animation", name, self) end
function realFrameMethods:GetProgress() return 0 end
function realFrameMethods:GetAnimations() return end
function realFrameMethods:GetRegionParent() return rawget(self, "__parent") end
function realFrameMethods:GetTexture() return rawget(self, "__tex") end
function realFrameMethods:SetTexture(v) rawset(self, "__tex", v) return self end
function realFrameMethods:GetObjectLoaders() return end

--[[
  Unknown keys on a widget split two ways, and getting this wrong is what makes a
  naive stub useless:

    f:SetSomething(...)  must work and stay chainable
    f.SomeField          must be nil on a fresh widget, because addon code writes
                         "self.X = self.X or self:CreateTexture()" everywhere

  A blanket "return a function" breaks the second form: the field reads truthy and
  the addon stores a function where it expected a texture. So unknown keys are
  treated as methods only when they carry a widget-method prefix.
]]
local methodPrefixes = {
  "Set", "Clear", "Add", "Insert", "Remove", "Register", "Unregister", "Enable",
  "Disable", "Show", "Hide", "Start", "Stop", "Play", "Pause", "Restart", "Advance",
  "Toggle", "Lock", "Unlock", "Select", "Deselect", "Scroll", "Click", "Highlight",
  "Update", "Draw", "Mark", "Notify", "Request", "Apply", "Reset", "Rotate", "Adjust",
  "Attach", "Detach", "Raise", "Lower", "Save", "Restore", "Do", "On", "Init",
  "Finish", "Cancel", "Kill", "Fire", "Push", "Pop", "Queue", "Flush",
}
local getterPrefixes = { "Get", "Is", "Has", "Can", "Should", "Are", "Was" }

local function matchesPrefix(k, list)
  for _, p in ipairs(list) do
    -- exact match ("Play", "Stop") or prefix followed by a capital ("SetFoo")
    if k == p then return true end
    if k:sub(1, #p) == p and #k > #p and k:sub(#p + 1, #p + 1):match("%u") then
      return true
    end
  end
  return false
end

local chainNoop = function(self) return self end
local nilNoop = function() return nil end

frameMT.__index = function(t, k)
  local real = realFrameMethods[k]
  if real then return real end
  if type(k) ~= "string" then return nil end
  if k:sub(1, 2) == "__" then return nil end
  if matchesPrefix(k, methodPrefixes) then
    rawset(t, k, chainNoop)
    return chainNoop
  end
  if matchesPrefix(k, getterPrefixes) then
    rawset(t, k, nilNoop)
    return nilNoop
  end
  return nil
end
frameMT.__tostring = function(t) return "<frame:" .. tostring(rawget(t, "__name") or "anon") .. ">" end

local frameCount = 0
function M.CreateFrame(ftype, name, parent, template, id)
  frameCount = frameCount + 1
  local f = setmetatable({
    __ftype = ftype or "Frame",
    __name = name,
    __parent = parent,
    __template = template,
    __id = id,
    __shown = true,
  }, frameMT)
  M.frames[#M.frames + 1] = f
  if name then rawset(_G, name, f) end
  return f
end

------------------------------------------------------------------ event firing

function M.fireEvent(event, ...)
  local fired = 0
  for frame, events in pairs(M.eventFrames) do
    if events[event] then
      local handler = scriptStore[frame] and scriptStore[frame]["OnEvent"]
      if handler then
        handler(frame, event, ...)
        fired = fired + 1
      end
    end
  end
  return fired
end

function M.runOnUpdate(elapsed)
  local ran = 0
  for frame, scripts in pairs(scriptStore) do
    if scripts.OnUpdate then
      scripts.OnUpdate(frame, elapsed or 0.1)
      ran = ran + 1
    end
  end
  return ran
end

M.scriptStore = scriptStore

------------------------------------------------------------------ timers

M.pendingTimers = {}

--[[
  C_Timer.NewTimer and NewTicker hand the ticker object to the callback, and addon
  code stores state on that object between scheduling and firing. So the ticker has
  to be a real table that survives, not a throwaway stub.
]]
local function schedule(delay, fn, passSelf)
  local ticker = M.CreateFrame("Ticker")
  ticker.Cancel = function(self) self.__cancelled = true end
  ticker.IsCancelled = function(self) return self.__cancelled and true or false end
  M.pendingTimers[#M.pendingTimers + 1] = { delay = delay, fn = fn, ticker = ticker, passSelf = passSelf }
  return ticker
end

function M.runTimers(maxRounds)
  local ran = 0
  for _ = 1, (maxRounds or 3) do
    local batch = M.pendingTimers
    if #batch == 0 then break end
    M.pendingTimers = {}
    for _, t in ipairs(batch) do
      if not t.ticker.__cancelled then
        if t.passSelf then t.fn(t.ticker) else t.fn() end
        ran = ran + 1
      end
    end
  end
  return ran
end

------------------------------------------------------------------ globals

function M.install()
  local G = _G

  -- Lua stdlib names WoW exposes as globals
  G.format, G.gsub, G.strsub, G.strupper, G.strlower, G.strlen, G.strrep =
    string.format, string.gsub, string.sub, string.upper, string.lower, string.len, string.rep
  G.strfind, G.strmatch, G.gmatch, G.strbyte, G.strchar, G.strrev =
    string.find, string.match, string.gmatch, string.byte, string.char, string.reverse
  G.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
  G.strsplit = function(sep, str, limit)
    local out, pattern = {}, "([^" .. sep:gsub("(%W)", "%%%1") .. "]*)"
    for piece in tostring(str):gmatch(pattern .. "[" .. sep:gsub("(%W)", "%%%1") .. "]?") do
      out[#out + 1] = piece
    end
    if #out > 0 and out[#out] == "" then out[#out] = nil end
    return unpack(out)
  end
  G.strtrim = function(s, chars)
    chars = chars or " \t\r\n"
    local p = "[" .. chars:gsub("(%W)", "%%%1") .. "]"
    return (tostring(s):gsub("^" .. p .. "+", ""):gsub(p .. "+$", ""))
  end
  G.tinsert, G.tremove, G.sort, G.tconcat = table.insert, table.remove, table.sort, table.concat
  G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  G.abs, G.ceil, G.floor, G.max, G.min, G.sqrt = math.abs, math.ceil, math.floor, math.max, math.min, math.sqrt
  G.random, G.fastrandom = math.random, math.random
  G.mod, G.fmod = math.fmod, math.fmod
  G.exp, G.log, G.log10, G.PI = math.exp, math.log, math.log10, math.pi
  -- WoW's global cos/sin/tan take DEGREES, unlike math.cos and friends.
  G.cos = function(d) return math.cos(math.rad(d)) end
  G.sin = function(d) return math.sin(math.rad(d)) end
  G.tan = function(d) return math.tan(math.rad(d)) end
  G.acos = function(v) return math.deg(math.acos(v)) end
  G.asin = function(v) return math.deg(math.asin(v)) end
  G.atan = function(v) return math.deg(math.atan(v)) end
  G.atan2 = function(y, x) return math.deg(math.atan2(y, x)) end
  G.rad, G.deg = math.rad, math.deg
  G.IsMouseButtonDown = function() return false end
  G.IsShiftKeyDown = function() return false end
  G.IsControlKeyDown = function() return false end
  G.IsAltKeyDown = function() return false end
  G.IsModifierKeyDown = function() return false end
  G.date, G.time, G.difftime = os.date, os.time, os.difftime
  -- WoW ships LuaBitOp as `bit`, and LuaJIT has it built in, but stock Lua 5.1 does not.
  -- The harness has to run under a real 5.1 (LuaJIT rejects escape sequences that 5.1
  -- accepts), so fall back to a pure-Lua implementation. Results are normalised to
  -- signed 32-bit, the way LuaBitOp returns them.
  local okBit, bitlib = pcall(require, "bit")
  if not okBit then
    local function norm(x) return math.floor(x) % 4294967296 end
    local function signed(x)
      if x >= 2147483648 then return x - 4294967296 end
      return x
    end
    local function fold(op)
      return function(a, ...)
        local r = norm(a)
        for i = 1, select("#", ...) do
          local x, y, acc, v = r, norm((select(i, ...))), 0, 1
          for _ = 1, 32 do
            local xb, yb = x % 2, y % 2
            if op(xb, yb) == 1 then acc = acc + v end
            x, y, v = (x - xb) / 2, (y - yb) / 2, v * 2
          end
          r = acc
        end
        return signed(r)
      end
    end
    bitlib = {
      band = fold(function(x, y) return (x == 1 and y == 1) and 1 or 0 end),
      bor  = fold(function(x, y) return (x == 1 or  y == 1) and 1 or 0 end),
      bxor = fold(function(x, y) return (x ~= y) and 1 or 0 end),
      bnot = function(a) return signed(norm(-norm(a) - 1)) end,
      lshift  = function(a, n) return signed(norm(norm(a) * 2 ^ (n % 32))) end,
      rshift  = function(a, n) return signed(math.floor(norm(a) / 2 ^ (n % 32))) end,
      arshift = function(a, n)
        n = n % 32
        local x = norm(a)
        if x >= 2147483648 then
          return signed(norm(math.floor(x / 2 ^ n) + (4294967296 - 2 ^ (32 - n))))
        end
        return signed(math.floor(x / 2 ^ n))
      end,
      tobit = function(a) return signed(norm(a)) end,
      tohex = function(a) return ("%08x"):format(norm(a)) end,
    }
  end
  G.bit = bitlib

  -- Client identity. Real values, so version branches take the retail path.
  G.GetLocale = function() return "enUS" end
  G.GetBuildInfo = function() return "12.1.0", "69000", "22 Aug 2026", 120100, 120100, "12.1.0" end
  G.GetRealmName = function() return "TestRealm" end
  G.GetNormalizedRealmName = function() return "TestRealm" end
  G.UnitName = function(unit) return (unit == "player") and "Tester" or "Unit", "TestRealm" end
  G.UnitFullName = function() return "Tester", "TestRealm" end
  G.UnitGUID = function() return "Player-1-00000001" end
  G.UnitLevel = function() return 80 end
  G.UnitClass = function() return "Monk", "MONK", 10 end
  G.UnitRace = function() return "Pandaren", "Pandaren", 24 end
  G.UnitFactionGroup = function() return "Alliance", "Alliance" end
  G.UnitSex = function() return 2 end
  G.UnitIsUnit = function(a, b) return a == b end
  G.UnitExists = function() return false end
  G.UnitInRaid = function() return nil end
  G.UnitInParty = function() return nil end
  G.UnitIsGroupLeader = function() return false end
  G.UnitIsGroupAssistant = function() return false end
  G.UnitGroupRolesAssigned = function() return "NONE" end
  G.UnitAffectingCombat = function() return false end
  G.InCombatLockdown = function() return false end
  G.IsInRaid = function() return false end
  G.IsInGroup = function() return false end
  G.IsInInstance = function() return false, "none" end
  G.IsInGuild = function() return true end
  G.GetNumGroupMembers = function() return 0 end
  G.GetNumSubgroupMembers = function() return 0 end
  G.GetRaidRosterInfo = function() return nil end
  G.GetNumGuildMembers = function() return 0, 0, 0 end
  G.GetGuildRosterInfo = function() return nil end
  G.GetGuildInfo = function() return "TestGuild", "Member", 1 end
  G.GetTime = function() return 1000.0 end
  G.GetServerTime = function() return os.time() end
  G.IsEncounterInProgress = function() return false end
  G.GetInstanceInfo = function() return "None", "none", 0, "", 0, 0, false, 0, 0 end
  G.GetAddOnMetadata = function() return nil end
  G.GetCursorPosition = function() return 0, 0 end
  G.GetScreenWidth = function() return 1920 end
  G.GetScreenHeight = function() return 1080 end
  -- Anything whose return feeds a numeric for-loop or arithmetic must return a real
  -- number here, or the universal stub surfaces as a bogus 'arithmetic on a table'.

  G.CreateFrame = M.CreateFrame
  G.UIParent = M.CreateFrame("Frame", "UIParent")
  G.WorldFrame = M.CreateFrame("Frame", "WorldFrame")
  G.GameTooltip = M.CreateFrame("GameTooltip", "GameTooltip")
  G.UIErrorsFrame = M.CreateFrame("Frame", "UIErrorsFrame")
  G.DEFAULT_CHAT_FRAME = M.CreateFrame("Frame", "DEFAULT_CHAT_FRAME")
  G.UISpecialFrames = {}
  G.SlashCmdList = M.slash
  G.StaticPopupDialogs = {}

  G.hooksecurefunc = function(a, b, c)
    local tbl, name, fn
    if type(a) == "table" then tbl, name, fn = a, b, c else tbl, name, fn = G, a, b end
    local orig = tbl[name]
    if type(orig) ~= "function" then
      -- Unknown or stubbed target: register the hook as a no-op rather than erroring.
      tbl[name] = fn
      return
    end
    tbl[name] = function(...) local r = { orig(...) } fn(...) return unpack(r) end
  end
  G.geterrorhandler = function() return function(err) error(err, 0) end end
  G.seterrorhandler = function() end
  G.securecall = function(fn, ...) if type(fn) == "function" then return fn(...) end end
  G.issecurevariable = function() return true end
  G.issecure = function() return true end
  G.forceinsecure = function() end
  G.scrub = function(...) return ... end
  G.Mixin = function(obj, ...)
    for i = 1, select("#", ...) do
      local mixin = select(i, ...)
      if type(mixin) == "table" then for k, v in pairs(mixin) do obj[k] = v end end
    end
    return obj
  end
  G.CreateFromMixins = function(...) return G.Mixin({}, ...) end
  G.CopyTable = function(t)
    local out = {}
    for k, v in pairs(t) do out[k] = (type(v) == "table") and G.CopyTable(v) or v end
    return out
  end
  G.tContains = function(t, item)
    for _, v in ipairs(t) do if v == item then return true end end
    return false
  end
  G.tIndexOf = function(t, item)
    for i, v in ipairs(t) do if v == item then return i end end
  end
  G.tDeleteItem = function(t, item)
    for i = #t, 1, -1 do if t[i] == item then table.remove(t, i) end end
  end
  G.Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
  G.Round = function(v) return math.floor(v + 0.5) end
  G.Saturate = function(v) return G.Clamp(v, 0, 1) end
  G.Lerp = function(a, b, t) return a + (b - a) * t end
  G.TableIsEmpty = function(t) return next(t) == nil end


  --[[
    A controllable raid.

    M.setRaid replaces the roster; the raid API below reads from it. SetRaidSubgroup
    and SwapRaidSubgroup reproduce the behaviour that makes applying a layout hard:
    the real calls FAIL SILENTLY when the destination subgroup already holds five
    players. A stub that simply moves people would let a broken move ordering pass.
  ]]
  M.raid = { members = {}, inRaid = false }
  M.raidCalls = {}

  function M.setRaid(list)
    M.raid.members = {}
    for i, m in ipairs(list or {}) do
      M.raid.members[i] = {
        name = m.name, subgroup = m.subgroup or 1,
        role = m.role or "NONE", class = m.class or "MONK",
      }
    end
    M.raid.inRaid = #M.raid.members > 0
    if M.raid.lead == nil then M.raid.lead = true end
    M.raidCalls = {}
  end

  function M.raidLayout()
    local out = {}
    for _, m in ipairs(M.raid.members) do out[m.name] = m.subgroup end
    return out
  end

  local function subgroupCount(g)
    local n = 0
    for _, m in ipairs(M.raid.members) do if m.subgroup == g then n = n + 1 end end
    return n
  end
  M.subgroupCount = subgroupCount

  M.raid.lead = true
  G.UnitIsGroupLeader = function() return M.raid.lead end
  G.UnitIsGroupAssistant = function() return M.raid.lead end
  G.IsInRaid = function() return M.raid.inRaid end
  G.IsInGroup = function() return M.raid.inRaid end
  G.GetNumGroupMembers = function() return #M.raid.members end
  G.GetRaidRosterInfo = function(i)
    local m = M.raid.members[i]
    if not m then return nil end
    -- name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole
    return m.name, 0, m.subgroup, 80, "Monk", m.class, "Zone", true, false, nil, false, m.role
  end
  G.UnitGroupRolesAssigned = function(name)
    for _, m in ipairs(M.raid.members) do if m.name == name then return m.role end end
    return "NONE"
  end
  G.SetRaidSubgroup = function(index, group)
    M.raidCalls[#M.raidCalls + 1] = { kind = "set", index = index, group = group }
    local m = M.raid.members[index]
    if not m then return end
    if m.subgroup == group then return end
    if subgroupCount(group) >= 5 then return end   -- the silent failure
    m.subgroup = group
  end
  G.SwapRaidSubgroup = function(a, b)
    M.raidCalls[#M.raidCalls + 1] = { kind = "swap", a = a, b = b }
    local ma, mb = M.raid.members[a], M.raid.members[b]
    if not ma or not mb then return end
    ma.subgroup, mb.subgroup = mb.subgroup, ma.subgroup
  end

  --[[
    Blizzard's damage meter. Empty by default; M.setMeter installs sessions.

    Enum.DamageMeterType is spelled out rather than stubbed so that a typo in a metric
    name reads as nil here exactly as it would in game, instead of resolving to a
    universal stub and quietly returning data.
  ]]
  G.Enum = G.Enum or {}
  G.Enum.DamageMeterType = {
    Dps = 1, Hps = 2, DamageDone = 3, HealingDone = 4, Absorbs = 5,
    Interrupts = 6, Dispels = 7, DamageTaken = 8, AvoidableDamageTaken = 9,
    Deaths = 10, EnemyDamageTaken = 11,
  }

  M.meter = { sessions = {}, data = {}, available = true }

  --- sessions: { { id, duration, name, dps = { {name, class, rate} }, hps = { ... } } }
  function M.setMeter(sessions, available)
    M.meter.sessions, M.meter.data = {}, {}
    M.meter.available = available ~= false
    for _, s in ipairs(sessions or {}) do
      M.meter.sessions[#M.meter.sessions + 1] =
        { sessionID = s.id, durationSeconds = s.duration, name = s.name }
      local function sources(list)
        local out = {}
        for _, src in ipairs(list or {}) do
          out[#out + 1] = {
            name = src.name, classFilename = src.class, sourceGUID = "G-" .. tostring(src.name),
            amountPerSecond = src.rate,
            totalAmount = src.total or (src.rate and src.rate * (s.duration or 1)),
          }
        end
        return out
      end
      M.meter.data[s.id] = {
        [1] = { durationSeconds = s.duration, combatSources = sources(s.dps) },
        [2] = { durationSeconds = s.duration, combatSources = sources(s.hps) },
      }
    end
  end

  G.C_DamageMeter = {
    IsDamageMeterAvailable = function() return M.meter.available end,
    GetAvailableCombatSessions = function() return M.meter.sessions end,
    GetCombatSessionFromID = function(id, mt)
      local d = M.meter.data[id]
      return d and d[mt] or nil
    end,
    ResetAllCombatSessions = function() M.setMeter({}) end,
  }

  G.C_Timer = {
    After = function(delay, fn) return schedule(delay, fn, false) end,
    NewTimer = function(delay, fn) return schedule(delay, fn, true) end,
    NewTicker = function(delay, fn) return schedule(delay, fn, true) end,
  }
  G.C_ChatInfo = {
    SendAddonMessage = function() return true end,
    SendAddonMessageLogged = function() return true end,
    RegisterAddonMessagePrefix = function() return true end,
    IsAddonMessagePrefixRegistered = function() return true end,
  }
  G.C_AddOns = {
    GetAddOnMetadata = function() return nil end,
    IsAddOnLoaded = function() return false end,
    GetNumAddOns = function() return 0 end,
    LoadAddOn = function() return false end,
    EnableAddOn = function() end,
    GetAddOnInfo = function() return nil end,
  }
  G.C_DateAndTime = {
    GetCurrentCalendarTime = function()
      local t = os.date("*t")
      return { year = t.year, month = t.month, monthDay = t.day, weekday = t.wday, hour = t.hour, minute = t.min }
    end,
    GetTodaysDate = function()
      local t = os.date("*t")
      return { year = t.year, month = t.month, monthDay = t.day, weekday = t.wday, hour = t.hour, minute = t.min }
    end,
    GetServerTimeLocal = function() return os.time() end,
  }

  --[[
    Globals the addon or its libraries define themselves must read as nil until
    they do, or bootstrap code like LibStub's "if not LibStub or LibStub.minor < 2"
    compares a stub against a number. Saved variables are added by the harness.
  ]]
  for _, name in ipairs({
    "LibStub",
    "BackdropTemplateMixin", "WeakAurasSaved", "BigWigs", "DBM",
  }) do
    M.nilGlobals[name] = true
  end

  -- Anything else resolves to a universal stub, and the access is recorded.
  setmetatable(G, {
    __index = function(_, k)
      if type(k) ~= "string" then return nil end
      if M.nilGlobals[k] then return nil end
      M.unknownGlobals[k] = (M.unknownGlobals[k] or 0) + 1
      local s = newStub(k)
      rawset(G, k, s)
      return s
    end,
  })
end

return M
