--[[
    ██████╗ ███████╗███╗   ███╗ ██████╗ ████████╗███████╗    ███████╗██████╗ ██╗   ██╗
    ██╔══██╗██╔════╝████╗ ████║██╔═══██╗╚══██╔══╝██╔════╝    ██╔════╝██╔══██╗╚██╗ ██╔╝
    ██████╔╝█████╗  ██╔████╔██║██║   ██║   ██║   █████╗      ███████╗██████╔╝ ╚████╔╝ 
    ██╔══██╗██╔══╝  ██║╚██╔╝██║██║   ██║   ██║   ██╔══╝      ╚════██║██╔═══╝   ╚██╔╝  
    ██║  ██║███████╗██║ ╚═╝ ██║╚██████╔╝   ██║   ███████╗    ███████║██║        ██║   
    ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝ ╚═════╝    ╚═╝   ╚══════╝    ╚══════╝╚═╝        ╚═╝   
    
    Remote Spy Pro - Script de Espionagem de Remotes Completo
    Versão: 2.0
    Compatível com execução no cliente (exploits como Synapse X, KRNL, etc.)
    
    Funcionalidades:
    - Hook em RemoteEvent:FireServer / InvokeServer
    - Hook em RemoteFunction:InvokeServer
    - Hook em eventos recebidos do servidor (OnClientEvent / OnClientInvoke)
    - Hook em BindableEvent e BindableFunction
    - Exibe argumentos formatados com tipo
    - UI com abas: Remotes, Logs, Bloqueados, Configurações
    - Filtros por nome, tipo
    - Bloquear/permitir remotes individuais
    - Copiar chamadas como código Lua
    - Script caller (rastrear de onde foi chamado)
    - Histórico de logs com timestamp
    - Contador de chamadas por remote
    - Detalhe completo de cada chamada
]]

-- ============================================================
-- VERIFICAÇÕES DE AMBIENTE
-- ============================================================

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- Funções de exploit necessárias
local getrawmetatable = getrawmetatable or rawget
local hookmetamethod = hookmetamethod or nil
local newcclosure = newcclosure or function(f) return f end
local checkcaller = checkcaller or function() return false end
local getcallingscript = getcallingscript or function() return nil end
local isexecutorclosure = isexecutorclosure or function() return false end
local cloneref = cloneref or function(x) return x end
local getnamecallmethod = getnamecallmethod or function() return "" end

-- ============================================================
-- ESTADO GLOBAL
-- ============================================================

local RSP = {
    Enabled = true,
    Logs = {},
    Blocked = {},
    MaxLogs = 500,
    Settings = {
        ShowFireServer = true,
        ShowInvokeServer = true,
        ShowOnClientEvent = true,
        ShowOnClientInvoke = true,
        ShowBindables = true,
        LogCallerScript = true,
        LogCallerLine = true,
        AutoScroll = true,
        ShowNotifications = true,
        MaxArgs = 10,
        Theme = "Dark",
    },
    Stats = {},  -- { [remotePath] = { calls = 0, blocked = 0 } }
    Filter = "",
    SelectedLog = nil,
    CurrentTab = "Logs",
    UI = {},
    Connections = {},
    OriginalFunctions = {},
    Version = "2.0",
}

-- ============================================================
-- UTILIDADES
-- ============================================================

local function getTimestamp()
    return os.date("%H:%M:%S")
end

local function getFullPath(instance)
    if not instance then return "Unknown" end
    local ok, path = pcall(function()
        local parts = {}
        local obj = instance
        while obj and obj ~= game do
            table.insert(parts, 1, obj.Name)
            obj = obj.Parent
        end
        return table.concat(parts, ".")
    end)
    return ok and path or tostring(instance)
end

