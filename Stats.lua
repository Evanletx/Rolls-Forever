local ADDON, ns = ...

local Stats = {}
ns.Stats = Stats

local BANDS = {
	{ 1, 10 }, { 11, 20 }, { 21, 30 }, { 31, 40 }, { 41, 50 },
	{ 51, 60 }, { 61, 70 }, { 71, 80 }, { 81, 90 }, { 91, 99 }, { 100, 100 },
}
Stats.BANDS = BANDS

function Stats.BandLabel(index)
	local band = BANDS[index]
	if band[1] == band[2] then
		return tostring(band[1])
	end
	return band[1] .. "-" .. band[2]
end

function Stats.BandIndex(roll)
	if roll >= 100 then
		return 11
	end
	local index = math.floor((roll - 1) / 10) + 1
	if index < 1 then
		index = 1
	elseif index > 10 then
		index = 10
	end
	return index
end

local function IsSelection(rollType)
	return rollType == "need" or rollType == "greed" or rollType == "de" or rollType == "tmog"
end
Stats.IsSelection = IsSelection

-- A Greed-tier pick (Greed, Disenchant, Transmog) can't win once anyone picks
-- Need, so that roll has no outcome: it's neither a win nor a loss.
local function BlockedByNeed(rec)
	local rollType = rec.type
	if rec.won == true or rollType == "need" or not IsSelection(rollType) then
		return false
	end
	return rec.wt == "need" or (type(rec.cn) == "number" and rec.cn > 0)
end
Stats.BlockedByNeed = BlockedByNeed

function Stats.Matches(rec, filter)
	if filter == "need" then
		return rec.type == "need"
	elseif filter == "greed" then
		return rec.type == "greed"
	end
	return true
end

function Stats.Filter(records, filter)
	if not filter or filter == "all" then
		return records
	end
	local out = {}
	for i = 1, #records do
		if Stats.Matches(records[i], filter) then
			out[#out + 1] = records[i]
		end
	end
	return out
end

local function Median(sortedValues)
	local n = #sortedValues
	if n == 0 then
		return nil
	end
	if n % 2 == 1 then
		return sortedValues[(n + 1) / 2]
	end
	return (sortedValues[n / 2] + sortedValues[n / 2 + 1]) / 2
end

function Stats.Compute(records)
	local s = {
		total = #records,
		need = 0, greed = 0, pass = 0, other = 0, unknown = 0,
		selections = 0,
		wins = 0, losses = 0, blocked = 0,
		numbered = 0,
		sum = 0,
		bands = {}, bandPct = {},
		below50 = 0, atLeast50 = 0,
		hundreds = 0, ones = 0,
		bestWinStreak = 0, longestDryStreak = 0, currentStreak = 0, currentStreakWon = nil,
		expectedWins = 0, expectedSample = 0, expectedActual = 0,
		zones = {},
	}
	for i = 1, #BANDS do
		s.bands[i] = 0
		s.bandPct[i] = 0
	end

	local values = {}
	local winSum, winCount, lossSum, lossCount = 0, 0, 0, 0
	local winRun, dryRun = 0, 0
	local zoneIndex = {}

	for i = 1, #records do
		local r = records[i]
		local rollType = r.type
		local selected = IsSelection(rollType)
		local won = r.won
		if BlockedByNeed(r) then
			won = nil
			s.blocked = s.blocked + 1
		end

		if rollType == "need" then
			s.need = s.need + 1
		elseif rollType == "greed" then
			s.greed = s.greed + 1
		elseif rollType == "pass" then
			s.pass = s.pass + 1
		elseif selected then
			s.other = s.other + 1
		else
			s.unknown = s.unknown + 1
		end

		if r.zone then
			local z = zoneIndex[r.zone]
			if not z then
				z = { name = r.zone, count = 0, wins = 0 }
				zoneIndex[r.zone] = z
				s.zones[#s.zones + 1] = z
			end
			z.count = z.count + 1
			if r.won == true then
				z.wins = z.wins + 1
			end
		end

		if selected then
			s.selections = s.selections + 1
			if won == true then
				s.wins = s.wins + 1
				winRun = winRun + 1
				dryRun = 0
				if winRun > s.bestWinStreak then
					s.bestWinStreak = winRun
				end
			elseif won == false then
				s.losses = s.losses + 1
				dryRun = dryRun + 1
				winRun = 0
				if dryRun > s.longestDryStreak then
					s.longestDryStreak = dryRun
				end
			end
			if type(r.exp) == "number" and won ~= nil then
				s.expectedWins = s.expectedWins + r.exp
				s.expectedSample = s.expectedSample + 1
				if won then
					s.expectedActual = s.expectedActual + 1
				end
			end
		end

		local roll = r.roll
		if selected and type(roll) == "number" and roll >= 1 and roll <= 100 then
			s.numbered = s.numbered + 1
			s.sum = s.sum + roll
			values[#values + 1] = roll
			local band = Stats.BandIndex(roll)
			s.bands[band] = s.bands[band] + 1
			if roll < 50 then
				s.below50 = s.below50 + 1
			else
				s.atLeast50 = s.atLeast50 + 1
			end
			if roll == 100 then
				s.hundreds = s.hundreds + 1
			elseif roll == 1 then
				s.ones = s.ones + 1
			end
			if not s.max or roll > s.max then
				s.max = roll
			end
			if not s.min or roll < s.min then
				s.min = roll
			end
			if won == true then
				winSum, winCount = winSum + roll, winCount + 1
				if not s.lowestWin or roll < s.lowestWin then
					s.lowestWin = roll
				end
			elseif won == false then
				lossSum, lossCount = lossSum + roll, lossCount + 1
				if not s.highestLoss or roll > s.highestLoss then
					s.highestLoss = roll
				end

				if type(r.wr) == "number" and r.wr >= roll and (r.wt == nil or r.wt == rollType) then
					local margin = r.wr - roll
					if not s.closestLoss or margin < s.closestLoss then
						s.closestLoss = margin
					end
				end
			end
		end
	end

	if winRun > 0 then
		s.currentStreak, s.currentStreakWon = winRun, true
	elseif dryRun > 0 then
		s.currentStreak, s.currentStreakWon = dryRun, false
	end

	if s.numbered > 0 then
		s.avg = s.sum / s.numbered
		table.sort(values)
		s.median = Median(values)
		local variance = 0
		for i = 1, #values do
			variance = variance + (values[i] - s.avg) ^ 2
		end
		s.stdev = math.sqrt(variance / #values)
		s.below50Pct = s.below50 / s.numbered * 100
		s.atLeast50Pct = s.atLeast50 / s.numbered * 100
		local best = 0
		for i = 1, #BANDS do
			s.bandPct[i] = s.bands[i] / s.numbered * 100
			if s.bands[i] > best then
				best = s.bands[i]
				s.modeBand = i
			end
		end
		s.maxBandCount = best
	end

	if winCount > 0 then
		s.avgWinningRoll = winSum / winCount
	end
	if lossCount > 0 then
		s.avgLosingRoll = lossSum / lossCount
	end

	local decided = s.wins + s.losses
	s.decided = decided
	if decided > 0 then
		s.winPct = s.wins / decided * 100
		s.lossPct = s.losses / decided * 100
	end

	if s.expectedSample >= 1 and s.expectedWins > 0 then
		s.luck = s.expectedActual / s.expectedWins
	end

	table.sort(s.zones, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.name < b.name
	end)

	return s
end
