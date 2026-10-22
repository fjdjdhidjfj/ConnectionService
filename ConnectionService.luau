local RunService = game:GetService("RunService")

local ConnectionService = {
    _bindings = {},
}

local RUN_EVENTS = {
    Heartbeat = RunService.Heartbeat,
    RenderStepped = RunService:IsClient() and RunService.RenderStepped or RunService.Heartbeat,
    Stepped = RunService.Stepped,
    PreSimulation = RunService.PreSimulation,
    PostSimulation = RunService.PostSimulation,
}

function ConnectionService.Bind(
    name: string,
    func: (deltaTime: number) -> (),
    eventType: string?,
    autoStart: boolean?,
    interval: number?
): boolean
    assert(type(name) == "string", "ConnectionService: name must be a string")
    assert(type(func) == "function", "ConnectionService: func must be a function")

    local selectedEvent = eventType or "Heartbeat"
    if not RUN_EVENTS[selectedEvent] then
        warn(string.format("[ConnectionService] Неизвестное событие '%s', выбран 'Heartbeat'", tostring(selectedEvent)))
        selectedEvent = "Heartbeat"
    end

    if ConnectionService._bindings[name] then
        ConnectionService.Disconnect(name)
    end

    ConnectionService._bindings[name] = {
        func = func,
        eventType = selectedEvent,
        interval = if interval and interval > 0 then interval else nil,
        _elapsed = 0,
        connection = nil,
        enabled = false,
    }

    if autoStart ~= false then
        ConnectionService.Connect(name)
    end

    return true
end

function ConnectionService.Connect(name: string, forceReconnect: boolean?): boolean
    local entry = ConnectionService._bindings[name]
    if not entry then
        warn(string.format("[ConnectionService] Задача '%s' не найдена", name))
        return false
    end

    if forceReconnect and entry.connection then
        ConnectionService.Disconnect(name)
    end

    if entry.connection and entry.connection.Connected then
        return false
    end

    local eventSignal = RUN_EVENTS[entry.eventType]
    entry._elapsed = 0

    local callback
    if entry.interval then
        callback = function(dt: number)
            entry._elapsed += dt
            if entry._elapsed >= entry.interval then
                local stepTime = entry._elapsed
                entry._elapsed = 0
                entry.func(stepTime)
            end
        end
    else
        callback = entry.func
    end

    entry.connection = eventSignal:Connect(callback)
    entry.enabled = true
    return true
end

function ConnectionService.Disconnect(name: string): boolean
    local entry = ConnectionService._bindings[name]
    if not entry or not entry.connection then
        return false
    end

    if entry.connection.Connected then
        entry.connection:Disconnect()
    end
    entry.connection = nil
    entry.enabled = false
    entry._elapsed = 0
    return true
end

function ConnectionService.Toggle(name: string, enabled: boolean?): boolean
    local entry = ConnectionService._bindings[name]
    if not entry then return false end

    local targetState = if enabled ~= nil then enabled else not entry.enabled
    if targetState then
        return ConnectionService.Connect(name)
    else
        return ConnectionService.Disconnect(name)
    end
end

function ConnectionService.Unbind(name: string): boolean
    ConnectionService.Disconnect(name)
    ConnectionService._bindings[name] = nil
    return true
end

function ConnectionService.Destroy(): ()
    for name, _ in pairs(ConnectionService._bindings) do
        ConnectionService.Disconnect(name)
    end
    table.clear(ConnectionService._bindings)
end

ConnectionService.Add = ConnectionService.Bind
ConnectionService.Remove = ConnectionService.Unbind

if _G.__ConnectionServiceInstance then
    pcall(function()
        _G.__ConnectionServiceInstance.Destroy()
    end)
end
_G.__ConnectionServiceInstance = ConnectionService

return ConnectionService
