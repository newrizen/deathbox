-- =========================================================
-- DEATHBOX - versão do BOHEAD para Luanti
-- Mod (depende de "default"/minetest_game) que cria
--   - Arena fechada construída a partir de um mapa em ASCII
--   - Barris explosivos
--   - Zumbis com 100 HP, que perseguem o jogador mais próximo
--     e causam dano por contato
--   - Arma "pistola" que dispara balas com dano
--   - Sistema de ondas (3 zumbis iniciais, +3 por onda)
--   - Suporte nativo a 2+ jogadores (qualquer jogador conectado
--     entra automaticamente como alvo dos zumbis)
--   - HUD de vida e onda atual
-- =========================================================

deathbox = {}
-- CONFIGURAÇÃO
deathbox.config = {
    base_pos = {x = 0, y = 300, z = 0},
    cell_size               = 1,    -- 1 char = 1 node
    wall_height             = 6,
    understructure_depth    = 3, -- quantos nodes a subestrutura (piso base + lava + novo piso) ocupa
    zombies_initial         = 10,
    zombies_increase        = 2,
    zombie_hp               = 100,
    zombie_damage           = 1,
    zombie_speed            = 2,
    zombie_attack_cooldown  = 1.2,
    goblin_speed            = 4,
    imp_speed               = 3,
    demon_hp                = 300,
    demon_damage            = 4,
    demonking_hp            = 1000,
    demonking_damage        = 8,
    demonking_speed         = 1.5,
    -- Ataque secundário (meteoro): só acontece quando o demonking está
    -- com menos da metade do HP e o jogador está longe demais para o
    -- ataque normal (leque de flame_ball2 em curto/médio alcance).
    demonking_meteor_range        = 12,  -- mesmo alcance do ataque normal: acima disso é "longe demais"
    demonking_meteor_cooldown     = 5,   -- segundos entre usos do ataque de meteoro
    demonking_meteor_rise_time    = 1.1, -- segundos que a bola gigante sobe antes de estourar no ar
    demonking_meteor_rise_speed   = 9,   -- velocidade vertical de subida da bola gigante
    demonking_meteor_fall_speed   = 14,  -- velocidade de queda dos meteoros (flame_ball2 comuns)
    round_wait_time         = 4,   -- segundos de espera entre ondas
    sword_damage            = 10,
    bullet_damage           = 10,
    bullet_speed            = 30,
    bullet_range            = 40,
    uzibullet_speed         = 45,
    flame_damage            = 10,
    flame_speed             = 14,
    flame_range             = 16,
    barrel_explosion_radius = 3,
    barrel_explosion_damage = 45,
    weapon_side_offset      = 0.3,
    -- ARMA VISÍVEL NA MÃO (3ª pessoa): osso do character.b3d padrão do
    -- minetest_game onde a entidade da arma é anexada, mais o
    -- deslocamento/rotação/escala dela. O wielditem nativo do engine
    -- não é confiável em 3ª pessoa (bug conhecido), então usamos uma
    -- entidade própria anexada a esse osso em vez de depender dele.
    -- held_weapon_offset é em "unidades de osso" (10 = 1 node).
    held_weapon_bone        = "Arm_Right",
    held_weapon_offset      = {x = 0, y = 6, z = 2},
    held_weapon_rotation    = {x = 90, y = 0, z = 270},
    held_weapon_scale       = 0.1,
    barrier_height          = 2,   -- altura da barreira em nodes
    barrier_hits_to_destroy = 40, -- total de tiros até a barreira ser destruída
    barrier_stages          = 5,   -- número de estágios visuais de degradação
    -- quantos nodes acima da estrutura (paredes/barreira) devem ser
    -- limpos durante a geração de terreno, para remover qualquer
    -- pedra/montanha que o mapgen tenha colocado por cima da arena.
    -- Aumente se a base_pos.y escolhida ficar perto de relevos altos
    -- do seu mapgen.
    clear_height_above = 20,
}

-- Mapa padrão (baseado em arena.json do jogo original)
-- "x" = parede, "b" = barril explosivo, "o" =  barreira destrutível, "." = piso vazio
deathbox.default_map = {
    "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "x.....................................x",
    "x.....................................x",
    "x....b......b......b......b......b....x",
    "x..b...............w...............b..x",
    "x.....................................x",
    "x.....................................x",
    "x.....................................x",
    "x.....................................x",
    "x.....................................x",
    "x..b...............................b..x",
    "x.....................................x",
    "x.....................................x",
    "x...............qq...qq...............x",
    "x...............qq...qq...............x",
    "x...............o.....o...............x",
    "x..bw...........o.....o...........wb..x",
    "x...............o.....o...............x",
    "x...............qq...qq...............x",
    "x...............qq...qq...............x",
    "x.....................................x",
    "x.....................................x",
    "x..b...............................b..x",
    "x.....................................x",
    "x.....................................x",
    "x.....................................x",
    "x.....................................x",
    "x.....................................x",
    "x..b...............w...............b..x",
    "x....b......b......b......b......b....x",
    "x.....................................x",
    "x.....................................x",
    "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
}

-- ESTADO DA PARTIDA
deathbox.state = {
    running = false,
    wave = 0,
    alive_zombies = 0,
    last_wave = 0,
    last_remaining = 0,
    map_origin = nil,   -- canto noroeste real em coordenadas de mundo
    map_w = 0,
    map_h = 0,
    spawn_pos = nil,
    active_map = nil,
    arena_ready = false, -- true quando a estrutura já está garantidamente no mapa
    border_floor_cache = nil, -- cache das posições de piso encostadas em parede
    arena_cell_cache = nil, -- cache de todas as posições de piso livre da arena (usado no ataque de meteoro)
}

local hud_ids = {} -- [player_name] = {health = id, wave = id}
-- Nomes de exibição das armas, usados na caixa de informações do HUD.
deathbox.weapon_names = {
    ["deathbox:spear"]        = "Lança",
    ["deathbox:medkit"]       = "Kit Médico",
    ["deathbox:pistol"]       = "Pistola",
    ["deathbox:pistol2"]      = "Pistola Estendida",
    ["deathbox:uzi"]          = "Metralhadora UZI",
    ["deathbox:flamethrower"] = "Lança-Chamas",
    ["deathbox:barrel"]       = "Barril (plantável)",
    ["deathbox:barrier_0"]    = "Barreira (plantável)",
}
-- Retorna o limite de tiros da arma (nil = munição ilimitada, ex: espada).
function deathbox.get_weapon_max_shots(item_name)
    if item_name == "deathbox:pistol" then return deathbox.config.pistol_max_shots end
    if item_name == "deathbox:pistol2" then return deathbox.config.pistol2_max_shots end
    if item_name == "deathbox:uzi" then return deathbox.config.uzi_max_shots end
    if item_name == "deathbox:shotgun" then return deathbox.config.shotgun_max_shots end
    if item_name == "deathbox:flamethrower" then return deathbox.config.flamethrower_max_shots end
    return nil
end
-- Retorna (nome_exibido, usos_restantes_como_texto) para o item na mão.
function deathbox.get_weapon_info(wielded)
    local item_name = wielded:get_name()
    if item_name == "" then return "Nenhuma", "-"
    end
    local label = deathbox.weapon_names[item_name] or item_name
    local max_shots = deathbox.get_weapon_max_shots(item_name)
    if max_shots then
        local shots_fired = wielded:get_meta():get_int("shots_fired")
        return label, tostring(math.max(0, max_shots - shots_fired))
    end
    return label, "Ilimitado"
end
-- Tabelas de chance de drop da caixa de arma, por onda. Cada entrada
-- é {item = "...", weight = N}. Os pesos não precisam somar 100: a
-- diferença até 100 é a chance de a caixa abrir vazia (nenhum item).
deathbox.weapon_drop_tables = {
    [2] = {
        {item = "deathbox:pistol",       weight = 50},
        {item = "deathbox:pistol2",      weight = 45},
        {item = "deathbox:medkit",       weight = 5},
    },
    [3] = {
        {item = "deathbox:pistol",       weight = 40},
        {item = "deathbox:pistol2",      weight = 35},
        {item = "deathbox:flamethrower", weight = 20},
        {item = "deathbox:medkit",       weight = 5},
    },
    [4] = {
        {item = "deathbox:pistol",       weight = 30},
        {item = "deathbox:pistol2",      weight = 25},
        {item = "deathbox:flamethrower", weight = 20},
        {item = "deathbox:uzi",          weight = 20},
        {item = "deathbox:medkit",       weight = 5},
    },
    -- Onda 5 em diante:
    from_wave_5 = {
        {item = "deathbox:pistol",       weight = 20},
        {item = "deathbox:pistol2",      weight = 20},
        {item = "deathbox:flamethrower", weight = 15},
        {item = "deathbox:uzi",          weight = 15},
        {item = "deathbox:shotgun",      weight = 15},
        {item = "deathbox:barrier_0",    weight = 5},
        {item = "deathbox:barrel",       weight = 5},
        {item = "deathbox:medkit",       weight = 5},
        -- 20% restantes: caixa abre vazia (ver deathbox.roll_weapon_drop)
    },
}

-- Retorna a drop table certa para a onda atual, ou nil para usar o
-- comportamento padrão (onda 1: sempre pistola).
function deathbox.get_weapon_drop_table_for_wave(wave)
    if wave == 2 then return deathbox.weapon_drop_tables[2] end
    if wave == 3 then return deathbox.weapon_drop_tables[3] end
    if wave == 4 then return deathbox.weapon_drop_tables[4] end
    if wave >= 5 then return deathbox.weapon_drop_tables.from_wave_5 end
    return nil
end

-- Sorteia um item_name a partir de uma drop table de {item, weight}.
-- Retorna nil se o sorteio cair na fração não coberta pelos pesos
-- (ou seja, "a caixa abriu vazia").
function deathbox.roll_weapon_drop(drop_table)
    local roll = math.random() * 100
    local acc = 0
    for _, entry in ipairs(drop_table) do acc = acc + entry.weight if roll < acc then return entry.item end end
    return nil
end

-- POSICIONAMENTO DIRETO EM FRENTE AO JOGADOR
-- Usado por barris e barreiras: ao clicar com o item na mão (place),
-- o node é colocado direto na célula em frente ao jogador (com base
-- na posição + direção do olhar), sem precisar apontar/selecionar
-- nenhum node. Só funciona se a célula de destino estiver vazia
-- (air) ou tiver uma poça de sangue (que é removida na hora).
function deathbox.get_front_of_player(player, distance)
    local pos = player:get_pos()
    local yaw = player:get_look_horizontal()
    distance = distance or 1
    return vector.round({
        x = pos.x - math.sin(yaw) * distance,
        y = pos.y,
        z = pos.z + math.cos(yaw) * distance,
    })
end

-- Retorna true se a posição puder receber um node plantável (vazia
-- ou com poça de sangue, que é removida na hora).
function deathbox.clear_for_planting(pos)
    local node = core.get_node(pos)
    if node.name == "air" then return true end
    if node.name == "deathbox:bloodpool" then core.set_node(pos, {name = "air"}) return true end
    return false
end

function deathbox.place_barrel_in_front(itemstack, placer)
    if not placer or not placer:is_player() then return itemstack end
    local pos = deathbox.get_front_of_player(placer, 1)
    if not deathbox.clear_for_planting(pos) then return itemstack end
    core.set_node(pos, {name = "deathbox:barrel"})
    core.sound_play("default_place_node_hard", {pos = pos, gain = 0.5, max_hear_distance = 10}, true)
    itemstack:take_item()
    return itemstack
end

function deathbox.place_barrier_in_front(itemstack, placer)
    if not placer or not placer:is_player() then return itemstack end
    local base_pos = deathbox.get_front_of_player(placer, 1)
    if not deathbox.clear_for_planting(base_pos) then return itemstack end
    core.set_node(base_pos, {name = "deathbox:barrier_0"})
    local top_pos = {x = base_pos.x, y = base_pos.y + 1, z = base_pos.z}
    if deathbox.clear_for_planting(top_pos) then core.set_node(top_pos, {name = "deathbox:barrier_0"})
    else top_pos = base_pos -- sem espaço acima: barreira de 1 node só
    end
    deathbox.register_barrier_column(base_pos, top_pos)
    core.get_meta(base_pos):set_int("hits", 0)
    core.sound_play("default_place_node_hard", {pos = base_pos, gain = 0.5, max_hear_distance = 10}, true)
    itemstack:take_item()
    return itemstack
end

-- NODES
core.register_node("deathbox:wall", {
    description = "Parede da Arena deathbox",
    tiles = {"db_soul_soil.png"},
    pointable = false,
    groups = {deathbox_arena = 1},
    sounds = default.node_sound_stone_defaults(),
})
core.register_node("deathbox:pillar", {
    description = "Pilar da Arena deathbox",
    tiles = {"db_pillar_topdown.png", "db_pillar_topdown.png", "db_pillar.png"},
    pointable = false,
    groups = {deathbox_arena = 1},
    sounds = default.node_sound_stone_defaults(),
})
core.register_node("deathbox:floor", {
    description = "Piso da Arena deathbox",
    tiles = {"db_floor.png"},
    pointable = true,
    groups = {deathbox_arena = 1},
    sounds = default.node_sound_stone_defaults(),
})
core.register_node("deathbox:barrel", {
    description = "Barril Explosivo",
    drawtype = "mesh",
    mesh = "db_barrel.obj",
    tiles = {"db_barrel.png"},
    selection_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 1, 0.5}},
    groups = {cracky = 1, deathbox_arena = 1, oddly_breakable_by_hand = 1},
    sounds = default.node_sound_wood_defaults(),
    on_punch = function(pos, node, puncher) deathbox.explode_barrel(pos) end,
    on_place = function(itemstack, placer, pointed_thing) return deathbox.place_barrel_in_front(itemstack, placer) end,
    on_secondary_use = function(itemstack, placer, pointed_thing) return deathbox.place_barrel_in_front(itemstack, placer) end,
})

-- Mata na hora qualquer mob ou jogador embaixo do ponto de pouso.
function deathbox.weapon_box_landing_kill(pos)
    local center = {x = pos.x, y = pos.y + 0.5, z = pos.z}
    for _, obj in ipairs(core.get_objects_inside_radius(center, 1.2)) do
        if obj:is_player() then obj:set_hp(0)
        else
            local ent = obj:get_luaentity()
            if ent and (ent.name == "deathbox:zombie" or ent.name == "deathbox:goblin" or ent.name == "deathbox:imp" or ent.name == "deathbox:demon" or ent.name == "deathbox:demonking") then
                obj:set_hp(0)
            end
        end
    end
    core.sound_play("default_place_node_hard", {pos = pos, gain = 0.6, max_hear_distance = 16}, true)
    core.add_particlespawner({
        amount = 20, time = 0.1,
        minpos = vector.subtract(pos, {x=0.5,y=0,z=0.5}),
        maxpos = vector.add(pos, {x=0.5,y=0.5,z=0.5}),
        minvel = {x=-3,y=1,z=-3}, maxvel = {x=3,y=5,z=3},
        minexptime = 0.3, maxexptime = 0.7,
        minsize = 1, maxsize = 3,
        texture = "db_dust.png",
    })
end
-- ENTIDADE: Caixa de arma cadenciada — controla a própria queda,
-- pra garantir que o efeito de impacto roda exatamente quando ela
-- toca o chão, sem depender do callback interno da engine.
core.register_entity("deathbox:weapon_box_drop", {
    initial_properties = {
        hp_max = 1,
        physical = true,
        static_save = false,
        collide_with_objects = false,
        collisionbox = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
        visual = "cube",
        visual_size = {x = 1, y = 1, z = 1},
        textures = {"db_box_topdown.png", "db_box_topdown.png", "db_box.png", "db_box.png", "db_box.png", "db_box.png"},
    },
    _target_pos = nil,
    on_activate = function(self, staticdata, dtime_s) self.object:set_acceleration({x = 0, y = -10, z = 0}) end,
    on_step = function(self, dtime, moveresult)
        if moveresult and moveresult.collides then
            local pos = self._target_pos or vector.round(self.object:get_pos())
            deathbox.weapon_box_landing_kill(pos)
            core.set_node(pos, {name = "deathbox:weapon_box"})
            self.object:remove()
        end
    end,
})
function deathbox.spawn_weapon_box_drop(pos)
    if not pos then return end
    local node = core.get_node(pos)
    if node and node.name ~= "air" and node.name ~= "deathbox:bloodpool" then return end
    if node and node.name == "deathbox:bloodpool" then core.set_node(pos, {name = "air"}) end
    local spawn_pos = {x = pos.x, y = pos.y + 15, z = pos.z}
    local obj = core.add_entity(spawn_pos, "deathbox:weapon_box_drop")
    if obj then
        local ent = obj:get_luaentity()
        if ent then ent._target_pos = pos end
        obj:set_velocity({x = 0, y = -8, z = 0})
    end
end
-- Agenda a próxima queda de caixa de arma na posição informada,
-- depois de 50s. Precisa ser chamada toda vez que uma caixa deixa
-- de existir, seja como for (jogador abrindo, imp destruindo,
-- barril explodindo por perto, etc.) — senão a cadeia de reposição
-- quebra pra sempre naquela posição.
function deathbox.schedule_weapon_box_respawn(box_pos)
    core.after(50, function() -- cada 50s cai uma caixa
        if not deathbox.state.running then return end
        local n = core.get_node(box_pos)
        if n.name ~= "air" and n.name ~= "deathbox:bloodpool" then return end
        deathbox.spawn_weapon_box_drop(box_pos)
    end)
