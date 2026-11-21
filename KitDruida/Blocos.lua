-- Kit do Druida: Blocos de quests.
--
-- Fase 1: junta em blocos, por proximidade, as quests do seu nível, da sua classe e da sua raça,
-- contando onde se pegam, onde se cumprem e onde se entregam, e ordena os blocos pelo XP por
-- minuto estimado. As quests já aceitas entram nos blocos junto com as sugeridas.
-- Fase 2: a ordem de percurso do bloco aberto. Cada quest tem as etapas pegar, cumprir (uma por
-- área de objetivos) e entregar, nessa ordem; a rota vai sempre para a etapa liberada mais perto,
-- e etapas a menos de 40 jardas uma da outra viram uma parada só. As paradas aparecem numeradas
-- no mapa (M) e no minimapa.
-- Fase 3: o loot. Cada recompensa ganha uma nota para o Feral. Se o druida usa o item (o próprio
-- jogo diz, pela linha vermelha na dica do item; sem a dica, vale a lista do Classic), os atributos
-- dele contra os do que está equipado no mesmo lugar dão a melhoria (Agility e Strength valem 1
-- por ponto, Stamina 0,5, DPS da arma 1, armadura 0,02). Some-se o valor de venda: vendedor, ou
-- leilão pelo Auctionator quando o item não vem vinculado. A quest vale a melhor recompensa (quase
-- sempre se escolhe uma). O botão no canto da lista ordena os blocos pelo loot por minuto ou pelo
-- XP por minuto.
--
-- A lista é uma sanfona: uma linha por bloco, e só o bloco aberto mostra as quests, uma por linha,
-- com o número da primeira parada, o estado (pegar, aceita ou pronta) e os ícones das recompensas.
-- Com o mouse parado numa quest aparecem os objetivos, as paradas, o XP, as recompensas descritas
-- e, se ela fizer parte de uma cadeia, a cadeia inteira, com as recompensas de cada quest.
--
-- Dados: QuestieDB, que funciona sem o Questie. A quest não traz as recompensas; elas vêm do
-- ItemDB (campo questRewards de cada item), lido uma vez, em pedaços, depois das quests.
--
-- Marcadores: quadros nossos, sem a HereBeDragons-Pins. A Pins registra um pool de pinos e um
-- provedor de dados dentro do WorldMapFrame e chama métodos do mapa a partir do addon; com ela
-- carregada (2.2.0 e 2.2.1), a área azul das quests sumiu do mapa. Aqui nada se escreve em quadro
-- da Blizzard: os pinos são filhos da tela do mapa e do minimapa e se posicionam só por leitura.
-- Da HereBeDragons fica o núcleo, que converte coordenadas.

local _, K = ...
local B = {}
K.Blocos = B

local ALCANCE = 2500          -- jardas: só entram quests com algum ponto a até isso de você
local RAIO_BLOCO = 450        -- jardas: distância máxima entre o centro da quest e o do bloco
local MAX_POR_BLOCO = 6
local MAX_BLOCOS = 5
local VELOCIDADE = 8          -- jardas por segundo, média entre a pé, Cat Form e Travel Form
local SEG_POR_OBJETIVO = 75   -- segundos por objetivo, em média
local NIVEL_ABAIXO, NIVEL_ACIMA = 4, 3
local POR_QUADRO = 400        -- quests lidas por quadro na primeira varredura
local ITENS_POR_QUADRO = 600  -- itens lidos por quadro na varredura das recompensas
local JUNTAR = 40             -- jardas: etapas mais perto que isso viram uma parada só
local AREA_OBJETIVO = 200     -- jardas: objetivos mais perto que isso são uma área só
local MAX_PARADAS = 40
local MAX_CADEIA = 8          -- quests antes e depois da atual, no máximo, na cadeia
local MAX_ITENS_DICA = 6
local LARGURA, ALTURA_LINHA, TOPO = 320, 18, 24

local ICONES = { 4, 3, 6, 2, 1, 5 }
local CORES = { "verde", "roxo", "azul", "laranja", "amarelo", "prata" }
local MARCA_PEGAR = "Interface\\GossipFrame\\AvailableQuestIcon"
local MARCA_ACEITA = "Interface\\RaidFrame\\ReadyCheck-Ready"
local MARCA_ENTREGAR = "Interface\\GossipFrame\\ActiveQuestIcon"
local SETA_FECHADA = "Interface\\Buttons\\UI-PlusButton-Up"
local SETA_ABERTA = "Interface\\Buttons\\UI-MinusButton-Up"
local REALCE = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local CINZA, OURO = "|cffb0b0b0", "|cffffd200"
local CAMPOS_PRE = { "preQuestSingle", "preQuestGroup" }
local ATRIBUTOS = {
    { "ITEM_MOD_STRENGTH_SHORT", "Str" },
    { "ITEM_MOD_AGILITY_SHORT", "Agi" },
    { "ITEM_MOD_STAMINA_SHORT", "Sta" },
    { "ITEM_MOD_INTELLECT_SHORT", "Int" },
    { "ITEM_MOD_SPIRIT_SHORT", "Spi" },
}
-- raio do minimapa ao ar livre, por zoom, quando o cliente não tem C_Minimap.GetViewRadius
local RAIO_MINIMAPA = { [0] = 233.3, [1] = 200, [2] = 166.7, [3] = 133.3, [4] = 100, [5] = 66.7 }

-- Fase 3: peso de cada atributo para o Feral subindo de nível, por ponto
local PESOS = {
    ITEM_MOD_AGILITY_SHORT = 1, ITEM_MOD_STRENGTH_SHORT = 1, ITEM_MOD_STAMINA_SHORT = 0.5,
    ITEM_MOD_ATTACK_POWER_SHORT = 0.5, ITEM_MOD_FERAL_ATTACK_POWER_SHORT = 0.5,
    ITEM_MOD_INTELLECT_SHORT = 0.2, ITEM_MOD_SPIRIT_SHORT = 0.2,
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 1, RESISTANCE0_NAME = 0.02,
}
-- como a diferença para o equipado aparece na dica, nessa ordem (o terceiro campo: com decimal)
local DIFERENCAS = {
    { "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", "DPS", true }, { "ITEM_MOD_STRENGTH_SHORT", "Str" },
    { "ITEM_MOD_AGILITY_SHORT", "Agi" }, { "ITEM_MOD_STAMINA_SHORT", "Sta" },
    { "ITEM_MOD_ATTACK_POWER_SHORT", "AP" }, { "ITEM_MOD_INTELLECT_SHORT", "Int" },
    { "ITEM_MOD_SPIRIT_SHORT", "Spi" }, { "RESISTANCE0_NAME", "armadura" },
}
-- um ponto de melhoria vale isto em cobre por nível do personagem (5 prata por nível): no 15,
-- +4 pontos valem 3 ouro, o bastante para uma melhoria passar na frente de qualquer venda
local COBRE_POR_PONTO_NIVEL = 500
local MELHORIA_MINIMA = 0.5   -- abaixo disso (+1 Spirit, por exemplo) não conta como melhoria
-- encaixe do item -> lugares no personagem
local LUGARES = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RELIC = { 18 },
}
-- o que o druida usa no Classic, para quando o jogo não diz pela dica do item
local DRUIDA_ARMADURA = { [0] = true, [1] = true, [2] = true, [8] = true }            -- diversos, tecido, couro, ídolo
local DRUIDA_ARMA = { [4] = true, [5] = true, [10] = true, [13] = true, [15] = true } -- maças, cajado, punho, adaga
local VERDE = "|cff40ff40"

local HBD
local zonaParaMapa, xpDB
local nivelQuest, nivelMin, idsBase = {}, {}, nil
local sucessores, recompensas = {}, {}
local varrido, recompensasProntas = false, false
local progressoBase, progressoRecompensas
local cacheDados, cachePontos, cacheExtra, cacheCadeia = {}, {}, {}, {}
local cacheCentro = { npc = {}, object = {}, item = {} }
local blocos = {}
local feitasAtuais, aceitasAtuais = {}, {}
local meuBitRaca, meuBitClasse = 0, 0
local agendado, emCombatePendente = false, false
local escolha = { modo = "auto" }   -- bloco aberto na lista: auto (o melhor), nenhum ou fixo
local dica                         -- dica aberta agora: { dono, mostrar }, para refazer
local cacheAvaliacao, equipado = {}, {}   -- nota de cada item e o que está equipado, por lugar
local faltamItens, nivelAtual = false, 1  -- algum item ainda não carregou; nível no último cálculo

local DesenharLista, DesenharPinos, MostrarErro, LootDaQuest

local function Textura(i)
    return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. ICONES[i]
end

local function Opcoes()
    return (K.db and K.db.blocos) or { pinos = true, ordem = "loot" }
end

K.AoCarregar(function()
    if type(K.db.blocos) ~= "table" then
        K.db.blocos = {}
    end
    if K.db.blocos.pinos == nil then
        K.db.blocos.pinos = true
    end
    if K.db.blocos.ordem ~= "xp" and K.db.blocos.ordem ~= "loot" then
        K.db.blocos.ordem = "loot"
    end
end)

-- Erro que não para o módulo: vai só para o registro do Kit (KitDruidaDB.erros)
local function Anotar(etapa, erro)
    if K.GuardarErro then
        K.GuardarErro("[Blocos " .. etapa .. "] " .. tostring(erro))
    end
end

local function TemBase()
    return _G.LibQuestieDB and _G.QuestDB and _G.NpcDB and _G.ObjectDB and _G.ItemDB
        and type(_G.QuestDB.GetAllIds) == "function"
end

local function Ler(entidade, campo, id)
    local funcao = entidade and entidade[campo]
    if type(funcao) ~= "function" then
        return nil
    end
    local ok, valor = pcall(funcao, id)
    if ok then
        return valor
    end
    return nil
end

local function Decodificar(texto)
    if type(texto) ~= "string" then
        return nil
    end
    local trecho = loadstring(texto)
    if not trecho then
        return nil
    end
    local ok, tabela = pcall(trecho)
    if ok and type(tabela) == "table" then
        return tabela
    end
    return nil
end

local function PrepararApoio()
    local suporte = LibQuestieDB.Support
    local zonas = suporte and suporte.Get and suporte.Get("ZoneDB")
    local privado = zonas and zonas.private
    zonaParaMapa = (privado and Decodificar(privado.areaIdToUiMapId)) or {}
    local extra = privado and Decodificar(privado.areaIdToUiMapIdOverride)
    if extra then
        for area, mapa in pairs(extra) do
            zonaParaMapa[area] = mapa
        end
    end
    local xp = suporte and suporte.Get and suporte.Get("QuestXP")
    xpDB = (xp and type(xp.db) == "table") and xp.db or {}
end

