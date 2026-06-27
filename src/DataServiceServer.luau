local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

if RunService:IsClient() then
	return {} :: any
end

local Packages = script.Parent.Parent
local Value = require(script.Parent.Value)
local DataServiceUtils = require(script.Parent.DataServiceUtils)
local Signal = require(Packages.Signal)
local Networker = require(Packages.Networker)
local ProfileStore = if RunService:IsServer() then require(Packages.ProfileStore) else nil :: any

local DATA_PREFIX = "PLAYER_"
local DEFAULT_PROFILE_STORE_INDEX = "Default"

--[=[
	@type DataTemplate { [string]: any }
	@within DataServiceServer
	
	Defines the structure of player data used by the DataServiceServer.

	```lua
	local datatemplate = {
		currency = 0,
		inventory = {
			apples = 5,
			oranges = 10,
		},
		settings = {
			music = true,
		},
		items = {} :: { [string]: ItemData },
		array = {} :: { number },
	}
	```

	
	:::note
	Player data automatically reconciles the template on join if new keys are added.
	:::
	:::warning
	Follow JSON rules for all data. (e.g., no Vector3, CFrame, etc.)
	:::
]=]
type DataTemplate = { [string | number]: any }

--[=[
	@interface DataOptions
	@within DataServiceServer
	.template DataTemplate -- Template dictionary for player data.
	.profileStoreIndex string -- Index for the ProfileStore.
	.useMock boolean? -- Use Mock data for testing.
	.viewedUserId number? -- User ID to view data for. Use to view a specific player's data without saving.
	.overridenUserId number? -- User ID to override for the profile. Use to play on another player's save.
	.dontSave boolean? -- Prevent saving the profile. Use for testing without saving.
	.resetData boolean? -- Reset the data on player join. Use to wipe data for testing.
	
	```lua
	local options = {
		template = require(path.to.datatemplate),
		profileStoreIndex = "Public",
	}
	```

	Provides options for initializing the DataServiceServer.
]=]
type DataOptions<T> = DataServiceUtils.DataOptions<T>
type MessageData = { key: string, data: { any } }

local DataServiceServer = {
	_profiles = {} :: any,
	_waitSignals = {} :: { [Player]: Signal.Signal<any> },
	_removalFunctions = {} :: { (player: Player, data: any) -> () },
	_globalCallbacks = {} :: { [string]: (player: Player, { any }) -> boolean? },
	_globalCallbackAdded = Signal.new() :: Signal.Signal<string>,
	data = {} :: { [Player]: Value.Value<any> },
}

--[=[
	@class DataServiceServer
	The server-side service for managing player data.
]=]
function DataServiceServer:init<T>(options: DataOptions<T>)
	assert(RunService:IsServer(), "DataServiceServer can only be used on the server.")
	assert(not self.playerStore, "DataServiceServer has already been initialized.")
	Value.shouldRecordPath = true
	self.options = options
	self.networker = Networker.server.new("DataService", self, {})
	self.playerStore = ProfileStore.New(options.profileStoreIndex or DEFAULT_PROFILE_STORE_INDEX, options.template)

	for _, player: Player in Players:GetPlayers() do
		task.spawn(function()
			self:_playerAdded(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		self:_playerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self:_playerRemoving(player)
	end)

	return self.data, self
end

local function storeCancel(player: Player)
	return {
		Cancel = function()
			return player.Parent ~= Players
		end,
	}
end

--[=[
	@method resetData
	@within DataServiceServer
	@param player Player

	Resets the data for the specified player by removing their profile from the store.
	The player is then kicked from the game with a message to rejoin.

	```lua
	Data.Service:resetData(player)
	```
]=]
function DataServiceServer.resetData(self: DataServiceServer<any>, player: Player): ()
	local index = self:_getProfileKey(player.UserId)
	self:_playerRemoving(player)
	self.playerStore:RemoveAsync(index)
	player:Kick("Your data has been reset. Please rejoin.")
end

function DataServiceServer:_playerAdded(player: Player)
	local userId = self.options.overridenUserId or self.options.viewedUserId or player.UserId
	local index = self:_getProfileKey(userId)

	if self.options.resetData and not self.options.viewedUserId then
		self.playerStore:RemoveAsync(index)
	end

	local profile = if self.options.useMock
		then self.playerStore.Mock:StartSessionAsync(index, storeCancel(player))
		elseif self.options.viewedUserId or self.options.dontSave then self.playerStore:GetAsync(index)
		else self.playerStore:StartSessionAsync(index, storeCancel(player))

	profile:AddUserId(userId)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		self._profiles[player] = nil
		player:Kick(`Profile session end - Please rejoin`)
	end)

	if not player:IsDescendantOf(Players) then
		player:Kick(`Profile load fail - Please rejoin`)
		return
	end

	self._profiles[player] = profile
	self:_initPlayer(player, profile.Data)

	if not player:IsDescendantOf(Players) then
		player:Kick(`Profile load fail - Please rejoin`)
		return
	end

	profile:MessageHandler(function(messageData: MessageData, processed: () -> ())
		local cb = self._globalCallbacks[messageData.key]
		if cb then
			if (cb :: any)(player, messageData.data) ~= false then
				processed()
			end
			return
		end

		local waitConnection: any
		waitConnection = self._globalCallbackAdded:Connect(function(key: string)
			if key ~= messageData.key then
				return
			end

			local newCb = self._globalCallbacks[messageData.key]
			if (newCb :: any)(player, messageData.data) ~= false then
				processed()
			end

			waitConnection:Disconnect()
		end)
	end)