end
core.register_node("deathbox:weapon_box", {
    description = "Caixa de Arma",
    tiles = {"db_box_topdown.png", "db_box_topdown.png", "db_box.png"},
    groups = {cracky = 1, deathbox_arena = 1, oddly_breakable_by_hand = 1},
    sounds = default.node_sound_wood_defaults(),
on_punch = function(pos, node, puncher)
    if not puncher or not puncher:is_player() then return end
    local box_pos = {x = pos.x, y = pos.y, z = pos.z}
    core.set_node(pos, {name = "air"})
    core.sound_play("default_chest_close", {pos = pos, gain = 0.6, max_hear_distance = 10}, true)
    -- Onda 1 (ou qualquer onda sem tabela definida): sempre pistola.
    -- Ondas 2+: sorteia conforme deathbox.weapon_drop_tables.
    local item_name = "deathbox:pistol"
    local drop_table = deathbox.get_weapon_drop_table_for_wave(deathbox.state.wave)
    if drop_table then item_name = deathbox.roll_weapon_drop(drop_table) end
    if item_name then
        local inv = puncher:get_inventory()
        if inv then
            local wielded = puncher:get_wield_index()
            local added = false
            for i = 1, inv:get_size("main") do
                if i ~= wielded then
                    local stack = inv:get_stack("main", i)
                    if stack:is_empty() then
                        inv:set_stack("main", i, ItemStack(item_name))
                        added = true
                        break
                    end
                end
            end
            if not added then core.add_item(pos, item_name) end
        end
    else core.chat_send_player(puncher:get_player_name(), core.colorize("#aaaaaa", "A caixa estava vazia!")) -- Caiu na fração não coberta pelos pesos: caixa vazia.
    end
    core.add_particlespawner({
        amount = 8, time = 0.2,
        minpos = vector.subtract(pos, {x=0.3,y=0.3,z=0.3}),
        maxpos = vector.add(pos, {x=0.3,y=0.3,z=0.3}),
        minvel = {x=-1,y=1,z=-1}, maxvel = {x=1,y=3,z=1},
        minexptime = 0.3, maxexptime = 0.6,
        minsize = 1, maxsize = 2,
        texture = "db_dust.png",
    })
    deathbox.schedule_weapon_box_respawn(box_pos)
end,
})
-- BARREIRAS DESTRUTÍVEIS ("o" no mapa)
-- Cada barreira ocupa deathbox.config.barrier_height nodes de altura
-- (base + topo). Tomam dano por tiro: a cada
-- (barrier_hits_to_destroy / barrier_stages) tiros, degradam um
-- estágio visual; ao atingir barrier_hits_to_destroy tiros, a
-- barreira inteira é destruída (todos os nodes que a compõem).
-- O contador de tiros é guardado nos metadados do node da base.
local BARRIER_STAGES = deathbox.config.barrier_stages
local HITS_PER_STAGE = deathbox.config.barrier_hits_to_destroy / BARRIER_STAGES
function deathbox.register_barrier_stage(stage)
    core.register_node("deathbox:barrier_" .. stage, {
        description = "Barreira de Pedra Branca (estágio " .. stage .. ")",
        drawtype = "mesh",
        mesh = "db_barrier.obj",
        tiles = {"db_barrier_" .. stage .. ".png"},
        pointable = false,
        groups = {cracky = 2, deathbox_arena = 1, deathbox_barrier = 1},
        sounds = default.node_sound_stone_defaults(),
        on_punch = function(pos, node, puncher) deathbox.hit_barrier(pos) end,
    })
end
for stage = 0, BARRIER_STAGES - 1 do deathbox.register_barrier_stage(stage) end
core.override_item("deathbox:barrier_0", {
    on_place = function(itemstack, placer, pointed_thing) return deathbox.place_barrier_in_front(itemstack, placer) end,
    on_secondary_use = function(itemstack, placer, pointed_thing) return deathbox.place_barrier_in_front(itemstack, placer) end,
})

-- Registra um par de posições (base e topo) como pertencendo à
-- mesma barreira, para que dano em qualquer uma das duas reflita
-- visualmente em ambas. A "base" é sempre a fonte de verdade do
-- contador de tiros.
deathbox.barrier_columns = {} -- chave "x,z" base -> {base_y, top_y}
local function barrier_key(x, z) return x .. "," .. z end
function deathbox.register_barrier_column(base_pos, top_pos)
    deathbox.barrier_columns[barrier_key(base_pos.x, base_pos.z)] = {base_y = base_pos.y, top_y = top_pos.y}
end

function deathbox.hit_barrier(pos)
    -- Tenta a chave direta primeiro
    local key = barrier_key(pos.x, pos.z)
    local column = deathbox.barrier_columns[key]
    -- Se não achou, varre vizinhos (o projétil pode ter arredondado errado)
    if not column then
        for dx = -1, 1 do
            for dz = -1, 1 do
                local k = barrier_key(pos.x + dx, pos.z + dz)
                if deathbox.barrier_columns[k] then
                    key = k
                    column = deathbox.barrier_columns[k]
                    break
                end
            end
            if column then break end
        end
    end
    if not column then return end
    -- Reconstrói x,z da chave encontrada (pode ter sido vizinho)
    local kx, kz = key:match("^(-?%d+),(-?%d+)$")
    kx, kz = tonumber(kx), tonumber(kz)
    local base_pos = {x = kx, y = column.base_y, z = kz}
    local top_pos  = {x = kx, y = column.top_y,  z = kz}

    local meta = core.get_meta(base_pos)
    local hits = meta:get_int("hits") + 1
    meta:set_int("hits", hits)
    if hits >= deathbox.config.barrier_hits_to_destroy then
        core.set_node(base_pos, {name = "air"})
        core.set_node(top_pos,  {name = "air"})
        core.sound_play("default_dig_cracky", {pos = base_pos, gain = 0.6, max_hear_distance = 16}, true)
        core.add_particlespawner({
            amount = 16, time = 0.2,
            minpos = vector.subtract(base_pos, {x=0.3,y=0,z=0.3}),
            maxpos = vector.add(top_pos, {x=0.3,y=0.3,z=0.3}),
            minvel = {x=-2,y=1,z=-2}, maxvel = {x=2,y=4,z=2},
            minexptime = 0.3, maxexptime = 0.8,
            minsize = 2, maxsize = 4,
            texture = "db_dust.png",
        })
        deathbox.barrier_columns[key] = nil
        return
    end
    local stage = math.floor(hits / HITS_PER_STAGE)
    if stage > BARRIER_STAGES - 1 then stage = BARRIER_STAGES - 1 end
    local new_name = "deathbox:barrier_" .. stage
    core.set_node(base_pos, {name = new_name})
    core.set_node(top_pos,  {name = new_name})
    core.get_meta(base_pos):set_int("hits", hits)
end


function deathbox.apply_knockback(obj, attacker_pos, force)
    if not obj or not obj:get_pos() then return end
    local pos = obj:get_pos()
    local dir
    if attacker_pos then dir = vector.direction(attacker_pos, pos)
    else dir = {x = 0, y = 0, z = 0}
    end
    local vel = obj:get_velocity() or {x = 0, y = 0, z = 0}
    obj:set_velocity({
        x = dir.x * force,
        y = math.max(2, vel.y),
        z = dir.z * force,
    })
end

-- =========================================================
-- SISTEMA DE MORTE ANIMADA DOS MOBS
-- Interceptamos o dano via on_punch (return true = cancela o
-- mecanismo padrão do engine). Quando o HP chega a 0,
-- chamamos mob_start_death: paramos o mob, tocamos a animação
-- de deitar (lay, frames 162-166 no esqueleto padrão do
-- character.b3d; nos modelos .glb o mesmo trecho fica em
-- 162/30 .. 166/30 segundos), e só depois removemos.
-- damage_mob é o ponto único usado tanto pelo on_punch quanto
-- pelos set_hp diretos dos projéteis (que agora passam por
-- aqui em vez de chamar obj:set_hp diretamente).
-- =========================================================

-- Nomes de mobs que usam .glb (timeline em segundos ÷ 30)
local GLB_MOBS = {
    ["deathbox:zombie"]    = true,
    ["deathbox:imp"]       = true,
    ["deathbox:demon"]     = true,
    ["deathbox:demonking"] = true,
}

-- Inicia a sequência de morte animada de um mob.
function deathbox.mob_start_death(self)
    if self._dying then return end
    self._dying = true
    local pos = self.object:get_pos()
    -- Zera velocidade horizontal; mantém gravidade para o mob
    -- pousar no chão. math.min(vy,0) descarta impulso pra cima
    -- mas preserva queda se o mob já estava descendo.
    local vy = self.object:get_velocity().y
    self.object:set_velocity({x = 0, y = math.min(vy, 0), z = 0})
    self.object:set_acceleration({x = 0, y = -10, z = 0})
    -- Torna invulnerável para não ser removido pelo engine enquanto
    -- a animação toca (set_armor_groups({immortal=1}) desativa dano)
    self.object:set_armor_groups({immortal = 1})
    -- Animação de deitar (lay): frames 162-166 no esqueleto padrão.
    -- Modelos .glb usam a mesma trilha mas em segundos (÷ 30).
    if GLB_MOBS[self.name] then
        self.object:set_animation({x = 162 / 30, y = 166 / 30}, 1, 0, false)
    else
        self.object:set_animation({x = 162, y = 166}, 30, 0, false)
    end
    -- Efeitos de morte
    if pos then deathbox.spawn_bloodpool(pos)
    end
    -- Atualiza contador e verifica fim de onda
    deathbox.state.alive_zombies = math.max(0, deathbox.state.alive_zombies - 1)
    deathbox.check_wave_complete()
    -- Remove o mob após a animação terminar (~1.5 s)
    local obj_ref = self.object
    core.after(1.5, function() if obj_ref and obj_ref:get_pos() then obj_ref:remove() end end)
end

-- Ponto único de dano para mobs. Substitui chamadas diretas a
-- obj:set_hp() nos projéteis, garantindo que a animação de
-- morte sempre seja tocada.
function deathbox.damage_mob(obj, damage)
    local ent = obj:get_luaentity()
    if not ent or ent._dying then return end
    local new_hp = obj:get_hp() - damage
    if new_hp <= 0 then deathbox.mob_start_death(ent)
    else obj:set_hp(new_hp)
    end
end

-- ARMAS
function deathbox.sword_attack(user)
    if not user or not user:is_player() then return end
    local cfg = deathbox.config
    local pos = user:get_pos()
    pos.y = pos.y + 1.0
    local yaw = user:get_look_horizontal()
    local dir = {
        x = -math.sin(yaw),
        y = 0,
        z = math.cos(yaw),
    }
    local range = 2.5
    local best_obj, best_dist = nil, range
    for _, obj in ipairs(core.get_objects_inside_radius(pos, range)) do
        if obj ~= user and not obj:is_player() then
            local ent = obj:get_luaentity()
            if ent and (ent.name == "deathbox:zombie" or ent.name == "deathbox:goblin" or ent.name == "deathbox:imp" or ent.name == "deathbox:demon" or ent.name == "deathbox:demonking") then
                local mob_pos = obj:get_pos()
                if mob_pos then
                    local to_mob = vector.subtract(mob_pos, pos)
                    to_mob.y = 0
                    local dist = vector.length(to_mob)
                    if dist <= range then
                        local ndir = vector.normalize(to_mob)
                        local dot = ndir.x * dir.x + ndir.z * dir.z
                        -- só conta como "na frente" do jogador (cone de ~70°)
                        if dot > 0.3 and dist < best_dist then
                            best_obj = obj
                            best_dist = dist
                        end
                    end
                end
            end
        end
    end
    if best_obj then
        best_obj:punch(user, 1.0, {full_punch_interval = 0.1, damage_groups = {fleshy = cfg.sword_damage}}, dir)
        best_obj:add_velocity({x = dir.x * 6, y = 1, z = dir.z * 6})
    end
    core.sound_play("default_punch", {pos = pos, gain = 0.4, max_hear_distance = 10}, true)
end

core.register_tool("deathbox:sword", {
    description = "Espada\n(clique direito para usar)",
    inventory_image = "db_sword.png",
    wield_image = "db_sword.png",
    wield_scale = {x = 2.5, y = 2.5, z = 2.5},
    range = 9.1,
    on_secondary_use = function(itemstack, user, pointed_thing)
        deathbox.sword_attack(user)
        return itemstack
    end,
    on_place = function(itemstack, user, pointed_thing)
        deathbox.sword_attack(user)
        return itemstack
    end,
})

core.register_tool("deathbox:spear", {
    description = "Lança\n(clique direito para usar)",
    inventory_image = "db_spear.png",
    wield_image = "db_spear.png",
    wield_scale = {x = 2.5, y = 2.5, z = 2.5},
    range = 9.1,
    on_secondary_use = function(itemstack, user, pointed_thing)
        deathbox.sword_attack(user)
        return itemstack
    end,
    on_place = function(itemstack, user, pointed_thing)
        deathbox.sword_attack(user)
        return itemstack
    end,
})

core.register_craftitem("deathbox:medkit", {
    description = "Kit Médico",
    inventory_image = "db_medkit.png",
    on_place = function(itemstack, user, pointed_thing)
        if not user then return itemstack end
        local hp = user:get_hp()
        local max_hp = user:get_properties().hp_max or 20
        user:set_hp(math.min(hp + 5, max_hp))
        itemstack:take_item()
        return itemstack
    end,
})

-- =========================================================
-- SONS CONTÍNUOS (LOOP) DE ARMAS AUTOMÁTICAS
-- A UZI e o lança-chamas tocam um som em loop enquanto o jogador
-- mantém o clique direito pressionado e ainda há balas/combustível.
-- Guardamos o handle do som por jogador/arma para poder pará-lo
-- exatamente quando o gatilho é solto, a munição acaba, a arma é
-- trocada, o jogador morre ou desconecta.
-- =========================================================
deathbox.loop_sound_handles = {} -- [player_name] = {uzi = handle, flamethrower = handle}

function deathbox.start_loop_sound(player, key, soundname, params)
    if not player or not player:is_player() then return end
    local pname = player:get_player_name()
    local handles = deathbox.loop_sound_handles[pname]
    if not handles then
        handles = {}
        deathbox.loop_sound_handles[pname] = handles
    end
    if handles[key] then return end -- já está tocando, não reinicia
    handles[key] = core.sound_play(soundname, params, false)
end

function deathbox.stop_loop_sound(player_name, key)
    local handles = deathbox.loop_sound_handles[player_name]
    if not handles or not handles[key] then return end
    core.sound_stop(handles[key])
    handles[key] = nil
end

function deathbox.stop_all_loop_sounds(player_name)
    local handles = deathbox.loop_sound_handles[player_name]
    if not handles then return end
    for _, handle in pairs(handles) do core.sound_stop(handle) end
    deathbox.loop_sound_handles[player_name] = nil
end

deathbox.config.pistol_max_shots = 18
core.register_tool("deathbox:pistol", {
    description = "Pistola Lock 18\nTiros: 18\n(clique direito para disparar)",
    inventory_image = "db_pistol.png",
    wield_image = "db_pistol.png",
    wield_scale = {x = 2.5, y = 2.5, z = 2.5},
    range = 9.1,
    on_secondary_use = function(itemstack, user, pointed_thing) return deathbox.fire_pistol(itemstack, user) end,
    on_place = function(itemstack, user, pointed_thing) return deathbox.fire_pistol(itemstack, user) end,
})
function deathbox.fire_pistol(itemstack, user)
    local meta = itemstack:get_meta()
    local shots_fired = meta:get_int("shots_fired") + 1
    deathbox.bullet_weapon(user, deathbox.config.bullet_speed)
    if user and user:is_player() then
        core.sound_play("default_metal2", {pos = user:get_pos(), gain = 2, max_hear_distance = 14}, true) -- db_pistol_shot"
    end
    if shots_fired >= deathbox.config.pistol_max_shots then
        if user and user:is_player() then
            core.chat_send_player(user:get_player_name(), core.colorize("#ffaa55", "Pistola sem munição!"))
            core.sound_play("default_dig_metal", {pos = user:get_pos(), gain = 0.6, max_hear_distance = 14}, true)
        end
        return ItemStack("")
    end
    meta:set_int("shots_fired", shots_fired)
    local remaining = deathbox.config.pistol_max_shots - shots_fired
    meta:set_string("description", "Pistola Lock 18\n(" .. remaining .. " tiros restantes)\n(clique direito para disparar)")
    return itemstack
end
deathbox.config.pistol2_max_shots = 34
core.register_tool("deathbox:pistol2", {
    description = "Pistola Lock 34\n[Pente Estendido]\nTiros: 34\n(clique direito para disparar)",
    inventory_image = "db_pistol2.png",
    wield_image = "db_pistol2.png",
    wield_scale = {x = 2.5, y = 2.5, z = 2.5},
    range = 9.1,
    on_secondary_use = function(itemstack, user, pointed_thing) return deathbox.fire_pistol2(itemstack, user) end,
    on_place = function(itemstack, user, pointed_thing) return deathbox.fire_pistol2(itemstack, user) end,
})
function deathbox.fire_pistol2(itemstack, user)
    local meta = itemstack:get_meta()
    local shots_fired = meta:get_int("shots_fired") + 1
    deathbox.bullet_weapon(user, deathbox.config.bullet_speed)
    if user and user:is_player() then
        core.sound_play("default_metal2", {pos = user:get_pos(), gain = 2, max_hear_distance = 14}, true) -- db_pistol_shot"
    end
    if shots_fired >= deathbox.config.pistol2_max_shots then
        if user and user:is_player() then
            core.chat_send_player(user:get_player_name(), core.colorize("#ffaa55", "Pistola Estendida sem munição!"))
            core.sound_play("default_dig_metal", {pos = user:get_pos(), gain = 0.6, max_hear_distance = 14}, true)
        end
        return ItemStack("")
    end
    meta:set_int("shots_fired", shots_fired)
    local remaining = deathbox.config.pistol2_max_shots - shots_fired
    meta:set_string("description", "Pistola Lock 34\n(" .. remaining .. " tiros restantes)\n(clique direito para disparar)")
    return itemstack
end
deathbox.config.shotgun_max_shots = 10
core.register_tool("deathbox:shotgun", {
    description = "Espingarda 10\nTiros: 10\n(clique direito para disparar)",
    inventory_image = "db_shotgun.png",
    wield_image = "db_shotgun.png",
    wield_scale = {x = 2.5, y = 2.5, z = 2.5},
    range = 9.1,
    on_secondary_use = function(itemstack, user, pointed_thing) return deathbox.fire_shotgun(itemstack, user) end,
    on_place = function(itemstack, user, pointed_thing) return deathbox.fire_shotgun(itemstack, user) end,
})
function deathbox.fire_shotgun(itemstack, user)
    local meta = itemstack:get_meta()
    local shots_fired = meta:get_int("shots_fired") + 1
    -- Dispara 3 balas do mesmo ponto: uma reta, uma 5 graus a esquerda
    -- e uma 5 graus a direita (desvio no angulo horizontal de mira).
    deathbox.bullet_weapon(user, deathbox.config.bullet_speed, -5)
    deathbox.bullet_weapon(user, deathbox.config.bullet_speed, 0)
    deathbox.bullet_weapon(user, deathbox.config.bullet_speed, 5)
    if user and user:is_player() then
        core.sound_play("tnt_explode", {pos = user:get_pos(), gain = 0.3, max_hear_distance = 14}, true) -- db_pistol_shot"
    end
    if shots_fired >= deathbox.config.shotgun_max_shots then
        if user and user:is_player() then
            core.chat_send_player(user:get_player_name(), core.colorize("#ffaa55", "Pistola Estendida sem munição!"))
            core.sound_play("default_dig_metal", {pos = user:get_pos(), gain = 0.6, max_hear_distance = 14}, true)
        end
        return ItemStack("")
    end
    meta:set_int("shots_fired", shots_fired)
    local remaining = deathbox.config.shotgun_max_shots - shots_fired
    meta:set_string("description", "Espingarda 10\n(" .. remaining .. " tiros restantes)\n(clique direito para disparar)")
    return itemstack
