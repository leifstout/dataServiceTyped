---
sidebar_position: 1
---

# Getting Started with DataServiceTyped

DataService provides a simple way to manage player data on the server while keeping clients in sync automatically.

## 1) Install

Add DataService to your `wally.toml`:

```toml
[dependencies]
DataServiceTyped = "leifstout/dataservicetyped@1.0.0"
```

Then run:

```bash
wally install
```

## 2) Define your Data

Create a Data.luau module for your data:

```lua
local DataServiceTyped = require(Packages.DataServiceTyped)

local template = {
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

return DataServiceTyped({
	template = template,
	useMock = false,
	resetData = false,
})
```

> Keep values JSON-compatible (numbers, strings, booleans, arrays, dictionaries).

## 3) Usage on server

Index Data with a player to interact with their data:

```lua
local Data = require(Path.To.Data)

Data.server[player].currency(50)
```

Use the `Global` field to interact with every player's data at once:

```lua
local Data = require(Path.To.Data)

Data.server.Global.currency.Add(5)

Data.server.Global.currency.Changed(function(player: Player, newValue: number, oldValue: number)
	print(player.Name, oldValue, "->", newValue)
end)
```

Global mutations use each loaded player's normal data value, so their individual
`Changed` callbacks still run and each change replicates to the correct client.
Global `Changed` callbacks also run for mutations made through `Data.server[player]`.

## 4) Usage on client

Use Data directly on the client:

```lua
local Data = require(Path.To.Data)

Data.client.currency(50)

Data.client.inventory.apples.Changed(function(n: number)
	print("Apples changed to", n)
end)
```

## Next steps

- Browse the **complete API reference**: https://leifstout.github.io/dataServicetyped/api
