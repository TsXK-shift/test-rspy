-- Remote Spy Pro v4.0 (arquivo único)
-- Gerado automaticamente - não editar manualmente

getgenv().__RSP_MODULES = getgenv().__RSP_MODULES or {}

-- ═══════════════════════════════════════
-- módulo: serializer
-- ═══════════════════════════════════════
getgenv().__RSP_MODULES.serializer = (function()
--[[
    RSP Serializer - converte args reais em código Lua executável
    Inspirado no DataToCode do SimpleSpy V3, porém simplificado e sem
    dependência de loadstring externo.

    Suporta: nil, boolean, number (inf/nan), string (multiline + escapes),
    Vector2/3, CFrame, UDim/UDim2, Color3, BrickColor, NumberRange, Ray,
    TweenInfo, Rect, EnumItem, Instance (com path correto), tables
    (com detecção de ciclos, duplicatas e chaves não-triviais), userdata
    genérico, funções (nome via debug.info).

    API:
      serializer.encode(args)  -> (string codigoLua, bool precisaGetNil)
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local MAX_TABLE = 1000
local MAX_STRING = 10000
local INDENT = 4

local M = {}

local function identIsValid(s)
    return type(s) == "string" and s:match("^[%a_][%w_]*$") == s
end

-- escape de strings (lida com \n, \t, \\, ", bytes não-imprimíveis)
local function escapeStr(s)
    if #s > MAX_STRING then s = s:sub(1, MAX_STRING) end
    local buf, n = {}, 0
    for i = 1, #s do
        local c = s:sub(i, i)
        local b = string.byte(c)
        if c == "\\" then n=n+1; buf[n]="\\\\"
        elseif c == '"' then n=n+1; buf[n]='\\"'
        elseif c == "\n" then n=n+1; buf[n]="\\n"
        elseif c == "\r" then n=n+1; buf[n]="\\r"
        elseif c == "\t" then n=n+1; buf[n]="\\t"
        elseif b < 32 or b > 126 then n=n+1; buf[n]="\\"..b
        else n=n+1; buf[n]=c
        end
    end
    return '"'..table.concat(buf)..'"'
end

-- number especial (inf, nan)
local function encodeNum(v)
    if v ~= v then return "0/0" end
    if v == math.huge then return "math.huge" end
    if v == -math.huge then return "-math.huge" end
    if v == math.floor(v) and math.abs(v) < 1e15 then
        return string.format("%d", v)
    end
    return tostring(v)
end

-- Instance → path executável
local function instanceToPath(inst, state)
    if not inst then return "nil" end
    local okGame = pcall(function() return inst == game end)
    if okGame and inst == game then return "game" end
    if inst == workspace then return "workspace" end
    if inst == LocalPlayer then return 'game:GetService("Players").LocalPlayer' end

    -- character do LocalPlayer
    if LocalPlayer and LocalPlayer.Character and inst == LocalPlayer.Character then
        return 'game:GetService("Players").LocalPlayer.Character'
    end

    local parts = {}
    local cur = inst
    local depth = 0
    local rootedInGame = false
    local serviceRoot = nil

    while cur and depth < 50 do
        depth = depth + 1
        local ok, parent = pcall(function() return cur.Parent end)
        if not ok then break end
        if parent == game then
            serviceRoot = cur
            rootedInGame = true
            break
        end
        if parent == nil then
            -- instância nil (não parented ao DataModel)
            break
        end
        local name = cur.Name
        if identIsValid(name) then
            table.insert(parts, 1, "."..name)
        else
            table.insert(parts, 1, ':FindFirstChild('..escapeStr(name)..')')
        end
        cur = parent
    end

    if rootedInGame and serviceRoot then
        local cls = serviceRoot.ClassName
        local head
        if cls == "Workspace" then
            head = "workspace"
        else
            head = string.format('game:GetService("%s")', cls)
        end
        return head..table.concat(parts)
    end

    -- fallback: nil instance
    state.needGetNil = true
    local okName = pcall(function() return inst.Name end)
    local okCls  = pcall(function() return inst.ClassName end)
    if okName and okCls then
        return string.format('getNil(%s, "%s")%s',
            escapeStr(inst.Name), inst.ClassName, table.concat(parts))
    end
    return 'nil --[[instance sem path]]'
end

-- encoders por typeof
local typeEncoders = {
    ["nil"]     = function() return "nil" end,
    boolean     = function(v) return tostring(v) end,
    number      = encodeNum,
    string      = function(v) return escapeStr(v) end,
    Vector2     = function(v) return string.format("Vector2.new(%s, %s)", encodeNum(v.X), encodeNum(v.Y)) end,
    Vector3     = function(v) return string.format("Vector3.new(%s, %s, %s)", encodeNum(v.X), encodeNum(v.Y), encodeNum(v.Z)) end,
    CFrame      = function(v)
        local c = {v:GetComponents()}
        local parts = {}
        for i, n in ipairs(c) do parts[i] = encodeNum(n) end
        return "CFrame.new("..table.concat(parts, ", ")..")"
    end,
    UDim        = function(v) return string.format("UDim.new(%s, %d)", encodeNum(v.Scale), v.Offset) end,
    UDim2       = function(v) return string.format("UDim2.new(%s, %d, %s, %d)",
        encodeNum(v.X.Scale), v.X.Offset, encodeNum(v.Y.Scale), v.Y.Offset) end,
    Color3      = function(v) return string.format("Color3.fromRGB(%d, %d, %d)",
        math.floor(v.R*255+0.5), math.floor(v.G*255+0.5), math.floor(v.B*255+0.5)) end,
    BrickColor  = function(v) return string.format("BrickColor.new(%q)", v.Name) end,
    NumberRange = function(v) return string.format("NumberRange.new(%s, %s)", encodeNum(v.Min), encodeNum(v.Max)) end,
    Ray         = function(v) return string.format("Ray.new(Vector3.new(%s,%s,%s), Vector3.new(%s,%s,%s))",
        encodeNum(v.Origin.X), encodeNum(v.Origin.Y), encodeNum(v.Origin.Z),
        encodeNum(v.Direction.X), encodeNum(v.Direction.Y), encodeNum(v.Direction.Z)) end,
    Rect        = function(v) return string.format("Rect.new(%s, %s, %s, %s)",
        encodeNum(v.Min.X), encodeNum(v.Min.Y), encodeNum(v.Max.X), encodeNum(v.Max.Y)) end,
    TweenInfo   = function(v) return string.format(
        "TweenInfo.new(%s, Enum.EasingStyle.%s, Enum.EasingDirection.%s, %d, %s, %s)",
        encodeNum(v.Time), v.EasingStyle.Name, v.EasingDirection.Name,
        v.RepeatCount, tostring(v.Reverses), encodeNum(v.DelayTime)) end,
    EnumItem    = function(v) return tostring(v) end,
    Enum        = function(v) return "Enum."..tostring(v) end,
    Enums       = function() return "Enum" end,
    RBXScriptSignal     = function() return "nil --[[RBXScriptSignal não serializável]]" end,
    RBXScriptConnection = function() return "nil --[[RBXScriptConnection não serializável]]" end,
}

-- encoder de tabela com controle de ciclo/duplicata/profundidade
local encodeValue

local function encodeTable(t, state, level, path)
    -- duplicata: referência já vista → marca como duplicata (tratada depois)
    if state.seen[t] then
        return "{} --[[DUPLICATE]]"
    end
    state.seen[t] = path or "<root>"
    level = level + 1
    local indent = string.rep(" ", level * INDENT)
    local closeIndent = string.rep(" ", (level-1) * INDENT)

    local count = 0
    local parts = {}

    -- array-part primeiro (estetica)
    local isArrayLike = true
    local expect = 1
    for k, _ in pairs(t) do
        if k ~= expect then isArrayLike = false; break end
        expect = expect + 1
    end

    if isArrayLike then
        for i, v in ipairs(t) do
            count = count + 1
            if count > MAX_TABLE then
                parts[#parts+1] = indent.."-- MAX_TABLE excedido"
                break
            end
            local subPath = path.."["..i.."]"
            parts[#parts+1] = indent..encodeValue(v, state, level, subPath)..","
        end
    else
        for k, v in pairs(t) do
            count = count + 1
            if count > MAX_TABLE then
                parts[#parts+1] = indent.."-- MAX_TABLE excedido"
                break
            end
            local keyStr, subPath
            if identIsValid(k) then
                keyStr = k
                subPath = path.."."..k
            else
                local ek = encodeValue(k, state, level, path.."[?]")
                keyStr = "["..ek.."]"
                subPath = path.."["..ek.."]"
            end
            parts[#parts+1] = indent..keyStr.." = "..encodeValue(v, state, level, subPath)..","
        end
    end

    if count == 0 then return "{}" end
    return "{\n"..table.concat(parts, "\n").."\n"..closeIndent.."}"
end

encodeValue = function(v, state, level, path)
    level = level or 0
    path = path or "args"

    local tt = typeof(v)
    local enc = typeEncoders[tt]
    if enc then return enc(v) end

    if tt == "Instance" then
        return instanceToPath(v, state)
    end
    if tt == "table" then
        return encodeTable(v, state, level, path)
    end
    if tt == "function" then
        local ok, info = pcall(debug.info, v, "n")
        if ok and info and info ~= "" then
            return string.format('nil --[[function %s]]', tostring(info))
        end
        return "nil --[[function]]"
    end
    if tt == "userdata" then
        return "newproxy(true) --[[userdata genérico]]"
    end
    if tt == "buffer" then
        return "buffer.create(0) --[[buffer]]"
    end
    return string.format("nil --[[%s]]", tt)
end

-- API pública
function M.encode(args)
    local state = { seen = {}, needGetNil = false }
    local n = #args
    if n == 0 then
        return "local args = {}", false
    end

    local parts = {}
    for i = 1, n do
        parts[i] = string.rep(" ", INDENT)..encodeValue(args[i], state, 1, "args["..i.."]")..","
    end
    local code = "local args = {\n"..table.concat(parts, "\n").."\n}"
    return code, state.needGetNil
end

-- encode single value (pra preview de args individuais)
function M.encodeSingle(v)
    local state = { seen = {}, needGetNil = false }
    return encodeValue(v, state, 0, "v"), state.needGetNil
end

-- preview curto (pra lista de logs, não executável)
function M.preview(v, maxLen)
    maxLen = maxLen or 60
    local tt = typeof(v)
    if tt == "string" then
        local s = v:gsub("\n", "\\n"):gsub("\t", "\\t")
        if #s > maxLen then s = s:sub(1, maxLen-3).."..." end
        return '"'..s..'"'
    elseif tt == "number" or tt == "boolean" or tt == "nil" then
        return tostring(v)
    elseif tt == "Vector3" then
        return string.format("V3(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z)
    elseif tt == "Vector2" then
        return string.format("V2(%.1f,%.1f)", v.X, v.Y)
    elseif tt == "CFrame" then
        return string.format("CF(%.1f,%.1f,%.1f)", v.Position.X, v.Position.Y, v.Position.Z)
    elseif tt == "Color3" then
        return string.format("RGB(%d,%d,%d)", v.R*255, v.G*255, v.B*255)
    elseif tt == "Instance" then
        local ok, cls = pcall(function() return v.ClassName end)
        local ok2, nm  = pcall(function() return v.Name end)
        return string.format("<%s:%s>", ok and cls or "?", ok2 and nm or "?")
    elseif tt == "table" then
        local n = 0; for _ in pairs(v) do n = n + 1 end
        return string.format("{%d items}", n)
    elseif tt == "EnumItem" then
        return tostring(v)
    end
    return "<"..tt..">"
end

function M.previewArgs(args, maxArgs)
    maxArgs = maxArgs or 8
    if not args or #args == 0 then return "()" end
    local parts = {}
    for i = 1, math.min(#args, maxArgs) do
        parts[i] = M.preview(args[i])
    end
    if #args > maxArgs then
        parts[#parts+1] = string.format("+%d", #args - maxArgs)
    end
    return "("..table.concat(parts, ", ")..")"
end

return M

end)()

-- ═══════════════════════════════════════
-- módulo: hooks
-- ═══════════════════════════════════════
getgenv().__RSP_MODULES.hooks = (function()
--[[
    RSP Hooks - camada de interceptação

    Estratégia: híbrida, seguindo o padrão SimpleSpy V3
      1) hookmetamethod(game, "__namecall") -> pega TODAS as chamadas
         method-call (remote:FireServer(...)) independente de cache.
      2) hookfunction nos protótipos de RemoteEvent/RemoteFunction/
         UnreliableRemoteEvent -> pega chamadas tipo remote.FireServer(remote, ...)
         que não passam por __namecall.

    Assim cobrimos TANTO method-call quanto cached-call.

    API:
      hooks.init(env, callback)
        env: tabela com funções do executor
        callback: função(data) chamada a cada chamada interceptada
      hooks.shutdown()  desfaz os hooks
      hooks.stats       tabela com contadores
]]

local M = {
    stats = { ns = 0, fs = 0, is = 0, ufs = 0, ce = 0 },
    _installed = false,
    _originals = {},
}

-- deepclone preservando ref de Instance (evita race condition)
local function deepclone(v, seen)
    seen = seen or {}
    if type(v) ~= "table" then return v end
    if seen[v] then return seen[v] end
    local copy = {}
    seen[v] = copy
    for k, val in pairs(v) do
        copy[deepclone(k, seen)] = deepclone(val, seen)
    end
    return copy
end

-- detector de tabela cíclica (trava serializer)
local function isCyclic(t, seen)
    seen = seen or {}
    if type(t) ~= "table" then return false end
    if seen[t] then return true end
    seen[t] = true
    for _, v in pairs(t) do
        if type(v) == "table" and isCyclic(v, seen) then return true end
    end
    seen[t] = nil
    return false
end

local function safePath(inst)
    local ok, r = pcall(function()
        local parts, cur, d = {}, inst, 0
        while cur and cur ~= game and d < 30 do
            table.insert(parts, 1, cur.Name)
            cur = cur.Parent
            d = d + 1
        end
        return table.concat(parts, ".")
    end)
    return ok and r or tostring(inst)
end

function M.init(env, callback)
    if M._installed then return false, "já instalado" end
    M._installed = true

    local hookfunction     = env.hookfunction
    local hookmetamethod   = env.hookmetamethod
    local getnamecallmethod= env.getnamecallmethod
    local newcclosure      = env.newcclosure or function(f) return f end
    local checkcaller      = env.checkcaller or function() return false end
    local cloneref         = env.cloneref or function(x) return x end
    local getcallingscript = env.getcallingscript

    local IsA = game.IsA

    -- wrapper comum de log
    local function emit(method, self, args, metamethod)
        local cfg = env.config
        if not cfg or not cfg.enabled then return end
        if not cfg.logCheckCaller and checkcaller() then return end

        if isCyclic(args) then return end
        args = deepclone(args)

        local clsOk, cls = pcall(function() return self.ClassName end)
        if not clsOk then return end

        local remoteType
        if cls == "RemoteEvent" or cls == "UnreliableRemoteEvent" then
            remoteType = "RemoteEvent"
        elseif cls == "RemoteFunction" then
            remoteType = "RemoteFunction"
        else
            return
        end

        local src = nil
        if getcallingscript then
            local ok, s = pcall(getcallingscript)
            if ok and s then src = cloneref(s) end
        end

        local ln
        pcall(function()
            local info = debug.info(3, "l")
            ln = info
        end)

        if method == "FireServer" then M.stats.fs = M.stats.fs + 1
        elseif method == "InvokeServer" then M.stats.is = M.stats.is + 1 end
        if metamethod == "__namecall" then M.stats.ns = M.stats.ns + 1 end

        callback({
            type       = method,
            remoteType = cls,
            remote     = self,
            remoteName = self.Name,
            remotePath = safePath(self),
            args       = args,
            argCount   = #args,
            callerScript = src,
            callerLine = ln,
            metamethod = metamethod,
            blocked    = env.isBlocked and env.isBlocked(self) or false,
        })
    end

    -- ── MÉTODO 1: __namecall via hookmetamethod ──
    local namecallOk = false
    if hookmetamethod and getnamecallmethod then
        local oldNC
        local ok, err = pcall(function()
            oldNC = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                local method = getnamecallmethod()
                if method == "FireServer" or method == "InvokeServer" then
                    if typeof(self) == "Instance" then
                        local isRemote = false
                        pcall(function()
                            isRemote = IsA(self, "RemoteEvent")
                                or IsA(self, "RemoteFunction")
                                or IsA(self, "UnreliableRemoteEvent")
                        end)
                        if isRemote then
                            local args = {...}
                            local blocked = env.isBlocked and env.isBlocked(self)
                            emit(method, self, args, "__namecall")
                            if blocked then
                                if method == "InvokeServer" then return nil end
                                return
                            end
                        end
                    end
                end
                return oldNC(self, ...)
            end))
        end)
        if ok then
            M._originals.__namecall = oldNC
            namecallOk = true
        else
            warn("[RSP] __namecall hook falhou: "..tostring(err))
        end
    end

    -- ── MÉTODO 2: hookfunction nos protótipos ──
    -- (captura remote.FireServer(remote, ...) cached-call)
    if hookfunction then
        local function hookProto(className, methodName, key)
            local okCreate, temp = pcall(Instance.new, className)
            if not okCreate then return false end
            local orig = temp[methodName]
            temp:Destroy()
            local ok, err = pcall(function()
                M._originals[key] = hookfunction(orig, newcclosure(function(self, ...)
                    if typeof(self) == "Instance" then
                        local args = {...}
                        local blocked = env.isBlocked and env.isBlocked(self)
                        emit(methodName, self, args, "hookfunction")
                        if blocked then
                            if methodName == "InvokeServer" then return nil end
                            return
                        end
                    end
                    return M._originals[key](self, ...)
                end))
            end)
            if not ok then
                warn("[RSP] hookProto("..className..","..methodName..") falhou: "..tostring(err))
            end
            return ok
        end

        hookProto("RemoteEvent", "FireServer", "FireServer")
        hookProto("RemoteFunction", "InvokeServer", "InvokeServer")
        -- UnreliableRemoteEvent só existe em versões recentes, falha silenciosa ok
        pcall(function()
            hookProto("UnreliableRemoteEvent", "FireServer", "UnreliableFireServer")
        end)
    end

    -- ── BÔNUS: OnClientEvent passivo (capta Server→Client) ──
    local patched = {}
    local function watchRE(obj)
        if typeof(obj) ~= "Instance" then return end
        local ok, isRE = pcall(function() return obj:IsA("RemoteEvent") end)
        if not ok or not isRE then return end
        if patched[obj] then return end
        patched[obj] = true
        pcall(function()
            obj.OnClientEvent:Connect(function(...)
                local cfg = env.config
                if not cfg or not cfg.enabled then return end
                if not cfg.logClientEvents then return end
                M.stats.ce = M.stats.ce + 1
                local args = {...}
                if isCyclic(args) then return end
                callback({
                    type       = "OnClientEvent",
                    remoteType = "RemoteEvent",
                    remote     = obj,
                    remoteName = obj.Name,
                    remotePath = safePath(obj),
                    args       = deepclone(args),
                    argCount   = #args,
                    metamethod = "passive",
                    blocked    = false,
                })
            end)
        end)
    end
    task.spawn(function()
        pcall(function()
            for _, obj in ipairs(game:GetDescendants()) do watchRE(obj) end
        end)
        game.DescendantAdded:Connect(function(obj) task.defer(watchRE, obj) end)
    end)

    return true
end

function M.shutdown()
    -- Nota: desfazer hookfunction/hookmetamethod requer re-aplicar os originais
    -- como hook, o que nem todo executor suporta. Default: apenas desabilita via flag.
    M._installed = false
end

return M

end)()

-- ═══════════════════════════════════════
-- módulo: ui
-- ═══════════════════════════════════════
getgenv().__RSP_MODULES.ui = (function()
--[[
    RSP UI - interface com pool virtual (renderiza só ~20 itens),
    painel de detalhes com script Lua executável gerado pelo serializer,
    filtro, stats, blacklist, config.
]]

local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local M = {}

local GETNIL_HELPER = "local function getNil(name, class)\n    for _, v in next, getnilinstances() do\n        if v.ClassName == class and v.Name == name then return v end\n    end\nend\n\n"

local C = {
    BG       = Color3.fromRGB(13,13,18),
    Surface  = Color3.fromRGB(20,20,28),
    Panel    = Color3.fromRGB(26,26,36),
    PanelH   = Color3.fromRGB(32,32,44),
    Border   = Color3.fromRGB(42,42,58),
    Accent   = Color3.fromRGB(90,170,255),
    AccentD  = Color3.fromRGB(55,110,200),
    Success  = Color3.fromRGB(72,210,110),
    Warning  = Color3.fromRGB(255,185,55),
    Error    = Color3.fromRGB(255,72,72),
    Text     = Color3.fromRGB(220,220,235),
    TextD    = Color3.fromRGB(140,140,165),
    TextM    = Color3.fromRGB(80,80,100),

    FireServer         = Color3.fromRGB(90,170,255),
    InvokeServer       = Color3.fromRGB(175,115,255),
    OnClientEvent      = Color3.fromRGB(72,210,130),
}

local function typeColor(t) return C[t] or C.Accent end

-- construtores mínimos
local function N(cls, props, kids)
    local o = Instance.new(cls)
    if props then for k,v in pairs(props) do o[k]=v end end
    if kids then for _,k in ipairs(kids) do k.Parent = o end end
    return o
end
local function Rnd(r) return N("UICorner",{CornerRadius=UDim.new(0,r)}) end
local function Pad(y,x) return N("UIPadding",{
    PaddingTop=UDim.new(0,y), PaddingBottom=UDim.new(0,y),
    PaddingLeft=UDim.new(0,x), PaddingRight=UDim.new(0,x)}) end
local function Lbl(t,s,c,f,p)
    local l=N("TextLabel",{Text=t,TextSize=s,TextColor3=c,Font=f or Enum.Font.Gotham,
        BackgroundTransparency=1, TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center})
    if p then for k,v in pairs(p) do l[k]=v end end
    return l
end
local function Btn(t,s,p,extra)
    local b=N("TextButton",{Text=t,TextSize=s,TextColor3=C.Text,Font=Enum.Font.GothamMedium,
        BackgroundColor3=C.Panel, BorderSizePixel=0, AutoButtonColor=true})
    if p then for k,v in pairs(p) do b[k]=v end end
    if extra then for _,e in ipairs(extra) do e.Parent=b end end
    return b
end

local ITEM_H = 42
local ITEM_S = 45
local POOL_N = 20

function M.build(state)
    -- state: { config, logs, blocked, stats, serializer, env, hookStats, onBlock, onUnblock, onClear }

    -- destruir anterior
    local parent = (gethui and gethui()) or CoreGui
    pcall(function()
        local old = parent:FindFirstChild("RSP_ProV4")
        if old then old:Destroy() end
    end)

    local Gui = N("ScreenGui",{Name="RSP_ProV4", ResetOnSpawn=false, IgnoreGuiInset=true,
        ZIndexBehavior=Enum.ZIndexBehavior.Sibling, Parent=parent})

    local WIN_W, WIN_H = 820, 520

    local Win = N("Frame",{Size=UDim2.new(0,WIN_W,0,WIN_H),
        Position=UDim2.new(0.5,-WIN_W/2,0.5,-WIN_H/2),
        BackgroundColor3=C.BG, BorderSizePixel=0, Parent=Gui},{
        Rnd(8),
        N("UIStroke",{Color=C.Border,Thickness=1}),
    })

    -- ── HEADER ──
    local HDR = N("Frame",{Size=UDim2.new(1,0,0,42),BackgroundColor3=C.Surface,
        BorderSizePixel=0, Parent=Win},{Rnd(8), Pad(0,14)})
    N("Frame",{Size=UDim2.new(1,0,0,10),Position=UDim2.new(0,0,1,-10),
        BackgroundColor3=C.Surface, BorderSizePixel=0, Parent=HDR})

    Lbl("🔍 Remote Spy Pro", 15, C.Text, Enum.Font.GothamBold, {
        Size=UDim2.new(0,200,1,0), Parent=HDR})
    local StatusLbl = Lbl("● ativo", 11, C.Success, Enum.Font.GothamMedium, {
        Size=UDim2.new(0,80,1,0), Position=UDim2.new(0,200,0,0), Parent=HDR})

    local execTag = Lbl(state.env.Name.." | "..(state.env.hookMode or "?"),
        10, C.TextD, Enum.Font.Gotham, {
        Size=UDim2.new(0,260,1,0), Position=UDim2.new(0,290,0,0),
        TextXAlignment=Enum.TextXAlignment.Right, Parent=HDR})

    local CloseBtn = Btn("✕", 14, {Size=UDim2.new(0,28,0,28),
        Position=UDim2.new(1,-34,0.5,-14), BackgroundColor3=C.Panel,
        TextColor3=C.Error, Parent=HDR}, {Rnd(6)})

    -- ── TABS ──
    local TABS = N("Frame",{Size=UDim2.new(1,-24,0,32),Position=UDim2.new(0,12,0,50),
        BackgroundTransparency=1, Parent=Win},{
        N("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,
            Padding=UDim.new(0,6), SortOrder=Enum.SortOrder.LayoutOrder})})

    local tabs, tabContents, currentTab = {}, {}, nil
    local function mkTab(name, order)
        local b = Btn(name, 12, {Size=UDim2.new(0,98,1,0),BackgroundColor3=C.Surface,
            TextColor3=C.TextD, LayoutOrder=order, Parent=TABS}, {Rnd(6)})
        tabs[name] = b
        tabContents[name] = N("Frame",{Size=UDim2.new(1,-24,1,-94),
            Position=UDim2.new(0,12,0,86), BackgroundColor3=C.Surface,
            BorderSizePixel=0, Visible=false, Parent=Win},{Rnd(8)})
        b.MouseButton1Click:Connect(function()
            if currentTab then
                tabs[currentTab].BackgroundColor3 = C.Surface
                tabs[currentTab].TextColor3 = C.TextD
                tabContents[currentTab].Visible = false
            end
            b.BackgroundColor3 = C.Accent
            b.TextColor3 = C.BG
            tabContents[name].Visible = true
            currentTab = name
        end)
    end
    mkTab("Logs", 1)
    mkTab("Blocked", 2)
    mkTab("Config", 3)

    -- ╔══════════════════════════════════════╗
    -- ║           ABA LOGS                   ║
    -- ╚══════════════════════════════════════╝
    local LogTab = tabContents["Logs"]

    local TopBar = N("Frame",{Size=UDim2.new(1,0,0,36),BackgroundTransparency=1,
        Parent=LogTab}, {Pad(0,12)})
    local SearchBox = N("TextBox",{Size=UDim2.new(0,250,0,26),
        Position=UDim2.new(0,0,0.5,-13), BackgroundColor3=C.Panel,
        BorderSizePixel=0, PlaceholderText="🔍 filtrar por nome ou path",
        Text="", TextColor3=C.Text, PlaceholderColor3=C.TextD,
        TextSize=11, Font=Enum.Font.Gotham, TextXAlignment=Enum.TextXAlignment.Left,
        ClearTextOnFocus=false, Parent=TopBar}, {Rnd(5), Pad(0,8)})

    local CountLbl = Lbl("0 logs", 11, C.TextD, Enum.Font.Gotham, {
        Size=UDim2.new(0,120,0,26), Position=UDim2.new(0,260,0.5,-13), Parent=TopBar})

    local ClearBtn = Btn("🗑 Limpar", 11, {Size=UDim2.new(0,80,0,26),
        Position=UDim2.new(1,-88,0.5,-13),
        BackgroundColor3=Color3.fromRGB(50,18,18), TextColor3=C.Error,
        Parent=TopBar}, {Rnd(5)})

    -- split: lista | detalhes
    local Split = N("Frame",{Size=UDim2.new(1,-24,1,-48),Position=UDim2.new(0,12,0,40),
        BackgroundTransparency=1, Parent=LogTab})

    local LIST_W = 340
    local ListPanel = N("Frame",{Size=UDim2.new(0,LIST_W,1,0),
        BackgroundTransparency=1, Parent=Split})
    local LogScroll = N("ScrollingFrame",{Size=UDim2.new(1,0,1,0),
        BackgroundTransparency=1, BorderSizePixel=0, ScrollBarThickness=4,
        ScrollBarImageColor3=C.Border, CanvasSize=UDim2.new(0,0,0,0),
        Parent=ListPanel})
    local LogInner = N("Frame",{Size=UDim2.new(1,0,1,0),
        BackgroundTransparency=1, Parent=LogScroll})

    -- pool virtual
    local pool = {}
    for i=1,POOL_N do
        local item = N("Frame",{Size=UDim2.new(1,-6,0,ITEM_H),
            BackgroundColor3=C.Panel, BorderSizePixel=0, Visible=false,
            Parent=LogInner},{Rnd(5)})
        local bar = N("Frame",{Size=UDim2.new(0,3,1,-8),
            Position=UDim2.new(0,0,0,4), BackgroundColor3=C.Accent,
            BorderSizePixel=0, Parent=item},{Rnd(2)})
        local tagBg = N("Frame",{Size=UDim2.new(0,74,0,16),
            Position=UDim2.new(0,8,0,6), BackgroundColor3=C.BG,
            BorderSizePixel=0, Parent=item},{Rnd(4)})
        local tagLbl = Lbl("",9,C.Accent,Enum.Font.GothamBold,{
            Size=UDim2.new(1,0,1,0),TextXAlignment=Enum.TextXAlignment.Center,
            Parent=tagBg})
        local nameLbl = Lbl("",12,C.Text,Enum.Font.GothamMedium,{
            Size=UDim2.new(1,-150,0,16),Position=UDim2.new(0,90,0,4),
            TextTruncate=Enum.TextTruncate.AtEnd, Parent=item})
        local argsLbl = Lbl("",10,C.TextD,Enum.Font.Code,{
            Size=UDim2.new(1,-100,0,14),Position=UDim2.new(0,90,0,22),
            TextTruncate=Enum.TextTruncate.AtEnd, Parent=item})
        local timeLbl = Lbl("",9,C.TextM,Enum.Font.Gotham,{
            Size=UDim2.new(0,54,0,14),Position=UDim2.new(1,-58,0,6),
            TextXAlignment=Enum.TextXAlignment.Right, Parent=item})
        local click = N("TextButton",{Text="",Size=UDim2.new(1,0,1,0),
            BackgroundTransparency=1, Parent=item})
        pool[i] = {item=item,bar=bar,tagBg=tagBg,tagLbl=tagLbl,
            nameLbl=nameLbl,argsLbl=argsLbl,timeLbl=timeLbl,click=click,log=nil}
    end

    local filtered = {}
    local selected = nil
    local showDetail -- forward

    -- ── SCROLL INTELIGENTE ──
    -- userScrolled: usuário subiu manualmente, pausa auto-scroll
    -- pendingNew: quantos logs novos chegaram enquanto estava pausado
    local userScrolled = false
    local pendingNew = 0
    local SCROLL_THRESHOLD = 30  -- px do fundo pra considerar "no fundo"

    -- botão flutuante "⬇ Ir pro final (N novos)"
    local JumpBtn = N("TextButton",{
        Text = "⬇ Ir pro final", TextSize = 11, TextColor3 = C.BG,
        Font = Enum.Font.GothamBold, BackgroundColor3 = C.Accent,
        BorderSizePixel = 0, Size = UDim2.new(0,150,0,28),
        Position = UDim2.new(1,-164,1,-38),  -- canto inferior direito do ListPanel
        Visible = false, AutoButtonColor = true, ZIndex = 5,
        Parent = ListPanel},{Rnd(14)})
    JumpBtn.MouseButton1Click:Connect(function()
        userScrolled = false
        pendingNew = 0
        JumpBtn.Visible = false
        local h = math.max(0, #filtered * ITEM_S)
        LogScroll.CanvasSize = UDim2.new(0,0,0,h)
        local vis = LogScroll.AbsoluteSize.Y
        LogScroll.CanvasPosition = Vector2.new(0, math.max(0, h-vis))
    end)

    -- detectar se usuário saiu do fundo
    local function isAtBottom()
        local h = LogScroll.CanvasSize.Y.Offset
        local vis = LogScroll.AbsoluteSize.Y
        local y = LogScroll.CanvasPosition.Y
        if h <= vis then return true end  -- ainda cabe tudo na tela
        return (h - vis - y) <= SCROLL_THRESHOLD
    end

    local function rebuildFiltered()
        filtered = {}
        local f = state.config.filter or ""
        for _, log in ipairs(state.logs) do
            if f == "" or
               (log.remoteName or ""):lower():find(f,1,true) or
               (log.remotePath or ""):lower():find(f,1,true) or
               (log.type or ""):lower():find(f,1,true) then
                filtered[#filtered+1] = log
            end
        end
    end

    local function renderList()
        local total = #filtered
        local canvasH = math.max(0, total * ITEM_S)
        if LogScroll.CanvasSize.Y.Offset ~= canvasH then
            LogScroll.CanvasSize = UDim2.new(0,0,0,canvasH)
        end
        local firstIdx = math.max(1, math.floor(LogScroll.CanvasPosition.Y / ITEM_S))
        for slot=1, POOL_N do
            local idx = firstIdx + slot - 1
            local pi = pool[slot]
            if idx > total then
                pi.item.Visible = false; pi.log = nil
            else
                local log = filtered[idx]
                local clr = typeColor(log.type)
                pi.log = log
                pi.item.Visible = true
                pi.item.Position = UDim2.new(0,3,0,(idx-1)*ITEM_S)
                pi.bar.BackgroundColor3 = log.blocked and C.Error or clr
                pi.tagLbl.TextColor3 = clr
                pi.tagLbl.Text = log.type or ""
                pi.nameLbl.Text = log.remoteName or "?"
                pi.nameLbl.TextColor3 = log.blocked and C.Error or C.Text
                pi.argsLbl.Text = log.argsPreview or ""
                pi.timeLbl.Text = log.timestamp or ""
                pi.item.BackgroundColor3 = (selected == log) and C.PanelH or C.Panel
            end
        end
    end

    LogScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        renderList()
        -- atualizar estado de scroll: se voltou pro fundo, retoma auto-scroll
        if isAtBottom() then
            if userScrolled then
                userScrolled = false
                pendingNew = 0
                JumpBtn.Visible = false
            end
        else
            userScrolled = true
        end
    end)

    for _, pi in ipairs(pool) do
        pi.click.MouseButton1Click:Connect(function()
            if pi.log then
                selected = pi.log
                renderList()
                showDetail(pi.log)
            end
        end)
        pi.item.MouseEnter:Connect(function()
            if pi.log and selected ~= pi.log then
                pi.item.BackgroundColor3 = C.PanelH
            end
        end)
        pi.item.MouseLeave:Connect(function()
            if pi.log and selected ~= pi.log then
                pi.item.BackgroundColor3 = C.Panel
            end
        end)
    end

    -- painel de detalhes
    local DetailPanel = N("Frame",{Size=UDim2.new(1,-LIST_W-8,1,0),
        Position=UDim2.new(0,LIST_W+8,0,0), BackgroundColor3=C.Panel,
        BorderSizePixel=0, Parent=Split}, {Rnd(6)})

    local DTopBar = N("Frame",{Size=UDim2.new(1,-16,0,32),
        Position=UDim2.new(0,8,0,8), BackgroundTransparency=1, Parent=DetailPanel})

    local DTypeLbl = Lbl("", 13, C.Accent, Enum.Font.GothamBold, {
        Size=UDim2.new(0.5,0,1,0), Parent=DTopBar})
    local DMetaLbl = Lbl("", 10, C.TextD, Enum.Font.Code, {
        Size=UDim2.new(0.5,0,1,0), Position=UDim2.new(0.5,0,0,0),
        TextXAlignment=Enum.TextXAlignment.Right, Parent=DTopBar})

    local DInfoFrame = N("Frame",{Size=UDim2.new(1,-16,0,50),
        Position=UDim2.new(0,8,0,42), BackgroundColor3=C.BG,
        BorderSizePixel=0, Parent=DetailPanel}, {Rnd(5), Pad(4,8)})
    local DPathLbl = Lbl("", 10, C.TextD, Enum.Font.Code, {
        Size=UDim2.new(1,0,0,14), Parent=DInfoFrame})
    local DScriptLbl = Lbl("", 10, C.TextD, Enum.Font.Code, {
        Size=UDim2.new(1,0,0,14), Position=UDim2.new(0,0,0,16), Parent=DInfoFrame})
    local DTimeLbl = Lbl("", 10, C.TextM, Enum.Font.Gotham, {
        Size=UDim2.new(1,0,0,14), Position=UDim2.new(0,0,0,32), Parent=DInfoFrame})

    -- code box: mostra script Lua executável gerado
    local CodeContainer = N("Frame",{Size=UDim2.new(1,-16,1,-152),
        Position=UDim2.new(0,8,0,100), BackgroundColor3=C.BG,
        BorderSizePixel=0, Parent=DetailPanel}, {Rnd(5)})
    local CodeScroll = N("ScrollingFrame",{Size=UDim2.new(1,0,1,0),
        BackgroundTransparency=1, BorderSizePixel=0, ScrollBarThickness=4,
        ScrollBarImageColor3=C.Border, CanvasSize=UDim2.new(0,0,0,0),
        Parent=CodeContainer})
    local CodeBox = N("TextLabel",{Text="-- Selecione um log para ver o script gerado",
        TextSize=11, Font=Enum.Font.Code, TextColor3=C.Text,
        BackgroundTransparency=1, Size=UDim2.new(1,-16,0,400),
        Position=UDim2.new(0,8,0,6), TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Top, TextWrapped=false,
        Parent=CodeScroll})

    -- ações
    local ActBar = N("Frame",{Size=UDim2.new(1,-16,0,34),
        Position=UDim2.new(0,8,1,-42), BackgroundTransparency=1, Parent=DetailPanel})

    local CopyScriptBtn = Btn("📋 Copiar Script", 11, {Size=UDim2.new(0,130,1,0),
        Position=UDim2.new(0,0,0,0), BackgroundColor3=C.AccentD,
        Parent=ActBar}, {Rnd(5)})
    local CopyPathBtn = Btn("📝 Copiar Path", 11, {Size=UDim2.new(0,112,1,0),
        Position=UDim2.new(0,136,0,0), BackgroundColor3=C.Panel,
        Parent=ActBar}, {Rnd(5)})
    local BlockBtn = Btn("🚫 Bloquear", 11, {Size=UDim2.new(0,100,1,0),
        Position=UDim2.new(0,254,0,0),
        BackgroundColor3=Color3.fromRGB(50,18,18), TextColor3=C.Error,
        Parent=ActBar}, {Rnd(5)})
    local RunBtn = Btn("▶ Executar", 11, {Size=UDim2.new(0,94,1,0),
        Position=UDim2.new(1,-96,0,0), BackgroundColor3=Color3.fromRGB(25,70,35),
        TextColor3=C.Success, Parent=ActBar}, {Rnd(5)})

    local currentLog = nil
    local currentScript = ""

    showDetail = function(log)
        if not log then return end
        currentLog = log
        local clr = typeColor(log.type)
        DTypeLbl.Text = log.type or "?"
        DTypeLbl.TextColor3 = clr
        DMetaLbl.Text = log.metamethod or ""
        DPathLbl.Text = "📁 "..(log.remotePath or "?")
        local srcTxt = "📜 "
        if log.callerScript then
            local ok, p = pcall(function() return log.callerScript:GetFullName() end)
            srcTxt = srcTxt..(ok and p or tostring(log.callerScript))
            if log.callerLine then srcTxt = srcTxt..":"..log.callerLine end
        else
            srcTxt = srcTxt.."(script não disponível)"
        end
        DScriptLbl.Text = srcTxt
        DTimeLbl.Text = "⏰ "..(log.timestamp or "?").."  |  args: "..(log.argCount or 0)

        -- gerar script
        CodeBox.Text = "-- gerando..."
        task.spawn(function()
            local okGen, code, needNil = pcall(state.serializer.encode, log.args or {})
            if not okGen then
                currentScript = "-- erro ao gerar script:\n-- "..tostring(code)
            else
                local header = string.format("-- [RSP] %s  [%s via %s]\n-- Path: %s\n\n",
                    log.timestamp or "?", log.type or "?", log.metamethod or "?",
                    log.remotePath or "?")
                if needNil then header = header..GETNIL_HELPER end

                local pathCode = string.format('game:GetService("%s")',
                    log.remote and log.remote:FindFirstAncestorOfClass("Workspace") and "Workspace"
                    or "ReplicatedStorage")
                -- usar serializer pra path exato
                local okP, pathExact = pcall(state.serializer.encodeSingle, log.remote)
                if okP and pathExact then pathCode = pathExact end

                local call
                if log.type == "FireServer" then
                    call = pathCode..":FireServer(unpack(args))"
                elseif log.type == "InvokeServer" then
                    call = "local returned = "..pathCode..":InvokeServer(unpack(args))"
                else
                    call = "-- "..pathCode..":FireServer(unpack(args))  -- (é OnClientEvent, só log)"
                end
                currentScript = header..code.."\n\n"..call
            end
            CodeBox.Text = currentScript
            -- ajustar altura da textbox com base em linhas
            local lines = 1
            for _ in currentScript:gmatch("\n") do lines = lines + 1 end
            local h = math.max(400, lines * 14)
            CodeBox.Size = UDim2.new(1,-16,0,h)
            CodeScroll.CanvasSize = UDim2.new(0,0,0,h+12)
            CodeScroll.CanvasPosition = Vector2.new(0,0)
        end)

        -- atualizar Block button
        if state.blocked[log.remotePath] then
            BlockBtn.Text = "✅ Desbloquear"
            BlockBtn.BackgroundColor3 = Color3.fromRGB(25,70,35)
            BlockBtn.TextColor3 = C.Success
        else
            BlockBtn.Text = "🚫 Bloquear"
            BlockBtn.BackgroundColor3 = Color3.fromRGB(50,18,18)
            BlockBtn.TextColor3 = C.Error
        end
    end

    CopyScriptBtn.MouseButton1Click:Connect(function()
        if not currentLog or currentScript == "" then return end
        if state.env.setclipboard then
            state.env.setclipboard(currentScript)
            CopyScriptBtn.Text = "✅ Copiado!"
            task.delay(1.2, function() CopyScriptBtn.Text = "📋 Copiar Script" end)
        end
    end)

    CopyPathBtn.MouseButton1Click:Connect(function()
        if not currentLog then return end
        if state.env.setclipboard then
            state.env.setclipboard(currentLog.remotePath or "")
            CopyPathBtn.Text = "✅ Copiado!"
            task.delay(1.2, function() CopyPathBtn.Text = "📝 Copiar Path" end)
        end
    end)

    BlockBtn.MouseButton1Click:Connect(function()
        if not currentLog then return end
        local p = currentLog.remotePath
        if state.blocked[p] then
            state.blocked[p] = nil
        else
            state.blocked[p] = true
        end
        showDetail(currentLog)
    end)

    RunBtn.MouseButton1Click:Connect(function()
        if not currentLog or not currentLog.remote then return end
        RunBtn.Text = "..."
        task.spawn(function()
            local ok, err = pcall(function()
                if currentLog.type == "FireServer" then
                    currentLog.remote:FireServer(unpack(currentLog.args))
                elseif currentLog.type == "InvokeServer" then
                    currentLog.remote:InvokeServer(unpack(currentLog.args))
                end
            end)
            RunBtn.Text = ok and "✓ OK" or "✗ Erro"
            task.delay(1.5, function() RunBtn.Text = "▶ Executar" end)
        end)
    end)

    ClearBtn.MouseButton1Click:Connect(function()
        table.clear(state.logs)
        selected = nil
        currentLog = nil
        filtered = {}
        userScrolled = false
        pendingNew = 0
        JumpBtn.Visible = false
        LogScroll.CanvasSize = UDim2.new(0,0,0,0)
        LogScroll.CanvasPosition = Vector2.new(0,0)
        for _, p in ipairs(pool) do p.item.Visible = false; p.log = nil end
        CountLbl.Text = "0 logs"
        CodeBox.Text = "-- logs limpos"
    end)

    SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        state.config.filter = SearchBox.Text:lower()
        rebuildFiltered()
        CountLbl.Text = #filtered.." logs"
        LogScroll.CanvasPosition = Vector2.new(0,0)
        renderList()
    end)

    -- ╔══════════════════════════════════════╗
    -- ║          ABA BLOCKED                 ║
    -- ╚══════════════════════════════════════╝
    local BlkTab = tabContents["Blocked"]
    local BlkScroll = N("ScrollingFrame",{Size=UDim2.new(1,-16,1,-16),
        Position=UDim2.new(0,8,0,8), BackgroundTransparency=1, BorderSizePixel=0,
        ScrollBarThickness=4, ScrollBarImageColor3=C.Border,
        CanvasSize=UDim2.new(0,0,0,0), Parent=BlkTab})
    local BlkList = N("Frame",{Size=UDim2.new(1,0,0,0),
        BackgroundTransparency=1, Parent=BlkScroll},{
        N("UIListLayout",{Padding=UDim.new(0,4), SortOrder=Enum.SortOrder.LayoutOrder}),
        Pad(4,4)})
    local blkLayout = BlkList:FindFirstChildOfClass("UIListLayout")
    blkLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        BlkScroll.CanvasSize = UDim2.new(0,0,0,blkLayout.AbsoluteContentSize.Y+16)
    end)

    local function refreshBlocked()
        for _, c in ipairs(BlkList:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        local any = false
        for path, _ in pairs(state.blocked) do
            any = true
            local row = N("Frame",{Size=UDim2.new(1,-4,0,32),
                BackgroundColor3=Color3.fromRGB(40,18,18),BorderSizePixel=0,
                Parent=BlkList},{Rnd(5), Pad(0,10)})
            Lbl("🚫 "..path, 11, C.Text, Enum.Font.Gotham,{
                Size=UDim2.new(1,-90,1,0),
                TextTruncate=Enum.TextTruncate.AtEnd, Parent=row})
            local unb = Btn("Permitir", 10, {Size=UDim2.new(0,78,0,22),
                Position=UDim2.new(1,-82,0.5,-11),
                BackgroundColor3=Color3.fromRGB(25,60,30),TextColor3=C.Success,
                Parent=row},{Rnd(4)})
            unb.MouseButton1Click:Connect(function()
                state.blocked[path] = nil
                row:Destroy()
            end)
        end
        if not any then
            Lbl("Nenhum remote bloqueado", 11, C.TextM, Enum.Font.Gotham,{
                Size=UDim2.new(1,0,0,40), TextXAlignment=Enum.TextXAlignment.Center,
                Parent=BlkList})
        end
    end

    tabs["Blocked"].MouseButton1Click:Connect(refreshBlocked)

    -- ╔══════════════════════════════════════╗
    -- ║           ABA CONFIG                 ║
    -- ╚══════════════════════════════════════╝
    local CfgTab = tabContents["Config"]
    local CfgScroll = N("ScrollingFrame",{Size=UDim2.new(1,-16,1,-16),
        Position=UDim2.new(0,8,0,8), BackgroundTransparency=1, BorderSizePixel=0,
        ScrollBarThickness=4, ScrollBarImageColor3=C.Border,
        CanvasSize=UDim2.new(0,0,0,0), Parent=CfgTab})
    local CfgList = N("Frame",{Size=UDim2.new(1,0,0,0),
        BackgroundTransparency=1, Parent=CfgScroll},{
        N("UIListLayout",{Padding=UDim.new(0,5), SortOrder=Enum.SortOrder.LayoutOrder}),
        Pad(4,4)})
    local cfgLayout = CfgList:FindFirstChildOfClass("UIListLayout")
    cfgLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        CfgScroll.CanvasSize = UDim2.new(0,0,0,cfgLayout.AbsoluteContentSize.Y+16)
    end)

    local ord = 0
    local function cfgSec(txt)
        ord = ord + 1
        Lbl(txt, 10, C.TextD, Enum.Font.GothamBold, {
            Size=UDim2.new(1,0,0,18), LayoutOrder=ord, Parent=CfgList})
    end
    local function cfgTog(label, key)
        ord = ord + 1
        local row = N("Frame",{Size=UDim2.new(1,-4,0,30),BackgroundColor3=C.Panel,
            BorderSizePixel=0,LayoutOrder=ord,Parent=CfgList},{Rnd(5), Pad(0,10)})
        Lbl(label,11,C.Text,Enum.Font.Gotham,{Size=UDim2.new(1,-50,1,0),Parent=row})
        local on = state.config[key]
        local bg = N("Frame",{Size=UDim2.new(0,34,0,16),
            Position=UDim2.new(1,-40,0.5,-8),
            BackgroundColor3=on and C.Accent or C.Border,BorderSizePixel=0,
            Parent=row},{Rnd(8)})
        local knob = N("Frame",{Size=UDim2.new(0,10,0,10),
            Position=UDim2.new(on and 1 or 0, on and -13 or 3, 0.5, -5),
            BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Parent=bg},{Rnd(5)})
        N("TextButton",{Text="",Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,
            Parent=bg}).MouseButton1Click:Connect(function()
            state.config[key] = not state.config[key]
            local v = state.config[key]
            TweenService:Create(bg,TweenInfo.new(0.14),{
                BackgroundColor3=v and C.Accent or C.Border}):Play()
            TweenService:Create(knob,TweenInfo.new(0.14),{
                Position=UDim2.new(v and 1 or 0, v and -13 or 3, 0.5, -5)}):Play()
        end)
    end

    cfgSec("── CAPTURA ──")
    cfgTog("Habilitar captura", "enabled")
    cfgTog("Logar chamadas do próprio executor (checkcaller)", "logCheckCaller")
    cfgTog("Logar OnClientEvent (Server → Client)", "logClientEvents")

    cfgSec("── INTERFACE ──")
    cfgTog("Auto-scroll", "autoScroll")

    cfgSec("── AMBIENTE ──")
    ord = ord + 1
    local envBox = N("Frame",{Size=UDim2.new(1,-4,0,90),
        BackgroundColor3=C.Panel,BorderSizePixel=0,LayoutOrder=ord,
        Parent=CfgList},{Rnd(5), Pad(6,10)})
    Lbl("Executor: "..state.env.Name, 11, C.Text, Enum.Font.GothamBold,{
        Size=UDim2.new(1,0,0,16),Parent=envBox})
    Lbl("Hook: "..(state.env.hookMode or "?"), 10, C.TextD, Enum.Font.Gotham,{
        Size=UDim2.new(1,0,0,14),Position=UDim2.new(0,0,0,18),Parent=envBox})
    local hookStatsLbl = Lbl("", 10, C.TextD, Enum.Font.Code,{
        Size=UDim2.new(1,0,0,14),Position=UDim2.new(0,0,0,34),Parent=envBox})
    Lbl("hookfunction: "..tostring(state.env.CanHookFunction)
        .."  |  hookmetamethod: "..tostring(state.env.CanHookMeta),
        9, C.TextM, Enum.Font.Gotham,{
        Size=UDim2.new(1,0,0,14),Position=UDim2.new(0,0,0,50),Parent=envBox})
    Lbl("clipboard: "..(state.env.setclipboard and "✓" or "✗")
        .."  |  cloneref: "..(state.env.cloneref and "✓" or "✗"),
        9, C.TextM, Enum.Font.Gotham,{
        Size=UDim2.new(1,0,0,14),Position=UDim2.new(0,0,0,66),Parent=envBox})

    -- export json
    ord = ord + 1
    local ExpBtn = Btn("📤 Exportar JSON", 11, {Size=UDim2.new(0,160,0,28),
        BackgroundColor3=C.AccentD, LayoutOrder=ord,Parent=CfgList}, {Rnd(5)})
    ExpBtn.MouseButton1Click:Connect(function()
        if not state.env.setclipboard then return end
        local export = {}
        for _, l in ipairs(state.logs) do
            export[#export+1] = {
                id=l.id,timestamp=l.timestamp,type=l.type,
                remoteName=l.remoteName, remotePath=l.remotePath,
                argCount=l.argCount, argsPreview=l.argsPreview,
                metamethod=l.metamethod, blocked=l.blocked,
            }
        end
        local ok, j = pcall(HttpService.JSONEncode, HttpService, export)
        if ok then
            state.env.setclipboard(j)
            ExpBtn.Text = "✓ Copiado!"
            task.delay(1.5, function() ExpBtn.Text = "📤 Exportar JSON" end)
        end
    end)

    -- DRAG
    do
        local drag,ds,sp = false
        HDR.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                drag=true; ds=i.Position; sp=Win.Position end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if drag and (i.UserInputType == Enum.UserInputType.MouseMovement
            or i.UserInputType == Enum.UserInputType.Touch) then
                local d=i.Position-ds
                Win.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,
                    sp.Y.Scale,sp.Y.Offset+d.Y) end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then drag=false end
        end)
    end

    CloseBtn.MouseButton1Click:Connect(function() Gui:Destroy() end)

    -- abrir aba inicial (não usar :Fire() - RBXScriptSignal não tem esse método)
    tabs["Logs"].BackgroundColor3 = C.Accent
    tabs["Logs"].TextColor3 = C.BG
    tabContents["Logs"].Visible = true
    currentTab = "Logs"

    -- animação de abertura
    Win.Size = UDim2.new(0,0,0,0)
    TweenService:Create(Win, TweenInfo.new(0.25, Enum.EasingStyle.Back,
        Enum.EasingDirection.Out), {Size=UDim2.new(0,WIN_W,0,WIN_H)}):Play()

    -- hookStats live update
    task.spawn(function()
        while Gui.Parent do
            local s = state.hookStats or {}
            hookStatsLbl.Text = string.format("stats: ns=%d fs=%d is=%d ce=%d",
                s.ns or 0, s.fs or 0, s.is or 0, s.ce or 0)
            task.wait(0.5)
        end
    end)

    -- API para atualizar UI externamente
    return {
        onNewLog = function(log)
            log.argsPreview = state.serializer.previewArgs(log.args or {}, 6)
            rebuildFiltered()
            CountLbl.Text = #filtered.." logs"

            if state.config.autoScroll and not userScrolled then
                -- usuário está no fundo: scrolla pro novo log normalmente
                task.defer(function()
                    local h = math.max(0, #filtered * ITEM_S)
                    LogScroll.CanvasSize = UDim2.new(0,0,0,h)
                    local vis = LogScroll.AbsoluteSize.Y
                    LogScroll.CanvasPosition = Vector2.new(0, math.max(0, h-vis))
                    renderList()
                end)
            else
                -- usuário subiu pra ler: não mexe no scroll, só atualiza canvas
                -- e mostra quantos logs novos chegaram
                pendingNew = pendingNew + 1
                JumpBtn.Text = "⬇ "..pendingNew.." novo"..(pendingNew>1 and "s" or "")
                JumpBtn.Visible = true
                task.defer(renderList)
            end
        end,
        rebuild = function()
            rebuildFiltered()
            CountLbl.Text = #filtered.." logs"
            renderList()
        end,
        gui = Gui,
    }
end

return M

end)()

-- ═══════════════════════════════════════
-- main
-- ═══════════════════════════════════════
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