local function formatValue(value, depth)
    depth = depth or 0
    if depth > 3 then return "..." end
    
    local t = typeof(value)
    
    if t == "string" then
        local escaped = value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
        if #escaped > 80 then
            return string.format('"%s..." [string:%d]', escaped:sub(1, 77), #value)
        end
        return string.format('"%s"', escaped)
    elseif t == "number" then
        if value == math.floor(value) then
            return string.format("%d", value)
        end
        return string.format("%.4f", value):gsub("%.?0+$", "")
    elseif t == "boolean" then
        return tostring(value)
    elseif t == "nil" then
        return "nil"
    elseif t == "table" then
        local count = 0
        local parts = {}
        for k, v in pairs(value) do
            count = count + 1
            if count > 8 then
                table.insert(parts, string.format("... (+%d)", count - 8))
                break
            end
            local key = type(k) == "string" and k or string.format("[%s]", tostring(k))
            table.insert(parts, string.format("%s = %s", key, formatValue(v, depth + 1)))
        end
        if count == 0 then return "{}" end
        return "{ " .. table.concat(parts, ", ") .. " }"
    elseif t == "Instance" then
        local ok, path = pcall(getFullPath, value)
        local cls = ok and value.ClassName or "Instance"
        return string.format("<%s: %s>", cls, ok and path or "?")
    elseif t == "Vector3" then
        return string.format("Vector3(%g, %g, %g)", value.X, value.Y, value.Z)
    elseif t == "Vector2" then
        return string.format("Vector2(%g, %g)", value.X, value.Y)
    elseif t == "CFrame" then
        local p = value.Position
        return string.format("CFrame(%g, %g, %g)", p.X, p.Y, p.Z)
    elseif t == "Color3" then
        return string.format("Color3(%d, %d, %d)", value.R*255, value.G*255, value.B*255)
    elseif t == "UDim2" then
        return string.format("UDim2(%g,%g, %g,%g)", value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset)
    elseif t == "Enum" or t == "EnumItem" then
        return tostring(value)
    elseif t == "function" then
        return string.format("<function>")
    elseif t == "userdata" then
        return string.format("<userdata>")
    else
        return string.format("<%s: %s>", t, tostring(value))
    end
end

local function formatArgs(args)
    if not args or #args == 0 then return "()" end
    local parts = {}
    for i, v in ipairs(args) do
        if i > RSP.Settings.MaxArgs then
            table.insert(parts, string.format("... (+%d args)", #args - RSP.Settings.MaxArgs))
            break
        end
        table.insert(parts, formatValue(v))
    end
    return "(" .. table.concat(parts, ", ") .. ")"
end

local function valueToLua(value, depth)
    depth = depth or 0
    if depth > 3 then return "nil --[[deep]]" end
    local t = typeof(value)
    if t == "string" then
        return string.format("%q", value)
    elseif t == "number" or t == "boolean" or t == "nil" then
        return tostring(value)
    elseif t == "table" then
        local parts = {}
        for k, v in pairs(value) do
            local key = type(k) == "string" and string.format("[%q]", k) or string.format("[%d]", k)
            table.insert(parts, string.format("  %s = %s", key, valueToLua(v, depth+1)))
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n}"
    elseif t == "Vector3" then
        return string.format("Vector3.new(%g, %g, %g)", value.X, value.Y, value.Z)
    elseif t == "Vector2" then
        return string.format("Vector2.new(%g, %g)", value.X, value.Y)
    elseif t == "CFrame" then
        local p = value.Position
        return string.format("CFrame.new(%g, %g, %g)", p.X, p.Y, p.Z)
    elseif t == "Color3" then
        return string.format("Color3.fromRGB(%d, %d, %d)", value.R*255, value.G*255, value.B*255)
    elseif t == "UDim2" then
        return string.format("UDim2.new(%g, %g, %g, %g)", value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset)
    elseif t == "EnumItem" then
        return tostring(value)
    elseif t == "Instance" then
        return string.format('game:GetService("Players").LocalPlayer --[[%s]]', getFullPath(value))
    else
        return string.format("nil --[[%s]]", t)
    end
end

local function argsToLua(args)
    local parts = {}
    for _, v in ipairs(args or {}) do
        table.insert(parts, valueToLua(v))
    end
    return table.concat(parts, ", ")
end

local function getCallerInfo()
    if not RSP.Settings.LogCallerScript then return nil, nil end
    local ok, info = pcall(function()
        -- Pular frames internos do RemoteSpy
        for i = 3, 10 do
            local dbinfo = debug.info(i, "sln")
            if dbinfo then
                local src = dbinfo[1] or ""
                local line = dbinfo[2] or 0
                local name = dbinfo[3] or ""
                -- Ignorar frames do executor e do RemoteSpy
                if not src:find("RemoteSpy") and not src:find("executor") and src ~= "" then
                    return src, line
                end
            end
        end
        return nil, nil
    end)
    if ok then return info end
    return nil, nil
end

-- ============================================================
-- SISTEMA DE LOGGING
-- ============================================================

local logCallbacks = {}

local function addLog(logData)
    -- Incrementar stats
    local path = logData.remotePath or "unknown"
    if not RSP.Stats[path] then
        RSP.Stats[path] = { calls = 0, blocked = 0 }
    end
    RSP.Stats[path].calls = RSP.Stats[path].calls + 1
    if logData.blocked then
        RSP.Stats[path].blocked = RSP.Stats[path].blocked + 1
    end
    
    logData.id = #RSP.Logs + 1
    logData.timestamp = getTimestamp()
    
    table.insert(RSP.Logs, logData)
    
    -- Limitar tamanho
    while #RSP.Logs > RSP.MaxLogs do
        table.remove(RSP.Logs, 1)
    end
    
    -- Notificar callbacks de UI
    for _, cb in ipairs(logCallbacks) do
        pcall(cb, logData)
    end
end

local function onNewLog(callback)
    table.insert(logCallbacks, callback)
end

-- ============================================================
-- HOOK ENGINE
-- ============================================================

local hooked = false

local function setupHooks()
    if hooked then return end
    hooked = true
    
    -- Verificar se hookmetamethod está disponível
    if not hookmetamethod then
        warn("[RemoteSpy] hookmetamethod não disponível. Usando método alternativo.")
        -- Método alternativo: monkey patch direto nas instâncias descobertas
        setupAlternativeHook()
        return
    end
    
    local gameMeta = getrawmetatable(game)
    local oldNamecall = gameMeta.__namecall
    RSP.OriginalFunctions.__namecall = oldNamecall
    
    hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if not RSP.Enabled then
            return oldNamecall(self, ...)
        end
        
        local method = getnamecallmethod()
        local args = {...}
        
        -- Verificar se é chamada interna do executor
        if checkcaller and checkcaller() then
            return oldNamecall(self, ...)
        end
        
        local isRemoteEvent = typeof(self) == "Instance" and self:IsA("RemoteEvent")
        local isRemoteFunction = typeof(self) == "Instance" and self:IsA("RemoteFunction")
        local isBindableEvent = typeof(self) == "Instance" and self:IsA("BindableEvent")
        local isBindableFunction = typeof(self) == "Instance" and self:IsA("BindableFunction")
        
        -- RemoteEvent:FireServer
        if isRemoteEvent and method == "FireServer" then
            if not RSP.Settings.ShowFireServer then
                return oldNamecall(self, ...)
            end
            
            local path = getFullPath(self)
            local isBlocked = RSP.Blocked[path]
            
            local callerSrc, callerLine = getCallerInfo()
            
            addLog({
                type = "FireServer",
                remoteType = "RemoteEvent",
                remoteName = self.Name,
                remotePath = path,
                remote = self,
                args = args,
                argsFormatted = formatArgs(args),
                blocked = isBlocked,
                callerScript = callerSrc,
                callerLine = callerLine,
                direction = "→ Server",
            })
            
            if isBlocked then return end
            return oldNamecall(self, ...)
        end
        
        -- RemoteFunction:InvokeServer
        if isRemoteFunction and method == "InvokeServer" then
            if not RSP.Settings.ShowInvokeServer then
                return oldNamecall(self, ...)
            end
            
            local path = getFullPath(self)
            local isBlocked = RSP.Blocked[path]
            
            local callerSrc, callerLine = getCallerInfo()
            
            addLog({
                type = "InvokeServer",
                remoteType = "RemoteFunction",
                remoteName = self.Name,
                remotePath = path,
                remote = self,
                args = args,
                argsFormatted = formatArgs(args),
                blocked = isBlocked,
                callerScript = callerSrc,
                callerLine = callerLine,
                direction = "→ Server",
            })
            
            if isBlocked then return nil end
            return oldNamecall(self, ...)
        end
        
        -- BindableEvent:Fire
        if isBindableEvent and method == "Fire" and RSP.Settings.ShowBindables then
            local path = getFullPath(self)
            local isBlocked = RSP.Blocked[path]
            
            local callerSrc, callerLine = getCallerInfo()
            
            addLog({
                type = "Fire",
                remoteType = "BindableEvent",
                remoteName = self.Name,
                remotePath = path,
                remote = self,
                args = args,
                argsFormatted = formatArgs(args),
                blocked = isBlocked,
                callerScript = callerSrc,
                callerLine = callerLine,
                direction = "→ Bindable",
            })
            
            if isBlocked then return end
            return oldNamecall(self, ...)
        end
        
        -- BindableFunction:Invoke
        if isBindableFunction and method == "Invoke" and RSP.Settings.ShowBindables then
            local path = getFullPath(self)
            local isBlocked = RSP.Blocked[path]
            
            local callerSrc, callerLine = getCallerInfo()
            
            addLog({
                type = "Invoke",
                remoteType = "BindableFunction",
                remoteName = self.Name,
                remotePath = path,
                remote = self,
                args = args,
                argsFormatted = formatArgs(args),
                blocked = isBlocked,
                callerScript = callerSrc,
                callerLine = callerLine,
                direction = "→ Bindable",
            })
            
            if isBlocked then return nil end
            return oldNamecall(self, ...)
        end
        
        return oldNamecall(self, ...)
    end))
    
    -- Hook OnClientEvent e OnClientInvoke via __index
    local oldIndex = gameMeta.__index
    RSP.OriginalFunctions.__index = oldIndex
    
    hookmetamethod(game, "__index", newcclosure(function(self, key)
        local result = oldIndex(self, key)
        
        if not RSP.Enabled then return result end
        if checkcaller and checkcaller() then return result end
        
        -- Hookar OnClientEvent
        if typeof(self) == "Instance" and self:IsA("RemoteEvent") and key == "OnClientEvent" then
            if RSP.Settings.ShowOnClientEvent then
                -- Wrap o connect para logar
                local wrappedSignal = setmetatable({}, {
                    __index = result,
                    __newindex = result,
                    __namecall = function(sig, ...)
                        local method2 = getnamecallmethod()
                        if method2 == "Connect" or method2 == "connect" then
                            local connectArgs = {...}
                            local originalCallback = connectArgs[1]
                            if type(originalCallback) == "function" then
                                connectArgs[1] = function(...)
                                    local cbArgs = {...}
                                    local path = getFullPath(self)
                                    addLog({
                                        type = "OnClientEvent",
                                        remoteType = "RemoteEvent",
                                        remoteName = self.Name,
                                        remotePath = path,
                                        remote = self,
                                        args = cbArgs,
                                        argsFormatted = formatArgs(cbArgs),
                                        blocked = false,
                                        callerScript = nil,
                                        callerLine = nil,
                                        direction = "← Client",
                                    })
                                    return originalCallback(...)
                                end
                            end
                            return oldIndex(sig, "Connect")(sig, table.unpack(connectArgs))
                        end
                        return oldIndex(sig, method2)(sig, ...)
                    end,
                })
                return wrappedSignal
            end
        end
        
        return result
    end))