end
deathbox.config.uzi_max_shots = 70
core.register_tool("deathbox:uzi", {
    description = "Metralhadora UZI\nTiros: 70\n(segure o clique direito para disparar)",
    inventory_image = "db_uzi.png",
    wield_image = "db_uzi.png",
    wield_scale = {x = 2.5, y = 2.5, z = 2.5},
    range = 9.1,
    on_secondary_use = function(itemstack, user, pointed_thing) return deathbox.fire_uzi(itemstack, user) end,
    on_place = function(itemstack, user, pointed_thing) return deathbox.fire_uzi(itemstack, user) end,
})
function deathbox.fire_uzi(itemstack, user)
    local meta = itemstack:get_meta()
    local shots_fired = meta:get_int("shots_fired") + 1
    deathbox.bullet_weapon(user, deathbox.config.uzibullet_speed)
    if shots_fired >= deathbox.config.uzi_max_shots then
        if user and user:is_player() then
            core.chat_send_player(user:get_player_name(), core.colorize("#ffaa55", "Metralhadora UZI sem munição!"))
            deathbox.stop_loop_sound(user:get_player_name(), "uzi")
            core.sound_play("fire_flint_and_steel", {pos = user:get_pos(), gain = 0.6, max_hear_distance = 16}, true)
        end
        return ItemStack("")
    end
    if user and user:is_player() then
        deathbox.start_loop_sound(user, "uzi", "default_metal2_fast", {object = user, gain = 2, max_hear_distance = 16, loop = true})  -- db_uzi_loop"
    end
    meta:set_int("shots_fired", shots_fired)
    local remaining = deathbox.config.uzi_max_shots - shots_fired
    meta:set_string("description", "Metralhadora UZI\n(" .. remaining .. " tiros restantes)\n(segure o clique direito para disparar)")
    return itemstack
end

function deathbox.bullet_weapon(user, speed, angle_offset_deg)
    if not user or not user:is_player() then return end
    local cfg = deathbox.config
    local pos = user:get_pos()
    -- Atira sempre na altura do meio do corpo dos zumbis (y+1.0)
    -- independente do eye_height da câmera
    pos.y = pos.y + 1.0
    -- yaw_base é sempre o angulo real de mira do jogador: usado para
    -- posicionar o ponto de origem do disparo (spawn_pos), garantindo
    -- que tiros com angle_offset_deg (ex.: leque da espingarda) saiam
    -- todos do mesmo ponto. yaw é o angulo já com o desvio aplicado,
    -- usado apenas na direção/velocidade da bala.
    local yaw_base = user:get_look_horizontal()
    local yaw = yaw_base
    if angle_offset_deg and angle_offset_deg ~= 0 then
        yaw = yaw + math.rad(angle_offset_deg)
    end
    local dir = {
        x = -math.sin(yaw),
        y = 0,
        z =  math.cos(yaw),
    }
    local base_dir = {
        x = -math.sin(yaw_base),
        y = 0,
        z =  math.cos(yaw_base),
    }
    local right = { -- deslocamento para a direita, mao do player
        x = math.cos(yaw_base),
        y = 0,
        z = math.sin(yaw_base),
    }
    local spawn_pos = vector.add(pos, vector.multiply(base_dir, 0.4))
    spawn_pos = vector.add(spawn_pos, vector.multiply(right, cfg.weapon_side_offset))
    local obj = core.add_entity(spawn_pos, "deathbox:bullet_shot")
    if obj then
        -- "speed" permite que armas específicas (ex: a UZI) usem sua
        -- própria velocidade de bala; sem ele, mantém o padrão usado
        -- pelas pistolas.
        local bullet_vel = speed or cfg.flame_speed
        obj:set_velocity({
            x = dir.x * bullet_vel,
            y = 0,
            z = dir.z * bullet_vel,
        })
        obj:set_yaw(yaw)
        local ent = obj:get_luaentity()
        ent._owner = user:get_player_name()
    end
end

--Lança-chamas
deathbox.config.flamethrower_max_shots = 150
function deathbox.fire_weapon(user, life)
    if not user or not user:is_player() then return end
    local cfg = deathbox.config
    local pos = user:get_pos()
    pos.y = pos.y + 1.0
    local yaw = user:get_look_horizontal()
    local dir = {
        x = -math.sin(yaw),
        y = 0,
        z = math.cos(yaw),
    }
    local right = { -- deslocamento para a direita, mao do player
        x = math.cos(yaw),
        y = 0,
        z = math.sin(yaw),
    }
    local spawn_pos = vector.add(pos, vector.multiply(dir, 1.2))
    spawn_pos = vector.add(spawn_pos, vector.multiply(right, cfg.weapon_side_offset))
    local obj = core.add_entity(spawn_pos, "deathbox:flames")
    if obj then
        obj:set_velocity({
            x = dir.x * cfg.flame_speed,
            y = 0,
            z = dir.z * cfg.flame_speed,
        })
        obj:set_yaw(yaw)
        local ent = obj:get_luaentity()
        if ent then
            ent._owner = user:get_player_name()
            ent._life = life or 0.1
        end
    end
end
core.register_tool("deathbox:flamethrower", {
    description = "Lança-Chamas\n(100 tiros)",
    inventory_image = "db_flamethrower.png",
    wield_image = "db_flamethrower.png",
    wield_scale = {x = 2.5, y = 2.5, z = 2.5},
    range = 9.1,
    on_secondary_use = function(itemstack, user)
        return deathbox.fire_flamethrower(itemstack, user, 0.1)
    end,
    on_place = function(itemstack, user)
        return deathbox.fire_flamethrower(itemstack, user, 0.1)
    end,
})
function deathbox.fire_flamethrower(itemstack, user, life)
    local meta = itemstack:get_meta()
    local shots_fired = meta:get_int("shots_fired") + 1
    deathbox.fire_weapon(user, life)
    if shots_fired >= deathbox.config.flamethrower_max_shots then
        if user and user:is_player() then
            core.chat_send_player(user:get_player_name(), core.colorize("#ffaa55", "Lança-chamas sem combustível!"))
            deathbox.stop_loop_sound(user:get_player_name(), "flamethrower")
            core.sound_play("fire_flint_and_steel", {pos = user:get_pos(), gain = 0.6, max_hear_distance = 16}, true)
        end
        return ItemStack("")
    end
    if user and user:is_player() then
        deathbox.start_loop_sound(user, "flamethrower", "default_furnace_active", {object = user, gain = 4, max_hear_distance = 16, loop = true}) -- db_flamethrower_loop"
    end
    meta:set_int("shots_fired", shots_fired)
    local remaining = deathbox.config.flamethrower_max_shots - shots_fired
    meta:set_string("description", "Lança-Chamas\n(" .. remaining .. " tiros restantes)")
    return itemstack
end
deathbox.flame_timer = 0
core.register_globalstep(function(dtime)
    deathbox.flame_timer = deathbox.flame_timer + dtime
    if deathbox.flame_timer < 0.08 then return end
    deathbox.flame_timer = 0
    for _, player in ipairs(core.get_connected_players()) do
        local wielded = player:get_wielded_item()
        local pname = player:get_player_name()
        if wielded:get_name() == "deathbox:flamethrower" then
            local ctrl = player:get_player_control()
            if ctrl.RMB then
                local new_stack = deathbox.fire_flamethrower(wielded, player, 0.2)
                player:set_wielded_item(new_stack)
            else deathbox.stop_loop_sound(pname, "flamethrower") -- gatilho solto: para o som contínuo
            end
        else deathbox.stop_loop_sound(pname, "flamethrower") -- não está com o lança-chamas na mão: garante que o som pare
        end
    end
end)

-- Igual ao lança-chamas: enquanto o jogador segurar o clique
-- direito com a UZI na mão, ela continua disparando sozinha, sem
-- precisar clicar a cada tiro.
deathbox.uzi_timer = 0
core.register_globalstep(function(dtime)
    deathbox.uzi_timer = deathbox.uzi_timer + dtime
    if deathbox.uzi_timer < 0.1 then return end
    deathbox.uzi_timer = 0
    for _, player in ipairs(core.get_connected_players()) do
        local wielded = player:get_wielded_item()
        local pname = player:get_player_name()
        if wielded:get_name() == "deathbox:uzi" then
            local ctrl = player:get_player_control()
            if ctrl.RMB then
                local new_stack = deathbox.fire_uzi(wielded, player)
                player:set_wielded_item(new_stack)
            else deathbox.stop_loop_sound(pname, "uzi") -- gatilho solto: para o som contínuo
            end
        else deathbox.stop_loop_sound(pname, "uzi") -- não está com a UZI na mão: garante que o som pare
        end
    end
end)

-- =========================================================
-- ARMA VISÍVEL NA MÃO EM 3ª PESSOA
-- O wielditem nativo do engine (a malha 3D gerada a partir do
-- inventory_image, anexada automaticamente ao boneco do jogador)
-- não é exibido de forma confiável em 3ª pessoa — isso é uma
-- limitação/bug conhecido do próprio engine, independente do mod.
-- Por isso criamos nossa própria entidade "deathbox:held_weapon",
-- com visual = "wielditem" (esse é o tipo/enum nativo do engine; o
-- itemstring em si vai no campo separado wield_item), e a anexamos
-- manualmente a um osso que já existe no character.b3d padrão do
-- minetest_game (cfg.held_weapon_bone) — sem precisar editar esse
-- arquivo.
-- =========================================================
core.register_entity("deathbox:held_weapon", {
    initial_properties = {
        physical = false,
        collide_with_objects = false,
        pointable = false,
        static_save = false,
        is_visible = false,
        visual = "wielditem",
        wield_item = "",
        backface_culling = false,
    },
})

deathbox.held_weapon_entities = {} -- [player_name] = {obj = ObjectRef, last_item = "itemname"}

-- Garante que existe uma entidade de arma anexada ao jogador,
-- (re)criando-a se necessário (ex.: depois de sair/voltar da área
-- carregada), e atualiza o item exibido se ele tiver mudado desde
-- a última verificação.
function deathbox.update_held_weapon(player)
    if not player or not player:is_player() then return end
    local cfg = deathbox.config
    local pname = player:get_player_name()
    local item_name = player:get_wielded_item():get_name()
    local entry = deathbox.held_weapon_entities[pname]

    if not entry or not entry.obj or not entry.obj:get_pos() then
        local obj = core.add_entity(player:get_pos(), "deathbox:held_weapon")
        if not obj then return end
        obj:set_attach(player, cfg.held_weapon_bone, cfg.held_weapon_offset, cfg.held_weapon_rotation)
        entry = {obj = obj, last_item = nil}
        deathbox.held_weapon_entities[pname] = entry
    end

    if entry.last_item == item_name then return end
    entry.last_item = item_name

    if item_name == "" then
        entry.obj:set_properties({is_visible = false, wield_item = ""})
    else
        entry.obj:set_properties({
            is_visible = true,
            wield_item = item_name,
            visual_size = {x = cfg.held_weapon_scale, y = cfg.held_weapon_scale, z = cfg.held_weapon_scale},
        })
    end
end

function deathbox.remove_held_weapon(player_name)
    local entry = deathbox.held_weapon_entities[player_name]
    if entry and entry.obj then entry.obj:remove() end
    deathbox.held_weapon_entities[player_name] = nil
end

core.register_on_joinplayer(function(player) deathbox.update_held_weapon(player) end)
core.register_on_leaveplayer(function(player)
    deathbox.remove_held_weapon(player:get_player_name())
    deathbox.stop_all_loop_sounds(player:get_player_name())
end)

-- Verifica periodicamente (não a cada passo, por performance) se o
-- item na mão de cada jogador mudou, já que o engine não tem um
-- callback nativo de "troca de item empunhado".
deathbox.held_weapon_timer = 0
core.register_globalstep(function(dtime)
    deathbox.held_weapon_timer = deathbox.held_weapon_timer + dtime
    if deathbox.held_weapon_timer < 0.2 then return end
    deathbox.held_weapon_timer = 0
    for _, player in ipairs(core.get_connected_players()) do
        deathbox.update_held_weapon(player)
    end
end)

-- ENTIDADE: Projétil de fogo
core.register_entity("deathbox:flames", {
    initial_properties = {
        hp_max = 1,
        physical = true,
        pointable = false,
        static_save = false,
        collide_with_objects = false,
        collisionbox = {-0.01, -0.15, -0.03, 0.01, 0.15, 0.03},
        visual = "sprite",
        visual_size = {x = 0.5, y = 1.25},
        textures = {"db_flames.png"},
        glow = 14,
    },
    _owner = nil,
    _life = 0.3,
    on_step = function(self, dtime, moveresult)
        self._life = self._life - dtime
        if self._life <= 0 then self.object:remove() return end
        local pos = self.object:get_pos()
        if not pos then return end
        local vel = self.object:get_velocity()
        local function check_hit(p)
            local cp = vector.round(p)
            local cn = core.get_node(cp)
            if not cn then return false end
            if cn.name:find("deathbox:barrier") then
                deathbox.hit_barrier(cp)
                self.object:remove()
                return true
            elseif cn.name == "deathbox:barrel" then
                deathbox.explode_barrel(cp)
                self.object:remove()
                return true
            elseif cn.name == "deathbox:weapon_box" then
                core.set_node(cp, {name = "air"})
                deathbox.schedule_weapon_box_respawn(cp)
                self.object:remove()
                return true
            elseif cn.name ~= "air" and cn.name ~= "ignore" and cn.name ~= "deathbox:floor" and cn.name ~= "deathbox:bloodpool" then
                self.object:remove()
                return true
            end
            return false
        end
        if moveresult and moveresult.collides then
            local offsets = {
                {x=0,y=0,z=0},{x=0,y=-1,z=0},{x=0,y=1,z=0},
                {x=1,y=0,z=0},{x=-1,y=0,z=0},
                {x=0,y=0,z=1},{x=0,y=0,z=-1},
                {x=1,y=-1,z=0},{x=-1,y=-1,z=0},
                {x=0,y=-1,z=1},{x=0,y=-1,z=-1},
            }
            for _, off in ipairs(offsets) do if check_hit(vector.add(pos, off)) then return end end
            self.object:remove()
            return
        end
        for _, obj in ipairs(core.get_objects_inside_radius(pos, 1.5)) do
            if obj ~= self.object and not obj:is_player() then
                local ent = obj:get_luaentity()
                if ent and (ent.name == "deathbox:zombie" or ent.name == "deathbox:goblin") then -- or ent.name == "deathbox:imp"
                    local mob_pos = obj:get_pos()
                    local mob_pos = obj:get_pos()
                    if mob_pos then
                        local dx = pos.x - mob_pos.x
                        local dz = pos.z - mob_pos.z
                        local horiz_dist = math.sqrt(dx*dx + dz*dz)
                        local dy = pos.y - (mob_pos.y + 0.85)
                        if horiz_dist < 0.35 and math.abs(dy) < 0.85 then
                            local owner_obj = self._owner and core.get_player_by_name(self._owner)
                            if owner_obj then
                                obj:punch(owner_obj, 1.0, {full_punch_interval = 0.1, damage_groups = {fleshy = deathbox.config.flame_damage}}, vel)
                                local mob_pos = obj:get_pos()
                                if mob_pos then
                                   local knock = vector.normalize(vel)
                                   obj:add_velocity({
                                       x = knock.x * 5,
                                       y = 0.1,
                                       z = knock.z * 5
                                   })
                                end
                                self.object:remove()
                                return
                            else deathbox.damage_mob(obj, deathbox.config.flame_damage)
                            end
                            self.object:remove()
                            return
                        end
                    end
                end
            end
        end
    local rounded = vector.round(pos) 
    for _, check in ipairs({rounded, {x=rounded.x, y=rounded.y-1, z=rounded.z}}) do
        if check_hit(check) then return end
    end
end,
})

