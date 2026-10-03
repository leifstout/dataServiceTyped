local PARENT_KEY = "___P"
local KEY_KEY = "___K"
local CHILDREN_KEY = "___C"
local CONTAINER_KEY = "___X"
local REPLICATOR_KEY = "___R"
local CHANGED_KEY = "_ChangedCbs"
local ARRAY_INSERTED_KEY = "_OnInsertCbs"
local ARRAY_REMOVED_KEY = "_OnRemoveCbs"
local KEY_ADDED_KEY = "_OnKeyAddedCbs"
local KEY_REMOVED_KEY = "_OnKeyRemovedCbs"
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

local function fireCallbacks(value: Value<any>, fnKey: string, ...)
	local cbs = rawget(value, fnKey) :: any
	if not cbs then
		return
	end

	for _, cb in cbs do
		local current = rawget(value, fnKey) :: any
		if current == cbs or (current and table.find(current, cb)) then
			task.spawn(cb, ...)
		end
	end
end

local function sendChangedSignalToChildren(value: Value<any>, initial: boolean?)
	if not initial and rawget(value, CHANGED_KEY) then
		fireCallbacks(value, CHANGED_KEY, value())
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
			local changedCbs = table.clone(rawget(value, fnKey) or {}) :: any
			table.insert(changedCbs, cb)
			rawset(value, fnKey, changedCbs)

			return function()
				local updatedCbs = rawget(value, fnKey) :: any
				if not updatedCbs then
					return
				end

				local cbIndex = table.find(updatedCbs, cb)
				if not cbIndex then
					return
				end

				if #updatedCbs == 1 then
					rawset(value, fnKey, nil)
					return
				end

				updatedCbs = table.clone(updatedCbs)
				table.remove(updatedCbs, cbIndex)
				rawset(value, fnKey, updatedCbs)
			end
		end
	end
end

local Changed = createCallbackFn(CHANGED_KEY)
local OnInsert = createCallbackFn(ARRAY_INSERTED_KEY)
local OnRemove = createCallbackFn(ARRAY_REMOVED_KEY)
local OnKeyAdded = createCallbackFn(KEY_ADDED_KEY)
local OnKeyRemoved = createCallbackFn(KEY_REMOVED_KEY)

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

	local immediateParentValue = rawget(value, PARENT_KEY) :: any
	if immediateParentValue ~= nil and replicateType == "set" then
		local key = rawget(value, KEY_KEY)
		local rawValue = value()

		if prevRawValue == nil and rawValue ~= nil then
			fireCallbacks(immediateParentValue, KEY_ADDED_KEY, key, rawValue)
		elseif prevRawValue ~= nil and rawValue == nil then
			fireCallbacks(immediateParentValue, KEY_REMOVED_KEY, key, prevRawValue)
		end
	end

	repeat
		local pathKey = rawget(currentValue, KEY_KEY)
		if path and pathKey ~= nil then
			table.insert(path, pathKey)
		end

		if not replicaterFn then
			replicaterFn = rawget(currentValue, REPLICATOR_KEY)
		end

		if rawget(currentValue, CHANGED_KEY) then
			fireCallbacks(currentValue, CHANGED_KEY, currentValue(), prevRawValue, prevKey)
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

		if rawget(value, ARRAY_INSERTED_KEY) then
			fireCallbacks(value, ARRAY_INSERTED_KEY, item, pos or table.find(raw, item))
		end
	end
end

local function ArrayRemove<T>(value: Value<any>)
	return function(pos: number?, shouldReplicate: boolean?)
		local raw = value()
		local removed = table.remove(raw, pos)
		adoptChildren(value)
		fireChangeAndReplicate(value, nil, "remove", shouldReplicate, pos)

		if rawget(value, ARRAY_REMOVED_KEY) then
			fireCallbacks(value, ARRAY_REMOVED_KEY, removed, pos or #raw + 1)
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
	OnKeyAdded = OnKeyAdded,
	OnKeyRemoved = OnKeyRemoved,
}

meta.__index = function(value: Value<any>, index: string)
	local functionalKey = FUNCTIONAL_KEYS[index]
	if functionalKey then
		return functionalKey(value)
	end

	local raw = value()
	if type(raw) ~= "table" then
		error(`attempted to index '{rawget(value, KEY_KEY)}'({typeof(raw)}) with '{index}'({typeof(index)})`)
	end

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
	local parentValue = rawget(value, PARENT_KEY) :: any
	local rawParent = if parentValue then parentValue() else rawget(value, CONTAINER_KEY) :: any
	local key = rawget(value, KEY_KEY) :: any
	local hasParent = type(rawParent) == "table"
	local raw = if not hasParent then nil elseif key ~= nil then rawParent[key] else rawParent -- Root has no key

	if select("#", ...) == 0 then -- someValue()
		return raw
	end

	if not hasParent then
		error(`attempted to set '{key}' but its parent is {typeof(rawParent)}`)
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
type OnKeyAdded<T> = ((string, T) -> ()) -> () -> ()
type OnKeyRemoved<T> = ((string, T) -> ()) -> () -> ()
type ValueMeta<T> = { Changed: Changed<T> }
type ValueDictMeta<T> = { OnKeyAdded: OnKeyAdded<T>, OnKeyRemoved: OnKeyRemoved<T> }
type ValueArrayMeta<T> = {
	Remove: ArrayRemove<T>,
	Insert: ArrayInsert<T>,
	OnRemove: OnArrayRemove<T>,
	OnInsert: OnArrayInsert<T>,
}
type ValueCall<T> = ((T | (T) -> T)?, boolean?) -> T
export type ValueBase<T> = ValueCall<T> & ValueMeta<T>
export type Value<T> = ValueType<T>

-- selene: allow(undefined_variable)
type function ValueType(T)
	local node = types.newtable()
	local function addProperties(from)
		for key, prop in from:properties() do
			node:setproperty(key, prop.read)
		end
	end

	addProperties(ValueMeta(T))
	if T:is("table") then
		local indexer = T:indexer()
		if indexer and indexer.index:is("number") then -- { T }
			addProperties(ValueArrayMeta(indexer.readresult))
		elseif indexer then -- { [string]: T }
			addProperties(ValueDictMeta(indexer.readresult))
		else -- { a: x, b: y, c: z }
			addProperties(ValueDictMeta(types.any))
		end

		for key, prop in T:properties() do
			node:setproperty(key, ValueType(prop.read))
		end
		if indexer then
			node:setindexer(indexer.index, ValueType(indexer.readresult))
		end
	end

	return types.intersectionof(ValueCall(T), node)
end

function Value.new<T>(raw: T, key: string?, parent: Value<any>?, replicator: (({ string }, any?) -> ())?): ValueType<T>
	local value = setmetatable({
		[KEY_KEY] = key,
		[PARENT_KEY] = parent,
		[CONTAINER_KEY] = if parent then nil else raw, -- only the root holds its table
		[REPLICATOR_KEY] = replicator,
		[CHILDREN_KEY] = nil,
	}, meta)

	adoptChildren(value :: any)

	return value :: any
end

return Value