end

-- Método alternativo para exploits sem hookmetamethod
function setupAlternativeHook()
    -- Hook via substituição direta nos métodos
    local originalFireServer = Instance.new("RemoteEvent").FireServer
    local originalInvokeServer = Instance.new("RemoteFunction").InvokeServer
    
    -- Esta abordagem funciona em alguns executores
    local function hookInstance(instance)
        if not instance or not instance.Parent then return end
        
        if instance:IsA("RemoteEvent") then
            local orig = instance.FireServer
            RSP.OriginalFunctions[instance] = RSP.OriginalFunctions[instance] or {}
            RSP.OriginalFunctions[instance].FireServer = orig
            
            -- Sobrescrever (pode não funcionar em todos os exploits)
            pcall(function()
                instance.FireServer = function(self, ...)
                    local args = {...}
                    local path = getFullPath(self)
                    if RSP.Enabled and RSP.Settings.ShowFireServer then
                        addLog({
                            type = "FireServer",
                            remoteType = "RemoteEvent",
                            remoteName = self.Name,
                            remotePath = path,
                            remote = self,
                            args = args,
                            argsFormatted = formatArgs(args),
                            blocked = RSP.Blocked[path] or false,
                            direction = "→ Server",
                        })
                        if RSP.Blocked[path] then return end
                    end
                    return orig(self, ...)
                end
            end)
        end
    end
    
    -- Escanear workspace e scripts
    local function scanDescendants(parent)
        for _, child in ipairs(parent:GetDescendants()) do
            hookInstance(child)
        end
    end
    
    pcall(scanDescendants, game)
    
    -- Monitorar novos descendants
    game.DescendantAdded:Connect(function(obj)
        task.defer(hookInstance, obj)
    end)
end

-- ============================================================
-- INTERFACE GRÁFICA
-- ============================================================

-- Remover UI antiga se existir
if RSP.UI.ScreenGui then
    pcall(function() RSP.UI.ScreenGui:Destroy() end)
end

-- Cores do tema
local Theme = {
    Background = Color3.fromRGB(15, 15, 20),
    Surface = Color3.fromRGB(22, 22, 30),
    SurfaceAlt = Color3.fromRGB(28, 28, 38),
    Border = Color3.fromRGB(45, 45, 65),
    Accent = Color3.fromRGB(100, 180, 255),
    AccentDim = Color3.fromRGB(60, 120, 200),
    Success = Color3.fromRGB(80, 220, 120),
    Warning = Color3.fromRGB(255, 190, 60),
    Error = Color3.fromRGB(255, 80, 80),
    Text = Color3.fromRGB(220, 220, 235),
    TextDim = Color3.fromRGB(140, 140, 160),
    TextMuted = Color3.fromRGB(80, 80, 100),
    
    -- Cores por tipo de remote
    FireServer = Color3.fromRGB(100, 180, 255),
    InvokeServer = Color3.fromRGB(180, 120, 255),
    OnClientEvent = Color3.fromRGB(80, 220, 150),
    OnClientInvoke = Color3.fromRGB(150, 255, 180),
    Fire = Color3.fromRGB(255, 160, 60),
    Invoke = Color3.fromRGB(255, 120, 80),
    Blocked = Color3.fromRGB(255, 60, 60),
}

local function typeColor(logType)
    return Theme[logType] or Theme.TextDim
end

-- Helpers para criar instâncias
local function Create(className, properties, children)
    local inst = Instance.new(className)
    for k, v in pairs(properties or {}) do
        if k ~= "Parent" then
            inst[k] = v
        end
    end
    for _, child in ipairs(children or {}) do
        if child then child.Parent = inst end
    end
    if properties and properties.Parent then
        inst.Parent = properties.Parent
    end
    return inst
end

local function Label(text, size, color, font, props)
    local p = props or {}
    p.Text = text
    p.TextSize = size or 13
    p.TextColor3 = color or Theme.Text
    p.Font = font or Enum.Font.Gotham
    p.BackgroundTransparency = p.BackgroundTransparency ~= nil and p.BackgroundTransparency or 1
    p.TextXAlignment = p.TextXAlignment or Enum.TextXAlignment.Left
    return Create("TextLabel", p)
end

local function Button(text, size, props, children)
    local p = props or {}
    p.Text = text
    p.TextSize = size or 13
    p.Font = p.Font or Enum.Font.GothamBold
    p.TextColor3 = p.TextColor3 or Theme.Text
    p.BackgroundColor3 = p.BackgroundColor3 or Theme.SurfaceAlt
    p.BorderSizePixel = 0
    p.AutoButtonColor = false
    local btn = Create("TextButton", p, children)
    
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), {
            BackgroundColor3 = Color3.new(
                math.min(1, btn.BackgroundColor3.R + 0.08),
                math.min(1, btn.BackgroundColor3.G + 0.08),
                math.min(1, btn.BackgroundColor3.B + 0.08)
            )
        }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), {
            BackgroundColor3 = p.BackgroundColor3
        }):Play()
    end)
    
    return btn
end

local function Divider(props)
    local p = props or {}
    p.BackgroundColor3 = p.BackgroundColor3 or Theme.Border
    p.BorderSizePixel = 0
    p.Size = p.Size or UDim2.new(1, 0, 0, 1)
    return Create("Frame", p)
end