-- 3400 vira "3.400"
local function Milhar(n)
    local texto = tostring(math.floor((n or 0) + 0.5))
    local invertido = texto:reverse():gsub("(%d%d%d)", "%1.")
    local certo = invertido:reverse()
    return (certo:gsub("^%.", ""))
end

-- 3400 vira "3,4 mil"; 12800 vira "12 mil"
local function XPCurto(n)
    n = math.floor((n or 0) + 0.5)
    if n >= 10000 then
        return math.floor(n / 1000) .. " mil"
    elseif n >= 1000 then
        return (string.format("%.1f mil", n / 1000):gsub("%.", ","))
    end
    return tostring(n)
end

---------------------------------------------------------------------------
-- Geometria (coordenadas de mundo da HereBeDragons, em jardas)
---------------------------------------------------------------------------

local function Distancia(a, b)
    if not (a and b) or a.inst ~= b.inst then
        return nil
    end
    local dx, dy = a.mx - b.mx, a.my - b.my
    return math.sqrt(dx * dx + dy * dy)
end

local function Media(lista)
    local soma, n, base = { mx = 0, my = 0 }, 0, nil
    for _, ponto in ipairs(lista) do
        if not base then
            base = ponto
        end
        if ponto.inst == base.inst then
            soma.mx, soma.my, n = soma.mx + ponto.mx, soma.my + ponto.my, n + 1
        end
    end
    if n == 0 then
        return nil
    end
    return { mx = soma.mx / n, my = soma.my / n, inst = base.inst, mapa = base.mapa }
end

-- O ponto da lista mais perto do alvo (a média não tem x, y de mapa; um ponto real tem)
local function PontoProximo(lista, alvo)
    local perto, menor = lista[1], math.huge
    if not alvo then
        return perto
    end
    for _, ponto in ipairs(lista) do
        local d = Distancia(alvo, ponto) or math.huge
        if d < menor then
            perto, menor = ponto, d
        end
    end
    return perto
end

