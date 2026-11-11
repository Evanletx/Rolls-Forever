local ADDON, ns = ...

local Data = {}
ns.Data = Data

local PREFIX = "RF1"
local FORMAT = "RollsForever"
local FORMAT_VERSION = "1"
local MAX_TEXT = 6000000
local MAX_CHARS = 200
local MAX_ROLLS = 100000
local MIN_TIME = 1262304000
local ROLL_FIELDS = 21
local CHAR_FIELDS = 8

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENC, DEC = {}, {}
for i = 1, 64 do
	local c = ALPHABET:sub(i, i)
	ENC[i - 1] = c
	DEC[c:byte()] = i - 1
end

local ROLL_TYPES = { need = true, greed = true, pass = true, de = true, tmog = true }
local QUALITY_HEX = {
	[0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee",
	[5] = "ff8000", [6] = "e6cc80", [7] = "00ccff", [8] = "00ccff",
}

local function Encode(s)
	local out, n = {}, 0
	for i = 1, #s, 3 do
		local a, b, c = s:byte(i, i + 2)
		local v = a * 65536 + (b or 0) * 256 + (c or 0)
		n = n + 1
		out[n] = ENC[math.floor(v / 262144)]
			.. ENC[math.floor(v / 4096) % 64]
			.. (b and ENC[math.floor(v / 64) % 64] or "=")
			.. (c and ENC[v % 64] or "=")
	end
	return table.concat(out)
end

local function Decode(s)
	if #s % 4 ~= 0 or not s:find("^[A-Za-z0-9+/]*=?=?$") then
		return nil
	end
	local out, n = {}, 0
	for i = 1, #s, 4 do
		local a, b, c, d = s:byte(i, i + 3)
		local va, vb = DEC[a], DEC[b]
		local vc, vd = DEC[c], DEC[d]
		if not va or not vb then
			return nil
		end
		local v = va * 262144 + vb * 4096 + (vc or 0) * 64 + (vd or 0)
		n = n + 1
		if not vc then
			out[n] = string.char(math.floor(v / 65536))
		elseif not vd then
			out[n] = string.char(math.floor(v / 65536), math.floor(v / 256) % 256)
		else
			out[n] = string.char(math.floor(v / 65536), math.floor(v / 256) % 256, v % 256)
		end
	end
	return table.concat(out)
end

local function Hash(s, multiplier, modulus)
	local h = #s % modulus
	for i = 1, #s do
		h = (h * multiplier + s:byte(i)) % modulus
	end
	return h
end

local function Checksum(s)
	return string.format("%.0f.%.0f", Hash(s, 31, 4294967291), Hash(s, 131, 4294967279))
end

local ESCAPES = { ["\\"] = "\\\\", ["\t"] = "\\t", ["\n"] = "\\n", ["\r"] = "" }
local UNESCAPES = { ["\\"] = "\\", t = "\t", n = "\n" }

local function Str(v)
	if v == nil then
		return ""
	end
	return (tostring(v):gsub("[\\\t\n\r]", ESCAPES))
end

local function Int(v)
	if type(v) ~= "number" then
		return ""
	end
	return string.format("%.0f", v)
end

local function Bool(v)
	if v == true then
		return "1"
	elseif v == false then
		return "0"
	end
	return ""
end

local function Unescape(s)
	return (s:gsub("\\(.)", function(c)
		return UNESCAPES[c] or ""
	end))
end

local function Split(line)
	local fields, n = {}, 0
	for field in (line .. "\t"):gmatch("([^\t]*)\t") do
		n = n + 1
		fields[n] = Unescape(field)
	end
	return fields, n
end

local function CleanText(s, maxLength)
	s = s:gsub("|", ""):gsub("%c", " "):match("^%s*(.-)%s*$")
	if #s > maxLength then
		s = s:sub(1, maxLength)
	end
	if s == "" then
		return nil
	end
	return s
end

local function ReadInt(s, low, high)
	if s == "" then
		return nil, true
	end
	if #s > 12 or not s:find("^%-?%d+$") then
		return nil, false
	end
	local v = tonumber(s)
	if not v or v < low or v > high then
		return nil, false
	end
	return v, true
end

local function ReadBool(s)
	if s == "" then
		return nil, true
	elseif s == "1" then
		return true, true
	elseif s == "0" then
		return false, true
	end
	return nil, false
end

local function ItemString(rec)
	local item = type(rec.link) == "string" and rec.link:match("(item:[%d:%-]+)") or nil
	if not item and type(rec.item) == "number" then
		item = "item:" .. Int(rec.item)
	end
	return item
end

local function Signature(rec)
	return Int(rec.t) .. "|" .. Int(rec.item) .. "|" .. tostring(rec.type) .. "|" .. Int(rec.roll)
end

function Data.Export()
	local lines, charCount, rollCount = {}, 0, 0
	local keys = {}
	for key, char in pairs(ns.db.chars) do
		if not char.test and type(char.rolls) == "table" and #char.rolls > 0 then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)

	for _, key in ipairs(keys) do
		local char = ns.db.chars[key]
		local rollLines = {}
		for _, rec in ipairs(char.rolls) do
			local item = ItemString(rec)
			if item and type(rec.t) == "number" then
				rollLines[#rollLines + 1] = table.concat({
					"R", Int(rec.t), item, Str(rec.n), Int(rec.q), Str(rec.type), Bool(rec.off and true or nil),
					Int(rec.roll), Bool(rec.won), Str(rec.wn), Str(rec.wc), Int(rec.wr), Str(rec.wt),
					Bool(rec.allp and true or nil), Int(rec.cn), Int(rec.cg), Int(rec.cp),
					type(rec.exp) == "number" and string.format("%.6f", rec.exp) or "",
					Str(rec.zone), Int(rec.inst), Int(rec.grp), Bool(rec.inf and true or nil),
				}, "\t")
			end
		end
		if #rollLines > 0 then
			charCount = charCount + 1
			rollCount = rollCount + #rollLines
			lines[#lines + 1] = table.concat({
				"C", Str(key), Str(char.name), Str(char.surname), Str(char.realm), Str(char.class),
				Int(char.level), Int(#rollLines),
			}, "\t")
			for i = 1, #rollLines do
				lines[#lines + 1] = rollLines[i]
			end
		end
	end

	if rollCount == 0 then
		return nil, 0, 0
	end
	table.insert(lines, 1, table.concat({ "H", FORMAT, FORMAT_VERSION, Int(ns.Now()), Int(charCount) }, "\t"))
	local payload = table.concat(lines, "\n")
	return PREFIX .. ":" .. Checksum(payload) .. ":" .. Encode(payload), charCount, rollCount
end

local function ParseRoll(fields, now)
	local rec = { src = "import" }
	local ok

	rec.t, ok = ReadInt(fields[2], MIN_TIME, now + 86400)
	if not rec.t or not ok then
		return nil
	end

	local item = fields[3]
	if #item > 200 or not item:find("^item:[%d:%-]+$") then
		return nil
	end
	rec.item = tonumber(item:match("^item:(%d+)"))
	if not rec.item or rec.item < 1 or rec.item > 100000000 then
		return nil
	end

	rec.n = CleanText(fields[4], 120) or "Unknown item"

	rec.q, ok = ReadInt(fields[5], 0, 8)
	if not ok then
		return nil
	end

	if fields[6] ~= "" then
		if not ROLL_TYPES[fields[6]] then
			return nil
		end
		rec.type = fields[6]
	end

	local off
	off, ok = ReadBool(fields[7])
	if not ok then
		return nil
	end
	rec.off = off or nil

	rec.roll, ok = ReadInt(fields[8], 1, 100)
	if not ok then
		return nil
	end
	rec.won, ok = ReadBool(fields[9])
	if not ok then
		return nil
	end

	rec.wn = CleanText(fields[10], 60)
	if fields[11] ~= "" then
		if #fields[11] > 20 or not fields[11]:find("^[A-Z]+$") then
			return nil
		end
		rec.wc = fields[11]
	end
	rec.wr, ok = ReadInt(fields[12], 1, 100)
	if not ok then
		return nil
	end
	if fields[13] ~= "" then
		if not ROLL_TYPES[fields[13]] then
			return nil
		end
		rec.wt = fields[13]
	end

	local allPassed
	allPassed, ok = ReadBool(fields[14])
	if not ok then
		return nil
	end
	rec.allp = allPassed or nil

	rec.cn, ok = ReadInt(fields[15], 0, 100)
	if not ok then
		return nil
	end
	rec.cg, ok = ReadInt(fields[16], 0, 100)
	if not ok then
		return nil
	end
	rec.cp, ok = ReadInt(fields[17], 0, 100)
	if not ok then
		return nil
	end

	if fields[18] ~= "" then
		if #fields[18] > 12 or not fields[18]:find("^%d%.%d+$") then
			return nil
		end
		local chance = tonumber(fields[18])
		if not chance or chance < 0 or chance > 1 then
			return nil
		end
		rec.exp = chance
	end

	rec.zone = CleanText(fields[19], 80)
	rec.inst, ok = ReadInt(fields[20], 0, 100000000)
	if not ok then
		return nil
	end
	rec.grp, ok = ReadInt(fields[21], 0, 100)
	if not ok then
		return nil
	end
	local inferred
	inferred, ok = ReadBool(fields[22])
	if not ok then
		return nil
	end
	rec.inf = inferred or nil

	rec.link = "|cff" .. (QUALITY_HEX[rec.q or 1] or "ffffff") .. "|H" .. item .. "|h[" .. rec.n .. "]|h|r"
	return rec
end

local function Parse(text)
	if type(text) ~= "string" then
		return nil, "empty"
	end
	text = text:gsub("%s+", "")
	if text == "" then
		return nil, "empty"
	end
	if #text > MAX_TEXT then
		return nil, "toobig"
	end
	local h1, h2, body = text:match("^" .. PREFIX .. ":(%d+)%.(%d+):([A-Za-z0-9+/=]+)$")
	if not body then
		return nil, "format"
	end
	local payload = Decode(body)
	if not payload or payload == "" then
		return nil, "format"
	end
	if Checksum(payload) ~= (h1 .. "." .. h2) then
		return nil, "checksum"
	end

	local now = ns.Now()
	local staged, current, expectedChars = {}, nil, nil
	local totalRolls = 0
	local first = true
	for line in payload:gmatch("[^\n]+") do
		local fields, count = Split(line)
		local kind = fields[1]
		if first then
			first = false
			if kind ~= "H" or count ~= 5 or fields[2] ~= FORMAT then
				return nil, "format"
			end
			if fields[3] ~= FORMAT_VERSION then
				return nil, "version"
			end
			expectedChars = ReadInt(fields[5], 1, MAX_CHARS)
			if not expectedChars then
				return nil, "invalid"
			end
		elseif kind == "C" then
			if count ~= CHAR_FIELDS then
				return nil, "invalid"
			end
			if current and #current.rolls ~= current.expected then
				return nil, "invalid"
			end
			if #staged >= MAX_CHARS then
				return nil, "invalid"
			end
			local key = fields[2]
			if key == "" or #key > 80 or key:find("[|%c]") or key:find("%-Sample$") then
				return nil, "invalid"
			end
			local expected = ReadInt(fields[8], 1, MAX_ROLLS)
			local level, levelOk = ReadInt(fields[7], 1, 200)
			if not expected or not levelOk then
				return nil, "invalid"
			end
			local class = fields[6]
			if class ~= "" and (#class > 20 or not class:find("^[A-Z]+$")) then
				return nil, "invalid"
			end
			current = {
				key = key,
				name = CleanText(fields[3], 40) or "Unknown",
				surname = CleanText(fields[4], 40),
				realm = CleanText(fields[5], 60),
				class = class ~= "" and class or nil,
				level = level,
				expected = expected,
				rolls = {},
			}
			for i = 1, #staged do
				if staged[i].key == key then
					return nil, "invalid"
				end
			end
			staged[#staged + 1] = current
		elseif kind == "R" then
			if not current or count ~= ROLL_FIELDS + 1 then
				return nil, "invalid"
			end
			totalRolls = totalRolls + 1
			if totalRolls > MAX_ROLLS or #current.rolls >= current.expected then
				return nil, "invalid"
			end
			local rec = ParseRoll(fields, now)
			if not rec then
				return nil, "invalid"
			end
			current.rolls[#current.rolls + 1] = rec
		else
			return nil, "invalid"
		end
	end

	if first or #staged ~= expectedChars then
		return nil, "invalid"
	end
	if current and #current.rolls ~= current.expected then
		return nil, "invalid"
	end
	return staged
end

local ERRORS = {
	empty = "Paste an export into the box first.",
	toobig = "That's far too big to be a Rolls Forever export.",
	format = "That doesn't look like a Rolls Forever export.",
	version = "That export is from a newer version. Update Rolls Forever and try again.",
	checksum = "That export is damaged or has been edited, so it wasn't imported.",
	invalid = "That export has data in it that shouldn't be there, so it wasn't imported.",
}

function Data.Import(text)
	local staged, reason = Parse(text)
	if not staged then
		return false, ERRORS[reason] or ERRORS.format
	end

	local added, skipped, touched = 0, 0, 0
	for _, incoming in ipairs(staged) do
		local char = ns.db.chars[incoming.key]
		if not char then
			char = {
				rolls = {}, seen = {}, nextId = 1, imported = true,
				name = incoming.name, surname = incoming.surname, realm = incoming.realm,
				class = incoming.class, level = incoming.level,
			}
			ns.db.chars[incoming.key] = char
		end
		char.rolls = char.rolls or {}
		char.nextId = char.nextId or (#char.rolls + 1)

		local have = {}
		for _, rec in ipairs(char.rolls) do
			have[Signature(rec)] = true
		end
		local addedHere = 0
		for _, rec in ipairs(incoming.rolls) do
			local signature = Signature(rec)
			if have[signature] then
				skipped = skipped + 1
			else
				have[signature] = true
				rec.id = char.nextId
				char.nextId = char.nextId + 1
				char.rolls[#char.rolls + 1] = rec
				addedHere = addedHere + 1
			end
		end
		if addedHere > 0 then
			touched = touched + 1
			added = added + addedHere
			table.sort(char.rolls, function(a, b)
				local ta, tb = a.t or 0, b.t or 0
				if ta ~= tb then
					return ta < tb
				end
				return (a.id or 0) < (b.id or 0)
			end)
		end
	end

	ns.Debug("IMPORT", "added", added, "skipped", skipped, "characters", #staged)
	if added == 0 then
		return true, "Nothing new in that export. You already have all " .. skipped .. " rolls."
	end
	local message = "Imported " .. added .. (added == 1 and " roll" or " rolls") .. " for "
		.. touched .. (touched == 1 and " character." or " characters.")
	if skipped > 0 then
		message = message .. " Skipped " .. skipped .. " you already had."
	end
	return true, message, added
end

function Data.Check(text)
	local staged, reason = Parse(text)
	if not staged then
		return false, ERRORS[reason] or ERRORS.format
	end
	local rolls = 0
	for _, incoming in ipairs(staged) do
		rolls = rolls + #incoming.rolls
	end
	return true, staged, #staged, rolls
end

function Data.Replace(staged)
	local chars, rolls = {}, 0
	for _, incoming in ipairs(staged) do
		table.sort(incoming.rolls, function(a, b)
			return (a.t or 0) < (b.t or 0)
		end)
		for i, rec in ipairs(incoming.rolls) do
			rec.id = i
		end
		chars[incoming.key] = {
			rolls = incoming.rolls, seen = {}, nextId = #incoming.rolls + 1, imported = true,
			name = incoming.name, surname = incoming.surname, realm = incoming.realm,
			class = incoming.class, level = incoming.level,
		}
		rolls = rolls + #incoming.rolls
	end

	local current = ns.char
	if current and ns.charKey then
		local mine = chars[ns.charKey]
		if not mine then
			mine = { rolls = {}, seen = {}, nextId = 1 }
			chars[ns.charKey] = mine
		end
		mine.imported = nil
		mine.name, mine.surname, mine.realm = current.name, current.surname, current.realm
		mine.class, mine.level, mine.lastSeen = current.class, current.level, current.lastSeen
	end

	ns.db.chars = chars
	if ns.charKey then
		ns.char = chars[ns.charKey]
	end
	if ns.Capture and ns.Capture.pending then
		for i = #ns.Capture.pending, 1, -1 do
			ns.Capture.pending[i] = nil
		end
	end
	ns.Debug("REPLACE", "rolls", rolls, "characters", #staged)
	return rolls, #staged
end

ns.On("PLAYER_LOGIN", function()
	if not ns.db then
		return
	end
	local pending = ns.db.pendingImport
	ns.db.pendingImport = nil
	if type(pending) ~= "string" then
		return
	end
	local ok, staged = Data.Check(pending)
	if not ok then
		ns.Print("Couldn't load your file. " .. staged)
		return
	end
	local rolls, characters = Data.Replace(staged)
	ns.Print("Loaded your file: " .. rolls .. (rolls == 1 and " roll" or " rolls") .. " across "
		.. characters .. (characters == 1 and " character." or " characters."))
end)

ns.On("PLAYER_LOGOUT", function()
	if not ns.db then
		return
	end
	local text, characters, rolls = Data.Export()
	if text then
		ns.db.lastExport = { text = text, time = ns.Now(), characters = characters, rolls = rolls }
	else
		ns.db.lastExport = nil
	end
end)

Data.Checksum = Checksum
Data.Encode = Encode
Data.Decode = Decode