local function Corner(radius)
    return Create("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

local function Padding(v, h)
    return Create("UIPadding", {
        PaddingTop = UDim.new(0, v or 6),
        PaddingBottom = UDim.new(0, v or 6),
        PaddingLeft = UDim.new(0, h or 8),
        PaddingRight = UDim.new(0, h or 8),
    })
end

-- ============================================================
-- CRIAR INTERFACE
-- ============================================================

-- ScreenGui
local ScreenGui = Create("ScreenGui", {
    Name = "RemoteSpyPro",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 9999,
})

pcall(function()
    ScreenGui.Parent = CoreGui
end)
if not ScreenGui.Parent then
    ScreenGui.Parent = LocalPlayer.PlayerGui
end

RSP.UI.ScreenGui = ScreenGui

-- Janela principal
local MainFrame = Create("Frame", {
    Name = "Main",
    Size = UDim2.new(0, 720, 0, 500),
    Position = UDim2.new(0.5, -360, 0.5, -250),
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    Parent = ScreenGui,
}, {
    Corner(10),
    Create("UIStroke", { Color = Theme.Border, Thickness = 1.5 }),
})

RSP.UI.MainFrame = MainFrame

-- Sombra
local Shadow = Create("ImageLabel", {
    Name = "Shadow",
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundTransparency = 1,
    Position = UDim2.new(0.5, 0, 0.5, 8),
    Size = UDim2.new(1, 40, 1, 40),
    ZIndex = -1,
    Image = "rbxassetid://6014261993",
    ImageColor3 = Color3.new(0, 0, 0),
    ImageTransparency = 0.5,
    ScaleType = Enum.ScaleType.Slice,
    SliceCenter = Rect.new(49, 49, 450, 450),
    Parent = MainFrame,
})

-- Header (drag bar)
local Header = Create("Frame", {
    Name = "Header",
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = Theme.Surface,
    BorderSizePixel = 0,
    Parent = MainFrame,
}, {
    Corner(10),
})

-- Corrigir cantos inferiores do header
Create("Frame", {
    Size = UDim2.new(1, 0, 0, 10),
    Position = UDim2.new(0, 0, 1, -10),
    BackgroundColor3 = Theme.Surface,
    BorderSizePixel = 0,
    Parent = Header,
})

-- Logo / Título
local TitleContainer = Create("Frame", {
    Size = UDim2.new(1, -120, 1, 0),
    BackgroundTransparency = 1,
    Parent = Header,
})

Create("Frame", {
    Name = "Dot",
    Size = UDim2.new(0, 8, 0, 8),
    Position = UDim2.new(0, 14, 0.5, -4),
    BackgroundColor3 = Theme.Accent,
    BorderSizePixel = 0,
    Parent = TitleContainer,
}, { Corner(4) })

Create("Frame", {
    Name = "Dot2",
    Size = UDim2.new(0, 8, 0, 8),
    Position = UDim2.new(0, 26, 0.5, -4),
    BackgroundColor3 = Theme.AccentDim,
    BorderSizePixel = 0,
    Parent = TitleContainer,
}, { Corner(4) })

Label("Remote Spy Pro", 14, Theme.Text, Enum.Font.GothamBold, {
    Position = UDim2.new(0, 44, 0, 0),
    Size = UDim2.new(0, 200, 1, 0),
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = TitleContainer,
})

Label("v" .. RSP.Version, 11, Theme.TextMuted, Enum.Font.Gotham, {
    Position = UDim2.new(0, 180, 0, 0),
    Size = UDim2.new(0, 60, 1, 0),
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = TitleContainer,
})

-- Botões de controle do header
local HeaderButtons = Create("Frame", {
    Size = UDim2.new(0, 110, 1, 0),
    Position = UDim2.new(1, -110, 0, 0),
    BackgroundTransparency = 1,
    Parent = Header,
})

local function HeaderBtn(text, color, xPos)
    local btn = Create("TextButton", {
        Text = text,
        TextSize = 11,
        Font = Enum.Font.GothamBold,
        TextColor3 = color,
        Size = UDim2.new(0, 30, 0, 20),
        Position = UDim2.new(0, xPos, 0.5, -10),
        BackgroundColor3 = Theme.SurfaceAlt,
        BorderSizePixel = 0,
        Parent = HeaderButtons,
    }, { Corner(5) })
    return btn
end

local MinBtn = HeaderBtn("—", Theme.TextDim, 8)
local ToggleBtn = HeaderBtn("●", Theme.Success, 42)
local CloseBtn = HeaderBtn("✕", Theme.Error, 76)

-- Toggle visibilidade
local minimized = false
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    local targetSize = minimized and UDim2.new(0, 720, 0, 40) or UDim2.new(0, 720, 0, 500)
    TweenService:Create(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {
        Size = targetSize
    }):Play()
end)

-- Toggle espionagem
ToggleBtn.MouseButton1Click:Connect(function()
    RSP.Enabled = not RSP.Enabled
    ToggleBtn.TextColor3 = RSP.Enabled and Theme.Success or Theme.Error
    ToggleBtn.Text = RSP.Enabled and "●" or "○"
end)

CloseBtn.MouseButton1Click:Connect(function()
    TweenService:Create(MainFrame, TweenInfo.new(0.2), { Size = UDim2.new(0, 0, 0, 0) }):Play()
    task.delay(0.25, function()
        ScreenGui:Destroy()
    end)
end)

-- ============================================================
-- ABAS
-- ============================================================

local TabBar = Create("Frame", {
    Name = "TabBar",
    Size = UDim2.new(1, 0, 0, 34),
    Position = UDim2.new(0, 0, 0, 40),
    BackgroundColor3 = Theme.Surface,
    BorderSizePixel = 0,
    Parent = MainFrame,
}, {
    Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 2),
    }),
    Padding(0, 6),
})

local tabIndicator = Create("Frame", {
    Name = "Indicator",
    Size = UDim2.new(0, 60, 0, 2),
    Position = UDim2.new(0, 6, 1, -2),
    BackgroundColor3 = Theme.Accent,
    BorderSizePixel = 0,
    Parent = TabBar,
}, { Corner(2) })

local tabs = {}
local tabFrames = {}

local function createTab(name, icon, order)
    local btn = Create("TextButton", {
        Text = icon .. " " .. name,
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        TextColor3 = Theme.TextDim,
        Size = UDim2.new(0, 90, 1, -4),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = order,
        Parent = TabBar,
    })
    tabs[name] = btn
    return btn
end

local LogsTabBtn = createTab("Logs", "📋", 1)
local RemotesTabBtn = createTab("Remotes", "📡", 2)
local BlockedTabBtn = createTab("Blocked", "🚫", 3)
local SettingsTabBtn = createTab("Config", "⚙", 4)

-- Conteúdo principal
local ContentArea = Create("Frame", {
    Name = "Content",
    Size = UDim2.new(1, 0, 1, -74),
    Position = UDim2.new(0, 0, 0, 74),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
    Parent = MainFrame,
})

local function createTabFrame(name)
    local frame = Create("Frame", {
        Name = name,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = ContentArea,
    })
    tabFrames[name] = frame
    return frame
end

local LogsFrame = createTabFrame("Logs")
local RemotesFrame = createTabFrame("Remotes")
local BlockedFrame = createTabFrame("Blocked")
local SettingsFrame = createTabFrame("Settings")

local function switchTab(name)
    RSP.CurrentTab = name
    for tabName, frame in pairs(tabFrames) do
        frame.Visible = tabName == name
    end
    for tabName, btn in pairs(tabs) do
        btn.TextColor3 = tabName == name and Theme.Accent or Theme.TextDim
    end
end

LogsTabBtn.MouseButton1Click:Connect(function() switchTab("Logs") end)
RemotesTabBtn.MouseButton1Click:Connect(function() switchTab("Remotes") end)
BlockedTabBtn.MouseButton1Click:Connect(function() switchTab("Blocked") end)
SettingsTabBtn.MouseButton1Click:Connect(function() switchTab("Settings") end)

-- ============================================================
-- ABA: LOGS
-- ============================================================

-- Barra de ferramentas de logs
local LogsToolbar = Create("Frame", {
    Size = UDim2.new(1, 0, 0, 36),
    BackgroundColor3 = Theme.Surface,
    BorderSizePixel = 0,
    Parent = LogsFrame,
}, {
    Padding(4, 8),
    Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 6),
    }),
})

-- Campo de busca
local SearchBox = Create("TextBox", {
    PlaceholderText = "🔍  Filtrar por nome...",
    PlaceholderColor3 = Theme.TextMuted,
    Text = "",
    TextSize = 12,
    Font = Enum.Font.Gotham,
    TextColor3 = Theme.Text,
    Size = UDim2.new(0, 200, 0, 26),
    BackgroundColor3 = Theme.SurfaceAlt,
    BorderSizePixel = 0,
    TextXAlignment = Enum.TextXAlignment.Left,
    ClearTextOnFocus = false,
    Parent = LogsToolbar,
}, {
    Corner(6),
    Padding(0, 8),
    Create("UIStroke", { Color = Theme.Border, Thickness = 1 }),
})

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    RSP.Filter = SearchBox.Text:lower()
end)

-- Botão limpar
local ClearBtn = Button("🗑 Limpar", 11, {
    Size = UDim2.new(0, 75, 0, 26),
    BackgroundColor3 = Theme.SurfaceAlt,
    Parent = LogsToolbar,
}, { Corner(6) })

ClearBtn.MouseButton1Click:Connect(function()
    RSP.Logs = {}
    RSP.Stats = {}
end)