-- Objetivos perto uns dos outros são uma área só; cada área vira uma etapa "cumprir"
local function AreasDeObjetivo(objetivos)
    local grupos = {}
    for _, ponto in ipairs(objetivos) do
        local junto
        for _, grupo in ipairs(grupos) do
            local d = Distancia(grupo[1], ponto)
            if d and d <= AREA_OBJETIVO then
                junto = grupo
                break
            end
        end
        if junto then
            junto[#junto + 1] = ponto
        else
            grupos[#grupos + 1] = { ponto }
        end
    end
    local areas = {}
    for _, grupo in ipairs(grupos) do
        areas[#areas + 1] = PontoProximo(grupo, Media(grupo))
    end
    return areas
end

---------------------------------------------------------------------------
-- Posições
---------------------------------------------------------------------------

-- Centro dos pontos de nascimento de um NPC ou objeto, no mapa da zona principal dele
local function Centro(tipo, entidade, id)
    local cache = cacheCentro[tipo]
    if cache[id] ~= nil then
        return cache[id] or nil
    end
    local resultado = false
    local spawns = Ler(entidade, "spawns", id)
    if type(spawns) == "table" then
        local zona = Ler(entidade, "zoneID", id)
        local lista = zona and spawns[zona]
        if type(lista) ~= "table" then
            zona, lista = next(spawns)
        end
        local mapa = zona and zonaParaMapa[zona]
        if type(lista) == "table" and type(mapa) == "number" and mapa > 0 then
            local somaX, somaY, n = 0, 0, 0
            for _, ponto in ipairs(lista) do
                local x, y = ponto[1], ponto[2]
                if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
                    somaX, somaY, n = somaX + x, somaY + y, n + 1
                end
            end
            if n > 0 then
                local x, y = somaX / n / 100, somaY / n / 100
                local mx, my, instancia = HBD:GetWorldCoordinatesFromZone(x, y, mapa)
                if mx and my then
                    resultado = { mapa = mapa, x = x, y = y, mx = mx, my = my, inst = instancia }
                end
            end
        end
    end
    cache[id] = resultado
    return resultado or nil
end

local function CentroNpc(id)
    return Centro("npc", NpcDB, id)
end

local function CentroObjeto(id)
    return Centro("object", ObjectDB, id)
end

-- Item de objetivo: onde cai (primeiro NPC ou objeto que tenha posição)
local function CentroItem(id)
    local cache = cacheCentro.item
    if cache[id] ~= nil then
        return cache[id] or nil
    end
    local resultado = false
    for _, npc in ipairs(Ler(ItemDB, "npcDrops", id) or {}) do
        resultado = CentroNpc(npc) or false
        if resultado then
            break
        end
    end
    if not resultado then
        for _, objeto in ipairs(Ler(ItemDB, "objectDrops", id) or {}) do
            resultado = CentroObjeto(objeto) or false
            if resultado then
                break
            end
        end
    end
    cache[id] = resultado
    return resultado or nil
end

---------------------------------------------------------------------------
-- Dados de cada quest (lidos uma vez)
---------------------------------------------------------------------------

local function Existe(id)
    if type(id) ~= "number" then
        return false
    end
    if type(QuestDB.Exists) ~= "function" then
        return true
    end
    local ok, sim = pcall(QuestDB.Exists, id)
    return not ok or (sim and true) or false
end

local function Dados(id)
    local c = cacheDados[id]
    if c ~= nil then
        return c or nil
    end
    local d = false
    if Existe(id) then
        d = {
            nome = Ler(QuestDB, "name", id) or ("Quest " .. id),
            racas = Ler(QuestDB, "requiredRaces", id),
            classes = Ler(QuestDB, "requiredClasses", id),
            preGrupo = Ler(QuestDB, "preQuestGroup", id),
            preUma = Ler(QuestDB, "preQuestSingle", id),
            exclusivas = Ler(QuestDB, "exclusiveTo", id),
            inicio = Ler(QuestDB, "startedBy", id),
            fim = Ler(QuestDB, "finishedBy", id),
            objetivos = Ler(QuestDB, "objectives", id),
            -- quest de profissão ou de reputação não entra nos blocos, mas aparece na cadeia
            especial = Ler(QuestDB, "requiredSkill", id) ~= nil or Ler(QuestDB, "requiredMinRep", id) ~= nil,
        }
    end
    cacheDados[id] = d
    return d or nil
end

-- Campos que só a dica usa: lidos na primeira vez que a quest aparece numa dica
local function Extra(id)
    local c = cacheExtra[id]
    if not c then
        c = {
            proxima = Ler(QuestDB, "nextQuestInChain", id),
            migalha = Ler(QuestDB, "breadcrumbForQuestId", id),
            texto = Ler(QuestDB, "objectivesText", id),
        }
        cacheExtra[id] = c
    end
    return c
end

-- Onde se pega, onde se cumpre e onde se entrega
local function Pontos(id, d)
    local c = cachePontos[id]
    if c ~= nil then
        return c or nil
    end
    local p = { objetivos = {}, nObjetivos = 0 }
    local inicio = d.inicio or {}
    for _, npc in ipairs(inicio[1] or {}) do
        if Ler(NpcDB, "friendlyToFaction", npc) ~= "A" then
            local centro = CentroNpc(npc)
            if centro then
                p.inicio, p.quemDa = centro, Ler(NpcDB, "name", npc)
                break
            end
        end
    end
    if not p.inicio then
        for _, objeto in ipairs(inicio[2] or {}) do
            local centro = CentroObjeto(objeto)
            if centro then
                p.inicio, p.quemDa = centro, Ler(ObjectDB, "name", objeto)
                break
            end
        end
    end
    p.soPorItem = not p.inicio and inicio[3] ~= nil

    local objetivos = d.objetivos or {}
    local function Somar(centro)
        p.nObjetivos = p.nObjetivos + 1
        if centro and #p.objetivos < 3 then
            p.objetivos[#p.objetivos + 1] = centro
        end
    end
    for _, o in ipairs(objetivos[1] or {}) do
        Somar(CentroNpc(o[1]))
    end
    for _, o in ipairs(objetivos[2] or {}) do
        Somar(CentroObjeto(o[1]))
    end
    for _, o in ipairs(objetivos[3] or {}) do
        Somar(CentroItem(o[1]))
    end
    for _, o in ipairs(objetivos[5] or {}) do
        Somar(type(o[2]) == "number" and CentroNpc(o[2]) or nil)
    end
    p.areas = AreasDeObjetivo(p.objetivos)

    local fim = d.fim or {}
    for _, npc in ipairs(fim[1] or {}) do
        if Ler(NpcDB, "friendlyToFaction", npc) ~= "A" then
            local centro = CentroNpc(npc)
            if centro then
                p.fim, p.quemRecebe = centro, Ler(NpcDB, "name", npc)
                break
            end
        end
    end
    if not p.fim then
        for _, objeto in ipairs(fim[2] or {}) do
            local centro = CentroObjeto(objeto)
            if centro then
                p.fim, p.quemRecebe = centro, Ler(ObjectDB, "name", objeto)
                break
            end
        end
    end
    cachePontos[id] = p
    return p
end

---------------------------------------------------------------------------
-- Filtro
---------------------------------------------------------------------------

-- Máscara de raça do QuestieDB por ID de raça. O Skyborne do Forever usa os bits 32 e 33, que a
-- biblioteca bit do jogo (32 bits) trunca: por isso o teste abaixo é feito com aritmética.
local MASCARA_RACA = {
    [1] = 1, [2] = 2, [3] = 4, [4] = 8, [5] = 16, [6] = 32, [7] = 64, [8] = 128, [9] = 256,
    [10] = 512, [11] = 1024, [22] = 2097152, [24] = 8388608, [25] = 16777216, [26] = 33554432,
    [95] = 4294967296, [96] = 8589934592,
}

local function BitDaRaca(id)
    if type(id) ~= "number" then
        return 0
    end
    return MASCARA_RACA[id] or (id <= 32 and 2 ^ (id - 1)) or 0
end

local function Permite(mascara, bitJogador)
    if not mascara or mascara == 0 or not bitJogador or bitJogador == 0 then
        return true
    end
    return math.floor(mascara / bitJogador) % 2 == 1
end

local function Concluidas()
    local feitas = {}
    if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
        local ok, lista = pcall(C_QuestLog.GetAllCompletedQuestIDs)
        if ok and type(lista) == "table" then
            for _, id in ipairs(lista) do
                feitas[id] = true
            end
            return feitas
        end
    end
    if GetQuestsCompleted then
        local ok, mapa = pcall(GetQuestsCompleted)
        if ok and type(mapa) == "table" then
            return mapa
        end
    end
    return feitas
end

local function Aceitas()
    local aceitas = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
        return aceitas
    end
    local n = C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and type(info) == "table" and not info.isHeader and type(info.questID) == "number" then
            aceitas[info.questID] = true
        end
    end
    return aceitas
end

-- Quest aceita com os objetivos cumpridos: falta só entregar
local function Pronta(id)
    local funcao = (C_QuestLog and C_QuestLog.IsComplete) or IsQuestComplete
    if type(funcao) ~= "function" then
        return false
    end
    local ok, valor = pcall(funcao, id)
    if not ok or K.Secreto(valor) then
        return false
    end
    return valor == true or valor == 1
end

local function XP(id, nivelJogador)
    local e = xpDB and xpDB[id]
    if type(e) ~= "table" or type(e[2]) ~= "number" then
        return 0
    end
    local diferenca = nivelJogador - (type(e[1]) == "number" and e[1] or nivelJogador)
    local fator = (diferenca <= 5 and 1) or (diferenca == 6 and 0.8) or (diferenca == 7 and 0.6)
        or (diferenca == 8 and 0.4) or (diferenca == 9 and 0.2) or 0.1
    return e[2] * fator
end

---------------------------------------------------------------------------
-- Blocos e rota
---------------------------------------------------------------------------

local function Candidatas(jogador, nivel)
    local feitas, aceitas = Concluidas(), Aceitas()
    feitasAtuais, aceitasAtuais = feitas, aceitas
    local lista = {}
    local function Avaliar(id, aceita)
        local d = Dados(id)
        if not d or d.especial then
            return
        end
        if not aceita then
            if not Permite(d.racas, meuBitRaca) or not Permite(d.classes, meuBitClasse) then
                return
            end
            for _, pre in ipairs(d.preGrupo or {}) do
                if not feitas[pre] then
                    return
                end
            end
            if d.preUma and #d.preUma > 0 then
                local alguma = false
                for _, pre in ipairs(d.preUma) do
                    if feitas[pre] then
                        alguma = true
                        break
                    end
                end
                if not alguma then
                    return
                end
            end
            for _, outra in ipairs(d.exclusivas or {}) do
                if feitas[outra] or aceitas[outra] then
                    return
                end
            end
        end
        local p = Pontos(id, d)
        if not aceita and not p.inicio then
            return
        end
        local pronta = aceita and Pronta(id)
        local todos = {}
        if not aceita then
            todos[#todos + 1] = p.inicio
        end
        if not pronta then
            for _, o in ipairs(p.objetivos) do
                todos[#todos + 1] = o
            end
        end
        if p.fim then
            todos[#todos + 1] = p.fim
        end
        local perto = false
        for _, ponto in ipairs(todos) do
            local dist = Distancia(jogador, ponto)
            if dist and dist <= ALCANCE then
                perto = true
                break
            end
        end
        if not perto then
            return
        end
        local centro = Media(todos)
        if not centro then
            return
        end
        lista[#lista + 1] = {
            id = id, nome = d.nome, aceita = aceita, pronta = pronta, nivel = nivelQuest[id] or 0,
            pontos = p, todos = todos, centro = centro, xp = XP(id, nivel),
            distancia = Distancia(jogador, centro) or math.huge,
        }
    end

    for id in pairs(aceitas) do
        Avaliar(id, true)
    end
    for _, id in ipairs(idsBase or {}) do
        if not feitas[id] and not aceitas[id] then
            local nq, nm = nivelQuest[id] or 0, nivelMin[id] or 0
            if nq <= 0 then
                nq = nivel
            end
            if nm <= nivel and nq >= nivel - NIVEL_ABAIXO and nq <= nivel + NIVEL_ACIMA then
                Avaliar(id, false)
            end
        end
    end
    return lista
end

-- Rota do bloco a partir de você. Cada quest é uma fila de etapas (pegar, cumprir em cada área,
-- entregar); só a primeira etapa de cada fila está liberada. A rota vai para a etapa liberada mais
-- perto, consome essa etapa e junta na mesma parada as outras liberadas a até JUNTAR jardas (de
-- novo e de novo, porque consumir libera a próxima etapa da mesma quest, que pode estar ali mesmo).
local function Rota(jogador, quests)
    local filas = {}
    for _, q in ipairs(quests) do
        local fila = {}
        if not q.aceita and q.pontos.inicio then
            fila[#fila + 1] = { q = q, etapa = "pegar", ponto = q.pontos.inicio }
        end
        if not q.pronta then
            local origem = q.pontos.inicio or jogador
            local areas = {}
            for _, area in ipairs(q.pontos.areas or {}) do
                areas[#areas + 1] = area
            end
            table.sort(areas, function(a, b)
                return (Distancia(origem, a) or math.huge) < (Distancia(origem, b) or math.huge)
            end)
            for _, area in ipairs(areas) do
                fila[#fila + 1] = { q = q, etapa = "cumprir", ponto = area }
            end
        end
        if q.pontos.fim then
            fila[#fila + 1] = { q = q, etapa = "entregar", ponto = q.pontos.fim }
        end
        filas[#filas + 1] = fila
    end

    local function Liberadas()
        local lista = {}
        for _, fila in ipairs(filas) do
            if fila[1] then
                lista[#lista + 1] = fila
            end
        end
        return lista
    end

    local paradas, atual, total = {}, jogador, 0
    while #paradas < MAX_PARADAS do
        local abertas = Liberadas()
        if #abertas == 0 then
            break
        end
        local escolhida, menor
        for _, fila in ipairs(abertas) do
            local d = Distancia(atual, fila[1].ponto) or math.huge
            if not menor or d < menor then
                escolhida, menor = fila, d
            end
        end
        local primeira = table.remove(escolhida, 1)
        local parada = { ponto = primeira.ponto, acoes = { primeira } }
        local juntou = true
        while juntou do
            juntou = false
            for _, fila in ipairs(Liberadas()) do
                local d = Distancia(parada.ponto, fila[1].ponto)
                if d and d <= JUNTAR then
                    parada.acoes[#parada.acoes + 1] = table.remove(fila, 1)
                    juntou = true
                end
            end
        end
        if menor < math.huge then
            total = total + menor
        end
        paradas[#paradas + 1] = parada
        parada.numero = #paradas
        atual = parada.ponto
    end
    return paradas, total
end

local function MontarBlocos(jogador, lista)
    table.sort(lista, function(a, b)
        return a.distancia < b.distancia
    end)
    local usados, resultado = {}, {}
    for _, semente in ipairs(lista) do
        if not usados[semente] then
            local bloco = { quests = { semente } }
            usados[semente] = true
            local centro = semente.centro
            local adicionou = true
            while adicionou and #bloco.quests < MAX_POR_BLOCO do
                adicionou = false
                local melhor, melhorDist
                for _, q in ipairs(lista) do
                    if not usados[q] then
                        local d = Distancia(centro, q.centro)
                        if d and d <= RAIO_BLOCO and (not melhorDist or d < melhorDist) then
                            melhor, melhorDist = q, d
                        end
                    end
                end
                if melhor then
                    usados[melhor] = true
                    bloco.quests[#bloco.quests + 1] = melhor
                    local centros = {}
                    for _, q in ipairs(bloco.quests) do
                        centros[#centros + 1] = q.centro
                    end
                    centro = Media(centros) or centro
                    adicionou = true
                end
            end

            local paradas, percurso = Rota(jogador, bloco.quests)
            local objetivos, xp, loot, venda, melhorias = 0, 0, 0, 0, 0
            for _, q in ipairs(bloco.quests) do
                if not q.pronta then
                    objetivos = objetivos + math.max(1, q.pontos.nObjetivos)
                end
                xp = xp + q.xp
                q.paradas, q.primeira = {}, nil
                q.loot = LootDaQuest(q.id)
                loot, venda = loot + q.loot.nota, venda + q.loot.venda
                if q.loot.melhoria >= MELHORIA_MINIMA then
                    melhorias = melhorias + 1
                end
            end
            for _, parada in ipairs(paradas) do
                for _, acao in ipairs(parada.acoes) do
                    local q = acao.q
                    q.paradas[#q.paradas + 1] = { numero = parada.numero, etapa = acao.etapa }
                    q.primeira = q.primeira or parada.numero
                end
            end
            table.sort(bloco.quests, function(a, b)
                return (a.primeira or 999) < (b.primeira or 999)
            end)
            local segundos = percurso / VELOCIDADE + objetivos * SEG_POR_OBJETIVO
            bloco.centro, bloco.xp, bloco.paradas = centro, xp, paradas
            bloco.minutos = math.max(1, segundos / 60)
            bloco.loot, bloco.venda, bloco.melhorias = loot, venda, melhorias
            bloco.nota = xp / bloco.minutos
            bloco.notaLoot = loot / bloco.minutos
            resultado[#resultado + 1] = bloco
        end
    end
    -- por loot: loot por minuto, e o XP desempata; por XP: só o XP por minuto
    local porLoot = Opcoes().ordem ~= "xp"
    table.sort(resultado, function(a, b)
        if porLoot and a.notaLoot ~= b.notaLoot then
            return a.notaLoot > b.notaLoot
        end
        return a.nota > b.nota
    end)
    while #resultado > MAX_BLOCOS do
        table.remove(resultado)
    end
    return resultado
end

-- Qual bloco está aberto na lista: o que você abriu (achado de novo depois de cada recálculo pelas
-- quests em comum), nenhum, ou, de saída, o melhor
local function IndiceAberto()
    if #blocos == 0 or escolha.modo == "nenhum" then
        return nil
    end
    if escolha.modo == "fixo" and escolha.ids then
        local melhor, maior = nil, 0
        for i, bloco in ipairs(blocos) do
            local comum = 0
            for _, q in ipairs(bloco.quests) do
                if escolha.ids[q.id] then
                    comum = comum + 1
                end
            end
            if comum > maior then
                melhor, maior = i, comum
            end
        end
        if melhor then
            return melhor
        end
    end
    return 1
end

local function Fixar(i)
    local ids = {}
    for _, q in ipairs(blocos[i].quests) do
        ids[q.id] = true
    end
    escolha = { modo = "fixo", ids = ids }
end

---------------------------------------------------------------------------
-- Itens de recompensa
---------------------------------------------------------------------------

local InfoInstantanea = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local InfoCompleta = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local AtributosDoItem = (C_Item and C_Item.GetItemStats) or GetItemStats
local PedirItem = C_Item and C_Item.RequestLoadItemDataByID

-- Ícone, tipo e encaixe: o cliente sabe na hora, sem consultar o servidor
local function Instantaneo(id)
    if type(InfoInstantanea) ~= "function" then
        return nil
    end
    local ok, _, _, subtipo, encaixe, icone, classe, subclasse = pcall(InfoInstantanea, id)
    if not ok then
        return nil
    end
    return icone, subtipo, encaixe, classe, subclasse
end

local function CorDaQualidade(qualidade)
    if type(qualidade) ~= "number" then
        return "|cffffffff"
    end
    local tabela = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[qualidade]
    if tabela and type(tabela.hex) == "string" then
        return tabela.hex
    end
    local funcao = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
    if funcao then
        local ok, _, _, _, hex = pcall(funcao, qualidade)
        if ok and type(hex) == "string" then
            return "|c" .. hex
        end
    end
    return "|cffffffff"
end

-- Nome (na cor da qualidade), ícone e descrição curta: tipo, encaixe, DPS e atributos.
-- Item que o jogo ainda não carregou sai com o nome da base, em branco, e é pedido ao servidor;
-- quando chega, a dica se refaz sozinha (GET_ITEM_INFO_RECEIVED).
local function InfoItem(id)
    local icone, subtipo, encaixe, classe, subclasse = Instantaneo(id)
    local nome, link, qualidade
    if type(InfoCompleta) == "function" then
        local ok, n, l, q = pcall(InfoCompleta, id)
        if ok and type(n) == "string" then
            nome, link, qualidade = n, l, q
        end
    end
    if not nome then
        nome = Ler(ItemDB, "name", id) or ("Item " .. id)
        if PedirItem then
            pcall(PedirItem, id)
        end
    end
    local partes = {}
    local encaixeTexto = type(encaixe) == "string" and encaixe ~= "" and _G[encaixe] or nil
    if type(encaixeTexto) ~= "string" or encaixeTexto == "" then
        encaixeTexto = nil
    end
    if classe == 2 then
        partes[#partes + 1] = subtipo
        partes[#partes + 1] = encaixeTexto
    elseif classe == 4 then
        if subclasse ~= 0 then
            partes[#partes + 1] = subtipo
        end
        partes[#partes + 1] = encaixeTexto
    else
        partes[#partes + 1] = subtipo
    end
    if link and type(AtributosDoItem) == "function" then
        local ok, atributos = pcall(AtributosDoItem, link)
        if ok and type(atributos) == "table" then
            local dps = atributos.ITEM_MOD_DAMAGE_PER_SECOND_SHORT
            if type(dps) == "number" and dps > 0 then
                partes[#partes + 1] = (string.format("%.1f DPS", dps):gsub("%.", ","))
            end
            local lista = {}
            for _, a in ipairs(ATRIBUTOS) do
                local v = atributos[a[1]]
                if type(v) == "number" and v ~= 0 then
                    lista[#lista + 1] = string.format("%+d %s", v, a[2])
                end
            end
            if #lista > 0 then
                partes[#partes + 1] = table.concat(lista, " ")
            end
        end
    end
    local limpas = {}
    for _, parte in ipairs(partes) do
        if type(parte) == "string" and parte ~= "" then
            limpas[#limpas + 1] = parte
        end
    end
    return { nome = nome, cor = CorDaQualidade(qualidade), icone = icone, descricao = table.concat(limpas, " · ") }
end

---------------------------------------------------------------------------
-- Fase 3: quanto a recompensa vale para o Feral
---------------------------------------------------------------------------

local function Atributos(link)
    if not link or type(AtributosDoItem) ~= "function" then
        return {}
    end
    local ok, tabela = pcall(AtributosDoItem, link)
    return (ok and type(tabela) == "table") and tabela or {}
end

local function Pontuar(atributos)
    local soma = 0
    for chave, peso in pairs(PESOS) do
        local v = atributos[chave]
        if type(v) == "number" then
            soma = soma + v * peso
        end
    end
    return soma
end

local function PrecoLeilao(link)
    if not (link and Auctionator and Auctionator.API and Auctionator.API.v1
        and Auctionator.API.v1.GetAuctionPriceByItemLink) then
        return nil
    end
    local ok, preco = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, K.NOME, link)
    if ok and type(preco) == "number" and preco > 0 then
        return preco
    end
    return nil
end

-- O que está equipado num lugar (guardado até o equipamento mudar)
local function Equipado(lugar)
    local e = equipado[lugar]
    if e then
        return e
    end
    e = { atributos = {}, pontos = 0 }
    local link = GetInventoryItemLink and GetInventoryItemLink("player", lugar)
    if type(link) == "string" then
        e.atributos = Atributos(link)
        e.pontos = Pontuar(e.atributos)
        local _, _, encaixe = Instantaneo(link)
        e.encaixe = encaixe
    end
    equipado[lugar] = e
    return e
end

-- Com o que a recompensa compete: anel e berloque, com o pior dos dois; arma de duas mãos, com a
-- mão principal e a secundária juntas; item de mão secundária, com nada se a arma é de duas mãos
local function Concorrente(encaixe)
    local lugares = LUGARES[encaixe]
    if not lugares then
        return nil
    end
    if encaixe == "INVTYPE_2HWEAPON" then
        local principal, secundaria = Equipado(16), Equipado(17)
        local junto = { atributos = {}, pontos = principal.pontos + secundaria.pontos }
        for chave in pairs(PESOS) do
            local a, b = principal.atributos[chave], secundaria.atributos[chave]
            if a or b then
                junto.atributos[chave] = (a or 0) + (b or 0)
            end
        end
        return junto
    end
    if encaixe == "INVTYPE_HOLDABLE" and Equipado(16).encaixe == "INVTYPE_2HWEAPON" then
        return nil
    end
    local pior
    for _, lugar in ipairs(lugares) do
        local e = Equipado(lugar)
        if not pior or e.pontos < pior.pontos then
            pior = e
        end
    end
    return pior
end

-- "Requires Level %d" do cliente, como padrão de busca (a linha de nível mínimo não desqualifica:
-- item até 2 níveis acima conta, porque você chega lá)
local NIVEL_MINIMO = ((ITEM_MIN_LEVEL or "Requires Level %d"):gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    :gsub("%%d", "%%d+"))

local function Vermelho(cor)
    if type(cor) ~= "table" or K.Secreto(cor.r) or K.Secreto(cor.g) or K.Secreto(cor.b) then
        return false
    end
    return type(cor.r) == "number" and cor.r > 0.9
        and type(cor.g) == "number" and cor.g < 0.3 and type(cor.b) == "number" and cor.b < 0.3
end

-- O druida usa o item? Primeiro pergunta ao jogo: na dica do item, texto vermelho (fora o de nível
-- mínimo) quer dizer que não usa, como armadura de malha ou arma que ele não aprendeu. Sem a dica,
-- vale a lista do Classic.
local function UsavelAgora(id, classe, subclasse)
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local ok, dados = pcall(C_TooltipInfo.GetItemByID, id)
        if ok and type(dados) == "table" and type(dados.lines) == "table" and #dados.lines > 0 then
            for _, linha in ipairs(dados.lines) do
                local lados = { { linha.leftText, linha.leftColor }, { linha.rightText, linha.rightColor } }
                for _, lado in ipairs(lados) do
                    local texto, cor = lado[1], lado[2]
                    if type(texto) == "string" and not K.Secreto(texto) and Vermelho(cor)
                        and not texto:find(NIVEL_MINIMO) then
                        return false
                    end
                end
            end
            return true
        end
    end
    if classe == 4 then
        return DRUIDA_ARMADURA[subclasse] == true
    elseif classe == 2 then
        return DRUIDA_ARMA[subclasse] == true
    end
    return false
end

-- A resposta fica guardada por item até o nível mudar (ler a dica do item custa)
local cacheUsavel = {}
local function Usavel(id, classe, subclasse)
    local c = cacheUsavel[id]
    if c and c.nivel == nivelAtual then
        return c.valor
    end
    local valor = UsavelAgora(id, classe, subclasse)
    cacheUsavel[id] = { nivel = nivelAtual, valor = valor }
    return valor
end

-- Nota de uma recompensa, em cobre: a melhoria para o Feral (convertida pelo nível) mais o valor de
-- venda. Item que o jogo ainda não carregou é pedido ao servidor e fica de fora deste cálculo; quando
-- chega, o cálculo se refaz (GET_ITEM_INFO_RECEIVED).
local function AvaliarItem(id)
    local c = cacheAvaliacao[id]
    if c ~= nil then
        return c or nil
    end
    if type(InfoCompleta) ~= "function" then
        cacheAvaliacao[id] = false
        return nil
    end
    local ok, nome, link, _, _, nivelMin, _, _, _, encaixe, _, preco, classe, subclasse, ligacao =
        pcall(InfoCompleta, id)
    if not ok or type(nome) ~= "string" then
        faltamItens = true
        if PedirItem then
            pcall(PedirItem, id)
        end
        return nil
    end
    local av = { melhoria = 0, venda = type(preco) == "number" and preco or 0, fonte = "vendedor" }
    -- vinculado ao pegar (1) ou item de quest (4) não vai a leilão
    if ligacao ~= 1 and ligacao ~= 4 then
        local leilao = PrecoLeilao(link)
        if leilao and leilao * 0.95 > av.venda then
            av.venda, av.fonte = leilao * 0.95, "leilão"
        end
    end
    if (classe == 2 or classe == 4) and LUGARES[encaixe] and type(nivelMin) == "number"
        and nivelMin > nivelAtual + 2 then
        av.nivelAlto = nivelMin
    elseif (classe == 2 or classe == 4) and LUGARES[encaixe] then
        av.usavel = Usavel(id, classe, subclasse)
        local rival = av.usavel and Concorrente(encaixe)
        if rival then
            local atributos = Atributos(link)
            av.melhoria = Pontuar(atributos) - rival.pontos
            av.diferenca = {}
            for _, d in ipairs(DIFERENCAS) do
                local v = (atributos[d[1]] or 0) - (rival.atributos[d[1]] or 0)
                if v ~= 0 then
                    av.diferenca[#av.diferenca + 1] = { d[2], v, d[3] }
                end
            end
        end
    end
    local pontos = av.melhoria >= MELHORIA_MINIMA and av.melhoria or 0
    av.nota = pontos * COBRE_POR_PONTO_NIVEL * nivelAtual + av.venda
    cacheAvaliacao[id] = av
    return av
end

-- "+2 Agi +1 Sta -12 armadura": a diferença para o que está equipado
local function TextoDiferenca(av)
    local partes = {}
    for _, d in ipairs(av.diferenca or {}) do
        local nome, v, decimal = d[1], d[2], d[3]
        local numero
        if decimal then
            numero = (string.format("%+.1f", v):gsub("%.", ","))
        else
            numero = string.format("%+d", math.floor(v + (v > 0 and 0.5 or -0.5)))
        end
        partes[#partes + 1] = numero .. " " .. nome
    end
    return table.concat(partes, " ")
end

-- O que a recompensa vale, em poucas palavras, para a coluna da direita da dica
local function ResumoValor(av)
    if not av then
        return CINZA .. "carregando...|r"
    end
    if av.melhoria >= MELHORIA_MINIMA then
        local texto = TextoDiferenca(av)
        return VERDE .. "melhoria" .. (texto ~= "" and (": " .. texto) or "") .. "|r"
    end
    local venda = "sem valor de venda"
    if av.venda > 0 then
        venda = (av.fonte == "leilão" and "leilão " or "vende ") .. K.Moeda(av.venda)
    end
    if av.nivelAlto then
        return CINZA .. "pede nível " .. av.nivelAlto .. " · " .. venda .. "|r"
    elseif av.usavel == false then
        return CINZA .. "o druida não usa · " .. venda .. "|r"
    elseif av.usavel then
        return CINZA .. "não melhora · " .. venda .. "|r"
    end
    return CINZA .. venda .. "|r"
end

-- Recompensas da quest, da melhor nota para a pior (item ainda não carregado vai para o fim)
local function RecompensasOrdenadas(id)
    local lista = {}
    for _, item in ipairs(recompensas[id] or {}) do
        local av = AvaliarItem(item)
        lista[#lista + 1] = { item = item, av = av, nota = av and av.nota or -1 }
    end
    table.sort(lista, function(a, b)
        if a.nota ~= b.nota then
            return a.nota > b.nota
        end
        return a.item < b.item
    end)
    return lista
end

-- A quest vale a melhor recompensa (quase sempre se escolhe uma)
function LootDaQuest(id)
    local melhor = RecompensasOrdenadas(id)[1]
    if not (melhor and melhor.av) then
        return { nota = 0, venda = 0, melhoria = 0 }
    end
    local av = melhor.av
    return { nota = av.nota, venda = av.venda, melhoria = av.melhoria, item = melhor.item }
end

-- Ícones das recompensas, da melhor para a pior, para o canto direito da linha da quest; o "+"
-- verde marca melhoria para o Feral
local function IconesDeRecompensa(id)
    local lista = RecompensasOrdenadas(id)
    if #lista == 0 then
        return ""
    end
    local partes = {}
    for n = 1, math.min(3, #lista) do
        local icone = Instantaneo(lista[n].item)
        if icone then
            local melhora = lista[n].av and lista[n].av.melhoria >= MELHORIA_MINIMA
            partes[#partes + 1] = (melhora and (VERDE .. "+|r") or "") .. "|T" .. icone .. ":14:14|t"
        end
    end
    if #lista > 3 then
        partes[#partes + 1] = CINZA .. "(+" .. (#lista - 3) .. ")|r"
    end
    return table.concat(partes, "")
end

---------------------------------------------------------------------------
-- Cadeia de quests
---------------------------------------------------------------------------

local function Elegivel(id)
    local d = Dados(id)
    return d and Permite(d.racas, meuBitRaca) and Permite(d.classes, meuBitClasse)
end

local function NomeDaQuest(id)
    local d = Dados(id)
    return d and d.nome or ("Quest " .. id)
end

-- Para trás pelos pré-requisitos (prefere o que você já fez); para frente pela próxima da cadeia,
-- pela quest que esta abre (migalha) e por quem tem esta como pré-requisito (a de menor nível)
local function Cadeia(id)
    local c = cacheCadeia[id]
    if c then
        return c
    end
    local visto = { [id] = true }
    local antes, atual = {}, id
    while #antes < MAX_CADEIA do
        local d = Dados(atual)
        if not d then
            break
        end
        local escolhida
        for _, lista in ipairs({ d.preUma or {}, d.preGrupo or {} }) do
            for _, pre in ipairs(lista) do
                if not visto[pre] and Elegivel(pre) then
                    if feitasAtuais[pre] then
                        escolhida = pre
                        break
                    end
                    escolhida = escolhida or pre
                end
            end
            if escolhida and feitasAtuais[escolhida] then
                break
            end
        end
        if not escolhida then
            break
        end
        visto[escolhida] = true
        table.insert(antes, 1, escolhida)
        atual = escolhida
    end

    local depois = {}
    atual = id
    while #depois < MAX_CADEIA do
        local e = Extra(atual)
        local candidatas = {}
        if type(e.proxima) == "number" then
            candidatas[#candidatas + 1] = e.proxima
        end
        if type(e.migalha) == "number" then
            candidatas[#candidatas + 1] = e.migalha
        end
        local abertas = {}
        for _, s in ipairs(sucessores[atual] or {}) do
            abertas[#abertas + 1] = s
        end
        table.sort(abertas, function(a, b)
            local na, nb = nivelQuest[a] or 0, nivelQuest[b] or 0
            if na ~= nb then
                return na < nb
            end
            return a < b
        end)
        for _, s in ipairs(abertas) do
            candidatas[#candidatas + 1] = s
        end
        local seguinte
        for _, s in ipairs(candidatas) do
            if not visto[s] and Elegivel(s) then
                seguinte = s
                break
            end
        end
        if not seguinte then
            break
        end
        visto[seguinte] = true
        depois[#depois + 1] = seguinte
        atual = seguinte
    end

    local lista = {}
    for _, q in ipairs(antes) do
        lista[#lista + 1] = q
    end
    lista[#lista + 1] = id
    local indice = #lista
    for _, q in ipairs(depois) do
        lista[#lista + 1] = q
    end
    c = { lista = lista, indice = indice }
    cacheCadeia[id] = c
    return c
end

---------------------------------------------------------------------------
-- Dicas (mouse parado numa linha ou num marcador)
---------------------------------------------------------------------------

-- Abre a dica para o lado com mais espaço na tela
local function Ancora(dono)
    local x = dono:GetCenter()
    if not x then
        return "ANCHOR_RIGHT"
    end
    local escala = dono:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return (x * escala > UIParent:GetWidth() / 2) and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
end

local function CorDoNivel(nivel)
    if type(GetQuestDifficultyColor) == "function" and type(nivel) == "number" and nivel > 0 then
        local ok, cor = pcall(GetQuestDifficultyColor, nivel)
        if ok and type(cor) == "table" and type(cor.r) == "number" then
            return string.format("|cff%02x%02x%02x", math.floor(cor.r * 255 + 0.5),
                math.floor(cor.g * 255 + 0.5), math.floor(cor.b * 255 + 0.5))
        end
    end
    return "|cffffffff"
end

local function Rotulo(id)
    local nivel = nivelQuest[id] or 0
    return (nivel > 0 and ("[" .. nivel .. "] ") or "") .. NomeDaQuest(id)
end

local function TextoDoObjetivo(id)
    local texto = Extra(id).texto
    if type(texto) == "table" then
        local partes = {}
        for _, t in ipairs(texto) do
            if type(t) == "string" and t ~= "" then
                partes[#partes + 1] = t
            end
        end
        texto = table.concat(partes, " ")
    end
    if type(texto) ~= "string" or texto == "" then
        return nil
    end
    texto = texto:gsub("%$[Bb]", " ")
    texto = texto:gsub("%$[Nn]", UnitName("player") or "você")
    if #texto > 220 then
        texto = texto:sub(1, 217) .. "..."
    end
    return texto
end

local function LinhasDeObjetivo(q)
    if q.aceita and C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, lista = pcall(C_QuestLog.GetQuestObjectives, q.id)
        if ok and type(lista) == "table" and #lista > 0 then
            for _, o in ipairs(lista) do
                local texto = type(o) == "table" and o.text or nil
                if type(texto) == "string" and not K.Secreto(texto) and texto ~= "" then
                    local feito = o.finished
                    if not K.Secreto(feito) and feito == true then
                        GameTooltip:AddLine("  " .. texto, 0.5, 0.8, 0.5)
                    else
                        GameTooltip:AddLine("  " .. texto, 0.9, 0.9, 0.9)
                    end
                end
            end
            return
        end
    end
    local texto = TextoDoObjetivo(q.id)
    if texto then
        GameTooltip:AddLine(texto, 0.75, 0.75, 0.75, true)
    end
end

-- Cada recompensa, da melhor para a pior: ícone e nome à esquerda, o que vale à direita (melhoria
-- para o Feral, ou venda); com detalhe, mais uma linha com tipo, encaixe e atributos
local function LinhasDeRecompensa(id, recuo, limite, detalhe)
    if not recompensasProntas then
        GameTooltip:AddLine(recuo .. "lendo a base de recompensas...", 0.6, 0.6, 0.6)
        return
    end
    local lista = RecompensasOrdenadas(id)
    if #lista == 0 then
        GameTooltip:AddLine(recuo .. "nenhum item", 0.6, 0.6, 0.6)
        return
    end
    for n, r in ipairs(lista) do
        if n > limite then
            GameTooltip:AddLine(recuo .. "e mais " .. (#lista - limite), 0.6, 0.6, 0.6)
            break
        end
        local info = InfoItem(r.item)
        local icone = info.icone and ("|T" .. info.icone .. ":14:14|t ") or ""
        GameTooltip:AddDoubleLine(recuo .. icone .. info.cor .. info.nome .. "|r", ResumoValor(r.av),
            1, 1, 1, 1, 1, 1)
        if detalhe and info.descricao ~= "" then
            GameTooltip:AddLine(recuo .. "      " .. info.descricao, 0.6, 0.6, 0.6)
        end
    end
end

local function LinhasDaCadeia(q)
    local c = Cadeia(q.id)
    if #c.lista < 2 then
        return
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(string.format("Cadeia: %d quests (esta é a %dª)", #c.lista, c.indice), 1, 0.82, 0)
    for n, id in ipairs(c.lista) do
        local linha = n .. ". " .. Rotulo(id)
        if id == q.id then
            GameTooltip:AddDoubleLine(linha, "esta", 1, 0.82, 0, 1, 0.82, 0)
        elseif feitasAtuais[id] then
            GameTooltip:AddDoubleLine(linha, "feita", 0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
        else
            GameTooltip:AddDoubleLine(linha, aceitasAtuais[id] and "aceita" or "", 1, 1, 1, 0.6, 1, 0.6)
            LinhasDeRecompensa(id, "      ", 4)
        end
    end
end

local NOME_ETAPA = { pegar = "Pegar com %s", cumprir = "Cumprir os objetivos", entregar = "Entregar a %s" }
local COR_ETAPA = { pegar = { 1, 0.82, 0 }, cumprir = { 1, 1, 1 }, entregar = { 0.6, 1, 0.6 } }

local function DicaDaQuest(dono, i, q)
    GameTooltip:SetOwner(dono, Ancora(dono))
    GameTooltip:AddLine(q.nome, 1, 0.82, 0)
    local estado = (q.pronta and "pronta para entregar") or (q.aceita and "aceita") or "a pegar"
    GameTooltip:AddDoubleLine(CorDoNivel(q.nivel) .. "Nível " .. q.nivel .. "|r · " .. estado,
        "Bloco " .. i .. " (" .. CORES[i] .. ")", 1, 1, 1, 0.75, 0.75, 0.75)
    for _, p in ipairs(q.paradas or {}) do
        local quem = p.etapa == "pegar" and (q.pontos.quemDa or "?") or (q.pontos.quemRecebe or "?")
        local cor = COR_ETAPA[p.etapa]
        GameTooltip:AddDoubleLine(string.format(NOME_ETAPA[p.etapa], quem), "parada " .. p.numero,
            cor[1], cor[2], cor[3], 0.75, 0.75, 0.75)
    end
    LinhasDeObjetivo(q)
    if q.xp > 0 then
        GameTooltip:AddLine("XP: " .. Milhar(q.xp), 0.6, 0.8, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Recompensas", 1, 0.82, 0)
    LinhasDeRecompensa(q.id, "  ", MAX_ITENS_DICA, true)
    LinhasDaCadeia(q)
    GameTooltip:Show()
end

local function Nomedomapa(mapa)
    local info = mapa and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapa)
    return info and info.name or ""
end

local function DicaDoBloco(dono, i, bloco)
    GameTooltip:SetOwner(dono, Ancora(dono))
    GameTooltip:AddLine("Bloco " .. i .. " (" .. CORES[i] .. ")", 1, 0.82, 0)
    GameTooltip:AddLine(Nomedomapa(bloco.centro and bloco.centro.mapa or bloco.quests[1].centro.mapa), 1, 1, 1)
    GameTooltip:AddLine(string.format("%d quests · %d paradas · ~%d min · %s XP", #bloco.quests,
        #bloco.paradas, math.floor(bloco.minutos + 0.5), Milhar(bloco.xp)), 0.8, 0.8, 0.8)
    local melhorias = ""
    if bloco.melhorias > 0 then
        melhorias = VERDE .. bloco.melhorias .. (bloco.melhorias == 1 and " melhoria" or " melhorias")
            .. " para o Feral|r · "
    end
    GameTooltip:AddLine("Loot: " .. melhorias .. "venda " .. K.Moeda(bloco.venda), 0.8, 0.8, 0.8)
    if i == IndiceAberto() then
        GameTooltip:AddLine("Clique para fechar.", 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine("Clique para abrir e ver a rota no mapa.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function MostrarDica(dono, mostrar)
    dica = { dono = dono, mostrar = mostrar }
    mostrar()
end

local refazendo = false

-- Refaz a dica aberta (item que chegou do servidor, recompensas que terminaram de carregar)
local function RefazerDica()
    if refazendo or not dica then
        return
    end
    refazendo = true
    C_Timer.After(0.15, function()
        refazendo = false
        if dica and GameTooltip:IsShown() and GameTooltip:GetOwner() == dica.dono then
            local ok, erro = pcall(dica.mostrar)
            if not ok then
                Anotar("na dica", erro)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Quadro com a lista dos blocos (sanfona)
---------------------------------------------------------------------------

local quadro = CreateFrame("Frame", "KitDruidaBlocos", UIParent)
quadro:SetSize(LARGURA, 60)
quadro:Hide()
local fundo = quadro:CreateTexture(nil, "BACKGROUND")
fundo:SetAllPoints(quadro)
fundo:SetColorTexture(0, 0, 0, 0.6)
local titulo = quadro:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
titulo:SetPoint("TOPLEFT", quadro, "TOPLEFT", 8, -6)
titulo:SetText("Blocos de quests")
-- botão da ordem dos blocos (loot ou XP), no canto do título
local botaoOrdem = CreateFrame("Button", nil, quadro)
botaoOrdem:SetSize(78, 14)
botaoOrdem:SetPoint("TOPRIGHT", quadro, "TOPRIGHT", -6, -4)
botaoOrdem:SetHighlightTexture(REALCE, "ADD")
botaoOrdem.texto = botaoOrdem:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
botaoOrdem.texto:SetPoint("RIGHT", botaoOrdem, "RIGHT", 0, 0)
botaoOrdem.texto:SetJustifyH("RIGHT")
local situacao = quadro:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
situacao:SetPoint("RIGHT", botaoOrdem, "LEFT", -6, 0)
situacao:SetJustifyH("RIGHT")
local separador = quadro:CreateTexture(nil, "ARTWORK")
separador:SetColorTexture(1, 0.82, 0, 0.25)
separador:SetHeight(1)
separador:SetPoint("TOPLEFT", quadro, "TOPLEFT", 6, -19)
separador:SetPoint("TOPRIGHT", quadro, "TOPRIGHT", -6, -19)
local mensagem = quadro:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
mensagem:SetPoint("TOPLEFT", quadro, "TOPLEFT", 8, -TOPO)
mensagem:SetWidth(LARGURA - 16)
mensagem:SetJustifyH("LEFT")
mensagem:SetJustifyV("TOP")
mensagem:SetText("Lendo a base...")

K.RegistrarQuadro("blocos", quadro, {
    padrao = { "TOPRIGHT", "TOPRIGHT", -220, -240 },
    rotulo = "Blocos de quests",
    visivelSempre = true,
})

local function TextoDaOrdem()
    botaoOrdem.texto:SetText(OURO .. (Opcoes().ordem == "xp" and "ordem: XP" or "ordem: loot") .. "|r")
end

botaoOrdem:SetScript("OnClick", function()
    local opcoes = Opcoes()
    opcoes.ordem = opcoes.ordem == "xp" and "loot" or "xp"
    TextoDaOrdem()
    GameTooltip:Hide()
    B.Recalcular()
end)
botaoOrdem:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, Ancora(self))
    GameTooltip:AddLine("Ordem dos blocos", 1, 0.82, 0)
    GameTooltip:AddLine("Loot: melhorias para o Feral e valor de venda das recompensas, por minuto.", 1, 1, 1, true)
    GameTooltip:AddLine("XP: experiência por minuto.", 1, 1, 1, true)
    GameTooltip:AddLine("Clique para trocar.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
botaoOrdem:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

local linhas = {}

-- Uma linha da lista (cabeçalho de bloco ou quest). Arrastar com Shift move o quadro inteiro.
local function Linha(n)
    local l = linhas[n]
    if l then
        return l
    end
    l = CreateFrame("Button", nil, quadro)
    l:SetHeight(ALTURA_LINHA)
    l:SetHighlightTexture(REALCE, "ADD")
    l.seta = l:CreateTexture(nil, "ARTWORK")
    l.seta:SetSize(12, 12)
    l.seta:SetPoint("LEFT", l, "LEFT", 2, 0)
    l.icone = l:CreateTexture(nil, "ARTWORK")
    l.numero = l:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l.numero:SetJustifyH("RIGHT")
    l.numero:SetWidth(18)
    l.numero:SetPoint("LEFT", l, "LEFT", 12, 0)
    l.direita = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.direita:SetPoint("RIGHT", l, "RIGHT", -4, 0)
    l.direita:SetJustifyH("RIGHT")
    l.texto = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.texto:SetJustifyH("LEFT")
    l.texto:SetWordWrap(false)
    l:RegisterForClicks("LeftButtonUp")
    l:RegisterForDrag("LeftButton")
    l:SetScript("OnDragStart", function(self)
        self.movendo = K.movendo or IsShiftKeyDown()
        local arrastar = quadro:GetScript("OnDragStart")
        if self.movendo and arrastar then
            arrastar(quadro)
        end
    end)
    l:SetScript("OnDragStop", function(self)
        local soltar = quadro:GetScript("OnDragStop")
        if self.movendo and soltar then
            soltar(quadro)
        end
        self.movendo = false
    end)
    l:SetScript("OnClick", function(self)
        if self.aoClicar then
            self.aoClicar()
        end
    end)
    l:SetScript("OnEnter", function(self)
        if self.dica then
            local ok, erro = pcall(MostrarDica, self, self.dica)
            if not ok then
                Anotar("na dica", erro)
            end
        end
    end)
    l:SetScript("OnLeave", function()
        dica = nil
        GameTooltip:Hide()
    end)
    linhas[n] = l
    return l
end

local function PorTexto(l, esquerda)
    l.texto:ClearAllPoints()
    l.texto:SetPoint("LEFT", l, "LEFT", esquerda, 0)
    l.texto:SetPoint("RIGHT", l.direita, "LEFT", -6, 0)
end

local function MontarCabecalho(l, i, bloco, aberto)
    l.seta:SetTexture(aberto and SETA_ABERTA or SETA_FECHADA)
    l.seta:Show()
    l.icone:ClearAllPoints()
    l.icone:SetPoint("LEFT", l, "LEFT", 17, 0)
    l.icone:SetSize(14, 14)
    l.icone:SetTexture(Textura(i))
    l.icone:Show()
    l.numero:Hide()
    local minutos = math.floor(bloco.minutos + 0.5)
    if Opcoes().ordem == "xp" then
        l.direita:SetText(string.format("%s%s XP · ~%d min|r", CINZA, XPCurto(bloco.xp), minutos))
    else
        local melhorias = bloco.melhorias > 0 and (VERDE .. "+" .. bloco.melhorias .. "|r ") or ""
        l.direita:SetText(string.format("%s%s%s · ~%d min|r", melhorias, CINZA, K.Moeda(bloco.venda), minutos))
    end
    PorTexto(l, 35)
    local zona = Nomedomapa(bloco.centro and bloco.centro.mapa or bloco.quests[1].centro.mapa)
    l.texto:SetText(string.format("%sBloco %d|r %s%s|r", OURO, i, CINZA, zona))
    l.aoClicar = function()
        if i == IndiceAberto() then
            escolha = { modo = "nenhum" }
        else
            Fixar(i)
        end
        GameTooltip:Hide()
        DesenharLista()
        DesenharPinos()
    end
    l.dica = function()
        DicaDoBloco(l, i, bloco)
    end
end

local function MontarQuest(l, i, q)
    l.seta:Hide()
    l.numero:SetText(q.primeira or "")
    l.numero:Show()
    l.icone:ClearAllPoints()
    l.icone:SetPoint("LEFT", l, "LEFT", 34, 0)
    l.icone:SetSize(12, 12)
    l.icone:SetTexture((q.pronta and MARCA_ENTREGAR) or (q.aceita and MARCA_ACEITA) or MARCA_PEGAR)
    l.icone:Show()
    l.direita:SetText(IconesDeRecompensa(q.id))
    PorTexto(l, 50)
    local nivel = (q.nivel and q.nivel > 0) and ("[" .. q.nivel .. "] ") or ""
    l.texto:SetText(CorDoNivel(q.nivel) .. nivel .. q.nome .. "|r")
    l.aoClicar = nil
    l.dica = function()
        DicaDaQuest(l, i, q)
    end
end

function DesenharLista()
    for _, l in ipairs(linhas) do
        l:Hide()
        l.aoClicar, l.dica = nil, nil
    end
    situacao:SetText(progressoRecompensas or "")
    TextoDaOrdem()
    local aviso
    if not TemBase() then
        aviso = "Falta o QuestieDB na pasta de addons."
    elseif not HBD then
        aviso = "Faltou a biblioteca de mapa (HereBeDragons)."
    elseif not varrido then
        aviso = progressoBase or "Lendo a base..."
    elseif #blocos == 0 then
        aviso = "Nenhuma quest do seu nível por perto."
    end
    if aviso then
        mensagem:SetText(aviso)
        mensagem:Show()
        quadro:SetHeight(TOPO + mensagem:GetStringHeight() + 8)
        return
    end
    mensagem:Hide()

    local aberto = IndiceAberto()
    if aberto and escolha.modo == "fixo" then
        Fixar(aberto)
    end
    local n, y = 0, -TOPO + 2
    local function Proxima()
        n = n + 1
        local l = Linha(n)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", quadro, "TOPLEFT", 4, y)
        l:SetPoint("TOPRIGHT", quadro, "TOPRIGHT", -4, y)
        y = y - ALTURA_LINHA
        return l
    end
    for i, bloco in ipairs(blocos) do
        local l = Proxima()
        MontarCabecalho(l, i, bloco, i == aberto)
        l:Show()
        if i == aberto then
            for _, q in ipairs(bloco.quests) do
                local lq = Proxima()
                MontarQuest(lq, i, q)
                lq:Show()
            end
        end
    end
    quadro:SetHeight(-y + 6)

    -- a dica aberta numa linha que mudou de conteúdo é refeita (ou fechada, se a linha sumiu)
    local dono = GameTooltip:IsShown() and GameTooltip:GetOwner()
    for _, l in ipairs(linhas) do
        if dono == l then
            if l:IsShown() and l.dica and l:IsMouseOver() then
                local ok, erro = pcall(MostrarDica, l, l.dica)
                if not ok then
                    Anotar("na dica", erro)
                end
            else
                dica = nil
                GameTooltip:Hide()
            end
        end
    end
end

---------------------------------------------------------------------------
-- Marcadores próprios no mapa e no minimapa (sem a HereBeDragons-Pins)
---------------------------------------------------------------------------

local LerCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
local tela, relogio
local pinosMapa, livresMapa, pinosMini, livresMini = {}, {}, {}, {}
local mapaSujo = true
local ultimoMapa, ultimaEscala, ultimaLargura

local function DescreverAcao(acao)
    local q = acao.q
    local nome = ((q.nivel and q.nivel > 0) and ("[" .. q.nivel .. "] ") or "") .. q.nome
    if acao.etapa == "pegar" then
        return "Pegar: " .. nome .. " (com " .. (q.pontos.quemDa or "?") .. ")", 1, 0.82, 0
    elseif acao.etapa == "entregar" then
        return "Entregar: " .. nome .. " (a " .. (q.pontos.quemRecebe or "?") .. ")", 0.6, 1, 0.6
    end
    return "Cumprir: " .. nome, 1, 1, 1
end

local function DicaDoPino(f)
    local d = f.dados
    if not d then
        return
    end
    GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
    if d.tipo == "parada" then
        GameTooltip:AddLine(string.format("Bloco %d (%s) · parada %d de %d", d.bloco, CORES[d.bloco],
            d.parada.numero, d.total), 1, 0.82, 0)
        for _, acao in ipairs(d.parada.acoes) do
            local texto, r, g, b = DescreverAcao(acao)
            GameTooltip:AddLine(texto, r, g, b, true)
        end
    else
        local q = d.q
        GameTooltip:AddLine("Bloco " .. d.bloco .. " (" .. CORES[d.bloco] .. ")", 1, 0.82, 0)
        local nivel = (q.nivel and q.nivel > 0) and ("[" .. q.nivel .. "] ") or ""
        GameTooltip:AddLine(nivel .. q.nome, 1, 1, 1)
        if q.pronta then
            GameTooltip:AddLine("Pronta: entregar a " .. (q.pontos.quemRecebe or "?") .. ".", 0.6, 1, 0.6, true)
        elseif q.aceita then
            GameTooltip:AddLine("Aceita: o visto marca a área dos objetivos.", 0.6, 1, 0.6, true)
        else
            GameTooltip:AddLine("Pegar com " .. (q.pontos.quemDa or "?") .. ".", 1, 0.82, 0, true)
        end
        GameTooltip:AddLine("Abra o bloco na lista para ver a rota numerada.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function NovoPino(pai)
    local f = CreateFrame("Frame", nil, pai)
    f:SetSize(18, 18)
    f.icone = f:CreateTexture(nil, "ARTWORK")
    f.icone:SetPoint("CENTER", f, "CENTER")
    f.marca = f:CreateTexture(nil, "OVERLAY")
    f.marca:SetSize(11, 11)
    f.marca:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 4, -4)
    f.numero = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.numero:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 4, -3)
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        local ok, erro = pcall(DicaDoPino, self)
        if not ok then
            Anotar("na dica do marcador", erro)
        end
    end)
    f:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    f:Hide()
    return f
end

local function PinoDe(lista, livres, pai, tamanho, fonte)
    local f = table.remove(livres) or NovoPino(pai)
    f:SetSize(tamanho, tamanho)
    f.icone:SetSize(tamanho - 2, tamanho - 2)
    f.numero:SetFontObject(fonte)
    lista[#lista + 1] = f
    return f
end

local function Vestir(f, i, marca, numero, ponto, dados)
    f.icone:SetTexture(Textura(i))
    if marca then
        f.marca:SetTexture(marca)
        f.marca:Show()
    else
        f.marca:Hide()
    end
    if numero then
        f.numero:SetText(numero)
        f.numero:Show()
    else
        f.numero:Hide()
    end
    f.ponto, f.dados = ponto, dados
    f.naBorda, f.prioridade = nil, 0
    f:SetAlpha(1)
end

local function LimparPinos()
    for _, f in ipairs(pinosMapa) do
        f:Hide()
        f.ponto, f.dados = nil, nil
        livresMapa[#livresMapa + 1] = f
    end
    pinosMapa = {}
    for _, f in ipairs(pinosMini) do
        f:Hide()
        f.ponto, f.dados = nil, nil
        livresMini[#livresMini + 1] = f
    end
    pinosMini = {}
end

local function MapaDeZona(mapa)
    local dados = mapa and HBD and HBD.mapData and HBD.mapData[mapa]
    local tipo = dados and dados.mapType
    local T = Enum and Enum.UIMapType
    if T then
        return tipo == T.Zone or tipo == T.Dungeon or tipo == T.Micro
    end
    return tipo == 3 or tipo == 4 or tipo == 5
end

-- Cada pino fica no canto da tela do mapa, na posição do ponto no mapa aberto, com a escala
-- inversa à do zoom (o tamanho na tela não muda). Só em mapa de zona; no continente, nada.
local function PosicionarNoMapa()
    if not (tela and WorldMapFrame) then
        return
    end
    local mapa = WorldMapFrame:GetMapID()
    local zona = MapaDeZona(mapa)
    local escala = tela:GetScale()
    local largura, altura = tela:GetSize()
    if not escala or escala <= 0 then
        escala = 1
    end
    local nivel = math.min(tela:GetFrameLevel() + 1500, 9000)
    for _, f in ipairs(pinosMapa) do
        local x, y
        if zona and f.ponto then
            x, y = HBD:GetZoneCoordinatesFromWorldInstance(f.ponto.mx, f.ponto.my, f.ponto.inst, mapa)
        end
        if x and y then
            f:SetScale(1 / escala)
            f:ClearAllPoints()
            f:SetPoint("CENTER", tela, "TOPLEFT", x * largura * escala, -y * altura * escala)
            f:SetFrameLevel(nivel + (f.prioridade or 0))
            f:Show()
        else
            f:Hide()
        end
    end
end

-- Roda enquanto o mapa está aberto: só lê o mapa e o zoom, e reposiciona quando mudam
local function VigiarMapa()
    local mapa = WorldMapFrame:GetMapID()
    local escala = tela:GetScale()
    local largura = tela:GetWidth()
    if mapaSujo or mapa ~= ultimoMapa or escala ~= ultimaEscala or largura ~= ultimaLargura then
        mapaSujo = false
        ultimoMapa, ultimaEscala, ultimaLargura = mapa, escala, largura
        PosicionarNoMapa()
    end
end

local function EsconderMini()
    for _, f in ipairs(pinosMini) do
        f:Hide()
    end
end

-- Mesma conta da HereBeDragons: distância até você, girada se o minimapa gira, na escala do raio
-- de visão; o pino com naBorda fica preso na borda quando sai do alcance (a próxima parada)
local function PosicionarNoMinimapa()
    if #pinosMini == 0 or not (HBD and Minimap) then
        return
    end
    local px, py, instancia = HBD:GetPlayerWorldPosition()
    if K.Secreto(px) or K.Secreto(py) or not (px and py) then
        EsconderMini()
        return
    end
    local seno, cosseno
    if LerCVar and LerCVar("rotateMinimap") == "1" then
        local direcao = GetPlayerFacing and GetPlayerFacing()
        if K.Secreto(direcao) or type(direcao) ~= "number" then
            EsconderMini()
            return
        end
        seno, cosseno = math.sin(direcao), math.cos(direcao)
    end
    local raio = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
    if K.Secreto(raio) or type(raio) ~= "number" or raio <= 0 then
        raio = RAIO_MINIMAPA[Minimap:GetZoom()] or 233.3
    end
    local metadeLargura, metadeAltura = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
    for _, f in ipairs(pinosMini) do
        local p = f.ponto
        if p and p.inst == instancia then
            local dx, dy = px - p.mx, py - p.my
            if seno then
                dx, dy = dx * cosseno - dy * seno, dx * seno + dy * cosseno
            end
            local rx, ry = dx / raio, dy / raio
            local distancia = (rx * rx + ry * ry) / 0.81
            local fora = distancia > 1
            if fora and f.naBorda then
                local r = math.sqrt(distancia)
                rx, ry = rx / r, ry / r
            end
            if not fora or f.naBorda then
                f:ClearAllPoints()
                f:SetPoint("CENTER", Minimap, "CENTER", rx * metadeLargura, -ry * metadeAltura)
                f:SetAlpha(fora and 0.7 or 1)
                f:Show()
            else
                f:Hide()
            end
        else
            f:Hide()
        end
    end
end

-- Quadros-vigia nossos, filhos do mapa e do minimapa: só rodam com eles à vista
local function PrepararMapa()
    if WorldMapFrame and not tela then
        local ok, canvas = pcall(function()
            return (WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas())
                or (WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child)
        end)
        if ok and canvas then
            tela = canvas
            local vigia = CreateFrame("Frame", nil, WorldMapFrame)
            vigia:SetScript("OnUpdate", function(self)
                local certo, erro = pcall(VigiarMapa)
                if not certo then
                    self:SetScript("OnUpdate", nil)
                    Anotar("nos marcadores do mapa", erro)
                end
            end)
        end
    end
    if Minimap and not relogio then
        relogio = CreateFrame("Frame", nil, Minimap)
        local acumulado = 0
        relogio:SetScript("OnUpdate", function(self, passo)
            acumulado = acumulado + (passo or 0)
            if acumulado < 0.05 then
                return
            end
            acumulado = 0
            local certo, erro = pcall(PosicionarNoMinimapa)
            if not certo then
                self:SetScript("OnUpdate", nil)
                Anotar("nos marcadores do minimapa", erro)
            end
        end)
    end
end

-- Bloco aberto: uma marca numerada por parada, no mapa e no minimapa (a parada 1 fica presa na
-- borda do minimapa quando longe). Outros blocos: só no mapa, mais claros, "!" para pegar, visto
-- para aceita e "?" para pronta.
function DesenharPinos()
    LimparPinos()
    if not (HBD and Opcoes().pinos) then
        return
    end
    local aberto = IndiceAberto()
    for i, bloco in ipairs(blocos) do
        if i == aberto then
            for _, parada in ipairs(bloco.paradas or {}) do
                local dados = { tipo = "parada", bloco = i, parada = parada, total = #bloco.paradas }
                if tela then
                    local f = PinoDe(pinosMapa, livresMapa, tela, 20, "NumberFontNormal")
                    Vestir(f, i, nil, parada.numero, parada.ponto, dados)
                    f.prioridade = 10
                end
                if Minimap then
                    local m = PinoDe(pinosMini, livresMini, Minimap, 15, "NumberFontNormalSmall")
                    Vestir(m, i, nil, parada.numero, parada.ponto, dados)
                    m.naBorda = parada.numero == 1
                end
            end
        elseif tela then
            for _, q in ipairs(bloco.quests) do
                local ponto, marca
                if q.pronta then
                    ponto, marca = q.pontos.fim, MARCA_ENTREGAR
                elseif q.aceita then
                    ponto, marca = q.pontos.areas[1] or q.pontos.fim, MARCA_ACEITA
                else
                    ponto, marca = q.pontos.inicio, MARCA_PEGAR
                end
                if ponto then
                    local f = PinoDe(pinosMapa, livresMapa, tela, 16, "NumberFontNormal")
                    Vestir(f, i, marca, nil, ponto, { tipo = "quest", bloco = i, q = q })
                    f:SetAlpha(0.7)
                end
            end
        end
    end
    mapaSujo = true
    if WorldMapFrame and WorldMapFrame:IsShown() then
        PosicionarNoMapa()
    end
    PosicionarNoMinimapa()
end

---------------------------------------------------------------------------
-- Cálculo
---------------------------------------------------------------------------

local avisouErro = false

function MostrarErro(etapa, erro)
    for _, l in ipairs(linhas) do
        l:Hide()
    end
    mensagem:SetText("Erro " .. etapa .. ":\n" .. tostring(erro))
    mensagem:Show()
    quadro:SetHeight(TOPO + mensagem:GetStringHeight() + 8)
    Anotar(etapa, erro)
    if not avisouErro then
        avisouErro = true
        print(K.PREFIXO .. "|cffff5050Blocos de quests, erro " .. etapa .. ":|r " .. tostring(erro))
    end
end

-- Pede ao servidor os itens de recompensa dos blocos, para a dica já abrir com nome e atributos
local function PedirItensDosBlocos()
    if not (recompensasProntas and PedirItem) then
        return
    end
    for _, bloco in ipairs(blocos) do
        for _, q in ipairs(bloco.quests) do
            for _, item in ipairs(recompensas[q.id] or {}) do
                pcall(PedirItem, item)
            end
        end
    end
end

local function RecalcularInterno()
    if not (TemBase() and HBD and varrido) then
        DesenharLista()
        return
    end
    if InCombatLockdown() then
        emCombatePendente = true
        return
    end
    local px, py, instancia = HBD:GetPlayerWorldPosition()
    if K.Secreto(px) or K.Secreto(py) then
        return
    end
    local nivel = UnitLevel("player")
    if not (px and py and type(nivel) == "number") then
        return
    end
    local jogador = { mx = px, my = py, inst = instancia }
    local _, _, idRaca = UnitRace("player")
    local _, _, idClasse = UnitClass("player")
    meuBitRaca = BitDaRaca(idRaca)
    meuBitClasse = type(idClasse) == "number" and 2 ^ (idClasse - 1) or 0
    cacheCadeia, cacheAvaliacao = {}, {}
    nivelAtual, faltamItens = nivel, false
    local ok, lista = pcall(Candidatas, jogador, nivel)
    if not ok then
        MostrarErro("ao ler a base", lista)
        return
    end
    blocos = MontarBlocos(jogador, lista)
    PedirItensDosBlocos()
    DesenharLista()
    DesenharPinos()
end

function B.Recalcular()
    agendado = false
    local ok, erro = pcall(RecalcularInterno)
    if not ok then
        MostrarErro("no cálculo", erro)
    end
end

function B.Agendar(segundos)
    if agendado then
        return
    end
    agendado = true
    C_Timer.After(segundos or 2, B.Recalcular)
end

function B.AtualizarPinos()
    local ok, erro = pcall(DesenharPinos)
    if not ok then
        Anotar("nos marcadores", erro)
    end
end

---------------------------------------------------------------------------
-- Leitura da base, em pedaços, para não travar o jogo
---------------------------------------------------------------------------

-- Recompensas: o ItemDB diz, para cada item, de que quests ele é recompensa; aqui se inverte
local function VarrerRecompensas()
    local ok, ids = pcall(ItemDB.GetAllIds)
    if not ok or type(ids) ~= "table" then
        recompensasProntas = true
        Anotar("na leitura das recompensas", "o QuestieDB não entregou a lista de itens")
        return
    end
    local total, i = #ids, 0
    local function Passo()
        local fim = math.min(i + ITENS_POR_QUADRO, total)
        for k = i + 1, fim do
            local item = ids[k]
            if type(item) == "number" then
                local quests = Ler(ItemDB, "questRewards", item)
                if type(quests) == "table" then
                    for _, q in ipairs(quests) do
                        local lista = recompensas[q]
                        if not lista then
                            lista = {}
                            recompensas[q] = lista
                        end
                        lista[#lista + 1] = item
                    end
                end
            end
        end
        i = fim
        return i >= total
    end
    local leitor = CreateFrame("Frame")
    leitor:SetScript("OnUpdate", function(self)
        local certo, pronto = pcall(Passo)
        if not certo then
            self:SetScript("OnUpdate", nil)
            recompensasProntas, progressoRecompensas = true, nil
            situacao:SetText("")
            Anotar("na leitura das recompensas", pronto)
        elseif pronto then
            self:SetScript("OnUpdate", nil)
            recompensasProntas, progressoRecompensas = true, nil
            PedirItensDosBlocos()
            DesenharLista()
            RefazerDica()
            B.Agendar(1)   -- com as recompensas conhecidas, a ordem por loot passa a valer
        else
            progressoRecompensas = string.format("recompensas %d%%", math.floor(i * 100 / math.max(1, total)))
            situacao:SetText(progressoRecompensas)
        end
    end)
end

-- Quests: nível, nível mínimo e quem abre quem (o inverso dos pré-requisitos, para a cadeia)
local function Varrer()
    local ok, ids = pcall(QuestDB.GetAllIds)
    if not ok or type(ids) ~= "table" then
        progressoBase = "O QuestieDB não entregou a lista de quests."
        DesenharLista()
        return
    end
    idsBase = ids
    local total, i = #idsBase, 0
    local function Passo()
        local fim = math.min(i + POR_QUADRO, total)
        for k = i + 1, fim do
            local id = idsBase[k]
            if type(id) == "number" then
                local nq, nm = Ler(QuestDB, "questLevel", id), Ler(QuestDB, "requiredLevel", id)
                nivelQuest[id] = type(nq) == "number" and nq or 0
                nivelMin[id] = type(nm) == "number" and nm or 0
                for _, campo in ipairs(CAMPOS_PRE) do
                    local pres = Ler(QuestDB, campo, id)
                    if type(pres) == "table" then
                        for _, pre in ipairs(pres) do
                            if type(pre) == "number" then
                                local lista = sucessores[pre]
                                if not lista then
                                    lista = {}
                                    sucessores[pre] = lista
                                end
                                lista[#lista + 1] = id
                            end
                        end
                    end
                end
            end
        end
        i = fim
        progressoBase = string.format("Lendo a base de quests (%d de %d)...", i, total)
        return i >= total
    end
    local leitor = CreateFrame("Frame")
    leitor:SetScript("OnUpdate", function(self)
        local certo, pronto = pcall(Passo)
        if not certo then
            self:SetScript("OnUpdate", nil)
            MostrarErro("na leitura da base", pronto)
        elseif pronto then
            self:SetScript("OnUpdate", nil)
            varrido, progressoBase = true, nil
            B.Recalcular()
            VarrerRecompensas()
        else
            DesenharLista()
        end
    end)
end

K.AoEntrar(function()
    HBD = LibStub and LibStub("HereBeDragons-2.0", true)
    if HBD then
        PrepararMapa()
    end
    if not (HBD and TemBase()) then
        DesenharLista()
        return
    end
    PrepararApoio()
    Varrer()
end)

local eventos = CreateFrame("Frame")
for _, evento in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_LEVEL_UP",
    "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED", "QUEST_LOG_UPDATE", "GET_ITEM_INFO_RECEIVED",
    "PLAYER_EQUIPMENT_CHANGED" }) do
    pcall(eventos.RegisterEvent, eventos, evento)
end
eventos:SetScript("OnEvent", function(_, evento)
    if evento == "GET_ITEM_INFO_RECEIVED" then
        RefazerDica()
        -- chegou item que faltava na nota: refaz o cálculo (uma vez só, pelo agendamento)
        if faltamItens and varrido then
            B.Agendar(3)
        end
        return
    end
    if evento == "PLAYER_EQUIPMENT_CHANGED" then
        equipado, cacheAvaliacao = {}, {}
    end
    if not varrido then
        return
    end
    if evento == "PLAYER_REGEN_ENABLED" then
        if emCombatePendente then
            emCombatePendente = false
            B.Agendar(1)
        end
    elseif evento == "QUEST_LOG_UPDATE" then
        B.Agendar(5)
    else
        B.Agendar(2)
    end
end)

-- De tempos em tempos, porque você anda e o que fica perto muda
C_Timer.NewTicker(45, function()
    if varrido then
        B.Agendar(1)
    end
end)
