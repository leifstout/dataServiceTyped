---
sidebar_position: 2
---

# Service Functions

`Data.Service` is the server-only API for lifecycle hooks, ProfileStore access, data resets, and cross-server messages.

Require the server side of your data module first:

```lua
local Data = require(path.to.Data).server
```

Most gameplay code can use `Data[player]` directly:

```lua
Data[player].currency(function(currency)
	return currency + 10
end)
```

Use `Data.Service` when you need behavior around loading, leaving, profiles, or global messages.

## `onPlayerInit(player, data)`

Override `onPlayerInit` to run code after a player's profile loads but before it is sent to the client.

```lua
function Data.Service:onPlayerInit(player, data)
	data.totalJoins = (data.totalJoins or 0) + 1
	data.lastJoinTime = os.time()
end
```

This receives the raw data table, not `Data[player]`. That is intentional: this is the cleanest place to do migrations, defaults, and one-time cleanup before anything can listen or replicate.

```lua
function Data.Service:onPlayerInit(player, data)
	if data.currency < 0 then
		data.currency = 0
	end

	data.settings.sfx = if data.settings.sfx == nil then true else data.settings.sfx
end
```

## `waitForData(player)`

`waitForData` yields until a player's data has finished loading, then returns the same data object you get from `Data[player]`.

```lua
local data = Data.Service:waitForData(player)

data.currency(50)
```

You usually only need this in code that might run before the player's data exists yet, such as early `PlayerAdded` logic or another service starting up at the same time as DataServiceTyped.

After data is loaded, prefer the simple form:

```lua
Data[player].currency(50)
```

## `getProfile(player)`

Returns the loaded ProfileStore profile for a player.

```lua
local profile = Data.Service:getProfile(player)
```

Use this when you need ProfileStore-specific functionality that DataServiceTyped does not wrap. For normal reads and writes, use `Data[player]`.

```lua
local profile = Data.Service:getProfile(player)

if profile then
	print(profile.Data.currency)
end
```

## `asyncGetProfile(userId)`

Loads a profile by user id and returns it.

```lua
local profile = Data.Service:asyncGetProfile(123456789)

if profile then
	print(profile.Data.currency)
end
```

This is useful for admin tools, profile inspection, and read-only flows where the player is not currently in the server.

## `resetData(player)`

Deletes the player's saved profile and kicks them so they can rejoin with fresh data.

```lua
Data.Service:resetData(player)
```

This is most useful for admin commands and local testing. It ends the current profile session, removes the saved data, and kicks the player with a reset message.

## `addPlayerRemovingCallback(fn)`

Registers a callback that runs when a player's profile is about to end.

```lua
local disconnect = Data.Service:addPlayerRemovingCallback(function(player, data)
	data.lastLeaveTime = os.time()
end)
```

The callback receives the player and the raw data table. This is useful for final timestamps, cleanup, or writing values that should happen right before the ProfileStore session ends.

The function returns a disconnect callback:

```lua
local disconnect = Data.Service:addPlayerRemovingCallback(function(player, data)
	print(player.Name, "left with", data.currency, "coins")
end)

disconnect()
```

## `sendGlobalMessage(key, userId, data)`

Sends a ProfileStore global message to a user's profile.

```lua
Data.Service:sendGlobalMessage("GiftCoins", 123456789, {
	amount = 100,
	from = "DailyReward",
})
```

The `key` decides which callback handles the message. The `userId` can be a number or string. The `data` argument should be a plain table.

## `addGlobalCallback(key, callback)`

Registers a callback for global messages with a matching key.

```lua
Data.Service:addGlobalCallback("GiftCoins", function(player, data)
	local amount = data.amount
	if typeof(amount) ~= "number" then
		return false
	end

	Data[player].currency(function(currency)
		return currency + amount
	end)
end)
```

The callback receives the player and the message data. Return `false` when the message should not be marked as processed.

Global messages are a good fit for cross-server rewards, purchases, gifts, and admin actions aimed at a player who may not be in the current server.

## Quick Reference

```lua
-- Runs before data is sent to the client
function Data.Service:onPlayerInit(player, data) end

-- Waits for Data[player] to exist
local data = Data.Service:waitForData(player)

-- Gets the loaded ProfileStore profile
local profile = Data.Service:getProfile(player)

-- Loads a profile by user id
local profile = Data.Service:asyncGetProfile(userId)

-- Deletes saved data and kicks the player
Data.Service:resetData(player)

-- Runs before the profile session ends
local disconnect = Data.Service:addPlayerRemovingCallback(function(player, data) end)

-- Sends and receives ProfileStore global messages
Data.Service:sendGlobalMessage("Key", userId, data)
Data.Service:addGlobalCallback("Key", function(player, data) end)
```