-- Status
local LogCountLabel = Label("0 logs", 11, Theme.TextMuted, Enum.Font.Gotham, {
    Size = UDim2.new(0, 80, 0, 26),
    TextXAlignment = Enum.TextXAlignment.Right,
    Parent = LogsToolbar,
})

-- Separador
Divider({ Position = UDim2.new(0, 0, 0, 36), Parent = LogsFrame })

-- Painel principal de logs (esquerda) + detalhes (direita)
local LogSplit = Create("Frame", {
    Size = UDim2.new(1, 0, 1, -37),
    Position = UDim2.new(0, 0, 0, 37),
    BackgroundTransparency = 1,
    Parent = LogsFrame,
})

-- Lista de logs
local LogListContainer = Create("Frame", {
    Size = UDim2.new(0, 430, 1, 0),
    BackgroundTransparency = 1,
    Parent = LogSplit,
})

local LogScrollFrame = Create("ScrollingFrame", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = Theme.Border,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Parent = LogListContainer,
})

local LogList = Create("Frame", {
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    Parent = LogScrollFrame,
}, {
    Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 1),
    }),
})

-- Separador vertical
Divider({
    Size = UDim2.new(0, 1, 1, 0),
    Position = UDim2.new(0, 430, 0, 0),
    Parent = LogSplit,
})

-- Painel de detalhes
local DetailPanel = Create("Frame", {
    Size = UDim2.new(1, -431, 1, 0),
    Position = UDim2.new(0, 431, 0, 0),
    BackgroundTransparency = 1,
    Parent = LogSplit,
})

local DetailScroll = Create("ScrollingFrame", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = Theme.Border,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Parent = DetailPanel,
})

local DetailContent = Create("Frame", {
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    Parent = DetailScroll,
}, {
    Padding(8, 10),
    Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
    }),
})

local function clearDetail()
    for _, child in ipairs(DetailContent:GetChildren()) do
        if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
            child:Destroy()
        end
    end
end

local function DetailRow(key, value, color, order)
    local row = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = order or 0,
        Parent = DetailContent,
    })
    Label(key, 10, Theme.TextMuted, Enum.Font.GothamBold, {
        Size = UDim2.new(1, 0, 0, 16),
        Parent = row,
    })
    Label(value, 11, color or Theme.Text, Enum.Font.Code, {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Position = UDim2.new(0, 0, 0, 16),
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })
    return row
end

local function showLogDetail(log)
    clearDetail()
    RSP.SelectedLog = log
    
    -- Header do detail
    local typeColor = typeColor(log.type)
    
    -- Tipo + direção
    local headerRow = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = Theme.SurfaceAlt,
        BorderSizePixel = 0,
        LayoutOrder = 0,
        Parent = DetailContent,
    }, {
        Corner(6),
        Padding(6, 10),
    })
    
    Label(log.type, 13, typeColor, Enum.Font.GothamBold, {
        Size = UDim2.new(0.5, 0, 1, 0),
        Parent = headerRow,
    })
    Label(log.direction or "", 11, Theme.TextMuted, Enum.Font.Gotham, {
        Size = UDim2.new(0.5, 0, 1, 0),
        Position = UDim2.new(0.5, 0, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = headerRow,
    })
    
    -- Informações
    DetailRow("⏰ Timestamp", log.timestamp or "?", Theme.TextDim, 1)
    DetailRow("📡 Remote", log.remoteName or "?", Theme.Accent, 2)
    DetailRow("📁 Path", log.remotePath or "?", Theme.TextDim, 3)
    DetailRow("🔷 Tipo", log.remoteType or "?", typeColor, 4)
    
    if log.callerScript then
        DetailRow("📜 Script", log.callerScript, Theme.Warning, 5)
    end
    if log.callerLine then
        DetailRow("📍 Linha", tostring(log.callerLine), Theme.Warning, 6)
    end
    
    if log.blocked then
        DetailRow("🚫 Status", "BLOQUEADO", Theme.Error, 7)
    end
    
    -- Args
    local argsRow = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 8,
        Parent = DetailContent,
    })
    
    Label("📦 Argumentos", 10, Theme.TextMuted, Enum.Font.GothamBold, {
        Size = UDim2.new(1, 0, 0, 16),
        Parent = argsRow,
    })
    
    if log.args and #log.args > 0 then
        for i, arg in ipairs(log.args) do
            if i > RSP.Settings.MaxArgs then break end
            local argBg = Create("Frame", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Theme.SurfaceAlt,
                BorderSizePixel = 0,
                LayoutOrder = i,
                Parent = argsRow,
            }, {
                Corner(4),
                Padding(4, 8),
            })
            
            local argType = typeof(arg)
            Label(string.format("[%d] %s", i, argType), 9, Theme.TextMuted, Enum.Font.GothamBold, {
                Size = UDim2.new(1, 0, 0, 14),
                Parent = argBg,
            })
            Label(formatValue(arg), 11, Theme.Text, Enum.Font.Code, {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                Position = UDim2.new(0, 0, 0, 14),
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = argBg,
            })
        end
    else
        Label("(sem argumentos)", 11, Theme.TextMuted, Enum.Font.Gotham, {
            Size = UDim2.new(1, 0, 0, 20),
            Position = UDim2.new(0, 0, 0, 16),
            Parent = argsRow,
        })
    end
    
    -- Botões de ação
    local ActionsRow = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 60),
        BackgroundTransparency = 1,
        LayoutOrder = 9,
        Parent = DetailContent,
    }, {
        Create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 6),
            VerticalAlignment = Enum.VerticalAlignment.Center,
        }),
    })
    
    -- Copiar script
    local CopyScriptBtn = Button("📋 Copiar Script", 11, {
        Size = UDim2.new(0, 120, 0, 28),
        BackgroundColor3 = Theme.AccentDim,
        TextColor3 = Theme.Text,
        Parent = ActionsRow,
    }, { Corner(6) })
    
    CopyScriptBtn.MouseButton1Click:Connect(function()
        local path = log.remotePath or log.remoteName
        local code
        if log.type == "FireServer" then
            code = string.format(
                '-- RemoteSpy Pro - %s\nlocal remote = game:GetService("ReplicatedStorage"):FindFirstChild("%s", true)\nif remote then\n    remote:FireServer(%s)\nend',
                log.timestamp, log.remoteName, argsToLua(log.args)
            )
        elseif log.type == "InvokeServer" then
            code = string.format(
                '-- RemoteSpy Pro - %s\nlocal remote = game:GetService("ReplicatedStorage"):FindFirstChild("%s", true)\nif remote then\n    local result = remote:InvokeServer(%s)\nend',
                log.timestamp, log.remoteName, argsToLua(log.args)
            )
        else
            code = string.format(
                '-- RemoteSpy Pro - %s [%s]\n-- Path: %s\n-- Args: %s',
                log.timestamp, log.type, path, log.argsFormatted
            )
        end
        
        if setclipboard then
            setclipboard(code)
            CopyScriptBtn.Text = "✅ Copiado!"
            task.delay(1.5, function()
                CopyScriptBtn.Text = "📋 Copiar Script"
            end)
        end
    end)
    
    -- Bloquear/desbloquear
    local path = log.remotePath
    local isBlocked = RSP.Blocked[path]
    local BlockToggleBtn = Button(isBlocked and "✅ Desbloquear" or "🚫 Bloquear", 11, {
        Size = UDim2.new(0, 110, 0, 28),
        BackgroundColor3 = isBlocked and Theme.Success or Theme.Error,
        TextColor3 = Theme.Text,
        Parent = ActionsRow,
    }, { Corner(6) })
    
    BlockToggleBtn.MouseButton1Click:Connect(function()
        if RSP.Blocked[path] then
            RSP.Blocked[path] = nil
            BlockToggleBtn.Text = "🚫 Bloquear"
            BlockToggleBtn.BackgroundColor3 = Theme.Error
        else
            RSP.Blocked[path] = true
            BlockToggleBtn.Text = "✅ Desbloquear"
            BlockToggleBtn.BackgroundColor3 = Theme.Success
        end
    end)
