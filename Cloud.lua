local ADDON, ns = ...

local Cloud = {}
ns.Cloud = Cloud

Cloud.SCHEMA = 1
Cloud.AVAILABLE = false
Cloud.API = {
	base = "",
	link = "",
	push = "",
	pull = "",
	status = "",
}

function Cloud.Init()
	local db = ns.db
	if type(db.cloud) ~= "table" then
		db.cloud = {}
	end
	local cloud = db.cloud
	cloud.schema = Cloud.SCHEMA
	if cloud.optIn ~= true then
		cloud.optIn = false
	end
	return cloud
end

function Cloud.IsAvailable()
	return Cloud.AVAILABLE
end

function Cloud.IsOptedIn()
	return Cloud.AVAILABLE and ns.db and ns.db.cloud and ns.db.cloud.optIn == true or false
end

function Cloud.SetOptIn(enabled)
	local cloud = Cloud.Init()
	cloud.optIn = enabled and true or false
	if not cloud.optIn then
		cloud.outbox = nil
		cloud.inbox = nil
	end
	return cloud.optIn
end

function Cloud.QueueUpload()
	if not Cloud.IsOptedIn() then
		return false
	end
	local payload, characters, rolls = ns.Data.Export()
	if not payload then
		return false
	end
	ns.db.cloud.outbox = {
		schema = Cloud.SCHEMA,
		created = ns.Now(),
		account = ns.db.cloud.account,
		characters = characters,
		rolls = rolls,
		payload = payload,
	}
	return true
end

function Cloud.PullPending()
	if not Cloud.IsOptedIn() then
		return false
	end
	local cloud = ns.db.cloud
	local inbox = cloud.inbox
	if type(inbox) ~= "table" or type(inbox.payload) ~= "string" then
		return false
	end
	local ok, message, added = ns.Data.Import(inbox.payload)
	cloud.inbox = nil
	cloud.lastPull = { time = ns.Now(), ok = ok, message = message, added = added }
	if ok and added and added > 0 then
		ns.Print("Cloud sync: " .. message)
		ns.FireDataChanged()
	end
	return ok
end

function Cloud.Status()
	if not Cloud.AVAILABLE then
		return "Cloud sync through apphub.au is on the way, but it isn't switched on yet."
	end
	if Cloud.IsOptedIn() then
		return "Cloud sync is on."
	end
	return "Cloud sync is off."
end

ns.On("PLAYER_LOGIN", function()
	if ns.db then
		Cloud.Init()
		Cloud.PullPending()
	end
end)

ns.On("PLAYER_LOGOUT", function()
	if ns.db then
		Cloud.QueueUpload()
	end
end)
