--[[
	RaidOps Alpha - UI

	A deliberately small widget layer. The previous build inherited a 229 KB toolkit to
	get four option panes; this exists so the rewrite does not repeat that.

	Rules for anything added here:
	  - dark and flat by default, no gradients or borders that need art files
	  - every constructor returns the frame, so calls chain
	  - no dependency on any third-party library
]]

local ADDON, ns = ...
local RO = ns.RO

local UI = {}
RO.UI = UI

UI.colors = {
	bg      = { 0.07, 0.08, 0.10, 0.94 },
	panel   = { 0.10, 0.11, 0.14, 1 },
	line    = { 0.18, 0.19, 0.24, 1 },
	text    = { 0.86, 0.88, 0.92, 1 },
	dim     = { 0.55, 0.57, 0.64, 1 },
	accent  = { 1.00, 0.66, 0.00, 1 },
	danger  = { 0.90, 0.30, 0.25, 1 },
}
UI.font = "Fonts\\FRIZQT__.TTF"

local function unpackColor(c) return c[1], c[2], c[3], c[4] end

--- Flat coloured texture filling its parent, or a 1px line when height is given.
function UI:Fill(parent, color, layer)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetColorTexture(unpackColor(color or self.colors.panel))
	t:SetAllPoints(parent)
	return t
end

function UI:Line(parent, color)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetColorTexture(unpackColor(color or self.colors.line))
	t:SetHeight(1)
	return t
end

function UI:Text(parent, text, size, color)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(self.font, size or 12, "")
	fs:SetTextColor(unpackColor(color or self.colors.text))
	fs:SetJustifyH("LEFT")
	fs:SetText(text or "")
	return fs
end

--- Movable, closable panel. Returns the frame; frame.content is where things go.
function UI:Panel(name, title, width, height)
	local f = CreateFrame("Frame", name, UIParent)
	f:SetSize(width or 640, height or 460)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	f:Hide()

	self:Fill(f, self.colors.bg)

	local header = CreateFrame("Frame", nil, f)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(30)
	self:Fill(header, self.colors.panel)
	f.header = header

	f.title = self:Text(header, title or name, 13)
	f.title:SetPoint("LEFT", 12, 0)

	local rule = self:Line(f)
	rule:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
	rule:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)

	local close = self:Button(header, "X", 22, 18)
	close:SetPoint("RIGHT", -6, 0)
	close:SetScript("OnClick", function() f:Hide() end)
	f.close = close

	local content = CreateFrame("Frame", nil, f)
	content:SetPoint("TOPLEFT", 0, -31)
	content:SetPoint("BOTTOMRIGHT")
	f.content = content

	if name then tinsert(UISpecialFrames, name) end
	return f
end

function UI:Button(parent, label, width, height)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 120, height or 22)

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetColorTexture(unpackColor(self.colors.panel))
	bg:SetAllPoints(b)
	b.bg = bg

	local fs = self:Text(b, label, 12)
	fs:SetPoint("CENTER")
	fs:SetJustifyH("CENTER")
	b.label = fs

	b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.16, 0.17, 0.21, 1) end)
	b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(unpackColor(UI.colors.panel)) end)
	return b
end

function UI:Check(parent, label, checked, onChange)
	local c = CreateFrame("CheckButton", nil, parent)
	c:SetSize(18, 18)

	local box = c:CreateTexture(nil, "BACKGROUND")
	box:SetColorTexture(unpackColor(self.colors.panel))
	box:SetAllPoints(c)

	local mark = c:CreateTexture(nil, "ARTWORK")
	mark:SetColorTexture(unpackColor(self.colors.accent))
	mark:SetPoint("TOPLEFT", 4, -4)
	mark:SetPoint("BOTTOMRIGHT", -4, 4)
	c.mark = mark

	c.label = self:Text(c, label, 12)
	c.label:SetPoint("LEFT", c, "RIGHT", 6, 0)

	function c:Refresh() self.mark:SetShown(self:GetChecked()) end
	c:SetChecked(checked and true or false)
	c:Refresh()
	c:SetScript("OnClick", function(self)
		self:Refresh()
		if onChange then onChange(self:GetChecked()) end
	end)
	return c
end

function UI:Edit(parent, width, text, onChange)
	local e = CreateFrame("EditBox", nil, parent)
	e:SetSize(width or 200, 20)
	e:SetAutoFocus(false)
	e:SetFont(self.font, 12, "")
	e:SetTextInsets(6, 6, 0, 0)
	self:Fill(e, self.colors.panel)
	e:SetText(text or "")
	e:SetScript("OnEscapePressed", e.ClearFocus)
	e:SetScript("OnEnterPressed", e.ClearFocus)
	if onChange then
		e:SetScript("OnTextChanged", function(self, user) if user then onChange(self:GetText()) end end)
	end
	return e
end

--- Vertical list of rows. Rows are recycled; provide an update function.
-- update(row, item, index) is called for each visible item.
function UI:List(parent, rowHeight, buildRow, updateRow)
	local list = CreateFrame("ScrollFrame", nil, parent)
	local inner = CreateFrame("Frame", nil, list)
	inner:SetSize(1, 1)
	list:SetScrollChild(inner)
	list.rows, list.inner, list.rowHeight = {}, inner, rowHeight or 20

	function list:SetItems(items)
		local h = self.rowHeight
		for i, item in ipairs(items) do
			local row = self.rows[i]
			if not row then
				row = buildRow(inner)
				row:SetHeight(h)
				row:SetPoint("TOPLEFT", 0, -(i - 1) * h)
				row:SetPoint("TOPRIGHT", 0, -(i - 1) * h)
				self.rows[i] = row
			end
			updateRow(row, item, i)
			row:Show()
		end
		for i = #items + 1, #self.rows do self.rows[i]:Hide() end
		inner:SetHeight(math.max(1, #items * h))
	end
	return list
end