end

-- ============================================================
-- RENDERIZAÇÃO DOS LOGS
-- ============================================================

local logEntries = {}
local lastLogCount = 0

local function createLogEntry(log)
    local color = typeColor(log.type)
    
    local entry = Create("TextButton", {
        Name = "Log_" .. log.id,
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = log.id,
        Parent = LogList,
    })
    
    -- Borda esquerda colorida
    Create("Frame", {
        Size = UDim2.new(0, 3, 1, 0),
        BackgroundColor3 = log.blocked and Theme.Error or color,
        BorderSizePixel = 0,
        Parent = entry,
    }, { Corner(2) })
    
    -- Tag de tipo
    local tag = Create("Frame", {
        Size = UDim2.new(0, 90, 0, 18),
        Position = UDim2.new(0, 10, 0.5, -9),
        BackgroundColor3 = Color3.new(color.R * 0.2, color.G * 0.2, color.B * 0.2),
        BorderSizePixel = 0,
        Parent = entry,
    }, {
        Corner(4),
        Label(log.type, 10, color, Enum.Font.GothamBold, {
            Size = UDim2.new(1, 0, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Center,
        })
    })
    
    -- Nome do remote
    Label(log.remoteName or "?", 12, Theme.Text, Enum.Font.GothamBold, {
        Size = UDim2.new(1, -280, 1, 0),
        Position = UDim2.new(0, 108, 0, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = entry,
    })
    
    -- Timestamp
    Label(log.timestamp or "", 10, Theme.TextMuted, Enum.Font.Gotham, {
        Size = UDim2.new(0, 60, 1, 0),
        Position = UDim2.new(1, -68, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = entry,
    })
    
    -- Ícone de bloqueado
    if log.blocked then
        Label("🚫", 12, Theme.Error, Enum.Font.Gotham, {
            Size = UDim2.new(0, 20, 1, 0),
            Position = UDim2.new(1, -88, 0, 0),
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = entry,
        })
    end
    
    entry.MouseButton1Click:Connect(function()
        -- Destacar selecionado
        for _, e in ipairs(LogList:GetChildren()) do
            if e:IsA("TextButton") then
                e.BackgroundColor3 = Theme.Surface
            end
        end
        entry.BackgroundColor3 = Theme.SurfaceAlt
        showLogDetail(log)
    end)
    
    entry.MouseEnter:Connect(function()
        if RSP.SelectedLog ~= log then
            TweenService:Create(entry, TweenInfo.new(0.1), {
                BackgroundColor3 = Color3.new(
                    Theme.Surface.R + 0.04,
                    Theme.Surface.G + 0.04,
                    Theme.Surface.B + 0.04
                )
            }):Play()
        end
    end)
    entry.MouseLeave:Connect(function()
        if RSP.SelectedLog ~= log then
            TweenService:Create(entry, TweenInfo.new(0.1), {
                BackgroundColor3 = Theme.Surface
            }):Play()
        end
    end)
    
    return entry
end

-- Atualizar lista de logs
onNewLog(function(log)
    -- Verificar filtro
    local filter = RSP.Filter
    if filter ~= "" then
        local name = (log.remoteName or ""):lower()
        local path = (log.remotePath or ""):lower()
        if not name:find(filter, 1, true) and not path:find(filter, 1, true) then
            return
        end
    end
    
    -- Verificar configurações de tipo
    if log.type == "FireServer" and not RSP.Settings.ShowFireServer then return end
    if log.type == "InvokeServer" and not RSP.Settings.ShowInvokeServer then return end
    if log.type == "OnClientEvent" and not RSP.Settings.ShowOnClientEvent then return end
    if log.type == "OnClientInvoke" and not RSP.Settings.ShowOnClientInvoke then return end
    if (log.type == "Fire" or log.type == "Invoke") and not RSP.Settings.ShowBindables then return end
    
    -- Criar entrada
    local entry = createLogEntry(log)
    table.insert(logEntries, entry)
    
    -- Remover entradas antigas da UI se necessário
    while #logEntries > RSP.MaxLogs do
        local old = table.remove(logEntries, 1)
        if old and old.Parent then
            old:Destroy()
        end
    end
    
    -- Auto scroll
    if RSP.Settings.AutoScroll then
        task.defer(function()
            LogScrollFrame.CanvasPosition = Vector2.new(0, LogScrollFrame.AbsoluteCanvasSize.Y)
        end)
    end
    
    -- Atualizar contador
    LogCountLabel.Text = #RSP.Logs .. " logs"
end)

-- Reconstruir lista quando filtro mudar
local lastFilter = ""
RunService.Heartbeat:Connect(function()
    if RSP.Filter ~= lastFilter then
        lastFilter = RSP.Filter
        -- Limpar e recriar com filtro
        for _, child in ipairs(LogList:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end
        logEntries = {}
        
        for _, log in ipairs(RSP.Logs) do
            local filter = RSP.Filter
            if filter == "" then
                createLogEntry(log)
            else
                local name = (log.remoteName or ""):lower()
                local path = (log.remotePath or ""):lower()
                if name:find(filter, 1, true) or path:find(filter, 1, true) then
                    createLogEntry(log)
                end
            end
        end
    end
end)

-- ============================================================
-- ABA: REMOTES (lista de todos os remotes encontrados)
-- ============================================================

local RemotesList = Create("ScrollingFrame", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = Theme.Border,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Parent = RemotesFrame,
})

local RemotesListContent = Create("Frame", {
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    Parent = RemotesList,
}, {
    Create("UIListLayout", {
        SortOrder = Enum.SortOrder.Name,
        Padding = UDim.new(0, 1),
    }),
    Padding(6, 8),
})

local function refreshRemotesList()
    for _, child in ipairs(RemotesListContent:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
    
    local found = {}
    
    local function scanFor(parent)
        for _, obj in ipairs(parent:GetDescendants()) do
            local t = obj.ClassName
            if t == "RemoteEvent" or t == "RemoteFunction" or t == "BindableEvent" or t == "BindableFunction" then
                local path = getFullPath(obj)
                if not found[path] then
                    found[path] = { instance = obj, type = t, path = path }
                end
            end
        end
    end
    
    pcall(scanFor, game:GetService("ReplicatedStorage"))
    pcall(scanFor, game:GetService("ReplicatedFirst"))
    pcall(scanFor, workspace)
    pcall(scanFor, game:GetService("Players").LocalPlayer)
    
    -- Também adicionar remotes do histórico de logs
    for _, log in ipairs(RSP.Logs) do
        local path = log.remotePath
        if path and not found[path] then
            found[path] = {
                instance = log.remote,
                type = log.remoteType,
                path = path,
                name = log.remoteName,
                fromLogs = true,
            }
        end
    end
    
    local count = 0
    for path, data in pairs(found) do
        count = count + 1
        local stats = RSP.Stats[path] or { calls = 0, blocked = 0 }
        local isBlocked = RSP.Blocked[path]
        
        local colorByType = {
            RemoteEvent = Theme.FireServer,
            RemoteFunction = Theme.InvokeServer,
            BindableEvent = Theme.Fire,
            BindableFunction = Theme.Invoke,
        }
        local typeClr = colorByType[data.type] or Theme.TextDim
        
        local row = Create("Frame", {
            Name = path,
            Size = UDim2.new(1, 0, 0, 38),
            BackgroundColor3 = Theme.Surface,
            BorderSizePixel = 0,
            Parent = RemotesListContent,
        }, { Corner(6), Padding(0, 10) })
        
        Create("Frame", {
            Size = UDim2.new(0, 3, 1, 0),
            BackgroundColor3 = isBlocked and Theme.Error or typeClr,
            BorderSizePixel = 0,
            Parent = row,
        }, { Corner(2) })
        
        Label(data.name or (data.instance and data.instance.Name) or "?", 12, Theme.Text, Enum.Font.GothamBold, {
            Size = UDim2.new(0.4, 0, 1, 0),
            Position = UDim2.new(0, 10, 0, 0),
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = row,
        })
        
        Label(data.type, 10, typeClr, Enum.Font.Gotham, {
            Size = UDim2.new(0.2, 0, 1, 0),
            Position = UDim2.new(0.4, 10, 0, 0),
            Parent = row,
        })
        
        Label(string.format("📞 %d chamadas", stats.calls), 10, Theme.TextDim, Enum.Font.Gotham, {
            Size = UDim2.new(0.2, 0, 1, 0),
            Position = UDim2.new(0.6, 0, 0, 0),
            Parent = row,
        })
        
        local blockBtn = Button(isBlocked and "✅ Permitir" or "🚫 Bloquear", 10, {
            Size = UDim2.new(0, 80, 0, 22),
            Position = UDim2.new(1, -85, 0.5, -11),
            BackgroundColor3 = isBlocked and Theme.Success or Color3.fromRGB(60, 30, 30),
            TextColor3 = isBlocked and Theme.Background or Theme.Error,
            Parent = row,
        }, { Corner(5) })
        
        blockBtn.MouseButton1Click:Connect(function()
            if RSP.Blocked[path] then
                RSP.Blocked[path] = nil
                blockBtn.Text = "🚫 Bloquear"
                blockBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
                blockBtn.TextColor3 = Theme.Error
                row:FindFirstChild("Frame").BackgroundColor3 = typeClr
            else
                RSP.Blocked[path] = true
                blockBtn.Text = "✅ Permitir"
                blockBtn.BackgroundColor3 = Theme.Success
                blockBtn.TextColor3 = Theme.Background
                row:FindFirstChild("Frame").BackgroundColor3 = Theme.Error
            end
        end)
    end
    
    if count == 0 then
        Label("Nenhum remote encontrado.\nDispare alguns eventos primeiro.", 12, Theme.TextMuted, Enum.Font.Gotham, {
            Size = UDim2.new(1, 0, 0, 60),
            TextXAlignment = Enum.TextXAlignment.Center,
            TextWrapped = true,
            Parent = RemotesListContent,
        })
    end
end

-- Botão refresh remotes
local RemotesHeader = Create("Frame", {
    Size = UDim2.new(1, 0, 0, 36),
    BackgroundColor3 = Theme.Surface,
    BorderSizePixel = 0,
    Parent = RemotesFrame,
}, {
    Padding(4, 8),
    Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 6),
    }),
})

Label("Remotes detectados no jogo", 12, Theme.TextDim, Enum.Font.GothamBold, {
    Size = UDim2.new(1, -100, 0, 26),
    Parent = RemotesHeader,
})

local RefreshBtn = Button("🔄 Atualizar", 11, {
    Size = UDim2.new(0, 90, 0, 26),
    BackgroundColor3 = Theme.AccentDim,
    Parent = RemotesHeader,
}, { Corner(6) })

RefreshBtn.MouseButton1Click:Connect(function()
    refreshRemotesList()
end)

RemotesTabBtn.MouseButton1Click:Connect(function()
    refreshRemotesList()
end)

-- ============================================================
-- ABA: BLOCKED
-- ============================================================

local BlockedHeader = Create("Frame", {
    Size = UDim2.new(1, 0, 0, 36),
    BackgroundColor3 = Theme.Surface,
    BorderSizePixel = 0,
    Parent = BlockedFrame,
}, {
    Padding(4, 8),
    Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 6),
    }),
})

