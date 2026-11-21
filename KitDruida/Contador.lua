-- Kit do Druida: Contador de Buffs.
-- Contagem regressiva dos buffs que você precisa manter em você: Mark of the Wild, Thorns,
-- comida (Well Fed) e Well-Rested. Quando falta 1 minuto, o ícone pisca em amarelo e toca um
-- alerta; quando o buff acaba, o ícone fica vermelho com "acabou" e toca outro alerta.
-- Com a leitura recusada (combate), a contagem segue pelo último fim conhecido.

local _, K = ...

local AVISO_ANTES = 60   -- segundos antes do fim para o primeiro alerta
local TAMANHO = 40       -- tamanho do ícone, em pixels (a escala do quadro multiplica)
local ESPACO = 10
local ICONE_PADRAO = "Interface\\Icons\\INV_Misc_QuestionMark"

local RASTREADOS = {
    { chave = "motw", rotulo = "Mark of the Wild", nomes = { "mark of the wild", "gift of the wild" } },
    { chave = "thorns", rotulo = "Thorns", nomes = { "thorns" } },
    { chave = "comida", rotulo = "Well Fed", nomes = { "well fed", "increased agility", "increased intellect",
        "increased stamina", "increased strength", "increased spirit", "mana regeneration" } },
    { chave = "rested", rotulo = "Well-Rested", nomes = { "well-rested" }, maxPilhas = 3 },
}
K.BUFFS = RASTREADOS

local MAPA, estado = {}, {}
for _, r in ipairs(RASTREADOS) do
    for _, nome in ipairs(r.nomes) do
        MAPA[nome] = r.chave
    end
    estado[r.chave] = { visto = false, ativo = false, fim = nil, icone = nil, pilhas = nil, avisou = false }
end

local function Ligado(chave)
    return K.db ~= nil and K.db.contador.buffs[chave] ~= false
end

local function ComSom()
    return K.db == nil or K.db.contador.som ~= false
end

-- 1h59, 25m, 9:13
local function Formatar(s)
    if s >= 3600 then
        return string.format("%dh%02d", math.floor(s / 3600), math.floor(s / 60) % 60)
    elseif s >= 600 then
        return math.floor(s / 60) .. "m"
    end
    return string.format("%d:%02d", math.floor(s / 60), math.floor(s % 60))
end

-- Lê os buffs do personagem: tabela chave -> { fim, icone, pilhas }, ou nil se o jogo recusou.
local function LerBuffs()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        return nil
    end
    local achados = {}
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or K.Secreto(a) then
            return nil
        end
        if a == nil then
            break
        end
        if type(a) ~= "table" or K.Secreto(a.name) then
            return nil
        end
        local nome = type(a.name) == "string" and a.name:lower() or nil
        local chave = nome and MAPA[nome]
        if chave then
            local fim = a.expirationTime
            if K.Secreto(fim) or type(fim) ~= "number" then
                fim = nil
            end
            local icone = a.icon
            if K.Secreto(icone) then
                icone = nil
            end
            local pilhas = a.applications
            if K.Secreto(pilhas) or type(pilhas) ~= "number" then
                pilhas = nil
            end
            local atual = achados[chave]
            if not atual or (fim and atual.fim and fim > atual.fim) then
                achados[chave] = { fim = fim, icone = icone, pilhas = pilhas }
            end
        end
    end
    return achados
end

local function Atualizar()
    if not K.db then
        return
    end
    local achados = LerBuffs()
    local agora = GetTime()
    for _, r in ipairs(RASTREADOS) do
        if Ligado(r.chave) then
            local e = estado[r.chave]
            if achados then
                local b = achados[r.chave]
                if b then
                    if b.icone then
                        e.icone = b.icone
                    end
                    e.pilhas = b.pilhas
                    local novoFim = (b.fim and b.fim > 0) and b.fim or 0
                    if not e.ativo or (e.fim and novoFim > e.fim + 1) then
                        e.avisou = false
                    end
                    e.fim = novoFim
                    e.ativo, e.visto = true, true
                elseif e.ativo then
                    e.ativo = false
                    K.Avisar(r.rotulo .. " acabou", ComSom())
                end
            elseif e.ativo and e.fim and e.fim > 0 and e.fim <= agora then
                e.ativo = false
                K.Avisar(r.rotulo .. " acabou", ComSom())
            end
            if e.ativo and e.fim and e.fim > 0 and not e.avisou and e.fim - agora <= AVISO_ANTES then
                e.avisou = true
                K.Avisar(r.rotulo .. " acaba em menos de 1 minuto", ComSom())
            end
        end
    end
end

-- Quadro dos ícones
local quadro = CreateFrame("Frame", "KitDruidaContador", UIParent)
quadro:SetSize(TAMANHO, TAMANHO)

