local RunService = game:GetService("RunService")

local Packages = script.Parent.Parent
local Signal = require(Packages.Signal)
local Networker = require(Packages.Networker)
local Value = require(script.Parent.Value)

if RunService:IsServer() then
	return {} :: any
end

local DataServiceClient = {
	hasLoaded = false,
	loadedSignal = Signal.new(),
}

function DataServiceClient.init<T>(self: DataServiceClient<T>, template: T)
	self.networker = Networker.client.new("DataService", self)

	if not RunService:IsRunning() then
		self:load(template)
	end

	if self.hasLoaded then
		return self.data
	end

	self.loadedSignal:Wait()

	return self.data
end

function DataServiceClient.load<T>(self: DataServiceClient<T>, data: T)
	self.data = Value.new(data)
	self.hasLoaded = true
	self.loadedSignal:Fire()
end

function DataServiceClient.get<T>(self: DataServiceClient<T>, path: { string }): Value.Value<any>
	if not self.hasLoaded then
		self.loadedSignal:Wait()
	end

	local current = self.data
	for i = #path, 2, -1 do
		local key = path[i]
		current = (current :: any)[key]
	end

	return current[path[1]]
end

function DataServiceClient.set<T>(self: DataServiceClient<T>, path: { string }, value: any?)
	self:get(path)(value)
end

function DataServiceClient.insert<T>(self: DataServiceClient<T>, path: { string }, item: any, pos: number?)
	self:get(path).Insert(item, pos)
end

function DataServiceClient.remove<T>(self: DataServiceClient<T>, path: { string }, pos: number?)
	self:get(path).Remove(pos)
end

export type DataServiceClient<T> = typeof(DataServiceClient) & {
	hasLoaded: boolean,
	loadedSignal: Signal.Signal<>,
	networker: Networker.Client,
	data: Value.Value<T>,
}

return DataServiceClient
