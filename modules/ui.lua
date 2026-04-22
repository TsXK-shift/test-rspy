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

    LogScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(renderList)

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
            if state.config.autoScroll then
                task.defer(function()
                    local h = math.max(0, #filtered * ITEM_S)
                    LogScroll.CanvasSize = UDim2.new(0,0,0,h)
                    local vis = LogScroll.AbsoluteSize.Y
                    LogScroll.CanvasPosition = Vector2.new(0, math.max(0, h-vis))
                    renderList()
                end)
            else
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