local icones = {}
for _, r in ipairs(RASTREADOS) do
    local f = CreateFrame("Frame", nil, quadro)
    f:SetSize(TAMANHO, TAMANHO)
    f.borda = f:CreateTexture(nil, "BACKGROUND")
    f.borda:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
    f.borda:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
    f.icone = f:CreateTexture(nil, "ARTWORK")
    f.icone:SetAllPoints(f)
    f.icone:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.tempo = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.tempo:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.pilhas = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.pilhas:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f:Hide()
    icones[r.chave] = f
end

local function Desenhar()
    local agora = GetTime()
    local n = 0
    for _, r in ipairs(RASTREADOS) do
        local e = estado[r.chave]
        local f = icones[r.chave]
        if Ligado(r.chave) and (e.visto or K.movendo) then
            n = n + 1
            f:ClearAllPoints()
            f:SetPoint("LEFT", quadro, "LEFT", (n - 1) * (TAMANHO + ESPACO), 0)
            f.icone:SetTexture(e.icone or ICONE_PADRAO)
            f:SetAlpha(1)
            if e.ativo then
                f.icone:SetDesaturated(false)
                f.borda:SetColorTexture(0, 0, 0, 0.8)
                f.tempo:SetTextColor(1, 1, 1)
                local resta = (e.fim and e.fim > 0) and math.max(0, e.fim - agora) or nil
                f.tempo:SetText(resta and Formatar(resta) or "")
                if resta and resta <= AVISO_ANTES then
                    f.borda:SetColorTexture(1, 0.82, 0, 1)
                    f.tempo:SetTextColor(1, 0.82, 0)
                    if math.floor(agora * 2) % 2 == 0 then
                        f:SetAlpha(0.45)
                    end
                end
                -- Pilhas: só o Well-Rested empilha (até 3); aparece como 2/3 ou 3/3
                local pilhas = ""
                if e.pilhas and e.pilhas > 1 then
                    pilhas = r.maxPilhas and (e.pilhas .. "/" .. r.maxPilhas) or tostring(e.pilhas)
                end
                f.pilhas:SetText(pilhas)
            elseif e.visto then
                f.icone:SetDesaturated(true)
                f.borda:SetColorTexture(1, 0.1, 0.1, 1)
                f.tempo:SetTextColor(1, 0.25, 0.25)
                f.tempo:SetText("acabou")
                f.pilhas:SetText("")
            else
                f.icone:SetDesaturated(true)
                f.borda:SetColorTexture(0, 0, 0, 0.8)
                f.tempo:SetTextColor(0.7, 0.7, 0.7)
                f.tempo:SetText(r.rotulo)
                f.pilhas:SetText("")
            end
            f:Show()
        else
            f:Hide()
        end
    end
    quadro:SetWidth(math.max(1, n) * (TAMANHO + ESPACO) - ESPACO)
end

local function Limpar()
    for _, r in ipairs(RASTREADOS) do
        local e = estado[r.chave]
        if not e.ativo then
            e.visto = false
        end
    end
    Desenhar()
end

K.RegistrarQuadro("contador", quadro, {
    rotulo = "Contador de Buffs",
    padrao = { "CENTER", "CENTER", 0, 200 },
    visivelSempre = true,
    aoMover = function()
        Desenhar()
    end,
})

K.Contador = {
    Desenhar = Desenhar,
    Limpar = Limpar,
    Testar = function()
        K.Avisar("teste do alerta do Contador de Buffs", ComSom())
    end,
}

K.AoEntrar(function()
    Atualizar()
    Desenhar()
    C_Timer.NewTicker(1, Atualizar)
    C_Timer.NewTicker(0.25, Desenhar)
end)

SLASH_KITCONTADOR1 = "/contador"
SlashCmdList.KITCONTADOR = function(msg)
    msg = type(msg) == "string" and msg:lower() or ""
    if msg:find("mover", 1, true) then
        K.ModoMover()
    elseif msg:find("teste", 1, true) then
        K.Contador.Testar()
    elseif msg:find("limpar", 1, true) then
        Limpar()
    else
        local agora = GetTime()
        for _, r in ipairs(RASTREADOS) do
            local e = estado[r.chave]
            local s
            if not Ligado(r.chave) then
                s = "desligado na janela do /kit"
            elseif e.ativo then
                s = (e.fim and e.fim > 0) and ("faltam " .. Formatar(math.max(0, e.fim - agora))) or "ativo"
            elseif e.visto then
                s = "acabou"
            else
                s = "não visto desde que você entrou"
            end
            print(K.PREFIXO .. r.rotulo .. ": " .. s)
        end
        print(K.PREFIXO .. "ajustes e botão de mover: /kit ou o ícone no minimapa.")
    end
end
