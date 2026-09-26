--[[
	Groups - split a raid into balanced sides.

	Two problems live here, and they are kept apart on purpose.

	  1. WHO goes where. A pure function, module.Balance, that takes a roster and a way
	     to score people and returns a name -> subgroup assignment. No frames, no API
	     calls, so it can be tested directly against known numbers.

	  2. HOW to get them there. SetRaidSubgroup and SwapRaidSubgroup both fail silently
	     when the destination subgroup is full, so applying a layout is a move-ordering
	     problem rather than a loop. module.PlanMoves solves it; module:Apply executes
	     the plan. Also pure, also directly testable.

	Balancing method, per role bucket:
	  - score every player, healers on HPS and everyone else on DPS
	  - players the meter never saw are slotted at their role's median and named in
	    chat, so a raider who was not in the data is obvious rather than quietly sorted
	    to the bottom
	  - sort the bucket descending and hand each player to the side holding the fewest
	    of that role, breaking ties on the lower running total

	Fewest-first before lowest-total is deliberate. A pure lowest-total greedy will put
	three healers on one side and one on the other as long as the sums match. Count
	first guarantees even role counts; the total only decides between sides that are
	already level. That is the longest-processing-time heuristic, and on a raid-sized
	list it lands within a few percent of an optimal partition.

	With no fight data at all every score is zero, the tie-break never fires, and the
	result is a plain even-counts split. Worse than a balanced one, better than random,
	and it needs no separate code path.
]]

local ADDON, ns = ...
local RO = ns.RO
local UI = RO.UI

local GROUP_MAX  = 5
local RAID_GROUPS = 8
local ROLES = { "TANK", "HEALER", "DAMAGER" }

local module = RO:NewModule("Groups", {
	parts   = 2,       -- how many sides to split into
	byPerf  = true,    -- balance on recorded throughput
	stagger = 0.15,    -- seconds between subgroup calls when applying
})
module.title = "Raid Groups"

--------------------------------------------------------------------- balance

local function median(values)
	local n = #values
	if n == 0 then return nil end
	table.sort(values)
	if n % 2 == 1 then return values[(n + 1) / 2] end
	return (values[n / 2] + values[n / 2 + 1]) / 2
end
module.Median = median

