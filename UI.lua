local ADDON, ns = ...
local Stats = ns.Stats

local UI = { filter = "all", page = 1 }
ns.UI = UI

local FRAME_W, FRAME_H = 1080, 560
local LEFT_W = 408
local TAB_H = 32
local PAD = 16
local INNER_W = LEFT_W - PAD * 2
local ROWS_PER_PAGE = 20
local ROW_H = 20
local RIGHT_W = FRAME_W - 4 - LEFT_W - 2 - 6
local ALL_KEY = "*"
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local QUESTION_MARK_ICON = 134400
local MEDIA = "Interface\\AddOns\\RollsForever\\Media\\"

local GOLD = { 1, 0.82, 0 }
local GREEN = { 0.25, 0.85, 0.3 }
local RED = { 0.9, 0.25, 0.2 }
local GREY = { 0.6, 0.6, 0.6 }
local BLUE = { 0.3, 0.55, 0.85 }

local Q_RED = { 0.85, 0.2, 0.15 }
local Q_GREY = { 0.62, 0.62, 0.62 }
local Q_WHITE = { 1, 1, 1 }
local Q_GREEN = { 0.12, 1, 0 }
local Q_BLUE = { 0, 0.44, 0.87 }
local Q_PURPLE = { 0.64, 0.21, 0.93 }
local Q_ORANGE = { 1, 0.5, 0 }
local BAND_COLORS = {
	Q_RED,
	Q_GREY, Q_GREY,
	Q_WHITE, Q_WHITE,
	Q_GREEN,
	Q_BLUE, Q_BLUE,
	Q_PURPLE, Q_PURPLE,
	Q_ORANGE,
}

local PERIODS = {
	{ key = "30d", label = "30d", long = "30 days", days = 30 },
	{ key = "60d", label = "60d", long = "60 days", days = 60 },
	{ key = "3m", label = "3m", long = "3 months", months = 3 },
	{ key = "6m", label = "6m", long = "6 months", months = 6 },
	{ key = "9m", label = "9m", long = "9 months", months = 9 },
	{ key = "1y", label = "1y", long = "1 year", months = 12 },
	{ key = "all", label = "All", long = "All time" },
}
local PERIOD_BY_KEY = {}
for _, period in ipairs(PERIODS) do
	PERIOD_BY_KEY[period.key] = period
end
UI.period = "all"

local TYPE_INFO = {
	need = { label = NEED or "Need", atlas = "lootroll-icon-need" },
	greed = { label = GREED or "Greed", atlas = "lootroll-icon-greed" },
	pass = { label = PASS or "Pass", atlas = "lootroll-icon-pass" },
	tmog = { label = "Transmog", atlas = "lootroll-icon-transmog" },
	de = { label = ROLL_DISENCHANT or "Disenchant", texture = "Interface\\Buttons\\UI-GroupLoot-DE-Up" },
}

local function Text(parent, font, justify)
	local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
	if justify then
		fs:SetJustifyH(justify)
	end
	return fs
end

local function Round(v)
	return math.floor(v + 0.5)
end

local function Pct(v)
	if not v then
		return "-"
	end
	return Round(v) .. "%"
end

local function OrDash(v)
	if v == nil then
		return "-"
	end
	return tostring(v)
end

local function Hex(color)
	return string.format("|cff%02x%02x%02x", Round(color[1] * 255), Round(color[2] * 255), Round(color[3] * 255))
end

local function QualityColor(quality)
	if quality then
		if ColorManager and ColorManager.GetColorDataForItemQuality then
			local data = ColorManager.GetColorDataForItemQuality(quality)
			if data and data.color then
				return data.color:GetRGB()
			end
		end
		local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
		if color then
			return color.r, color.g, color.b
		end
	end
	return 1, 1, 1
end

local function ClassColored(name, classFile)
	local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if color and name then
		return string.format("|cff%02x%02x%02x%s|r", Round(color.r * 255), Round(color.g * 255), Round(color.b * 255), name)
	end
	return name or "-"
end

local function ItemIcon(itemID)
	if itemID and C_Item and C_Item.GetItemIconByID then
		local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
		if ok and icon then
			return icon
		end
	end
	return QUESTION_MARK_ICON
end

local function RelativeTime(t)
	if not t then
		return "-"
	end
	local diff = ns.Now() - t
	if diff < 60 then
		return "now"
	elseif diff < 3600 then
		return math.floor(diff / 60) .. "m"
	elseif diff < 86400 then
		return math.floor(diff / 3600) .. "h"
	elseif diff < 86400 * 7 then
		return math.floor(diff / 86400) .. "d"
	end
	return date("%d %b", t)
end

local function TypeLabel(rec)
	local info = TYPE_INFO[rec.type]
	if not info then
		return "-"
	end
	if rec.off then
		return info.label .. " (OS)"
	end
	return info.label
end

local function Play(soundName)
	if PlaySound and SOUNDKIT and SOUNDKIT[soundName] then
		PlaySound(SOUNDKIT[soundName])
	end
end

local function AttachTooltip(region, title, body)
	region:EnableMouse(true)
	region:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(type(title) == "function" and title(self) or title, 1, 1, 1)
		local text = type(body) == "function" and body(self) or body
		if text then
			GameTooltip:AddLine(text, GOLD[1], GOLD[2], GOLD[3], true)
		end
		GameTooltip:Show()
	end)
	region:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

local function MakeHeader(parent, label, y)
	local fs = Text(parent, "GameFontNormal", "LEFT")
	fs:SetPoint("TOPLEFT", PAD, y)
	fs:SetText(label)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", PAD, y - 16)
	line:SetPoint("TOPRIGHT", -PAD, y - 16)
	return fs
end

local function MakeHeroTile(parent, index, label, tooltip)
	local width = INNER_W / 3
	local tile = CreateFrame("Frame", nil, parent)
	tile:SetSize(width, 50)
	tile:SetPoint("TOPLEFT", PAD + (index - 1) * width, -14)
	tile.label = Text(tile, "GameFontNormalSmall", "CENTER")
	tile.label:SetPoint("TOP", 0, 0)
	tile.label:SetText(label)
	tile.value = Text(tile, "GameFontHighlightHuge", "CENTER")
	tile.value:SetPoint("TOP", tile.label, "BOTTOM", 0, -6)
	if tile.value.SetTextScale then
		tile.value:SetTextScale(1.3)
	end
	tile.value:SetText("-")
	AttachTooltip(tile, label, tooltip)
	return tile
end

local function MakeHistogram(parent, y)
	local hist = CreateFrame("Frame", nil, parent)
	hist:SetSize(INNER_W, 126)
	hist:SetPoint("TOPLEFT", PAD, y)
	hist.columns = {}
	local count = #Stats.BANDS
	local pitch = INNER_W / count
	for i = 1, count do
		local col = CreateFrame("Frame", nil, hist)
		col:SetSize(pitch, 126)
		col:SetPoint("BOTTOMLEFT", (i - 1) * pitch, 0)

		col.pct = Text(col, "GameFontHighlightSmall", "CENTER")
		col.pct:SetPoint("TOP", 0, 0)

		col.range = Text(col, "GameFontDisableSmall", "CENTER")
		col.range:SetPoint("BOTTOM", 0, 0)
		col.range:SetText(Stats.BandLabel(i))
		if col.range.SetTextScale then
			col.range:SetTextScale(0.85)
		end

		local bar = CreateFrame("StatusBar", nil, col)
		bar:SetSize(20, 96)
		bar:SetPoint("BOTTOM", 0, 14)
		bar:SetOrientation("VERTICAL")
		bar:SetStatusBarTexture(BAR_TEXTURE)
		if bar.SetRotatesTexture then
			bar:SetRotatesTexture(true)
		end
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		local bg = bar:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.4)
		col.bar = bar

		col.index = i
		AttachTooltip(col, function(self)
			return "Rolled " .. Stats.BandLabel(self.index)
		end, function(self)
			return (self.count or 0) .. " rolls (" .. Pct(self.percent or 0) .. ")"
		end)
		hist.columns[i] = col
	end
	return hist
