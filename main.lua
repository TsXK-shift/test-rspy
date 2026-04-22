--[[
    Remote Spy Pro v4.0  -  Main Loader

    Arquitetura:
      modules/serializer.lua  -  args → código Lua executável
      modules/hooks.lua       -  __namecall + hookfunction combinados
      modules/ui.lua          -  interface virtual

    Uso: edite BASE_URL abaixo pro seu repositório, depois:
      loadstring(game:HttpGet("https://SEU_REPO/main.lua"))()

    Ou execute tudo num arquivo único (use build_single.lua).
]]

--═══════════════════════════════════════════════════════
-- CONFIGURE AQUI: URL base do seu repositório (sem barra final)
--═══════════════════════════════════════════════════════
local BASE_URL = "https://raw.githubusercontent.com/TsXK-shift/test-rspy/refs/heads/main"
--═══════════════════════════════════════════════════════

-- Detectar se rodando do arquivo único (build_single.lua coloca os módulos em getgenv())
local function loadModule(name)
    if getgenv().__RSP_MODULES and getgenv().__RSP_MODULES[name] then
        return getgenv().__RSP_MODULES[name]
    end
    local url = BASE_URL.."/modules/"..name..".lua"
    local ok, src = pcall(game.HttpGet, game, url)
    if not ok then
        error("[RSP] Falha ao baixar "..name..": "..tostring(src))
    end
    local f, err = loadstring(src, name)
    if not f then error("[RSP] Erro ao compilar "..name..": "..tostring(err)) end
    return f()
end

-- ── DETECÇÃO DE AMBIENTE ──
local env = {
    hookfunction      = hookfunction or replaceclosure,
    hookmetamethod    = hookmetamethod,
    newcclosure       = newcclosure or function(f) return f end,
    getnamecallmethod = getnamecallmethod,
    checkcaller       = checkcaller or function() return false end,
    setclipboard      = setclipboard or toclipboard or (Clipboard and Clipboard.set),
    getrawmetatable   = getrawmetatable,
    cloneref          = cloneref or function(x) return x end,
    getcallingscript  = getcallingscript,
    Name = (identifyexecutor and identifyexecutor())
        or (getexecutorname and getexecutorname())
        or "Unknown",
}
env.CanHookFunction = env.hookfunction ~= nil
env.CanHookMeta     = env.hookmetamethod ~= nil and env.getnamecallmethod ~= nil

-- ── ESTADO GLOBAL ──
-- Cleanup anterior
if getgenv().RSP_Pro and getgenv().RSP_Pro.gui then
    pcall(function() getgenv().RSP_Pro.gui:Destroy() end)
end

local state = {
    version = "4.0",
    logs = {},
    blocked = {},
    stats = {},
    config = {
        enabled = true,
        logCheckCaller = false,  -- default false = não loga próprias chamadas do executor
        logClientEvents = true,
        autoScroll = true,
        filter = "",
    },
    env = env,
}

-- ── CARREGAR MÓDULOS ──
print("[RSP] Executor:", env.Name)
print("[RSP] hookfunction:", tostring(env.CanHookFunction),
      "| hookmetamethod:", tostring(env.CanHookMeta))

local okS, serializer = pcall(loadModule, "serializer")
if not okS then
    warn("[RSP] FALHA serializer:", serializer); return
end
local okH, hooks = pcall(loadModule, "hooks")
if not okH then
    warn("[RSP] FALHA hooks:", hooks); return
end
local okU, ui = pcall(loadModule, "ui")
if not okU then
    warn("[RSP] FALHA ui:", ui); return
end

state.serializer = serializer
state.hookStats = hooks.stats
state.isBlocked = function(remote)
    if not remote then return false end
    local ok, path = pcall(function()
        local parts, cur, d = {}, remote, 0
        while cur and cur ~= game and d < 30 do
            table.insert(parts, 1, cur.Name)
            cur = cur.Parent
            d = d + 1
        end
        return table.concat(parts, ".")
    end)
    if not ok then return false end
    return state.blocked[path] == true
end

-- CRÍTICO: setar env.config ANTES de hooks.init,
-- porque o hook começa a interceptar imediatamente e acessa env.config
env.config = state.config
env.isBlocked = state.isBlocked

-- ╔══════════════════════════════════════╗
-- ║ hooks ANTES da UI                    ║
-- ╚══════════════════════════════════════╝

local uiApi
local addLogQueue = {}

local function logCallback(data)
    data.id = #state.logs + 1
    data.timestamp = os.date("%H:%M:%S")
    local okP, preview = pcall(serializer.previewArgs, data.args or {}, 6)
    data.argsPreview = okP and preview or "(?)"

    table.insert(state.logs, data)
    if #state.logs > 500 then table.remove(state.logs, 1) end

    local p = data.remotePath or "?"
    state.stats[p] = state.stats[p] or {calls=0, blocked=0}
    state.stats[p].calls = state.stats[p].calls + 1
    if data.blocked then state.stats[p].blocked = state.stats[p].blocked + 1 end

    if uiApi then
        pcall(uiApi.onNewLog, data)
    else
        table.insert(addLogQueue, data)
    end
end

-- determinar hookMode
local hookMode = "fallback"
if env.CanHookMeta then hookMode = "namecall+hookfunction"
elseif env.CanHookFunction then hookMode = "hookfunction" end
env.hookMode = hookMode

-- INICIALIZAR HOOKS
local okInit, errInit = pcall(hooks.init, env, logCallback)
if not okInit then
    warn("[RSP] ❌ Erro ao inicializar hooks: "..tostring(errInit))
else
    print("[RSP] ✓ Hooks ativos em modo:", hookMode)
end

-- ── UI ──
local okUi, uiResult = pcall(ui.build, state)
if not okUi then
    warn("[RSP] ❌ Erro ao montar UI: "..tostring(uiResult))
    return
end
uiApi = uiResult

-- drenar fila acumulada
if #addLogQueue > 0 then
    print("[RSP] drenando", #addLogQueue, "logs pré-UI")
    pcall(uiApi.rebuild)
end

-- Exportar pro escopo global pra poder inspecionar
getgenv().RSP_Pro = {
    state = state,
    hooks = hooks,
    serializer = serializer,
    gui = uiApi.gui,
    version = state.version,
}

-- log de inicialização
task.spawn(function()
    task.wait(0.1)
    logCallback({
        type = "FireServer",
        remoteType = "Sistema",
        remote = nil,
        remoteName = "RSP_Init",
        remotePath = "System.RSP_Init",
        args = {"executor="..env.Name, "mode="..hookMode},
        argCount = 2,
        metamethod = "system",
        blocked = false,
    })
end)

print("[RSP] v"..state.version.." carregado. Use getgenv().RSP_Pro pra inspecionar.")
