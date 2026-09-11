--[[
	RaidOps Alpha - Core

	Core owns four things and nothing else:
	  - the saved-variable table and its defaults
	  - a module registry
	  - event dispatch, so a module declares handlers instead of managing frames
	  - the slash command and its subcommand table
]]

local ADDON, ns = ...

local RO = {}
_G.RaidOpsAlpha = RO
ns.RO = RO

RO.name     = "RaidOps Alpha"
RO.short    = "RaidOps"
RO.version  = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version") or "?"
RO.modules  = {}          -- ordered
RO.byName   = {}          -- name -> module
RO.commands = {}          -- subcommand -> { help, fn }

--------------------------------------------------------------------- database

-- Defaults are declared per module in RO:NewModule. Core only owns the root.
local ROOT_DEFAULTS = {
	minimap = { hide = false, angle = 200 },
	debug   = false,
}

local function applyDefaults(target, defaults)
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			if type(target[k]) ~= "table" then target[k] = {} end
			applyDefaults(target[k], v)
		elseif target[k] == nil then
			target[k] = v
		end
	end
	return target
end
RO.ApplyDefaults = applyDefaults

--------------------------------------------------------------------- modules

--- Register a module.
-- @param name      unique key, also the config tab label unless title is given
-- @param defaults  table merged into RaidOpsAlphaDB[name] on load
-- @return the module table. Add handlers as module.events.EVENT_NAME = function(module, ...)
function RO:NewModule(name, defaults)
	assert(type(name) == "string", "module needs a name")
	assert(not self.byName[name], "duplicate module: " .. name)

	local module = {
		name      = name,
		title     = name,
		defaults  = defaults or {},
		events    = {},
		enabled   = true,
	}
	function module:Print(...) RO:Print(...) end
	function module:Debug(...) if RO.db and RO.db.debug then RO:Print("|cff888888" .. self.name .. ":|r", ...) end end

	self.modules[#self.modules + 1] = module
	self.byName[name] = module
	return module
end

function RO:GetModule(name) return self.byName[name] end

--------------------------------------------------------------------- output

function RO:Print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	print("|cff30c8ffRaidOps|r " .. table.concat(parts, " "))
end

--------------------------------------------------------------- event dispatch

local dispatcher = CreateFrame("Frame")
local registered = {}     -- event -> { modules }

local function ensureRegistered(event)
	if registered[event] then return end
	registered[event] = {}
	dispatcher:RegisterEvent(event)
end

local coreEvents = {}

--[[
	One place for module failures. Core pcalls module code on purpose so that one broken
	module cannot take the addon down - see DESIGN.md. The cost is that a module error is
	only ever a printed line, invisible to anything watching for a raised error, which is
	how tools/loadtest.lua could report "loaded clean" for a module whose OnEnable threw.

	RO.onModuleError is the seam. The harness sets it and counts what arrives. In game it
	is nil and this function just prints, exactly as before.
]]
local function moduleError(context, err)
	RO:Print("|cffff4040error|r " .. context .. ": " .. tostring(err))
	if RO.onModuleError then
		pcall(RO.onModuleError, context, err)
	end
end
RO.moduleError = moduleError   -- Config.lua reports pane failures through the same funnel

dispatcher:SetScript("OnEvent", function(_, event, ...)
	local core = coreEvents[event]
	if core then core(...) end

	local list = registered[event]
	if not list then return end
	for i = 1, #list do
		local module = list[i]
		if module.enabled then
			local handler = module.events[event]
			if handler then
				local ok, err = pcall(handler, module, ...)
				if not ok then
					moduleError("in " .. module.name .. " on " .. event, err)
				end
			end
		end
	end
end)

local function wireModuleEvents(module)
	for event in pairs(module.events) do
		ensureRegistered(event)
		local list = registered[event]
		list[#list + 1] = module
	end
end

--------------------------------------------------------------------- lifecycle

dispatcher:RegisterEvent("ADDON_LOADED")
dispatcher:RegisterEvent("PLAYER_LOGIN")

function coreEvents.ADDON_LOADED(addonName)
	if addonName ~= ADDON then return end

	--[[
		Saved variables do not exist while an addon's files are executing. They are
		restored between file execution and this event, which is why every default is
		applied here rather than at file scope. This cost a live session on the previous
		build; see DESIGN.md.
	]]
	RaidOpsAlphaDB = RaidOpsAlphaDB or {}
	RO.db = applyDefaults(RaidOpsAlphaDB, ROOT_DEFAULTS)

	for _, module in ipairs(RO.modules) do
		RO.db[module.name] = applyDefaults(RO.db[module.name] or {}, module.defaults)
		module.db = RO.db[module.name]
		wireModuleEvents(module)
		if module.OnLoad then
			local ok, err = pcall(module.OnLoad, module)
			if not ok then moduleError("loading " .. module.name, err) end
		end
	end

	RO.loaded = true
end

function coreEvents.PLAYER_LOGIN()
	for _, module in ipairs(RO.modules) do
		if module.OnEnable then
			local ok, err = pcall(module.OnEnable, module)
			if not ok then moduleError("enabling " .. module.name, err) end
		end
	end
end

RO.dispatcher = dispatcher

--------------------------------------------------------------------- commands

function RO:RegisterCommand(word, help, fn)
	self.commands[word] = { help = help, fn = fn }
end

RO:RegisterCommand("help", "list commands", function()
	RO:Print(RO.name .. " " .. RO.version)
	local words = {}
	for word in pairs(RO.commands) do words[#words + 1] = word end
	table.sort(words)
	for _, word in ipairs(words) do
		print(("  |cff30c8ff/roa %s|r - %s"):format(word, RO.commands[word].help))
	end
end)

RO:RegisterCommand("debug", "toggle debug output", function()
	RO.db.debug = not RO.db.debug
	RO:Print("debug", RO.db.debug and "on" or "off")
end)

SlashCmdList["ROALPHA"] = function(input)
	local word, rest = (input or ""):match("^(%S*)%s*(.-)$")
	word = word:lower()
	if word == "" then
		if RO.OpenConfig then RO:OpenConfig() else RO.commands.help.fn() end
		return
	end
	local cmd = RO.commands[word]
	if cmd then cmd.fn(rest) else RO:Print("unknown command:", word, "- try /roa help") end
end
SLASH_ROALPHA1 = "/roa"
SLASH_ROALPHA2 = "/raidopsalpha"