-- ENTIDADE: Projétil de fogo
core.register_entity("deathbox:flame_ball", {
    initial_properties = {
        hp_max = 1,
        physical = true,
        static_save = false,
        collide_with_objects = false,
        collisionbox = {0.01, -0.15, -0.01, 0.01, 0.15, 0.01},
        visual = "sprite",
        visual_size = {x = 0.5, y = 0.5},
        textures = {"db_flame.png"},
        glow = 8,
        pointable = false,
    },
    _owner = nil,
    _life = 0.8,
    on_step = function(self, dtime, moveresult)
        self._life = self._life - dtime
        if self._life <= 0 then self.object:remove() return end
        local pos = self.object:get_pos()
        if not pos then return end
        local vel = self.object:get_velocity()
        local function check_hit(p)
            local cp = vector.round(p)
            local cn = core.get_node(cp)
            if not cn then return false end
            if cn.name:find("deathbox:barrier") then
                deathbox.hit_barrier(cp)
                self.object:remove()
                return true
            elseif cn.name == "deathbox:barrel" then
                deathbox.explode_barrel(cp)
                self.object:remove()
                return true
            elseif cn.name == "deathbox:weapon_box" then
                core.set_node(cp, {name = "air"})
                deathbox.schedule_weapon_box_respawn(cp)
                self.object:remove()
                return true
            elseif cn.name ~= "air" and cn.name ~= "ignore" and cn.name ~= "deathbox:floor" and cn.name ~= "deathbox:bloodpool" then
                self.object:remove()
                return true
            end
            return false
        end
        if moveresult and moveresult.collides then
            local offsets = {
                {x=0,y=0,z=0},{x=0,y=-1,z=0},{x=0,y=1,z=0},
                {x=1,y=0,z=0},{x=-1,y=0,z=0},
                {x=0,y=0,z=1},{x=0,y=0,z=-1},
                {x=1,y=-1,z=0},{x=-1,y=-1,z=0},
                {x=0,y=-1,z=1},{x=0,y=-1,z=-1},
            }
            for _, off in ipairs(offsets) do if check_hit(vector.add(pos, off)) then return end end
            self.object:remove()
            return
        end
        for _, obj in ipairs(core.get_objects_inside_radius(pos, 1.5)) do
            if obj ~= self.object and obj:is_player() then
                local player_pos = obj:get_pos()
                if player_pos then
                    local dx = pos.x - player_pos.x
                    local dz = pos.z - player_pos.z
                    local horiz_dist = math.sqrt(dx*dx + dz*dz)
                    local dy = pos.y - (player_pos.y + 0.85)
                    if horiz_dist < 0.35 and math.abs(dy) < 0.85 then
                        obj:punch(self.object, 1.0, {full_punch_interval = 0.1, damage_groups = {fleshy = deathbox.config.flame_damage}}, vel)
                        self.object:remove()
                        return
                    end
                end
            elseif obj ~= self.object and not obj:is_player() then
                local ent = obj:get_luaentity()
                if ent and (ent.name == "deathbox:zombie" or ent.name == "deathbox:goblin" or ent.name == "deathbox:imp" or ent.name == "deathbox:demon" or ent.name == "deathbox:demonking") then
                    local mob_pos = obj:get_pos()
                    local mob_pos = obj:get_pos()
                    if mob_pos then
                        local dx = pos.x - mob_pos.x
                        local dz = pos.z - mob_pos.z
                        local horiz_dist = math.sqrt(dx*dx + dz*dz)
                        local dy = pos.y - (mob_pos.y + 0.85)
                        if horiz_dist < 0.35 and math.abs(dy) < 0.85 then
                            local owner_obj = self._owner and core.get_player_by_name(self._owner)
                            if owner_obj then
                                obj:punch(owner_obj, 1.0, {full_punch_interval = 0.1, damage_groups = {fleshy = deathbox.config.flame_damage}}, vel)
                                local mob_pos = obj:get_pos()
                                if mob_pos then
                                   local knock = vector.normalize(vel)
                                   obj:add_velocity({
                                       x = knock.x * 25,
                                       y = 2,
                                       z = knock.z * 25
                                   })
                                end
                                self.object:remove()
                                return
                            else deathbox.damage_mob(obj, deathbox.config.flame_damage)
                            end
                            self.object:remove()
                            return
                        end
                    end
                end
            end
        end
    local rounded = vector.round(pos) -- 475
    for _, check in ipairs({rounded, {x=rounded.x, y=rounded.y-1, z=rounded.z}}) do
        if check_hit(check) then return end
    end
end,
})

-- ENTIDADE: Projétil de fogo
core.register_entity("deathbox:flame_ball2", {
    initial_properties = {
        hp_max = 1,
        physical = true,
        static_save = false,
        collide_with_objects = false,
        collisionbox = {0.01, -0.15, -0.01, 0.01, 0.15, 0.01},
        visual = "sprite",
        visual_size = {x = 0.7, y = 0.7},
        textures = {"db_flame2.png"},
        glow = 14,
        pointable = false,
    },
    _owner = nil,
    _life = 0.8,
    on_step = function(self, dtime, moveresult)
        self._life = self._life - dtime
        if self._life <= 0 then self.object:remove() return end
        local pos = self.object:get_pos()
        if not pos then return end
        local vel = self.object:get_velocity()
        local function check_hit(p)
            local cp = vector.round(p)
            local cn = core.get_node(cp)
            if not cn then return false end
            if cn.name:find("deathbox:barrier") then
                deathbox.hit_barrier(cp)
                self.object:remove()
                return true
            elseif cn.name == "deathbox:barrel" then
                deathbox.explode_barrel(cp)
                self.object:remove()
                return true
            elseif cn.name == "deathbox:weapon_box" then
                core.set_node(cp, {name = "air"})
                deathbox.schedule_weapon_box_respawn(cp)
                self.object:remove()
                return true
            elseif cn.name ~= "air" and cn.name ~= "ignore" and cn.name ~= "deathbox:floor" and cn.name ~= "deathbox:bloodpool" then
                self.object:remove()
                return true
            end
            return false
        end
        if moveresult and moveresult.collides then
            local offsets = {
                {x=0,y=0,z=0},{x=0,y=-1,z=0},{x=0,y=1,z=0},
                {x=1,y=0,z=0},{x=-1,y=0,z=0},
                {x=0,y=0,z=1},{x=0,y=0,z=-1},
                {x=1,y=-1,z=0},{x=-1,y=-1,z=0},
                {x=0,y=-1,z=1},{x=0,y=-1,z=-1},
            }
            for _, off in ipairs(offsets) do if check_hit(vector.add(pos, off)) then return end end
            self.object:remove()
            return
        end
        for _, obj in ipairs(core.get_objects_inside_radius(pos, 1.5)) do
            if obj ~= self.object and obj:is_player() then
                local player_pos = obj:get_pos()
                if player_pos then
                    local dx = pos.x - player_pos.x
                    local dz = pos.z - player_pos.z
                    local horiz_dist = math.sqrt(dx*dx + dz*dz)
                    local dy = pos.y - (player_pos.y + 0.85)
                    if horiz_dist < 0.35 and math.abs(dy) < 0.85 then
                        obj:punch(self.object, 1.0, {full_punch_interval = 0.1, damage_groups = {fleshy = deathbox.config.flame_damage}}, vel)
                        self.object:remove()
                        return
                    end
                end
            elseif obj ~= self.object and not obj:is_player() then
                local ent = obj:get_luaentity()
                if ent and (ent.name == "deathbox:zombie" or ent.name == "deathbox:goblin" or ent.name == "deathbox:imp" or ent.name == "deathbox:demon" or ent.name == "deathbox:demonking") then
                    local mob_pos = obj:get_pos()
                    local mob_pos = obj:get_pos()
                    if mob_pos then
                        local dx = pos.x - mob_pos.x
                        local dz = pos.z - mob_pos.z
                        local horiz_dist = math.sqrt(dx*dx + dz*dz)
                        local dy = pos.y - (mob_pos.y + 0.85)
                        if horiz_dist < 0.35 and math.abs(dy) < 0.85 then
                            local owner_obj = self._owner and core.get_player_by_name(self._owner)
                            if owner_obj then
                                obj:punch(owner_obj, 1.0, {full_punch_interval = 0.1, damage_groups = {fleshy = deathbox.config.flame_damage}}, vel)
                                local mob_pos = obj:get_pos()
                                if mob_pos then
                                   local knock = vector.normalize(vel)
                                   obj:add_velocity({
                                       x = knock.x * 25,
                                       y = 2,
                                       z = knock.z * 25
                                   })
                                end
                                self.object:remove()
                                return
                            else deathbox.damage_mob(obj, deathbox.config.flame_damage)
                            end
                            self.object:remove()
                            return
                        end
                    end
                end
            end
        end
    local rounded = vector.round(pos) -- 475
    for _, check in ipairs({rounded, {x=rounded.x, y=rounded.y-1, z=rounded.z}}) do
        if check_hit(check) then return end
    end
end,
})

-- ENTIDADE: projétil de fogo GIGANTE (3x o tamanho da flame_ball2),
-- disparado reto para cima pelo demonking em seu ataque secundário.
-- Não colide com nada durante a subida: some sozinho após
-- demonking_meteor_rise_time segundos, dando origem a 3 flame_ball2
-- comuns que caem verticalmente sobre pontos aleatórios da arena.
core.register_entity("deathbox:flame_ball2_giant", {
    initial_properties = {
        hp_max = 1,
        physical = false,
        static_save = false,
        collide_with_objects = false,
        visual = "sprite",
        visual_size = {x = 0.7 * 3, y = 0.7 * 3}, -- 3x maior que a flame_ball2 comum
        textures = {"db_flame2.png"},
        glow = 14,
        pointable = false,
    },
    _life = 0,
    on_activate = function(self, staticdata, dtime_s)
        self._life = deathbox.config.demonking_meteor_rise_time
    end,
    on_step = function(self, dtime)
        self._life = self._life - dtime
        if self._life <= 0 then
            local pos = self.object:get_pos()
            if pos then deathbox.spawn_demonking_meteor_rain(pos) end
            self.object:remove()
        end
    end,
})

-- ENTIDADE: meteoro (flame_ball2 comum) que cai verticalmente sobre
-- um ponto aleatório da arena, originado da flame_ball2_giant. Mantém
-- os efeitos comuns de destruição de barril/caixa de arma e dano a
-- jogadores/mobs, mas trata piso e lava de forma especial:
--   - ao colidir com o piso de cima (o caminhável), remove esse node,
--     abrindo uma cratera que revela a lava por baixo;
--   - ao colidir com a lava, apenas remove o projétil (a lava em si
--     nunca é alterada);
--   - o piso de baixo (subestrutura, abaixo da lava) NUNCA é
--     removido/danificado por este projétil.
core.register_entity("deathbox:flame_ball2_meteor", {
    initial_properties = {
        hp_max = 1,
        physical = true,
        static_save = false,
        collide_with_objects = false,
        collisionbox = {0.01, -0.15, -0.01, 0.01, 0.15, 0.01},
        visual = "sprite",
        visual_size = {x = 0.7, y = 0.7},
        textures = {"db_flame2.png"},
        glow = 14,
        pointable = false,
    },
    _owner = nil,
    _life = 6, -- tempo maior que a flame_ball2 comum, para cair de bem mais alto
    on_step = function(self, dtime, moveresult)
        self._life = self._life - dtime
        if self._life <= 0 then self.object:remove() return end
        local pos = self.object:get_pos()
        if not pos then return end
        local vel = self.object:get_velocity()
        local function check_hit(p)
            local cp = vector.round(p)
            local cn = core.get_node(cp)
            if not cn then return false end
            if cn.name:find("deathbox:barrier") then
                deathbox.hit_barrier(cp)
                self.object:remove()
                return true
            elseif cn.name == "deathbox:barrel" then
                deathbox.explode_barrel(cp)
                self.object:remove()
                return true
            elseif cn.name == "deathbox:weapon_box" then
                core.set_node(cp, {name = "air"})
                deathbox.schedule_weapon_box_respawn(cp)
                self.object:remove()
                return true
            elseif cn.name == "default:lava_source" or cn.name == "default:lava_flowing" then
                -- caiu na lava (ex.: em uma cratera já aberta por outro
                -- meteoro): apenas some, nunca mexe na lava nem no que
                -- está abaixo dela.
                self.object:remove()
                return true
            elseif cn.name == "deathbox:floor" then
                -- Só o piso de CIMA (o caminhável) pode ser removido.
                -- O piso de baixo (subestrutura, logo abaixo da lava)
                -- fica sempre no mesmo Y do piso de base e nunca deve
                -- ser tocado por este projétil.
                local floor2_y = deathbox.get_wall_base_y() + 2
                if cp.y >= floor2_y then
                    core.set_node(cp, {name = "air"})
                    core.add_particlespawner({
                        amount = 20, time = 0.05,
                        minpos = vector.subtract(cp, {x=0.4,y=0.1,z=0.4}),
                        maxpos = vector.add(cp, {x=0.4,y=0.4,z=0.4}),
                        minvel = {x=-1,y=1,z=-1}, maxvel = {x=1,y=3,z=1},
                        minexptime = 0.3, maxexptime = 0.7,
                        minsize = 1, maxsize = 4,
                        texture = "db_flame.png",
                    })
                end
                self.object:remove()
                return true
            elseif cn.name ~= "air" and cn.name ~= "ignore" and cn.name ~= "deathbox:bloodpool" then
                self.object:remove()
                return true
            end
            return false
        end
        if moveresult and moveresult.collides then
            local offsets = {
                {x=0,y=0,z=0},{x=0,y=-1,z=0},{x=0,y=1,z=0},
                {x=1,y=0,z=0},{x=-1,y=0,z=0},
                {x=0,y=0,z=1},{x=0,y=0,z=-1},
                {x=1,y=-1,z=0},{x=-1,y=-1,z=0},
                {x=0,y=-1,z=1},{x=0,y=-1,z=-1},
            }
            for _, off in ipairs(offsets) do if check_hit(vector.add(pos, off)) then return end end
            self.object:remove()
            return
        end
        for _, obj in ipairs(core.get_objects_inside_radius(pos, 1.5)) do
            if obj ~= self.object and obj:is_player() then
                local player_pos = obj:get_pos()
                if player_pos then
                    local dx = pos.x - player_pos.x
                    local dz = pos.z - player_pos.z
                    local horiz_dist = math.sqrt(dx*dx + dz*dz)
                    local dy = pos.y - (player_pos.y + 0.85)
                    if horiz_dist < 0.35 and math.abs(dy) < 0.85 then
                        obj:punch(self.object, 1.0, {full_punch_interval = 0.1, damage_groups = {fleshy = deathbox.config.flame_damage}}, vel)
                        self.object:remove()
                        return
                    end
                end
            elseif obj ~= self.object and not obj:is_player() then
                local ent = obj:get_luaentity()
                if ent and (ent.name == "deathbox:zombie" or ent.name == "deathbox:goblin" or ent.name == "deathbox:imp" or ent.name == "deathbox:demon" or ent.name == "deathbox:demonking") then
                    local mob_pos = obj:get_pos()
                    if mob_pos then
                        local dx = pos.x - mob_pos.x
                        local dz = pos.z - mob_pos.z
                        local horiz_dist = math.sqrt(dx*dx + dz*dz)
                        local dy = pos.y - (mob_pos.y + 0.85)
                        if horiz_dist < 0.35 and math.abs(dy) < 0.85 then
                            local owner_obj = self._owner and core.get_player_by_name(self._owner)
                            if owner_obj then
                                obj:punch(owner_obj, 1.0, {full_punch_interval = 0.1, damage_groups = {fleshy = deathbox.config.flame_damage}}, vel)
                            else
                                deathbox.damage_mob(obj, deathbox.config.flame_damage)
                            end
                            self.object:remove()
                            return
                        end
                    end
                end
            end
        end
        local rounded = vector.round(pos)
        for _, check in ipairs({rounded, {x=rounded.x, y=rounded.y-1, z=rounded.z}}) do
            if check_hit(check) then return end
        end
    end,
})


core.register_entity("deathbox:bullet_shot", {
    initial_properties = {
        --hp_max = 1,
        physical = true,
        static_save = false,
        collide_with_objects = false,
        collisionbox = {-0.15, -0.15, -0.15, 0.15, 0.15, 0.15},
        visual = "sprite",
        visual_size = {x = 0.5, y = 0.5},
        textures = {"db_bullet.png"},
        glow = 14,
        pointable = false,
    },
    _owner = nil,
    _life = 3,
    _last_pos = nil,
    on_step = function(self, dtime, moveresult)
        self._life = self._life - dtime
        if self._life <= 0 then self.object:remove() return end
        local pos = self.object:get_pos()
        if not pos then return end
        local vel = self.object:get_velocity()
        -- Posição no passo anterior, usada para varrer todo o trecho
        -- percorrido neste step (ver comentário abaixo).
        local prev_pos = self._last_pos or pos
        self._last_pos = pos
        local function check_hit(p)
            local cp = vector.round(p)
            local cn = core.get_node(cp)
            if not cn then return false end
            if cn.name:find("deathbox:barrier") then
                deathbox.hit_barrier(cp)
                self.object:remove()
                return true
            elseif cn.name == "deathbox:barrel" then
                deathbox.explode_barrel(cp)
                self.object:remove()
                return true
            elseif cn.name == "deathbox:weapon_box" then
                core.set_node(cp, {name = "air"})
                deathbox.schedule_weapon_box_respawn(cp)
                self.object:remove()
                return true
            elseif cn.name ~= "air" and cn.name ~= "ignore" and cn.name ~= "deathbox:floor" and cn.name ~= "deathbox:bloodpool" then
                self.object:remove()
                return true
            end
            return false
        end
        if moveresult and moveresult.collides then
            local offsets = {
                {x=0,y=0,z=0},{x=0,y=-1,z=0},{x=0,y=1,z=0},
                {x=1,y=0,z=0},{x=-1,y=0,z=0},
                {x=0,y=0,z=1},{x=0,y=0,z=-1},
                {x=1,y=-1,z=0},{x=-1,y=-1,z=0},
                {x=0,y=-1,z=1},{x=0,y=-1,z=-1},
            }
            for _, off in ipairs(offsets) do if check_hit(vector.add(pos, off)) then return end end
            self.object:remove()
            return
        end
        local function try_hit_mobs_at(p)
            for _, obj in ipairs(core.get_objects_inside_radius(p, 1.5)) do
                if obj ~= self.object and not obj:is_player() then
                    local ent = obj:get_luaentity()
                    if ent and (ent.name == "deathbox:zombie" or ent.name == "deathbox:goblin" or ent.name == "deathbox:imp" or ent.name == "deathbox:demon" or ent.name == "deathbox:demonking") then
                        local mob_pos = obj:get_pos()
                        if mob_pos then
                            local dx = p.x - mob_pos.x
                            local dz = p.z - mob_pos.z
                            local horiz_dist = math.sqrt(dx*dx + dz*dz)
                            local dy = p.y - (mob_pos.y + 0.85)
                            if horiz_dist < 0.35 and math.abs(dy) < 0.85 then
                                local owner_obj = self._owner and core.get_player_by_name(self._owner)
                                if owner_obj then
                                    obj:punch(owner_obj, 1.0, {full_punch_interval = 0.1, damage_groups = {fleshy = deathbox.config.bullet_damage}}, vel)
                                    local knock = vector.normalize(vel)
                                    obj:add_velocity({
                                        x = knock.x * 25,
                                        y = 0.5,
                                        z = knock.z * 25
                                    })
                                else deathbox.damage_mob(obj, deathbox.config.bullet_damage)
                                end
                                self.object:remove()
                                return true
                            end
                        end
                    end
                end
            end
            return false
        end
        local seg = vector.subtract(pos, prev_pos)
        local seg_len = vector.length(seg)
        local samples = math.max(1, math.ceil(seg_len / 0.1))
        for i = 0, samples do
            local t = i / samples
            local sample_pos = vector.add(prev_pos, vector.multiply(seg, t))
            if try_hit_mobs_at(sample_pos) then return end
        end
        local rounded = vector.round(pos)
        for _, check in ipairs({rounded, {x=rounded.x, y=rounded.y-1, z=rounded.z}}) do if check_hit(check) then return end end
    end,
})

