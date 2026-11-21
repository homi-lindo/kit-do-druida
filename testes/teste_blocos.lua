-- Banco de testes do Blocos.lua fora do jogo (LuaJIT): API do WoW simulada, base de quests falsa,
-- e a sequência carga -> login -> varredura -> cálculo -> itens chegando do servidor -> lista ->
-- dicas -> botão de ordem -> cliques -> marcadores.
-- Uso: luajit teste_blocos.lua <caminho do Blocos.lua> [sem-dica]
--   sem-dica: tira o C_TooltipInfo, para testar a lista de armas e armaduras do Classic

local caminho = assert(arg[1], "passe o caminho do Blocos.lua")
local semDica = arg[2] == "sem-dica"
local errosGuardados = 0
local timers = {}

---------------------------------------------------------------------------
-- Quadros simulados
---------------------------------------------------------------------------
local todos = {}
local Frame = {}
Frame.__index = function(_, k)
    local v = rawget(Frame, k)
    if v ~= nil then
        return v
    end
    if type(k) == "string" and k:match("^[A-Z]") then
        return function() end
    end
    return nil
end

local function Novo(tipo, pai)
    local f = setmetatable({ _tipo = tipo, _pai = pai, _scripts = {}, _shown = true, _w = 10, _h = 10,
        _escala = 1, _nivel = 3, _texto = "" }, Frame)
    todos[#todos + 1] = f
    return f
end

function Frame:SetScript(nome, fn) self._scripts[nome] = fn end
function Frame:GetScript(nome) return self._scripts[nome] end
function Frame:Show() self._shown = true end
function Frame:Hide() self._shown = false end
function Frame:SetShown(v) self._shown = v and true or false end
function Frame:IsShown() return self._shown end
function Frame:IsVisible() return self._shown end
function Frame:SetSize(w, h) self._w, self._h = w, h end
function Frame:SetWidth(w) self._w = w end
function Frame:SetHeight(h) self._h = h end
function Frame:GetWidth() return self._w end
function Frame:GetHeight() return self._h end
function Frame:GetSize() return self._w, self._h end
function Frame:SetScale(s) self._escala = s end
function Frame:GetScale() return self._escala end
function Frame:GetEffectiveScale() return 1 end
function Frame:SetFrameLevel(n) self._nivel = n end
function Frame:GetFrameLevel() return self._nivel end
function Frame:GetCenter() return 1500, 600 end
function Frame:IsMouseOver() return false end
function Frame:SetText(t) self._texto = t == nil and "" or tostring(t) end
function Frame:GetText() return self._texto end
function Frame:GetStringHeight()
    local _, n = self._texto:gsub("\n", "")
    return 12 * (n + 1)
end
function Frame:SetTexture(t) self._textura = t end
function Frame:SetPoint(...) self._pos = { ... } end
function Frame:ClearAllPoints() self._pos = nil end
function Frame:SetAlpha(a) self._alpha = a end
function Frame:CreateTexture() return Novo("Texture", self) end
function Frame:CreateFontString() return Novo("FontString", self) end

function CreateFrame(tipo, nome, pai)
    local f = Novo(tipo, pai)
    if nome then
        _G[nome] = f
    end
    return f
end

UIParent = Novo("Frame")
UIParent:SetSize(1920, 1080)
local canvas = Novo("Frame")
canvas:SetSize(1000, 667)
WorldMapFrame = Novo("Frame")
WorldMapFrame.ScrollContainer = { Child = canvas }
rawset(WorldMapFrame, "GetCanvas", function() return canvas end)
rawset(WorldMapFrame, "GetMapID", function() return 1 end)
Minimap = Novo("Frame")
Minimap:SetSize(140, 140)
rawset(Minimap, "GetZoom", function() return 0 end)

GameTooltip = { linhas = {}, dono = nil, visivel = false }
function GameTooltip:SetOwner(dono) self.dono, self.linhas, self.visivel = dono, {}, false end
function GameTooltip:AddLine(t) self.linhas[#self.linhas + 1] = tostring(t) end
function GameTooltip:AddDoubleLine(a, b) self.linhas[#self.linhas + 1] = tostring(a) .. "  ||  " .. tostring(b) end
function GameTooltip:Show() self.visivel = true end
function GameTooltip:Hide() self.visivel = false end
function GameTooltip:IsShown() return self.visivel end
function GameTooltip:GetOwner() return self.dono end

---------------------------------------------------------------------------
-- API do jogo simulada
---------------------------------------------------------------------------
C_Timer = {
    After = function(_, fn) timers[#timers + 1] = fn end,
    NewTicker = function() return {} end,
}
C_Map = { GetMapInfo = function(id) return { name = "Zona " .. id } end }
C_QuestLog = {
    GetAllCompletedQuestIDs = function() return { 100 } end,
    GetNumQuestLogEntries = function() return 1 end,
    GetInfo = function(i) if i == 1 then return { questID = 201, isHeader = false } end end,
    IsComplete = function() return false end,
    GetQuestObjectives = function(id)
        if id == 201 then return { { text = "Raposa Teste: 3/8", finished = false } } end
        return {}
    end,
}
function UnitLevel() return 10 end
function UnitRace() return "Skyborne", "Skyborne", 96 end
function UnitClass() return "Druid", "DRUID", 11 end
function UnitName() return "Druida" end
function InCombatLockdown() return false end
function IsShiftKeyDown() return false end
function GetQuestDifficultyColor(n) return { r = 1, g = n > 10 and 0.5 or 1, b = 0 } end
function GetPlayerFacing() return 0 end
ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" }, [2] = { hex = "|cff1eff00" }, [3] = { hex = "|cff0070dd" } }
ITEM_MIN_LEVEL = "Requires Level %d"
INVTYPE_CHEST = "Chest"
INVTYPE_FEET = "Feet"
INVTYPE_HAND = "Hands"
INVTYPE_FINGER = "Finger"
INVTYPE_CLOAK = "Back"
INVTYPE_2HWEAPON = "Two-Hand"
INVTYPE_WEAPON = "One-Hand"
C_CVar = { GetCVar = function() return "0" end }
C_Minimap = { GetViewRadius = function() return 200 end }
Enum = { UIMapType = { Zone = 3, Dungeon = 4, Micro = 5 } }

-- itens: nome, qualidade, nível mínimo, encaixe, preço no vendedor, classe, subclasse, ligação
-- (1 = vinculado ao pegar, 2 = ao equipar, 0 = nenhuma), atributos, subtipo
local defs = {
    [600] = { "Peitoral de Couro", 2, 8, "INVTYPE_CHEST", 120, 4, 2, 1,
        { ITEM_MOD_AGILITY_SHORT = 3, ITEM_MOD_STAMINA_SHORT = 2, RESISTANCE0_NAME = 60 }, "Leather" },
    [601] = { "Botas de Couro", 2, 8, "INVTYPE_FEET", 80, 4, 2, 1,
        { ITEM_MOD_STAMINA_SHORT = 1, RESISTANCE0_NAME = 40 }, "Leather" },
    [602] = { "Maça Grande", 2, 9, "INVTYPE_2HWEAPON", 300, 2, 5, 1,
        { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 12.34, ITEM_MOD_STRENGTH_SHORT = 5 }, "Two-Handed Maces" },
    [603] = { "Anel do Chefe", 3, 10, "INVTYPE_FINGER", 50, 4, 0, 2, { ITEM_MOD_STAMINA_SHORT = 2 }, "Miscellaneous" },
    [604] = { "Luvas da Erva", 2, 7, "INVTYPE_HAND", 30, 4, 2, 1,
        { ITEM_MOD_AGILITY_SHORT = 1, RESISTANCE0_NAME = 20 }, "Leather" },
    [605] = { "Capa do Urso", 2, 8, "INVTYPE_CLOAK", 40, 4, 1, 1,
        { ITEM_MOD_AGILITY_SHORT = 3, ITEM_MOD_STAMINA_SHORT = 2 }, "Cloth" },
    [606] = { "Cota de Malha", 2, 8, "INVTYPE_CHEST", 150, 4, 3, 1, { ITEM_MOD_STRENGTH_SHORT = 4 }, "Mail" },
    [607] = { "Poção Menor", 1, 5, "", 25, 0, 1, 0, {}, "Potion" },
    [608] = { "Elmo do Futuro", 2, 14, "INVTYPE_HEAD", 90, 4, 2, 1, { ITEM_MOD_AGILITY_SHORT = 5 }, "Leather" },
    [900] = { "Camisa Velha", 1, 1, "INVTYPE_CHEST", 5, 4, 1, 1,
        { ITEM_MOD_AGILITY_SHORT = 1, RESISTANCE0_NAME = 10 }, "Cloth" },
    [901] = { "Maça Velha", 1, 1, "INVTYPE_WEAPON", 10, 2, 4, 1,
        { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 5, ITEM_MOD_STRENGTH_SHORT = 1 }, "One-Handed Maces" },
    [902] = { "Luvas Boas", 2, 5, "INVTYPE_HAND", 20, 4, 2, 1,
        { ITEM_MOD_AGILITY_SHORT = 2, RESISTANCE0_NAME = 25 }, "Leather" },
}
-- 601 e 605 só chegam do servidor depois de pedidos
local carregado = {}
for id in pairs(defs) do carregado[id] = true end
carregado[601], carregado[605] = false, false
local pendentes, pedidos = {}, {}

local function Numero(x)
    if type(x) == "number" then return x end
    return tonumber(tostring(x):match("(%d+)"))
end

C_Item = {
    GetItemInfoInstant = function(x)
        local id = Numero(x)
        local d = defs[id]
        if not d then return nil end
        return id, "Item", d[10], d[4], 130000 + id, d[6], d[7]
    end,
    GetItemInfo = function(x)
        local id = Numero(x)
        local d = defs[id]
        if not d or not carregado[id] then return nil end
        return d[1], "link:" .. id, d[2], 10, d[3], "Item", d[10], 1, d[4], 130000 + id, d[5], d[6], d[7], d[8]
    end,
    GetItemStats = function(link)
        local d = defs[Numero(link)]
        local copia = {}
        for k, v in pairs(d and d[9] or {}) do copia[k] = v end
        return copia
    end,
    RequestLoadItemDataByID = function(id)
        if not carregado[id] and not pendentes[id] then
            pendentes[id] = true
            pedidos[#pedidos + 1] = id
        end
    end,
}
local equipadoNoTeste = { [5] = "link:900", [16] = "link:901", [10] = "link:902" }
function GetInventoryItemLink(_, lugar) return equipadoNoTeste[lugar] end
Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function(_, link)
    if link == "link:603" then return 5000 end
end } } }
if not semDica then
    local VERM, BRANCO = { r = 1, g = 0.125, b = 0.125 }, { r = 1, g = 1, b = 1 }
    C_TooltipInfo = { GetItemByID = function(id)
        local d = defs[id]
        if not d then return nil end
        local linhas = { { leftText = d[1], leftColor = BRANCO }, { leftText = d[4], rightText = d[10],
            rightColor = (d[7] == 3) and VERM or BRANCO } }
        if d[3] > 10 then
            linhas[#linhas + 1] = { leftText = "Requires Level " .. d[3], leftColor = VERM }
        end
        return { lines = linhas }
    end }
end

---------------------------------------------------------------------------
-- HereBeDragons simulada (mesma convenção da real: mundo = esquerda - largura * x)
---------------------------------------------------------------------------
local HBD = { mapData = { [1] = { mapType = 3 }, [2] = { mapType = 3 } } }
function HBD:GetWorldCoordinatesFromZone(x, y, mapa)
    return 1000 - x * 1000, 1000 - y * 1000, mapa == 2 and 1 or 0
end
function HBD:GetPlayerWorldPosition() return 700, 700, 0 end -- (30%, 30%) no mapa 1
function HBD:GetZoneCoordinatesFromWorldInstance(mx, my, inst, mapa)
    if inst ~= 0 or mapa ~= 1 then return nil, nil end
    local x, y = (1000 - mx) / 1000, (1000 - my) / 1000
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil, nil end
    return x, y
end
function LibStub(nome) if nome == "HereBeDragons-2.0" then return HBD end end

---------------------------------------------------------------------------
-- QuestieDB falso
---------------------------------------------------------------------------
local H = 8589934592 -- Skyborne da Horda (bit 33)
local quests = {
    [100] = { name = "Primeira", questLevel = 8, requiredLevel = 6, startedBy = { { 1 } }, finishedBy = { { 1 } },
        nextQuestInChain = 101 },
    [101] = { name = "Lobos de Teste", questLevel = 10, requiredLevel = 8, startedBy = { { 1 } },
        finishedBy = { { 2 } }, objectives = { { { 10, "Lobo", 8 } } }, preQuestSingle = { 100 },
        nextQuestInChain = 102, objectivesText = { "Mate 8 lobos para $N.$BVolte ao acampamento." } },
    [102] = { name = "Mais Lobos", questLevel = 11, requiredLevel = 9, startedBy = { { 2 } },
        finishedBy = { { 1 } }, objectives = { { { 11, "Lobo Grande", 4 } } }, preQuestSingle = { 101 } },
    [103] = { name = "Chefe dos Lobos", questLevel = 12, requiredLevel = 10, startedBy = { { 1 } },
        finishedBy = { { 1 } }, objectives = { { { 13, "Chefe", 1 } } }, preQuestSingle = { 102 } },
    [200] = { name = "Ervas", questLevel = 9, requiredLevel = 7, startedBy = { { 3 } }, finishedBy = { { 3 } },
        objectives = { nil, nil, { { 500 } } } },
    [201] = { name = "Entrega Aceita", questLevel = 10, requiredLevel = 8, startedBy = { { 4 } },
        finishedBy = { { 4 } }, objectives = { { { 12, "Raposa", 8 } } } },
    [300] = { name = "Só da Aliança", questLevel = 10, requiredLevel = 8, requiredRaces = 1 + 4 + 8 + 64,
        startedBy = { { 1 } }, finishedBy = { { 1 } } },
    [301] = { name = "De Profissão", questLevel = 10, requiredLevel = 8, requiredSkill = { 182, 50 },
        startedBy = { { 1 } }, finishedBy = { { 1 } } },
    [302] = { name = "Da Horda", questLevel = 10, requiredLevel = 8, requiredRaces = 2 + 16 + 32 + 128 + H,
        startedBy = { { 4 } }, finishedBy = { { 4 } } },
    [400] = { name = "Longe", questLevel = 10, requiredLevel = 8, startedBy = { { 5 } }, finishedBy = { { 5 } } },
    [210] = { name = "Ursos do Leste", questLevel = 10, requiredLevel = 8, startedBy = { { 6 } },
        finishedBy = { { 6 } }, objectives = { { { 14, "Urso", 6 } } } },
}
local npcs = {
    [1] = { name = "Chefe do Posto", friendlyToFaction = "H", zoneID = 1, spawns = { [1] = { { 30, 30 } } } },
    [2] = { name = "Caçadora", friendlyToFaction = "AH", zoneID = 1, spawns = { [1] = { { 31, 30 } } } },
    [3] = { name = "Herbalista", friendlyToFaction = "H", zoneID = 1, spawns = { [1] = { { 50, 50 } } } },
    [4] = { name = "Mensageiro", friendlyToFaction = "H", zoneID = 1, spawns = { [1] = { { 32, 31 } } } },
    [5] = { name = "Distante", friendlyToFaction = "H", zoneID = 2, spawns = { [2] = { { 50, 50 } } } },
    [6] = { name = "Guarda do Leste", friendlyToFaction = "H", zoneID = 1, spawns = { [1] = { { 90, 90 } } } },
    [10] = { name = "Lobo", zoneID = 1, spawns = { [1] = { { 35, 35 }, { 36, 34 } } } },
    [11] = { name = "Lobo Grande", zoneID = 1, spawns = { [1] = { { 40, 40 } } } },
    [12] = { name = "Raposa", zoneID = 1, spawns = { [1] = { { 60, 60 } } } },
    [13] = { name = "Chefe", zoneID = 1, spawns = { [1] = { { 45, 45 } } } },
    [14] = { name = "Urso", zoneID = 1, spawns = { [1] = { { 80, 88 } } } },
}
local objetos = { [20] = { name = "Moita", zoneID = 1, spawns = { [1] = { { 52, 52 } } } } }
local itens = {
    [500] = { name = "Folha", objectDrops = { 20 } },
    [600] = { name = "Peitoral de Couro", questRewards = { 101 } },
    [601] = { name = "Botas de Couro", questRewards = { 101 } },
    [602] = { name = "Maça Grande", questRewards = { 102 } },
    [603] = { name = "Anel do Chefe", questRewards = { 103 } },
    [604] = { name = "Luvas da Erva", questRewards = { 200 } },
    [605] = { name = "Capa do Urso", questRewards = { 210 } },
    [606] = { name = "Cota de Malha", questRewards = { 200 } },
    [607] = { name = "Poção Menor", questRewards = { 200 } },
    [608] = { name = "Elmo do Futuro", questRewards = { 302 } },
}

local function Entidade(dados)
    return setmetatable({
        GetAllIds = function()
            local ids = {}
            for id in pairs(dados) do ids[#ids + 1] = id end
            table.sort(ids)
            return ids
        end,
        Exists = function(id) return dados[id] ~= nil end,
    }, { __index = function(_, campo)
        return function(id) return dados[id] and dados[id][campo] end
    end })
end
QuestDB, NpcDB, ObjectDB, ItemDB = Entidade(quests), Entidade(npcs), Entidade(objetos), Entidade(itens)
LibQuestieDB = { Support = { Get = function(nome)
    if nome == "ZoneDB" then return { private = { areaIdToUiMapId = "return {[1]=1,[2]=2}" } } end
    if nome == "QuestXP" then return { db = { [101] = { 10, 450 }, [102] = { 11, 500 }, [200] = { 9, 300 },
        [201] = { 10, 400 }, [302] = { 10, 350 }, [210] = { 10, 420 } } } end
end } }

---------------------------------------------------------------------------
-- Kit simulado
---------------------------------------------------------------------------
local carregar, entrar = {}, {}
local K = { PREFIXO = "[Kit] ", NOME = "KitDruida", db = {}, movendo = false }
function K.AoCarregar(fn) carregar[#carregar + 1] = fn end
function K.AoEntrar(fn) entrar[#entrar + 1] = fn end
function K.RegistrarQuadro(_, frame)
    frame:SetScript("OnDragStart", function() end)
    frame:SetScript("OnDragStop", function() end)
end
function K.Secreto() return false end
function K.GuardarErro(t)
    errosGuardados = errosGuardados + 1
    print("!! ERRO GUARDADO: " .. t)
end
function K.Moeda(cobre)
    local negativo = cobre < 0
    cobre = math.floor(math.abs(cobre) + 0.5)
    local texto
    if cobre >= 10000 then
        texto = string.format("%dg %ds", math.floor(cobre / 10000), math.floor(cobre / 100) % 100)
    elseif cobre >= 100 then
        texto = string.format("%ds %dc", math.floor(cobre / 100), cobre % 100)
    else
        texto = cobre .. "c"
    end
    return (negativo and "-" or "") .. texto
end

---------------------------------------------------------------------------
-- Sequência
---------------------------------------------------------------------------
local function Limpo(t)
    return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t", "[ícone]"))
end

local function RodarQuadros(vezes)
    for _ = 1, vezes do
        for _, f in ipairs(todos) do
            local fn = f._scripts.OnUpdate
            if fn then fn(f, 0.1) end
        end
    end
end

local function RodarTimers()
    for _ = 1, 5 do
        local lista = timers
        timers = {}
        for _, fn in ipairs(lista) do fn() end
    end
end

local function Evento(nome, ...)
    for _, f in ipairs(todos) do
        local fn = f._scripts.OnEvent
        if fn then fn(f, nome, ...) end
    end
end

-- o "servidor" entrega os itens pedidos
local function Servidor()
    local lista = {}
    for id in pairs(pendentes) do lista[#lista + 1] = id end
    table.sort(lista)
    pendentes = {}
    for _, id in ipairs(lista) do
        carregado[id] = true
        Evento("GET_ITEM_INFO_RECEIVED", id, true)
    end
    return lista
end

local function Linhas()
    local saida = {}
    for _, f in ipairs(todos) do
        if f._tipo == "Button" and f._shown and f.direita then
            saida[#saida + 1] = f
        end
    end
    table.sort(saida, function(a, b) return a._pos[5] > b._pos[5] end)
    return saida
end

local function BotaoOrdem()
    for _, f in ipairs(todos) do
        if f._tipo == "Button" and f.texto and not f.direita then return f end
    end
end

local function MostrarLista(titulo)
    print("== " .. titulo .. " (" .. Limpo(BotaoOrdem().texto._texto) .. ") ==")
    for _, l in ipairs(Linhas()) do
        print(string.format("  %2s  %-50s %s", l.numero._shown and l.numero._texto or "",
            Limpo(l.texto._texto), Limpo(l.direita._texto)))
    end
end

local function Dica(l)
    l._scripts.OnEnter(l)
    print("-- dica: " .. Limpo(l.texto._texto))
    for _, t in ipairs(GameTooltip.linhas) do print("     " .. Limpo(t)) end
    l._scripts.OnLeave(l)
end

print(semDica and "### sem a dica do jogo (lista do Classic)" or "### com a dica do jogo (C_TooltipInfo)")
local chunk = assert(loadfile(caminho))
chunk("KitDruida", K)
for _, fn in ipairs(carregar) do fn() end
for _, fn in ipairs(entrar) do fn() end
RodarQuadros(6)
RodarTimers()
MostrarLista("antes de os itens 601 e 605 chegarem")
local chegaram = Servidor()
print("itens que chegaram do servidor: " .. table.concat(chegaram, ", "))
RodarTimers()
MostrarLista("depois que chegaram")

for _, l in ipairs(Linhas()) do
    if l.texto._texto:find("Bloco") then Dica(l) end
end
-- abre o bloco 2 (o das quests de lobo) para ver as dicas das quests
for _, l in ipairs(Linhas()) do
    if l.texto._texto:find("Bloco 2") then l._scripts.OnClick(l) end
end
MostrarLista("bloco 2 aberto")
for _, l in ipairs(Linhas()) do
    if l.texto._texto:find("Lobos de Teste") or l.texto._texto:find("Ervas") or l.texto._texto:find("Da Horda") then
        Dica(l)
    end
end

-- troca a ordem para XP e volta
local botao = BotaoOrdem()
botao._scripts.OnClick(botao)
MostrarLista("depois do botão de ordem")
botao._scripts.OnClick(botao)
MostrarLista("de volta")

-- equipa o peitoral: ele deixa de ser melhoria
equipadoNoTeste[5] = "link:600"
Evento("PLAYER_EQUIPMENT_CHANGED", 5, false)
RodarTimers()
for _, l in ipairs(Linhas()) do
    if l.texto._texto:find("Lobos de Teste") then Dica(l) end
end

RodarQuadros(2)
local noMapa, noMini = 0, 0
for _, f in ipairs(todos) do
    if f._pai == canvas and f._shown and f.dados then noMapa = noMapa + 1 end
    if f._pai == Minimap and f._shown and f.dados then noMini = noMini + 1 end
end
print(string.format("marcadores no mapa: %d; no minimapa: %d; itens pedidos ao servidor: %d", noMapa, noMini, #pedidos))
print("erros guardados: " .. errosGuardados)