end

local function MakeSplitBar(parent, y, leftLabel, rightLabel, leftColor, rightColor)
	local split = CreateFrame("Frame", nil, parent)
	split:SetSize(INNER_W, 32)
	split:SetPoint("TOPLEFT", PAD, y)

	split.leftText = Text(split, "GameFontHighlightSmall", "LEFT")
	split.leftText:SetPoint("TOPLEFT", 0, 0)
	split.rightText = Text(split, "GameFontHighlightSmall", "RIGHT")
	split.rightText:SetPoint("TOPRIGHT", 0, 0)

	local track = split:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(0, 0, 0, 0.4)
	track:SetHeight(12)
	track:SetPoint("BOTTOMLEFT", 0, 2)
	track:SetPoint("BOTTOMRIGHT", 0, 2)

	split.left = split:CreateTexture(nil, "ARTWORK")
	split.left:SetTexture(BAR_TEXTURE)
	split.left:SetVertexColor(leftColor[1], leftColor[2], leftColor[3])
	split.left:SetHeight(12)
	split.left:SetPoint("BOTTOMLEFT", 0, 2)

	split.right = split:CreateTexture(nil, "ARTWORK")
	split.right:SetTexture(BAR_TEXTURE)
	split.right:SetVertexColor(rightColor[1], rightColor[2], rightColor[3])
	split.right:SetHeight(12)
	split.right:SetPoint("BOTTOMRIGHT", 0, 2)

	function split:Set(leftCount, rightCount)
		local total = (leftCount or 0) + (rightCount or 0)
		if total <= 0 then
			self.left:Hide()
			self.right:Hide()
			self.leftText:SetText(leftLabel .. "  " .. Hex(GREY) .. "-|r")
			self.rightText:SetText(Hex(GREY) .. "-|r  " .. rightLabel)
			return
		end
		local leftPct = leftCount / total * 100
		local leftWidth = INNER_W * leftCount / total
		self.left:SetShown(leftCount > 0)
		self.right:SetShown(rightCount > 0)
		if leftCount > 0 then
			self.left:SetWidth(math.max(1, leftWidth))
		end
		if rightCount > 0 then
			self.right:SetWidth(math.max(1, INNER_W - leftWidth))
		end
		self.leftText:SetText(leftLabel .. "  " .. Hex(leftColor) .. Pct(leftPct) .. "|r")
		self.rightText:SetText(Hex(rightColor) .. Pct(100 - leftPct) .. "|r  " .. rightLabel)
	end
	return split
end

local function MakeStatLine(parent, x, y, width, label, tooltip)
	local line = CreateFrame("Frame", nil, parent)
	line:SetSize(width, 18)
	line:SetPoint("TOPLEFT", x, y)
	line.value = Text(line, "GameFontHighlightSmall", "RIGHT")
	line.value:SetPoint("RIGHT", 0, 0)
	line.value:SetText("-")

	line.label = Text(line, "GameFontNormalSmall", "LEFT")
	line.label:SetPoint("LEFT", 0, 0)
	line.label:SetPoint("RIGHT", line.value, "LEFT", -8, 0)
	line.label:SetWordWrap(false)
	line.label:SetText(label)
	if tooltip then
		AttachTooltip(line, label, tooltip)
	end
	return line
end

function UI:BuildStatsPanel(panel)
	local w = {}
	self.widgets = w

	w.rolls = MakeHeroTile(panel, 1, "Rolls", "How many times you rolled Need or Greed.")
	w.average = MakeHeroTile(panel, 2, "Average Roll", "Your average roll. Pure luck should land around 50.")
	w.won = MakeHeroTile(panel, 3, "Items Won", "Rolls you actually won.")

	MakeHeader(panel, "Numbers Rolled", -74)
	w.mostLikely = Text(panel, "GameFontNormalSmall", "RIGHT")
	w.mostLikely:SetPoint("TOPRIGHT", -PAD, -75)
	w.hist = MakeHistogram(panel, -98)

	w.halves = MakeSplitBar(panel, -234, "Below 50", "50 and above", BLUE, GOLD)
	w.outcome = MakeSplitBar(panel, -272, "Won loot", "Pure salt", GREEN, RED)

	local details = MakeHeader(panel, "Details", -314)
	local info = CreateFrame("Frame", nil, panel)
	info:SetSize(16, 16)
	info:SetPoint("LEFT", details, "RIGHT", 3, 0)
	local infoIcon = info:CreateTexture(nil, "ARTWORK")
	infoIcon:SetTexture("Interface\\FriendsFrame\\InformationIcon")
	infoIcon:SetAllPoints()
	AttachTooltip(info, GREED or "Greed",
		"Greed luck, streaks and losses are only calculated against rolls where nobody selected Need.")
	info:Hide()
	w.greedInfo = info
	local colW = (INNER_W - 24) / 2
	local leftX, rightX = PAD, PAD + colW + 24
	local y0, step = -336, 18
	w.median = MakeStatLine(panel, leftX, y0, colW, "Median roll")
	w.highest = MakeStatLine(panel, leftX, y0 - step, colW, "Highest roll")
	w.lowest = MakeStatLine(panel, leftX, y0 - step * 2, colW, "Lowest roll")
	w.hundreds = MakeStatLine(panel, leftX, y0 - step * 3, colW, "Natural 100s")
	w.ones = MakeStatLine(panel, leftX, y0 - step * 4, colW, "Natural 1s")
	w.avgWin = MakeStatLine(panel, leftX, y0 - step * 5, colW, "Avg winning roll")

	w.luck = MakeStatLine(panel, rightX, y0, colW, "Luck",
		"How often you win compared to an even split with everyone who rolled the same as you. +0% means you're bang on average.")
	w.winStreak = MakeStatLine(panel, rightX, y0 - step, colW, "Best win streak")
	w.dryStreak = MakeStatLine(panel, rightX, y0 - step * 2, colW, "Longest dry streak",
		"The most rolls in a row you've gone without a win.")
	w.streak = MakeStatLine(panel, rightX, y0 - step * 3, colW, "Current streak",
		"How your last few rolls went.")
	w.closest = MakeStatLine(panel, rightX, y0 - step * 4, colW, "Closest loss",
		"The closest you've come to winning without getting it.")
	w.avgLoss = MakeStatLine(panel, rightX, y0 - step * 5, colW, "Avg losing roll")

	w.picks = MakeStatLine(panel, PAD, y0 - step * 6 - 6, INNER_W, "Your picks",
		"What you've picked over time.")
	w.topZone = MakeStatLine(panel, PAD, y0 - step * 7 - 6, INNER_W, "Most rolls in")
end

