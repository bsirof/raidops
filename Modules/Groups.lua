--[[
	Groups - stub.

	Intent: named raid group layouts, apply to the current raid, import and export
	as text.

	Relevant API, confirmed against 12.1:
	  SetRaidSubgroup, SwapRaidSubgroup, GetRaidRosterInfo, GetNumGroupMembers
	Both subgroup calls silently fail out of combat if the target slot is full, so
	apply is a solve-then-sequence problem rather than a straight loop. That is the
	one genuinely hard part of this module and is worth designing before coding.
]]

local ADDON, ns = ...
local RO = ns.RO
local UI = RO.UI

local module = RO:NewModule("Groups", {
	layouts  = {},        -- name -> { [playerName] = subgroup }
	selected = nil,
})
module.title = "Raid Groups"

function module.events.GROUP_ROSTER_UPDATE(self)
	-- TODO: refresh the roster view when the config window is open
end

function module:BuildOptions(pane)
	local t = UI:Text(pane, "Raid group layouts", 13)
	t:SetPoint("TOPLEFT", 16, -16)
	local hint = UI:Text(pane, "Not built yet. Design note: applying a layout needs a\n" ..
		"move ordering that never targets a full subgroup.", 12, UI.colors.dim)
	hint:SetPoint("TOPLEFT", 16, -40)
end
