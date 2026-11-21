-- Kit do Druida: Macros do Druida.
-- Cria no personagem os macros da seção Macros do guia, com o botão da janela do Kit ou
-- /kit macros, e os mantém em dia: o do urso passa para Dire Bear Form quando você aprende a forma.
-- Só fora de combate: o jogo não deixa addon mexer em macro em combate, e o que ficar pendente é
-- feito quando o combate acaba. Para pôr na barra: /macro, aba com o nome do personagem, arrastar.
-- O Kit só atualiza macro que ele mesmo criou (os nomes ficam em KitDruidaDB.macros.criados): um
-- macro seu com o mesmo nome fica como está. A atualização automática não recria macro que você
-- apagou; o botão recria.
--
-- Diferença para o guia: o Dash entra em Cat Form com "/cast !Cat Form" em vez de [noform:3],
-- porque o número da forma muda conforme as formas que você já aprendeu.

local _, K = ...
local M = {}
K.Macros = M

local ICONE = 134400        -- o ponto de interrogação: o jogo mostra o ícone do feitiço do macro
local DIRE_BEAR_FORM = 9634

local function Conhece(feitico)
    local funcao = IsPlayerSpell or IsSpellKnown
    if type(funcao) ~= "function" then
        return false
    end
    local ok, sim = pcall(funcao, feitico)
    return ok and sim == true
end

-- Os macros do guia, na ordem em que aparecem lá (nome de até 16 letras, corpo de até 255)
local function Lista()
    local urso = Conhece(DIRE_BEAR_FORM) and "Dire Bear Form" or "Bear Form"
    return {
        { "Viagem", "#showtooltip\n/cast [swimming] Aquatic Form; [outdoors] Travel Form; Cat Form" },
        { "Abertura", "#showtooltip\n/cast [stealth] Ravage; Shred" },
        { "Dash", "#showtooltip Dash\n/cast !Cat Form\n/cast Dash" },
        { "Gato", "#showtooltip\n/cast !Cat Form" },
        { "Urso", "#showtooltip\n/cast !" .. urso },
        { "Regrowth", "#showtooltip Regrowth\n/cancelform\n/cast [@player] Regrowth" },
        { "Healing Touch", "#showtooltip Healing Touch\n/cancelform\n/cast [@player] Healing Touch" },
        { "Reviver", "#showtooltip\n/cast [combat] Rebirth; Revive" },
    }
end

K.AoCarregar(function()
    if type(K.db.macros) ~= "table" then
        K.db.macros = {}
    end
    if type(K.db.macros.criados) ~= "table" then
        K.db.macros.criados = {}
    end
end)

local function Indice(nome)
    if type(GetMacroIndexByName) ~= "function" then
        return 0
    end
    local ok, i = pcall(GetMacroIndexByName, nome)
    return (ok and type(i) == "number") and i or 0
end

local function Corpo(indice)
    if type(GetMacroInfo) ~= "function" or indice == 0 then
        return nil
    end
    local ok, _, _, corpo = pcall(GetMacroInfo, indice)
    return ok and corpo or nil
end

local pendente = false   -- false, "auto" ou "manual" (pedido pelo botão durante o combate)

-- Cria os que faltam e atualiza os que o Kit criou e mudaram. Em silêncio (atualização automática),
-- só fala se mudou algo e não recria macro apagado.
function M.Sincronizar(silencioso)
    if not (K.db and K.db.macros) then
        return
    end
    if InCombatLockdown() then
        if not silencioso then
            pendente = "manual"
        elseif not pendente then
            pendente = "auto"
        end
        if not silencioso then
            print(K.PREFIXO .. "macros: fica para o fim do combate (o jogo não deixa addon mexer em macro em combate).")
        end
        return
    end
    pendente = false
    local criados = K.db.macros.criados
    local feitos, mudados, seus, recusados = {}, {}, {}, {}
    for _, m in ipairs(Lista()) do
        local nome, corpo = m[1], m[2]
        local i = Indice(nome)
        if i == 0 then
            if not silencioso then
                pcall(CreateMacro, nome, ICONE, corpo, true)
                if Indice(nome) > 0 then
                    criados[nome] = true
                    feitos[#feitos + 1] = nome
                else
                    recusados[#recusados + 1] = nome
                end
            end
        elseif criados[nome] then
            if Corpo(i) ~= corpo then
                pcall(EditMacro, i, nome, ICONE, corpo)
                if Corpo(Indice(nome)) == corpo then
                    mudados[#mudados + 1] = nome
                else
                    recusados[#recusados + 1] = nome
                end
            end
        else
            seus[#seus + 1] = nome
        end
    end
    if #feitos > 0 then
        print(K.PREFIXO .. "macros criados no personagem: " .. table.concat(feitos, ", ") .. ".")
    end
    if #mudados > 0 then
        print(K.PREFIXO .. "macros atualizados: " .. table.concat(mudados, ", ") .. ".")
    end
    if #recusados > 0 then
        print(K.PREFIXO .. "o jogo recusou: " .. table.concat(recusados, ", ")
            .. " (o limite de macros do personagem pode estar cheio).")
    end
    if not silencioso then
        if #seus > 0 then
            print(K.PREFIXO .. "não mexi nos seus macros de mesmo nome: " .. table.concat(seus, ", ") .. ".")
        end
        if #feitos == 0 and #mudados == 0 and #recusados == 0 then
            print(K.PREFIXO .. "os macros já estão em dia.")
        end
        print(K.PREFIXO .. "para pôr na barra: /macro, aba com o nome do personagem, e arraste o ícone.")
    end
end

-- Quantos macros do guia o Kit tem no personagem, e o total (para o botão da janela)
function M.Contagem()
    local n, total = 0, 0
    local criados = (K.db and K.db.macros and K.db.macros.criados) or {}
    for _, m in ipairs(Lista()) do
        total = total + 1
        if criados[m[1]] and Indice(m[1]) > 0 then
            n = n + 1
        end
    end
    return n, total
end

-- Feitiço novo (Dire Bear Form no 40) ou fim de combate com algo pendente: atualiza em silêncio
local agendado = false
local eventos = CreateFrame("Frame")
eventos:RegisterEvent("SPELLS_CHANGED")
eventos:RegisterEvent("PLAYER_REGEN_ENABLED")
eventos:SetScript("OnEvent", function(_, evento)
    if not (K.db and K.db.macros) or agendado then
        return
    end
    local silencioso
    if evento == "PLAYER_REGEN_ENABLED" then
        if not pendente then
            return
        end
        silencioso = pendente ~= "manual"
    else
        if not next(K.db.macros.criados) then
            return
        end
        silencioso = true
    end
    agendado = true
    C_Timer.After(2, function()
        agendado = false
        local ok, erro = pcall(M.Sincronizar, silencioso)
        if not ok and K.GuardarErro then
            K.GuardarErro("[Macros] " .. tostring(erro))
        end
    end)
end)