Label("Remotes bloqueados", 12, Theme.TextDim, Enum.Font.GothamBold, {
    Size = UDim2.new(0.5, 0, 0, 26),
    Parent = BlockedHeader,
})

local UnblockAllBtn = Button("🔓 Desbloquear Todos", 11, {
    Size = UDim2.new(0, 150, 0, 26),
    BackgroundColor3 = Color3.fromRGB(60, 40, 20),
    TextColor3 = Theme.Warning,
    Parent = BlockedHeader,
}, { Corner(6) })

UnblockAllBtn.MouseButton1Click:Connect(function()
    RSP.Blocked = {}
    refreshBlockedList()
end)

local BlockedScroll = Create("ScrollingFrame", {
    Size = UDim2.new(1, 0, 1, -37),
    Position = UDim2.new(0, 0, 0, 37),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = Theme.Border,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Parent = BlockedFrame,
})

local BlockedContent = Create("Frame", {
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    Parent = BlockedScroll,
}, {
    Create("UIListLayout", { SortOrder = Enum.SortOrder.Name, Padding = UDim.new(0, 1) }),
    Padding(6, 8),
})

function refreshBlockedList()
    for _, child in ipairs(BlockedContent:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    
    local hasAny = false
    for path, _ in pairs(RSP.Blocked) do
        hasAny = true
        local row = Create("Frame", {
            Name = path,
            Size = UDim2.new(1, 0, 0, 36),
            BackgroundColor3 = Color3.fromRGB(40, 20, 20),
            BorderSizePixel = 0,
            Parent = BlockedContent,
        }, {
            Corner(6),
            Padding(0, 10),
            Create("UIStroke", { Color = Theme.Error, Thickness = 1, Transparency = 0.7 }),
        })
        
        Label("🚫 " .. path, 11, Theme.Text, Enum.Font.Gotham, {
            Size = UDim2.new(1, -90, 1, 0),
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = row,
        })
        
        local ubBtn = Button("✅ Desbloquear", 10, {
            Size = UDim2.new(0, 85, 0, 22),
            Position = UDim2.new(1, -88, 0.5, -11),
            BackgroundColor3 = Theme.Success,
            TextColor3 = Theme.Background,
            Parent = row,
        }, { Corner(5) })
        
        ubBtn.MouseButton1Click:Connect(function()
            RSP.Blocked[path] = nil
            row:Destroy()
        end)
    end
    
    if not hasAny then
        Label("Nenhum remote bloqueado.", 12, Theme.TextMuted, Enum.Font.Gotham, {
            Size = UDim2.new(1, 0, 0, 40),
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = BlockedContent,
        })
    end
end

BlockedTabBtn.MouseButton1Click:Connect(refreshBlockedList)

-- ============================================================
-- ABA: CONFIGURAÇÕES
-- ============================================================

local SettingsScroll = Create("ScrollingFrame", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = Theme.Border,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Parent = SettingsFrame,
})

local SettingsContent = Create("Frame", {
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    Parent = SettingsScroll,
}, {
    Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
    Padding(10, 14),
})

local function SectionLabel(text, order)
    Label(text, 11, Theme.TextMuted, Enum.Font.GothamBold, {
        Size = UDim2.new(1, 0, 0, 22),
        LayoutOrder = order,
        Parent = SettingsContent,
    })
end

