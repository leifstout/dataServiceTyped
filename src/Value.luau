local PARENT_KEY = "___P"
local KEY_KEY = "___K"
local CHILDREN_KEY = "___C"
local CONTAINER_KEY = "___X"
local REPLICATOR_KEY = "___R"
local CHANGED_KEY = "_ChangedCbs"
local ARRAY_INSERTED_KEY = "_OnInsertCbs"
local ARRAY_REMOVED_KEY = "_OnRemoveCbs"
local meta = {}
local Value = { shouldRecordPath = false }

local function adoptChildren(value: Value<any>)
	local raw = value()
	if type(raw) ~= "table" then
		return
	end

	local children = rawget(value, CHILDREN_KEY) :: { [any]: any }
	if not children then
		children = {}
		rawset(value, CHILDREN_KEY, children)
	end

	for key, _ in raw :: any do
		local childValue = children[key]
		if not childValue then
			childValue = Value.new(raw, key, value)
			children[key] = childValue
		end
	end

	for key, childValue in children do
		rawset(childValue, CONTAINER_KEY, raw)
		if raw[key] ~= nil then
			continue
		end

		-- Maybe change to hasCallbackDeep in future
		local hasChangedCallback = rawget(childValue, CHANGED_KEY) ~= nil
		if not hasChangedCallback then
			children[key] = nil
		end
	end
end

local function sendChangedSignalToChildren(value: Value<any>, initial: boolean?)
	if not initial then
		local changedCbs = rawget(value, CHANGED_KEY) :: any
		if changedCbs then
			local raw = value()
			for _, cb in changedCbs do
				task.spawn(cb, raw)
			end
		end
	end

	local childrenValues = rawget(value, CHILDREN_KEY)
	if not childrenValues then
		return
	end

	for _, childValue in childrenValues do
		sendChangedSignalToChildren(childValue)
	end
end

local function createCallbackFn(fnKey: string)
	return function(value: Value<any>)
		return function<T>(cb: (T) -> () -> ())
			local changedCbs = rawget(value, fnKey) :: any
			if not changedCbs then
				changedCbs = {}
				rawset(value, fnKey, changedCbs)
			end

			table.insert(changedCbs, cb)
			return function()
				local updatedCbs = rawget(value, fnKey) :: any
				if not updatedCbs then
					return
				end

				local cbIndex = table.find(updatedCbs, cb)
				if not cbIndex then
					return
				end

				table.remove(updatedCbs, cbIndex)
				if #updatedCbs == 0 then
					rawset(value, fnKey, nil)
				end
			end
		end
	end
end

local Changed = createCallbackFn(CHANGED_KEY)
local OnInsert = createCallbackFn(ARRAY_INSERTED_KEY)
local OnRemove = createCallbackFn(ARRAY_REMOVED_KEY)

local function fireChangeAndReplicate<T>(
	value: Value<T>,
	prevRawValue: T?,
	replicateType: string?,
	forcedReplication: boolean?,
	...
)
	local shouldReplicate = forcedReplication ~= false
	local path = if Value.shouldRecordPath and shouldReplicate then {} else nil
	local currentValue: any = value
	local prevKey = nil
	local replicaterFn

	repeat
		local pathKey = rawget(currentValue, KEY_KEY)
		if path and pathKey ~= nil then
			table.insert(path, pathKey)
		end

		if not replicaterFn then
			replicaterFn = rawget(currentValue, REPLICATOR_KEY)
		end

		local changedCbs = rawget(currentValue, CHANGED_KEY) :: any
		if changedCbs then
			local v = currentValue()
			for _, cb in changedCbs do
				task.spawn(cb, v, prevRawValue, prevKey)
			end
		end

		prevKey = pathKey
		currentValue = rawget(currentValue, PARENT_KEY) :: any
	until currentValue == nil

	if shouldReplicate and replicaterFn then
		(replicaterFn :: any)(replicateType, path, ...)
	end
end

local function ArrayInsert<T>(value: Value<any>)
	return function(item: T, pos: number?, shouldReplicate: boolean?)
		local raw = value()
		if pos then
			table.insert(raw, pos, item)
		else
			table.insert(raw, item)
		end

		adoptChildren(value)
		fireChangeAndReplicate(value, nil, "insert", shouldReplicate, item, pos)

		local insertedCbs = rawget(value, ARRAY_INSERTED_KEY)
		if insertedCbs then
			local posInsertedAt = pos or table.find(raw, item)
			for _, cb in insertedCbs do
				task.spawn(cb, item, posInsertedAt)
			end
		end
	end
