# ConnectionService

A lightweight, robust wrapper for managing Roblox `RunService` event connections (`Heartbeat`, `RenderStepped`, `Stepped`, `PreSimulation`, `PostSimulation`) by unique keys. It includes built-in execution throttling (interval timers), toggleable states, and hot-reload safety.

[![Luau](https://img.shields.io/badge/Language-Luau-blue.svg)](https://luau.org/)
[![Platform](https://img.shields.io/badge/Platform-Roblox-red.svg)](https://roblox.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

[**Русская версия документации (README_ru.md)**](README_ru.md)

---

## Features

- **Keyed Connections**: Bind and control loops by name without keeping track of `RBXScriptConnection` variables.
- **Interval Throttling**: Run callbacks at custom time intervals (e.g., every `0.5` seconds) instead of every single frame, passing accumulated `deltaTime`.
- **Pause & Resume**: Easily enable, disable, or toggle tasks without destroying their configuration.
- **Server/Client Safe**: Safely references client-only events like `RenderStepped` on the server by automatically falling back to `Heartbeat`.
- **Hot-Reload Friendly**: Automatically cleans up running connections when the module is re-executed in test environments via `_G`.
- **Type-Checked**: Written in strict typed Luau.

---

## Installation

### Method 1: Local ModuleScript (Recommended)

1. Create a `ModuleScript` named `ConnectionService` inside `ReplicatedStorage` (or `ServerScriptService` / client container depending on your scope).
2. Paste the source code into the `ModuleScript`.
3. Require it from any `Script` or `LocalScript`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConnectionService = require(ReplicatedStorage:WaitForChild("ConnectionService"))
```

### Method 2: Dynamic Load via `loadstring`

You can load the latest version directly over HTTP (useful for test environments, command bars, or external script loaders):

```lua
local ConnectionService = loadstring(game:HttpGet("https://raw.githubusercontent.com/fjdjdhidjfj/ConnectionService/refs/heads/main/ConnectionService.luau"))()
```

---

## Quick Start

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConnectionService = require(ReplicatedStorage.ConnectionService)

-- Bind a simple Heartbeat loop
ConnectionService.Bind("RotatePart", function(dt)
    workspace.Part.CFrame *= CFrame.Angles(0, math.rad(90) * dt, 0)
end)

-- Later, pause it:
ConnectionService.Disconnect("RotatePart")

-- Resume it:
ConnectionService.Connect("RotatePart")

-- Permanently remove it when no longer needed:
ConnectionService.Unbind("RotatePart")
```

---

## API Reference

### `ConnectionService.Bind`
```lua
ConnectionService.Bind(
    name: string,
    func: (deltaTime: number) -> (),
    eventType: string?,
    autoStart: boolean?,
    interval: number?
): boolean
```
Registers a new task. If a task with `name` already exists, it is disconnected and overwritten.

- **Parameters:**
  - `name`: Unique identifier for the connection.
  - `func`: Callback function receiving `deltaTime` (in seconds). If an `interval` is set, `deltaTime` equals the accumulated elapsed time since the last call.
  - `eventType` *(optional, default = `"Heartbeat"`)*: Target `RunService` event name.
  - `autoStart` *(optional, default = `true`)*: Whether to connect immediately. Pass `false` to register without starting.
  - `interval` *(optional)*: Minimum duration (in seconds) between invocations. If `nil` or `<= 0`, runs every frame.
- **Returns:** `true` on success.
- **Alias:** `ConnectionService.Add`

---

### `ConnectionService.Connect`
```lua
ConnectionService.Connect(name: string, forceReconnect: boolean?): boolean
```
Activates an existing task.

- **Parameters:**
  - `name`: Target task name.
  - `forceReconnect` *(optional, default = `false`)*: If `true`, resets any active connection before reconnecting.
- **Returns:** `true` if connected successfully; `false` if the task does not exist or is already running.

---

### `ConnectionService.Disconnect`
```lua
ConnectionService.Disconnect(name: string): boolean
```
Pauses a running task. The task configuration remains saved and can be resumed later.

- **Parameters:**
  - `name`: Target task name.
- **Returns:** `true` if disconnected; `false` if not found or already inactive.

---

### `ConnectionService.Toggle`
```lua
ConnectionService.Toggle(name: string, enabled: boolean?): boolean
```
Toggles the active state of a registered task.

- **Parameters:**
  - `name`: Target task name.
  - `enabled` *(optional)*: Explicit target state (`true` to connect, `false` to disconnect). If omitted, flips the current state.
- **Returns:** `true` on state change, `false` if the task is not registered.

---

### `ConnectionService.Unbind`
```lua
ConnectionService.Unbind(name: string): boolean
```
Disconnects the task and permanently deletes it from internal memory.

- **Parameters:**
  - `name`: Target task name.
- **Returns:** `true`.
- **Alias:** `ConnectionService.Remove`

---

### `ConnectionService.Destroy`
```lua
ConnectionService.Destroy(): ()
```
Disconnects all active connections and cleans the internal registry. Ideal for teardown or state resets.

---

## Supported Events

| Event Name | Scope | Description |
| :--- | :--- | :--- |
| `Heartbeat` *(default)* | Client & Server | Fires every frame after physics calculation. |
| `RenderStepped` | Client only | Fires every frame prior to frame rendering. *(Automatically falls back to `Heartbeat` if called on the server)*. |
| `Stepped` | Client & Server | Fires every frame prior to physics simulation. |
| `PreSimulation` | Client & Server | Newer API alternative for `Stepped`. |
| `PostSimulation` | Client & Server | Newer API alternative for `Heartbeat`. |

*Note: If an invalid event name is passed, the service logs a warning and falls back to `Heartbeat`.*

---

## Usage Examples

### 1. Throttled Loop (Regeneration / Interval Task)
Run logic every 0.5 seconds instead of every single frame:

```lua
ConnectionService.Bind(
    "RegenTick",
    function(elapsedTime)
        player.Health = math.min(100, player.Health + (5 * elapsedTime))
    end,
    "Heartbeat",
    true,
    0.5 -- Runs every 0.5 seconds
)
```

### 2. Client Camera Follow (`RenderStepped`)
Update visual elements immediately before frame rendering:

```lua
ConnectionService.Bind(
    "CustomCamera",
    function(dt)
        local character = player.Character
        if character and character:FindFirstChild("Head") then
            camera.CFrame = CFrame.new(character.Head.Position + Vector3.new(0, 5, 10), character.Head.Position)
        end
    end,
    "RenderStepped"
)
```

### 3. Pause & Resume Task via UI
```lua
local isRunning = true

pauseButton.Activated:Connect(function()
    isRunning = not isRunning
    ConnectionService.Toggle("GameLoop", isRunning)
    pauseButton.Text = isRunning and "Pause" or "Resume"
end)
```

---

## License

This project is licensed under the MIT License.
