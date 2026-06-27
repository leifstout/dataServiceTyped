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
}

return function<T>(options: DataOptions<T>)
	return {
		client = (if RunService:IsClient() then DataServiceClient:init() else {}) :: Value<T>,
		server = (if RunService:IsServer() then DataServiceServer:init(options) else {}) :: ServerPlayerData<T>,
	}
end
