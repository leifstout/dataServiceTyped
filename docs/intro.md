---
sidebar_position: 1
---

# DataServiceTyped

**DataServiceTyped** is persistent, typed, automatically replicated player data for Roblox Luau.

The API is intentionally small:

```lua
Data[player].currency() -- get
Data[player].currency(50) -- set
Data[player].currency(function(currency) -- update
	return currency + 10
end)
```

On the client, it is the same idea without the `player`:

```lua
Data.currency()
Data.currency(50)
Data.currency.Changed(function(currency)
	print(currency)
end)
```

## Installation

Add `DataServiceTyped` to your `wally.toml`:

```toml
[dependencies]
DataServiceTyped = "leifstout/dataservicetyped@1.0.5"
```

Then run:

```bash
wally install
```

:::important
DataServiceTyped uses Luau's new type solver for its typed data API. Enable the new type solver in Workspace properties or Luau LSP settings for types and IntelliSense to work correctly.
:::

## Create Your Data

Create one shared data module. Most games call it `Data.luau`.

```lua title="Data.luau"
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local DataServiceTyped = require(Packages.DataServiceTyped)

type ItemData = {
	health: number,
	dmg: number,
}

local template = {
	currency = 0,
	inventory = {
		apples = 5,
		oranges = 10,
	},
	settings = {
		music = true,
		sfx = true,
	},
	items = {} :: { [string]: ItemData },
	equippedItemId = nil :: string?,
	questProgress = {} :: { number },
}

return DataServiceTyped({
	template = template,
})
```

Keep saved data datastore-safe: numbers, strings, booleans, arrays, dictionaries, and `nil` for optional values. Do not store Instances, CFrames, Vector3s, functions, threads, or userdata.

## Require It

Require `.server` on the server:

```lua
local Data = require(path.to.Data).server
```

Require `.client` on the client:

```lua
local Data = require(path.to.Data).client
```

This keeps the local variable named `Data` everywhere.

## Get

Call a field with no arguments.

```lua
local currency = Data[player].currency()
local apples = Data[player].inventory.apples()
local musicEnabled = Data[player].settings.music()
```

On the client:

```lua
local currency = Data.currency()
local apples = Data.inventory.apples()
```

## Set

Call a field with a new value.

```lua
Data[player].currency(50)
Data[player].inventory.apples(12)
Data[player].settings.music(false)
Data[player].equippedItemId("wooden_sword")
```

Clear optional values with `nil`.

```lua
Data[player].equippedItemId(nil)
```

Server changes save and replicate to that player's client automatically.

Client changes are local-only:

```lua
Data.settings.music(false)
```

That updates the client mirror and fires client callbacks, but it does not save and does not replicate to the server.

## Update

Call a field with a function to update from the current value.

```lua
Data[player].currency(function(currency)
	return currency + 10
end)
```

The function receives the old value and returns the new value.

```lua
Data[player].inventory.apples(function(apples)
	return math.max(0, apples - 1)
end)
```

## Listen

Use `.Changed` on any field.

```lua
local disconnect = Data[player].currency.Changed(function(currency, previousCurrency)
	print("Currency:", previousCurrency, "->", currency)
end)

disconnect()
```

Client code looks the same:

```lua
Data.currency.Changed(function(currency)
	print("Currency changed to", currency)
end)
```

You can listen to nested fields:

```lua
Data[player].inventory.apples.Changed(function(apples)
	print("Apples:", apples)
end)
```

You can also listen to parent tables:

```lua
Data[player].inventory.Changed(function(inventory, previousChildValue, childKey)
	print(childKey, "changed")
end)
```

## Optional Replication

Server writes replicate by default. Pass `false` as the second argument to skip replication for that write.

```lua
Data[player].currency(100, false)

Data[player].currency(function(currency)
	return currency + 25
end, false)
```

This still changes the server data and still saves. It only skips the server-to-client update for that mutation.

## Arrays

Typed arrays get `.Insert`, `.Remove`, `.OnInsert`, and `.OnRemove`.

```lua
Data[player].questProgress.Insert(10)
Data[player].questProgress.Insert(20)
Data[player].questProgress.Insert(15, 2)

print(Data[player].questProgress()[1]) -- 10
print(Data[player].questProgress()[2]) -- 15
print(Data[player].questProgress()[3]) -- 20
```

Remove by position:

```lua
local removed = Data[player].questProgress.Remove(2)
```

Omit the position to remove the last item:

```lua
local last = Data[player].questProgress.Remove()
```

Listen to array operations:

```lua
Data[player].questProgress.OnInsert(function(item, position)
	print("Inserted", item, "at", position)
end)

Data[player].questProgress.OnRemove(function(item, position)
	print("Removed", item, "from", position)
end)
```

Skip replication for an array operation with `false`:

```lua
Data[player].questProgress.Insert(3, nil, false)
Data[player].questProgress.Remove(1, false)
```

## Dictionaries

String-keyed dictionaries work like normal nested data.

```lua
Data[player].items.sword_001({
	health = 0,
	dmg = 12,
})

print(Data[player].items.sword_001.dmg())
```

Remove dictionary entries by setting them to `nil`.

```lua
Data[player].items.sword_001(nil)
```

Listen for dictionary keys being added or removed with `.OnKeyAdded` and `.OnKeyRemoved`.

```lua
Data[player].items.OnKeyAdded(function(key, item)
	print("Added item", key, item.dmg)
end)

Data[player].items.OnKeyRemoved(function(key, item)
	print("Removed item", key, item.dmg)
end)
```

Both functions return a disconnect callback, just like `.Changed`.

These fire when a key changes from `nil` to a value, or from a value to `nil`.

```lua
Data[player].items.potion_001({
	health = 25,
	dmg = 0,
}) -- OnKeyAdded

Data[player].items.potion_001(nil) -- OnKeyRemoved
```

Changing an existing key fires `.Changed`, not `.OnKeyAdded`.

```lua
Data[player].items.potion_001.dmg(5)
```

## Options

You can pass options when creating the data module:

```lua
return DataServiceTyped({
	template = template,
	profileStoreIndex = "Default",
	profileStoreDataPrefix = "PLAYER_",
	useMock = false,
	viewedUserId = nil,
	overridenUserId = nil,
	dontSave = false,
	resetData = false,
})
```

| Option | Description |
| --- | --- |
| `template` | Required. The default data shape for every player. |
| `profileStoreIndex` | ProfileStore name. Defaults to `"Default"`. |
| `profileStoreDataPrefix` | Prefix before the user id in the profile key. Defaults to `"PLAYER_"`. |
| `useMock` | Uses ProfileStore mock storage for testing. |
| `viewedUserId` | Loads another user's data for viewing without starting a write session. |
| `overridenUserId` | Uses another user id as the active profile id. |
| `dontSave` | Loads with `GetAsync` instead of a write session. Useful for read-only testing. |
| `resetData` | Removes the profile before loading. Useful while testing data templates. |

`overridenUserId` is spelled this way in the current API.

## Next Steps

- Read about [service functions](./service-functions) for profile access, reset tools, loading hooks, and global messages.
- Browse the [complete API reference](https://leifstout.github.io/dataServiceTyped/api)
