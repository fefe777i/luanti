local WORLD_NAME = "stone_world"
local SPAWN = {x = 0, y = 20, z = 0}

local function enter_world(name)
    if not core.create_subworld(WORLD_NAME) then
        core.chat_send_player(name, "Не вдалося створити Stone World.")
        return
    end

    if not core.transfer_player(name, WORLD_NAME, SPAWN) then
        core.chat_send_player(name, "Не вдалося перейти у Stone World.")
        return
    end

    core.chat_send_player(name, "Ти у Stone World!")
end

core.register_chatcommand("stoneworld", {
    description = "Перейти у Stone World",
    privs = {},
    func = function(name)
        enter_world(name)
    end,
})

core.register_chatcommand("overworld", {
    description = "Повернутися у головний світ",
    privs = {},
    func = function(name)
        if not core.transfer_player(name, "overworld", SPAWN) then
            core.chat_send_player(name, "Не вдалося повернутися у головний світ.")
            return
        end

        core.chat_send_player(name, "Ти повернувся у головний світ!")
    end,
})
