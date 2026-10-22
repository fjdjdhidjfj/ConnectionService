# ConnectionService

Легковесный и удобный менеджер подключений к событиям `RunService` (`Heartbeat`, `RenderStepped`, `Stepped`, `PreSimulation`, `PostSimulation`) в Roblox. Предоставляет возможность управления циклами по строковым именам, поддержку таймеров с заданным интервалом (троттлинг), паузу/возобновление и защиту от утечек при перезагрузке скрипта.

[**English Documentation (README.md)**](README.md)

---

## Преимущества

* **Именованные подключения**: Не нужно хранить переменные объектов `RBXScriptConnection` в каждом скрипте - управление происходит по ключу (`name`).
* **Интервалы выполнения (троттлинг)**: Вызов функции с заданной периодичностью (например, каждые `0.2` сек) вместо каждого кадра с передачей накопившегося `deltaTime`.
* **Пауза и переключение**: Функции `Disconnect`, `Connect` и `Toggle` позволяют временно останавливать задачи без удаления их настроек.
* **Безопасность сервер/клиент**: Защита от случайного вызова клиентского `RenderStepped` на сервере (модуль автоматически переключает его на `Heartbeat`).
* **Hot-Reload / Перезапуск**: Автоматическая очистка старых подключений через `_G` при повторном запуске скрипта (удобно во время тестирования и пересборки).
* **Строгая типизация**: Полная поддержка Luau Type Checking.

---

## Установка

### Способ 1: Локальный ModuleScript (Рекомендуемый)

1. Создайте `ModuleScript` с именем `ConnectionService` в `ReplicatedStorage` (или в `ServerScriptService` / клиентской папке).
2. Скопируйте исходный код в созданный `ModuleScript`.
3. Подключите модуль в нужном скрипте:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConnectionService = require(ReplicatedStorage:WaitForChild("ConnectionService"))
```

### Способ 2: Загрузка через `loadstring`

Для быстрого тестирования, использования в командной строке Studio или внешних загрузчиках можно выполнить загрузку напрямую по URL:

```lua
local ConnectionService = loadstring(game:HttpGet("https://raw.githubusercontent.com/fjdjdhidjfj/ConnectionService/refs/heads/main/ConnectionService.luau"))()
```

---

## Быстрый старт

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConnectionService = require(ReplicatedStorage.ConnectionService)

-- Привязка покадрового обновления
ConnectionService.Bind("RotateCoin", function(dt)
    workspace.Coin.CFrame *= CFrame.Angles(0, math.rad(90) * dt, 0)
end)

-- Приостановка задачи:
ConnectionService.Disconnect("RotateCoin")

-- Возобновление работы:
ConnectionService.Connect("RotateCoin")

-- Полное удаление, когда задача больше не нужна:
ConnectionService.Unbind("RotateCoin")
```

---

## Справочник API

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

Регистрирует новую задачу. Если задача с таким `name` уже существовала, она будет предварительно отключена и перезаписана.

* **Параметры:**
  * `name`: Уникальное имя (ключ) подключения.
  * `func`: Функция обратного вызова, принимающая `deltaTime` (в секундах). Если задан `interval`, передается суммарное время, прошедшее с предыдущего вызова.
  * `eventType` *(опционально, по умолчанию `"Heartbeat"`)*: Имя события `RunService`.
  * `autoStart` *(опционально, по умолчанию `true`)*: Запускать ли цикл сразу после регистрации. Передайте `false`, если хотите лишь зарегистрировать задачу.
  * `interval` *(опционально)*: Интервал вызова в секундах. Если `nil` или `<= 0`, функция выполняется каждый кадр.
* **Возвращает:** `true` при успешной привязке.
* **Алиас:** `ConnectionService.Add`

---

### `ConnectionService.Connect`

```lua
ConnectionService.Connect(name: string, forceReconnect: boolean?): boolean
```

