local RunService = game:GetService("RunService")

local DataServiceClient = require(script.DataServiceClient)
local DataServiceServer = require(script.DataServiceServer)
local DataServiceUtils = require(script.DataServiceUtils)
local Value = require(script.Value)

export type Client<T> = DataServiceClient.DataServiceClient<T>
export type Server<T> = DataServiceServer.DataServiceServer<T>
export type DataOptions<T> = DataServiceUtils.DataOptions<T>
export type Value<T> = Value.Value<T>
export type PublicDataServiceServer<T> = DataServiceServer.Public<T>
export type ServerPlayerData<T> = { [Player]: Value<T> } & {
	Service: PublicDataServiceServer<T>,
	Global: Value.GlobalValue<T>,
}

return function<T>(options: DataOptions<T>)
	local client = {} :: Value<T>
	local server = {} :: ServerPlayerData<T>

	if RunService:IsClient() then
		client = DataServiceClient:init()
	end

	if RunService:IsServer() then
		local playerData, dataService, globalData = DataServiceServer:init(options)

		playerData.Service = dataService
		playerData.Global = globalData
		server = playerData
	end

	return {
		client = client :: Value<T>,
		server = server :: ServerPlayerData<T>,
	}
end