-- ENTIDADE: Zumbi
core.register_entity("deathbox:zombie", {
    initial_properties = {
        hp_max = deathbox.config.zombie_hp,
        physical = true,
        static_save = false,
        collide_with_objects = true,
        collisionbox = {-0.25, 0.0, -0.25, 0.25, 1.7, 0.25},
        visual = "mesh",
        mesh = "db_zumbi.glb",
        textures = {"db_zombie.png^[colorize:#888888:50"},
        visual_size = {x = 1, y = 1},
        stepheight = 0.6,
        makes_footstep_sound = true,
    },
    _attack_timer = 0,
    _dying = false,
    on_activate = function(self, staticdata, dtime_s)
        self._dying = false
        self._last_puncher = nil
        self.object:set_armor_groups({fleshy = 100})
        self.object:set_acceleration({x = 0, y = -10, z = 0})
        self.object:set_hp(deathbox.config.zombie_hp)
        self._last_hp = deathbox.config.zombie_hp
        self.object:set_animation({x = 168 / 30, y = 187 / 30}, 1, 0, true)
    end,
    on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
        -- Interceptamos o dano manualmente para podermos tocar a
        -- animação de morte antes de o engine remover o mob.
        if self._dying then
            local vy = self.object:get_velocity().y
            self.object:set_velocity({x = 0, y = math.min(vy, 0), z = 0})
            return true
        end
        self._last_puncher = puncher
        local new_hp = self.object:get_hp() - damage
        if new_hp <= 0 then deathbox.mob_start_death(self)
        core.sound_play("db_zombie_die", {pos = self.object:get_pos(), gain = 0.01}, true) --default_dig_cracky
        else
            self.object:set_hp(new_hp)
            -- Knockback e sangue ao tomar dano
            local self_pos = self.object:get_pos()
            deathbox.spawn_bloodpool(self_pos)
            core.sound_play("db_zombie_hurt", {pos = self.object:get_pos(), gain = 0.01}, true) 
            if puncher and puncher:get_pos() then deathbox.apply_knockback(self.object, puncher:get_pos(), 4) end
        end
        return true  -- cancela o mecanismo padrão de dano do engine
    end,
    on_step = function(self, dtime, moveresult)
        if self._dying then
            -- Enquanto morre, cancela qualquer velocidade horizontal
            -- que o engine ou um punch residual tenha aplicado.
            local vy = self.object:get_velocity().y
            self.object:set_velocity({x = 0, y = math.min(vy, 0), z = 0})
            return
        end
        self._attack_timer = self._attack_timer + dtime
        if not deathbox.state.running then return end
        local self_pos = self.object:get_pos()
        local nearest, nearest_dist = nil, math.huge
        for _, player in ipairs(core.get_connected_players()) do
            local hp = player:get_hp()
            if hp and hp > 0 then
                local dist = vector.distance(self_pos, player:get_pos())
                if dist < nearest_dist then
                    nearest = player
                    nearest_dist = dist
                end
            end
        end
        if not nearest then self.object:set_velocity({x = 0, y = self.object:get_velocity().y, z = 0}) return end
        local dir = vector.subtract(nearest:get_pos(), self_pos)
        dir.y = 0
        local len = vector.length(dir)
        if len > 1.1 then
            dir = vector.normalize(dir)
            local vel = vector.multiply(dir, deathbox.config.zombie_speed)
            vel.y = self.object:get_velocity().y
            self.object:set_velocity(vel)
            self.object:set_yaw(math.atan2(-dir.x, dir.z))
        else
            self.object:set_velocity({x = 0, y = self.object:get_velocity().y, z = 0})
            if self._attack_timer >= deathbox.config.zombie_attack_cooldown then
                self._attack_timer = 0
                nearest:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = deathbox.config.zombie_damage}}, nil)
            end
        end
    end,
    on_death = function(self, killer)
        -- Fallback: só chega aqui se set_hp(0) foi chamado diretamente
        -- (ex.: dbstop). Evita dupla contagem se já iniciamos a morte.
        if self._dying then return end
        deathbox.state.alive_zombies = math.max(0, deathbox.state.alive_zombies - 1)
        deathbox.check_wave_complete()
    end,
})

-- ENTIDADE: goblin
core.register_entity("deathbox:goblin", {
    initial_properties = {
        hp_max = deathbox.config.zombie_hp,
        physical = true,
        static_save = false,
        collide_with_objects = true,
        collisionbox = {-0.15, 0.0, -0.15, 0.15, 1.7, 0.15},
        visual = "mesh",
        mesh = "character.b3d",
        textures = {"db_goblin.png^[multiply:#128332:50"},
        visual_size = {x = 0.7, y = 0.7},
        stepheight = 0.6,
        makes_footstep_sound = true,
        glow = 1,
    },
    _attack_timer = 0,
    _dying = false,
    on_activate = function(self, staticdata, dtime_s)
        self._dying = false
        self._last_puncher = nil
        self.object:set_armor_groups({fleshy = 100})
        self.object:set_acceleration({x = 0, y = -10, z = 0})
        self.object:set_hp(deathbox.config.zombie_hp)
        self._last_hp = deathbox.config.zombie_hp
        self.object:set_animation({x = 168, y = 187}, 30, 0, true)
    end,
    on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
        if self._dying then
            local vy = self.object:get_velocity().y
            self.object:set_velocity({x = 0, y = math.min(vy, 0), z = 0})
            return true
        end
        self._last_puncher = puncher
        local new_hp = self.object:get_hp() - damage
        if new_hp <= 0 then deathbox.mob_start_death(self)
        core.sound_play("db_goblin_die", {pos = self.object:get_pos(), gain = 0.1}, true) --default_dig_cracky
        else
            self.object:set_hp(new_hp)
            local self_pos = self.object:get_pos()
            deathbox.spawn_bloodpool(self_pos)
            core.sound_play("db_goblin_hurt", {pos = self.object:get_pos(), gain = 0.1}, true) --default_dig_cracky
            if puncher and puncher:get_pos() then deathbox.apply_knockback(self.object, puncher:get_pos(), 4) end
        end
        return true
    end,
    on_step = function(self, dtime, moveresult)
        if self._dying then
            -- Enquanto morre, cancela qualquer velocidade horizontal
            -- que o engine ou um punch residual tenha aplicado.
            local vy = self.object:get_velocity().y
            self.object:set_velocity({x = 0, y = math.min(vy, 0), z = 0})
            return
        end
        self._attack_timer = self._attack_timer + dtime
        if not deathbox.state.running then return end
        local self_pos = self.object:get_pos()
        local nearest, nearest_dist = nil, math.huge
        for _, player in ipairs(core.get_connected_players()) do
            local hp = player:get_hp()
            if hp and hp > 0 then
                local dist = vector.distance(self_pos, player:get_pos())
                if dist < nearest_dist then
                    nearest = player
                    nearest_dist = dist
                end
            end
        end
        if not nearest then self.object:set_velocity({x = 0, y = self.object:get_velocity().y, z = 0}) return end
        local dir = vector.subtract(nearest:get_pos(), self_pos)
        dir.y = 0
        local len = vector.length(dir)
        if len > 0.5 then
            dir = vector.normalize(dir)
            local vel = vector.multiply(dir, deathbox.config.goblin_speed)
            vel.y = self.object:get_velocity().y
            self.object:set_velocity(vel)
            self.object:set_yaw(math.atan2(-dir.x, dir.z))
        else
            self.object:set_velocity({x = 0, y = self.object:get_velocity().y, z = 0})
            if self._attack_timer >= deathbox.config.zombie_attack_cooldown then
                self._attack_timer = 0
                nearest:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = deathbox.config.zombie_damage}}, nil)
            end
        end
    end,
    on_death = function(self, killer)
        if self._dying then return end
        deathbox.state.alive_zombies = math.max(0, deathbox.state.alive_zombies - 1)
        deathbox.check_wave_complete()
    end,
})

-- Acha a posição da caixa de arma mais próxima de "pos", dentro da
-- área da arena. Usado pelo imp para sempre priorizar destruir
-- caixas antes de atacar o jogador. Retorna nil se não houver
-- nenhuma caixa no mapa no momento.
function deathbox.find_nearest_weapon_box(pos)
    local origin = deathbox.state.map_origin
    if not origin then return nil end
    local p1 = {x = origin.x, y = origin.y, z = origin.z}
    local p2 = {
        x = origin.x + deathbox.state.map_w - 1,
        y = origin.y,
        z = origin.z + deathbox.state.map_h - 1,
    }
    local found = core.find_nodes_in_area(p1, p2, {"deathbox:weapon_box"})
    if not found or #found == 0 then return nil end
    local nearest, nearest_dist = nil, math.huge
    for _, box_pos in ipairs(found) do
        local dist = vector.distance(pos, box_pos)
        if dist < nearest_dist then
            nearest = box_pos
            nearest_dist = dist
        end
    end
    return nearest
end

-- Destrói a caixa de arma na posição informada, sem dropar nenhum
-- item (é o imp "comendo" a caixa, e não um jogador abrindo ela).
function deathbox.imp_destroy_box(pos)
    if core.get_node(pos).name ~= "deathbox:weapon_box" then return end
    core.set_node(pos, {name = "air"})
    core.sound_play("default_dig_cracky", {pos = pos, gain = 0.5, max_hear_distance = 10}, true)
    core.add_particlespawner({
        amount = 8, time = 0.2,
        minpos = vector.subtract(pos, {x=0.3,y=0.3,z=0.3}),
        maxpos = vector.add(pos, {x=0.3,y=0.3,z=0.3}),
        minvel = {x=-1,y=1,z=-1}, maxvel = {x=1,y=3,z=1},
        minexptime = 0.3, maxexptime = 0.6,
        minsize = 1, maxsize = 2,
        texture = "db_dust.png",
    })
    deathbox.schedule_weapon_box_respawn(pos)
end

-- ENTIDADE: imp
-- Prioridade do imp: enquanto existir qualquer caixa de arma na
-- arena, ele abandona a perseguição ao jogador e vai destruí-la.
-- A busca pela caixa mais próxima é refeita periodicamente, então
-- se uma caixa nova surgir enquanto ele já estiver indo atacar o
-- jogador, ele detecta na próxima busca e troca de alvo na hora,
-- indo destruir a caixa nova antes de voltar a perseguir alguém.
core.register_entity("deathbox:imp", {
    initial_properties = {
        hp_max = deathbox.config.zombie_hp,
        physical = true,
        static_save = false,
        collide_with_objects = true,
        collisionbox = {-0.15, 0.0, -0.15, 0.15, 1.7, 0.15},
        visual = "mesh",
        mesh = "db_demonking.glb",
        textures = {"db_imp.png^[multiply:#ed1c24:50"},
        visual_size = {x = 0.7, y = 0.7},
        stepheight = 0.6,
        makes_footstep_sound = true,
        glow = 1,
    },
    _attack_timer = 0,
    _box_search_timer = 0,
    _target_box_pos = nil,
    _dying = false,
    on_activate = function(self, staticdata, dtime_s)
        self._dying = false
        self._last_puncher = nil
        self.object:set_armor_groups({fleshy = 100})
        self.object:set_acceleration({x = 0, y = -10, z = 0})
        self.object:set_hp(deathbox.config.zombie_hp)
        self._last_hp = deathbox.config.zombie_hp
        self.object:set_animation({x = 168 / 30, y = 187 / 30}, 1, 0, true)
        self._attack_timer = 0
        self._box_search_timer = 0
        self._target_box_pos = nil
    end,
    on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
        if self._dying then
            local vy = self.object:get_velocity().y
            self.object:set_velocity({x = 0, y = math.min(vy, 0), z = 0})
            return true
        end
        self._last_puncher = puncher
        local new_hp = self.object:get_hp() - damage
        if new_hp <= 0 then deathbox.mob_start_death(self)
        core.sound_play("db_imp_die", {pos = self.object:get_pos(), gain = 0.05}, true) --default_dig_cracky
        else
            self.object:set_hp(new_hp)
            local self_pos = self.object:get_pos()
            deathbox.spawn_bloodpool(self_pos)
            core.sound_play("db_imp_hurt", {pos = self.object:get_pos(), gain = 0.05}, true) 
            if puncher and puncher:get_pos() then deathbox.apply_knockback(self.object, puncher:get_pos(), 4) end
        end
        return true
    end,
    on_step = function(self, dtime, moveresult)
        if self._dying then
            -- Enquanto morre, cancela qualquer velocidade horizontal
            -- que o engine ou um punch residual tenha aplicado.
            local vy = self.object:get_velocity().y
            self.object:set_velocity({x = 0, y = math.min(vy, 0), z = 0})
            return
        end
        self._attack_timer = self._attack_timer + dtime
        if not deathbox.state.running then return end
        local self_pos = self.object:get_pos()
        -- Refaz a busca pela caixa mais próxima periodicamente (não
        -- precisa ser todo frame). Se a caixa que ele já estava de
        -- olho foi destruída por outra coisa nesse meio tempo
        -- (jogador, barril, etc.), descarta o alvo na hora.
        self._box_search_timer = self._box_search_timer + dtime
        if self._box_search_timer >= 0.3 then
            self._box_search_timer = 0
            self._target_box_pos = deathbox.find_nearest_weapon_box(self_pos)
        elseif self._target_box_pos and core.get_node(self._target_box_pos).name ~= "deathbox:weapon_box" then self._target_box_pos = nil
        end
        if self._target_box_pos then
            local box_pos = self._target_box_pos
            local dir = vector.subtract({x = box_pos.x, y = self_pos.y, z = box_pos.z}, self_pos)
            dir.y = 0
            local len = vector.length(dir)
            if len > 1.0 then
                dir = vector.normalize(dir)
                local vel = vector.multiply(dir, deathbox.config.imp_speed)
                vel.y = self.object:get_velocity().y
                self.object:set_velocity(vel)
                self.object:set_yaw(math.atan2(-dir.x, dir.z))
            else
                self.object:set_velocity({x = 0, y = self.object:get_velocity().y, z = 0})
                deathbox.imp_destroy_box(box_pos)
                self._target_box_pos = nil
            end
            return -- com uma caixa-alvo definida, ignora completamente o jogador
        end

        -- Sem nenhuma caixa na arena: comportamento normal, persegue
        -- e ataca o jogador mais próximo.
        local nearest, nearest_dist = nil, math.huge
        for _, player in ipairs(core.get_connected_players()) do
            local hp = player:get_hp()
            if hp and hp > 0 then
                local dist = vector.distance(self_pos, player:get_pos())
                if dist < nearest_dist then
                    nearest = player
                    nearest_dist = dist
                end
            end
        end
        if not nearest then self.object:set_velocity({x = 0, y = self.object:get_velocity().y, z = 0}) return end
        local dir = vector.subtract(nearest:get_pos(), self_pos)
        dir.y = 0
        local len = vector.length(dir)
        if len > 0.5 then
            dir = vector.normalize(dir)
            local vel = vector.multiply(dir, deathbox.config.goblin_speed)
            vel.y = self.object:get_velocity().y
            self.object:set_velocity(vel)
            self.object:set_yaw(math.atan2(-dir.x, dir.z))
        else
            self.object:set_velocity({x = 0, y = self.object:get_velocity().y, z = 0})
            if self._attack_timer >= deathbox.config.zombie_attack_cooldown then
                self._attack_timer = 0
                nearest:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = deathbox.config.zombie_damage}}, nil)
            end
        end
    end,
    on_death = function(self, killer)
        if self._dying then return end
        deathbox.state.alive_zombies = math.max(0, deathbox.state.alive_zombies - 1)
        deathbox.check_wave_complete()
    end,
})

-- ENTIDADE: Demon
core.register_entity("deathbox:demon", {
    initial_properties = {
        hp_max = deathbox.config.demon_hp,
        physical = true,
        static_save = false,
        collide_with_objects = true,
        collisionbox = {-0.25, 0.0, -0.25, 0.25, 1.7, 0.25},
        visual = "mesh",
        mesh = "db_demonking.glb",
        textures = {"db_demon.png^[multiply:#ed1c24:100"},
        visual_size = {x = 1, y = 1.25},
        stepheight = 0.6,
        makes_footstep_sound = true,
        glow = 4,
    },
    _attack_timer = 0,
    _melee_timer = 0,
    _burst_count = 0,
    _burst_timer = 0,
    _in_burst = false,
    _burst_target = nil,
    _dying = false,
    on_activate = function(self, staticdata, dtime_s)
        self._dying = false
        self._last_puncher = nil
        self.object:set_armor_groups({fleshy = 100})
        self.object:set_acceleration({x = 0, y = -10, z = 0})
        self.object:set_hp(deathbox.config.demon_hp)
        self._last_hp = deathbox.config.demon_hp
        self.object:set_animation({x = 168 / 30, y = 187 / 30}, 1, 0, true)
        self._attack_timer = 0
        self._melee_timer = 0
        self._burst_count = 0
        self._burst_timer = 0
        self._in_burst = false
        self._burst_target = nil
    end,
    on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
        if self._dying then
            local vy = self.object:get_velocity().y
            self.object:set_velocity({x = 0, y = math.min(vy, 0), z = 0})
            return true
        end
        self._last_puncher = puncher
        local new_hp = self.object:get_hp() - damage
        if new_hp <= 0 then deathbox.mob_start_death(self)
        core.sound_play("db_demon_die", {pos = self.object:get_pos(), gain = 0.05}, true) --default_dig_cracky
        else
            self.object:set_hp(new_hp)
            local self_pos = self.object:get_pos()
            deathbox.spawn_bloodpool(self_pos)
            core.sound_play("db_demon_hurt", {pos = self.object:get_pos(), gain = 0.05}, true) --default_dig_cracky
            if puncher and puncher:get_pos() then
                deathbox.apply_knockback(self.object, puncher:get_pos(), 4)
            end
        end
        return true
    end,
    on_step = function(self, dtime, moveresult)
        if self._dying then
            -- Enquanto morre, cancela qualquer velocidade horizontal
            -- que o engine ou um punch residual tenha aplicado.
            local vy = self.object:get_velocity().y
            self.object:set_velocity({x = 0, y = math.min(vy, 0), z = 0})
            return
        end
        if not deathbox.state.running then return end
        local self_pos = self.object:get_pos()
        local nearest, nearest_dist = nil, math.huge
        for _, player in ipairs(core.get_connected_players()) do
            local hp = player:get_hp()
            if hp and hp > 0 then
                local dist = vector.distance(self_pos, player:get_pos())
                if dist < nearest_dist then
                    nearest = player
                    nearest_dist = dist
                end
            end
        end
        if not nearest then self.object:set_velocity({x=0, y=self.object:get_velocity().y, z=0}) return end
        local dir = vector.subtract(nearest:get_pos(), self_pos)
        dir.y = 0
        local len = vector.length(dir)
        self._melee_timer = self._melee_timer + dtime
        if len <= 1.1 then
            if self._melee_timer >= deathbox.config.zombie_attack_cooldown then
                self._melee_timer = 0
                nearest:punch(self.object, 1.0, {ull_punch_interval = 1.0, damage_groups = {fleshy = deathbox.config.demon_damage}}, nil)
            end
        end
        if len > 0.1 then
            dir = vector.normalize(dir)
            local speed = self._in_burst and 0 or deathbox.config.zombie_speed
            local vel = vector.multiply(dir, speed)
            vel.y = self.object:get_velocity().y
            self.object:set_velocity(vel)
            self.object:set_yaw(math.atan2(-dir.x, dir.z))
        end
        if self._in_burst then
            self._burst_timer = self._burst_timer - dtime
            if self._burst_timer <= 0 then
                local target = self._burst_target
                if target and target:is_player() and target:get_hp() > 0 then
                    local tpos = self.object:get_pos()
                    tpos.y = tpos.y + 0.85
                    local tdir = vector.subtract(vector.add(target:get_pos(), {x=0, y=0.85, z=0}), tpos)
                    local tlen = vector.length(tdir)
                    if tlen > 0 then
                        tdir = vector.normalize(tdir)
                        local proj = core.add_entity(vector.add(tpos, vector.multiply(tdir, 0.8)), "deathbox:flame_ball")
                        if proj then
                            proj:set_velocity(vector.multiply(tdir, deathbox.config.flame_speed))
                            local ent = proj:get_luaentity()
                            if ent then ent._owner = nil end
                        end
                    end
                end
                self._burst_count = self._burst_count + 1
                if self._burst_count >= 6 then
                    self._in_burst    = false
                    self._burst_count = 0
                    self._attack_timer = 0
                else self._burst_timer = 0.3
                end
            end
        else
            self._attack_timer = self._attack_timer + dtime
            if self._attack_timer >= 1 and len <= 6 then
                self._in_burst     = true
                self._burst_count  = 0
                self._burst_timer  = 0
                self._burst_target = nearest
            end
        end
    end,
    on_death = function(self, killer)
        if self._dying then return end
        deathbox.state.alive_zombies = math.max(0, deathbox.state.alive_zombies - 1)
        deathbox.check_wave_complete()
    end,
})

