# UART Barometer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a synchronous dual-UART barometer module, test it thoroughly, and wire it into the existing sample application loop.

**Architecture:** Create a new `gbaro.lua` module that owns UART1/UART2 setup, request/response framing, CRC verification, and payload decoding. Keep application changes limited to requiring the module and adding a single periodic logging task.

**Tech Stack:** Lua, LuatOS `uart` API, script-style Lua tests with fake globals

---

### Task 1: Document the new UART barometer surface

**Files:**
- Create: `docs/superpowers/specs/2026-04-21-uart-barometer-design.md`
- Create: `docs/superpowers/plans/2026-04-21-uart-barometer.md`

- [ ] **Step 1: Write the approved design document**

```markdown
Document the dual-UART API, protocol format, error model, and test scope that were approved during brainstorming.
```

- [ ] **Step 2: Write the implementation plan**

```markdown
Break the work into test-first steps covering module tests, module implementation, main integration, and verification.
```

### Task 2: Add failing tests for the module and app integration

**Files:**
- Create: `tests/gbaro_test.lua`
- Modify: `tests/main_test.lua`

- [ ] **Step 1: Write the failing module test**

```lua
local module_loader, load_err = loadfile("gbaro.lua")
assert(module_loader, load_err)
local gbaro = module_loader()

local ok, reading = gbaro.read(gbaro.UART1)
assert(ok, "expected UART1 read to succeed")
assert(reading.temperature == 25.8, "expected decoded temperature")
assert(reading.pressure == 100.0, "expected decoded pressure")
```

- [ ] **Step 2: Run the module test and verify it fails**

Run: `D:\tool\lua\bin\lua.cmd tests\gbaro_test.lua`
Expected: FAIL because `gbaro.lua` does not exist yet.

- [ ] **Step 3: Update the main integration test to require the new module**

```lua
assert(required_modules.gbaro, "main.lua should require gbaro")
assert(#task_queue == 3, "main.lua should register three local background tasks")
```

- [ ] **Step 4: Run the main integration test and verify it fails**

Run: `D:\tool\lua\bin\lua.cmd tests\main_test.lua`
Expected: FAIL because `main.lua` does not require `gbaro` or start the new task yet.

### Task 3: Implement the barometer module

**Files:**
- Create: `gbaro.lua`
- Test: `tests/gbaro_test.lua`

- [ ] **Step 1: Add the public constants and UART init flow**

```lua
gbaro.UART1 = 1
gbaro.UART2 = 2
gbaro.BAUD_RATE = 9600

function gbaro.init()
    return uart.setup(gbaro.UART1, gbaro.BAUD_RATE, 8, 1, uart.None, uart.LSB, 1024) == 0
        and uart.setup(gbaro.UART2, gbaro.BAUD_RATE, 8, 1, uart.None, uart.LSB, 1024) == 0
end
```

- [ ] **Step 2: Add frame building, CRC validation, synchronous frame reads, and payload parsing**

```lua
local function build_request(cmd) end
local function read_frame(id, timeout_ms) end
local function parse_temperature_frame(frame) end
local function parse_pressure_frame(frame) end
```

- [ ] **Step 3: Add `gbaro.read(id)` and `gbaro.read_all()`**

```lua
function gbaro.read(id) end

function gbaro.read_all()
    return {
        [gbaro.UART1] = ...,
        [gbaro.UART2] = ...
    }
end
```

- [ ] **Step 4: Run the module test and verify it passes**

Run: `D:\tool\lua\bin\lua.cmd tests\gbaro_test.lua`
Expected: PASS

### Task 4: Integrate the module into the application loop

**Files:**
- Modify: `main.lua`
- Test: `tests/main_test.lua`

- [ ] **Step 1: Require the module and add the barometer task**

```lua
_G.gbaro = require("gbaro")

sys.taskInit(function()
    if not gbaro.init() then
        log.error("main", "gbaro初始化失败")
        return
    end
end)
```

- [ ] **Step 2: Log both UART readings in the new task**

```lua
local all = gbaro.read_all()
local uart1 = all[gbaro.UART1] or {}
local uart2 = all[gbaro.UART2] or {}
```

- [ ] **Step 3: Run the main integration test and verify it passes**

Run: `D:\tool\lua\bin\lua.cmd tests\main_test.lua`
Expected: PASS

### Task 5: Run full verification

**Files:**
- Test: `tests/io_test.lua`
- Test: `tests/gadc_test.lua`
- Test: `tests/gsht30_test.lua`
- Test: `tests/gbaro_test.lua`
- Test: `tests/main_test.lua`

- [ ] **Step 1: Run the full Lua test suite**

Run:

```powershell
D:\tool\lua\bin\lua.cmd tests\io_test.lua
D:\tool\lua\bin\lua.cmd tests\gadc_test.lua
D:\tool\lua\bin\lua.cmd tests\gsht30_test.lua
D:\tool\lua\bin\lua.cmd tests\gbaro_test.lua
D:\tool\lua\bin\lua.cmd tests\main_test.lua
```

Expected: every script prints `PASS` and exits 0.

- [ ] **Step 2: Review the diff for only intended files**

Run: `git diff -- gbaro.lua main.lua tests/gbaro_test.lua tests/main_test.lua docs/superpowers/specs/2026-04-21-uart-barometer-design.md docs/superpowers/plans/2026-04-21-uart-barometer.md`
Expected: only the new module, app integration, tests, and docs are changed.
