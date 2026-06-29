---
sidebar_position: 1
---

# Setup for DataServiceTyped

**DataServiceTyped** provides a simple way to manage player data on the server while keeping clients in sync automatically.

## Installation

Add `DataServiceTyped` to your `wally.toml`:

```toml
[dependencies]
DataServiceTyped = "leifstout/dataservicetyped@1.0.3"
```

This will install the newest version of `DataServiceTyped` for the major version `1`.
> To enforce a specific version, replace `@` with `@=` followed by the version you want.

Then run:

```bash
wally install
```

## Define your Data

Create a `Data.luau` module for your data:

```lua
local DataServiceTyped = require(Packages.DataServiceTyped)

-- Dictionary type information
type ItemData = {
	health: number,
	dmg: number
}

-- This is the data template for each player. This can be anything.
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

-- See `DataServiceUtils.DataOptions` for more information.
return DataServiceTyped({
	template = template,
	useMock = false,
	resetData = false,
})
```

> Keep values JSON-compatible (e.g. numbers, strings, booleans, arrays, dictionaries, or null). That means no CFrames, Vector3s, etc.

## Usage on the Server

Index `Data` with a [Player](https://create.roblox.com/docs/en-us/reference/engine/classes/Player) to interact with their data:

```lua
local Data = require(Path.To.Data)

-- This changes the indexed player's `currency` to the value of `50`
-- This get replicated to the client.
Data[player].currency(50)
```

## Usage on the Client

Use `Data` directly on the client:

```lua
local Data = require(Path.To.Data)

-- This changes the local player's `currency` to the value of `50`
-- This does not get replicated to the server.
Data.currency(50)

-- This listens for changes of the local player's `inventory.apples` value.
Data.inventory.apples.Changed(function(n: number)
	print("Apples changed to", n)
end)
```

## Next steps

- Browse the [**complete API reference**](https://leifstout.github.io/dataServiceTyped/api)
