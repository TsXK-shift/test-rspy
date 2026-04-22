--[[
    Remote Spy Pro v3.0
    Compatível com: Xeno, Delta, Solara, Fluxus, KRNL, Synapse X e outros

    ESTRATÉGIA DE HOOK (em ordem de prioridade):
    1. hookfunction no protótipo do RemoteEvent/RemoteFunction (funciona no Xeno)
    2. hookmetamethod via __namecall (Synapse X, Wave, etc.)
    3. Scan de instâncias + patch individual (fallback universal)

    PERFORMANCE:
    - Renderização virtual: apenas ~16 itens visíveis renderizados por vez
    - Sem AutomaticCanvasSize (causa freeze no Delta)
    - Sem AutomaticSize em listas (causa recálculo a cada frame)
    - Batch de UI updates via task.defer
]]

-- ╔══════════════════════════════════════╗
-- ║       DETECÇÃO DE AMBIENTE           ║
-- ╚══════════════════════════════════════╝

local ENV = {
    hookfunction      = (hookfunction or replaceclosure or nil),
    hookmetamethod    = (hookmetamethod or nil),
    newcclosure       = (newcclosure or function(f) return f end),
    getnamecallmethod = (getnamecallmethod or nil),
    checkcaller       = (checkcaller or function() return false end),
    setclipboard      = (setclipboard or toclipboard or rbxtheclip or nil),
    getrawmetatable   = (getrawmetatable or nil),
    isexecutorclosure = (isexecutorclosure or function() return false end),
    cloneref          = (cloneref or function(x) return x end),
    Name = (identifyexecutor and identifyexecutor())
        or (getexecutorname and getexecutorname())
        or "Unknown",
}

ENV.CanHookFunction = ENV.hookfunction ~= nil
ENV.CanHookMeta     = ENV.hookmetamethod ~= nil and ENV.getnamecallmethod ~= nil
ENV.CanCopy         = ENV.setclipboard ~= nil

print(string.format("[RSP] Executor: %s | hookfunction: %s | hookmetamethod: %s",
    ENV.Name, tostring(ENV.CanHookFunction), tostring(ENV.CanHookMeta)))

-- ╔══════════════════════════════════════╗
-- ║            SERVIÇOS                  ║
-- ╚══════════════════════════════════════╝

local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")
local CoreGui          = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local HttpService      = game:GetService("HttpService")
local LocalPlayer      = Players.LocalPlayer

-- ╔══════════════════════════════════════╗
-- ║         ESTADO GLOBAL                ║
-- ╚══════════════════════════════════════╝

local RSP = {
    Version   = "3.0",
    Enabled   = true,
    Logs      = {},
    Blocked   = {},
    Stats     = {},
    MaxLogs   = 300,
    Filter    = "",
    Settings  = {
        FireServer     = true,
        InvokeServer   = true,
        OnClientEvent  = true,
        OnClientInvoke = true,
        Bindables      = true,
        AutoScroll     = true,
        MaxArgs        = 8,
    },
    UI        = {},
    _logCBs   = {},
    _originals= {},
    _patched  = {},
}

getgenv().RSP = RSP

-- ╔══════════════════════════════════════╗
-- ║           UTILITÁRIOS                ║
-- ╚══════════════════════════════════════╝

local function safePath(inst)
    if not inst or typeof(inst) ~= "Instance" then return "?" end
    local ok, r = pcall(function()
        local t, o, d = {}, inst, 0
        while o and o ~= game and d < 20 do
            table.insert(t, 1, o.Name)
            o = o.Parent; d = d + 1
        end
        return table.concat(t, ".")
    end)
    return (ok and r) or tostring(inst)
end

