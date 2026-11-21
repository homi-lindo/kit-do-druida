-- Kit do Druida: Painel da Sessão.
-- Quadro com a sessão de jogo: XP por hora, ouro por hora (o líquido, depois de treino e
-- compras), quanto falta para o próximo nível e para a próxima meta de ouro, com o tempo
-- estimado no ritmo da sessão. As metas são as do guia do Druid: 100 de ouro no 40 (montaria)
-- e 1.200 no 60 (épica), com marcos a cada 5 níveis.
-- A sessão continua depois de um /reload ou de uma queda curta (até 15 minutos fora).

local _, K = ...

local PAUSA_MAX = 15 * 60
local MONTARIA = { nivel = 40, ouro = 100, rotulo = "Montaria (40)" }
local EPICA = { nivel = 60, ouro = 1200, rotulo = "Épica (60)" }
local METAS = { { 20, 3 }, { 25, 10 }, { 30, 25 }, { 35, 55 }, { 40, 100 }, { 45, 170 }, { 50, 410 }, { 55, 750 }, { 60, 1200 } }

local s                      -- estado da sessão (K.db.painel.sessao)
local xpAntes, maxAntes, nivelAntes
local ultimoTique

local function Numero(funcao, ...)
    if not funcao then
        return nil
    end
    local ok, valor = pcall(funcao, ...)
    if ok and not K.Secreto(valor) and type(valor) == "number" then
        return valor
    end
    return nil
end

local function Milhar(n)
    local texto = tostring(math.floor(n + 0.5))
    local resultado = texto:reverse():gsub("(%d%d%d)", "%1."):reverse()
    return (resultado:gsub("^%.", ""))
end

local function Duracao(segundos)
    if not segundos or segundos ~= segundos or segundos == math.huge or segundos < 0 then
        return "—"
    end
    segundos = math.floor(segundos)
    local h, m = math.floor(segundos / 3600), math.floor(segundos / 60) % 60
    if h > 0 then
        return string.format("%dh%02d", h, m)
    end
    return m .. " min"
end

local function NovaSessao()
    s = { tempo = 0, xp = 0, ouroInicio = Numero(GetMoney) or 0, visto = time() }
    K.db.painel.sessao = s
    xpAntes, ultimoTique = nil, nil
end

local function SomarXP()
    local xp, maximo, nivel = Numero(UnitXP, "player"), Numero(UnitXPMax, "player"), Numero(UnitLevel, "player")
    if not (xp and maximo and nivel) then
        return
    end
    if xpAntes and s then
        local ganho
        -- XP só cai quando o nível vira (o nível novo pode chegar um evento depois)
        if nivel > nivelAntes or xp < xpAntes then
            ganho = (maxAntes - xpAntes) + xp
        else
            ganho = xp - xpAntes
        end
        if ganho > 0 then
            s.xp = s.xp + ganho
        end
    end
    xpAntes, maxAntes, nivelAntes = xp, maximo, nivel
end

-- Quadro
local quadro = CreateFrame("Frame", "KitDruidaPainel", UIParent)
quadro:SetSize(330, 92)
local fundo = quadro:CreateTexture(nil, "BACKGROUND")
fundo:SetAllPoints(quadro)
fundo:SetColorTexture(0, 0, 0, 0.45)

local linhas = {}
for i = 1, 5 do
    local linha = quadro:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    linha:SetPoint("TOPLEFT", quadro, "TOPLEFT", 8, -6 - (i - 1) * 16)
    linha:SetJustifyH("LEFT")
    linhas[i] = linha
end
linhas[1]:SetFontObject("GameFontNormal")

local function ProximaMeta(nivel)
    for _, meta in ipairs(METAS) do
        if meta[1] >= nivel then
            return meta[1], meta[2]
        end
    end
    return nil
end