function UI:UpdateStats(s)
	local w = self.widgets
	w.greedInfo:SetShown(self.filter == "greed")
	w.rolls.value:SetText(s.selections)
	w.average.value:SetText(s.avg and string.format("%.1f", s.avg) or "-")
	w.won.value:SetText(s.wins)

	local maxCount = math.max(1, s.maxBandCount or 1)
	for i, col in ipairs(w.hist.columns) do
		local count = s.bands[i] or 0
		col.count, col.percent = count, s.bandPct[i] or 0
		col.bar:SetMinMaxValues(0, maxCount)
		col.bar:SetValue(count)
		local color = BAND_COLORS[i]
		col.bar:SetStatusBarColor(color[1], color[2], color[3])
		col.pct:SetText(s.numbered > 0 and Pct(col.percent) or "")

		if i == s.modeBand then
			col.range:SetTextColor(color[1], color[2], color[3])
		else
			col.range:SetTextColor(0.5, 0.5, 0.5)
		end
	end
	if s.modeBand then
		w.mostLikely:SetText("Most frequent: " .. Hex(BAND_COLORS[s.modeBand]) .. Stats.BandLabel(s.modeBand) .. "|r")
	else
		w.mostLikely:SetText(Hex(GREY) .. "No roll numbers yet|r")
	end

	w.halves:Set(s.below50, s.atLeast50)
	w.outcome:Set(s.wins, s.losses)

	w.median.value:SetText(s.median and (s.median % 1 == 0 and string.format("%d", s.median) or string.format("%.1f", s.median)) or "-")
	w.highest.value:SetText(OrDash(s.max))
	w.lowest.value:SetText(OrDash(s.min))
	w.hundreds.value:SetText(s.hundreds)
	w.ones.value:SetText(s.ones)
	w.avgWin.value:SetText(s.avgWinningRoll and string.format("%.1f", s.avgWinningRoll) or "-")
	w.avgLoss.value:SetText(s.avgLosingRoll and string.format("%.1f", s.avgLosingRoll) or "-")

	if s.luck then
		local delta = Round((s.luck - 1) * 100)
		local color = (delta >= 0) and GREEN or RED
		w.luck.value:SetText(Hex(color) .. string.format("%+d%%", delta) .. "|r")
	else
		w.luck.value:SetText("-")
	end
	w.winStreak.value:SetText(s.bestWinStreak)
	w.dryStreak.value:SetText(s.longestDryStreak)
	w.closest.value:SetText(s.closestLoss and ("by " .. s.closestLoss) or "-")
	if s.currentStreak > 0 and s.currentStreakWon then
		w.streak.value:SetText(Hex(GREEN) .. s.currentStreak .. (s.currentStreak == 1 and " win" or " wins") .. "|r")
	elseif s.currentStreak > 0 then
		w.streak.value:SetText(Hex(RED) .. s.currentStreak .. " dry|r")
	else
		w.streak.value:SetText("-")
	end
	w.picks.value:SetText(s.need .. " Need  |  " .. s.greed .. " Greed  |  " .. s.pass .. " Pass")

	local top = s.zones[1]
	w.topZone.value:SetText(top and (top.name .. " (" .. top.count .. ")") or "-")
end

local COL = {
	itemX = 2, itemW = 186,
	typeX = 194, typeW = 40,
	rollX = 250, rollW = 28,
	resultX = 290, resultW = 42,
	winnerX = 338,
	winnerRollW = 32,
	whereW = 100,
	whenW = 40,
}

local function ShowRowTooltip(row)
	local rec = row.rec
	if not rec then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	local shown = false
	if rec.link then
		shown = pcall(GameTooltip.SetHyperlink, GameTooltip, rec.link)
	end
	if not shown then
		local r, g, b = QualityColor(rec.q)
		GameTooltip:SetText(rec.n or (UNKNOWN or "Unknown"), r, g, b)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Loot Roll", GOLD[1], GOLD[2], GOLD[3])

	local mine = TypeLabel(rec)
	if rec.roll then
		mine = mine .. " - " .. rec.roll
	end
	GameTooltip:AddDoubleLine("You", mine, 1, 1, 1, 1, 1, 1)

	if rec.allp then
		GameTooltip:AddDoubleLine("Winner", "Everyone passed", 1, 1, 1, GREY[1], GREY[2], GREY[3])
	elseif rec.wn then
		local winner = ClassColored(rec.wn, rec.wc)
		local detail = TYPE_INFO[rec.wt] and TYPE_INFO[rec.wt].label or nil
		if detail and rec.wr then
			winner = winner .. " (" .. detail .. " - " .. rec.wr .. ")"
		elseif rec.wr then
			winner = winner .. " (" .. rec.wr .. ")"
		elseif detail then
			winner = winner .. " (" .. detail .. ")"
		end
		GameTooltip:AddDoubleLine("Winner", winner, 1, 1, 1, 1, 1, 1)
	end
	if rec.cn or rec.cg or rec.cp then
		GameTooltip:AddDoubleLine("Group picks",
			(rec.cn or 0) .. " Need, " .. (rec.cg or 0) .. " Greed, " .. (rec.cp or 0) .. " Pass", 1, 1, 1, 1, 1, 1)
	end
	if rec.zone then
		GameTooltip:AddDoubleLine("Where", rec.zone, 1, 1, 1, 1, 1, 1)
	end
	if rec.t then
		GameTooltip:AddDoubleLine("When", date("%d %b %Y %H:%M", rec.t), 1, 1, 1, 1, 1, 1)
	end
	local owner = UI.owners and UI.owners[rec]
	if owner then
		GameTooltip:AddDoubleLine("Character", owner, 1, 1, 1, 1, 1, 1)
	end
	local blocked = Stats.BlockedByNeed(rec)
	if blocked and not rec.roll then
		GameTooltip:AddLine("No number here: someone picked Need, so Greed never got to roll. Not counted as a loss.", GREY[1], GREY[2], GREY[3], true)
	elseif blocked then
		GameTooltip:AddLine("Not counted as a loss: someone picked Need, so this roll couldn't win.", GREY[1], GREY[2], GREY[3], true)
	end
	if rec.inf and not blocked then
		GameTooltip:AddLine("Counted as a loss - the game never said you won this one.", GREY[1], GREY[2], GREY[3], true)
	end
	GameTooltip:Show()
end

local function MakeRow(parent, index, top)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 8, top - (index - 1) * ROW_H)
	row:SetPoint("TOPRIGHT", -8, top - (index - 1) * ROW_H)

	if index % 2 == 0 then
		local stripe = row:CreateTexture(nil, "BACKGROUND")
		stripe:SetAllPoints()
		stripe:SetColorTexture(1, 1, 1, 0.04)
	end
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", COL.itemX, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.name = Text(row, "GameFontHighlightSmall", "LEFT")
	row.name:SetPoint("LEFT", COL.itemX + 21, 0)
	row.name:SetWidth(COL.itemW - 21)
	row.name:SetWordWrap(false)

	row.typeIcon = row:CreateTexture(nil, "ARTWORK")
	row.typeIcon:SetSize(14, 14)
	row.typeIcon:SetPoint("LEFT", COL.typeX, 0)

	row.typeText = Text(row, "GameFontHighlightSmall", "LEFT")
	row.typeText:SetPoint("LEFT", COL.typeX + 18, 0)
	row.typeText:SetWidth(COL.typeW)
	row.typeText:SetWordWrap(false)

	row.roll = Text(row, "GameFontHighlightSmall", "RIGHT")
	row.roll:SetPoint("LEFT", COL.rollX, 0)
	row.roll:SetWidth(COL.rollW)

	row.result = Text(row, "GameFontHighlightSmall", "LEFT")
	row.result:SetPoint("LEFT", COL.resultX, 0)
	row.result:SetWidth(COL.resultW)

	row.when = Text(row, "GameFontDisableSmall", "RIGHT")
	row.when:SetPoint("RIGHT", -2, 0)
	row.when:SetWidth(COL.whenW)

	row.winnerRoll = Text(row, "GameFontHighlightSmall", "RIGHT")
	row.where = Text(row, "GameFontHighlightSmall", "LEFT")
	row.where:SetPoint("RIGHT", row.when, "LEFT", -8, 0)
	row.where:SetWidth(COL.whereW)
	row.where:SetWordWrap(false)
	row.where:SetTextColor(0.78, 0.78, 0.78)

	row.winnerRoll:SetPoint("RIGHT", row.where, "LEFT", -10, 0)
	row.winnerRoll:SetWidth(COL.winnerRollW)

	row.winner = Text(row, "GameFontHighlightSmall", "LEFT")
	row.winner:SetPoint("LEFT", COL.winnerX, 0)
	row.winner:SetPoint("RIGHT", row.winnerRoll, "LEFT", -4, 0)
	row.winner:SetWordWrap(false)

	row:SetScript("OnEnter", ShowRowTooltip)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self)
		local rec = self.rec
		if rec and rec.link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
			HandleModifiedItemClick(rec.link)
		end
	end)
	return row