local function fmtVal(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "string"   then
        local s = v:gsub('"','\\"'):gsub('\n','\\n')
        return string.format('"%s"', #s>60 and s:sub(1,57).."..." or s)
    elseif t == "number"  then
        return v == math.floor(v) and tostring(math.floor(v)) or string.format("%.3f",v)
    elseif t == "boolean" or t == "nil" then return tostring(v)
    elseif t == "Vector3"  then return string.format("V3(%g,%g,%g)",v.X,v.Y,v.Z)
    elseif t == "Vector2"  then return string.format("V2(%g,%g)",v.X,v.Y)
    elseif t == "CFrame"   then local p=v.Position return string.format("CF(%g,%g,%g)",p.X,p.Y,p.Z)
    elseif t == "Color3"   then return string.format("RGB(%d,%d,%d)",v.R*255,v.G*255,v.B*255)
    elseif t == "UDim2"    then return string.format("UDim2(%g,%g,%g,%g)",v.X.Scale,v.X.Offset,v.Y.Scale,v.Y.Offset)
    elseif t == "Instance" then
        local ok2, p2 = pcall(safePath, v)
        return string.format("<%s:%s>", v.ClassName, ok2 and p2 or "?")
    elseif t == "table" then
        if depth > 2 then return "{...}" end
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n = n + 1; if n > 5 then parts[n]="..."; break end
            parts[n] = tostring(k).."="..fmtVal(val, depth+1)
        end
        return n == 0 and "{}" or "{"..table.concat(parts,",").."}"
    else
        if t:find("Enum") then return tostring(v) end
        return string.format("<%s>",t)
    end
end

local function fmtArgs(args)
    if not args or #args == 0 then return "()" end
    local parts = {}
    for i = 1, math.min(#args, RSP.Settings.MaxArgs) do
        parts[i] = fmtVal(args[i])
    end
    if #args > RSP.Settings.MaxArgs then
        parts[#parts+1] = string.format("+%d", #args - RSP.Settings.MaxArgs)
    end
    return "("..table.concat(parts,", ")..")"
end

local function toLuaVal(v, d)
    d = d or 0
    local t = typeof(v)
    if t=="string"  then return string.format("%q",v) end
    if t=="number" or t=="boolean" or t=="nil" then return tostring(v) end
    if t=="Vector3" then return string.format("Vector3.new(%g,%g,%g)",v.X,v.Y,v.Z) end
    if t=="Vector2" then return string.format("Vector2.new(%g,%g)",v.X,v.Y) end
    if t=="CFrame"  then local p=v.Position return string.format("CFrame.new(%g,%g,%g)",p.X,p.Y,p.Z) end
    if t=="Color3"  then return string.format("Color3.fromRGB(%d,%d,%d)",v.R*255,v.G*255,v.B*255) end
    if t=="Instance" then return string.format('game:GetService("ReplicatedStorage") --[[%s]]',safePath(v)) end
    if t=="table" and d < 2 then
        local parts = {}
        for k,val in pairs(v) do parts[#parts+1]=string.format("[%q]=%s",tostring(k),toLuaVal(val,d+1)) end
        return "{"..table.concat(parts,",").."}"
    end
    return "nil"
end

local function buildScript(log)
    local args = {}
    for _, v in ipairs(log.args or {}) do args[#args+1] = toLuaVal(v) end
    local argStr = table.concat(args, ", ")
    local rPath  = string.format('game:GetService("ReplicatedStorage"):FindFirstChild("%s",true)', log.remoteName or "?")
    if log.type == "FireServer" then
        return string.format('-- [RSP] %s\nlocal r=%s\nif r then r:FireServer(%s) end', log.timestamp, rPath, argStr)
    elseif log.type == "InvokeServer" then
        return string.format('-- [RSP] %s\nlocal r=%s\nif r then local res=r:InvokeServer(%s) end', log.timestamp, rPath, argStr)
    end
    return string.format('-- [RSP] %s [%s]\n-- Path: %s\n-- Args: %s', log.timestamp, log.type, log.remotePath, log.argsFormatted)
end

-- ╔══════════════════════════════════════╗
-- ║          SISTEMA DE LOG              ║
-- ╚══════════════════════════════════════╝

local function addLog(data)
    if not RSP.Enabled then return end
    local path = data.remotePath or "?"
    if not RSP.Stats[path] then RSP.Stats[path] = {calls=0,blocked=0} end
    RSP.Stats[path].calls = RSP.Stats[path].calls + 1
    if data.blocked then RSP.Stats[path].blocked = RSP.Stats[path].blocked + 1 end
    data.id          = #RSP.Logs + 1
    data.timestamp   = os.date("%H:%M:%S")
    data.argsFormatted = fmtArgs(data.args)
    table.insert(RSP.Logs, data)
    if #RSP.Logs > RSP.MaxLogs then table.remove(RSP.Logs, 1) end
    for _, cb in ipairs(RSP._logCBs) do pcall(cb, data) end
end

local function onLog(cb) table.insert(RSP._logCBs, cb) end

-- ╔══════════════════════════════════════╗
-- ║        HOOK ENGINE                   ║
-- ╚══════════════════════════════════════╝

local function getCallerSafe()
    local src, line = nil, nil
    pcall(function()
        for i = 4, 8 do
            local info = debug.info(i, "sln")
            if info then
                local s = info[1] or ""
                if s ~= "" and not s:lower():find("remotespypro") and not s:lower():find("executor") then
                    src = s; line = info[2]; break
                end
            end
        end
    end)
    return src, line
end

-- Hookar OnClientEvent em todas as RemoteEvents encontradas
local function hookClientEvents()
    local function hookRE(obj)
        if typeof(obj) ~= "Instance" then return end
        local ok, isRE = pcall(function() return obj:IsA("RemoteEvent") end)
        if not ok or not isRE then return end
        local key = tostring(obj) .. "_client"
        if RSP._patched[key] then return end
        RSP._patched[key] = true
        pcall(function()
            obj.OnClientEvent:Connect(function(...)
                if not RSP.Enabled or not RSP.Settings.OnClientEvent then return end
                addLog({ type="OnClientEvent", remoteType="RemoteEvent",
                    remoteName=obj.Name, remotePath=safePath(obj),
                    remote=obj, args={...}, blocked=false, direction="← Client" })
            end)
        end)
    end
    task.spawn(function()
        pcall(function()
            for _, obj in ipairs(game:GetDescendants()) do hookRE(obj) end
        end)
        game.DescendantAdded:Connect(function(obj) task.defer(hookRE, obj) end)
    end)
end

-- ── MÉTODO 1: hookfunction no protótipo (Xeno, KRNL, Fluxus, Solara) ──
local function setupHookFunction()
    print("[RSP] Usando hookfunction no protótipo...")

    local tRE = Instance.new("RemoteEvent")
    local tRF = Instance.new("RemoteFunction")
    local tBE = Instance.new("BindableEvent")
    local tBF = Instance.new("BindableFunction")

    local orig_FS = tRE.FireServer
    local orig_IS = tRF.InvokeServer
    local orig_FBE= tBE.Fire
    local orig_IBF= tBF.Invoke

    tRE:Destroy(); tRF:Destroy(); tBE:Destroy(); tBF:Destroy()

    RSP._originals.FireServer   = orig_FS
    RSP._originals.InvokeServer = orig_IS

    local results = {}

    results[1] = pcall(function()
        ENV.hookfunction(orig_FS, ENV.newcclosure(function(self, ...)
            if ENV.checkcaller() then return orig_FS(self, ...) end
            if not RSP.Settings.FireServer then return orig_FS(self, ...) end
            local args = {...}
            local path = safePath(self)
            local blocked = RSP.Blocked[path]
            local src, ln = getCallerSafe()
            addLog({ type="FireServer", remoteType="RemoteEvent",
                remoteName=self.Name, remotePath=path,
                remote=self, args=args, blocked=blocked,
                callerScript=src, callerLine=ln, direction="→ Server" })
            if blocked then return end
            return orig_FS(self, ...)
        end))
    end)

    results[2] = pcall(function()
        ENV.hookfunction(orig_IS, ENV.newcclosure(function(self, ...)
            if ENV.checkcaller() then return orig_IS(self, ...) end
            if not RSP.Settings.InvokeServer then return orig_IS(self, ...) end
            local args = {...}
            local path = safePath(self)
            local blocked = RSP.Blocked[path]
            local src, ln = getCallerSafe()
            addLog({ type="InvokeServer", remoteType="RemoteFunction",
                remoteName=self.Name, remotePath=path,
                remote=self, args=args, blocked=blocked,
                callerScript=src, callerLine=ln, direction="→ Server" })
            if blocked then return nil end
            return orig_IS(self, ...)
        end))
    end)

    results[3] = pcall(function()
        ENV.hookfunction(orig_FBE, ENV.newcclosure(function(self, ...)
            if ENV.checkcaller() then return orig_FBE(self, ...) end
            if not RSP.Settings.Bindables then return orig_FBE(self, ...) end
            local args = {...}
            local path = safePath(self)
            addLog({ type="Fire", remoteType="BindableEvent",
                remoteName=self.Name, remotePath=path,
                remote=self, args=args, blocked=RSP.Blocked[path], direction="→ Bind" })
            if RSP.Blocked[path] then return end
            return orig_FBE(self, ...)
        end))
    end)

    results[4] = pcall(function()
        ENV.hookfunction(orig_IBF, ENV.newcclosure(function(self, ...)
            if ENV.checkcaller() then return orig_IBF(self, ...) end
            if not RSP.Settings.Bindables then return orig_IBF(self, ...) end
            local args = {...}
            local path = safePath(self)
            addLog({ type="Invoke", remoteType="BindableFunction",
                remoteName=self.Name, remotePath=path,
                remote=self, args=args, blocked=RSP.Blocked[path], direction="→ Bind" })
            if RSP.Blocked[path] then return nil end
            return orig_IBF(self, ...)
        end))
    end)

    for i, ok in ipairs(results) do
        print(string.format("[RSP] hookfunction[%d]: %s", i, tostring(ok)))
    end

    hookClientEvents()
    return results[1] or results[2]
end

-- ── MÉTODO 2: hookmetamethod __namecall (Synapse X, Wave) ──
local function setupNamecallHook()
    print("[RSP] Usando hookmetamethod __namecall...")
    local gameMeta = ENV.getrawmetatable(game)
    local oldNC    = gameMeta.__namecall
    RSP._originals.__namecall = oldNC
    local ok = pcall(ENV.hookmetamethod, game, "__namecall", ENV.newcclosure(function(self, ...)
        local method = ENV.getnamecallmethod()
        if ENV.checkcaller() or not RSP.Enabled then return oldNC(self, ...) end
        local t = typeof(self)=="Instance" and self.ClassName or ""
        if t=="RemoteEvent" and method=="FireServer" and RSP.Settings.FireServer then
            local args, path = {...}, safePath(self)
            local blocked = RSP.Blocked[path]
            local src, ln = getCallerSafe()
            addLog({ type="FireServer", remoteType="RemoteEvent",
                remoteName=self.Name, remotePath=path, remote=self,
                args=args, blocked=blocked, callerScript=src, callerLine=ln, direction="→ Server" })
            if blocked then return end
            return oldNC(self, ...)
        end
        if t=="RemoteFunction" and method=="InvokeServer" and RSP.Settings.InvokeServer then
            local args, path = {...}, safePath(self)
            local blocked = RSP.Blocked[path]
            local src, ln = getCallerSafe()
            addLog({ type="InvokeServer", remoteType="RemoteFunction",
                remoteName=self.Name, remotePath=path, remote=self,
                args=args, blocked=blocked, callerScript=src, callerLine=ln, direction="→ Server" })
            if blocked then return nil end
            return oldNC(self, ...)
        end
        if t=="BindableEvent" and method=="Fire" and RSP.Settings.Bindables then
            local args, path = {...}, safePath(self)
            addLog({ type="Fire", remoteType="BindableEvent",
                remoteName=self.Name, remotePath=path, remote=self,
                args=args, blocked=RSP.Blocked[path], direction="→ Bind" })
            if RSP.Blocked[path] then return end
            return oldNC(self, ...)
        end
        if t=="BindableFunction" and method=="Invoke" and RSP.Settings.Bindables then
            local args, path = {...}, safePath(self)
            addLog({ type="Invoke", remoteType="BindableFunction",
                remoteName=self.Name, remotePath=path, remote=self,
                args=args, blocked=RSP.Blocked[path], direction="→ Bind" })
            if RSP.Blocked[path] then return nil end
            return oldNC(self, ...)
        end
        return oldNC(self, ...)
    end))
    hookClientEvents()
    return ok
end

-- ── MÉTODO 3: Fallback - patch por instância ──
local function patchInstance(obj)
    if not obj or not obj.Parent then return end
    local key = tostring(obj)
    if RSP._patched[key] then return end
    RSP._patched[key] = true
    local cls = obj.ClassName

    if cls == "RemoteEvent" then
        local origFire = obj.FireServer
        pcall(function()
            obj.FireServer = function(s, ...)
                local args, path = {...}, safePath(s)
                if RSP.Enabled and RSP.Settings.FireServer then
                    addLog({ type="FireServer", remoteType="RemoteEvent",
                        remoteName=s.Name, remotePath=path, remote=s,
                        args=args, blocked=RSP.Blocked[path], direction="→ Server" })
                    if RSP.Blocked[path] then return end
                end
                return origFire(s, ...)
            end
        end)
        pcall(function()
            obj.OnClientEvent:Connect(function(...)
                if not RSP.Enabled or not RSP.Settings.OnClientEvent then return end
                addLog({ type="OnClientEvent", remoteType="RemoteEvent",
                    remoteName=obj.Name, remotePath=safePath(obj),
                    remote=obj, args={...}, blocked=false, direction="← Client" })
            end)
        end)

    elseif cls == "RemoteFunction" then
        local origInv = obj.InvokeServer
        pcall(function()
            obj.InvokeServer = function(s, ...)
                local args, path = {...}, safePath(s)
                if RSP.Enabled and RSP.Settings.InvokeServer then
                    addLog({ type="InvokeServer", remoteType="RemoteFunction",
                        remoteName=s.Name, remotePath=path, remote=s,
                        args=args, blocked=RSP.Blocked[path], direction="→ Server" })
                    if RSP.Blocked[path] then return nil end
                end
                return origInv(s, ...)
            end
        end)

    elseif cls == "BindableEvent" and RSP.Settings.Bindables then
        local origFire = obj.Fire
        pcall(function()
            obj.Fire = function(s, ...)
                local args, path = {...}, safePath(s)
                if RSP.Enabled then
                    addLog({ type="Fire", remoteType="BindableEvent",
                        remoteName=s.Name, remotePath=path, remote=s,
                        args=args, blocked=RSP.Blocked[path], direction="→ Bind" })
                    if RSP.Blocked[path] then return end
                end
                return origFire(s, ...)
            end
        end)

    elseif cls == "BindableFunction" and RSP.Settings.Bindables then
        local origInv = obj.Invoke
        pcall(function()
            obj.Invoke = function(s, ...)
                local args, path = {...}, safePath(s)
                if RSP.Enabled then
                    addLog({ type="Invoke", remoteType="BindableFunction",
                        remoteName=s.Name, remotePath=path, remote=s,
                        args=args, blocked=RSP.Blocked[path], direction="→ Bind" })
                    if RSP.Blocked[path] then return nil end
                end
                return origInv(s, ...)
            end
        end)
    end
end

local function setupFallback()
    print("[RSP] Usando fallback: patch por instância...")
    local function scan(p)
        pcall(function()
            for _, obj in ipairs(p:GetDescendants()) do
                local c = obj.ClassName
                if c=="RemoteEvent" or c=="RemoteFunction"
                or c=="BindableEvent" or c=="BindableFunction" then
                    task.defer(patchInstance, obj)
                end
            end
        end)
    end
    scan(game)
    game.DescendantAdded:Connect(function(obj) task.defer(patchInstance, obj) end)
end

-- Escolher melhor método
local hookMode = "fallback"
local function initHooks()
    local ok = false
    if ENV.CanHookFunction then
        local s = pcall(setupHookFunction)
        if s then ok=true; hookMode="hookfunction" end
    end
    if not ok and ENV.CanHookMeta then
        local s = pcall(setupNamecallHook)
        if s then ok=true; hookMode="__namecall" end
    end
    if not ok then
        pcall(setupFallback)
        hookMode = "fallback"
    end
    print(string.format("[RSP] ✅ Hook ativo: %s", hookMode))
end

-- ╔══════════════════════════════════════╗
-- ║          INTERFACE GRÁFICA           ║
-- ╚══════════════════════════════════════╝

-- Limpar UI antiga
pcall(function() CoreGui:FindFirstChild("RSP_Pro"):Destroy() end)
pcall(function() LocalPlayer.PlayerGui:FindFirstChild("RSP_Pro"):Destroy() end)

local C = {
    BG      = Color3.fromRGB(13,13,18),
    Surface = Color3.fromRGB(20,20,28),
    Panel   = Color3.fromRGB(26,26,36),
    Border  = Color3.fromRGB(42,42,58),
    Accent  = Color3.fromRGB(90,170,255),
    AccentD = Color3.fromRGB(55,110,200),
    Success = Color3.fromRGB(72,210,110),
    Warning = Color3.fromRGB(255,185,55),
    Error   = Color3.fromRGB(255,72,72),
    Text    = Color3.fromRGB(215,215,230),
    TextD   = Color3.fromRGB(130,130,155),
    TextM   = Color3.fromRGB(68,68,90),
    FireServer    = Color3.fromRGB(90,170,255),
    InvokeServer  = Color3.fromRGB(175,115,255),
    OnClientEvent = Color3.fromRGB(72,210,130),
    OnClientInvoke= Color3.fromRGB(130,255,160),
    Fire          = Color3.fromRGB(255,160,55),
    Invoke        = Color3.fromRGB(255,115,75),
}
local function typeClr(t) return C[t] or C.TextD end

-- Helpers de criação
local function N(cn, p, ch)
    local i = Instance.new(cn)
    for k,v in pairs(p or {}) do if k~="Parent" then pcall(function() i[k]=v end) end end
    for _,c in ipairs(ch or {}) do if c then c.Parent=i end end
    if p and p.Parent then i.Parent=p.Parent end
    return i
end
local function Lbl(txt,sz,col,fnt,p)
    local pr=p or {}
    pr.Text=txt; pr.TextSize=sz or 13; pr.TextColor3=col or C.Text
    pr.Font=fnt or Enum.Font.Gotham
    pr.BackgroundTransparency=pr.BackgroundTransparency~=nil and pr.BackgroundTransparency or 1
    pr.TextXAlignment=pr.TextXAlignment or Enum.TextXAlignment.Left
    return N("TextLabel",pr)
end
local function Btn(txt,sz,p,ch)
    local pr=p or {}
    pr.Text=txt; pr.TextSize=sz or 12
    pr.Font=pr.Font or Enum.Font.GothamBold
    pr.TextColor3=pr.TextColor3 or C.Text
    pr.BackgroundColor3=pr.BackgroundColor3 or C.Panel
    pr.BorderSizePixel=0; pr.AutoButtonColor=false
    local b=N("TextButton",pr,ch)
    local origBG=b.BackgroundColor3
    b.MouseEnter:Connect(function()
        b.BackgroundColor3=Color3.new(math.min(1,origBG.R+.07),math.min(1,origBG.G+.07),math.min(1,origBG.B+.07))
    end)
    b.MouseLeave:Connect(function() b.BackgroundColor3=origBG end)
    return b
end
local function Rnd(r) return N("UICorner",{CornerRadius=UDim.new(0,r or 6)}) end
local function Pad(v,h) return N("UIPadding",{
    PaddingTop=UDim.new(0,v or 6),PaddingBottom=UDim.new(0,v or 6),
    PaddingLeft=UDim.new(0,h or 8),PaddingRight=UDim.new(0,h or 8)}) end
local function Div(p) local pr=p or {}
    pr.BackgroundColor3=pr.BackgroundColor3 or C.Border
    pr.BorderSizePixel=0; pr.Size=pr.Size or UDim2.new(1,0,0,1)
    return N("Frame",pr) end

-- ── ScreenGui + Janela ──
local SG = N("ScreenGui",{Name="RSP_Pro",ResetOnSpawn=false,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=9999})
pcall(function() SG.Parent=CoreGui end)
if not SG.Parent then SG.Parent=LocalPlayer.PlayerGui end
RSP.UI.ScreenGui=SG

local WIN_W,WIN_H=740,490
local Win = N("Frame",{Name="Window",
    Size=UDim2.new(0,WIN_W,0,WIN_H),
    Position=UDim2.new(0.5,-WIN_W/2,0.5,-WIN_H/2),
    BackgroundColor3=C.BG,BorderSizePixel=0,ClipsDescendants=true,
    Parent=SG},{Rnd(10),N("UIStroke",{Color=C.Border,Thickness=1.5})})
RSP.UI.Win=Win

-- ── Header ──
local HDR = N("Frame",{Size=UDim2.new(1,0,0,38),BackgroundColor3=C.Surface,
    BorderSizePixel=0,Parent=Win},{Rnd(10)})
N("Frame",{Size=UDim2.new(1,0,0,12),Position=UDim2.new(0,0,1,-12),
    BackgroundColor3=C.Surface,BorderSizePixel=0,Parent=HDR})

N("Frame",{Size=UDim2.new(0,7,0,7),Position=UDim2.new(0,12,0.5,-3.5),
    BackgroundColor3=C.Accent,BorderSizePixel=0,Parent=HDR},{Rnd(4)})
N("Frame",{Size=UDim2.new(0,7,0,7),Position=UDim2.new(0,23,0.5,-3.5),
    BackgroundColor3=C.AccentD,BorderSizePixel=0,Parent=HDR},{Rnd(4)})
Lbl("Remote Spy Pro",13,C.Text,Enum.Font.GothamBold,{
    Position=UDim2.new(0,38,0,0),Size=UDim2.new(0,200,1,0),Parent=HDR})
Lbl("v"..RSP.Version,10,C.TextM,Enum.Font.Gotham,{
    Position=UDim2.new(0,168,0,0),Size=UDim2.new(0,50,1,0),Parent=HDR})
Lbl(ENV.Name,9,C.TextD,Enum.Font.Gotham,{
    Position=UDim2.new(0,218,0,0),Size=UDim2.new(0,130,1,0),Parent=HDR})

local HBtns=N("Frame",{Size=UDim2.new(0,108,1,0),Position=UDim2.new(1,-108,0,0),
    BackgroundTransparency=1,Parent=HDR})
local BtnMin    = Btn("—",10,{Size=UDim2.new(0,28,0,18),Position=UDim2.new(0,4,0.5,-9),
    BackgroundColor3=C.Panel,Parent=HBtns},{Rnd(5)})
local BtnToggle = Btn("●",10,{Size=UDim2.new(0,28,0,18),Position=UDim2.new(0,36,0.5,-9),
    BackgroundColor3=C.Panel,TextColor3=C.Success,Parent=HBtns},{Rnd(5)})
local BtnClose  = Btn("✕",10,{Size=UDim2.new(0,28,0,18),Position=UDim2.new(0,68,0.5,-9),
    BackgroundColor3=C.Panel,TextColor3=C.Error,Parent=HBtns},{Rnd(5)})

local minimized=false
BtnMin.MouseButton1Click:Connect(function()
    minimized=not minimized
    TweenService:Create(Win,TweenInfo.new(0.22,Enum.EasingStyle.Quart),{
        Size=minimized and UDim2.new(0,WIN_W,0,38) or UDim2.new(0,WIN_W,0,WIN_H)
    }):Play()
end)
BtnToggle.MouseButton1Click:Connect(function()
    RSP.Enabled=not RSP.Enabled
    BtnToggle.TextColor3=RSP.Enabled and C.Success or C.Error
    BtnToggle.Text=RSP.Enabled and "●" or "○"
end)
BtnClose.MouseButton1Click:Connect(function()
    TweenService:Create(Win,TweenInfo.new(0.18),{Size=UDim2.new(0,0,0,0)}):Play()
    task.delay(0.2,function() SG:Destroy() end)
end)

-- ── Tab Bar ──
local TABS_H=32
local TabBar=N("Frame",{Size=UDim2.new(1,0,0,TABS_H),Position=UDim2.new(0,0,0,38),
    BackgroundColor3=C.Surface,BorderSizePixel=0,Parent=Win},{
    N("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,
        VerticalAlignment=Enum.VerticalAlignment.Center,Padding=UDim.new(0,2)}),
    Pad(0,6)})

local CONTENT_Y=38+TABS_H+1
local Content=N("Frame",{Size=UDim2.new(1,0,1,-CONTENT_Y),
    Position=UDim2.new(0,0,0,CONTENT_Y),BackgroundTransparency=1,
    ClipsDescendants=true,Parent=Win})
Div({Position=UDim2.new(0,0,0,38+TABS_H),Parent=Win})

local tabFrames={} local tabBtns={}
local function mkTab(name,icon,order)
    local btn=Btn(icon.." "..name,11,{Size=UDim2.new(0,88,1,-4),
        BackgroundTransparency=1,TextColor3=C.TextD,LayoutOrder=order,Parent=TabBar})
    local frame=N("Frame",{Name=name,Size=UDim2.new(1,0,1,0),
        BackgroundTransparency=1,Visible=false,Parent=Content})
    tabFrames[name]=frame; tabBtns[name]=btn
    return btn,frame
end
local LBtn,LFrame=mkTab("Logs",  "📋",1)
local RBtn,RFrame=mkTab("Remotes","📡",2)
local BBtn,BFrame=mkTab("Block", "🚫",3)
local SBtn,SFrame=mkTab("Config","⚙", 4)

local function switchTab(name)
    RSP.CurrentTab=name
    for n,f in pairs(tabFrames) do f.Visible=n==name end
    for n,b in pairs(tabBtns) do
        b.TextColor3=n==name and C.Accent or C.TextD
        b.BackgroundTransparency=n==name and 0 or 1
        if n==name then b.BackgroundColor3=C.BG end
    end
end
for name,btn in pairs(tabBtns) do
    btn.MouseButton1Click:Connect(function() switchTab(name) end)
end

-- ════════════════════════════════════════
-- ABA LOGS — VIRTUAL SCROLL (sem freeze)
-- Apenas ~16 frames reaproveitados; canvas
-- size calculado manualmente.
-- ════════════════════════════════════════
local ITEM_H  =34
local ITEM_GAP=1
local ITEM_S  =ITEM_H+ITEM_GAP
local POOL_N  =16

-- Toolbar
local LogToolbar=N("Frame",{Size=UDim2.new(1,0,0,36),BackgroundColor3=C.Surface,
    BorderSizePixel=0,Parent=LFrame},{
    Pad(4,8),
    N("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,
        VerticalAlignment=Enum.VerticalAlignment.Center,Padding=UDim.new(0,6)})})

local SearchBox=N("TextBox",{PlaceholderText="🔍 Filtrar...",PlaceholderColor3=C.TextM,
    Text="",TextSize=12,Font=Enum.Font.Gotham,TextColor3=C.Text,
    Size=UDim2.new(0,195,0,24),BackgroundColor3=C.Panel,BorderSizePixel=0,
    TextXAlignment=Enum.TextXAlignment.Left,ClearTextOnFocus=false,
    Parent=LogToolbar},{Rnd(6),Pad(0,8),N("UIStroke",{Color=C.Border,Thickness=1})})

local ClearLogsBtn=Btn("🗑 Limpar",11,{Size=UDim2.new(0,70,0,24),
    BackgroundColor3=C.Panel,Parent=LogToolbar},{Rnd(6)})
local LogCountLbl=Lbl("0 logs",10,C.TextM,Enum.Font.Gotham,{
    Size=UDim2.new(0,70,0,24),TextXAlignment=Enum.TextXAlignment.Right,
    Parent=LogToolbar})

-- Split: lista | detalhe
local LogSplit=N("Frame",{Size=UDim2.new(1,0,1,-37),Position=UDim2.new(0,0,0,37),
    BackgroundTransparency=1,Parent=LFrame})
Div({Size=UDim2.new(1,0,0,1),Position=UDim2.new(0,0,0,0),Parent=LogSplit})

local LIST_W=415
local ListPanel=N("Frame",{Size=UDim2.new(0,LIST_W,1,0),BackgroundTransparency=1,Parent=LogSplit})

-- ScrollingFrame SEM AutomaticCanvasSize
local LogScroll=N("ScrollingFrame",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,
    BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=C.Border,
    CanvasSize=UDim2.new(0,0,0,0),Parent=ListPanel})
local LogInner=N("Frame",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Parent=LogScroll})

-- Pool de itens (reaproveitados)
local pool={}
for i=1,POOL_N do
    local item=N("Frame",{Size=UDim2.new(1,-6,0,ITEM_H),BackgroundColor3=C.Surface,
        BorderSizePixel=0,Visible=false,Parent=LogInner},{Rnd(5)})
    local bar=N("Frame",{Size=UDim2.new(0,3,1,0),BackgroundColor3=C.Accent,
        BorderSizePixel=0,Parent=item},{Rnd(2)})
    local tagBg=N("Frame",{Size=UDim2.new(0,90,0,18),Position=UDim2.new(0,9,0.5,-9),
        BackgroundColor3=C.Panel,BorderSizePixel=0,Parent=item},{Rnd(4)})
    local tagLbl=Lbl("",10,C.Accent,Enum.Font.GothamBold,{
        Size=UDim2.new(1,0,1,0),TextXAlignment=Enum.TextXAlignment.Center,Parent=tagBg})
    local nameLbl=Lbl("",12,C.Text,Enum.Font.GothamBold,{
        Size=UDim2.new(1,-278,1,0),Position=UDim2.new(0,105,0,0),
        TextTruncate=Enum.TextTruncate.AtEnd,Parent=item})
    local argsLbl=Lbl("",9,C.TextD,Enum.Font.Code,{
        Size=UDim2.new(1,-278,0,11),Position=UDim2.new(0,105,0.5,2),
        TextTruncate=Enum.TextTruncate.AtEnd,Parent=item})
    local timeLbl=Lbl("",9,C.TextM,Enum.Font.Gotham,{
        Size=UDim2.new(0,55,1,0),Position=UDim2.new(1,-58,0,0),
        TextXAlignment=Enum.TextXAlignment.Right,Parent=item})
    local clickBtn=N("TextButton",{Size=UDim2.new(1,0,1,0),
        BackgroundTransparency=1,Text="",Parent=item})
    pool[i]={frame=item,bar=bar,tagBg=tagBg,tagLbl=tagLbl,
        nameLbl=nameLbl,argsLbl=argsLbl,timeLbl=timeLbl,
        clickBtn=clickBtn,boundLog=nil}
end

-- Estado virtual
local filteredLogs={}
local selectedLog=nil

local function rebuildFiltered()
    filteredLogs={}
    local f=RSP.Filter
    for _,log in ipairs(RSP.Logs) do
        local match=f=="" or
            (log.remoteName or ""):lower():find(f,1,true) or
            (log.remotePath or ""):lower():find(f,1,true) or
            (log.type or ""):lower():find(f,1,true)
        if match then filteredLogs[#filteredLogs+1]=log end
    end
end

local showDetail  -- declarada abaixo

local function renderList()
    local total=#filteredLogs
    local canvasH=math.max(0, total*ITEM_S)
    if LogScroll.CanvasSize.Y.Offset ~= canvasH then
        LogScroll.CanvasSize=UDim2.new(0,0,0,canvasH)
    end
    local canvasY=LogScroll.CanvasPosition.Y
    local firstIdx=math.max(1,math.floor(canvasY/ITEM_S))

    for slot=1,POOL_N do
        local logIdx=firstIdx+slot-1
        local pi=pool[slot]
        if logIdx>total then
            pi.frame.Visible=false; pi.boundLog=nil
        else
            local log=filteredLogs[logIdx]
            local clr=typeClr(log.type)
            pi.boundLog=log
            pi.frame.Visible=true
            pi.frame.Position=UDim2.new(0,3,0,(logIdx-1)*ITEM_S)
            pi.bar.BackgroundColor3=log.blocked and C.Error or clr
            pi.tagBg.BackgroundColor3=Color3.new(clr.R*.18,clr.G*.18,clr.B*.18)
            pi.tagLbl.TextColor3=clr
            pi.tagLbl.Text=log.type or ""
            pi.nameLbl.Text=log.remoteName or "?"
            pi.nameLbl.TextColor3=log.blocked and C.Error or C.Text
            pi.argsLbl.Text=log.argsFormatted or ""
            pi.timeLbl.Text=log.timestamp or ""
            pi.frame.BackgroundColor3=(selectedLog==log) and C.Panel or C.Surface
        end
    end
end

LogScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(renderList)

for _,pi in ipairs(pool) do
    pi.clickBtn.MouseButton1Click:Connect(function()
        if pi.boundLog then
            selectedLog=pi.boundLog
            renderList()
            showDetail(pi.boundLog)
        end
    end)
    pi.frame.MouseEnter:Connect(function()
        if pi.boundLog and selectedLog~=pi.boundLog then
            pi.frame.BackgroundColor3=Color3.new(C.Surface.R+.04,C.Surface.G+.04,C.Surface.B+.04)
        end
    end)
    pi.frame.MouseLeave:Connect(function()
        if pi.boundLog and selectedLog~=pi.boundLog then
            pi.frame.BackgroundColor3=C.Surface
        end
    end)
end

-- ── Painel de Detalhes ──
Div({Size=UDim2.new(0,1,1,0),Position=UDim2.new(0,LIST_W,0,0),Parent=LogSplit})
local DetailPanel=N("Frame",{Size=UDim2.new(1,-LIST_W-1,1,0),
    Position=UDim2.new(0,LIST_W+1,0,0),BackgroundTransparency=1,
    ClipsDescendants=true,Parent=LogSplit})
local DScroll=N("ScrollingFrame",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,
    BorderSizePixel=0,ScrollBarThickness=3,ScrollBarImageColor3=C.Border,
    CanvasSize=UDim2.new(0,0,0,560),Parent=DetailPanel})

-- Campos fixos (só texto muda, sem recriar frames)
local D={}
do
    local function mkF(yPos,lbl)
        local row=N("Frame",{Size=UDim2.new(1,0,0,40),Position=UDim2.new(0,0,0,yPos),
            BackgroundTransparency=1,Parent=DScroll})
        Lbl(lbl,9,C.TextM,Enum.Font.GothamBold,{Size=UDim2.new(1,0,0,13),
            Position=UDim2.new(0,10,0,0),Parent=row})
        return Lbl("",11,C.Text,Enum.Font.Code,{Size=UDim2.new(1,-16,0,26),
            Position=UDim2.new(0,10,0,13),TextWrapped=true,
            TextTruncate=Enum.TextTruncate.AtEnd,Parent=row})
    end
    local typeRow=N("Frame",{Size=UDim2.new(1,0,0,30),Position=UDim2.new(0,0,0,6),
        BackgroundColor3=C.Panel,BorderSizePixel=0,Parent=DScroll},{Rnd(6),Pad(0,10)})
    D.typeTag=Lbl("",13,C.Accent,Enum.Font.GothamBold,{Size=UDim2.new(0.55,0,1,0),Parent=typeRow})
    D.dirTag =Lbl("",10,C.TextD,Enum.Font.Gotham,{Size=UDim2.new(0.45,0,1,0),
        Position=UDim2.new(0.55,0,0,0),TextXAlignment=Enum.TextXAlignment.Right,Parent=typeRow})
    D.time   =mkF(40,  "⏰ Timestamp")
    D.name   =mkF(82,  "📡 Remote")
    D.path   =mkF(124, "📁 Path")
    D.rtype  =mkF(166, "🔷 Tipo")
    D.script =mkF(208, "📜 Script Origem")
    D.line   =mkF(250, "📍 Linha")
    D.status =mkF(292, "🚫 Status")
    D.args   =mkF(334, "📦 Args preview")
    D.argsExp=N("TextLabel",{Text="",TextSize=10,Font=Enum.Font.Code,
        TextColor3=C.TextD,BackgroundColor3=C.Panel,
        Size=UDim2.new(1,-16,0,76),Position=UDim2.new(0,8,0,376),
        TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Top,Parent=DScroll},{Rnd(5),Pad(4,6)})
    D.copyBtn=Btn("📋 Copiar Script",11,{Size=UDim2.new(0,128,0,26),
        Position=UDim2.new(0,8,0,460),BackgroundColor3=C.AccentD,Parent=DScroll},{Rnd(6)})
    D.blkBtn =Btn("🚫 Bloquear",11,{Size=UDim2.new(0,100,0,26),
        Position=UDim2.new(0,142,0,460),
        BackgroundColor3=Color3.fromRGB(55,22,22),TextColor3=C.Error,
        Parent=DScroll},{Rnd(6)})
    D.cpPath =Btn("📝 Copiar Path",11,{Size=UDim2.new(0,100,0,26),
        Position=UDim2.new(0,248,0,460),BackgroundColor3=C.Panel,Parent=DScroll},{Rnd(6)})
end

-- Conexões dos botões de detalhe (reconectadas a cada seleção)
local _blkConn, _cpConn, _copyConn
showDetail = function(log)
    if not log then return end
    local clr=typeClr(log.type)
    D.typeTag.Text=log.type or "?"; D.typeTag.TextColor3=clr
    D.dirTag.Text=log.direction or ""
    D.time.Text=log.timestamp or ""
    D.name.Text=log.remoteName or ""; D.name.TextColor3=clr
    D.path.Text=log.remotePath or ""
    D.rtype.Text=log.remoteType or ""
    D.script.Text=log.callerScript or "(não disponível)"
    D.script.TextColor3=log.callerScript and C.Warning or C.TextM
    D.line.Text=log.callerLine and tostring(log.callerLine) or "-"
    D.status.Text=log.blocked and "BLOQUEADO" or "permitido"
    D.status.TextColor3=log.blocked and C.Error or C.Success
    D.args.Text=log.argsFormatted or "()"
    -- Args expandidos
    local lines={}
    for i,v in ipairs(log.args or {}) do
        if i>RSP.Settings.MaxArgs then break end
        lines[#lines+1]=string.format("[%d] (%s) %s",i,typeof(v),fmtVal(v))
    end
    D.argsExp.Text=#lines>0 and table.concat(lines,"\n") or "(sem argumentos)"
    DScroll.CanvasPosition=Vector2.new(0,0)

    -- Botão copiar script
    if _blkConn  then _blkConn:Disconnect()  end
    if _cpConn   then _cpConn:Disconnect()   end
    if _copyConn then _copyConn:Disconnect() end
    _copyConn = D.copyBtn.MouseButton1Click:Connect(function()
        if not ENV.CanCopy then D.copyBtn.Text="❌ Sem clipboard"
            task.delay(2,function() D.copyBtn.Text="📋 Copiar Script" end); return end
        ENV.setclipboard(buildScript(log))
        D.copyBtn.Text="✅ Copiado!"
        task.delay(1.5,function() D.copyBtn.Text="📋 Copiar Script" end)
    end)
    local function refBlk()
        if RSP.Blocked[log.remotePath] then
            D.blkBtn.Text="✅ Desbloquear"
            D.blkBtn.BackgroundColor3=Color3.fromRGB(20,50,25)
            D.blkBtn.TextColor3=C.Success
        else
            D.blkBtn.Text="🚫 Bloquear"
            D.blkBtn.BackgroundColor3=Color3.fromRGB(55,22,22)
            D.blkBtn.TextColor3=C.Error
        end
    end
    refBlk()
    _blkConn=D.blkBtn.MouseButton1Click:Connect(function()
        RSP.Blocked[log.remotePath]=RSP.Blocked[log.remotePath] and nil or true
        refBlk()
    end)
    _cpConn=D.cpPath.MouseButton1Click:Connect(function()
        if ENV.CanCopy then
            ENV.setclipboard(log.remotePath or "")
            D.cpPath.Text="✅ Copiado!"
            task.delay(1.5,function() D.cpPath.Text="📝 Copiar Path" end)
        end
    end)
end

-- Limpar logs
ClearLogsBtn.MouseButton1Click:Connect(function()
    RSP.Logs={}; RSP.Stats={}; filteredLogs={}; selectedLog=nil
    LogScroll.CanvasSize=UDim2.new(0,0,0,0)
    LogScroll.CanvasPosition=Vector2.new(0,0)
    for _,p in ipairs(pool) do p.frame.Visible=false; p.boundLog=nil end
    LogCountLbl.Text="0 logs"
    D.typeTag.Text=""; D.name.Text=""; D.path.Text=""
    D.args.Text=""; D.argsExp.Text=""
end)

-- Filtro
SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    RSP.Filter=SearchBox.Text:lower()
    rebuildFiltered()
    LogScroll.CanvasPosition=Vector2.new(0,0)
    renderList()
end)

-- Callback novo log
onLog(function(log)
    -- Verificar tipos habilitados
    if log.type=="FireServer"    and not RSP.Settings.FireServer    then return end
    if log.type=="InvokeServer"  and not RSP.Settings.InvokeServer  then return end
    if log.type=="OnClientEvent" and not RSP.Settings.OnClientEvent then return end
    if log.type=="OnClientInvoke"and not RSP.Settings.OnClientInvoke then return end
    if (log.type=="Fire" or log.type=="Invoke") and not RSP.Settings.Bindables then return end

    rebuildFiltered()
    LogCountLbl.Text=#filteredLogs.." logs"

    if RSP.Settings.AutoScroll then
        task.defer(function()
            local total=#filteredLogs
            local h=math.max(0,total*ITEM_S)
            LogScroll.CanvasSize=UDim2.new(0,0,0,h)
            local vis=LogScroll.AbsoluteSize.Y
            LogScroll.CanvasPosition=Vector2.new(0,math.max(0,h-vis))
            renderList()
        end)
    else
        task.defer(renderList)
    end
end)

-- ════════════════════════════════════════
-- ABA REMOTES
-- ════════════════════════════════════════
local RemHdr=N("Frame",{Size=UDim2.new(1,0,0,36),BackgroundColor3=C.Surface,
    BorderSizePixel=0,Parent=RFrame},{Pad(4,8),
    N("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,
        VerticalAlignment=Enum.VerticalAlignment.Center,Padding=UDim.new(0,6)})})
Lbl("Remotes detectados",12,C.TextD,Enum.Font.GothamBold,{
    Size=UDim2.new(1,-110,0,26),Parent=RemHdr})
local RefreshBtn=Btn("🔄 Scan",11,{Size=UDim2.new(0,100,0,26),
    BackgroundColor3=C.AccentD,Parent=RemHdr},{Rnd(6)})
Div({Position=UDim2.new(0,0,0,36),Parent=RFrame})

local RemScroll=N("ScrollingFrame",{Size=UDim2.new(1,0,1,-37),
    Position=UDim2.new(0,0,0,37),BackgroundTransparency=1,BorderSizePixel=0,
    ScrollBarThickness=4,ScrollBarImageColor3=C.Border,
    CanvasSize=UDim2.new(0,0,0,0),Parent=RFrame})
local RemContent=N("Frame",{Size=UDim2.new(1,0,0,0),BackgroundTransparency=1,
    Parent=RemScroll},{
    N("UIListLayout",{SortOrder=Enum.SortOrder.Name,Padding=UDim.new(0,2)}),
    Pad(4,6)})
local remLayout=RemContent:FindFirstChildOfClass("UIListLayout")
remLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    RemScroll.CanvasSize=UDim2.new(0,0,0,remLayout.AbsoluteContentSize.Y+16)
end)

