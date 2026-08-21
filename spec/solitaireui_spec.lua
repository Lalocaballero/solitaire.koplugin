package.path = "./?.lua;" .. package.path

local function class()
    local cls = {}
    cls.__index = cls

    function cls:extend(defaults)
        defaults = defaults or {}
        setmetatable(defaults, self)
        defaults.__index = defaults
        defaults.extend = self.extend
        defaults.new = self.new
        return defaults
    end

    function cls:new(o)
        o = o or {}
        setmetatable(o, self)
        if o.init then
            o:init()
        end
        return o
    end

    return cls
end

local function widget(name)
    local cls = class()
    cls.name = name
    return cls
end

package.preload["ffi/blitbuffer"] = function()
    return {
        COLOR_BLACK = 0,
        COLOR_DARK_GRAY = 1,
        COLOR_GRAY = 2,
        COLOR_LIGHT_GRAY = 3,
        COLOR_WHITE = 4,
    }
end

package.preload["ui/widget/buttontable"] = function()
    local ButtonTable = widget("ButtonTable")
    function ButtonTable:getSize()
        return { h = 40 }
    end
    return ButtonTable
end

package.preload["ui/widget/container/centercontainer"] = function() return widget("CenterContainer") end
package.preload["ui/widget/container/framecontainer"] = function() return widget("FrameContainer") end
package.preload["ui/widget/container/inputcontainer"] = function() return widget("InputContainer") end
package.preload["ui/widget/container/widgetcontainer"] = function() return widget("WidgetContainer") end
package.preload["ui/widget/verticalgroup"] = function() return widget("VerticalGroup") end

package.preload["device"] = function()
    return {
        screen = {
            getSize = function() return { w = 600, h = 800 } end,
            getDPI = function() return 167 end,
        },
        isTouchDevice = function() return true end,
        hasKeys = function() return false end,
    }
end

package.preload["ui/font"] = function()
    return { getFace = function() return {} end }
end

package.preload["ui/geometry"] = function()
    return { new = function(_, o) return o end }
end

package.preload["ui/gesturerange"] = function()
    local GestureRange = widget("GestureRange")
    return GestureRange
end

package.preload["ui/widget/infomessage"] = function() return widget("InfoMessage") end
package.preload["ui/size"] = function() return {} end

package.preload["ui/widget/textwidget"] = function()
    local TextWidget = widget("TextWidget")
    function TextWidget:getSize()
        return { w = 10, h = 10 }
    end
    function TextWidget:paintTo() end
    function TextWidget:free() end
    return TextWidget
end

package.preload["ui/uimanager"] = function()
    return {
        close = function() end,
        scheduleIn = function() end,
        setDirty = function() end,
        show = function() end,
    }
end

package.preload["datastorage"] = function()
    return { getSettingsDir = function() return "/tmp" end }
end

package.preload["luasettings"] = function()
    return {
        open = function()
            return {
                flush = function() end,
                readSetting = function() return nil end,
                saveSetting = function() end,
            }
        end,
    }
end

package.preload["gettext"] = function()
    return function(text) return text end
end

local SolitaireUI = require("solitaireui")
local Game = require("game")

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local ui = setmetatable({
    game = Game:new(),
    game_started = false,
    hint_highlight = nil,
    selected_source = nil,
}, { __index = SolitaireUI })

ui.game.foundations[1] = {
    { suit = 1, rank = 1, face_up = true },
}
ui.findTouchZone = function()
    return { type = "foundation", index = 1 }
end
ui.refreshUI = function() end

ui:onTap(nil, { pos = { x = 1, y = 1 } })

assert_equal(ui.selected_source and ui.selected_source.type, "foundation", "foundation tap selects source type")
assert_equal(ui.selected_source and ui.selected_source.index, 1, "foundation tap selects source index")

local won_game = Game:new()
for foundation_idx = 1, 4 do
    for rank = 1, 13 do
        table.insert(won_game.foundations[foundation_idx], {
            suit = foundation_idx,
            rank = rank,
            face_up = true,
        })
    end
end

local saved_won_game = false
local deleted_won_game_save = false
local closing_ui = setmetatable({
    game = won_game,
    saveGame = function()
        saved_won_game = true
    end,
    deleteSave = function()
        deleted_won_game_save = true
    end,
}, { __index = SolitaireUI })

closing_ui:onClose()

assert_equal(saved_won_game, false, "closing a won game does not save completed state")
assert_equal(deleted_won_game_save, true, "closing a won game clears saved state")

print("solitaireui_spec: ok")
