--[[
	RaidOps Alpha - Config

	One window, a tab per module. A module gets a pane by defining
	module:BuildOptions(pane), which is called the first time its tab is opened.
]]

local ADDON, ns = ...
local RO = ns.RO
local UI = RO.UI

local frame

local function buildFrame()
	frame = UI:Panel("RaidOpsAlphaConfig", RO.name .. "  |cff55596a" .. RO.version .. "|r", 700, 480)

	local sidebar = CreateFrame("Frame", nil, frame.content)
	sidebar:SetPoint("TOPLEFT")
	sidebar:SetPoint("BOTTOMLEFT")
	sidebar:SetWidth(150)
	UI:Fill(sidebar, UI.colors.panel)

	local edge = sidebar:CreateTexture(nil, "ARTWORK")
	edge:SetColorTexture(0.18, 0.19, 0.24, 1)
	edge:SetWidth(1)
	edge:SetPoint("TOPRIGHT")
	edge:SetPoint("BOTTOMRIGHT")

	frame.panes = {}
	frame.tabs = {}

	local function select(index)
		for i, pane in ipairs(frame.panes) do
			pane:SetShown(i == index)
			frame.tabs[i].label:SetTextColor(
				i == index and unpack(UI.colors.accent) or unpack(UI.colors.dim))
		end
		local module = RO.modules[index]
		local pane = frame.panes[index]
		if module and pane and not pane.built then
			pane.built = true
			if module.BuildOptions then
				local ok, err = pcall(module.BuildOptions, module, pane)
				if not ok then
					-- The label alone is only visible to whoever opens this tab, which
					-- means the load test called a broken pane clean. Report it through
					-- Core's funnel as well, so the harness and the chat frame both see it.
					RO.moduleError("building options for " .. module.name, err)
					UI:Text(pane, "options failed to build: " .. tostring(err), 12, UI.colors.danger)
						:SetPoint("TOPLEFT", 16, -16)
				end
			else
				local t = UI:Text(pane, "Nothing to configure yet.", 12, UI.colors.dim)
				t:SetPoint("TOPLEFT", 16, -16)
			end
		end
	end

	for i, module in ipairs(RO.modules) do
		local pane = CreateFrame("Frame", nil, frame.content)
		pane:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
		pane:SetPoint("BOTTOMRIGHT")
		pane:Hide()
		frame.panes[i] = pane

		local tab = UI:Button(sidebar, module.title, 150, 26)
		tab:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
		tab.label:SetJustifyH("LEFT")
		tab.label:ClearAllPoints()
		tab.label:SetPoint("LEFT", 12, 0)
		tab:SetScript("OnClick", function() select(i) end)
		frame.tabs[i] = tab
	end

	local credit = UI:Text(frame, "RaidOps Alpha is original work. /roa help", 10, UI.colors.dim)
	credit:SetPoint("BOTTOMLEFT", 12, 8)

	if #RO.modules > 0 then select(1) end

	-- Only tab 1 is built here; the rest build on click. tools/loadtest.lua needs the
	-- tabs to click through them, so the frame is reachable rather than a file local.
	RO.configFrame = frame
	return frame
end

function RO:OpenConfig()
	if not frame then buildFrame() end
	frame:SetShown(not frame:IsShown())
end

RO:RegisterCommand("config", "open the options window", function() RO:OpenConfig() end)