local function refreshRemotes()
    for _,c in ipairs(RemContent:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    local found={}
    local function scan(p)
        pcall(function()
            for _,o in ipairs(p:GetDescendants()) do
                local cls=o.ClassName
                if cls=="RemoteEvent" or cls=="RemoteFunction"
                or cls=="BindableEvent" or cls=="BindableFunction" then
                    local path=safePath(o)
                    if not found[path] then found[path]={inst=o,cls=cls,name=o.Name,path=path} end
                end
            end
        end)
    end
    pcall(scan, game:GetService("ReplicatedStorage"))
    pcall(scan, game:GetService("ReplicatedFirst"))
    pcall(scan, workspace)
    pcall(scan, LocalPlayer)
    for _,log in ipairs(RSP.Logs) do
        if log.remotePath and not found[log.remotePath] then
            found[log.remotePath]={inst=log.remote,cls=log.remoteType,
                name=log.remoteName,path=log.remotePath,fromLog=true}
        end
    end
    local clrMap={RemoteEvent=C.FireServer,RemoteFunction=C.InvokeServer,
        BindableEvent=C.Fire,BindableFunction=C.Invoke}
    local count=0
    for path,data in pairs(found) do
        count=count+1
        local stats=RSP.Stats[path] or {calls=0}
        local isBlk=RSP.Blocked[path]
        local clr=clrMap[data.cls] or C.TextD
        local row=N("Frame",{Name=path,Size=UDim2.new(1,0,0,36),
            BackgroundColor3=C.Surface,BorderSizePixel=0,Parent=RemContent},{Rnd(5),Pad(0,10)})
        N("Frame",{Size=UDim2.new(0,3,1,0),BackgroundColor3=isBlk and C.Error or clr,
            BorderSizePixel=0,Parent=row},{Rnd(2)})
        Lbl(data.name or "?",12,C.Text,Enum.Font.GothamBold,{Size=UDim2.new(0.38,0,1,0),
            Position=UDim2.new(0,10,0,0),TextTruncate=Enum.TextTruncate.AtEnd,Parent=row})
        Lbl(data.cls or "",10,clr,Enum.Font.Gotham,{Size=UDim2.new(0.26,0,1,0),
            Position=UDim2.new(0.38,8,0,0),Parent=row})
        Lbl(string.format("📞 %d",stats.calls),10,C.TextD,Enum.Font.Gotham,{
            Size=UDim2.new(0.15,0,1,0),Position=UDim2.new(0.64,0,0,0),Parent=row})
        local bb=Btn(isBlk and "✅ Permitir" or "🚫 Bloquear",10,{
            Size=UDim2.new(0,80,0,22),Position=UDim2.new(1,-84,0.5,-11),
            BackgroundColor3=isBlk and Color3.fromRGB(20,50,25) or Color3.fromRGB(55,22,22),
            TextColor3=isBlk and C.Success or C.Error,Parent=row},{Rnd(5)})
        local bar=row:FindFirstChildOfClass("Frame")
        bb.MouseButton1Click:Connect(function()
            local blk=not RSP.Blocked[path]
            RSP.Blocked[path]=blk or nil
            bb.Text=blk and "✅ Permitir" or "🚫 Bloquear"
            bb.BackgroundColor3=blk and Color3.fromRGB(20,50,25) or Color3.fromRGB(55,22,22)
            bb.TextColor3=blk and C.Success or C.Error
            bar.BackgroundColor3=blk and C.Error or clr
        end)
    end
    if count==0 then
        Lbl("Nenhum remote encontrado.\nDispare eventos ou jogue um pouco primeiro.",
            12,C.TextM,Enum.Font.Gotham,{Size=UDim2.new(1,0,0,60),
            TextXAlignment=Enum.TextXAlignment.Center,TextWrapped=true,Parent=RemContent})
    end
end
RefreshBtn.MouseButton1Click:Connect(refreshRemotes)
RBtn.MouseButton1Click:Connect(refreshRemotes)

-- ════════════════════════════════════════
-- ABA BLOCK
-- ════════════════════════════════════════
local BlkHdr=N("Frame",{Size=UDim2.new(1,0,0,36),BackgroundColor3=C.Surface,
    BorderSizePixel=0,Parent=BFrame},{Pad(4,8),
    N("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,
        VerticalAlignment=Enum.VerticalAlignment.Center,Padding=UDim.new(0,6)})})
