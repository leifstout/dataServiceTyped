local RunService = game:GetService("RunService")

local DataServiceClient = require(script.Parent.DataServiceClient)
local DataServiceServer = require(script.Parent.DataServiceServer)
local DataServiceUtils = require(script.Parent.DataServiceUtils)
local Value = require(script.Parent.Value)

type ServerPlayerData<T> = { [Player]: Value.Value<T> } & {
	Service: DataServiceServer.Public<T>,
}

return function<T>(options: DataServiceUtils.DataOptions<T>)
	return {
		client = (if RunService:IsClient() then DataServiceClient:init() else {}) :: Value.Value<T>,
		server = (if RunService:IsServer() then DataServiceServer:init(options) else {}) :: ServerPlayerData<T>,
	}
end
