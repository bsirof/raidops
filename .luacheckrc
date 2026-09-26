--[[
	luacheck configuration for RaidOps Alpha.

	Two jobs: tell luacheck which globals the WoW client provides, and turn off the
	handful of warnings that are wrong for addon code rather than merely noisy. Nothing
	here suppresses a warning because it was inconvenient; each exclusion has a reason.

	Run:  luacheck .
]]

std = "lua51"
max_line_length = false

-- self is unused in a method that only reaches module-level helpers. Warning about it
-- would push the code towards dot-syntax for some methods and colon for others.
ignore = {
	"212/self",   -- unused argument self
	"212/_.*",    -- arguments deliberately named _
	"213",        -- unused loop variable, common in numeric fills
	"211/ADDON",  -- every file takes (ADDON, ns); most only want ns
	-- An OnClick or OnEnter handler is passed the widget as self, which shadows the
	-- enclosing method's self. That is how the client calls it, not a mistake.
	"431/self", "432/self",
}

-- The addon's own surface. Core assigns the first two; the rest are set by files here.
globals = {
	"RaidOpsAlpha", "RaidOpsAlphaDB",
	"SLASH_ROALPHA1", "SLASH_ROALPHA2",
	"SlashCmdList", "UISpecialFrames",
}

-- What the client provides. Kept to what this addon actually touches, so an API that
-- is not really there still shows up as undefined rather than being waved through.
read_globals = {
	-- frames and widgets
	"CreateFrame", "UIParent", "GameFontNormal", "GameFontHighlight",
	-- units and the group
	"UnitName", "UnitClass", "UnitGUID", "UnitExists", "UnitIsUnit",
	"UnitGroupRolesAssigned", "UnitAffectingCombat", "InCombatLockdown",
	"UnitIsGroupLeader", "UnitIsGroupAssistant",
	"IsInRaid", "IsInGroup", "IsInInstance", "IsInGuild",
	"GetNumGroupMembers", "GetNumSubgroupMembers", "GetRaidRosterInfo",
	"SetRaidSubgroup", "SwapRaidSubgroup",
	-- namespaced APIs. This addon targets one interface version, so these are called
	-- directly rather than through a compatibility shim.
	"C_Timer", "C_AddOns", "C_ChatInfo", "C_PartyInfo", "C_DateAndTime",
	"C_DamageMeter", "Enum",
	-- misc client helpers
	"GetAddOnMetadata", "GetLocale", "GetBuildInfo", "GetRealmName", "GetTime",
	"GetServerTime", "GetInstanceInfo", "IsEncounterInProgress",
	"Clamp", "Round", "Saturate", "Lerp", "TableIsEmpty",
	"wipe", "tinsert", "tremove", "sort", "tconcat", "strsplit", "strtrim",
	"date", "time", "difftime",
	"SendChatMessage", "UnitFullName", "GetNormalizedRealmName",
}

-- The harness deliberately reaches for globals the addon would not, and shadows names
-- across independent test sections. Neither is a defect in a test file.
files["tools/"] = {
	ignore = { "411", "412", "421", "422", "431", "432", "113", "143", "212", "231" },
}