Lbl("Remotes bloqueados",12,C.TextD,Enum.Font.GothamBold,{
    Size=UDim2.new(0.5,0,0,26),Parent=BlkHdr})
local UnblockAllBtn=Btn("🔓 Desbloquear Todos",11,{Size=UDim2.new(0,155,0,26),
    BackgroundColor3=Color3.fromRGB(55,38,15),TextColor3=C.Warning,Parent=BlkHdr},{Rnd(6)})
local BlkScroll=N("ScrollingFrame",{Size=UDim2.new(1,0,1,-37),
    Position=UDim2.new(0,0,0,37),BackgroundTransparency=1,BorderSizePixel=0,
    ScrollBarThickness=4,ScrollBarImageColor3=C.Border,
    CanvasSize=UDim2.new(0,0,0,0),Parent=BFrame})
local BlkContent=N("Frame",{Size=UDim2.new(1,0,0,0),BackgroundTransparency=1,
    Parent=BlkScroll},{N("UIListLayout",{SortOrder=Enum.SortOrder.Name,Padding=UDim.new(0,2)}),
    Pad(4,6)})
local blkLayout=BlkContent:FindFirstChildOfClass("UIListLayout")
blkLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    BlkScroll.CanvasSize=UDim2.new(0,0,0,blkLayout.AbsoluteContentSize.Y+16)
end)
local function refreshBlocked()
    for _,c in ipairs(BlkContent:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    local any=false
    for path,_ in pairs(RSP.Blocked) do
        any=true
        local row=N("Frame",{Name=path,Size=UDim2.new(1,0,0,34),
            BackgroundColor3=Color3.fromRGB(35,14,14),BorderSizePixel=0,
            Parent=BlkContent},{Rnd(5),Pad(0,10),
            N("UIStroke",{Color=C.Error,Thickness=1,Transparency=0.65})})
        Lbl("🚫 "..path,11,C.Text,Enum.Font.Gotham,{Size=UDim2.new(1,-96,1,0),
            TextTruncate=Enum.TextTruncate.AtEnd,Parent=row})
        Btn("✅ Permitir",10,{Size=UDim2.new(0,82,0,22),Position=UDim2.new(1,-86,0.5,-11),
            BackgroundColor3=Color3.fromRGB(20,48,22),TextColor3=C.Success,Parent=row},{Rnd(5)})
            .MouseButton1Click:Connect(function() RSP.Blocked[path]=nil; row:Destroy() end)
    end
    if not any then Lbl("Nenhum remote bloqueado.",11,C.TextM,Enum.Font.Gotham,{
        Size=UDim2.new(1,0,0,40),TextXAlignment=Enum.TextXAlignment.Center,Parent=BlkContent}) end
end
BBtn.MouseButton1Click:Connect(refreshBlocked)
UnblockAllBtn.MouseButton1Click:Connect(function() RSP.Blocked={}; refreshBlocked() end)

-- ════════════════════════════════════════
-- ABA CONFIG
-- ════════════════════════════════════════
local CfgScroll=N("ScrollingFrame",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,
    BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=C.Border,
    CanvasSize=UDim2.new(0,0,0,0),Parent=SFrame})