-- ENTIDADE: Demon King
core.register_entity("deathbox:demonking", {
    initial_properties = {
        hp_max = deathbox.config.demonking_hp,
        physical = true,
        static_save = false,
        collide_with_objects = true,
        collisionbox = {-0.5, 0.0, -0.5, 0.5, 3.4, 0.5},
        visual = "mesh",
        mesh = "db_demonking.glb",
        textures = {"db_demonking.png^[multiply:#ed1c24:50"},
        visual_size = {x = 1.25, y = 1.5},
        stepheight = 0.6,
        makes_footstep_sound = true,
        glow = 10,
    },
    _attack_timer = 0,
    _melee_timer = 0,
    _burst_count = 0,
    _burst_timer = 0,
    _in_burst = false,
    _burst_target = nil,
    _meteor_timer = 0,
    _dying = false,
    on_activate = function(self, staticdata, dtime_s)
        self._dying = false
        self._last_puncher = nil
        self.object:set_armor_groups({fleshy = 100})
        self.object:set_acceleration({x = 0, y = -10, z = 0})
        self.object:set_hp(deathbox.config.demonking_hp)
        self._last_hp = deathbox.config.demonking_hp
        -- db_demonking.glb é glTF: a faixa de animação é em SEGUNDOS na
        -- timeline do próprio modelo, não em "frames" do character.b3d.
        -- O ciclo de "andar" do esqueleto original (frames 168-187 a
        -- 30fps) foi exportado preservando o mesmo timing, então
        -- equivale a 168/30 .. 187/30 segundos nesta timeline. Velocidade
        -- 1 = tempo real (recomendado pela documentação da Luanti p/ glTF).
        self.object:set_animation({x = 168 / 30, y = 187 / 30}, 1, 0, true)
        self._attack_timer = 0
        self._melee_timer = 0
        self._burst_count = 0
        self._burst_timer = 0
        self._in_burst = false
        self._burst_target = nil
        self._meteor_timer = deathbox.config.demonking_meteor_cooldown
    end,
    on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
        if self._dying then
            local vy = self.object:get_velocity().y
            self.object:set_velocity({x = 0, y = math.min(vy, 0), z = 0})
            return true
        end
        self._last_puncher = puncher
        local new_hp = self.object:get_hp() - damage
        if new_hp <= 0 then deathbox.mob_start_death(self)
        core.sound_play("db_devil_die", {pos = self.object:get_pos(), gain = 0.05}, true) --default_dig_cracky
        else
            self.object:set_hp(new_hp)
            local self_pos = self.object:get_pos()
            deathbox.spawn_bloodpool(self_pos)
            core.sound_play("db_devil_hurt", {pos = self.object:get_pos(), gain = 0.05}, true) --default_dig_cracky
            if puncher and puncher:get_pos() then deathbox.apply_knockback(self.object, puncher:get_pos(), 4) end
        end
        return true
    end,
    on_step = function(self, dtime, moveresult)
        if self._dying then
            -- Enquanto morre, cancela qualquer velocidade horizontal
            -- que o engine ou um punch residual tenha aplicado.
            local vy = self.object:get_velocity().y
            self.object:set_velocity({x = 0, y = math.min(vy, 0), z = 0})
            return
        end
        if not deathbox.state.running then return end
        local self_pos = self.object:get_pos()
        local nearest, nearest_dist = nil, math.huge
        for _, player in ipairs(core.get_connected_players()) do
            local hp = player:get_hp()
            if hp and hp > 0 then
                local dist = vector.distance(self_pos, player:get_pos())
                if dist < nearest_dist then
                    nearest = player
                    nearest_dist = dist
                end
            end
        end
        if not nearest then self.object:set_velocity({x=0, y=self.object:get_velocity().y, z=0}) return end
        local dir = vector.subtract(nearest:get_pos(), self_pos)
        dir.y = 0
        local len = vector.length(dir)
        self._melee_timer = self._melee_timer + dtime
        if len <= 1.1 then
            if self._melee_timer >= deathbox.config.zombie_attack_cooldown then
                self._melee_timer = 0
                nearest:punch(self.object, 1.0, {ull_punch_interval = 1.0, damage_groups = {fleshy = deathbox.config.demonking_damage}}, nil)
            end
        end
        if len > 0.1 then
            dir = vector.normalize(dir)
            local speed = self._in_burst and 0 or deathbox.config.demonking_speed
            local vel = vector.multiply(dir, speed)
            vel.y = self.object:get_velocity().y
            self.object:set_velocity(vel)
            self.object:set_yaw(math.atan2(-dir.x, dir.z))
        end
        if self._in_burst then
            self._burst_timer = self._burst_timer - dtime
            if self._burst_timer <= 0 then
                local target = self._burst_target
                if target and target:is_player() and target:get_hp() > 0 then
                    local tpos = self.object:get_pos()
                    tpos.y = tpos.y + 0.85
                    local tdir = vector.subtract(vector.add(target:get_pos(), {x=0, y=0.85, z=0}), tpos)
                    local tlen = vector.length(tdir)
                    if tlen > 0 then
                        tdir = vector.normalize(tdir)
                        -- "frente" do leque = direção até o alvo no momento da
                        -- explosão (tdir); "direita" é tdir rotacionado 90°.
                        local forward = {x = tdir.x, y = 0, z = tdir.z}
                        local right = {x = forward.z, y = 0, z = -forward.x}
                        local back = {x = -forward.x, y = 0, z = -forward.z}
                        local left = {x = -right.x, y = 0, z = -right.z}
                        local dirs = {
                            forward,
                            back,
                            right,
                            left,
                            vector.normalize(vector.add(forward, right)),
                            vector.normalize(vector.add(forward, left)),
                            vector.normalize(vector.add(back, right)),
                            vector.normalize(vector.add(back, left)),
                        }
                        for _, d in ipairs(dirs) do
                            local shot_dir = vector.normalize(d)
                            local proj = core.add_entity(vector.add(tpos, vector.multiply(shot_dir, 0.8)), "deathbox:flame_ball2")
                            if proj then
                                proj:set_velocity(vector.multiply(shot_dir, deathbox.config.flame_speed))
                                local ent = proj:get_luaentity()
                                if ent then ent._owner = nil end
                            end
                        end
                    end
                end
                self._burst_count = self._burst_count + 1
                if self._burst_count >= 6 then
                    self._in_burst    = false
                    self._burst_count = 0
                    self._attack_timer = 0
                else self._burst_timer = 0.3
                end
            end
        else
            self._attack_timer = self._attack_timer + dtime
            if self._attack_timer >= 1 and len <= 12 then
                self._in_burst     = true
                self._burst_count  = 0
                self._burst_timer  = 0
                self._burst_target = nearest
            else
                -- Ataque secundário (chuva de meteoros): só entra em
                -- cooldown/ativa quando o demonking está com menos da
                -- metade do HP e o jogador está longe demais para o
                -- ataque normal (fora do alcance demonking_meteor_range).
                self._meteor_timer = self._meteor_timer - dtime
                local hp = self.object:get_hp()
                if self._meteor_timer <= 0
                and hp <= deathbox.config.demonking_hp / 2
                and len > deathbox.config.demonking_meteor_range then
                    self._meteor_timer = deathbox.config.demonking_meteor_cooldown
                    local launch_pos = self.object:get_pos()
                    launch_pos.y = launch_pos.y + 2.0
                    local proj = core.add_entity(launch_pos, "deathbox:flame_ball2_giant")
                    if proj then
                        proj:set_velocity({x = 0, y = deathbox.config.demonking_meteor_rise_speed, z = 0})
                        local ent = proj:get_luaentity()
                        if ent then ent._owner = nil end
                    end
                    core.sound_play("tnt_explode", {pos = launch_pos, gain = 0.4, max_hear_distance = 32}, true)
                end
            end
        end
    end,
    on_death = function(self, killer)
        if self._dying then return end
        deathbox.state.alive_zombies = math.max(0, deathbox.state.alive_zombies - 1)
        deathbox.check_wave_complete()
    end,
})


-- BARRIL EXPLOSIVO
function deathbox.explode_barrel(pos)
    local cfg = deathbox.config
    -- evita explosões duplicadas do mesmo barril
    if core.get_node(pos).name ~= "deathbox:barrel" then return end
    core.set_node(pos, {name = "air"})
    core.sound_play("tnt_explode", {pos = pos, gain = 1, max_hear_distance = 32}, true)
    core.add_particlespawner({
        amount = 50,
        glow = 14,
        time = 0.05,
        minpos = vector.subtract(pos, {x = 0.3, y = 0.3, z = 0.3}),
        maxpos = vector.add(pos, {x = 0.3, y = 0.3, z = 0.3}),
        minvel = {x = -3, y = 1, z = -3},
        maxvel = {x = 3, y = 4, z = 3},
        minexptime = 0.4,
        maxexptime = 1.0,
        minsize = 1,
        maxsize = 10,
        texture = "db_flame.png",
    })
    -- reação em cadeia + dano em barreiras
    for x = pos.x - cfg.barrel_explosion_radius, pos.x + cfg.barrel_explosion_radius do
        for y = pos.y - 1, pos.y + 2 do
            for z = pos.z - cfg.barrel_explosion_radius, pos.z + cfg.barrel_explosion_radius do
                local p = {x=x, y=y, z=z}
                local dist = vector.distance(pos, p)
                if dist <= cfg.barrel_explosion_radius then
                    local node = core.get_node(p)
                    -- explode barris próximos
                    if node.name == "deathbox:barrel" then
                        if not vector.equals(p, pos) then
                            core.after(0.05, function() if core.get_node(p).name == "deathbox:barrel" then deathbox.explode_barrel(p) end end)
                        end
                    -- causa dano em barreiras
                    elseif node.name:find("deathbox:barrier") then
                        deathbox.hit_barrier(p)
                        deathbox.hit_barrier(p)
                        deathbox.hit_barrier(p)
                        deathbox.hit_barrier(p)
                        deathbox.hit_barrier(p)
                    -- destrói na hora qualquer caixa de arma próxima
                    elseif node.name == "deathbox:weapon_box" then
                        core.set_node(p, {name = "air"})
                        core.add_particlespawner({
                            amount = 6, time = 0.1,
                            minpos = vector.subtract(p, {x=0.3,y=0.3,z=0.3}),
                            maxpos = vector.add(p, {x=0.3,y=0.3,z=0.3}),
                            minvel = {x=-1,y=1,z=-1}, maxvel = {x=1,y=3,z=1},
                            minexptime = 0.3, maxexptime = 0.6,
                            minsize = 1, maxsize = 2,
                            texture = "db_dust.png",
                        })
                        deathbox.schedule_weapon_box_respawn(p)
                    end
                end
            end
        end
    end
    -- dano em entidades
    for _, obj in ipairs(core.get_objects_inside_radius(pos, cfg.barrel_explosion_radius)) do
        local obj_pos = obj:get_pos()
        if not obj_pos then goto continue end
        local dir = vector.direction(pos, obj_pos)
        local dist = math.max(1, vector.distance(pos, obj_pos))
        local force = 12 / dist
        local ent = obj:get_luaentity()
        if ent and (ent.name == "deathbox:zombie" or ent.name == "deathbox:goblin" or ent.name == "deathbox:imp" or ent.name == "deathbox:demon" or ent.name == "deathbox:demonking") then
            obj:punch(nil, 1, {full_punch_interval = 0.1, damage_groups = {fleshy = cfg.barrel_explosion_damage}}, nil)
            obj:add_velocity({
                x = dir.x * force,
                y = force * 0.2,
                z = dir.z * force
            })
        elseif obj:is_player() then
            obj:punch(nil, 1, {full_punch_interval = 0.1, damage_groups = {fleshy = math.floor(cfg.barrel_explosion_damage / 2)}}, nil)
            obj:add_velocity({
                x = dir.x * force,
                y = force * 0.2,
                z = dir.z * force
            })
        end
        ::continue::
    end
end
core.register_node("deathbox:bloodpool", {
    description = "Poça de Sangue",
    drawtype = "mesh",
    mesh = "db_bloodpool.obj",
    tiles = {"db_bloodpool.png"},
    use_texture_alpha = "clip",
    paramtype = "light",
    walkable = false,
    pointable = true,
    buildable_to = true,
    selection_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, -0.45, 0.5}}
})

-- Cria uma poça de sangue no piso, abaixo da posição de quem foi
-- atingido (jogador ou mob). Procura o piso da arena (deathbox:floor)
-- descendo a partir da posição informada, e coloca a poça no node
-- vazio imediatamente acima dele.
function deathbox.spawn_bloodpool(pos)
    if not pos then return end
    local p = vector.round(pos)
    for dy = 0, -2, -1 do
        local floor_pos = {x = p.x, y = p.y + dy, z = p.z}
        local floor_node = core.get_node(floor_pos)
        if floor_node and floor_node.name == "deathbox:floor" then
            local above = {x = floor_pos.x, y = floor_pos.y + 1, z = floor_pos.z}
            local above_node = core.get_node(above)
            if above_node and (above_node.name == "air" or above_node.name == "deathbox:bloodpool") then
                core.set_node(above, {name = "deathbox:bloodpool"})
            end
            return
        end
    end
end


-- Teleporta o jogador para o ponto de spawn OFICIAL do mundo: o mesmo
-- ponto exato para onde o minetest_game manda o jogador quando ele
-- morre e respawna (e não uma posição aproximada/"parecida" perto dali).
--
-- Antes esta função fazia uma busca por 2 nodes de ar livre a partir
-- do static_spawnpoint, subindo até 30 nodes - isso podia colocar o
-- jogador em um Y diferente do spawn real. Agora ela espelha
-- exatamente a lógica de (re)spawn do minetest_game/engine, na mesma
-- ordem de prioridade que eles usam:
--   1) static_spawnpoint (minetest.conf) - se o servidor configurou
--      isso, é para lá que TODO respawn por morte vai.
--   2) spawn.get_default_pos() - API oficial do mod "spawn" do
--      minetest_game: é o ponto calculado pelo algoritmo de busca de
--      bioma que o jogo usa quando não há static_spawnpoint definido
--      (ou seja, na prática, o ponto pra onde a maioria dos jogadores
--      vai ao morrer).
--   3) fallback - só é usado se nem o mod "spawn" estiver presente
--      (ex.: rodando sem minetest_game) nem static_spawnpoint estiver
--      configurado; nesse caso não existe uma forma confiável de
--      descobrir o spawn real via API Lua.
local function teleport_to_world_spawn(player)
    local spawn_pos = core.setting_get_pos("static_spawnpoint")
    if not spawn_pos and spawn and spawn.get_default_pos then
        spawn_pos = spawn.get_default_pos()
    end
    if not spawn_pos then
        core.log("warning", "[deathbox] Não foi possível determinar o spawn oficial do mundo " ..
            "(sem static_spawnpoint e sem mod 'spawn' do minetest_game). Usando fallback (0,30,0).")
        spawn_pos = {x = 0, y = 30, z = 0}
    end
    player:set_pos(spawn_pos)
end
core.register_node("deathbox:victory_portal", {
    description = "Portal da Vitória",
    drawtype = "mesh",
    mesh = "db_blackhole.obj",
    tiles = {"db_blackhole.png"},
    selection_box = {type = "fixed", fixed = {-0.2, -0.2, -0.2, 0.2, 0.2, 0.2}},
    groups = {cracky = 1, unbreakable = 1},
    sunlight_propagates = false,
    paramtype = "light",
    on_punch = function(pos, node, puncher)
        if puncher and puncher:is_player() then teleport_to_world_spawn(puncher) end
    end,
    on_rightclick = function(pos, node, clicker)
        if clicker and clicker:is_player() then teleport_to_world_spawn(clicker) end
    end,
})
core.register_entity("deathbox:portal_disc", {
    initial_properties = {
        visual = "sprite",
        textures = {"db_blackholedisc.png"},
        visual_size = {x = 0.73, y = 0.73},
        physical = false,
        collide_with_objects = false,
        pointable = false,
        static_save = true,
        glow = 14,
    },
    on_step = function(self, dtime)
        local pos = self.object:get_pos()
        if not pos then return end
        local player = nil
        local dist = math.huge
        for _, p in ipairs(core.get_connected_players()) do
            local d = vector.distance(pos, p:get_pos())
            if d < dist then
                dist = d
                player = p
            end
        end
        if player then
            local ppos = player:get_pos()
            local dir = vector.direction(pos, ppos)
            local yaw = math.atan2(dir.z, dir.x) - math.pi / 2
            self.object:set_yaw(yaw)
        end
    end,
})

