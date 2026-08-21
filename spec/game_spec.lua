package.path = "./?.lua;" .. package.path

local Game = require("game")

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local game = Game:new()
local ok = game:fromSaveData({
    stock = {},
    waste = {},
    foundations = {},
    tableau = {},
})

assert_equal(ok, false, "malformed save data is rejected")

local check_ok = pcall(function()
    game:checkWin()
end)

assert_equal(check_ok, true, "rejected save data leaves game state usable")

print("game_spec: ok")
