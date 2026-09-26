--[[
	Perf - per-player damage and healing throughput.

	Collects what Blizzard's damage meter reports at the end of each boss encounter and
	keeps a running average per player. Raid Groups uses those averages to balance a
	split; nothing else depends on this module, and it is inert without it.

	Why C_DamageMeter. Midnight closed the addon API to protected combat data and
	COMBAT_LOG_EVENT_UNFILTERED can no longer be registered at all (DESIGN.md
	constraint 2), so parsing the log is not an option even if we wanted to own that
	code. C_DamageMeter is the sanctioned replacement and is computed server-side,
	which has a property worth more than convenience: two officers running the same
	split see identical numbers.

	The shape of that API is documented but not guaranteed, and session persistence is
	not documented at all. Every read here is type-checked and every entry point is
	wrapped, so a client that returns nothing produces "no data" rather than an error.
]]

local ADDON, ns = ...
local RO = ns.RO
local UI = RO.UI

local module = RO:NewModule("Perf", {
	--> Samples older than this drop out of the average. A window rather than a reset
	--> on login, because a disconnect mid-raid must not wipe the night's data.
	windowHours  = 8,
	--> Sessions shorter than this are wipe checks and stray trash. Short fights give
	--> wildly unrepresentative rates.
	minDuration  = 20,
	--> Per player. A long night of pulls should not grow the saved variables forever.
	maxSamples   = 40,
	players      = {},    -- shortname -> { name, class, guid, d = {samples}, h = {samples} }
	seen         = {},    -- sessionID -> timestamp it was folded in
})
module.title = "Performance"

--------------------------------------------------------------------- helpers

--> Meter source names may or may not carry a realm; the raid roster usually does not.
--> The short name lowercased is the one form both sides reliably agree on.
local function shortKey(name)
	if type(name) ~= "string" or name == "" then return nil end
	return (name:match("^([^-]+)") or name):lower()
end
module.ShortKey = shortKey

local function meterType(key)
	if type(Enum) ~= "table" or type(Enum.DamageMeterType) ~= "table" then return nil end
	return Enum.DamageMeterType[key]
end

function module:WindowSeconds()
	return (self.db and self.db.windowHours or 8) * 3600
end

--- Is the meter usable right now? Returns false plus a reason when not.
function module:Available()
	if type(C_DamageMeter) ~= "table" then
		return false, "C_DamageMeter is not present on this client"
	end
	if type(C_DamageMeter.GetAvailableCombatSessions) ~= "function" then
		return false, "C_DamageMeter.GetAvailableCombatSessions is missing"
	end
	if type(C_DamageMeter.IsDamageMeterAvailable) == "function" then
		local ok, avail = pcall(C_DamageMeter.IsDamageMeterAvailable)
		if ok and avail == false then return false, "the damage meter reports itself unavailable" end
	end
	if not meterType("Dps") then return false, "Enum.DamageMeterType.Dps is missing" end
	return true
end

function module:Sessions()
	if type(C_DamageMeter) ~= "table"
		or type(C_DamageMeter.GetAvailableCombatSessions) ~= "function" then return {} end
	local ok, list = pcall(C_DamageMeter.GetAvailableCombatSessions)
	if not ok or type(list) ~= "table" then return {} end
	return list
end

--------------------------------------------------------------------- reading

--> One metric of one session, as { [shortkey] = { name, class, guid, rate, total } }.
function module:ReadMetric(sessionID, typeKey)
	local mt = meterType(typeKey)
	if not mt or type(C_DamageMeter) ~= "table"
		or type(C_DamageMeter.GetCombatSessionFromID) ~= "function" then return nil end

	local ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, mt)
	if not ok or type(session) ~= "table" or type(session.combatSources) ~= "table" then
		return nil
	end

	local result = {}
	for _, src in ipairs(session.combatSources) do
		if type(src) == "table" then
			local key = shortKey(src.name)
			--> Pets and NPCs come through the same list and carry no class. They are
			--> not raiders and must never be scored as one.
			if key and type(src.classFilename) == "string" and src.classFilename ~= "" then
				local rate = tonumber(src.amountPerSecond)
				if not rate then
					local total, dur = tonumber(src.totalAmount), tonumber(session.durationSeconds)
					if total and dur and dur > 0 then rate = total / dur end
				end
				if rate and rate > 0 then
					result[key] = {
						name  = src.name,
						class = src.classFilename,
						guid  = src.sourceGUID,
						rate  = rate,
						total = tonumber(src.totalAmount) or 0,
					}
				end
			end
		end
	end
	return result, session
end

--------------------------------------------------------------------- folding

