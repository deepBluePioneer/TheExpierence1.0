local HttpService = game:GetService("HttpService")
local Promise = require(script.Parent.Promise)
local TableUtil = require(script.Parent.TableUtil)

export type SearchPredicate = (Instance) -> boolean
export type SearchQuery = {
    Tag: string?,
    ClassName: string?,
    Name: string?,
    Predicate: SearchPredicate?,
}

local DEFAULT_TIMEOUT = 10

local Waiter = {}

Waiter._trackedQueries = {}
setmetatable(Waiter._trackedQueries, {__mode = "v"})

--[[
    Returns a list of all the instances that match a predicate.
]]
function Waiter.get(list: {Instance}, predicate: SearchPredicate): {Instance?}
    return TableUtil.Filter(list, predicate)
end

--[[
    Returns the first instance that matches a predicate.
]]
function Waiter.getFirst(list: {Instance}, predicate: SearchPredicate): Instance?
    return Waiter.get(list, predicate)[1]
end

--[[
    Returns a `Promise` that resolves when an instance that matches the predicate is found.
    *Note: Default promise timeout is 10 seconds.*
]]
function Waiter.waitFor(list: {Instance}, predicate: SearchPredicate, timeout: number?)
    return Promise.new(function(resolve, _, onCancel)
        local cancelled = false
        onCancel(function()
            cancelled = true
        end)
        while not cancelled do
            local result = Waiter.getFirst(list, predicate)
            if result ~= nil then
                resolve(result)
                return
            end
            task.wait()
        end
    end)
    :catch(function(err)
        error(`Waiter.waitFor() failed: {err}`)
    end)
    :timeout(timeout or DEFAULT_TIMEOUT)
end

--[[
    Returns all the descendants of an instance.
]]
function Waiter.descendants(instance: Instance): {Instance?}
    local key = HttpService:GenerateGUID()
    local list = instance:GetDescendants()
    Waiter._trackedQueries[key] = list
    local addedConnection
    local removedConnection
    addedConnection = instance.DescendantAdded:Connect(function(descendant: Instance)
        if Waiter._trackedQueries[key] == nil then
            addedConnection:Disconnect()
            removedConnection:Disconnect()
        else
            table.insert(Waiter._trackedQueries[key], descendant)
        end
    end)
    removedConnection = instance.DescendantRemoving:Connect(function(descendant: Instance)
        if Waiter._trackedQueries[key] == nil then
            addedConnection:Disconnect()
            removedConnection:Disconnect()
        else
            local index = table.find(Waiter._trackedQueries[key], descendant)
            table.remove(Waiter._trackedQueries[key], index)
        end
    end)
    return Waiter._trackedQueries[key]
end

--[[
    Returns all the children of an instance.
]]
function Waiter.children(instance: Instance): {Instance?}
    local key = HttpService:GenerateGUID()
    local list = instance:GetChildren()
    Waiter._trackedQueries[key] = list
    local addedConnection
    local removedConnection
    addedConnection = instance.ChildAdded:Connect(function(child: Instance)
        if Waiter._trackedQueries[key] == nil then
            addedConnection:Disconnect()
            removedConnection:Disconnect()
        else
            table.insert(Waiter._trackedQueries[key], child)
        end
    end)
    removedConnection = instance.ChildRemoved:Connect(function(child: Instance)
        if Waiter._trackedQueries[key] == nil then
            addedConnection:Disconnect()
            removedConnection:Disconnect()
        else
            local index = table.find(Waiter._trackedQueries[key], child)
            table.remove(Waiter._trackedQueries[key], index)
        end
    end)
    return Waiter._trackedQueries[key]
end

--[[
    Returns all the siblings of an instance.
]]
function Waiter.siblings(instance: Instance): {Instance?}
    local key = HttpService:GenerateGUID()
    local list = instance.Parent:GetChildren()
    Waiter._trackedQueries[key] = list
    local index = table.find(Waiter._trackedQueries[key], instance)
    table.remove(Waiter._trackedQueries[key], index)
    local addedConnection
    local removedConnection
    addedConnection = instance.Parent.ChildAdded:Connect(function(child: Instance)
        if Waiter._trackedQueries[key] == nil then
            addedConnection:Disconnect()
            removedConnection:Disconnect()
        elseif child ~= instance then
            table.insert(Waiter._trackedQueries[key], child)
        end
    end)
    removedConnection = instance.Parent.ChildRemoved:Connect(function(child: Instance)
        if Waiter._trackedQueries[key] == nil then
            addedConnection:Disconnect()
            removedConnection:Disconnect()
        elseif child ~= instance then
            index = table.find(Waiter._trackedQueries[key], child)
            table.remove(Waiter._trackedQueries[key], index)
        end
    end)
    return Waiter._trackedQueries[key]
end

--[[
    Returns all the ancestors of an instance.
    *Note: Excludes the datamodel itself.*
]]
function Waiter.ancestors(instance: Instance): {Instance?}
    local function getAncestors(): {Instance?}
        local ancestors = {}
        local current = instance
        while current ~= game do
            if current.Parent == nil then break end
            current = current.Parent
            table.insert(ancestors, current)
        end
        return ancestors
    end
    local key = HttpService:GenerateGUID()
    local list = getAncestors()
    Waiter._trackedQueries[key] = list
    if instance == game then
        return Waiter._trackedQueries[key]
    end
    local ancestryConnection
    ancestryConnection = instance.AncestryChanged:Connect(function(_: Instance, _: Instance)
        if Waiter._trackedQueries[key] == nil then
            ancestryConnection:Disconnect()
        else
            local newAncestors = getAncestors()
            if #newAncestors == 0 then
                Waiter._trackedQueries[key] = {}
                return
            end
            table.clear(Waiter._trackedQueries[key])
            for _, newAncestor in newAncestors do
                table.insert(Waiter._trackedQueries[key], newAncestor)
            end
        end
    end)
    return Waiter._trackedQueries[key]
end

--[[
    Returns a `SearchPredicate` that matches instances with a specific tag.
]]
function Waiter.matchTag(tagQuery: string): SearchPredicate
    return function(instance: Instance): boolean
        return instance:HasTag(tagQuery)
    end
end

--[[
    Returns a `SearchPredicate` that matches instances with a specific attribute.
]]
function Waiter.matchAttribute(name: string, value: any): SearchPredicate
    return function(instance: Instance): boolean
        return instance:GetAttribute(name) == value
    end
end

--[[
    Returns a `SearchPredicate` that matches instances with a specific class name.
]]
function Waiter.matchClassName(className: string): SearchPredicate
    return function(instance: Instance): boolean
        return instance:IsA(className)
    end
end

--[[
    Returns a `SearchPredicate` that matches instances with a specific name.
]]
function Waiter.matchName(name: string): SearchPredicate
    return function(instance: Instance): boolean
        return instance.Name == name
    end
end

--[[
    Returns a `SearchPredicate` that matches instances with a specific combination of queries.
]]
function Waiter.matchQuery(query: SearchQuery): SearchPredicate
    return function(instance: Instance): boolean
        local matches = true
        if query.Tag ~= nil then
            matches = matches and Waiter.matchTag(query.Tag)(instance)
        end
        if query.ClassName ~= nil then
            matches = matches and Waiter.matchClassName(query.ClassName)(instance)
        end
        if query.Name ~= nil then
            matches = matches and Waiter.matchName(query.Name)(instance)
        end
        if query.Predicate ~= nil then
            matches = matches and query.Predicate(instance)
        end
        return matches
    end
end

return Waiter