local function LinhaMeta(rotulo, ouroMeta, dinheiro, ouroPorHora)
    local falta = ouroMeta * 10000 - dinheiro
    if falta <= 0 then
        return rotulo .. ": " .. K.Moeda(ouroMeta * 10000) .. ", já tem"
    end
    local eta = (ouroPorHora and ouroPorHora > 0) and (falta / ouroPorHora * 3600) or nil
    return rotulo .. ": faltam " .. K.Moeda(falta) .. " · " .. (eta and ("~" .. Duracao(eta)) or "sem ritmo ainda")
end

local function Desenhar()
    if not s then
        return
    end
    local xp, maximo, nivel = Numero(UnitXP, "player"), Numero(UnitXPMax, "player"), Numero(UnitLevel, "player")
    local dinheiro = Numero(GetMoney) or 0
    local horas = s.tempo / 3600
    local xpPorHora = horas > 0.02 and (s.xp / horas) or nil
    local liquido = dinheiro - s.ouroInicio
    local ouroPorHora = horas > 0.02 and (liquido / horas) or nil

    linhas[1]:SetText(string.format("Sessão %s · %s XP/h · %s/h",
        Duracao(s.tempo), xpPorHora and Milhar(xpPorHora) or "—", ouroPorHora and K.Moeda(ouroPorHora) or "—"))

    if xp and maximo and nivel and nivel < 60 then
        local falta = maximo - xp
        local eta = xpPorHora and xpPorHora > 0 and (falta / xpPorHora * 3600) or nil
        local descanso = Numero(GetXPExhaustion)
        linhas[2]:SetText(string.format("Nível %d: faltam %s XP · %s%s", nivel, Milhar(falta),
            eta and ("~" .. Duracao(eta)) or "sem ritmo ainda",
            descanso and descanso > 0 and (" · descanso " .. Milhar(descanso)) or ""))
    else
        linhas[2]:SetText(nivel and ("Nível " .. nivel) or "")
    end

    linhas[3]:SetText("Ouro: " .. K.Moeda(dinheiro) .. " · na sessão " .. (liquido >= 0 and "+" or "") .. K.Moeda(liquido))

    local metaNivel, metaOuro = ProximaMeta(nivel or 1)
    if metaNivel then
        linhas[4]:SetText(LinhaMeta("Meta do guia no " .. metaNivel, metaOuro, dinheiro, ouroPorHora))
    else
        linhas[4]:SetText("")
    end
    local alvo = (nivel and nivel >= MONTARIA.nivel) and EPICA or MONTARIA
    linhas[5]:SetText(LinhaMeta(alvo.rotulo, alvo.ouro, dinheiro, ouroPorHora))
end

local function Tique()
    if not s then
        return
    end
    local agora = GetTime()
    if ultimoTique then
        s.tempo = s.tempo + (agora - ultimoTique)
    end
    ultimoTique = agora
    s.visto = time()
    Desenhar()
end

K.RegistrarQuadro("painel", quadro, {
    rotulo = "Painel da Sessão",
    padrao = { "TOPLEFT", "TOPLEFT", 20, -200 },
    visivelSempre = true,
})

K.Painel = {
    NovaSessao = function()
        NovaSessao()
        SomarXP()
        Desenhar()
        print(K.PREFIXO .. "sessão nova no Painel da Sessão.")
    end,
}

K.AoEntrar(function()
    local anterior = K.db.painel.sessao
    if type(anterior) == "table" and type(anterior.visto) == "number" and time() - anterior.visto <= PAUSA_MAX then
        s = anterior
    else
        NovaSessao()
    end
    SomarXP()
    Tique()
    C_Timer.NewTicker(1, Tique)
end)

local eventos = CreateFrame("Frame")
eventos:RegisterEvent("PLAYER_XP_UPDATE")
eventos:SetScript("OnEvent", SomarXP)

SLASH_KITPAINEL1 = "/painel"
SlashCmdList.KITPAINEL = function(msg)
    msg = type(msg) == "string" and msg:lower() or ""
    if msg:find("reset", 1, true) then
        K.Painel.NovaSessao()
    elseif msg:find("mover", 1, true) then
        K.ModoMover()
    else
        K.AlternarVisivel("painel")
    end
    if K.AtualizarJanela then
        K.AtualizarJanela()
    end
end
