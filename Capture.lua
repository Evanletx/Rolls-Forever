local ADDON, ns = ...

local Capture = {}
ns.Capture = Capture

local IsSecret, Clean, Debug = ns.IsSecret, ns.Clean, ns.Debug

local ROLLTYPE = { [0] = "pass", [1] = "need", [2] = "greed", [3] = "de", [4] = "tmog" }

local STATE = (Enum and Enum.EncounterLootDropRollState) or {}
local ST_NEED = STATE.NeedMainSpec or 0
local ST_NEEDOFF = STATE.NeedOffSpec or 1
local ST_TMOG = STATE.Transmog or 2
local ST_GREED = STATE.Greed or 3
local ST_PASS = STATE.Pass or 5

local KEEP_CLOSED = 180
local GIVE_UP = 900

local pending = {}
Capture.pending = pending

local function StateToType(state)
	if state == ST_NEED then
		return "need", false
	elseif state == ST_NEEDOFF then
		return "need", true
	elseif state == ST_TMOG then
		return "tmog", false
	elseif state == ST_GREED then
		return "greed", false
	elseif state == ST_PASS then
		return "pass", false
	end
	return nil, false
end

local function Rank(rollType, offSpec)
	if rollType == "need" then
		return offSpec and 2 or 1
	elseif rollType == "tmog" then
		return 3
	elseif rollType == "greed" or rollType == "de" then
		return 4
	end
	return nil
end

local function ItemID(link)
	if IsSecret(link) or type(link) ~= "string" then
		return nil
	end
	return tonumber(link:match("item:(%d+)"))
end

local function ExtractLink(text)
	return text:match("(|c.-|Hitem:.-|h%[.-%]|h|r)") or text:match("(|Hitem:.-|h%[.-%]|h)") or text
end

local function Where()
	local zone, inst
	if GetInstanceInfo then
		local name, instType, _, _, _, _, _, instID = GetInstanceInfo()
		name, instType, instID = Clean(name), Clean(instType), Clean(instID)
		if instType and instType ~= "none" then
			zone, inst = name, instID
		end
	end
	if not zone and GetRealZoneText then
		zone = Clean(GetRealZoneText())
	end
	return zone, inst
end

