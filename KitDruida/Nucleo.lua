-- Kit do Druida: núcleo comum aos módulos.
-- Guarda a configuração (KitDruidaDB), cuida dos quadros que se movem e mudam de tamanho e
-- reúne as funções usadas por mais de um módulo.
--
-- Regra do Forever seguida em todo o kit: em combate o jogo esconde dos addons parte dos
-- valores ("secret") e às vezes recusa leituras com erro; por isso as leituras passam por
-- pcall e os valores por issecretvalue antes de qualquer comparação.

local NOME, K = ...
K.NOME = NOME
K.PREFIXO = "|cffffd200Kit do Druida:|r "
K.quadros = {}
K.movendo = false

local PADRAO = {
    quadros = {},
    contador = { buffs = { motw = true, thorns = true, comida = true, rested = true }, som = true },
    erva = { ligado = true, som = true },
    venda = { cinzas = true },
    painel = {},
    minimapa = { angulo = 225 },
}

local carregar, entrar = {}, {}

---------------------------------------------------------------------------
-- Registro de erros: todo erro de Lua do jogo, de qualquer addon, vai para KitDruidaDB.erros
-- (texto e pilha, os 30 primeiros distintos, com quantas vezes cada um se repetiu), para ser
-- lido fora do jogo no arquivo de dados do Kit. A lista recomeça a cada entrada no jogo, e o
-- tratador de erros anterior continua sendo chamado.
---------------------------------------------------------------------------

local errosDaSessao, errosVistos = {}, {}