core.register_entity("deathbox:portal_disc2", {
    initial_properties = {
        visual = "mesh",
        mesh = "db_disc2.obj",
        textures = {"db_blackholedisc2.png"},
        visual_size = {x = 8, y = 8},
        backface_culling = false,
        physical = false,
        collide_with_objects = false,
        pointable = false,
        static_save = true,
        glow = 14,
    },
    on_step = function(self, dtime)
        local pos = self.object:get_pos()
        if not pos then return end
        local player = nil
        local dist = math.huge
        for _, p in ipairs(core.get_connected_players()) do
            local d = vector.distance(pos, p:get_pos())
            if d < dist then
                dist = d
                player = p
            end
        end
        if player then
            local ppos = player:get_pos()
            local dir = vector.direction(pos, ppos)
            local yaw = math.atan2(dir.z, dir.x) - math.pi / 2
            self.object:set_yaw(yaw)
        end
    end,
})


core.register_globalstep(function()
    local portal_nodes = core.find_nodes_in_area(vector.subtract(deathbox.state.spawn_pos, 20), vector.add(deathbox.state.spawn_pos, 20), {"deathbox:victory_portal"})
    for _, pos in ipairs(portal_nodes) do
        for _, player in ipairs(core.get_connected_players()) do
            local ppos = player:get_pos()
            if vector.distance(ppos, pos) <= 1.5 then teleport_to_world_spawn(player) end
        end
    end
end)

-- ===========================================================
-- LAYOUT, GERAÇÃO DE TERRENO E RESET DA ARENA
-- A ideia: o LAYOUT (origem, dimensões, posição de spawn, colunas
-- de barreira) é puramente derivado da config + mapa ascii, então
-- pode ser calculado uma única vez, no carregamento do mod, sem
-- depender de nada estar gerado no mapa ainda.
--
-- A ESTRUTURA FÍSICA (paredes, pilares, piso, e o estado inicial
-- de barris/caixas/barreiras) é colocada via core.register_on_generated,
-- ou seja, nasce junto com a geração do terreno e fica salva no
-- mapa permanentemente — não precisa ser reconstruída em todo
-- /dbstart nem em todo restart do servidor.
--
-- O /dbstart só precisa RESETAR os elementos que mudam durante o
-- jogo (barris explodidos, caixas abertas, barreiras danificadas)
-- de volta ao estado inicial — isso é rápido e não depende de
-- geração de terreno.

function deathbox.compute_layout(map)
    map = map or deathbox.default_map
    local cfg = deathbox.config
    local origin = cfg.base_pos
    local height_map = #map
    local width_map  = #map[1]
    deathbox.state.map_origin = origin
    deathbox.state.map_w      = width_map
    deathbox.state.map_h      = height_map
    deathbox.state.active_map = map
    deathbox.barrier_columns  = {}
    deathbox.state.border_floor_cache = nil -- mapa mudou, recalcula as bordas
    deathbox.state.arena_cell_cache = nil -- idem, para o cache de células do ataque de meteoro
    local first_floor_pos = nil
    for row_i = 1, height_map do
        local row = map[row_i]
        for col_i = 1, width_map do
            local char = row:sub(col_i, col_i)
            local bx = origin.x + (col_i - 1)
            local bz = origin.z + (row_i - 1)
            if char == "o" then
                local base_pos = {x = bx, y = origin.y, z = bz}
                local top_pos  = {x = bx, y = origin.y + cfg.barrier_height - 1, z = bz}
                deathbox.register_barrier_column(base_pos, top_pos)
                first_floor_pos = first_floor_pos or base_pos
            elseif char ~= "x" then
                first_floor_pos = first_floor_pos or {x = bx, y = origin.y, z = bz}
            end
        end
    end
    -- spawn central (calculado a partir do char do mapa, não do
    -- node real — assim funciona mesmo antes da arena existir no mapa)
    local center_col = math.floor(width_map / 2)
    local center_row = math.floor(height_map / 2)
    deathbox.state.spawn_pos = {
        x = origin.x + center_col,
        y = origin.y + 0.5,
        z = origin.z + center_row,
    }
    local center_char = map[center_row + 1] and map[center_row + 1]:sub(center_col + 1, center_col + 1)
    if center_char == "x" and first_floor_pos then
        deathbox.state.spawn_pos = {x = first_floor_pos.x, y = first_floor_pos.y + 0.5, z = first_floor_pos.z}
    end
end

-- Nível Y onde começam as paredes/pilares (e também o piso de base,
-- mais abaixo na subestrutura piso-lava-piso). É o mesmo nível para
-- todo o perímetro, conforme pedido: a parede nasce na mesma altura
-- do piso.
function deathbox.get_wall_base_y()
    local cfg = deathbox.config
    return cfg.base_pos.y - cfg.understructure_depth
end

-- Limite superior até onde a coluna acima da arena deve ser limpa
-- (remove pedras/relevo do mapgen que sobrarem por cima da estrutura).
function deathbox.get_clear_top_y()
    local cfg = deathbox.config
    local wall_top = deathbox.get_wall_base_y() + cfg.wall_height - 1
    return math.max(wall_top, cfg.base_pos.y + cfg.barrier_height - 1) + cfg.clear_height_above
end

-- Bounding box (em coordenadas de node) que envolve toda a arena.
-- Usado para forçar o carregamento/geração via core.emerge_area e
-- também serve de minp/maxp "completo" para uma reconstrução manual.
function deathbox.get_arena_bounds()
    local cfg = deathbox.config
    local origin = cfg.base_pos
    local width  = #deathbox.default_map[1]
    local height = #deathbox.default_map
    local p1 = {x = origin.x, y = deathbox.get_wall_base_y(), z = origin.z}
    local p2 = {
        x = origin.x + width - 1,
        y = deathbox.get_clear_top_y(),
        z = origin.z + height - 1,
    }
    return p1, p2
end

-- Coloca a estrutura física da arena, mas só dentro da interseção
-- com [minp, maxp]. Chamado pelo core.register_on_generated para
-- cada chunk recém-gerado, e também manualmente por /dbrebuild
-- (passando o bounding box inteiro da arena).
function deathbox.place_structure(minp, maxp)
    local cfg = deathbox.config
    local origin = deathbox.state.map_origin
    local map = deathbox.state.active_map
    if not origin or not map then return end

    local map_w, map_h = deathbox.state.map_w, deathbox.state.map_h
    local ax_min, ax_max = origin.x, origin.x + map_w - 1
    local az_min, az_max = origin.z, origin.z + map_h - 1

    -- esse chunk nem toca a área (x,z) da arena
    if maxp.x < ax_min or minp.x > ax_max or maxp.z < az_min or minp.z > az_max then return end

    -- Camadas verticais da arena, de baixo para cima (só existem nas
    -- células internas, isto é, onde não há parede/pilar):
    --   floor1_y -> piso de base
    --   lava_y   -> lava, logo acima do piso de base
    --   floor2_y -> novo piso (o que de fato fica caminhável)
    --   origin.y -> nível onde ficam barris/caixa de arma/barreiras/spawn
    -- As paredes/pilares nascem no mesmo nível do piso de base
    -- (wall_base_y) e sobem cfg.wall_height nodes a partir daí,
    -- envolvendo as 3 camadas e ainda deixando espaço livre acima.
    local wall_base_y = deathbox.get_wall_base_y()
    local floor1_y = wall_base_y
    local lava_y   = wall_base_y + 1
    local floor2_y = wall_base_y + 2

    local clear_bottom = wall_base_y
    local clear_top = deathbox.get_clear_top_y()
    -- esse chunk nem toca a faixa de altura da arena
    if maxp.y < clear_bottom or minp.y > clear_top then return end
    local y_lo = math.max(clear_bottom, minp.y)
    local y_hi = math.min(clear_top, maxp.y)
    for row_i = 1, map_h do
        local bz = origin.z + (row_i - 1)
        if bz >= minp.z and bz <= maxp.z then
            local row = map[row_i]
            for col_i = 1, map_w do
                local bx = origin.x + (col_i - 1)
                if bx >= minp.x and bx <= maxp.x then
                    local char = row:sub(col_i, col_i)
                    -- limpa a coluna vertical (remove terreno natural do mapgen)
                    for y = y_lo, y_hi do core.set_node({x = bx, y = y, z = bz}, {name = "air"}) end

                    if char == "x" or char == "q" then
                        -- Parede/pilar: coluna sólida do piso de base até
                        -- o topo da parede. Sem piso embaixo: aqui é só
                        -- parede, do início ao fim.
                        local node_name = (char == "x") and "deathbox:wall" or "deathbox:pillar"
                        for y = 0, cfg.wall_height - 1 do
                            local ny = wall_base_y + y
                            if ny >= minp.y and ny <= maxp.y then
                                core.set_node({x = bx, y = ny, z = bz}, {name = node_name})
                            end
                        end
                    else
                        -- Célula interna (entre as paredes): piso de
                        -- base, lava por cima, e um novo piso por cima
                        -- da lava — é sobre esse novo piso que ficam os
                        -- demais nodes (barril, caixa, barreira, spawn).
                        if floor1_y >= minp.y and floor1_y <= maxp.y then
                            core.set_node({x = bx, y = floor1_y, z = bz}, {name = "deathbox:floor"})
                        end
                        if lava_y >= minp.y and lava_y <= maxp.y then
                            core.set_node({x = bx, y = lava_y, z = bz}, {name = "default:lava_source"})
                        end
                        if floor2_y >= minp.y and floor2_y <= maxp.y then
                            core.set_node({x = bx, y = floor2_y, z = bz}, {name = "deathbox:floor"})
                        end

                        if char == "b" then
                            if origin.y >= minp.y and origin.y <= maxp.y then
                                core.set_node({x = bx, y = origin.y, z = bz}, {name = "deathbox:barrel"})
                            end
                        elseif char == "w" then
                            if origin.y >= minp.y and origin.y <= maxp.y then
                                core.set_node({x = bx, y = origin.y, z = bz}, {name = "deathbox:weapon_box"})
                            end
                        elseif char == "o" then
                            for y = 0, cfg.barrier_height - 1 do
                                local ny = origin.y + y
                                if ny >= minp.y and ny <= maxp.y then
                                    core.set_node({x = bx, y = ny, z = bz}, {name = "deathbox:barrier_0"})
                                end
                            end
                            if origin.y >= minp.y and origin.y <= maxp.y then
                                core.get_meta({x = bx, y = origin.y, z = bz}):set_int("hits", 0)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Reseta só os elementos "destrutíveis/coletáveis" da arena de
-- volta ao estado inicial (barris, caixas de arma, barreiras).
-- Não toca em paredes/pilares/piso — esses são permanentes (vieram
-- da geração do terreno) e não precisam ser refeitos.
function deathbox.reset_arena()
    local cfg = deathbox.config
    local origin = deathbox.state.map_origin
    local map = deathbox.state.active_map
    if not origin or not map then return end
    deathbox.barrier_columns = {}
    for row_i = 1, deathbox.state.map_h do
        local row = map[row_i]
        local bz = origin.z + (row_i - 1)
        for col_i = 1, deathbox.state.map_w do
            local char = row:sub(col_i, col_i)
            local bx = origin.x + (col_i - 1)
            if char == "b" then core.set_node({x = bx, y = origin.y, z = bz}, {name = "deathbox:barrel"})
            elseif char == "w" then core.set_node({x = bx, y = origin.y, z = bz}, {name = "deathbox:weapon_box"})
            elseif char == "o" then
                local base_pos = {x = bx, y = origin.y, z = bz}
                local top_pos  = {x = bx, y = origin.y + cfg.barrier_height - 1, z = bz}
                for y = 0, cfg.barrier_height - 1 do
                    core.set_node({x = bx, y = origin.y + y, z = bz}, {name = "deathbox:barrier_0"})
                end
                core.get_meta(base_pos):set_int("hits", 0)
                deathbox.register_barrier_column(base_pos, top_pos)
            end
        end
    end
end


-- POSIÇÕES DE SPAWN DE ZUMBIS (pisos livres dentro do mapa)
function deathbox.get_border_floor_positions()
    if deathbox.state.border_floor_cache then return deathbox.state.border_floor_cache end
    local origin = deathbox.state.map_origin
    local map    = deathbox.state.active_map or deathbox.default_map
    local positions = {}
    local offsets = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
    for row_i = 1, #map do
        local row = map[row_i]
        for col_i = 1, #row do
            if row:sub(col_i, col_i) == "." then
                for _, off in ipairs(offsets) do
                    local nrow = map[row_i + off[2]]
                    if nrow and nrow:sub(col_i + off[1], col_i + off[1]) == "x" then
                        table.insert(positions, {
                            x = origin.x + (col_i - 1),
                            y = origin.y + 0.5,
                            z = origin.z + (row_i - 1),
                        })
                        break
                    end
                end
            end
        end
    end
    deathbox.state.border_floor_cache = positions
    return positions
end