end

--[=[
	@method sendGlobalMessage
	@within DataServiceServer
	@param key string
	@param userId number | string
	@param data { any }
	@return boolean

	Sends a global message to the specified user's profile.
	Returns true if the message was sent successfully, false otherwise.

	```lua
	Data.Service:sendGlobalMessage("SendGift", userId, { currency = 100, from = "Friend" })
	```
]=]
function DataServiceServer.sendGlobalMessage(
	self: DataServiceServer<any>,
	key: string,
	userId: number | string,
	data: { any }
): boolean
	local messageData: MessageData = { key = key, data = data }
	return self.playerStore:MessageAsync(self:_getProfileKey(userId), messageData)
end

--[=[
	@method addGlobalCallback
	@within DataServiceServer
	@param key string
	@param cb (player: Player, data: { any }) -> boolean?

	Adds a global callback function for handling messages with the specified key.
	The callback receives the player and data as parameters.
	If the callback returns false, the message is not processed further.

	```lua
	Data.Service:addGlobalCallback("SendGift", function(player: Player, data: { any }): boolean?
		print("Received gift for", player.Name, "with data:", data)
		-- Process the gift here
	end)
	```
]=]
function DataServiceServer.addGlobalCallback(
	self: DataServiceServer<any>,
	key: string,
	cb: (player: Player, { any }) -> boolean?
): ()
	assert(self._globalCallbacks[key] == nil, "Global callback already exists for key: " .. key)
	self._globalCallbacks[key] = cb
	self._globalCallbackAdded:Fire(key)
end

function DataServiceServer._getProfileKey(self: DataServiceServer<any>, userId: number | string): string
	return self:_getDataPrefix() .. tostring(userId)
end

function DataServiceServer._getDataPrefix(self: DataServiceServer<any>): string
	return self.options.profileStoreDataPrefix or DATA_PREFIX
end

--[=[
	@method onPlayerInit
	@within DataServiceServer
	@tag Override
	@param player Player
	@param data DataTemplate

	Overridable method called when a player initializes their data.
	You can use this method to set initial values or perform actions when a player joins.

	```lua
	function Data.Service:onPlayerInit(player: Player, data: DataTemplate): ()
		print(player.Name .. " has initialized with data:", data)
		data.sessionJoinTime = os.time() -- We can directly modify data since no connections exist yet.
	end
	```

	:::note
	`onPlayerInit` is called after a player's data has loaded but before it is sent to the client or is available to the server.
	:::
]=]
function DataServiceServer.onPlayerInit<T>(_self: DataServiceServer<T>, _player: Player, _data: T) end

