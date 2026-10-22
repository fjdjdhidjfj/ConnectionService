<div align="center">

# ConnectionService

[![Language](https://img.shields.io/badge/Language-Luau-blue.svg)](https://luau-lang.org/)
[![Platform](https://img.shields.io/badge/Platform-Roblox-black.svg)](https://roblox.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**[ 🇷🇺 Перейти к русскоязычной документации ](README.ru.md)**

</div>

---

Modular `RunService` connection dispatcher for Luau with native interval throttling, hot-reload safety, and zero global namespace pollution. Eliminates frame rate drops caused by duplicate threads and guarantees clean teardown during hot-reloads via `loadstring`.

---

## Features

* **Hot-Reload Idempotency:** Automatically shuts down stale connections via `_G.__ConnectionServiceInstance` when re-executed in runtime.
* **Native Interval Throttling:** Built-in `interval` accumulator allows scheduling periodic actions (0.1s, 0.5s, 1s) directly on frame cycles without `task.wait()` desync or thread stacking.
* **Zero `_G` Pollution:** Isolates all active `RBXScriptConnection` descriptors inside a localized module registry table.
* **Context Fallback:** Automatically redirects client-only signals (`RenderStepped`) to `Heartbeat` when executed in a server environment.
* **Instant State Toggling:** Pause and resume scheduled tasks on the fly while retaining configuration metadata.

---

## Installation

### Remote Fetch (`loadstring`)
```lua
local ConnectionService = loadstring(game:HttpGet("[https://raw.githubusercontent.com/fjdjdhidjfj/ConnectionService/main/ConnectionService.luau](https://raw.githubusercontent.com/fjdjdhidjfj/ConnectionService/main/ConnectionService.luau)"))()