local function NewPending(link, src)
	local P = {
		link = link,
		itemID = ItemID(link),
		born = GetTime(),
		t = ns.Now(),
		src = src,
		sel = {},
	}
	P.zone, P.inst = Where()
	P.grp = GetNumGroupMembers and Clean(GetNumGroupMembers()) or nil
	pending[#pending + 1] = P
	return P
end

local function FindByRollID(rollID)
	for i = #pending, 1, -1 do
		if pending[i].rollID == rollID then
			return pending[i]
		end
	end
end

local function FindByLH(lhKey)
	for i = #pending, 1, -1 do
		if pending[i].lhKey == lhKey then
			return pending[i]
		end
	end
end

local function FindByItem(itemID, withoutLH, withoutRollID, openOnly)
	local closed
	for i = 1, #pending do
		local P = pending[i]
		if P.itemID == itemID and not (withoutLH and P.lhKey) and not (withoutRollID and P.rollID) then
			if not P.final then
				return P
			end
			closed = P
		end
	end
	if openOnly then
		return nil
	end
	return closed
end

local function FindRecord(char, id)
	local rolls = char.rolls
	for i = #rolls, math.max(1, #rolls - 500), -1 do
		if rolls[i].id == id then
			return rolls[i]
		end
	end
end

local selfNames = {}

local function AddSelfName(name)
	if type(name) == "string" and not IsSecret(name) and name ~= "" then
		selfNames[name] = true
	end
end

local function BuildSelfNames()
	local function addPair(first, second)
		first, second = Clean(first), Clean(second)
		AddSelfName(first)
		if first and second and second ~= "" then
			AddSelfName(first .. " " .. second)
			AddSelfName(first .. "-" .. second)
		end
	end
	addPair(UnitName("player"))
	if UnitFullName then
		addPair(UnitFullName("player"))
	end
	if UnitNameUnmodified then
		addPair(UnitNameUnmodified("player"))
	end
	if GetUnitName then
		AddSelfName(Clean(GetUnitName("player", true)))
		AddSelfName(Clean(GetUnitName("player", false)))
	end
	AddSelfName(YOU)
end

local function IsMe(name)
	return name ~= nil and selfNames[name] == true
end

local function MyName()
	return ns.CharDisplayName(ns.char)
end

local function Commit(P)
	local char = ns.char
	if not char or P.skip or not P.itemID then
		return
	end
	local rec = P.rec
	local isNew = rec == nil
	if isNew then
		rec = { id = char.nextId, t = P.t }
		char.nextId = char.nextId + 1
		char.rolls[#char.rolls + 1] = rec
		P.rec = rec
	end
	if not P.quality and C_Item and C_Item.GetItemInfo then
		local ok, _, _, quality = pcall(C_Item.GetItemInfo, P.link)
		if ok then
			P.quality = Clean(quality)
		end
	end
	if P.won == nil and P.choice == "pass" then
		P.won = false
	end
	rec.link = P.link
	rec.item = P.itemID
	rec.n = P.name or P.link:match("%[(.-)%]")
	rec.q = P.quality
	rec.type = P.choice
	rec.off = P.off or nil
	rec.roll = P.roll
	rec.won = P.won
	rec.wn, rec.wc, rec.wr, rec.wt = P.winner, P.winnerClass, P.winnerRoll, P.winnerType
	rec.allp = P.allPassed or nil
	rec.cn, rec.cg, rec.cp = P.cn, P.cg, P.cp
	rec.exp = P.exp
	rec.zone, rec.inst, rec.grp = P.zone, P.inst, P.grp
	rec.src = P.src
	rec.inf = P.inferred or nil
	if P.lhKey then
		char.seen[P.lhKey] = { id = rec.id, item = P.itemID, t = ns.Now() }
	end
	Debug("COMMIT", isNew and "new" or "update", rec)
	ns.FireDataChanged()
end

local function Finalize(P)
	if not P.final then
		P.final = true
		P.closed = GetTime()
	end
	Commit(P)
end

local function InferAndFinalize(P)
	if P.final then
		return
	end
	if P.won == nil then
		P.won = false
		P.inferred = true
	end
	Finalize(P)
end

local function PendingFromRecord(rec, lhKey)
	local P = {
		link = rec.link, itemID = rec.item, name = rec.n, quality = rec.q,
		born = GetTime(), t = rec.t, rec = rec, lhKey = lhKey, src = rec.src, sel = {},
		choice = rec.type, off = rec.off, roll = rec.roll, won = rec.won,
		winner = rec.wn, winnerClass = rec.wc, winnerRoll = rec.wr, winnerType = rec.wt,
		allPassed = rec.allp, cn = rec.cn, cg = rec.cg, cp = rec.cp, exp = rec.exp,
		zone = rec.zone, inst = rec.inst, grp = rec.grp,
		final = true, closed = GetTime(),
	}
	pending[#pending + 1] = P
	return P
end

local function Expectation(myRank, ranks)
	if not myRank then
		return nil
	end
	local same = 0
	for i = 1, #ranks do
		if ranks[i] < myRank then
			return 0
		elseif ranks[i] == myRank then
			same = same + 1
		end
	end
	if same > 0 then
		return 1 / same
	end
	return nil
end

local function AbsorbDrop(P, info)
	local cn, cg, cp, ranks = 0, 0, 0, {}
	local mine
	for _, r in ipairs(info.rollInfos or {}) do
		local rollType, offSpec = StateToType(r.state)
		if rollType == "need" then
			cn = cn + 1
		elseif rollType == "pass" then
			cp = cp + 1
		elseif rollType then
			cg = cg + 1
		end
		local rank = Rank(rollType, offSpec)
		if rank then
			ranks[#ranks + 1] = rank
		end
		if r.isSelf then
			mine = r
		end
	end
	P.cn, P.cg, P.cp = cn, cg, cp
	P.src = "history"

	if mine then
		P.eligible = true
		local rollType, offSpec = StateToType(mine.state)
		if rollType then
			P.choice, P.off = rollType, offSpec or nil
		end
		if mine.roll then
			P.roll = mine.roll
		end
	end

	local done = false
	if info.winner then
		local w = info.winner
		P.winner, P.winnerClass, P.winnerRoll = w.playerName, w.playerClass, w.roll
		P.winnerType = StateToType(w.state)
		P.won = w.isSelf and true or false
		done = true
	elseif info.allPassed then
		P.allPassed, P.won = true, false
		done = true
	end

	local expectation = Expectation(Rank(P.choice, P.off), ranks)
	if expectation then
		P.exp = expectation
	end
	return done
end

function Capture.OnDrop(encounterID, lootListKey, info, backfill)
	local char = ns.char
	if not char or encounterID == nil or lootListKey == nil or IsSecret(encounterID) or IsSecret(lootListKey) then
		return
	end
	if not info then
		local ok, result = pcall(C_LootHistory.GetSortedInfoForDrop, encounterID, lootListKey)
		if not ok or type(result) ~= "table" then
			Debug("HISTORY_FAIL", encounterID, lootListKey, result)
			return
		end
		info = result
		Debug("HISTORY_DROP", encounterID, lootListKey, info)
	end

	local link = Clean(info.itemHyperlink)
	local itemID = ItemID(link)
	if not itemID then
		return
	end
	local finished = (info.winner ~= nil) or (info.allPassed and true or false)
	local lhKey = tostring(encounterID) .. ":" .. tostring(lootListKey)

	local P = FindByLH(lhKey)
	if P and P.itemID ~= itemID then
		P.lhKey = nil
		P = nil
	end

	if not P then

		local seen = char.seen[lhKey]
		if seen and seen.item == itemID then
			local liveRoll = FindByItem(itemID, true, false, true)
			local rec = (finished and not liveRoll) and FindRecord(char, seen.id) or nil
			if rec and backfill then
				return
			elseif rec then
				P = PendingFromRecord(rec, lhKey)
			else
				char.seen[lhKey] = nil
			end
		end
	end

	if not P then

		P = FindByItem(itemID, true)
		if P then
			P.lhKey = lhKey
		end
	end

	if not P then
		P = NewPending(link, backfill and "history-backfill" or "history")
		P.lhKey = lhKey
	end

	local ok, done = pcall(AbsorbDrop, P, info)
	if not ok then
		Debug("HISTORY_ERROR", lhKey, done)
		return
	end
	if backfill and P.src == "history" and not P.rollID and not P.rec then
		P.src = "history-backfill"
	end

	if done then

		if not P.eligible and not P.rollID and not P.choice and not P.rec then
			P.skip, P.final, P.closed = true, true, GetTime()
			return
		end
		Finalize(P)
	elseif P.rec then
		Commit(P)
	end
end

function Capture.ScanHistory(onlyEncounter)
	if not (C_LootHistory and C_LootHistory.GetAllEncounterInfos and C_LootHistory.GetSortedDropsForEncounter) then
		return
	end
	local ok, encounters = pcall(C_LootHistory.GetAllEncounterInfos)
	if not ok or type(encounters) ~= "table" then
		return
	end
	for _, encounter in ipairs(encounters) do
		local encounterID = Clean(encounter.encounterID)
		if encounterID and (not onlyEncounter or onlyEncounter == encounterID) then
			Debug("HISTORY_ENCOUNTER", encounter)
			local ok2, drops = pcall(C_LootHistory.GetSortedDropsForEncounter, encounterID)
			if ok2 and type(drops) == "table" then
				for _, drop in ipairs(drops) do
					local key = Clean(drop.lootListKey)
					if key then
						Capture.OnDrop(encounterID, key, drop, true)
					end
				end
			end
		end
	end
end

local function FormatToPattern(fmt, lazy)
	local out, order = {}, {}
	local i, n, argIndex = 1, #fmt, 0
	local function capture(kind, index)
		order[#order + 1] = index
		if kind == "d" then
			out[#out + 1] = "(%d+)"
		elseif lazy and lazy[index] then
			out[#out + 1] = "(.-)"
		else
			out[#out + 1] = "(.+)"
		end
	end
	while i <= n do
		local c = fmt:sub(i, i)
		if c == "%" then
			local _, stop, position, kind = fmt:find("^%%(%d+)%$([sd])", i)
			if stop then
				capture(kind, tonumber(position))
				i = stop + 1
			else
				local nextChar = fmt:sub(i + 1, i + 1)
				if nextChar == "s" or nextChar == "d" then
					argIndex = argIndex + 1
					capture(nextChar, argIndex)
					i = i + 2
				elseif nextChar == "%" then
					out[#out + 1] = "%%"
					i = i + 2
				else
					out[#out + 1] = "%%"
					i = i + 1
				end
			end
		else
			if c:find("[%^%$%(%)%.%[%]%*%+%-%?]") then
				out[#out + 1] = "%" .. c
			else
				out[#out + 1] = c
			end
			i = i + 1
		end
	end
	return "^" .. table.concat(out) .. "$", order
end
Capture.FormatToPattern = FormatToPattern

local CHAT_SPECS = {
	{ "LOOT_ROLL_YOU_WON_NO_SPAM_NEED", kind = "won", me = true, type = "need", args = { "roll", "link" } },
	{ "LOOT_ROLL_YOU_WON_NO_SPAM_NEED_OFF_SPEC", kind = "won", me = true, type = "need", off = true, args = { "roll", "link" } },
	{ "LOOT_ROLL_YOU_WON_NO_SPAM_GREED", kind = "won", me = true, type = "greed", args = { "roll", "link" } },
	{ "LOOT_ROLL_YOU_WON_NO_SPAM_DE", kind = "won", me = true, type = "de", args = { "roll", "link" } },
	{ "LOOT_ROLL_YOU_WON_NO_SPAM_TRANSMOG", kind = "won", me = true, type = "tmog", args = { "roll", "link" } },
	{ "LOOT_ROLL_YOU_WON", kind = "won", me = true, args = { "link" } },
	{ "LOOT_ROLL_LOST_ROLL", kind = "lost", me = true, args = { "typeText", "roll", "link" } },
	{ "LOOT_ROLL_NEED_SELF", kind = "select", me = true, type = "need", args = { "link" } },
	{ "LOOT_ROLL_GREED_SELF", kind = "select", me = true, type = "greed", args = { "link" } },
	{ "LOOT_ROLL_DISENCHANT_SELF", kind = "select", me = true, type = "de", args = { "link" } },
	{ "LOOT_ROLL_PASSED_SELF_AUTO", kind = "select", me = true, type = "pass", args = { "link" } },
	{ "LOOT_ROLL_PASSED_SELF", kind = "select", me = true, type = "pass", args = { "link" } },

	{ "LOOT_ROLL_WON_NO_SPAM_NEED", kind = "won", type = "need", args = { "player", "roll", "link" } },
	{ "LOOT_ROLL_WON_NO_SPAM_NEED_OFF_SPEC", kind = "won", type = "need", off = true, args = { "player", "roll", "link" } },
	{ "LOOT_ROLL_WON_NO_SPAM_GREED", kind = "won", type = "greed", args = { "player", "roll", "link" } },
	{ "LOOT_ROLL_WON_NO_SPAM_DE", kind = "won", type = "de", args = { "player", "roll", "link" } },
	{ "LOOT_ROLL_WON_NO_SPAM_TRANSMOGRIFICATION", kind = "won", type = "tmog", args = { "player", "roll", "link" } },
	{ "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS", kind = "rolled", type = "need", args = { "roll", "link", "player" } },
	{ "LOOT_ROLL_ROLLED_NEED", kind = "rolled", type = "need", args = { "roll", "link", "player" } },
	{ "LOOT_ROLL_ROLLED_GREED", kind = "rolled", type = "greed", args = { "roll", "link", "player" } },
	{ "LOOT_ROLL_ROLLED_DE", kind = "rolled", type = "de", args = { "roll", "link", "player" } },
	{ "LOOT_ROLL_ROLLED_TRANSMOG", kind = "rolled", type = "tmog", args = { "roll", "link", "player" } },
	{ "LOOT_ROLL_ALL_PASSED", kind = "allpassed", args = { "link" } },
	{ "LOOT_ROLL_NEED", kind = "select", type = "need", args = { "player", "link" } },
	{ "LOOT_ROLL_GREED", kind = "select", type = "greed", args = { "player", "link" } },
	{ "LOOT_ROLL_DISENCHANT", kind = "select", type = "de", args = { "player", "link" } },
	{ "LOOT_ROLL_PASSED_AUTO", kind = "select", type = "pass", args = { "player", "link" } },
	{ "LOOT_ROLL_PASSED_AUTO_FEMALE", kind = "select", type = "pass", args = { "player", "link" } },
	{ "LOOT_ROLL_PASSED", kind = "select", type = "pass", args = { "player", "link" } },
	{ "LOOT_ROLL_WON", kind = "won", args = { "player", "link" } },
	{ "LOOT_ROLL_STARTED", kind = "started", args = { "link" } },
}

local chatPatterns = {}

local function BuildChatPatterns()
	chatPatterns = {}
	local seenFormats = {}
	for _, spec in ipairs(CHAT_SPECS) do
		local fmt = _G[spec[1]]
		if type(fmt) == "string" and not seenFormats[fmt] then
			seenFormats[fmt] = true
			local names, lazy = {}, {}

			if fmt:find("lootHistory:%", 1, true) then
				names[1] = "history"
			end
			for _, name in ipairs(spec.args) do
				names[#names + 1] = name
				if name == "player" or name == "typeText" then
					lazy[#names] = true
				end
			end
			local pattern, order = FormatToPattern(fmt, lazy)
			chatPatterns[#chatPatterns + 1] = { spec = spec, pattern = pattern, order = order, names = names }
		end
	end
end

function Capture.Parse(text)
	for i = 1, #chatPatterns do
		local entry = chatPatterns[i]
		local captures = { text:match(entry.pattern) }
		if captures[1] then
			local spec = entry.spec
			local m = { kind = spec.kind, me = spec.me, type = spec.type, off = spec.off, global = spec[1] }
			for captureIndex, argIndex in ipairs(entry.order) do
				local name = entry.names[argIndex]
				if name then
					m[name] = captures[captureIndex]
				end
			end
			m.roll = tonumber(m.roll)
			if m.link then
				m.link = ExtractLink(m.link)
			end
			return m
		end
	end
end

local function TypeFromText(text)
	if not text then
		return nil
	end
	local lowered = text:lower()
	if NEED and lowered == NEED:lower() then
		return "need"
	elseif GREED and lowered == GREED:lower() then
		return "greed"
	elseif ROLL_DISENCHANT and lowered == ROLL_DISENCHANT:lower() then
		return "de"
	elseif TRANSMOGRIFICATION and lowered == TRANSMOGRIFICATION:lower() then
		return "tmog"
	end
end

local function CountFromChat(P)
	if P.src == "history" or P.src == "history-backfill" then
		return
	end
	local cn, cg, cp, ranks, any = 0, 0, 0, {}, false
	local function add(rollType, offSpec)
		if rollType == "need" then
			cn = cn + 1
		elseif rollType == "pass" then
			cp = cp + 1
		elseif rollType then
			cg = cg + 1
		end
		local rank = Rank(rollType, offSpec)
		if rank then
			ranks[#ranks + 1] = rank
		end
	end
	for _, rollType in pairs(P.sel) do
		add(rollType)
		any = true
	end
	if not any then
		return
	end
	add(P.choice, P.off)
	P.cn, P.cg, P.cp = cn, cg, cp
	local expectation = Expectation(Rank(P.choice, P.off), ranks)
	if expectation then
		P.exp = expectation
	end
end

function Capture.OnChat(text)
	if IsSecret(text) or type(text) ~= "string" then
		return
	end
	local m = Capture.Parse(text)
	if not m then
		if text:find("lootHistory", 1, true) then
			Debug("CHAT_UNMATCHED", text)
		end
		return
	end
	Debug("CHAT", m.global, text)

	local itemID = ItemID(m.link)
	if not itemID then
		return
	end
	local me = m.me or IsMe(m.player)

	local P = FindByItem(itemID)
	if not P then
		if not me then
			return
		end
		P = NewPending(m.link, "chat")
	end
	if not P.src then
		P.src = "chat"
	end

	if m.kind == "select" then
		if me then
			P.choice, P.off = m.type, m.off or nil
		elseif m.player then
			P.sel[m.player] = m.type
		end
	elseif m.kind == "rolled" then
		if me then
			P.choice, P.roll = m.type, m.roll
		elseif m.player then
			P.sel[m.player] = m.type
			P.rolls = P.rolls or {}
			P.rolls[m.player] = m.roll
		end
	elseif m.kind == "lost" then
		P.choice = TypeFromText(m.typeText) or P.choice
		P.roll = m.roll or P.roll
		P.won = false
		P.finalHint = true
	elseif m.kind == "won" then
		if me then
			P.won = true
			P.choice = m.type or P.choice
			if m.off then
				P.off = true
			end
			P.roll = m.roll or P.roll
			P.winner, P.winnerClass = MyName(), ns.char and ns.char.class or nil
			P.winnerRoll, P.winnerType = P.roll, P.choice
		else
			P.won = false
			P.winner = m.player
			P.winnerRoll = m.roll or (P.rolls and P.rolls[m.player]) or P.winnerRoll
			P.winnerType = m.type or P.sel[m.player] or P.winnerType
		end
		P.finalHint = true
	elseif m.kind == "allpassed" then
		P.allPassed, P.won = true, false
		P.finalHint = true
	end

	CountFromChat(P)

	if P.finalHint or P.final then
		Finalize(P)
	end
end

local function StartRoll(rollID, lootHandle, rollTime)
	rollID = Clean(rollID)
	if not rollID or FindByRollID(rollID) then
		return
	end
	local link
	if GetLootRollItemLink then
		local ok, result = pcall(GetLootRollItemLink, rollID)
		if ok then
			link = Clean(result)
		end
	end
	local itemID = ItemID(link)
	if not itemID then
		Debug("ROLL_NO_LINK", rollID, link)
		return
	end

	local P = FindByItem(itemID, false, true, true)
	if P and (GetTime() - P.born) > 30 then
		P = nil
	end
	if not P then
		P = NewPending(link, "roll")
	end
	P.rollID = rollID
	P.handle = Clean(lootHandle)

	rollTime = Clean(rollTime)
	if type(rollTime) == "number" and rollTime > 0 then
		local seconds = (rollTime > 1000) and (rollTime / 1000) or rollTime
		P.giveUp = seconds + 45
	end
	if GetLootRollItemInfo then
		local ok, _, name, _, quality, _, canNeed = pcall(GetLootRollItemInfo, rollID)
		if ok then
			P.name = Clean(name) or P.name
			P.quality = Clean(quality) or P.quality
			P.canNeed = Clean(canNeed) and true or false
		end
	end
end

local function OnRollChoice(rollID, rollType)
	rollID, rollType = Clean(rollID), Clean(rollType)
	if not rollID then
		return
	end
	if not FindByRollID(rollID) then
		StartRoll(rollID)
	end
	local P = FindByRollID(rollID)
	Debug("ROLL_CHOICE", rollID, rollType, P and P.link)
	if P and ROLLTYPE[rollType] and not P.final then
		P.choice = ROLLTYPE[rollType]
	end
end

local function OnNeedRoll(rollID, roll)
	local P = FindByRollID(Clean(rollID))
	roll = Clean(roll)
	if P and roll then
		P.roll = roll
		P.choice = P.choice or "need"
		if P.rec then
			Commit(P)
		end
	end
end

local function OnRollWon(itemLink, _, rollType, roll)
	local link = Clean(itemLink)
	local itemID = ItemID(link)
	if not itemID then
		return
	end
	local P = FindByItem(itemID)
	if not P then
		P = NewPending(link, "roll")
	end
	rollType, roll = Clean(rollType), Clean(roll)
	P.won = true
	P.inferred = nil
	P.choice = ROLLTYPE[rollType] or P.choice
	if type(roll) == "number" and roll > 0 then
		P.roll = roll
	end
	P.winner, P.winnerClass = MyName(), ns.char and ns.char.class or nil
	P.winnerRoll, P.winnerType = P.roll, P.choice
	Finalize(P)
end

local function OnRollsComplete(lootHandle)
	lootHandle = Clean(lootHandle)
	if lootHandle == nil then
		return
	end

	C_Timer.After(6, function()
		for i = 1, #pending do
			local P = pending[i]
			if P.handle == lootHandle and not P.final then
				InferAndFinalize(P)
			end
		end
	end)
end

function Capture.Sweep()
	local now = GetTime()
	for i = #pending, 1, -1 do
		local P = pending[i]
		if P.final then
			if now - (P.closed or now) > KEEP_CLOSED then
				table.remove(pending, i)
			end
		elseif now - P.born > (P.giveUp or GIVE_UP) then
			if P.choice or P.rollID then
				InferAndFinalize(P)
			else
				table.remove(pending, i)
			end
		end
	end
end

local function Rehydrate()
	if GetActiveLootRollIDs then
		local ok, ids = pcall(GetActiveLootRollIDs)
		if ok and type(ids) == "table" then
			for _, rollID in ipairs(ids) do
				StartRoll(rollID)
			end
		end
	end
	C_Timer.After(3, function()
		Capture.ScanHistory()
	end)
end

local enabled = false

function Capture.Enable()
	if enabled then
		return
	end
	enabled = true
	BuildSelfNames()
	BuildChatPatterns()

	ns.On("START_LOOT_ROLL", function(rollID, rollTime, lootHandle)
		Debug("START_LOOT_ROLL", rollID, rollTime, lootHandle)
		StartRoll(rollID, lootHandle, rollTime)
	end)
	ns.On("CANCEL_LOOT_ROLL", function(rollID)
		Debug("CANCEL_LOOT_ROLL", rollID)
	end)
	ns.On("CONFIRM_LOOT_ROLL", function(rollID, rollType, reason)
		Debug("CONFIRM_LOOT_ROLL", rollID, rollType, reason)
	end)
	ns.On("MAIN_SPEC_NEED_ROLL", function(rollID, roll, isWinning)
		Debug("MAIN_SPEC_NEED_ROLL", rollID, roll, isWinning)
		OnNeedRoll(rollID, roll)
	end)
	ns.On("LOOT_ITEM_ROLL_WON", function(itemLink, quantity, rollType, roll, upgraded)
		Debug("LOOT_ITEM_ROLL_WON", itemLink, quantity, rollType, roll, upgraded)
		OnRollWon(itemLink, quantity, rollType, roll)
	end)
	ns.On("LOOT_ROLLS_COMPLETE", function(lootHandle)
		Debug("LOOT_ROLLS_COMPLETE", lootHandle)
		OnRollsComplete(lootHandle)
	end)
	ns.On("LOOT_HISTORY_UPDATE_DROP", function(encounterID, lootListKey)
		Capture.OnDrop(encounterID, lootListKey)
	end)
	ns.On("LOOT_HISTORY_UPDATE_ENCOUNTER", function(encounterID)
		Debug("LOOT_HISTORY_UPDATE_ENCOUNTER", encounterID)
		Capture.ScanHistory(Clean(encounterID))
	end)
	ns.On("LOOT_HISTORY_CLEAR_HISTORY", function()
		Debug("LOOT_HISTORY_CLEAR_HISTORY")
		if ns.char then
			ns.char.seen = {}
		end
		for i = 1, #pending do
			pending[i].lhKey = nil
		end
	end)
	ns.On("CHAT_MSG_LOOT", function(text)
		Capture.OnChat(text)
	end)
	ns.On("PLAYER_ENTERING_WORLD", function()
		Rehydrate()
	end)

	if hooksecurefunc and RollOnLoot then
		hooksecurefunc("RollOnLoot", OnRollChoice)
	end
	if hooksecurefunc and ConfirmLootRoll then
		hooksecurefunc("ConfirmLootRoll", OnRollChoice)
	end
	if C_Timer and C_Timer.NewTicker then
		C_Timer.NewTicker(20, Capture.Sweep)
	end

	local missing = {}
	for event in pairs(ns.missingEvents) do
		missing[#missing + 1] = event
	end
	Debug("CAPTURE_ENABLED", "patterns", #chatPatterns, "missingEvents", table.concat(missing, ","),
		"RollOnLoot", RollOnLoot ~= nil, "C_LootHistory", C_LootHistory ~= nil)
end
