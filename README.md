# ConnectionService

![Luau](https://img.shields.io/badge/Language-Luau-00A2FF.svg?style=flat-square)
![Roblox](https://img.shields.io/badge/Platform-Roblox%20Engine-000000.svg?style=flat-square)
![Complexity](https://img.shields.io/badge/Lookup-%24O(1)%24-brightgreen.svg?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)

🌐 **Languages:** **English** | [Русский](README.ru.md)

A deterministic `RunService` lifecycle dispatcher for Luau environments with native interval throttling. Engineered to manage cyclic frame callbacks, prevent tick-rate degradation, and eliminate `RBXScriptConnection` memory leaks during dynamic script execution and `loadstring` hot-reloading.

---

## Architectural Motivation

When developing Luau scripts executed outside standard compilation pipelines (e.g., via `loadstring`, runtime injectors, or live debugging consoles), engineers routinely encounter four critical issues:

1. **Orphaned `RBXScriptConnection` Leaks:** Re-executing a script without tearing down prior hooks leaves dangling closures subscribed to `RunService` signals. This causes callback multiplication per frame and progressive FPS degradation.
2. **Asynchronous Thread Stacking:** Using `task.wait()` inside frame listeners spawns independent yielding coroutines on every tick (60-144+ times per second). This leads to exponential `RemoteEvent` packet flooding, severe ping spikes, and client disconnects.
3. **Global Environment (`_G`) Pollution:** Storing raw connection handles directly inside `_G[key]` breaks encapsulation, introduces key collisions, and complicates state introspection.
4. **Execution Context Mismatches:** Subscribing to client-exclusive signals (such as `RenderStepped`) in a server context results in an immediate runtime exception.

`ConnectionService` isolates active connection descriptors inside a module-scoped hash map with $O(1)$ lookup complexity, provides a native `deltaTime` accumulator for non-yielding interval throttling, enforces idempotent task binding, and guarantees automatic teardown of previous instances via a single global runtime anchor.

---

## Task Lifecycle State Machine

Every registered task adheres to a strict finite state machine:

```text
               ┌───────────────────────┐
               │         UNBOUND       │
               └───────────────────────┘
                           │
                 Bind()    │   Unbind() / Destroy()
                           ▼
               ┌───────────────────────┐
         ┌──── │       SUSPENDED       │ ◄───┐
         │     │  (conn = nil, false)  │     │
Connect()│     │    (_elapsed = 0)     │     │ Disconnect()
         │     └───────────────────────┘     │
         │                 │                 │
         │                 │ Toggle()        │
         ▼                 ▼                 │
   ┌───────────────────────────────────────────┐
   │                  ACTIVE                   │
   │           (conn = RBXScriptConnection)    │
   │           (accumulating _elapsed += dt)   │
   └───────────────────────────────────────────┘
```

---

## Frame Pipeline & Supported Signals

The dispatcher maps string identifiers to native `RunService` signals while enforcing context safety (`Client` vs. `Server`):

| Signal Identifier | Frame Pipeline Stage | Execution Context | Primary Use Case |
| :--- | :--- | :--- | :--- |
| **`RenderStepped`** | Pre-GPU Draw | Client Only | Camera manipulation, world-to-screen projections, 2D/3D ESP overlays. Blocks the render thread. |
| **`PreSimulation`** / **`Stepped`** | Pre-PhysX Step | Client & Server | Rigid body state mutation, disabling part collisions (`CanCollide = false`), applying impulses. |
| **`Heartbeat`** / **`PostSimulation`** *(Default)* | Post-PhysX Step | Client & Server | General gameplay loops, `CFrame` teleportation, spatial queries (`Raycast`), throttled network calls. |

> **Context Fallback Guarantee:** If `RenderStepped` is requested within a server context (`RunService:IsClient() == false`), the dispatcher automatically downgrades the binding to `Heartbeat` and emits a non-fatal warning via `warn()`.

---

## Installation & Bootstrap

### Remote Bootstrap (`loadstring` via GitHub Raw)
```lua
local ConnectionService = loadstring(game:HttpGet("[https://raw.githubusercontent.com/fjdjdhidjfj/ConnectionService/main/ConnectionService.luau](https://raw.githubusercontent.com/fjdjdhidjfj/ConnectionService/main/ConnectionService.luau)"))()
```

### Standard `ModuleScript` Require
```lua
local ConnectionService = require(game:GetService("ReplicatedStorage"):WaitForChild("ConnectionService"))
```

---

## API Specification

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
Registers a named callback in the internal registry.
* **Collision Resolution:** If a task with `name` already exists, its active connection is atomically disconnected before overwriting the descriptor.
* **Interval Throttling:** When `interval > 0` is provided, the service wraps `func` inside an internal `_elapsed` time accumulator. The callback is invoked only once the accumulated `deltaTime` reaches or exceeds `interval`, passing the exact elapsed step duration as its argument.
* **Parameters:**
  * `name` - Unique string identifier for the task.
  * `func` - Closure executed on trigger. Receives `deltaTime` (seconds elapsed since the previous frame or previous throttled trigger).
  * `eventType` *(optional)* - Target `RunService` phase. Defaults to `"Heartbeat"`.
  * `autoStart` *(optional)* - Immediately transitions the task to the `ACTIVE` state. Defaults to `true`.
  * `interval` *(optional)* - Minimum execution cooldown in seconds. If omitted or `<= 0`, executes every frame.
* **Alias:** `ConnectionService.Add`

---

### `ConnectionService.Connect`
```lua
ConnectionService.Connect(name: string, forceReconnect: boolean?): boolean
```
Transitions a registered task from `SUSPENDED` to `ACTIVE`.
* Resets the internal `_elapsed` accumulator to `0`.
* Instantiates an `RBXScriptConnection` via `:Connect()`.
* If `forceReconnect == true`, tears down any existing connection before establishing a new one.
* Returns `false` if the task is unregistered or already active (when `forceReconnect` is omitted).

---

### `ConnectionService.Disconnect`
```lua
ConnectionService.Disconnect(name: string): boolean
```
Transitions a task from `ACTIVE` to `SUSPENDED`.
* Invokes `:Disconnect()` on the underlying `RBXScriptConnection` and clears the internal connection pointer.
* Resets the internal `_elapsed` accumulator to `0`.
* Retains task metadata (`func`, `eventType`, `interval`) in memory for future resumption via `Connect()` or `Toggle()`.

---

### `ConnectionService.Toggle`
```lua
ConnectionService.Toggle(name: string, enabled: boolean?): boolean
```
Inverts the active state of a task or enforces an explicit boolean state.
* If `enabled == nil`, evaluates target state as `not entry.enabled`.
* Delegates execution to `Connect()` or `Disconnect()`.

---

### `ConnectionService.Unbind`
```lua
ConnectionService.Unbind(name: string): boolean
```
Completely destroys a task entry.
* Terminates any active connection via `Disconnect(name)`.
* Assigns `_bindings[name] = nil`, removing the hash key and dropping strong references to the `func` closure so it can be reclaimed by the Luau Garbage Collector (GC).
* **Alias:** `ConnectionService.Remove`

---

### `ConnectionService.Destroy`
```lua
ConnectionService.Destroy(): ()
```
Performs a full service teardown.
* Iterates through all registered tasks and invokes `:Disconnect()`.
* Purges the internal hash table in a single C-level call via `table.clear()`.

---

## Memory Management & Hot-Reload Guarantees

To support rapid iterative workflows without client restarts, `ConnectionService` implements an automatic Singleton Cleanup pattern at module initialization:

```lua
if _G.__ConnectionServiceInstance then
    pcall(function()
        _G.__ConnectionServiceInstance.Destroy()
    end)
end
_G.__ConnectionServiceInstance = ConnectionService
```

1. **Zero Closure Retention:** Calling `Unbind(name)` sets the hash map key to `nil`. In Luau, this immediately removes the slot from the table node array, allowing the garbage collector to free upvalue memory during the next sweep phase.
2. **Idempotent Re-injection:** Executing the script multiple times via `loadstring` triggers `Destroy()` on the previous singleton instance before binding new listeners, ensuring strictly $1:1$ callback execution per frame.

---

## Production Usage Examples

### 1. Throttled Entity Polling & Network Calls (No `task.wait` Stacking)
Safely firing `RemoteEvent` calls at a fixed `0.15`s rate without spawning yielding threads or overflowing the network queue:
```lua
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remoteEvent = ReplicatedStorage:WaitForChild("Paper"):WaitForChild("Remotes"):WaitForChild("__remoteevent")
local eggsFolder = Workspace:WaitForChild("Eggs")

ConnectionService.Bind("AutoCollectEggs", function(stepTime: number)
    local eggs = eggsFolder:GetChildren()
    if #eggs == 0 then return end

    local targetEgg = eggs[1]
    if targetEgg and targetEgg.Parent then
        remoteEvent:FireServer("Collect Egg", targetEgg.Name)
        targetEgg:Destroy()
    end
end, "Heartbeat", true, 0.15)
```

### 2. Render Synchronization (Camera & Visuals)
Execute screen-space calculations synchronously prior to frame presentation (runs every frame, `interval` omitted):
```lua
ConnectionService.Bind("ViewportProjection", function(dt: number)
    local camera = workspace.CurrentCamera
    if not camera then return end
    -- Perform world-to-viewport matrix calculations
end, "RenderStepped")
```

### 3. Pre-Physics Collision Override (Noclip)
Mutate `CanCollide` properties prior to the physics step to prevent impulse rejection by the solver:
```lua
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

ConnectionService.Bind("CollisionOverride", function()
    local character = LocalPlayer.Character
    if not character then return end

    for _, part in ipairs(character:GetChildren()) do
        if part:IsA("BasePart") and part.CanCollide then
            part.CanCollide = false
        end
    end
end, "Stepped", false) -- Registered in SUSPENDED state (autoStart = false)

-- Toggle state dynamically via UI or keybind
ConnectionService.Toggle("CollisionOverride", true)
```

### 4. Graceful Teardown
Release all engine hooks when unloading your main script:
```lua
ConnectionService.Destroy()
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