local CfgContent=N("Frame",{Size=UDim2.new(1,0,0,0),BackgroundTransparency=1,Parent=CfgScroll},{
    N("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,5)}),Pad(8,12)})
local cfgLayout=CfgContent:FindFirstChildOfClass("UIListLayout")
cfgLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    CfgScroll.CanvasSize=UDim2.new(0,0,0,cfgLayout.AbsoluteContentSize.Y+24)
end)
local function CfgSec(txt,order)
    Lbl(txt,9,C.TextM,Enum.Font.GothamBold,{Size=UDim2.new(1,0,0,18),LayoutOrder=order,Parent=CfgContent})
end
local function CfgTog(label,key,order)
    local row=N("Frame",{Size=UDim2.new(1,0,0,30),BackgroundColor3=C.Surface,
        BorderSizePixel=0,LayoutOrder=order,Parent=CfgContent},{Rnd(6),Pad(0,10)})
    Lbl(label,12,C.Text,Enum.Font.Gotham,{Size=UDim2.new(1,-50,1,0),Parent=row})
    local on=RSP.Settings[key]
    local bg=N("Frame",{Size=UDim2.new(0,36,0,16),Position=UDim2.new(1,-40,0.5,-8),
        BackgroundColor3=on and C.Accent or C.Border,BorderSizePixel=0,Parent=row},{Rnd(8)})
    local knob=N("Frame",{Size=UDim2.new(0,10,0,10),
        Position=UDim2.new(on and 1 or 0,on and -13 or 3,0.5,-5),
        BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Parent=bg},{Rnd(5)})
    N("TextButton",{Text="",Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Parent=bg})
        .MouseButton1Click:Connect(function()
            RSP.Settings[key]=not RSP.Settings[key]
            local v=RSP.Settings[key]
            TweenService:Create(bg,TweenInfo.new(0.14),{BackgroundColor3=v and C.Accent or C.Border}):Play()
            TweenService:Create(knob,TweenInfo.new(0.14),{
                Position=UDim2.new(v and 1 or 0,v and -13 or 3,0.5,-5)}):Play()
        end)
end
CfgSec("── Tipos de Remote ──",1)
CfgTog("FireServer (Client → Server)",     "FireServer",    2)
CfgTog("InvokeServer (Client → Server)",   "InvokeServer",  3)
CfgTog("OnClientEvent (Server → Client)",  "OnClientEvent", 4)
CfgTog("OnClientInvoke (Server → Client)", "OnClientInvoke",5)
CfgTog("Bindables (BindableEvent/Function)","Bindables",    6)
CfgSec("── Interface ──",7)
CfgTog("Auto Scroll","AutoScroll",8)
-- Max args
local maxRow=N("Frame",{Size=UDim2.new(1,0,0,30),BackgroundColor3=C.Surface,
    BorderSizePixel=0,LayoutOrder=9,Parent=CfgContent},{Rnd(6),Pad(0,10)})
local maxLbl=Lbl("Máximo de args: "..RSP.Settings.MaxArgs,12,C.Text,Enum.Font.Gotham,{
    Size=UDim2.new(0.6,0,1,0),Parent=maxRow})
Btn("−",13,{Size=UDim2.new(0,24,0,18),Position=UDim2.new(1,-56,0.5,-9),
    BackgroundColor3=C.Panel,Parent=maxRow},{Rnd(4)})
    .MouseButton1Click:Connect(function()
        RSP.Settings.MaxArgs=math.max(1,RSP.Settings.MaxArgs-1)
        maxLbl.Text="Máximo de args: "..RSP.Settings.MaxArgs
    end)
Btn("+",13,{Size=UDim2.new(0,24,0,18),Position=UDim2.new(1,-28,0.5,-9),
    BackgroundColor3=C.AccentD,Parent=maxRow},{Rnd(4)})
    .MouseButton1Click:Connect(function()
        RSP.Settings.MaxArgs=math.min(30,RSP.Settings.MaxArgs+1)
        maxLbl.Text="Máximo de args: "..RSP.Settings.MaxArgs
    end)
CfgSec("── Ações ──",10)
local actRow=N("Frame",{Size=UDim2.new(1,0,0,34),BackgroundTransparency=1,
    LayoutOrder=11,Parent=CfgContent},{
    N("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,
        Padding=UDim.new(0,8),VerticalAlignment=Enum.VerticalAlignment.Center})})
Btn("📤 Exportar JSON",11,{Size=UDim2.new(0,138,0,28),
    BackgroundColor3=C.AccentD,Parent=actRow},{Rnd(6)})
    .MouseButton1Click:Connect(function()
        if not ENV.CanCopy then return end
        local out={}
        for _,l in ipairs(RSP.Logs) do
            out[#out+1]={id=l.id,timestamp=l.timestamp,type=l.type,
                remoteType=l.remoteType,remoteName=l.remoteName,
                remotePath=l.remotePath,argsFormatted=l.argsFormatted,
                blocked=l.blocked,callerScript=l.callerScript,
                callerLine=l.callerLine,direction=l.direction}
        end
        local ok,j=pcall(HttpService.JSONEncode,HttpService,out)
        if ok then ENV.setclipboard(j) end
    end)
Btn("🗑 Limpar Tudo",11,{Size=UDim2.new(0,108,0,28),
    BackgroundColor3=Color3.fromRGB(50,15,15),TextColor3=C.Error,Parent=actRow},{Rnd(6)})
    .MouseButton1Click:Connect(function()
        RSP.Logs={}; RSP.Stats={}; RSP.Blocked={}; filteredLogs={}; selectedLog=nil
        LogScroll.CanvasSize=UDim2.new(0,0,0,0); LogScroll.CanvasPosition=Vector2.new(0,0)
        for _,p in ipairs(pool) do p.frame.Visible=false; p.boundLog=nil end
        LogCountLbl.Text="0 logs"
    end)
-- Info
CfgSec("── Informações do Executor ──",12)
local infoBox=N("Frame",{Size=UDim2.new(1,0,0,72),BackgroundColor3=C.Panel,
    BorderSizePixel=0,LayoutOrder=13,Parent=CfgContent},{Rnd(6),Pad(6,10)})
Lbl("Executor: "..ENV.Name,11,C.Text,Enum.Font.GothamBold,{
    Size=UDim2.new(1,0,0,18),Parent=infoBox})
local hmTxt=ENV.CanHookFunction and "hookfunction (protótipo)" or
             ENV.CanHookMeta    and "hookmetamethod (__namecall)" or
             "Fallback (patch instância)"
Lbl("Hook: "..hmTxt,10,C.TextD,Enum.Font.Gotham,{
    Size=UDim2.new(1,0,0,16),Position=UDim2.new(0,0,0,18),Parent=infoBox})
Lbl("Clipboard: "..(ENV.CanCopy and "✅ disponível" or "❌ indisponível"),
    10,C.TextD,Enum.Font.Gotham,{
    Size=UDim2.new(1,0,0,16),Position=UDim2.new(0,0,0,34),Parent=infoBox})
Lbl("hookfunction: "..tostring(ENV.CanHookFunction)
    .."  |  hookmetamethod: "..tostring(ENV.CanHookMeta),
    9,C.TextM,Enum.Font.Gotham,{
    Size=UDim2.new(1,0,0,16),Position=UDim2.new(0,0,0,52),Parent=infoBox})

-- ── DRAG ──
do
    local drag,ds,sp=false,nil,nil
    HDR.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then
            drag=true; ds=i.Position; sp=Win.Position end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and i.UserInputType==Enum.UserInputType.MouseMovement then
            local d=i.Position-ds
            Win.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y) end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end
    end)
end

-- ── INICIALIZAÇÃO ──
switchTab("Logs")

Win.Size=UDim2.new(0,0,0,0)
Win.Position=UDim2.new(0.5,0,0.5,0)
TweenService:Create(Win,TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{
    Size=UDim2.new(0,WIN_W,0,WIN_H),
    Position=UDim2.new(0.5,-WIN_W/2,0.5,-WIN_H/2)}):Play()

-- Hooks em thread separada (não trava a UI)
task.spawn(function()
    task.wait(0.3)
    initHooks()
    addLog({
        type="FireServer", remoteType="Sistema",
        remoteName="RSP Inicializado", remotePath="System.RSP",
        remote=nil, args={"executor="..ENV.Name,"hook="..hookMode},
        blocked=false, direction="⚡ Sistema"
    })
end)

print([[
┌────────────────────────────────────┐
│   Remote Spy Pro v3.0  ativo!      │
│   RSP.Enabled=false  → pausar      │
│   RSP.Blocked[path]=true→bloquear  │
│   RSP.Logs  → acessar logs         │
└────────────────────────────────────┘]])