local function GuardarErro(texto)
    local chave = texto:sub(1, 240)
    local item = errosVistos[chave]
    if item then
        item.vezes = item.vezes + 1
        return
    end
    if #errosDaSessao >= 30 then
        return
    end
    item = { quando = date("%d/%m %H:%M:%S"), texto = texto, vezes = 1 }
    errosVistos[chave] = item
    errosDaSessao[#errosDaSessao + 1] = item
end
K.GuardarErro = GuardarErro

if seterrorhandler and geterrorhandler then
    local anterior = geterrorhandler()
    seterrorhandler(function(mensagem, ...)
        local pilha = debugstack and debugstack(3, 8, 0) or ""
        pcall(GuardarErro, tostring(mensagem) .. "\n" .. tostring(pilha))
        if anterior then
            return anterior(mensagem, ...)
        end
    end)
end

-- Roda a partida de um módulo sem deixar que o erro dele impeça a dos outros
local function Rodar(funcao, etapa)
    local ok, erro = pcall(funcao)
    if not ok then
        GuardarErro("[" .. etapa .. "] " .. tostring(erro))
        print(K.PREFIXO .. "|cffff5050erro na " .. etapa .. ":|r " .. tostring(erro))
    end
end

function K.AoCarregar(funcao)
    carregar[#carregar + 1] = funcao
end

function K.AoEntrar(funcao)
    entrar[#entrar + 1] = funcao
end

local function Completar(destino, origem)
    for chave, valor in pairs(origem) do
        if type(valor) == "table" then
            if type(destino[chave]) ~= "table" then
                destino[chave] = {}
            end
            Completar(destino[chave], valor)
        elseif destino[chave] == nil then
            destino[chave] = valor
        end
    end
end

function K.Secreto(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

-- Ouro em texto: 1g 20s, 35s 10c, 8c
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

-- Ouro com as moedinhas do jogo, quando o cliente oferece a função
function K.MoedaIcone(cobre)
    local formatar = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if formatar then
        local ok, texto = pcall(formatar, math.floor(cobre + 0.5))
        if ok and type(texto) == "string" then
            return texto
        end
    end
    return K.Moeda(cobre)
end

-- Som de alerta (quando pedido), texto no meio da tela e linha no chat
function K.Avisar(texto, comSom)
    if comSom ~= false and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
    if RaidNotice_AddMessage and RaidWarningFrame then
        local cor = (ChatTypeInfo and ChatTypeInfo["RAID_WARNING"]) or { r = 1, g = 0.3, b = 0.1 }
        pcall(RaidNotice_AddMessage, RaidWarningFrame, texto, cor)
    end
    print(K.PREFIXO .. texto)
end

---------------------------------------------------------------------------
-- Quadros móveis: cada módulo registra o seu; o núcleo guarda lugar, tamanho e visibilidade
---------------------------------------------------------------------------

local function Config(nome)
    local cfg = K.db.quadros[nome]
    if type(cfg) ~= "table" then
        cfg = {}
        K.db.quadros[nome] = cfg
    end
    return cfg
end

local function AtualizarMouse(item)
    local f = item.frame
    local ligar = K.movendo or item.arrastando or IsShiftKeyDown()
    f:EnableMouse(ligar and true or false)
    if not ligar then
        f.kitFundo:Hide()
        if GameTooltip:GetOwner() == f then
            GameTooltip:Hide()
        end
    end
end

function K.AtualizarMouses()
    for _, item in pairs(K.quadros) do
        AtualizarMouse(item)
    end
end

function K.QuadroVisivel(nome)
    return not Config(nome).oculto
end

function K.Escala(nome)
    return Config(nome).escala or 1
end

-- Põe o quadro no lugar e no tamanho guardados e decide se aparece
function K.AplicarQuadro(nome)
    local item = K.quadros[nome]
    if not item or not K.db then
        return
    end
    local f, cfg = item.frame, Config(nome)
    f:SetScale(cfg.escala or 1)
    f:ClearAllPoints()
    local p = (type(cfg.pos) == "table" and cfg.pos[1]) and cfg.pos or item.padrao
    f:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    if K.movendo then
        f:Show()
    elseif item.visivelSempre then
        f:SetShown(not cfg.oculto)
    end
end

function K.AlternarVisivel(nome)
    local cfg = Config(nome)
    cfg.oculto = not cfg.oculto
    K.AplicarQuadro(nome)
end

-- Muda o tamanho em passos de 10%, entre 50% e 200%, sem tirar o quadro do lugar na tela
function K.MudarEscala(nome, passo)
    local item = K.quadros[nome]
    if not item then
        return
    end
    local cfg = Config(nome)
    local velha = cfg.escala or 1
    local nova = math.max(0.5, math.min(2, math.floor((velha + passo) * 10 + 0.5) / 10))
    if nova == velha then
        return
    end
    local p = (type(cfg.pos) == "table" and cfg.pos[1]) and cfg.pos or item.padrao
    cfg.pos = { p[1], p[2] or p[1], (p[3] or 0) * velha / nova, (p[4] or 0) * velha / nova }
    cfg.escala = nova
    K.AplicarQuadro(nome)
end

function K.RegistrarQuadro(nome, frame, opcoes)
    local item = { frame = frame, padrao = opcoes.padrao, visivelSempre = opcoes.visivelSempre,
        aoMover = opcoes.aoMover }
    K.quadros[nome] = item
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")

    local fundo = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    fundo:SetPoint("TOPLEFT", frame, "TOPLEFT", -6, 6)
    fundo:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 6, -6)
    fundo:SetColorTexture(0, 0.6, 1, 0.3)
    fundo:Hide()
    frame.kitFundo = fundo

    local rotulo = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rotulo:SetPoint("BOTTOM", frame, "TOP", 0, 10)
    rotulo:SetText(opcoes.rotulo)
    rotulo:Hide()
    frame.kitRotulo = rotulo

    frame:SetScript("OnDragStart", function(self)
        if K.movendo or IsShiftKeyDown() then
            item.arrastando = true
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
        item.arrastando = false
        local ponto, _, relativo, x, y = self:GetPoint(1)
        Config(nome).pos = { ponto, relativo, x, y }
        AtualizarMouse(item)
    end)
    frame:SetScript("OnEnter", function(self)
        self.kitFundo:Show()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(opcoes.rotulo)
        GameTooltip:AddLine("Arraste com o botão esquerdo para mudar de lugar.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        if not K.movendo then
            self.kitFundo:Hide()
        end
        GameTooltip:Hide()
    end)
end

-- Destrava (ou trava) todos os quadros de uma vez
function K.ModoMover(ativo)
    if ativo == nil then
        ativo = not K.movendo
    end
    K.movendo = ativo
    for nome, item in pairs(K.quadros) do
        local f = item.frame
        f.kitFundo:SetShown(ativo)
        f.kitRotulo:SetShown(ativo)
        if ativo then
            f:Show()
        elseif item.visivelSempre then
            f:SetShown(not Config(nome).oculto)
        else
            f:Hide()
        end
        if item.aoMover then
            item.aoMover(ativo)
        end
        AtualizarMouse(item)
    end
    if K.AtualizarJanela then
        K.AtualizarJanela()
    end
    print(K.PREFIXO .. (ativo and "quadros destravados: arraste cada um e depois clique em Travar quadros."
        or "quadros travados."))
end

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------

local eventos = CreateFrame("Frame")
eventos:RegisterEvent("ADDON_LOADED")
eventos:RegisterEvent("PLAYER_LOGIN")
eventos:RegisterEvent("MODIFIER_STATE_CHANGED")
eventos:SetScript("OnEvent", function(_, evento, arg1)
    if evento == "ADDON_LOADED" then
        if arg1 ~= NOME then
            return
        end
        KitDruidaDB = KitDruidaDB or {}
        Completar(KitDruidaDB, PADRAO)
        K.db = KitDruidaDB
        K.db.erros = errosDaSessao
        for _, funcao in ipairs(carregar) do
            Rodar(funcao, "carga")
        end
    elseif evento == "PLAYER_LOGIN" then
        for nome in pairs(K.quadros) do
            Rodar(function() K.AplicarQuadro(nome) end, "posição dos quadros")
        end
        for _, funcao in ipairs(entrar) do
            Rodar(funcao, "entrada")
        end
    elseif evento == "MODIFIER_STATE_CHANGED" and K.db then
        K.AtualizarMouses()
    end
end)