function DataServiceServer._initPlayer<T>(self: DataServiceServer<any>, player: Player, data: T): ()
	self:onPlayerInit(player, data)
	self.networker:fire(player, "load", data)

	self.data[player] = Value.new(data, nil, nil, function(replicateType: string, path: { string }, ...)
		self.networker:fire(player, replicateType, path, ...)
	end)

	local waitSignal = self._waitSignals[player]
	if waitSignal then
		waitSignal:Fire()
		waitSignal:Destroy()
		self._waitSignals[player] = nil
	end
end

function DataServiceServer._playerRemoving(self: DataServiceServer<any>, player: Player): ()
	local profile = self._profiles[player] :: any
	if not profile then
		return
	end

	for _, fn in self._removalFunctions do
		local success, err: any? = pcall(fn, player, profile.Data)
		if not success then
			warn(err or "Error in removal function for " .. player.Name)
		end
	end

	profile:EndSession()
	self._profiles[player] = nil

	local waitSignal = self._waitSignals[player]
	if waitSignal then
		waitSignal:Destroy()
		self._waitSignals[player] = nil
	end

	self.data[player] = nil
end

--[=[
	@method addPlayerRemovingCallback
	@within DataServiceServer
	@param fn (player: Player, data: any) -> ()

	Add any number of functions to be called when a player is removed.
	Used to perform cleanup or save data before the player leaves.

	```lua
	Data.Service:addPlayerRemovingCallback(function(player: Player, data: any): ()
		print(player.Name .. " is leaving with data:", data)
		-- Perform any cleanup or save operations here
	end)
	```

	```lua
	local disconnect = Data.Service:addPlayerRemovingCallback(function(player: Player, data: any): ()
		data.currency = 0
	end)

	-- Later, you can disconnect this function if needed
	disconnect()
	```
]=]
function DataServiceServer.addPlayerRemovingCallback(
	self: DataServiceServer<any>,
	fn: (player: Player, data: any) -> ()
): () -> ()
	table.insert(self._removalFunctions, fn)
	return function()
		local index = table.find(self._removalFunctions, fn)
		if index then
			table.remove(self._removalFunctions, index)
		end
	end
end

--[=[
	@method asyncGetProfile
	@within DataServiceServer
	@param userId number | string
	@return Profile?

	Asynchronously retrieves the profile for the given user ID using internal ProfileStore.
]=]
function DataServiceServer.asyncGetProfile(self: DataServiceServer<any>, userId: number | string): any?
	return self.playerStore:GetAsync(self:_getProfileKey(userId))
end

--[=[
	@method getProfile
	@within DataServiceServer
	@param player Player
	@return Profile

	Retrieves the profile for the given player.
]=]
function DataServiceServer.getProfile(self: DataServiceServer<any>, player: Player): any
	return self._profiles[player]
end

--[=[
	@method waitForData
	@within DataServiceServer
	@yields
	@param player Player
	@return Data

	Waits for the player's data to be initialized and returns it.
	If the data is already available, it returns immediately.
]=]
function DataServiceServer.waitForData(self: DataServiceServer<any>, player: Player): any
	local data = self.data[player]
	if data then
		return data
	end

	local waitSignal = self._waitSignals[player]
	if not waitSignal then
		waitSignal = Signal.new()
		self._waitSignals[player] = waitSignal
	end

	waitSignal:Wait()
	return self.data[player]
end

export type DataServiceServer<T> = typeof(DataServiceServer) & {
	networker: Networker.Server,
	data: { [Player]: Value.Value<any> },
	options: DataOptions<T>,
	playerStore: any,
}

export type Public<T> = {
	waitForData: (self: any, player: Player) -> (),
	onPlayerInit: (self: any, player: Player, data: T) -> (),
	getProfile: (self: any, player: Player) -> any,
	asyncGetProfile: (self: any, userId: number | string) -> any,
	resetData: (self: any, player: Player) -> (),
	addPlayerRemovingCallback: (self: any, fn: (player: Player, data: any) -> ()) -> () -> (),
	addGlobalCallback: (self: any, key: string, cb: (player: Player, { any }) -> boolean?) -> (),
	sendGlobalMessage: (self: any, key: string, userId: number | string, data: { any }) -> (),
}

return DataServiceServer
