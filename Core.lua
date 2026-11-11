local ADDON, ns = ...

ns.VERSION = "1.0.2"
ns.AUTHOR = "Evanlet"
ns.SUPPORT = "support@apphub.au"
ns.WEBSITE = "ageofauroria.apphub.au"

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) or false
end
ns.IsSecret = IsSecret

function ns.Clean(v)
	if IsSecret(v) then
		return nil
	end
	return v
end

function ns.Now()
	return (GetServerTime and GetServerTime()) or time()
end

function ns.Print(msg)
	local frame = DEFAULT_CHAT_FRAME
	if frame and frame.AddMessage then
		frame:AddMessage("|cffffd100Rolls Forever:|r " .. tostring(msg))
	end
end

local LOG_MAX = 800

local function Repr(v, depth)
	if IsSecret(v) then
		return "<secret>"
	end
	if type(v) == "table" then
		if depth > 3 then
			return "{...}"
		end
		local parts = {}
		for k, val in pairs(v) do
			parts[#parts + 1] = tostring(k) .. "=" .. Repr(val, depth + 1)
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end

local function WriteLog(tag, ...)
	local log = ns.db.log
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = Repr((select(i, ...)), 0)
	end
	log[#log + 1] = date("%m-%d %H:%M:%S") .. " " .. tag .. " " .. table.concat(parts, " | ")
	if #log > LOG_MAX then
		local keep = {}
		for i = #log - LOG_MAX + 201, #log do
			keep[#keep + 1] = log[i]
		end
		ns.db.log = keep
	end
end

function ns.Debug(tag, ...)
	if ns.db and ns.db.debug then

		pcall(WriteLog, tag, ...)
	end
end

local frame = CreateFrame("Frame")
local handlers = {}
ns.missingEvents = {}

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}

		if not pcall(frame.RegisterEvent, frame, event) then
			ns.missingEvents[event] = true
		end
	end
	table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if list then
		for i = 1, #list do
			list[i](...)
		end
	end
end)

local function InitDB()
	if type(RollsForeverDB) ~= "table" then
		RollsForeverDB = {}
	end
	local db = RollsForeverDB
	db.schema = db.schema or 1
	db.chars = db.chars or {}
	db.log = db.log or {}
	db.ui = db.ui or {}
	db.minimap = db.minimap or { angle = 215 }
	if db.debug == nil then
		db.debug = false
	end
	ns.db = db
end

local function InitCharacter()
	local db = ns.db
	local guid = ns.Clean(UnitGUID("player"))
	local name, second = UnitName("player")
	if UnitFullName then
		local fullName, fullSecond = UnitFullName("player")
		name = ns.Clean(fullName) or name
		second = ns.Clean(fullSecond) or second
	end
	name = ns.Clean(name) or UNKNOWN or "Unknown"
	second = ns.Clean(second)

	local realm = GetRealmName and ns.Clean(GetRealmName()) or nil
	local realmNorm = GetNormalizedRealmName and ns.Clean(GetNormalizedRealmName()) or nil
	local key = guid or (name .. "-" .. tostring(realm))

	local char = db.chars[key]
	if not char then
		char = { rolls = {}, nextId = 1 }
		db.chars[key] = char
	end
	char.rolls = char.rolls or {}
	char.seen = char.seen or {}
	char.nextId = char.nextId or (#char.rolls + 1)
	char.name = name

	if second and second ~= "" and second ~= realm and second ~= realmNorm then
		char.surname = second
	else
		char.surname = nil
	end
	char.realm = realm
	local _, classFile = UnitClass("player")
	char.class = ns.Clean(classFile)
	char.level = UnitLevel and ns.Clean(UnitLevel("player")) or nil
	char.lastSeen = ns.Now()

	local now = ns.Now()
	for lhKey, seen in pairs(char.seen) do
		if type(seen) ~= "table" or (now - (seen.t or 0)) > 43200 then
			char.seen[lhKey] = nil
		end
	end

	ns.charKey = key
	ns.char = char
	ns.Debug("LOGIN", "guid", guid, "UnitName", name, second, "realm", realm, realmNorm,
		"build", (GetBuildInfo and select(4, GetBuildInfo())), "project", WOW_PROJECT_ID)
end

function ns.CharDisplayName(char)
	if not char then
		return UNKNOWN or "Unknown"
	end
	if char.surname then
		return char.name .. " " .. char.surname
	end
	return char.name or (UNKNOWN or "Unknown")
end

function ns.GetCharList()
	local list = {}
	for key, char in pairs(ns.db.chars) do
		list[#list + 1] = { key = key, char = char, name = ns.CharDisplayName(char), count = #(char.rolls or {}) }
	end
	table.sort(list, function(a, b)
		if (a.key == ns.charKey) ~= (b.key == ns.charKey) then
			return a.key == ns.charKey
		end
		return a.name < b.name
	end)
	return list
end

function ns.FireDataChanged()
	local ui = ns.UI
	if ui and ui.frame and ui.frame:IsShown() then
		ui:RequestRefresh()
	end
end

local TEST_KEY = "RollsForever-Sample"

local SAMPLE_ITEMS = {
	{ 7717, "Ravager", 3 }, { 7718, "Herod's Shoulder", 3 }, { 7719, "Raging Berserker's Helm", 3 },
	{ 7720, "Whitemane's Chapeau", 3 }, { 7721, "Hand of Righteousness", 3 }, { 7722, "Triune Amulet", 3 },
	{ 7723, "Mograine's Might", 3 }, { 7724, "Gauntlets of Divinity", 3 }, { 7726, "Aegis of the Scarlet Commander", 3 },
	{ 7711, "Robe of Doan", 3 }, { 7712, "Mantle of Doan", 3 }, { 7713, "Illusionary Rod", 3 },
	{ 7714, "Hypnotic Blade", 3 }, { 10330, "Scarlet Leggings", 3 },
}
local SAMPLE_NAMES = {
	{ "Thorgrim", "WARRIOR" }, { "Sylvara", "HUNTER" }, { "Bexley", "MAGE" }, { "Morwen", "PRIEST" },
	{ "Dunhollow", "PALADIN" }, { "Quillfeather", "DRUID" }, { "Vexa", "ROGUE" }, { "Gristle", "WARLOCK" },
}
local QUALITY_HEX = { [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee" }

function ns.CreateSampleData()
	local char = { rolls = {}, seen = {}, nextId = 1, name = "Sample", surname = "Character", class = "PALADIN", test = true }
	local now = ns.Now()
	local count = 137
	for i = 1, count do
		local item = SAMPLE_ITEMS[math.random(#SAMPLE_ITEMS)]
		local chance = math.random(100)
		local ty = (chance <= 22 and "need") or (chance <= 88 and "greed") or "pass"
		local rec = {
			id = char.nextId,
			t = now - (count - i) * 5400 - math.random(0, 1800),
			item = item[1], n = item[2], q = item[3],
			link = "|c" .. QUALITY_HEX[item[3]] .. "|Hitem:" .. item[1] .. "::::::::60:::::|h[" .. item[2] .. "]|h|r",
			type = ty, zone = "Scarlet Monastery", grp = 5, src = "sample",
		}
		char.nextId = char.nextId + 1
		local rivals = (ty == "need") and math.random(0, 2) or math.random(2, 4)
		local other = SAMPLE_NAMES[math.random(#SAMPLE_NAMES)]
		if ty == "pass" then
			rec.won = false
			rec.wn, rec.wc, rec.wr, rec.wt = other[1], other[2], math.random(100), "greed"
		else
			rec.roll = math.random(100)
			local best = 0
			for _ = 1, rivals do
				best = math.max(best, math.random(100))
			end
			rec.exp = 1 / (rivals + 1)
			if ty == "need" then
				rec.cn, rec.cg, rec.cp = rivals + 1, 0, 4 - rivals
			else
				rec.cn, rec.cg, rec.cp = 0, rivals + 1, 4 - rivals
			end
			if rec.roll >= best then
				rec.won = true
				rec.wn, rec.wc, rec.wr, rec.wt = "Sample Character", "PALADIN", rec.roll, ty
			else
				rec.won = false
				rec.wn, rec.wc, rec.wr, rec.wt = other[1], other[2], best, ty
			end
		end
		char.rolls[#char.rolls + 1] = rec
	end
	ns.db.chars[TEST_KEY] = char
	return TEST_KEY
end

function ns.ClearSampleData()
	ns.db.chars[TEST_KEY] = nil
end

local function ToggleWindow()
	if ns.UI then
		ns.UI:Toggle()
	end
end
ns.ToggleWindow = ToggleWindow

local function HandleSlash(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "" then
		ToggleWindow()
	elseif msg == "debug" then
		ns.db.debug = not ns.db.debug
		ns.Print("Debug log " .. (ns.db.debug and "on" or "off") .. ".")
	elseif msg == "test" then
		local key = ns.CreateSampleData()
		if ns.UI then
			ns.UI:Open(key)
		end
		ns.Print("Sample rolls added. Type /rolls test clear to get rid of them.")
	elseif msg == "test clear" then
		ns.ClearSampleData()
		if ns.UI then
			ns.UI:OnCharactersChanged()
		end
		ns.Print("Sample rolls removed.")
	elseif msg == "minimap" then
		ns.db.minimap.hide = not ns.db.minimap.hide
		if ns.UI then
			ns.UI:UpdateMinimapButton()
		end
		ns.Print("Minimap button " .. (ns.db.minimap.hide and "hidden" or "shown") .. ".")
	elseif msg == "scale" or msg:find("^scale%s") then
		local value = tonumber(msg:match("^scale%s+([%d%.]+)$"))
		if value and value >= 0.6 and value <= 1.5 then
			ns.db.ui.scale = value
			if ns.UI then
				ns.UI:SetUserScale(value)
			end
			ns.Print("Window scale set to " .. value .. ". It'll still shrink if it doesn't fit your screen.")
		else
			ns.Print("Window scale is " .. (ns.db.ui.scale or 1) .. ". Change it with /rolls scale 0.9 (anything from 0.6 to 1.5).")
		end
	elseif msg == "cloud" then
		ns.Print(ns.Cloud and ns.Cloud.Status() or "Cloud sync isn't available.")
	elseif msg == "about" then
		ns.Print("v" .. ns.VERSION .. " by " .. ns.AUTHOR)
		ns.Print("Need a hand? " .. ns.SUPPORT)
		ns.Print("More at " .. ns.WEBSITE)
	elseif msg == "reset confirm" then
		if ns.char then
			ns.char.rolls = {}
			ns.char.seen = {}
			ns.char.nextId = 1
			ns.FireDataChanged()
			ns.Print("Wiped every roll saved for " .. ns.CharDisplayName(ns.char) .. ".")
		end
	elseif msg == "reset" then
		ns.Print("This wipes every roll saved for this character. Type /rolls reset confirm if you're sure.")
	else
		ns.Print("Commands: /rolls (open), /rolls scale 0.6-1.5, /rolls test, /rolls test clear, /rolls minimap, /rolls debug, /rolls reset, /rolls about")
	end
end

SLASH_ROLLSFOREVER1 = "/rolls"
SLASH_ROLLSFOREVER2 = "/rollsforever"
SLASH_ROLLSFOREVER3 = "/rf"
SlashCmdList["ROLLSFOREVER"] = HandleSlash

function RollsForever_OnAddonCompartmentClick()
	ToggleWindow()
end

function RollsForever_OnAddonCompartmentEnter(_, button)
	if GameTooltip and button then
		GameTooltip:SetOwner(button, "ANCHOR_LEFT")
		GameTooltip:SetText("Rolls Forever")
		GameTooltip:AddLine("Click to see how your rolls have been going.", 1, 1, 1, true)
		GameTooltip:Show()
	end
end

function RollsForever_OnAddonCompartmentLeave()
	if GameTooltip then
		GameTooltip:Hide()
	end
end

ns.On("ADDON_LOADED", function(name)
	if name == ADDON then
		InitDB()
	end
end)

ns.On("PLAYER_LOGIN", function()
	if not ns.db then
		InitDB()
	end
	InitCharacter()
	if ns.Capture then
		ns.Capture.Enable()
	end
	if ns.UI then
		ns.UI:OnLogin()
	end
end)
