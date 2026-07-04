local DataServiceUtils = {}

export type DataOptions<T> = {
	template: T,
	useMock: boolean?,
	viewedUserId: number?,
	overridenUserId: number?,
	dontSave: boolean?,
	resetData: boolean?,
	profileStoreIndex: string?,
	profileStoreDataPrefix: string?,
}

function DataServiceUtils.deepClone<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end

	local cloned = table.clone(value :: any)
	for key, child in cloned do
		cloned[key] = DataServiceUtils.deepClone(child)
	end

	return cloned :: any
end

return DataServiceUtils
