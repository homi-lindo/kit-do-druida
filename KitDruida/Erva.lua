-- Kit do Druida: Aviso de Erva.
-- Quando uma erva vira o alvo suave do jogo ("softinteract"), mostra o nome dela na tela e toca
-- um som. É o mesmo alvo que o Lueur acende: com o Lueur ligado, o jogo procura até 15 jardas
-- (limite do próprio jogo) e em todas as direções; sem ele, só aponta o que está quase
-- encostado. Em combate o Forever pode esconder o nome: aí não há aviso.

local _, K = ...

local REPETIR_APOS = 30   -- segundos até avisar de novo a mesma erva
local DURACAO = 4         -- segundos que o aviso fica na tela

-- Ervas do Forever, em minúsculas; basta o nome do objeto conter uma delas ("Wilted Peacebloom")
local ERVAS = {
    "peacebloom", "silverleaf", "earthroot", "mageroyal", "briarthorn", "stranglekelp", "bruiseweed",
    "wild steelbloom", "grave moss", "kingsblood", "liferoot", "fadeleaf", "goldthorn", "khadgar's whisker",
    "wintersbite", "firebloom", "purple lotus", "arthas' tears", "sungrass", "blindweed", "ghost mushroom",
    "gromsblood", "golden sansam", "dreamfoil", "mountain silversage", "plaguebloom", "icecap", "black lotus",
    "dreamroot",
}

local ultimo, ultimoQuando = nil, 0
local resta = 0

local function EhErva(nome)
    for _, erva in ipairs(ERVAS) do
        if nome:find(erva, 1, true) then
            return true
        end
    end
    return false
end

local quadro = CreateFrame("Frame", "KitDruidaErva", UIParent)
quadro:SetSize(420, 44)
quadro:SetFrameStrata("HIGH")
quadro:Hide()

local texto = quadro:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
texto:SetPoint("CENTER", quadro, "CENTER", 0, 0)
texto:SetTextColor(0.4, 1, 0.42)

quadro:SetScript("OnUpdate", function(self, decorrido)
    if K.movendo then
        return
    end
    resta = resta - decorrido
    if resta <= 0 then
        self:Hide()
    elseif resta < 1 then
        self:SetAlpha(resta)
    end
end)

local function Mostrar(nome)
    texto:SetText("Erva perto: " .. nome)
    resta = DURACAO
    quadro:SetAlpha(1)
    quadro:Show()
    if not K.db or K.db.erva.som ~= false then
        local som = SOUNDKIT and (SOUNDKIT.MAP_PING or SOUNDKIT.RAID_WARNING)
        if som then
            PlaySound(som, "Master")
        end
    end
end

local function Checar()
    if not (K.db and K.db.erva.ligado) or K.movendo then
        return
    end
    local ok, nome = pcall(UnitName, "softinteract")
    if not ok or K.Secreto(nome) or type(nome) ~= "string" or nome == "" then
        return
    end
    local baixo = nome:lower()
    if not EhErva(baixo) then
        return
    end
    -- O GUID distingue duas moitas iguais lado a lado; sem ele, vale o nome
    local okGuid, guid = pcall(UnitGUID, "softinteract")
    local chave = (okGuid and not K.Secreto(guid) and type(guid) == "string") and guid or baixo
    local agora = GetTime()
    if chave == ultimo and agora - ultimoQuando < REPETIR_APOS then
        return
    end
    ultimo, ultimoQuando = chave, agora
    Mostrar(nome)
end

K.RegistrarQuadro("erva", quadro, {
    rotulo = "Aviso de Erva",
    padrao = { "TOP", "TOP", 0, -140 },
    visivelSempre = false,
    aoMover = function(ativo)
        if ativo then
            texto:SetText("Erva perto: Peacebloom (exemplo)")
            quadro:SetAlpha(1)
        end
    end,
})

K.Erva = {
    Testar = function()
        Mostrar("Peacebloom (teste)")
    end,
}

local eventos = CreateFrame("Frame")
pcall(eventos.RegisterEvent, eventos, "PLAYER_SOFT_INTERACT_CHANGED")
eventos:SetScript("OnEvent", Checar)

SLASH_KITERVA1 = "/erva"
SlashCmdList.KITERVA = function(msg)
    msg = type(msg) == "string" and msg:lower() or ""
    if msg:find("teste", 1, true) then
        K.Erva.Testar()
        return
    end
    if not K.db then
        return
    end
    K.db.erva.ligado = not K.db.erva.ligado
    print(K.PREFIXO .. "aviso de erva " .. (K.db.erva.ligado and "ligado." or "desligado."))
    if K.AtualizarJanela then
        K.AtualizarJanela()
    end
end