--[[
	roster        array of { name = , role = , class = }
	parts         how many sides
	groupsPerSide how many subgroups each side owns
	scoreFor      function(name, role) -> number or nil. Injected rather than reaching
	              for the Perf module, so the maths can be tested without it.

	Returns assignment (name -> subgroup) and a report.
]]
function module.Balance(roster, parts, groupsPerSide, scoreFor)
	assert(parts >= 1 and groupsPerSide >= 1, "bad split geometry")
	if parts * groupsPerSide > RAID_GROUPS then
		return nil, ("%d sides of %d groups needs %d subgroups, a raid has %d")
			:format(parts, groupsPerSide, parts * groupsPerSide, RAID_GROUPS)
	end
	local capacity = groupsPerSide * GROUP_MAX
	if #roster > parts * capacity then
		return nil, ("%d players will not fit in %d sides of %d"):format(#roster, parts, capacity)
	end

	local buckets = {}
	for _, role in ipairs(ROLES) do buckets[role] = {} end
	for _, p in ipairs(roster) do
		--> Anyone without an assigned role is balanced as damage rather than left out.
		local bucket = buckets[p.role] and p.role or "DAMAGER"
		p.bucket = bucket
		table.insert(buckets[bucket], p)
	end

	local estimated, scored = {}, 0
	for _, role in ipairs(ROLES) do
		local list, known = buckets[role], {}
		for _, p in ipairs(list) do
			local s = scoreFor and scoreFor(p.name, role) or nil
			p.score, p.measured = s, s ~= nil
			if s then known[#known + 1] = s; scored = scored + 1 end
		end
		local mid = median(known)
		for _, p in ipairs(list) do
			if not p.score then
				p.score = mid or 0
				estimated[#estimated + 1] = p.name
			end
		end
		table.sort(list, function(a, b)
			if a.score == b.score then return a.name < b.name end
			return a.score > b.score
		end)
	end

	local sides = {}
	for i = 1, parts do
		sides[i] = { members = {}, count = {}, total = {}, measured = {} }
		for _, role in ipairs(ROLES) do
			sides[i].count[role], sides[i].total[role], sides[i].measured[role] = 0, 0, 0
		end
	end

	for _, role in ipairs(ROLES) do
		for _, p in ipairs(buckets[role]) do
			local best
			for i = 1, parts do
				local side = sides[i]
				if #side.members < capacity then
					if not best
						or side.count[role] < best.count[role]
						or (side.count[role] == best.count[role] and side.total[role] < best.total[role]) then
						best = side
					end
				end
			end
			if not best then return nil, "ran out of room mid-assignment" end
			best.count[role] = best.count[role] + 1
			best.total[role] = best.total[role] + p.score
			if p.measured then best.measured[role] = best.measured[role] + p.score end
			best.members[#best.members + 1] = p
		end
	end

	--> Tanks were placed first, then healers, then damage, so each side's list is
	--> already in that order and drops straight into its subgroups.
	local assign = {}
	for i = 1, parts do
		for n, p in ipairs(sides[i].members) do
			assign[p.name] = (i - 1) * groupsPerSide + math.floor((n - 1) / GROUP_MAX) + 1
		end
	end

	return assign, {
		sides = sides, estimated = estimated, scored = scored,
		parts = parts, groupsPerSide = groupsPerSide,
	}
end

--------------------------------------------------------------- move ordering

--[[
	Turn a current layout into a target one.

	current, target: name -> subgroup. Target must name every player in current.

	The hard case is a full destination. When it happens, some occupant of that group
	does not belong there: at most GROUP_MAX players want the group in the target, and
	one of them is standing outside it, so at most GROUP_MAX-1 of the occupants are
	correct. Swapping with that misplaced occupant always fixes at least one player and
	never changes any group's headcount, which is why this terminates.

	Returns a list of { kind = "set", name, group } / { kind = "swap", a, b }, or nil
	plus a reason.
]]
function module.PlanMoves(current, target)
	local cur, occupants, size = {}, {}, 0
	for name, g in pairs(current) do
		cur[name] = g
		occupants[g] = (occupants[g] or 0) + 1
		size = size + 1
	end

	local wanted = {}
	local misplaced, nMis = {}, 0
	for name, want in pairs(target) do
		if cur[name] == nil then return nil, ("%s is not in the raid"):format(tostring(name)) end
		wanted[want] = (wanted[want] or 0) + 1
		if wanted[want] > GROUP_MAX then
			return nil, ("target puts %d players in group %d"):format(wanted[want], want)
		end
		if cur[name] ~= want then misplaced[name] = true; nMis = nMis + 1 end
	end

	local moves, guard = {}, 0
	while nMis > 0 do
		guard = guard + 1
		--> Each iteration fixes at least one player, so this bound is unreachable in
		--> practice. It is here so a future change cannot turn a bug into a hang.
		if guard > size * 2 + 16 then return nil, "no move ordering found" end

		local moved = false
		for name in pairs(misplaced) do
			local want = target[name]
			if (occupants[want] or 0) < GROUP_MAX then
				occupants[cur[name]] = occupants[cur[name]] - 1
				occupants[want] = (occupants[want] or 0) + 1
				cur[name] = want
				misplaced[name] = nil
				nMis = nMis - 1
				moves[#moves + 1] = { kind = "set", name = name, group = want }
				moved = true
				break   -- occupancy changed, restart the scan
			end
		end
		if not moved then
			local a = next(misplaced)
			local want, b = target[a], nil
			for name, g in pairs(cur) do
				if g == want and misplaced[name] then b = name break end
			end
			if not b then
				return nil, ("group %d is full of players who belong there"):format(want)
			end
			cur[a], cur[b] = cur[b], cur[a]
			moves[#moves + 1] = { kind = "swap", a = a, b = b }
			if cur[a] == target[a] then misplaced[a] = nil; nMis = nMis - 1 end
			if cur[b] == target[b] then misplaced[b] = nil; nMis = nMis - 1 end
		end
	end
	return moves
end

--------------------------------------------------------------------- roster

function module:ReadRaid()
	if not IsInRaid() then return nil, "not in a raid" end
	local n = GetNumGroupMembers() or 0
	if n == 0 then return nil, "raid is empty" end

	local roster, current, index = {}, {}, {}
	for i = 1, n do
		--> combatRole is the 12th return and is the tank/healer/damage one. The 10th
		--> is main tank / main assist, which is a different thing entirely.
		local name, _, subgroup, _, _, class, _, _, _, _, _, combatRole = GetRaidRosterInfo(i)
		if name and subgroup then
			local role = combatRole
			if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then
				role = UnitGroupRolesAssigned(name)
			end
			roster[#roster + 1] = { name = name, role = role or "NONE", class = class, subgroup = subgroup }
			current[name] = subgroup
			index[name] = i
		end
	end
	if #roster == 0 then return nil, "could not read the raid roster" end
	return roster, current, index
end

--------------------------------------------------------------------- planning

function module:GroupsPerSide(count, parts)
	return math.ceil(count / parts / GROUP_MAX)
end

--- Build a plan without touching the raid. Returns plan, or nil plus a reason.
function module:BuildPlan(parts)
	parts = parts or self.db.parts
	local roster, current = self:ReadRaid()
	if not roster then return nil, current end

	local perf = RO:GetModule("Perf")
	local usePerf = self.db.byPerf and perf ~= nil
	local scoreFor
	if usePerf then
		scoreFor = function(name, role)
			local dps, hps = perf:Get(name)
			--> Score on the role's own metric, but fall back to the other rather than
			--> calling the player unknown. A healer who shows up only in the damage
			--> table still tells us more than a median guess does.
			if role == "HEALER" then return hps or dps end
			return dps or hps
		end
	end

	local groupsPerSide = self:GroupsPerSide(#roster, parts)
	local assign, report = module.Balance(roster, parts, groupsPerSide, scoreFor)
	if not assign then return nil, report end

	local moves, why = module.PlanMoves(current, assign)
	if not moves then return nil, why end

	report.assign, report.moves, report.current = assign, moves, current
	report.usePerf = usePerf
	report.roster = roster
	return report
end

--------------------------------------------------------------------- applying

--[[
	Execute a plan. Names are resolved to raid indices immediately before each call
	rather than captured up front: the raid index is the roster slot, and a disconnect
	or a leaver between planning and applying would otherwise move the wrong person.
	A move whose player has gone is skipped and reported, not guessed at.
]]
function module:Apply(plan)
	if InCombatLockdown() then return nil, "cannot change subgroups in combat" end
	if not IsInRaid() then return nil, "not in a raid" end
	--> Both subgroup calls need lead or assist and, like every other failure mode
	--> here, say nothing when they do not have it. Without this check the read-back
	--> would report every player in the wrong group and give no reason why.
	if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
		return nil, "you need raid lead or assist to move people"
	end
	if not plan or not plan.moves then return nil, "no plan to apply" end
	if #plan.moves == 0 then return 0, 0 end

	local done, skipped, i = 0, 0, 0
	local stagger = self.db.stagger or 0.15

	local function indexOf(name)
		local _, _, index = self:ReadRaid()
		return index and index[name]
	end

	local function step()
		i = i + 1
		local m = plan.moves[i]
		if not m then
			RO:Print(("applied %d move%s%s"):format(done, done == 1 and "" or "s",
				skipped > 0 and (", skipped " .. skipped) or ""))
			self:Verify(plan)
			return
		end
		local ok = true
		if m.kind == "set" then
			local idx = indexOf(m.name)
			if idx then SetRaidSubgroup(idx, m.group) else ok = false end
		else
			local a, b = indexOf(m.a), indexOf(m.b)
			if a and b then SwapRaidSubgroup(a, b) else ok = false end
		end
		if ok then done = done + 1 else skipped = skipped + 1 end
		C_Timer.After(stagger, step)
	end

	step()
	return #plan.moves
end

--[[
	Read the raid back and say whether it matches the plan.

	This exists because both subgroup calls fail silently. Without a read-back, a plan
	that half applied looks exactly like one that worked.
]]
function module:Verify(plan)
	local roster, current = self:ReadRaid()
	if not roster then return nil, current end
	local wrong = {}
	for name, want in pairs(plan.assign) do
		if current[name] and current[name] ~= want then
			wrong[#wrong + 1] = ("%s is in %d, wanted %d"):format(name, current[name], want)
		end
	end
	if #wrong == 0 then
		RO:Print("|cff44ff44raid matches the plan|r")
		return true
	end
	RO:Print(("|cffff4444%d player%s did not end up in the right group|r"):format(
		#wrong, #wrong == 1 and "" or "s"))
	for _, line in ipairs(wrong) do print("   " .. line) end
	return false
end

--------------------------------------------------------------------- reporting

function module:PrintPlan(plan)
	local perf = RO:GetModule("Perf")
	local fmt = perf and perf.FormatRate or tostring

	RO:Print(("%d-way split, %d group%s per side%s"):format(
		plan.parts, plan.groupsPerSide, plan.groupsPerSide == 1 and "" or "s",
		plan.usePerf and "" or "  |cffffff00(performance balancing off)|r"))

	for i, side in ipairs(plan.sides) do
		print(("  |cff30c8ffSide %d|r  %d players   %d tank, %d heal %s hps, %d dps %s dps")
			:format(i, #side.members, side.count.TANK,
				side.count.HEALER, fmt(side.total.HEALER),
				side.count.DAMAGER, fmt(side.total.DAMAGER)))
		local names = {}
		for _, p in ipairs(side.members) do
			names[#names + 1] = p.measured and p.name or (p.name .. "*")
		end
		print("     " .. table.concat(names, ", "))
	end

	if #plan.estimated > 0 then
		print(("  |cffffff00* no fight data (%d):|r %s  - placed at their role median")
			:format(#plan.estimated, table.concat(plan.estimated, ", ")))
	end
	if plan.scored == 0 then
		print("  |cffffff00Nothing has been recorded yet, so this is an even-counts split only.|r")
		print("  |cff55596aRun /roa perf to check the meter.|r")
	end
	print(("  %d move%s needed. |cff30c8ff/roa split apply|r to run it.")
		:format(#plan.moves, #plan.moves == 1 and "" or "s"))
end

--------------------------------------------------------------------- commands

RO:RegisterCommand("split", "preview a balanced split: split [2-4] | split apply", function(rest)
	local m = RO:GetModule("Groups")
	local arg = (rest or ""):lower():match("^%s*(%S*)")

	if arg == "apply" then
		if not m.plan then RO:Print("nothing planned - run /roa split first") return end
		local n, why = m:Apply(m.plan)
		if not n then RO:Print("cannot apply:", why) end
		return
	end

	local parts = tonumber(arg)
	if parts then
		if parts < 2 or parts > 4 then RO:Print("split into 2, 3 or 4") return end
		m.db.parts = parts
	end

	local plan, why = m:BuildPlan()
	if not plan then RO:Print("cannot plan a split:", why) return end
	m.plan = plan
	m:PrintPlan(plan)
end)

--------------------------------------------------------------------- events

function module.events.GROUP_ROSTER_UPDATE(self)
	--> A plan is only valid for the roster it was built from.
	self.plan = nil
end

--------------------------------------------------------------------- options

function module:BuildOptions(pane)
	local t = UI:Text(pane, "Raid group split", 13)
	t:SetPoint("TOPLEFT", 16, -16)

	local perfCheck = UI:Check(pane, "Balance by recorded DPS and HPS", self.db.byPerf,
		function(v) self.db.byPerf = v and true or false end)
	perfCheck:SetPoint("TOPLEFT", 16, -44)

	local partsLabel = UI:Text(pane, "Sides:", 12, UI.colors.dim)
	partsLabel:SetPoint("TOPLEFT", 16, -76)

	local buttons = {}
	for i = 2, 4 do
		local b = UI:Button(pane, tostring(i), 28, 20)
		b:SetPoint("TOPLEFT", 60 + (i - 2) * 32, -74)
		b:SetScript("OnClick", function()
			self.db.parts = i
			for n, other in pairs(buttons) do
				other.label:SetTextColor(unpack(n == i and UI.colors.accent or UI.colors.dim))
			end
		end)
		b.label:SetTextColor(unpack(i == self.db.parts and UI.colors.accent or UI.colors.dim))
		buttons[i] = b
	end

	local body = UI:Text(pane, "", 12)
	body:SetPoint("TOPLEFT", 16, -110)
	body:SetPoint("TOPRIGHT", -16, -110)
	body:SetJustifyH("LEFT")

	local applyBtn
	local function preview()
		local plan, why = self:BuildPlan()
		self.plan = plan
		if not plan then
			body:SetText("Cannot plan a split: " .. tostring(why))
			applyBtn:Hide()
			return
		end
		local perf = RO:GetModule("Perf")
		local fmt = perf and perf.FormatRate or tostring
		local lines = {}
		for i, side in ipairs(plan.sides) do
			lines[#lines + 1] = ("Side %d  %d players  %dT %dH (%s hps) %dD (%s dps)")
				:format(i, #side.members, side.count.TANK, side.count.HEALER,
					fmt(side.total.HEALER), side.count.DAMAGER, fmt(side.total.DAMAGER))
			local names = {}
			for _, p in ipairs(side.members) do
				names[#names + 1] = p.measured and p.name or (p.name .. "*")
			end
			lines[#lines + 1] = "   " .. table.concat(names, ", ")
		end
		if #plan.estimated > 0 then
			lines[#lines + 1] = ("* no fight data: %s"):format(table.concat(plan.estimated, ", "))
		end
		lines[#lines + 1] = ("%d move%s needed"):format(#plan.moves, #plan.moves == 1 and "" or "s")
		body:SetText(table.concat(lines, "\n"))
		applyBtn:SetShown(#plan.moves > 0)
	end

	local previewBtn = UI:Button(pane, "Preview split", 110, 22)
	previewBtn:SetPoint("TOPRIGHT", -16, -14)
	previewBtn:SetScript("OnClick", preview)

	applyBtn = UI:Button(pane, "Apply", 80, 22)
	applyBtn:SetPoint("RIGHT", previewBtn, "LEFT", -6, 0)
	applyBtn:Hide()
	applyBtn:SetScript("OnClick", function()
		if not self.plan then return end
		local n, why = self:Apply(self.plan)
		if not n then RO:Print("cannot apply:", why) end
	end)

	body:SetText("Press Preview to see how the current raid would be split.\n" ..
		"Nothing moves until you press Apply.")
end