local function Toggle(label, settingKey, order)
    local row = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        LayoutOrder = order,
        Parent = SettingsContent,
    }, { Corner(6), Padding(0, 10) })
    
    Label(label, 12, Theme.Text, Enum.Font.Gotham, {
        Size = UDim2.new(1, -60, 1, 0),
        Parent = row,
    })
    
    local isOn = RSP.Settings[settingKey]
    
    local toggleBg = Create("Frame", {
        Size = UDim2.new(0, 40, 0, 20),
        Position = UDim2.new(1, -45, 0.5, -10),
        BackgroundColor3 = isOn and Theme.Accent or Theme.Border,
        BorderSizePixel = 0,
        Parent = row,
    }, { Corner(10) })
    
    local toggleKnob = Create("Frame", {
        Size = UDim2.new(0, 14, 0, 14),
        Position = UDim2.new(isOn and 1 or 0, isOn and -17 or 3, 0.5, -7),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Parent = toggleBg,
    }, { Corner(7) })
    
    local toggleBtn = Create("TextButton", {
        Text = "",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Parent = toggleBg,
    })
    
    toggleBtn.MouseButton1Click:Connect(function()
        RSP.Settings[settingKey] = not RSP.Settings[settingKey]
        local on = RSP.Settings[settingKey]
        TweenService:Create(toggleBg, TweenInfo.new(0.15), {
            BackgroundColor3 = on and Theme.Accent or Theme.Border
        }):Play()
        TweenService:Create(toggleKnob, TweenInfo.new(0.15), {
            Position = UDim2.new(on and 1 or 0, on and -17 or 3, 0.5, -7)
        }):Play()
    end)
    
    return row
end

SectionLabel("── Tipos de Remote ──", 1)
Toggle("FireServer (RemoteEvent → Server)", "ShowFireServer", 2)
Toggle("InvokeServer (RemoteFunction → Server)", "ShowInvokeServer", 3)
Toggle("OnClientEvent (Server → Client)", "ShowOnClientEvent", 4)
Toggle("OnClientInvoke (Server → Client)", "ShowOnClientInvoke", 5)
Toggle("Bindables (BindableEvent / BindableFunction)", "ShowBindables", 6)

SectionLabel("── Debug ──", 7)
Toggle("Registrar Script de Origem", "LogCallerScript", 8)
Toggle("Registrar Linha de Origem", "LogCallerLine", 9)

SectionLabel("── Interface ──", 10)
Toggle("Auto Scroll (rolar automático)", "AutoScroll", 11)
Toggle("Notificações", "ShowNotifications", 12)

-- Max args slider simulado
local maxArgsRow = Create("Frame", {
    Size = UDim2.new(1, 0, 0, 34),
    BackgroundColor3 = Theme.Surface,
    BorderSizePixel = 0,
    LayoutOrder = 13,
    Parent = SettingsContent,
}, { Corner(6), Padding(0, 10) })

Label("Máximo de Argumentos: " .. RSP.Settings.MaxArgs, 12, Theme.Text, Enum.Font.Gotham, {
    Name = "MaxArgsLabel",
    Size = UDim2.new(0.6, 0, 1, 0),
    Parent = maxArgsRow,
})

local decBtn = Button("−", 13, {
    Size = UDim2.new(0, 28, 0, 22),
    Position = UDim2.new(1, -65, 0.5, -11),
    BackgroundColor3 = Theme.SurfaceAlt,
    Parent = maxArgsRow,
}, { Corner(5) })

local incBtn = Button("+", 13, {
    Size = UDim2.new(0, 28, 0, 22),
    Position = UDim2.new(1, -32, 0.5, -11),
    BackgroundColor3 = Theme.AccentDim,
    Parent = maxArgsRow,
}, { Corner(5) })

decBtn.MouseButton1Click:Connect(function()
    RSP.Settings.MaxArgs = math.max(1, RSP.Settings.MaxArgs - 1)
    maxArgsRow:FindFirstChild("MaxArgsLabel").Text = "Máximo de Argumentos: " .. RSP.Settings.MaxArgs
end)
incBtn.MouseButton1Click:Connect(function()
    RSP.Settings.MaxArgs = math.min(50, RSP.Settings.MaxArgs + 1)
    maxArgsRow:FindFirstChild("MaxArgsLabel").Text = "Máximo de Argumentos: " .. RSP.Settings.MaxArgs
end)

SectionLabel("── Ações ──", 14)

-- Exportar logs
local ExportRow = Create("Frame", {
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundTransparency = 1,
    LayoutOrder = 15,
    Parent = SettingsContent,
}, {
    Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 8),
        VerticalAlignment = Enum.VerticalAlignment.Center,
    }),
})

local ExportBtn = Button("📤 Exportar Logs (JSON)", 12, {
    Size = UDim2.new(0, 190, 0, 32),
    BackgroundColor3 = Theme.AccentDim,
    Parent = ExportRow,
}, { Corner(7) })

ExportBtn.MouseButton1Click:Connect(function()
    if not setclipboard then
        return
    end
    
    local export = {}
    for _, log in ipairs(RSP.Logs) do
        table.insert(export, {
            id = log.id,
            timestamp = log.timestamp,
            type = log.type,
            remoteType = log.remoteType,
            remoteName = log.remoteName,
            remotePath = log.remotePath,
            argsFormatted = log.argsFormatted,
            blocked = log.blocked,
            callerScript = log.callerScript,
            callerLine = log.callerLine,
            direction = log.direction,
        })
    end
    
    local ok, json = pcall(HttpService.JSONEncode, HttpService, export)
    if ok then
        setclipboard(json)
        ExportBtn.Text = "✅ Copiado!"
        task.delay(2, function()
            ExportBtn.Text = "📤 Exportar Logs (JSON)"
        end)
    end
end)

local ClearAllBtn = Button("🗑 Limpar Tudo", 12, {
    Size = UDim2.new(0, 120, 0, 32),
    BackgroundColor3 = Color3.fromRGB(60, 20, 20),
    TextColor3 = Theme.Error,
    Parent = ExportRow,
}, { Corner(7) })

ClearAllBtn.MouseButton1Click:Connect(function()
    RSP.Logs = {}
    RSP.Stats = {}
    RSP.Blocked = {}
    for _, child in ipairs(LogList:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    logEntries = {}
    clearDetail()
    LogCountLabel.Text = "0 logs"
end)

-- ============================================================
-- DRAG
-- ============================================================

local dragging = false
local dragStart, startPos

Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

-- ============================================================
-- INICIALIZAÇÃO
-- ============================================================

switchTab("Logs")
setupHooks()

-- Animação de entrada
MainFrame.Size = UDim2.new(0, 0, 0, 0)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
TweenService:Create(MainFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
    Size = UDim2.new(0, 720, 0, 500),
    Position = UDim2.new(0.5, -360, 0.5, -250),
}):Play()

-- Log de inicialização
task.delay(0.5, function()
    addLog({
        type = "FireServer",
        remoteType = "Sistema",
        remoteName = "RemoteSpyPro",
        remotePath = "System.RemoteSpyPro",
        args = { "Iniciado com sucesso!", RSP.Version },
        argsFormatted = '("Iniciado com sucesso!", "' .. RSP.Version .. '")',
        blocked = false,
        direction = "⚡ Sistema",
        callerScript = nil,
        callerLine = nil,
    })
    
    print("[RemoteSpy Pro] ✅ Iniciado! Espiando remotes...")
    print("[RemoteSpy Pro] Use RSP.Enabled = false para pausar")
    print("[RemoteSpy Pro] Use RSP.Blocked['caminho'] = true para bloquear")
    print("[RemoteSpy Pro] Use RSP.Logs para acessar os logs programaticamente")
end)

-- Expor globalmente
getgenv().RSP = RSP

print([[
╔════════════════════════════════╗
║   Remote Spy Pro v2.0 Ativo    ║
║   Espionando todas as Remotes  ║
╚════════════════════════════════╝
]])