function deathbox.get_random_floor_pos()
    local positions = deathbox.get_border_floor_positions()
    if #positions > 0 then
        return positions[math.random(1, #positions)]
    end
    -- Fallback (não deveria ocorrer com o mapa padrão, só existe
    -- por segurança caso algum mapa customizado não tenha nenhuma
    -- célula de borda válida): qualquer piso livre da arena.
    local origin = deathbox.state.map_origin
    local map    = deathbox.state.active_map or deathbox.default_map
    for _ = 1, 30 do
        local row_i = math.random(1, #map)
        local row   = map[row_i]
        local col_i = math.random(1, #row)
        if row:sub(col_i, col_i) == "." then
            return {
                x = origin.x + (col_i - 1),
                y = origin.y + 0.5,
                z = origin.z + (row_i - 1),
            }
        end
    end
    return deathbox.state.spawn_pos
end

-- Todas as células de piso livre ("." no mapa) da arena, incluindo as
-- centrais (diferente de get_border_floor_positions, que só pega as
-- encostadas em parede). Usado para o ataque de meteoro do demonking,
-- que precisa cair em "lugares aleatórios da arena" e não só nas bordas.
function deathbox.get_arena_cell_positions()
    if deathbox.state.arena_cell_cache then return deathbox.state.arena_cell_cache end
    local origin = deathbox.state.map_origin
    local map    = deathbox.state.active_map or deathbox.default_map
    local positions = {}
    for row_i = 1, #map do
        local row = map[row_i]
        for col_i = 1, #row do
            if row:sub(col_i, col_i) == "." then
                table.insert(positions, {
                    x = origin.x + (col_i - 1),
                    z = origin.z + (row_i - 1),
                })
            end
        end
    end
    deathbox.state.arena_cell_cache = positions
    return positions
end

function deathbox.get_random_arena_cell_pos()
    local positions = deathbox.get_arena_cell_positions()
    if #positions == 0 then return nil end
    return positions[math.random(1, #positions)]
end

-- Dispara os 3 meteoros (flame_ball2 comuns) que caem verticalmente
-- sobre pontos aleatórios da arena, chamado quando a flame_ball2_giant
-- do demonking "estoura" no ar. spawn_source_pos é só informativo (não
-- é usado como origem, já que cada meteoro nasce lá em cima, acima da
-- própria arena, e cai reto para baixo).
function deathbox.spawn_demonking_meteor_rain(spawn_source_pos)
    local cfg = deathbox.config
    local top_y = deathbox.get_clear_top_y()
    for _ = 1, 3 do
        local cell = deathbox.get_random_arena_cell_pos()
        if cell then
            local spawn_pos = {x = cell.x, y = top_y, z = cell.z}
            local proj = core.add_entity(spawn_pos, "deathbox:flame_ball2_meteor")
            if proj then
                proj:set_velocity({x = 0, y = -cfg.demonking_meteor_fall_speed, z = 0})
                local ent = proj:get_luaentity()
                if ent then ent._owner = nil end
            end
        end
    end
end

-- SISTEMA DE ONDAS
function deathbox.spawn_wave()
    local cfg = deathbox.config
    deathbox.state.wave = deathbox.state.wave + 1
    local wave = deathbox.state.wave
    local zombie_count = cfg.zombies_initial + (wave - 1) * cfg.zombies_increase
    local goblin_count = math.floor(wave/2)
    local imp_count = math.floor(wave/4)
    local demon_count  = math.floor(wave/5)
    local demonking_count  = math.floor(wave/11)
    local total = zombie_count + goblin_count + imp_count + demon_count + demonking_count
    deathbox.state.alive_zombies = total
    local msg = "[deathbox] Onda " .. wave .. " — " .. zombie_count .. " zumbis"
    if goblin_count > 0 then msg = msg .. ", " .. goblin_count .. " goblin(s)" .. (goblin_count > 1 and "s" or "") end
    if imp_count > 0 then msg = msg .. ", " .. imp_count .. " diabrete(s)" .. (imp_count > 1 and "s" or "") end
    if demon_count > 0 then msg = msg .. " e " .. demon_count .. " demônio(s)" .. (demon_count > 1 and "s" or "") end
    if demonking_count > 0 then msg = msg .. " e " .. demonking_count .. " rei demônio" .. (demonking_count > 1 and "s" or "") end
    msg = msg .. "!"
    core.chat_send_all(core.colorize("#ff5555", msg))
    deathbox.update_all_hud()
    for _ = 1, zombie_count do core.add_entity(deathbox.get_random_floor_pos(), "deathbox:zombie") end
    for _ = 1, goblin_count do core.add_entity(deathbox.get_random_floor_pos(), "deathbox:goblin") end
    for _ = 1, imp_count do core.add_entity(deathbox.get_random_floor_pos(), "deathbox:imp") end
    for _ = 1, demon_count do core.add_entity(deathbox.get_random_floor_pos(), "deathbox:demon") end
    for _ = 1, demonking_count do core.add_entity(deathbox.get_random_floor_pos(), "deathbox:demonking") end
end

function deathbox.check_wave_complete()
    deathbox.update_all_hud()
    if deathbox.state.running and deathbox.state.alive_zombies <= 0 then
        -- Final da partida após concluir a onda 11
        if deathbox.state.wave >= 11 then
            deathbox.state.running = false
            local portal_pos = {
                x = deathbox.state.spawn_pos.x,
                y = deathbox.state.spawn_pos.y + 1,
                z = deathbox.state.spawn_pos.z,
            }
            core.set_node(portal_pos, {name = "deathbox:victory_portal"})
            core.add_entity(vector.add(portal_pos, {x = 0, y = 0.5, z = 0}), "deathbox:portal_disc")
            core.add_entity(vector.add(portal_pos, {x = 0, y = 0.5, z = 0}), "deathbox:portal_disc2")
            core.chat_send_all(core.colorize("#55ff55", "[deathbox] Parabéns! A onda 11 foi concluída!"))
            return
        end
        core.chat_send_all(core.colorize("#55ff55", "[deathbox] Onda " .. deathbox.state.wave .. " concluída! Próxima em " .. deathbox.config.round_wait_time .. "s..."))
        core.after(deathbox.config.round_wait_time, function() if deathbox.state.running then deathbox.spawn_wave() end end)
    end
end

-- HUD
function deathbox.setup_hud(player)
    local name = player:get_player_name()
    if hud_ids[name] then return end
    hud_ids[name] = {}
    hud_ids[name].wave = player:hud_add({
        type = "text",
        position = {x = 0.5, y = 0.05},
        offset = {x = 0, y = 0},
        alignment = {x = 0, y = 0},
        scale = {x = 100, y = 30},
        text = "deathbox: aguardando início (/dbstart)",
        number = 0xFFFFFF,
    })
    hud_ids[name].zombies = player:hud_add({
        type = "text",
        position = {x = 0.5, y = 0.07},
        offset = {x = 0, y = 0},
        alignment = {x = 0, y = 0},
        scale = {x = 100, y = 30},
        text = "",
        number = 0xFFAAAA,
    })
    -- Fundo preto semitransparente atrás da caixa de informações.
    -- "[fill:WxH:#RRGGBBAA" gera uma textura sólida na hora, sem
    -- precisar de nenhum arquivo de imagem externo. Precisa ser
    -- adicionado ANTES do texto de info para renderizar por trás dele
    -- (o Luanti desenha os elementos de HUD na ordem de criação).
    hud_ids[name].info_bg = player:hud_add({
        type = "image",
        position = {x = 0.02, y = 0.95},
        offset = {x = -12, y = -90},
        alignment = {x = 1, y = 1.25},
        scale = {x = 1, y = 1},
        text = "",
    })
    -- Caixa de informações pessoal: vida, arma e usos restantes.
    -- Posicionada no canto inferior esquerdo, perto da área de mira/HUD do jogador.
    hud_ids[name].info = player:hud_add({
        type = "text",
        position = {x = 0.02, y = 0.95},
        offset = {x = 0, y = 0},
        alignment = {x = 1, y = -1},
        scale = {x = 100, y = 30},
        text = "",
        number = 0xFFFFFF,
    })
end
function deathbox.update_all_hud()
    for _, player in ipairs(core.get_connected_players()) do
        local name = player:get_player_name()
        if hud_ids[name] then
            if deathbox.state.running then
                player:hud_change(hud_ids[name].wave, "text", "DEATHBOX - Onda: " .. deathbox.state.wave)
                player:hud_change(hud_ids[name].zombies, "text", "Monstros restantes: " .. deathbox.state.alive_zombies)
            else
                player:hud_change(hud_ids[name].wave, "text", "[deathbox]\nAguardando Início\nEscreva: /dbstart")
                player:hud_change(hud_ids[name].zombies, "text", "")
            end
        end
    end
end
function deathbox.update_info_hud(player)
    local name = player:get_player_name()
    if not hud_ids[name] or not hud_ids[name].info then return end
    if not deathbox.state.running then
        player:hud_change(hud_ids[name].info, "text", "")
        if hud_ids[name].info_bg then
            player:hud_change(hud_ids[name].info_bg, "text", "")
        end
        return
    end
    local hp = player:get_hp()
    local wielded = player:get_wielded_item()
    local weapon_label, usos_label = deathbox.get_weapon_info(wielded)
    player:hud_change(hud_ids[name].info, "text",
        "Sangue: " .. hp .. "\nArma: " .. weapon_label .. "\nUsos: " .. usos_label)
    if hud_ids[name].info_bg then
        player:hud_change(hud_ids[name].info_bg, "text", "[fill:240x110:#00000099")
    end
end
deathbox.info_hud_timer = 0
core.register_globalstep(function(dtime)
    deathbox.info_hud_timer = deathbox.info_hud_timer + dtime
    if deathbox.info_hud_timer < 0.25 then return end
    deathbox.info_hud_timer = 0
    for _, player in ipairs(core.get_connected_players()) do
        deathbox.update_info_hud(player)
    end
end)

-- ===========================================================
-- GERAÇÃO DE TERRENO
-- ===========================================================
-- A arena nasce junto com o mapgen. Isso evita qualquer corrida
-- entre "jogador entrou" e "arena ainda não existe/carregada",
-- que era a causa da queda livre: antes, todo jogador era
-- teleportado para a arena 2s após entrar, mesmo que aquele bloco
-- do mapa ainda não estivesse de fato carregado/colidível — daí a
-- queda pelo vazio até o terreno real do mapgen, bem mais abaixo.
core.register_on_generated(function(minp, maxp, blockseed)
    deathbox.place_structure(minp, maxp)
end)

-- Calcula o layout imediatamente ao carregar o mod (não depende de
-- nada estar gerado ainda).
deathbox.compute_layout()

-- Pré-aquece (carrega/gera) a área da arena assim que o servidor sobe,
-- como uma otimização de "primeiro acesso" — mas isso é só best-effort.
-- IMPORTANTE: o /dbstart NÃO depende deste callback terminar. O callback
-- de core.emerge_area é assíncrono e, na prática, nem sempre dispara de
-- forma confiável para blocos que já existiam no banco de dados do mapa
-- (sobras da versão anterior do mod, que construía a arena via Lua em
-- runtime). Por isso o /dbstart garante a estrutura sozinho, de forma
-- síncrona, em vez de esperar por esse flag.
core.register_on_mods_loaded(function()
    local p1, p2 = deathbox.get_arena_bounds()
    core.emerge_area(p1, p2, function(blockpos, action, calls_remaining, param)
        if calls_remaining <= 0 then
            deathbox.state.arena_ready = true
            core.log("action", "[deathbox] pré-carregamento da área da arena concluído")
        end
    end)
end)

-- Aplica a configuração de câmera usada durante uma partida deathbox
-- (terceira pessoa + eye_height/eye_offset elevados, pra dar a visão
-- "de cima" característica do jogo). Centralizado aqui pra ser
-- reaplicado tanto no /dbstart quanto quando um jogador reconecta
-- no meio de uma partida em andamento — assim a visão nunca volta
-- ao padrão do engine enquanto a partida durar.
function deathbox.apply_match_camera(player)
    if not player or not player:is_player() then return end
    player:set_properties({eye_height = 10})
    player:set_eye_offset({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = -30})
    if player.set_camera then player:set_camera({mode = "third"}) end
end

-- Limita a rotação vertical da câmera durante a partida: o jogador só
-- pode olhar entre 45° para baixo (pitch = pi/4, a metade do caminho
-- até olhar reto para frente) e reto para baixo (pitch = pi/2). Ou
-- seja, a visão nunca volta ao horizonte/frente — fica sempre
-- inclinada para baixo, dentro dessa faixa de 45°.
--
-- A correção é sempre "depois do fato" (a câmera é controlada pelo
-- cliente; o servidor só consegue reagir e corrigir de volta com um
-- tick de atraso). Corrigir exatamente em cima do limite a cada tick
-- faz o servidor "lutar" contra o mouse do jogador o tempo todo bem
-- na linha do limite, o que aparece visualmente como tremor. Por
-- isso só corrigimos quando o jogador já passou uma pequena margem
-- de tolerância (TOLERANCE) do limite — pequena o bastante pra ser
-- imperceptível, mas suficiente pra parar de corrigir a cada tick e
-- eliminar o tremor.
local PITCH_MIN = math.pi / 4 -- 45° para baixo: olhar mais "frente" que isso não é permitido
local PITCH_MAX = math.pi / 2 -- 90° para baixo: reto para baixo
core.register_globalstep(function(dtime)
    if not deathbox.state.running then return end
    for _, player in ipairs(core.get_connected_players()) do
        local pitch = player:get_look_vertical()
        if pitch <= PITCH_MIN then
            player:set_look_vertical(PITCH_MIN)
        end
    end
end)
-- GAME OVER / LIMPEZA DE MOBS
local function remove_all_deathbox_entities()
    for _, obj in ipairs(core.get_objects_inside_radius(deathbox.state.spawn_pos or {x=0,y=0,z=0}, 500)) do
        local ent = obj:get_luaentity()
        if ent and (
            ent.name == "deathbox:zombie" or ent.name == "deathbox:goblin" or ent.name == "deathbox:imp" or ent.name == "deathbox:demon" or ent.name == "deathbox:demonking"
            or ent.name == "deathbox:bullet_shot" or ent.name == "deathbox:flame_ball" or ent.name == "deathbox:flame_ball2"
            or ent.name == "deathbox:flame_ball2_giant" or ent.name == "deathbox:flame_ball2_meteor")
            then obj:remove()
        end
    end
    deathbox.state.alive_zombies = 0
end
-- JOIN / RESPAWN
-- Fora de partida, o jogador entra e morre normalmente no terreno
-- do Minetest Game — nada aqui o move. Só durante uma partida em
-- andamento ele é colocado/levado de volta para a arena.
core.register_on_joinplayer(function(player)
    deathbox.setup_hud(player)
    if deathbox.state.running and deathbox.state.spawn_pos then
        core.after(2, function()
            if not (deathbox.state.running and player and player:is_player()) then return end
            player:set_pos(deathbox.state.spawn_pos)
            local inv = player:get_inventory()
            if inv and not inv:contains_item("main", "deathbox:spear") then inv:add_item("main", "deathbox:spear")
            end
            -- Mantém a mesma "visão" da partida (terceira pessoa,
            -- eye_height/eye_offset elevados) mesmo que o jogador
            -- esteja reconectando, e não entrando do zero.
            deathbox.apply_match_camera(player)
        end)
    end
    deathbox.update_all_hud()
end)

core.register_on_respawnplayer(function(player)
    if deathbox.state.running and deathbox.state.spawn_pos then
        core.after(0, function() if player and player:is_player() then player:set_pos(deathbox.state.spawn_pos) end end)
        return true
    end
    -- fora de partida, deixa o respawn padrão do jogo cuidar disso
    return false
end)


-- COMANDOS
core.register_chatcommand("dbstart", {
    description = "Reseta a arena deathbox ao estado inicial e inicia a partida (suporta 2+ jogadores)",
    func = function(name)
        if deathbox.state.running then return false, "O deathbox já está em andamento. Use /dbstop para reiniciar."end
        -- Remove discos de portal (da vitória de uma partida anterior),
        -- a animação de queda de caixa de arma e quaisquer itens largados
        -- no chão (ex.: armas que caíram da caixa por inventário cheio)
        -- que ainda estejam na arena, antes de resetar a estrutura.
        for _, obj in ipairs(core.get_objects_inside_radius(deathbox.state.spawn_pos or {x = 0, y = 0, z = 0}, 500)) do
            local ent = obj:get_luaentity()
            if ent then
                if ent.name == "deathbox:portal_disc" or ent.name == "deathbox:portal_disc2" or ent.name == "deathbox:weapon_box_drop" then
                    obj:remove()
                elseif ent.name == "__builtin:item" and ent.itemstring and ent.itemstring:find("^deathbox:") then
                    -- item largado no chão (ex.: arma que caiu da caixa
                    -- porque o inventário do jogador estava cheio)
                    obj:remove()
                end
            end
        end
        local p1, p2 = deathbox.get_arena_bounds()
        deathbox.place_structure(p1, p2)
        deathbox.state.running = true
        deathbox.state.wave = 0
        for _, player in ipairs(core.get_connected_players()) do
            local inv = player:get_inventory()
            if inv then
                for list_name, _ in pairs(inv:get_lists()) do inv:set_list(list_name, {}) end
                inv:add_item("main", "deathbox:spear")
            end
            player:set_hp(player:get_properties().hp_max or 20)
            player:set_pos(deathbox.state.spawn_pos)
            deathbox.apply_match_camera(player)
            core.chat_send_player(player:get_player_name(), "Você foi colocado em visão de terceira pessoa para a partida.")
        end
        core.after(1, function() if deathbox.state.running then deathbox.spawn_wave() end end) -- atraso para gerar monstros
        return true, "Arena resetada! Sobreviva às ondas de zumbis. Clique direito para atirar."
    end,
})

core.register_chatcommand("killwave", {
    description = "Mata todos os inimigos vivos da onda atual",
    privs = {server = true},
    func = function(name)
        local mortos = 0
        for _, obj in ipairs(core.get_objects_inside_radius(deathbox.state.spawn_pos or {x=0,y=0,z=0}, 1000)) do
            local ent = obj:get_luaentity()
            if ent and (
                ent.name == "deathbox:zombie" or
                ent.name == "deathbox:goblin" or
                ent.name == "deathbox:imp" or
                ent.name == "deathbox:demon" or
                ent.name == "deathbox:demonking"
            ) then
                deathbox.mob_start_death(ent)
                mortos = mortos + 1
            end
        end
        return true, "Mortos " .. mortos .. " inimigos."
    end,
})

core.register_chatcommand("dbstop", {
    description = "Para a partida do deathbox e remove os monstros vivos",
    func = function(name)
        if not deathbox.state.running then return false, "O deathbox não está em andamento." end
        deathbox.state.running = false
        if deathbox.state.map_origin then
            for _, obj in ipairs(core.get_objects_inside_radius(deathbox.state.spawn_pos, 64)) do
                local ent = obj:get_luaentity()
                if ent and (ent.name == "deathbox:zombie" or ent.name == "deathbox:goblin" or ent.name == "deathbox:imp" or ent.name == "deathbox:demon" or ent.name == "deathbox:demonking"
                or ent.name == "deathbox:bullet_shot" or ent.name == "deathbox:flame_ball" or ent.name == "deathbox:flame_ball2"
                or ent.name == "deathbox:flame_ball2_giant" or ent.name == "deathbox:flame_ball2_meteor") then
                    obj:remove()
                end
            end
        end
        for _, player in ipairs(core.get_connected_players()) do
            if player.set_camera then player:set_camera({mode = "any"}) end
            deathbox.stop_all_loop_sounds(player:get_player_name())
        end
        deathbox.update_all_hud()
        return true, "deathbox finalizado."
    end,
})

core.register_chatcommand("dbrebuild", {
    description = "Força a (re)construção da estrutura física da arena deathbox nas coordenadas atuais. " ..
                   "Use uma vez após instalar/atualizar o mod em um mundo já existente " ..
                   "(onde aquele trecho do mapa já tinha sido gerado antes da arena existir).",
    privs = {server = true},
    func = function(name)
        local p1, p2 = deathbox.get_arena_bounds()
        deathbox.place_structure(p1, p2)
        return true, "Estrutura física da arena deathbox (re)construída."
    end,
})

core.register_chatcommand("deathbox_weapon", {
    description = "Recebe a pistola deathbox no inventário",
    func = function(name)
        local player = core.get_player_by_name(name)
        if player then player:get_inventory():add_item("main", "deathbox:pistol") return true, "Pistola adicionada." end
        return false, "Jogador não encontrado."
    end,
})

local function show_game_over(player)
    core.show_formspec(
        player:get_player_name(),
        "deathbox:gameover",
        "formspec_version[4]" ..
        "size[8,4]" ..
        "label[3,0.7;VOCÊ MORREU]" ..
        "label[1,1.5;Onda alcançada: " .. deathbox.state.last_wave .. "]" ..
        "label[1,2.0;Monstros restantes: " .. deathbox.state.last_remaining .. "]" ..
        "button[0.5,2.7;2,1;back;Voltar]" ..
        "button[3,2.7;2,1;stay;Ficar]" ..
        "button[5.5,2.7;2,1;restart;Reiniciar]"
    )
end

core.register_on_player_hpchange(function(player, hp_change, reason)
    if not deathbox.state.running then return hp_change end
    if hp_change < 0 then
        deathbox.spawn_bloodpool(player:get_pos())
        local attacker = reason and reason.object
        if attacker and attacker:get_pos() then deathbox.apply_knockback(player, attacker:get_pos(), 5)
        end
    end
    if player:get_hp() + hp_change > 0 then return hp_change end
    deathbox.state.running = false
    for _, p in ipairs(core.get_connected_players()) do
        deathbox.stop_all_loop_sounds(p:get_player_name())
    end
    core.after(0, function()
        if not player or not player:is_player() then return end
        deathbox.state.last_wave = deathbox.state.wave
        deathbox.state.last_remaining = deathbox.state.alive_zombies
        player:set_hp(20)
        remove_all_deathbox_entities()
        deathbox.update_all_hud() -- atualiza o HUD de todos pra "aguardando início"
        show_game_over(player)
    end)
    return 0
end, true)

core.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "deathbox:gameover" then return end
    local name = player:get_player_name()
    if fields.stay then core.close_formspec(name, "deathbox:gameover")
    elseif fields.back then
        core.close_formspec(name, "deathbox:gameover")
        -- Remove todos os itens do inventário (pistola, lança-chamas, etc.)
        local inv = player:get_inventory()
        if inv then for list_name, _ in pairs(inv:get_lists()) do inv:set_list(list_name, {}) end end
        if player.set_camera then player:set_camera({mode = "any"}) end
        player:set_properties({eye_height = 1.625})
        player:set_eye_offset({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
        player:set_hp(0) -- força respawn padrão do Minetest
        core.after(0.1, function() if player and player:is_player() then player:respawn() end end)
    elseif fields.restart then
        core.close_formspec(name, "deathbox:gameover")
        -- Limpa o inventário (pistola, lança-chamas, etc. de uma run
        -- anterior) e devolve a espada, igual o /dbstart faz.
        local inv = player:get_inventory()
        if inv then
            for list_name, _ in pairs(inv:get_lists()) do inv:set_list(list_name, {}) end
            inv:add_item("main", "deathbox:spear")
        end
        player:set_hp(player:get_properties().hp_max or 20)
        if deathbox.state.spawn_pos then player:set_pos(deathbox.state.spawn_pos) end
        deathbox.apply_match_camera(player)
        deathbox.reset_arena()
        deathbox.state.running = true
        deathbox.state.wave = 0
        deathbox.spawn_wave()
    end
end)

-- Remove todos os mobs quando o último jogador sair
core.register_on_leaveplayer(function(player)
    if deathbox.state.running then
        remove_all_deathbox_entities()
        deathbox.state.running = false
        deathbox.state.wave = 0
        deathbox.update_all_hud() -- atualiza o HUD de quem ficou, pra "aguardando início"
    end
end)

core.log("action", "[deathbox] mod carregado")
