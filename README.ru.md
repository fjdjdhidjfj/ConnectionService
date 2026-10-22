# ConnectionService

![Luau](https://img.shields.io/badge/Language-Luau-00A2FF.svg?style=flat-square)
![Roblox](https://img.shields.io/badge/Platform-Roblox%20Engine-000000.svg?style=flat-square)
![Complexity](https://img.shields.io/badge/Lookup-%24O(1)%24-brightgreen.svg?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)

🌐 **Языки:** [English](README.md) | **Русский**

Высокопроизводительный диспетчер соединений `RunService` для среды Luau. Спроектирован для детерминированного управления жизненным циклом циклических подсистем, предотвращения деградации tick rate и исключения утечек памяти `RBXScriptConnection` при динамической инжекции и горячей перезагрузке (`loadstring`).

---

## Архитектурные предпосылки и мотивация

При разработке модулей, выполняемых вне стандартного конвейера компиляции (через `loadstring`, внешние загрузчики или отладочные консоли), инженеры регулярно сталкиваются с тремя критическими проблемами:

1. **Утечки дескрипторов `RBXScriptConnection`:** Повторное выполнение скрипта без предварительной деструкции оставляет старые замыкания подписанными на сигналы `RunService`. Это приводит к мультипликации вычислений на каждом кадре и прогрессирующей просадке FPS.
2. **Загрязнение глобального окружения (`_G` pollution):** Прямое сохранение соединений в `_G[key]` нарушает инкапсуляцию, создает риск коллизий имен и усложняет интроспекцию состояния.
3. **Несоответствие контекстов исполнения:** Попытка прямой подписки на клиентские события (например, `RenderStepped`) на стороне сервера вызывает фатальное исключение времени выполнения (`runtime error`).

`ConnectionService` изолирует активные дескрипторы внутри локальной хэш-таблицы модуля со сложностью доступа $O(1)$, гарантирует идемпотентность регистрации задач и автоматически выгружает предыдущий экземпляр сервиса через единый глобальный якорь.

---

## Модель состояний задачи (Lifecycle)

Каждая зарегистрированная задача подчиняется строгому конечному автомату:

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
Connect()│     └───────────────────────┘     │ Disconnect()
         │                 │                 │
         │                 │ Toggle()        │
         ▼                 ▼                 │
   ┌───────────────────────────────────────────┐
   │                  ACTIVE                   │
   │           (conn = RBXScriptConnection)    │
   └───────────────────────────────────────────┘
```

---

## Конвейер кадров и поддерживаемые сигналы

Модуль маппит строковые идентификаторы на нативные сигналы `RunService`, контролируя контекст исполнения (`Client` / `Server`):

| Идентификатор | Фаза конвейера кадра | Контекст | Основное назначение |
| :--- | :--- | :--- | :--- |
| **`RenderStepped`** | Перед вызовом GPU Draw | Только Клиент | Манипуляции с камерой, расчет экранных проекций, отрисовка 2D/3D ESP. Блокирует поток рендера. |
| **`PreSimulation`** / **`Stepped`** | До шага PhysX | Клиент и Сервер | Мутация параметров твердых тел, сброс коллизий (`CanCollide = false`), приложение физических импульсов. |
| **`Heartbeat`** / **`PostSimulation`** *(Default)* | После шага PhysX | Клиент и Сервер | Основная логика подсистем, телепортация через `CFrame`, трассировка лучей (`Raycast`), таймеры. |

> **Гарантия отказоустойчивости контекста:** Если подписка на `RenderStepped` запрашивается в серверном окружении (`RunService:IsClient() == false`), диспетчер автоматически перенаправляет задачу на `Heartbeat` и выводит нефатальное предупреждение через `warn()`.

---

## Установка и инициализация

### Удаленная загрузка (`loadstring` через GitHub Raw)
```lua
local ConnectionService = loadstring(game:HttpGet("https://raw.githubusercontent.com/fjdjdhidjfj/ConnectionService/main/ConnectionService.luau"))()
```

### Стандартный импорт через `ModuleScript`
```lua
local ConnectionService = require(game:GetService("ReplicatedStorage"):WaitForChild("ConnectionService"))
```

---

## Спецификация API

### `ConnectionService.Bind`
```lua
ConnectionService.Bind(
    name: string,
    callback: (deltaTime: number) -> (),
    eventType: string?,
    autoStart: boolean?
): boolean
```
Регистрирует именованный обработчик во внутреннем реестре.
* **Разрешение коллизий:** Если задача с ключом `name` уже существует, ее активное соединение атомарно разрывается перед перезаписью дескриптора.
* **Параметры:**
  * `name` - уникальный строковый идентификатор задачи.
  * `callback` - исполняемое замыкание. Принимает аргумент `deltaTime` (время в секундах с предыдущего кадра).
  * `eventType` *(опционально)* - целевой сигнал `RunService`. По умолчанию `"Heartbeat"`.
  * `autoStart` *(опционально)* - флаг немедленного перевода в состояние `ACTIVE`. По умолчанию `true`.
* **Алиас:** `ConnectionService.Add`

---

### `ConnectionService.Connect`
```lua
ConnectionService.Connect(name: string, forceReconnect: boolean?): boolean
```
Переводит зарегистрированную задачу из состояния `SUSPENDED` в `ACTIVE`.
* Создает экземпляр `RBXScriptConnection` через вызов `:Connect()`.
* При `forceReconnect == true` принудительно разрывает текущее соединение и инициализирует новое.
* Возвращает `false`, если задача не найдена или уже активна (при опущенном `forceReconnect`).

---

### `ConnectionService.Disconnect`
```lua
ConnectionService.Disconnect(name: string): boolean
```
Переводит задачу из состояния `ACTIVE` в `SUSPENDED`.
* Вызывает нативный метод `:Disconnect()` у удерживаемого соединения и зануляет внутренний указатель.
* Сохраняет метаданные задачи (`callback` и `eventType`) в реестре для последующего быстрого возобновления через `Connect()` или `Toggle()`.

---

### `ConnectionService.Toggle`
```lua
ConnectionService.Toggle(name: string, enabled: boolean?): boolean
```
Инвертирует состояние активности задачи либо принудительно устанавливает заданный булев статус.
* Если `enabled == nil`, целевое состояние вычисляется как `not entry.enabled`.
* Делегирует выполнение методам `Connect()` или `Disconnect()`.

---

### `ConnectionService.Unbind`
```lua
ConnectionService.Unbind(name: string): boolean
```
Полная деструкция задачи и освобождение памяти.
* Разрывает активное соединение через `Disconnect(name)`.
* Присваивает `_bindings[name] = nil`, удаляя ключ из хэш-таблицы и снимая сильную ссылку с замыкания `callback` для его утилизации сборщиком мусора (Luau GC).
* **Алиас:** `ConnectionService.Remove`

---

### `ConnectionService.Destroy`
```lua
ConnectionService.Destroy(): ()
```
Полная выгрузка сервиса.
* Итерируется по всем зарегистрированным задачам, вызывая `:Disconnect()`.
* Очищает внутренний реестр одним системным вызовом C-уровня `table.clear()`.

---

## Управление памятью и гарантии Hot-Reload

Для обеспечения чистоты рантайма при многократном перезапуске кода без перезахода в плейс модуль реализует паттерн Singleton Cleanup при инициализации:

```lua
if _G.__ConnectionServiceInstance then
    pcall(function()
        _G.__ConnectionServiceInstance.Destroy()
    end)
end
_G.__ConnectionServiceInstance = ConnectionService
```

1. **Отсутствие удержания замыканий (GC Cleanliness):** Вызов `Unbind(name)` присваивает ключу таблицы значение `nil`. В Luau это физически освобождает узел хэш-таблицы, позволяя сборщику мусора очистить память, занятую внешними переменными (`upvalues`), на следующем цикле сборки.
2. **Идемпотентная реинжекция:** Повторное выполнение скрипта через `loadstring` автоматически вызывает `Destroy()` у предыдущего инстанса до регистрации новых слушателей, гарантируя строгое соотношение $1:1$ между задачей и кадровым тиком.

---

## Примеры использования в продакшене

### 1. Синхронизация с рендером (Камера и визуализация)
Выполнение расчетов экранных проекций строго перед отрисовкой геометрии кадра:
```lua
ConnectionService.Bind("ViewportProjection", function(dt: number)
    local camera = workspace.CurrentCamera
    if not camera then return end
    -- Расчет матриц проекции и обновление визуальных маркеров
end, "RenderStepped")
```

### 2. Переопределение коллизий до шага физики (Noclip)
Модификация свойства `CanCollide` до запуска физического солвера для предотвращения выталкивания персонажа из геометрии:
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
end, "Stepped", false) -- Регистрация в состоянии SUSPENDED (autoStart = false)

-- Динамическое переключение через UI или бинд клавиши
ConnectionService.Toggle("CollisionOverride", true)
```

### 3. Корректная выгрузка (Graceful Teardown)
Освобождение всех системных хуков при завершении работы основного скрипта:
```lua
ConnectionService.Destroy()
```

---

## Лицензия

Этот проект распространяется под лицензией MIT - подробности в файле [LICENSE](LICENSE).