Активирует ранее зарегистрированную или приостановленную задачу.

* **Параметры:**
  * `name`: Имя задачи.
  * `forceReconnect` *(опционально, по умолчанию `false`)*: Если `true`, отключает активное соединение и подключает заново с обнулением таймера.
* **Возвращает:** `true`, если подключение прошло успешно; `false`, если задача не найдена или уже активна.

---

### `ConnectionService.Disconnect`

```lua
ConnectionService.Disconnect(name: string): boolean
```

Приостанавливает выполнение задачи. Параметры задачи сохраняются, и её можно активировать снова через `Connect`.

* **Параметры:**
  * `name`: Имя задачи.
* **Возвращает:** `true`, если соединение разорвано; `false`, если задача не найдена или уже выключена.

---

### `ConnectionService.Toggle`

```lua
ConnectionService.Toggle(name: string, enabled: boolean?): boolean
```

Переключает состояние задачи (включено / выключено).

* **Параметры:**
  * `name`: Имя задачи.
  * `enabled` *(опционально)*: Желаемое состояние (`true` для включения, `false` для выключения). Если параметр не передан, текущее состояние меняется на противоположное.
* **Возвращает:** Результат выполнения `Connect` или `Disconnect`.

---

### `ConnectionService.Unbind`

```lua
ConnectionService.Unbind(name: string): boolean
```

Полностью отключает задачу и удаляет её конфигурацию из памяти.

* **Параметры:**
  * `name`: Имя задачи.
* **Возвращает:** `true`.
* **Алиас:** `ConnectionService.Remove`

---

### `ConnectionService.Destroy`

```lua
ConnectionService.Destroy(): ()
```

Отключает все зарегистрированные задачи и полностью очищает внутреннюю таблицу сервиса. Полезно при сбросе состояния или выгрузке систем.

---

## Доступные события

| Имя события | Область видимости | Описание |
| :--- | :--- | :--- |
| `Heartbeat` *(по умолчанию)* | Сервер и Клиент | Вызывается каждый кадр после расчёта физики. |
| `RenderStepped` | Только Клиент | Вызывается каждый кадр перед рендером экрана. *(На сервере автоматически заменяется на `Heartbeat`)*. |
| `Stepped` | Сервер и Клиент | Вызывается каждый кадр перед симуляцией физики. |
| `PreSimulation` | Сервер и Клиент | Современный аналог события `Stepped`. |
| `PostSimulation` | Сервер и Клиент | Современный аналог события `Heartbeat`. |

*Примечание: Если передано некорректное имя события, модуль выведет предупреждение в `warn()` и переключится на `Heartbeat`.*

---

## Примеры использования

### 1. Выполнение с интервалом (Регенерация / Таймер)

Запуск логики каждые 0.5 секунды без выполнения лишних вычислений на каждом кадре:

```lua
ConnectionService.Bind(
    "RegenTask",
    function(elapsedTime)
        humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + (10 * elapsedTime))
    end,
    "Heartbeat",
    true,
    0.5 -- Вызов раз в полсекунды
)
```

### 2. Кастомная камера на клиенте (`RenderStepped`)

Синхронизация движения камеры без визуальных подергиваний:

```lua
ConnectionService.Bind(
    "CameraFollow",
    function(dt)
        local character = player.Character
        if character and character.PrimaryPart then
            camera.CFrame = character.PrimaryPart.CFrame * CFrame.new(0, 3, 10)
        end
    end,
    "RenderStepped"
)
```

### 3. Пауза игры через UI кнопку

```lua
local isGamePaused = false

pauseButton.Activated:Connect(function()
    isGamePaused = not isGamePaused
    ConnectionService.Toggle("MainGameLoop", not isGamePaused)
    pauseButton.Text = isGamePaused and "Продолжить" or "Пауза"
end)
```

---

## Лицензия

Проект распространяется под стандартной лицензией MIT.