local function addSample(entry, field, value, now, maxSamples)
	local list = entry[field]
	if not list then list = {}; entry[field] = list end
	list[#list + 1] = { v = value, t = now }
	while #list > maxSamples do table.remove(list, 1) end
end

--- Fold one session into the running averages. Returns a sample count, or nil + reason.
function module:FoldSession(sessionID, label, duration)
	local db = self.db
	if not db then return nil, "database not loaded yet" end
	if db.seen[sessionID] then return nil, "already recorded" end

	local dps = self:ReadMetric(sessionID, "Dps")
	local hps = self:ReadMetric(sessionID, "Hps")
	if not dps and not hps then return nil, "no data returned for that session" end

	local now = time()
	db.seen[sessionID] = now

	local count = 0
	local function fold(map, field)
		if not map then return end
		for key, src in pairs(map) do
			local entry = db.players[key]
			if not entry then entry = {}; db.players[key] = entry end
			entry.name, entry.class, entry.guid = src.name or entry.name, src.class or entry.class, src.guid or entry.guid
			addSample(entry, field, src.rate, now, db.maxSamples)
			count = count + 1
		end
	end
	fold(dps, "d")
	fold(hps, "h")

	db.lastLabel, db.lastDuration, db.lastFold = label, duration, now

	--> Keep the seen set from growing across nights.
	local window = self:WindowSeconds()
	for id, t in pairs(db.seen) do
		if type(t) ~= "number" or (now - t) > window then db.seen[id] = nil end
	end
	return count
end

--[[
	Pick the session that just ended.

	The order of GetAvailableCombatSessions is undocumented, so this trusts the highest
	session id rather than list position. Every other unrecorded session is marked
	consumed at the same time, so a trash pull that happened before the boss cannot be
	folded in later and counted as boss throughput.
]]
function module:CollectLatest()
	local db = self.db
	if not db then return nil, "database not loaded yet" end

	local sessions, best, bestEntry = self:Sessions(), nil, nil
	for _, s in ipairs(sessions) do
		local id = s and s.sessionID
		if type(id) == "number" and not db.seen[id] then
			if not best or id > best then best, bestEntry = id, s end
		end
	end
	if not best then return nil, "no new combat session found" end

	local now = time()
	for _, s in ipairs(sessions) do
		local id = s and s.sessionID
		if type(id) == "number" and id ~= best and not db.seen[id] then db.seen[id] = now end
	end

	local dur = tonumber(bestEntry.durationSeconds) or 0
	if dur < db.minDuration then
		db.seen[best] = now
		return nil, ("session %s ran %ds, below the %ds minimum"):format(tostring(best), dur, db.minDuration)
	end
	return self:FoldSession(best, bestEntry.name, dur)
end

--------------------------------------------------------------------- averages

local function average(list, now, window)
	if type(list) ~= "table" then return nil, 0 end
	local sum, n = 0, 0
	for _, s in ipairs(list) do
		if type(s) == "table" and type(s.v) == "number" and type(s.t) == "number"
			and (now - s.t) <= window then
			sum, n = sum + s.v, n + 1
		end
	end
	if n == 0 then return nil, 0 end
	return sum / n, n
end

--- Mean DPS, mean HPS, and the sample count behind each. Any may be nil.
function module:Get(name)
	local db = self.db
	if not db then return nil end
	local entry = db.players[shortKey(name) or ""]
	if not entry then return nil end
	local now, window = time(), self:WindowSeconds()
	local d, dn = average(entry.d, now, window)
	local h, hn = average(entry.h, now, window)
	return d, h, dn, hn
end

--- Everything known, keyed by short lowercase name. This is what Raid Groups reads.
function module:Snapshot()
	local db = self.db
	if not db then return {} end
	local now, window, snap = time(), self:WindowSeconds(), {}
	for key, entry in pairs(db.players) do
		local d, dn = average(entry.d, now, window)
		local h, hn = average(entry.h, now, window)
		if d or h then
			snap[key] = { name = entry.name, class = entry.class, dps = d, hps = h, dpsN = dn, hpsN = hn }
		end
	end
	return snap
end

function module:HasData()
	return next(self:Snapshot()) ~= nil
end

function module:Reset()
	if not self.db then return end
	wipe(self.db.players)
	wipe(self.db.seen)
	self.db.lastLabel, self.db.lastDuration, self.db.lastFold = nil, nil, nil
end

--------------------------------------------------------------------- events

function module.events.ENCOUNTER_END(self, _, encounterName)
	--> The server finalises the session a moment after the encounter ends. Reading
	--> immediately returns a truncated fight, or nothing at all.
	C_Timer.After(3, function()
		local ok, n, why = pcall(self.CollectLatest, self)
		if not ok then
			RO.moduleError("collecting fight data", n)
			return
		end
		if n then
			self.db.lastEncounter = encounterName
			self:Debug(("recorded %d samples from %s"):format(n, tostring(encounterName)))
		else
			self:Debug("nothing recorded:", why)
		end
	end)
end

--------------------------------------------------------------------- display

function module.FormatRate(v)
	if not v or v == 0 then return "0" end
	if v >= 1e6 then return ("%.2fM"):format(v / 1e6) end
	if v >= 1e3 then return ("%.0fK"):format(v / 1e3) end
	return ("%.0f"):format(v)
end
local fmt = module.FormatRate

function module:DumpApi()
	local ok, why = self:Available()
	RO:Print(("meter available: |cff%s%s|r%s"):format(
		ok and "44ff44" or "ff4444", tostring(ok), ok and "" or ("  (" .. tostring(why) .. ")")))
	if not ok then return end

	local keys = {}
	for k in pairs(Enum.DamageMeterType) do keys[#keys + 1] = k end
	table.sort(keys)
	RO:Print("Enum.DamageMeterType: " .. table.concat(keys, ", "))

	local sessions = self:Sessions()
	RO:Print(("sessions available: %d"):format(#sessions))
	local best
	for i, s in ipairs(sessions) do
		print(("  [%d] id=%s  dur=%ss  name=%s"):format(
			i, tostring(s.sessionID), tostring(s.durationSeconds), tostring(s.name)))
		if type(s.sessionID) == "number" and (not best or s.sessionID > best.sessionID) then best = s end
	end
	if not best then
		print("  Nothing recorded yet. Pull something, then run this again.")
		return
	end

	for _, metric in ipairs({ "Dps", "Hps" }) do
		local map, session = self:ReadMetric(best.sessionID, metric)
		if not map then
			RO:Print(("%s: |cffff4444no data|r (enum %s)"):format(metric, tostring(meterType(metric))))
		else
			local list = {}
			for _, src in pairs(map) do list[#list + 1] = src end
			table.sort(list, function(a, b) return a.rate > b.rate end)
			RO:Print(("%s: %d sources over %ss"):format(metric, #list,
				tostring(session and session.durationSeconds)))
			for i = 1, math.min(#list, 6) do
				local s = list[i]
				print(("   %d. %-20s %-12s %s/s"):format(i, tostring(s.name), tostring(s.class), fmt(s.rate)))
			end
			if #list > 6 then print(("   ... and %d more"):format(#list - 6)) end
		end
	end
end

function module:DumpStore()
	local snap, list = self:Snapshot(), {}
	for _, e in pairs(snap) do list[#list + 1] = e end
	table.sort(list, function(a, b) return (a.dps or a.hps or 0) > (b.dps or b.hps or 0) end)

	RO:Print(("stored: %d players, %dh window, last fight: %s"):format(
		#list, self.db.windowHours, tostring(self.db.lastEncounter or self.db.lastLabel or "none")))
	for _, e in ipairs(list) do
		print(("   %-20s %-12s dps %s (n=%d)   hps %s (n=%d)"):format(
			tostring(e.name), tostring(e.class), fmt(e.dps), e.dpsN or 0, fmt(e.hps), e.hpsN or 0))
	end
	if #list == 0 then
		print("   Nothing stored. Data is folded in when a boss encounter ends.")
	end
end

--------------------------------------------------------------------- commands

RO:RegisterCommand("perf", "fight data: perf | perf store | perf scan | perf reset", function(rest)
	local m = RO:GetModule("Perf")
	local arg = (rest or ""):lower():match("^%s*(%S*)")
	if arg == "store" then m:DumpStore()
	elseif arg == "reset" then m:Reset(); RO:Print("fight data cleared")
	elseif arg == "scan" then
		local n, why = m:CollectLatest()
		if n then RO:Print(("folded in %d samples"):format(n))
		else RO:Print("nothing folded:", why) end
	else
		m:DumpApi()
		print("  |cff55596a/roa perf store|r stored averages   |cff55596a/roa perf scan|r fold the last fight in now   |cff55596a/roa perf reset|r clear")
	end
end)

--------------------------------------------------------------------- options

function module:BuildOptions(pane)
	local t = UI:Text(pane, "Fight data", 13)
	t:SetPoint("TOPLEFT", 16, -16)

	local status = UI:Text(pane, "", 12, UI.colors.dim)
	status:SetPoint("TOPLEFT", 16, -40)
	status:SetJustifyH("LEFT")

	local body = UI:Text(pane, "", 12)
	body:SetPoint("TOPLEFT", 16, -96)
	body:SetPoint("TOPRIGHT", -16, -96)
	body:SetJustifyH("LEFT")

	local function refresh()
		local ok, why = self:Available()
		local snap, n = self:Snapshot(), 0
		local lines = {}
		for _, e in pairs(snap) do
			n = n + 1
			lines[#lines + 1] = ("%-18s  dps %-8s  hps %-8s"):format(
				tostring(e.name), fmt(e.dps), fmt(e.hps))
		end
		table.sort(lines)
		status:SetText(("Meter: %s\nRecorded: %d players over the last %d hours\nLast fight: %s")
			:format(ok and "available" or ("unavailable - " .. tostring(why)),
				n, self.db.windowHours,
				tostring(self.db.lastEncounter or self.db.lastLabel or "none")))
		body:SetText(#lines > 0 and table.concat(lines, "\n", 1, math.min(#lines, 24))
			or "Nothing recorded yet. Data is collected when a boss encounter ends.")
	end

	local refreshBtn = UI:Button(pane, "Refresh", 90, 22)
	refreshBtn:SetPoint("TOPRIGHT", -16, -14)
	refreshBtn:SetScript("OnClick", refresh)

	local clear = UI:Button(pane, "Clear data", 90, 22)
	clear:SetPoint("RIGHT", refreshBtn, "LEFT", -6, 0)
	clear:SetScript("OnClick", function() self:Reset(); refresh() end)

	pane:SetScript("OnShow", refresh)
	refresh()
end