end

local function ArrayRemove<T>(value: Value<any>)
	return function(pos: number?, shouldReplicate: boolean?)
		local raw = value()
		local removed = table.remove(raw, pos)
		adoptChildren(value)
		fireChangeAndReplicate(value, nil, "remove", shouldReplicate, pos)

		local removedCbs = rawget(value, ARRAY_REMOVED_KEY)
		if removedCbs then
			local posRemovedFrom = pos or #raw + 1
			for _, cb in removedCbs do
				task.spawn(cb, removed, posRemovedFrom)
			end
		end

		return removed
	end
end

local FUNCTIONAL_KEYS = {
	Changed = Changed,
	Insert = ArrayInsert,
	Remove = ArrayRemove,
	OnInsert = OnInsert,
	OnRemove = OnRemove,
}

meta.__index = function(value: Value<any>, index: string)
	local functionalKey = FUNCTIONAL_KEYS[index]
	if functionalKey then
		return functionalKey(value)
	end

	local raw = value()
	assert(
		type(raw) == "table",
		`attempted to index '{rawget(value, KEY_KEY)}'({typeof(raw)}) with '{index}'({typeof(index)})`
	)

	local valueChildren = rawget(value, CHILDREN_KEY) :: any
	if valueChildren and valueChildren[index] ~= nil then
		return valueChildren[index]
	end

	-- Adding new child index
	local newChild = Value.new(raw, index, value)
	if not valueChildren then
		valueChildren = {}
		rawset(value, CHILDREN_KEY, valueChildren)
	end
	valueChildren[index] = newChild

	return newChild
end

meta.__call = function(value: Value<any>, ...)
	local rawParent = rawget(value, CONTAINER_KEY) :: any
	local key = rawget(value, KEY_KEY) :: any
	local raw = if key ~= nil then rawParent[key] else rawParent -- Root has no key

	if select("#", ...) == 0 then -- someValue()
		return raw
	end

	local param, shouldReplicate = ...
	if type(param) == "function" then
		rawParent[key] = (param :: any)(raw) -- someValue(fn(prev) return prev + 1 end)
	else
		rawParent[key] = param -- someValue(1)
	end

	local updatedRaw = rawParent[key]
	adoptChildren(value)
	sendChangedSignalToChildren(value, true)
	fireChangeAndReplicate(value, raw, "set", shouldReplicate, updatedRaw)

	return updatedRaw
end

type ArrayRemove<T> = (number?, boolean?) -> T
type ArrayInsert<T> = (T, number?, boolean?) -> ()
type OnArrayRemove<T> = ((T, number?) -> ()) -> () -> ()
type OnArrayInsert<T> = ((T, number?) -> ()) -> () -> ()
type Changed<T> = ((T, T, string?) -> ()) -> () -> ()
type ValueMeta<T> = { Changed: Changed<T> }
type ValueArrayMeta<T> = {
	Remove: ArrayRemove<T>,
	Insert: ArrayInsert<T>,
	OnRemove: OnArrayRemove<T>,
	OnInsert: OnArrayInsert<T>,
}
export type ValueBase<T> = (((T | (T) -> T)?, boolean?) -> T) & ValueMeta<T>
type ValueArrayBase<T, U> = ValueBase<T> & ValueArrayMeta<U>
export type Value<T> = ValueType<T>

-- selene: allow(undefined_variable)
type function ValueType(T)
	local base = ValueBase(T)
	if not T:is("table") then
		return base
	end

	local indexer = T:indexer()
	if indexer then -- { [string]: T } or { any }
		local new = types.newtable()
		local index = indexer.index
		local result = indexer.readresult
		local valueBase = if index:is("number") then ValueArrayBase(T, result) else base

		new:setindexer(index, ValueType(result))
		return types.intersectionof(valueBase, new)
	else -- { a: x, b: y, c: z }
		local children = types.newtable()
		for key, prop in T:properties() do
			children:setproperty(key, ValueType(prop.read))
		end

		return types.intersectionof(base, children)
	end
end

function Value.new<T>(raw: T, key: string?, parent: Value<any>?, replicator: (({ string }, any?) -> ())?): ValueType<T>
	local value = setmetatable({
		[KEY_KEY] = key,
		[PARENT_KEY] = parent,
		[CONTAINER_KEY] = raw,
		[REPLICATOR_KEY] = replicator,
		[CHILDREN_KEY] = nil,
	}, meta)

	adoptChildren(value :: any)

	return value :: any
end

return Value
