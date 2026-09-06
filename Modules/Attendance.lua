--[[
	Attendance - stub.

	Intent: snapshot the raid roster on pull and on kill, keep history, export as text.

	Relevant API, confirmed against 12.1:
	  ENCOUNTER_START, ENCOUNTER_END, GetRaidRosterInfo, C_DateAndTime
	Note the previous build synced encounter events over an addon channel so that
	raiders whose client missed the event still logged. That is optional; local capture
	covers nearly everything.
]]

local ADDON, ns = ...
local RO = ns.RO
local UI = RO.UI

local module = RO:NewModule("Attendance", {
	mode    = "kill",   -- kill | pull | both
	history = {},       -- { time, encounter, difficulty, roster = {names} }
})
module.title = "Attendance"

function module.events.ENCOUNTER_END(self, encounterID, encounterName, difficultyID, groupSize, success)
	if self.db.mode == "kill" and success ~= 1 then return end
	-- TODO: capture the roster and append to self.db.history
	self:Debug("encounter end", encounterName, success)
end

function module:BuildOptions(pane)
	local t = UI:Text(pane, "Attendance", 13)
	t:SetPoint("TOPLEFT", 16, -16)
	local hint = UI:Text(pane, ("%d record(s) stored."):format(#self.db.history), 12, UI.colors.dim)
	hint:SetPoint("TOPLEFT", 16, -40)
end
