--[[
	Invites - stub.

	Intent: keyword invites from whisper, mass guild invite, disband and reinvite.
	Nothing is implemented yet; this file exists so the shape is settled.

	Relevant API, confirmed against 12.1:
	  C_PartyInfo.InviteUnit, C_PartyInfo.ConvertToRaid, UninviteUnit
	  CHAT_MSG_WHISPER, CHAT_MSG_BN_WHISPER, GROUP_ROSTER_UPDATE
	  C_GuildInfo.GuildRoster + GetGuildRosterInfo for the guild list
	Blizzard throttles invites; batch them rather than looping in one frame.
]]

local ADDON, ns = ...
local RO = ns.RO
local UI = RO.UI

local module = RO:NewModule("Invites", {
	keywords    = "inv invite 123",
	guildOnly   = true,
	fromWhisper = true,
})
module.title = "Invites"

function module:OnEnable()
	self:Debug("ready, keywords:", self.db.keywords)
end

function module.events.CHAT_MSG_WHISPER(self, text, sender)
	if not self.db.fromWhisper then return end
	-- TODO: match text against self.db.keywords, honour guildOnly, then invite
	self:Debug("whisper from", sender, "->", text)
end

function module:BuildOptions(pane)
	local y = -16
	local kw = UI:Text(pane, "Invite keywords", 12); kw:SetPoint("TOPLEFT", 16, y)
	y = y - 20
	local edit = UI:Edit(pane, 300, self.db.keywords, function(text) self.db.keywords = text end)
	edit:SetPoint("TOPLEFT", 16, y)
	y = y - 34
	local c1 = UI:Check(pane, "Invite on whisper keyword", self.db.fromWhisper,
		function(v) self.db.fromWhisper = v end)
	c1:SetPoint("TOPLEFT", 16, y)
	y = y - 26
	local c2 = UI:Check(pane, "Guild members only", self.db.guildOnly,
		function(v) self.db.guildOnly = v end)
	c2:SetPoint("TOPLEFT", 16, y)
end