end

local function FillRow(row, rec)
	row.rec = rec
	if not rec then
		row:Hide()
		return
	end
	row.icon:SetTexture(ItemIcon(rec.item))
	row.name:SetText(rec.n or (UNKNOWN or "Unknown"))
	row.name:SetTextColor(QualityColor(rec.q))

	local info = TYPE_INFO[rec.type]
	if info and info.atlas then
		row.typeIcon:SetAtlas(info.atlas)
		row.typeIcon:Show()
	elseif info and info.texture then
		row.typeIcon:SetTexture(info.texture)
		row.typeIcon:SetTexCoord(0, 1, 0, 1)
		row.typeIcon:Show()
	else
		row.typeIcon:Hide()
	end
	row.typeText:SetText(info and info.label or "-")
	row.roll:SetText(OrDash(rec.roll))

	local blocked = Stats.BlockedByNeed(rec)
	if rec.won == true then
		row.result:SetText("Won")
		row.result:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
	elseif rec.type == "pass" then
		row.result:SetText("Passed")
		row.result:SetTextColor(GREY[1], GREY[2], GREY[3])
	elseif blocked then
		row.result:SetText("N/A")
		row.result:SetTextColor(1, 1, 1)
	elseif rec.won == false then
		row.result:SetText("Lost")
		row.result:SetTextColor(RED[1], RED[2], RED[3])
	else
		row.result:SetText("-")
		row.result:SetTextColor(GREY[1], GREY[2], GREY[3])
	end

	-- A Need winner's "(Need - N)" is wider than the roll column, so the roll column grows to fit it
	-- (width 0 = size to text) and stays right-aligned with the plain "(N)" rolls.
	local inline = blocked and rec.wn and not rec.allp
	row.winnerRoll:SetWidth(inline and 0 or COL.winnerRollW)
	if rec.allp then
		row.winner:SetText(Hex(GREY) .. "All passed|r")
		row.winnerRoll:SetText("")
	elseif inline then
		local label = TYPE_INFO.need.label
		row.winner:SetText(ClassColored(rec.wn, rec.wc))
		row.winnerRoll:SetText("(" .. label .. (rec.wr and (" - " .. rec.wr) or "") .. ")")
	elseif rec.wn then
		row.winner:SetText(ClassColored(rec.wn, rec.wc))
		row.winnerRoll:SetText(rec.wr and ("(" .. rec.wr .. ")") or "")
	else
		row.winner:SetText(Hex(GREY) .. "-|r")
		row.winnerRoll:SetText("")
	end
	row.where:SetText(rec.zone or "-")
	row.when:SetText(RelativeTime(rec.t))
	row:Show()
end

local function MakeArrow(parent, direction)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(26, 26)
	local base = "Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page"
	button:SetNormalTexture(base .. "-Up")
	button:SetPushedTexture(base .. "-Down")
	button:SetDisabledTexture(base .. "-Disabled")
	button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	return button
end

function UI:BuildHistoryPanel(panel)
	local function header(label, x, justify, fromRight)
		local fs = Text(panel, "GameFontNormalSmall", justify)
		if fromRight then
			fs:SetPoint("TOPRIGHT", -10, -32)
		else
			fs:SetPoint("TOPLEFT", 8 + x, -32)
		end
		fs:SetText(label)
		return fs
	end
	header("Item", COL.itemX, "LEFT")
	header("Roll", COL.typeX, "LEFT")
	header("Result", COL.resultX, "LEFT")
	header("Winner", COL.winnerX, "LEFT")
	header("Where", RIGHT_W - 16 - 2 - COL.whenW - 8 - COL.whereW, "LEFT")
	header("When", 0, "RIGHT", true)

	local line = panel:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", 8, -47)
	line:SetPoint("TOPRIGHT", -8, -47)

	local search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	search:SetSize(math.floor(RIGHT_W * 0.4), 20)
	search:SetPoint("TOP", 0, -6)
	search:SetAutoFocus(false)
	search:SetMaxLetters(40)
	search:SetAlpha(0.85)
	search:HookScript("OnTextChanged", function(self)
		UI:QueueSearch(self:GetText())
	end)
	self.searchBox = search

	self.rows = {}
	for i = 1, ROWS_PER_PAGE do
		self.rows[i] = MakeRow(panel, i, -50)
	end

	self.emptyText = Text(panel, "GameFontDisable", "CENTER")
	self.emptyText:SetPoint("CENTER", 0, 20)
	self.emptyText:SetWidth(360)

	self.pageText = Text(panel, "GameFontHighlightSmall", "CENTER")
	self.pageText:SetPoint("BOTTOM", 0, 16)

	self.prevButton = MakeArrow(panel, "Prev")
	self.prevButton:SetPoint("RIGHT", self.pageText, "LEFT", -12, 0)
	self.prevButton:SetScript("OnClick", function()
		UI:SetPage(UI.page - 1)
		Play("IG_ABILITY_PAGE_TURN")
	end)

	self.nextButton = MakeArrow(panel, "Next")
	self.nextButton:SetPoint("LEFT", self.pageText, "RIGHT", 12, 0)
	self.nextButton:SetScript("OnClick", function()
		UI:SetPage(UI.page + 1)
		Play("IG_ABILITY_PAGE_TURN")
	end)

	self.countText = Text(panel, "GameFontDisableSmall", "RIGHT")
	self.countText:SetPoint("BOTTOMRIGHT", -12, 18)

	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		UI:SetPage(UI.page - delta)
	end)
end

function UI:SetPage(page)
	self.page = page
	self:UpdatePage()
end

function UI:UpdatePage()
	local list = self.list or {}
	local total = #list
	local maxPage = math.max(1, math.ceil(total / ROWS_PER_PAGE))
	if self.page > maxPage then
		self.page = maxPage
	end
	if self.page < 1 then
		self.page = 1
	end
	local offset = (self.page - 1) * ROWS_PER_PAGE
	for i = 1, ROWS_PER_PAGE do
		FillRow(self.rows[i], list[offset + i])
	end

	if total == 0 and self.search then
		self.emptyText:SetText("No rolls match \"" .. self.search .. "\".")
		self.emptyText:Show()
	elseif total == 0 and self.period ~= "all" then
		self.emptyText:SetText("No rolls in this date range.")
		self.emptyText:Show()
	elseif total == 0 then
		if self.filter == "all" then
			self.emptyText:SetText("Nothing here yet.\n\nGroup up, roll on some loot and it'll show up here.")
		else
			self.emptyText:SetText("No " .. (self.filter == "need" and "Need" or "Greed") .. " rolls recorded yet.")
		end
		self.emptyText:Show()
	else
		self.emptyText:Hide()
	end

	self.pageText:SetText(string.format(PAGE_NUMBER_WITH_MAX or "Page %d/%d", self.page, maxPage))
	self.prevButton:SetEnabled(self.page > 1)
	self.nextButton:SetEnabled(self.page < maxPage)
	if total > 0 then
		self.countText:SetText((offset + 1) .. "-" .. math.min(total, offset + ROWS_PER_PAGE) .. " of " .. total)
	else
		self.countText:SetText("")
	end
