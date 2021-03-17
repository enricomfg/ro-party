-- Data Service
-- RicoFox
-- March 17, 2021

local ProfileTemplate = {
	cash = 0
}

local ProfileService, ProfileStore

-- Private variables:
local Players = game:GetService("Players")
local Sessions = {} -- [player] = session

local Session do
	Session = {}
	Session.__index = Session
	Session.ClassName = "Session"

	function Session.new(player)
		local profile = ProfileStore:LoadProfileAsync(
			player.UserId,
			"ForceLoad"
		)
		if profile ~= nil then
			profile:Reconcile() -- Fill in missing variables from ProfileTemplate (optional)

			profile:ListenToRelease(function()
				Sessions[player] = nil
				-- The profile could've been loaded on another Roblox server:
				player:Kick('Your profile has been released!')
			end)

			if player:IsDescendantOf(Players) == true then
				return setmetatable({
					_profile = profile,
					_updateQueue = {},
					_updateListeners = {}
				}, Session)
				-- A profile has been successfully loaded:
			else
				-- Player left before the profile loaded:
				profile:Release()
			end
		else
			-- The profile couldn't be loaded possibly due to other
			--   Roblox servers trying to load this profile at the same time:
			player:Kick('Your profile couldn\'t be loaded!')
		end
	end

	function Session:Get(key)
		return self._profile.Data[key] or error(('Attempt to get from unexistant key "%s"'):format(key))
	end

	function Session:Update(key, updater)
		if not self._profile.Data[key] then error(('Attempt to update unexistant key "%s"'):format(key)) end

		self._updateQueue[key] = self._updateQueue[key] or {}
		table.insert(self._updateQueue, updater)

		if #self._updateQueue[key] > 1 then
			while true do
				local method = table.remove(self._updateQueue[key], 1)
				local response = method(self._profile.Data[key])
				self._profile.Data[key] = response

				if self._updateListeners[key] then
					for _, listener in ipairs(self._updateListeners[key]) do
						coroutine.wrap(listener)(response)
					end
				end
			end
		end
	end

	function Session:ListenToUpdate(key, listener)
		if not self._profile.Data[key] then error(('Attempt to listen to unexistant key "%s"'):format(key)) end

		self._updateListeners[key] = self._updateListeners[key] or {}
		table.insert(self._updateListeners[key], listener)
	end

	function Session:ListenToUpdateAndRun(key, listener)
		if not self._profile.Data[key] then error(('Attempt to listen to unexistant key "%s"'):format(key)) end
		self._updateListeners[key] = self._updateListeners[key] or {}
		table.insert(self._updateListeners[key], listener)

		listener(self._profile.Data[key])
	end
end

-- Service:
local DataService = {
	Client = {},
	_session_listeners = {}
}


function DataService:_playerAdded(player)
	local session = Session.new(player)

	if session ~= nil then
		Sessions[player] = session

		for _, listener in ipairs(self._session_listeners) do
			listener(session)
		end

		for key, value in pairs(session._profile.Data) do
			if self._updateListeners[key] then
				for _, listener in ipairs(self._updateListeners[key]) do
					coroutine.wrap(listener)(value)
				end
			end
		end
	else
		player:Kick('Session not loaded!')
	end
end


function DataService:BindToSessions(method)
	table.insert(self._session_listeners, method)

	for _, session in ipairs(Sessions) do
		coroutine.wrap(method)(session)
	end
end


function DataService:Start()
	for _, player in ipairs(Players:GetPlayers()) do
		coroutine.wrap(self._playerAdded)(self, player)
	end

	game.Players.PlayerAdded:Connect(function(player)
		self:_playerAdded(player)
	end)
end


function DataService:Init()
	ProfileService = self.Module.ProfileService
	ProfileStore = ProfileService.GetProfileStore(
		"Player",
		ProfileTemplate
	)
end


return DataService