end

function UI:GetRecords()
	local db = ns.db
	local out, owners = {}, nil
	if self.charKey == ALL_KEY then
		owners = {}
		for _, char in pairs(db.chars) do
			if not char.test then
				local name = ns.CharDisplayName(char)
				for _, rec in ipairs(char.rolls) do
					out[#out + 1] = rec
					owners[rec] = name
				end
			end
		end
		table.sort(out, function(a, b)
			local ta, tb = a.t or 0, b.t or 0
			if ta ~= tb then
				return ta < tb
			end
			return (a.id or 0) < (b.id or 0)
		end)
	else
		local char = db.chars[self.charKey]
		if char then
			for _, rec in ipairs(char.rolls) do
				out[#out + 1] = rec
			end
		end
	end
	return out, owners
end

function UI:Refresh()
	self.refreshQueued = false
	if not self.frame then
		return
	end
	local records, owners = self:GetRecords()
	records = self:FilterByDate(records)
	local filtered = Stats.Filter(records, self.filter)
	local s = Stats.Compute(filtered)
	self:UpdateStats(s)

	self.filtered = filtered
	self.owners = owners
	self:BuildList()
	self:UpdatePage()

	if self.filter == "all" then
		self.summary:SetText(s.total .. " items  |  " .. s.selections .. " rolled  |  " .. s.pass .. " passed")
	else
		self.summary:SetText(s.total .. " " .. (self.filter == "need" and "Need" or "Greed") .. " rolls  |  " .. s.wins .. " won")
	end
end

function UI:BuildList()
	local filtered = self.filtered or {}
	local list = {}
	local query = self.search
	if not query then
		for i = #filtered, 1, -1 do
			list[#list + 1] = filtered[i]
		end
		self.list = list
		return
	end

	local words = {}
	for word in query:gmatch("%S+") do
		words[#words + 1] = word
	end
	local byWinner = {}
	for i = #filtered, 1, -1 do
		local rec = filtered[i]
		local item = (rec.n or ""):lower()
		local winner = ((rec.wn or "") .. " " .. (rec.zone or "")):lower()
		local inItem, inEither = true, true
		for w = 1, #words do
			local word = words[w]
			if not item:find(word, 1, true) then
				inItem = false
				if not winner:find(word, 1, true) then
					inEither = false
					break
				end
			end
		end
		if inItem then
			list[#list + 1] = rec
		elseif inEither then
			byWinner[#byWinner + 1] = rec
		end
	end
	for i = 1, #byWinner do
		list[#list + 1] = byWinner[i]
	end
	self.list = list
end

function UI:QueueSearch(text)
	self.searchSerial = (self.searchSerial or 0) + 1
	local serial = self.searchSerial
	C_Timer.After(0.3, function()
		if serial == UI.searchSerial then
			UI:ApplySearch(text)
		end
	end)
end

function UI:ApplySearch(text)
	local query = (text or ""):lower():match("^%s*(.-)%s*$")
	if query == "" then
		query = nil
	end
	if query == self.search then
		return
	end
	self.search = query
	self.page = 1
	self:BuildList()
	self:UpdatePage()
end

local function Today()
	local now = date("*t", ns.Now())
	return { year = now.year, month = now.month, day = now.day }
end

function UI:GetDateRange()
	local period = PERIOD_BY_KEY[self.period]
	if not period or period.key == "all" then
		return nil
	end
	local d = self.endDate or Today()
	local finish = time({ year = d.year, month = d.month, day = d.day, hour = 23, min = 59, sec = 59 })
	local start
	if period.days then
		start = time({ year = d.year, month = d.month, day = d.day - period.days, hour = 0, min = 0, sec = 0 })
	else
		start = time({ year = d.year, month = d.month - period.months, day = d.day, hour = 0, min = 0, sec = 0 })
	end
	return start, finish
end

function UI:FilterByDate(records)
	local start, finish = self:GetDateRange()
	if not start then
		return records
	end
	local out = {}
	for i = 1, #records do
		local t = records[i].t
		if t and t >= start and t <= finish then
			out[#out + 1] = records[i]
		end
	end
	return out
end

function UI:DateFilterLabel()
	local period = PERIOD_BY_KEY[self.period] or PERIOD_BY_KEY.all
	if period.key == "all" then
		return period.long
	end
	if not self.endDate then
		return "Last " .. period.long
	end
	local d = self.endDate
	local stamp = time({ year = d.year, month = d.month, day = d.day, hour = 12 })
	local sameYear = d.year == Today().year
	return period.long .. " to " .. date(sameYear and "%d %b" or "%d %b %Y", stamp)
end

function UI:SetDateFilter(periodKey, endDate, keepEndDate)
	if periodKey then
		self.period = periodKey
	end
	if not keepEndDate then
		local today = Today()
		if endDate and endDate.year == today.year and endDate.month == today.month and endDate.day == today.day then
			endDate = nil
		end
		self.endDate = endDate
	end
	self.page = 1
	self:UpdateDateUI()
	self:Refresh()
end

local CELL_W, CELL_H = 28, 22
local POP_PAD = 12
local POP_W = CELL_W * 7 + POP_PAD * 2
local POP_H = 246

function UI:UpdateDateUI()
	if not self.dateButton then
		return
	end
	self.dateButton.text:SetText(self:DateFilterLabel())
	local pop = self.datePopup
	if not pop or not self.calendarView or not self.dateCatcher:IsShown() then
		return
	end

	local view = self.calendarView
	local today = Today()
	local first = time({ year = view.year, month = view.month, day = 1, hour = 12 })
	local firstInfo = date("*t", first)
	local daysInMonth = date("*t", time({ year = view.year, month = view.month + 1, day = 0, hour = 12 })).day
	pop.monthText:SetText(date("%B %Y", first))
	pop.nextButton:SetEnabled(view.year < today.year or (view.year == today.year and view.month < today.month))

	local start, finish = self:GetDateRange()
	local selected = self.endDate or today
	local todayEnd = time({ year = today.year, month = today.month, day = today.day, hour = 23, min = 59, sec = 59 })

	for index, cell in ipairs(pop.cells) do
		local day = index - (firstInfo.wday - 1)
		if day < 1 or day > daysInMonth then
			cell:Hide()
		else
			local stamp = time({ year = view.year, month = view.month, day = day, hour = 12 })
			cell.day = day
			cell.text:SetText(day)
			local isSelected = self.period ~= "all" and view.year == selected.year and view.month == selected.month and day == selected.day
			local isToday = view.year == today.year and view.month == today.month and day == today.day
			local future = stamp > todayEnd
			cell:SetEnabled(not future)
			cell.selected:SetShown(isSelected)
			cell.inRange:SetShown(not isSelected and start ~= nil and stamp >= start and stamp <= finish)
			if future then
				cell.text:SetTextColor(0.35, 0.35, 0.35)
			elseif isSelected or isToday then
				cell.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
			else
				cell.text:SetTextColor(1, 1, 1)
			end
			cell:Show()
		end
	end

	for _, chip in ipairs(pop.chips) do
		local active = chip.key == self.period
		chip.underline:SetShown(active)
		if active then
			chip.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		else
			chip.text:SetTextColor(0.8, 0.8, 0.8)
		end
	end

	if start then
		pop.rangeText:SetText(date("%d %b %Y", start) .. " - " .. date("%d %b %Y", finish))
	else
		pop.rangeText:SetText("Showing all your rolls")
	end
	pop.todayButton:SetShown(self.endDate ~= nil)
end

function UI:BuildDatePopup(f, anchor)

	local catcher = CreateFrame("Button", nil, f)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("DIALOG")
	catcher:Hide()
	catcher:SetScript("OnClick", function(self)
		self:Hide()
	end)

	local pop = CreateFrame("Frame", nil, catcher, "BackdropTemplate")
	pop:SetSize(POP_W, POP_H)
	pop:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -6, -6)
	pop:EnableMouse(true)
	pop:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	pop:SetBackdropColor(0.04, 0.04, 0.04, 0.97)
	pop:SetBackdropBorderColor(0.6, 0.6, 0.6)

	pop.monthText = Text(pop, "GameFontNormal", "CENTER")
	pop.monthText:SetPoint("TOP", 0, -13)
	local function shiftMonth(delta)
		local view = UI.calendarView
		local info = date("*t", time({ year = view.year, month = view.month + delta, day = 1, hour = 12 }))
		view.year, view.month = info.year, info.month
		UI:UpdateDateUI()
		Play("IG_ABILITY_PAGE_TURN")
	end
	pop.prevButton = MakeArrow(pop, "Prev")
	pop.prevButton:SetSize(22, 22)
	pop.prevButton:SetPoint("TOPLEFT", POP_PAD - 2, -8)
	pop.prevButton:SetScript("OnClick", function()
		shiftMonth(-1)
	end)
	pop.nextButton = MakeArrow(pop, "Next")
	pop.nextButton:SetSize(22, 22)
	pop.nextButton:SetPoint("TOPRIGHT", -(POP_PAD - 2), -8)
	pop.nextButton:SetScript("OnClick", function()
		shiftMonth(1)
	end)

	local initials = { "S", "M", "T", "W", "T", "F", "S" }
	for column = 1, 7 do
		local fs = Text(pop, "GameFontDisableSmall", "CENTER")
		fs:SetWidth(CELL_W)
		fs:SetPoint("TOPLEFT", POP_PAD + (column - 1) * CELL_W, -36)
		fs:SetText(initials[column])
	end

	pop.cells = {}
	for index = 1, 42 do
		local row, column = math.floor((index - 1) / 7), (index - 1) % 7
		local cell = CreateFrame("Button", nil, pop)
		cell:SetSize(CELL_W, CELL_H)
		cell:SetPoint("TOPLEFT", POP_PAD + column * CELL_W, -50 - row * CELL_H)

		cell.inRange = cell:CreateTexture(nil, "BACKGROUND")
		cell.inRange:SetPoint("TOPLEFT", 0, -1)
		cell.inRange:SetPoint("BOTTOMRIGHT", 0, 1)
		cell.inRange:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.1)

		cell.selected = cell:CreateTexture(nil, "BORDER")
		cell.selected:SetPoint("TOPLEFT", 1, -1)
		cell.selected:SetPoint("BOTTOMRIGHT", -1, 1)
		cell.selected:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)

		local hover = cell:CreateTexture(nil, "HIGHLIGHT")
		hover:SetPoint("TOPLEFT", 1, -1)
		hover:SetPoint("BOTTOMRIGHT", -1, 1)
		hover:SetColorTexture(1, 1, 1, 0.12)

		cell.text = Text(cell, "GameFontHighlightSmall", "CENTER")
		cell.text:SetPoint("CENTER", 0, 0)

		cell:SetScript("OnClick", function(self)
			local view = UI.calendarView

			local period = (UI.period == "all") and "30d" or nil
			UI:SetDateFilter(period, { year = view.year, month = view.month, day = self.day })
			Play("IG_CHARACTER_INFO_TAB")
		end)
		pop.cells[index] = cell
	end

	local divider = pop:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	divider:SetHeight(1)
	divider:SetPoint("TOPLEFT", POP_PAD, -188)
	divider:SetPoint("TOPRIGHT", -POP_PAD, -188)

	pop.chips = {}
	for index, period in ipairs(PERIODS) do
		local chip = CreateFrame("Button", nil, pop)
		chip:SetSize(CELL_W, 20)
		chip:SetPoint("TOPLEFT", POP_PAD + (index - 1) * CELL_W, -194)
		chip.key = period.key
		chip.text = Text(chip, "GameFontHighlightSmall", "CENTER")
		chip.text:SetPoint("CENTER", 0, 0)
		chip.text:SetText(period.label)
		chip.underline = chip:CreateTexture(nil, "ARTWORK")
		chip.underline:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
		chip.underline:SetHeight(1)
		chip.underline:SetPoint("BOTTOMLEFT", 5, 1)
		chip.underline:SetPoint("BOTTOMRIGHT", -5, 1)
		local hover = chip:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, 0.1)
		chip:SetScript("OnClick", function(self)
			local keepEndDate = true
			UI:SetDateFilter(self.key, nil, keepEndDate)
			Play("IG_CHARACTER_INFO_TAB")
		end)
		AttachTooltip(chip, period.long, period.key ~= "all" and "Counted back from the date you picked." or nil)
		pop.chips[index] = chip
	end

	pop.rangeText = Text(pop, "GameFontDisableSmall", "LEFT")
	pop.rangeText:SetPoint("BOTTOMLEFT", POP_PAD, 12)

	pop.todayButton = CreateFrame("Button", nil, pop)
	pop.todayButton:SetSize(40, 16)
	pop.todayButton:SetPoint("BOTTOMRIGHT", -POP_PAD, 9)
	local todayText = Text(pop.todayButton, "GameFontNormalSmall", "RIGHT")
	todayText:SetPoint("RIGHT", 0, 0)
	todayText:SetText("Today")
	pop.todayButton:SetScript("OnClick", function()
		local today = Today()
		UI.calendarView = { year = today.year, month = today.month }
		UI:SetDateFilter(nil, nil)
	end)

	self.dateCatcher = catcher
	self.datePopup = pop
end

function UI:ToggleDatePopup()
	local catcher = self.dateCatcher
	if catcher:IsShown() then
		catcher:Hide()
		return
	end
	local shown = self.endDate or Today()
	self.calendarView = { year = shown.year, month = shown.month }
	catcher:Show()
	self:UpdateDateUI()
end

function UI:BuildDateFilter(f)
	local button = CreateFrame("Button", nil, f)
	button:SetSize(176, 25)
	button:SetPoint("TOPLEFT", 316, -29)

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetAtlas("common-dropdown-textholder")
	background:SetPoint("TOPLEFT", -8, 7)
	background:SetPoint("BOTTOMRIGHT", 8, -9)

	local arrow = button:CreateTexture(nil, "OVERLAY")
	arrow:SetAtlas("common-dropdown-a-button", true)
	arrow:SetPoint("RIGHT", 1, -3)

	button.text = Text(button, "GameFontHighlight", "LEFT")
	button.text:SetPoint("TOPLEFT", 8, -8)
	button.text:SetSize(140, 10)
	button.text:SetWordWrap(false)

	local over, down = false, false
	local function updateArrow()
		local open = UI.dateCatcher and UI.dateCatcher:IsShown()
		local atlas = "common-dropdown-a-button"
		if down and over then
			atlas = "common-dropdown-a-button-pressedhover"
		elseif over then
			atlas = "common-dropdown-a-button-hover"
		elseif down then
			atlas = "common-dropdown-a-button-pressed"
		elseif open then
			atlas = "common-dropdown-a-button-open"
		end
		arrow:SetAtlas(atlas, true)
	end
	button.UpdateArrow = updateArrow

	button:SetScript("OnEnter", function()
		over = true
		updateArrow()
	end)
	button:SetScript("OnLeave", function()
		over = false
		updateArrow()
	end)
	button:SetScript("OnMouseDown", function()
		down = true
		updateArrow()
	end)
	button:SetScript("OnMouseUp", function()
		down = false
		updateArrow()
	end)
	button:SetScript("OnClick", function()
		UI:ToggleDatePopup()
		Play("IG_CHARACTER_INFO_TAB")
	end)

	self.dateButton = button
	self:BuildDatePopup(f, button)
	self.dateCatcher:SetScript("OnShow", updateArrow)
	self.dateCatcher:SetScript("OnHide", function()
		down = false
		over = button:IsMouseOver() and true or false
		updateArrow()
	end)
	self:UpdateDateUI()
end

function UI:RequestRefresh()
	if self.refreshQueued then
		return
	end
	self.refreshQueued = true
	C_Timer.After(0.25, function()
		UI:Refresh()
	end)
end

function UI:OnCharactersChanged()
	if not ns.db then
		return
	end
	if self.charKey ~= ALL_KEY and not ns.db.chars[self.charKey] then
		self.charKey = ns.charKey
	end
	if self.frame then
		if self.dropdown and self.dropdown.GenerateMenu then
			self.dropdown:GenerateMenu()
		end
		self:Refresh()
	end
end

function UI:BuildDropdown(f)
	local function IsSelected(key)
		return UI.charKey == key
	end
	local function SetSelected(key)
		UI.charKey = key
		UI.page = 1
		UI:Refresh()
	end
	local dropdown = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
	dropdown:SetWidth(230)
	dropdown:SetPoint("TOPLEFT", 70, -29)
	if dropdown.SetDefaultText then
		dropdown:SetDefaultText(CHARACTER or "Character")
	end
	dropdown:SetupMenu(function(_, root)
		root:CreateRadio("All Characters", IsSelected, SetSelected, ALL_KEY)
		for _, entry in ipairs(ns.GetCharList()) do
			local label = ClassColored(entry.name, entry.char.class) .. " " .. Hex(GREY) .. "(" .. entry.count .. ")|r"
			root:CreateRadio(label, IsSelected, SetSelected, entry.key)
		end
	end)
	self.dropdown = dropdown
end

local MESSAGE_SWAP, MESSAGE_HOLD, MESSAGE_FADE = 0.15, 5, 2

function UI.StepDataMessage(elapsed)
	local m = UI.dataMessage
	if not m or not m.phase then
		return
	end
	m.elapsed = m.elapsed + elapsed
	if m.phase == "out" then
		m.alpha = m.from * math.max(0, 1 - m.elapsed / MESSAGE_SWAP)
		if m.elapsed >= MESSAGE_SWAP then
			m.phase = "swap"
		end
	end
	if m.phase == "swap" then
		local pending = m.pending
		m.pending = nil
		m.text:SetText(pending.text)
		m.text:SetTextColor(pending.color[1], pending.color[2], pending.color[3])
		m.phase, m.elapsed, m.alpha = "in", 0, 0
	elseif m.phase == "in" then
		m.alpha = math.min(1, m.elapsed / MESSAGE_SWAP)
		if m.elapsed >= MESSAGE_SWAP then
			m.phase, m.elapsed, m.alpha = "hold", 0, 1
		end
	elseif m.phase == "hold" then
		m.alpha = 1
		if m.elapsed >= MESSAGE_HOLD then
			m.phase, m.elapsed = "fade", 0
		end
	elseif m.phase == "fade" then
		m.alpha = math.max(0, 1 - m.elapsed / MESSAGE_FADE)
		if m.elapsed >= MESSAGE_FADE then
			m.phase, m.alpha = nil, 0
			m.driver:SetScript("OnUpdate", nil)
		end
	end
	m.text:SetAlpha(m.alpha)
end

function UI:ShowDataMessage(text, color)
	local m = self.dataMessage
	m.pending = { text = text, color = color }
	if not m.phase then
		m.phase, m.elapsed, m.alpha = "swap", 0, 0
	elseif m.phase ~= "out" and m.phase ~= "swap" then
		m.phase, m.elapsed, m.from = "out", 0, m.alpha
	end
	m.driver:SetScript("OnUpdate", function(_, elapsed)
		UI.StepDataMessage(elapsed)
	end)
end

function UI:BuildDataPanel(f)
	local panel = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	panel:SetPoint("TOPLEFT", 4, -60)
	panel:SetPoint("BOTTOMRIGHT", -6, 5)
	panel:Hide()

	local title = Text(panel, "GameFontNormalLarge", "CENTER")
	title:SetPoint("TOP", 0, -46)
	title:SetText("Your roll data")

	local blurb = Text(panel, "GameFontHighlight", "CENTER")
	blurb:SetPoint("TOP", title, "BOTTOM", 0, -12)
	blurb:SetWidth(620)
	blurb:SetText("Export packs every character's rolls into one block of text you can keep as a backup or send to a friend.\nTo bring rolls in, paste a block into the box below and hit Import. Importing replaces everything you have saved.")

	local exportButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	exportButton:SetSize(150, 28)
	exportButton:SetPoint("TOP", -85, -138)
	exportButton:SetText("Export")

	local importButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	importButton:SetSize(150, 28)
	importButton:SetPoint("TOP", 85, -138)
	importButton:SetText("Import")

	local message = Text(panel, "GameFontNormal", "CENTER")
	message:SetPoint("TOP", 0, -180)
	message:SetWidth(700)
	message:SetAlpha(0)
	self.dataMessage = { text = message, driver = CreateFrame("Frame", nil, panel), alpha = 0 }

	local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	box:SetSize(620, 24)
	box:SetPoint("TOP", 0, -226)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	self.dataBox = box

	local hint = Text(panel, "GameFontDisableSmall", "CENTER")
	hint:SetPoint("TOP", box, "BOTTOM", 0, -8)
	hint:SetText("Ctrl+C copies, Ctrl+V pastes.")

	exportButton:SetScript("OnClick", function()
		local text, characters, rolls = ns.Data.Export()
		if not text then
			UI:ShowDataMessage("Nothing to export yet. Go roll on something first.", RED)
			return
		end
		box:SetText(text)
		box:SetCursorPosition(0)
		box:HighlightText()
		box:SetFocus()
		UI:ShowDataMessage("Exported " .. rolls .. (rolls == 1 and " roll" or " rolls") .. " from " .. characters
			.. (characters == 1 and " character" or " characters") .. ". Press Ctrl+C to copy it.", GOLD)
		Play("IG_CHARACTER_INFO_TAB")
	end)

	if StaticPopupDialogs then
		StaticPopupDialogs["ROLLSFOREVER_REPLACE"] = {
			text = "%s",
			button1 = "Replace",
			button2 = CANCEL or "Cancel",
			OnAccept = function()
				UI:ConfirmImport()
			end,
			OnCancel = function()
				UI.stagedImport = nil
			end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			showAlert = true,
		}
	end

	importButton:SetScript("OnClick", function()
		local ok, staged, characters, rolls = ns.Data.Check(box:GetText())
		Play("IG_CHARACTER_INFO_TAB")
		if not ok then
			UI:ShowDataMessage(staged, RED)
			return
		end
		UI.stagedImport = staged
		local warning = "This replaces ALL of your saved rolls with the " .. rolls .. (rolls == 1 and " roll" or " rolls")
			.. " from " .. characters .. (characters == 1 and " character" or " characters")
			.. " in this export.\n\nWhat you have now will be gone for good."
		if StaticPopup_Show and StaticPopupDialogs then
			StaticPopup_Show("ROLLSFOREVER_REPLACE", warning)
		else
			UI:ConfirmImport()
		end
	end)

	self.exportButton, self.importButton = exportButton, importButton
	self.dataPanel = panel
end

function UI:ConfirmImport()
	local staged = self.stagedImport
	self.stagedImport = nil
	if not staged then
		return
	end
	local rolls, characters = ns.Data.Replace(staged)
	self.dataBox:SetText("")
	self.dataBox:ClearFocus()
	self.charKey = ns.charKey
	self.page = 1
	self:ShowDataMessage("Done. Your data is now " .. rolls .. (rolls == 1 and " roll" or " rolls") .. " across "
		.. characters .. (characters == 1 and " character." or " characters."), GREEN)
	self:OnCharactersChanged()
end

function UI:SetView(view)
	local data = view == "data"
	self.view = data and "data" or "stats"
	self.dataPanel:SetShown(data)
	self.leftPanel:SetShown(not data)
	self.rightPanel:SetShown(not data)
	self.dropdown:SetShown(not data)
	self.dateButton:SetShown(not data)
	self.summary:SetShown(not data)
	if data and self.dateCatcher then
		self.dateCatcher:Hide()
	end
end

function UI:BuildTabs(f)
	local names = { "All Rolls", NEED or "Need", GREED or "Greed", "Data" }
	local filters = { "all", "need", "greed" }
	for i = 1, #names do
		local tab = CreateFrame("Button", "RollsForeverFrameTab" .. i, f, "PanelTabButtonTemplate")
		tab:SetID(i)
		tab:SetText(names[i])
		if i == 1 then
			tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 11, 2)
		end
		tab:SetScript("OnClick", function(self)
			PanelTemplates_SetTab(f, self:GetID())
			local filter = filters[self:GetID()]
			if filter then
				UI.filter = filter
				UI.page = 1
				UI:SetView("stats")
				UI:Refresh()
			else
				UI:SetView("data")
			end
			Play("IG_CHARACTER_INFO_TAB")
		end)
	end
	PanelTemplates_SetNumTabs(f, #names)
	PanelTemplates_SetTab(f, 1)
end

function UI:Build()
	if self.frame then
		return
	end
	local f = CreateFrame("Frame", "RollsForeverFrame", UIParent, "ButtonFrameTemplate")
	f:Hide()
	f:SetSize(FRAME_W, FRAME_H)
	local pos = ns.db.ui.pos
	if type(pos) == "table" and pos[1] then
		f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		f:SetPoint("CENTER", 0, 20)
	end
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		local point, _, relativePoint, x, y = frame:GetPoint(1)
		ns.db.ui.pos = { point, relativePoint, x, y }
	end)

	if f.SetTitle then
		f:SetTitle("Rolls Forever")
	end
	if f.SetPortraitToAsset then
		f:SetPortraitToAsset(MEDIA .. "Portrait.tga")
	end
	if ButtonFrameTemplate_HideButtonBar then
		ButtonFrameTemplate_HideButtonBar(f)
	end
	if f.Inset then
		f.Inset:Hide()
	end
	if UISpecialFrames then
		table.insert(UISpecialFrames, "RollsForeverFrame")
	end

	local titleHost = f.TitleContainer or f
	local powered = titleHost:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	powered:SetText("Visit us @ ageofauroria.apphub.au")
	powered:SetTextColor(0.55, 0.5, 0.42)
	powered:SetAlpha(0.7)
	if f.CloseButton then
		powered:SetPoint("RIGHT", f.CloseButton, "LEFT", -6, 0)
	else
		powered:SetPoint("TOPRIGHT", f, "TOPRIGHT", -32, -6)
	end
	self.poweredBy = powered

	self.frame = f
	self:BuildDropdown(f)
	self:BuildDateFilter(f)

	self.summary = Text(f, "GameFontHighlightSmall", "RIGHT")
	self.summary:SetPoint("TOPRIGHT", -16, -36)

	local left = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	left:SetPoint("TOPLEFT", 4, -60)
	left:SetPoint("BOTTOMLEFT", 4, 5)
	left:SetWidth(LEFT_W)
	self:BuildStatsPanel(left)

	local right = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 2, 0)
	right:SetPoint("BOTTOMRIGHT", -6, 5)
	self:BuildHistoryPanel(right)
	self.leftPanel, self.rightPanel = left, right
	self:BuildDataPanel(f)

	self:BuildTabs(f)

	f:SetScript("OnShow", function()
		Play("IG_CHARACTER_INFO_OPEN")
		UI:ApplyScale()
		UI:OnCharactersChanged()
	end)
	self:ApplyScale()
	f:SetScript("OnHide", function()
		Play("IG_CHARACTER_INFO_CLOSE")
		if UI.dateCatcher then
			UI.dateCatcher:Hide()
		end
	end)
end

function UI:ApplyScale()
	local f = self.frame
	if not f then
		return
	end
	local scale = tonumber(ns.db.ui.scale) or 1
	local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
	if screenW and screenH and screenW > 0 and screenH > 0 then
		local fit = math.min((screenW - 24) / FRAME_W, (screenH - 24) / (FRAME_H + TAB_H))
		if fit < scale then
			scale = fit
		end
	end
	if scale < 0.4 then
		scale = 0.4
	end
	f:SetScale(scale)
end

function UI:SetUserScale(scale)
	ns.db.ui.scale = scale
	self:ApplyScale()
end

function UI:Open(charKey)
	if not ns.db then
		return
	end
	self:Build()
	if charKey then
		self.charKey = charKey
		self.page = 1
	end
	if not self.charKey then
		self.charKey = ns.charKey
	end
	if self.frame:IsShown() then
		self:OnCharactersChanged()
	else
		self.frame:Show()
	end
end

function UI:Toggle()
	if self.frame and self.frame:IsShown() then
		self.frame:Hide()
	else
		self:Open()
	end
end

function UI:UpdateMinimapButton()
	local button = self.minimapButton
	if not button then
		return
	end
	local settings = ns.db.minimap
	if settings.hide then
		button:Hide()
		return
	end
	local angle = math.rad(settings.angle or 215)
	local radius = (Minimap:GetWidth() / 2) + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
	button:Show()
end

function UI:CreateMinimapButton()
	if self.minimapButton or not Minimap then
		return
	end
	local button = CreateFrame("Button", "RollsForeverMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("TOPLEFT", 7, -5)

	local icon = button:CreateTexture(nil, "ARTWORK")

	icon:SetSize(22, 22)
	icon:SetTexture(MEDIA .. "Minimap.tga")
	icon:SetPoint("CENTER", button, "TOPLEFT", 16, -16.5)

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function()
		UI:Toggle()
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Rolls Forever")
		GameTooltip:AddLine("Click to open. Drag to move.", 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local centerX, centerY = Minimap:GetCenter()
			local cursorX, cursorY = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			local angle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
			ns.db.minimap.angle = angle % 360
			UI:UpdateMinimapButton()
		end)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)

	self.minimapButton = button
	self:UpdateMinimapButton()
end

function UI:OnLogin()
	self.charKey = ns.charKey
	self:CreateMinimapButton()

	ns.On("DISPLAY_SIZE_CHANGED", function()
		UI:ApplyScale()
	end)
	ns.On("UI_SCALE_CHANGED", function()
		UI:ApplyScale()
	end)
end
