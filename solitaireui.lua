local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local Screen = Device.screen
local _ = require("gettext")

local Game = require("game")
local Stats = require("stats")

local SolitaireUI = InputContainer:extend{
    name = "solitaire_ui",
    modal = true,
    covers_fullscreen = true,
}


function SolitaireUI:init()
    self.dimen = Screen:getSize()
    self.dpi = Screen:getDPI()
    
    self.screen_width = self.dimen.w
    self.screen_height = self.dimen.h

    -- Helper function to convert pixel values to points based on screen DPI
    -- This allows us to maintain consistent physical sizes across different screen densities
    local function px_to_pt(px)
        return math.floor(px * 72 / self.dpi)
    end

    -- UI element heights
    self.status_bar_height = self.screen_height * 0.03
    self.button_bar_height = 50

    -- Card dimensions
    self.card_width = math.floor(self.screen_width / 9)
    self.card_height = math.floor(self.card_width * 1.4)
    self.card_spacing = math.floor(self.card_width * 0.15)
    self.stack_offset = math.floor(self.card_height * 0.35)

    -- Draw-3 fan offset for waste pile
    self.waste_fan_offset = math.floor(self.card_width * 0.3)

    -- Layout positions
    self.margin = math.floor(self.screen_width * 0.02)

    -- Desired pixel heights as fractions of card_width
    local corner_px      = math.floor(self.card_width/2)  -- rank + corner suit
    local center_suit_px = math.floor(self.card_width)    -- large centre suit
    local status_pt      = math.floor(self.status_bar_height * 1.45)


    -- Monospace font for rank and suit symbols to ensure proper alignment
    self.rank_font        = Font:getFace("scfont", px_to_pt(corner_px))
    self.suit_font        = Font:getFace("scfont", px_to_pt(corner_px))
    self.suit_center_font = Font:getFace("scfont", px_to_pt(center_suit_px))
    self.small_font       = Font:getFace("scfont", px_to_pt(center_suit_px)) -- Empty Aces slots
    self.status_font      = Font:getFace("scfont", px_to_pt(status_pt)) -- Status bar font size based on its height
    -- Save file path
    self.save_path = DataStorage:getSettingsDir() .. "/solitaire_save.lua"

    -- Settings path (for draw mode preference)
    self.settings_path = DataStorage:getSettingsDir() .. "/solitaire_settings.lua"

    -- Load settings
    self:loadSettings()

    -- Game state
    self.game = Game:new()
    self.game:setDrawMode(self.draw_mode_pref)

    -- Stats
    self.stats = Stats:new()

    -- Track if current game has had moves (to know if it's an "active" game)
    self.game_started = false

    -- Try to load saved game
    if not self:loadGame() then
        self.game:deal()
    else
        self.game_started = true
    end

    -- Selection state
    self.selected_source = nil
    self.hint_highlight = nil

    -- Touch zones
    self.touch_zones = {}

    -- Input handling
    if Device:isTouchDevice() then
        self.ges_events = {
            Tap = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                }
            },
            Hold = {
                GestureRange:new{
                    ges = "hold",
                    range = self.dimen,
                }
            },
        }
    end

    if Device:hasKeys() then
        self.key_events.Close = { { "Back" }, doc = "close game" }
    end

    self:buildUI()
end

function SolitaireUI:loadSettings()
    local ok, settings = pcall(LuaSettings.open, LuaSettings, self.settings_path)
    if ok and settings then
        self.draw_mode_pref = settings:readSetting("draw_mode") or 1
    else
        self.draw_mode_pref = 1
    end
end

function SolitaireUI:saveSettings()
    local settings = LuaSettings:open(self.settings_path)
    settings:saveSetting("draw_mode", self.draw_mode_pref)
    settings:flush()
end

function SolitaireUI:saveGame()
    local save_data = self.game:toSaveData()
    local settings = LuaSettings:open(self.save_path)
    settings:saveSetting("game", save_data)
    settings:flush()
end

function SolitaireUI:loadGame()
    local ok, settings = pcall(LuaSettings.open, LuaSettings, self.save_path)
    if not ok or not settings then
        return false
    end

    local save_data = settings:readSetting("game")
    if not save_data then
        return false
    end

    return self.game:fromSaveData(save_data)
end

function SolitaireUI:deleteSave()
    os.remove(self.save_path)
end

function SolitaireUI:buildUI()
    self.touch_zones = {}

    local game_area_height = self.screen_height - self.status_bar_height - self.button_bar_height

    -- Draw mode label
    local draw_mode_label = self.game.draw_mode == 3 and "D3" or "D1"

    local button_bar = ButtonTable:new{
        width = self.screen_width,
        buttons = {
            {
                {
                    text = _("New"),
                    callback = function() self:newGame() end,
                },
                {
                    text = _("Undo"),
                    callback = function() self:undoMove() end,
                    enabled = self.game:canUndo(),
                },
                {
                    text = _("Hint"),
                    callback = function() self:showHint() end,
                },
                {
                    text = _("Auto"),
                    callback = function() self:autoMove() end,
                },
                {
                    text = _(draw_mode_label),
                    callback = function() self:toggleDrawMode() end,
                },
                {
                    text = _("Stats"),
                    callback = function() self:showStats() end,
                },
                {
                    text = _("Top"),
                    callback = function() self:showLeaderboard() end,
                },
                {
                    text = _("Close"),
                    callback = function() self:onClose() end,
                },
            },
        },
        show_parent = self,
    }

    self.button_bar_height = button_bar:getSize().h
    game_area_height = self.screen_height - self.status_bar_height - self.button_bar_height

    local time_str = self.game:formatTime()
    local status_text = string.format("Moves: %d  |  Score: %d  |  Time: %s",
        self.game.moves, self.game.score, time_str)

    local status_bar = FrameContainer:new{
        width = self.screen_width,
        height = self.status_bar_height,
        bordersize = 0,
        padding = 5,
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        CenterContainer:new{
            dimen = Geom:new{w = self.screen_width - 10, h = self.status_bar_height - 10},
            TextWidget:new{
                text = status_text,
                face = self.status_font,
            }
        }
    }

    local game_area = WidgetContainer:new{
        dimen = Geom:new{
            w = self.screen_width,
            h = game_area_height,
        },
    }
    game_area._parent = self
    game_area.paintTo = function(widget, bb, x, y)
        widget._parent:drawGame(bb, x, y)
    end

    self[1] = FrameContainer:new{
        width = self.screen_width,
        height = self.screen_height,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        VerticalGroup:new{
            align = "left",
            status_bar,
            game_area,
            button_bar,
        }
    }
end

function SolitaireUI:drawGame(bb, offset_x, offset_y)
    local y_offset = offset_y + 10

    self:drawStock(bb, self.margin, y_offset)
    self:drawWaste(bb, self.margin + self.card_width + self.card_spacing, y_offset)

    local foundation_start_x = self.screen_width - (4 * self.card_width) - (3 * self.card_spacing) - self.margin
    for f = 1, 4 do
        local x = foundation_start_x + (f - 1) * (self.card_width + self.card_spacing)
        self:drawFoundation(bb, x, y_offset, f)
    end

    local tableau_y = y_offset + self.card_height + self.margin
    local total_tableau_width = 7 * self.card_width + 6 * self.card_spacing
    local tableau_start_x = (self.screen_width - total_tableau_width) / 2

    for col = 1, 7 do
        local x = tableau_start_x + (col - 1) * (self.card_width + self.card_spacing)
        self:drawTableauColumn(bb, x, tableau_y, col)
    end
end

function SolitaireUI:drawCard(bb, x, y, card, highlighted, is_top_card, is_stock)
    local is_stock = is_stock or false
    local border_width = highlighted and 3 or 1

    bb:paintRect(x, y, self.card_width, self.card_height, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(x, y, self.card_width, self.card_height, border_width, Blitbuffer.COLOR_BLACK)

    if card and card.face_up then
        local rank = self.game.RANKS[card.rank]
        local suit = self.game.SUITS[card.suit].symbol
        local color = self.game:getCardColor(card)

        local text_color = Blitbuffer.COLOR_BLACK
        if color == "red" then
            text_color = Blitbuffer.COLOR_DARK_GRAY
        end

        local padding = 3

        local rank_widget = TextWidget:new{
            text = rank,
            face = self.rank_font,
            fgcolor = text_color,
        }
        rank_widget:paintTo(bb, x + padding, y)
        rank_widget:free()

        if is_top_card then -- Draw Centered suit symbol on top card of each pile
            local suit_center_widget = TextWidget:new{
                text = suit,
                face = self.suit_center_font,
                fgcolor = text_color,
            }
            local sw = suit_center_widget:getSize().w
            local sh = suit_center_widget:getSize().h

            local center_x = x + math.floor((self.card_width - sw) / 2)
            local center_y = y + math.floor((self.card_height - sh) / 2)
            suit_center_widget:paintTo(bb, center_x, center_y)
            suit_center_widget:free()
        else -- Draw smaller suit symbol in corner for non-top cards to help identify them
            local suit_tr_widget = TextWidget:new{
                text = suit,
                face = self.suit_font,
                fgcolor = text_color,
            }
            local stw = suit_tr_widget:getSize().w
            if(is_stock) then
                suit_tr_widget:paintTo(bb, x + padding, y + self.card_height - stw - padding * 2)
            else
                suit_tr_widget:paintTo(bb, x + self.card_width - stw - padding, y)
            end

            suit_tr_widget:free()
        end

    elseif card then -- Face-down card pattern
        self:drawCardBackPattern(bb, x, y)
    end
end

function SolitaireUI:drawCardBackPattern(bb, x, y)
    local pattern_color = Blitbuffer.COLOR_DARK_GRAY
    local density = 16
    local spacing = math.floor(self.card_width / density)
    local dot_size = math.max(1, math.floor(self.card_width * 0.03))

    for i = spacing, self.card_width - spacing + dot_size, spacing do
        for j = spacing, self.card_height - spacing + dot_size/2, spacing do
            bb:paintRect(x + i - dot_size/2, y + j - dot_size/2, dot_size, dot_size, pattern_color)
        end
    end
end

function SolitaireUI:drawEmptySlot(bb, x, y, label)
    bb:paintRect(x, y, self.card_width, self.card_height, Blitbuffer.COLOR_LIGHT_GRAY)
    bb:paintBorder(x, y, self.card_width, self.card_height, 1, Blitbuffer.COLOR_GRAY)

    if label then
        local text_widget = TextWidget:new{
            text = label,
            face = self.small_font,
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        }
        local tw = text_widget:getSize().w
        local th = text_widget:getSize().h
        text_widget:paintTo(bb,
            x + (self.card_width - tw) / 2,
            y + (self.card_height - th) / 2)
        text_widget:free()
    end
end

function SolitaireUI:drawStock(bb, x, y)
    table.insert(self.touch_zones, {
        x = x, y = y, w = self.card_width, h = self.card_height,
        type = "stock"
    })

    if #self.game.stock > 0 then
        local card = {face_up = false}
        self:drawCard(bb, x, y, card, false, true)
    else
        self:drawEmptySlot(bb, x, y, "↺")
    end
end

function SolitaireUI:drawWaste(bb, x, y)
    local is_selected = self.selected_source and
        self.selected_source.type == "waste"
    local is_hint = self.hint_highlight and
        (self.hint_highlight.type == "waste_to_foundation" or
         self.hint_highlight.type == "waste_to_tableau")

    local waste = self.game.waste
    local waste_count = #waste

    if waste_count == 0 then
        -- Register touch zone for empty waste
        table.insert(self.touch_zones, {
            x = x, y = y, w = self.card_width, h = self.card_height,
            type = "waste"
        })
        self:drawEmptySlot(bb, x, y, nil)
        return
    end

    -- In Draw-3 mode, show up to 3 fanned cards from the waste
    if self.game.draw_mode == 3 and waste_count > 1 then
        -- Show up to 3 cards fanned out
        local show_count = math.min(3, waste_count)
        local start_idx = waste_count - show_count + 1

        for i = 0, show_count - 1 do
            local card_idx = start_idx + i
            local card = waste[card_idx]
            local card_x = x + i * self.waste_fan_offset
            local is_top = (i == show_count - 1)
            local highlight = is_top and (is_selected or is_hint)

            -- Only the top card gets a touch zone for playing
            if is_top then
                table.insert(self.touch_zones, {
                    x = card_x, y = y, w = self.card_width, h = self.card_height,
                    type = "waste"
                })
            end

            self:drawCard(bb, card_x, y, card, highlight, is_top, true)
        end
    else
        -- Draw-1 mode: show single card
        table.insert(self.touch_zones, {
            x = x, y = y, w = self.card_width, h = self.card_height,
            type = "waste"
        })
        local card = waste[waste_count]
        self:drawCard(bb, x, y, card, is_selected or is_hint, true)
    end
end

function SolitaireUI:drawFoundation(bb, x, y, foundation_idx)
    table.insert(self.touch_zones, {
        x = x, y = y, w = self.card_width, h = self.card_height,
        type = "foundation", index = foundation_idx
    })

    local foundation = self.game.foundations[foundation_idx]
    local is_hint = self.hint_highlight and
        self.hint_highlight.foundation == foundation_idx

    if #foundation > 0 then
        local card = foundation[#foundation]
        self:drawCard(bb, x, y, card, is_hint, true)
    else
        local suit_symbol = Game.SUITS[foundation_idx].symbol
        self:drawEmptySlot(bb, x, y, suit_symbol)
    end
end

function SolitaireUI:drawTableauColumn(bb, x, y, col_idx)
    local column = self.game.tableau[col_idx]

    local is_selected_col = self.selected_source and
        self.selected_source.type == "tableau" and
        self.selected_source.index == col_idx

    local is_hint_from = self.hint_highlight and
        self.hint_highlight.from == col_idx
    local is_hint_to = self.hint_highlight and
        (self.hint_highlight.to == col_idx or self.hint_highlight.tableau == col_idx)

    if #column == 0 then
        table.insert(self.touch_zones, {
            x = x, y = y, w = self.card_width, h = self.card_height,
            type = "tableau", index = col_idx, card_pos = 1
        })
        local highlight = is_hint_to
        if highlight then
            bb:paintRect(x, y, self.card_width, self.card_height, Blitbuffer.COLOR_GRAY)
        end
        self:drawEmptySlot(bb, x, y, "K")
    else
        for i, card in ipairs(column) do
            local card_y = y + (i - 1) * self.stack_offset
            local card_height = (i == #column) and self.card_height or self.stack_offset

            local is_card_selected = is_selected_col and
                i >= self.selected_source.card_pos
            local is_card_hint = (is_hint_from and self.hint_highlight.card_idx and
                i >= self.hint_highlight.card_idx) or (is_hint_to and i == #column)

            table.insert(self.touch_zones, {
                x = x, y = card_y, w = self.card_width, h = card_height,
                type = "tableau", index = col_idx, card_pos = i
            })

            local is_top = (i == #column)
            self:drawCard(bb, x, card_y, card, is_card_selected or is_card_hint, is_top)
        end
    end
end

function SolitaireUI:findTouchZone(x, y)
    for i = #self.touch_zones, 1, -1 do
        local zone = self.touch_zones[i]
        if x >= zone.x and x <= zone.x + zone.w and
           y >= zone.y and y <= zone.y + zone.h then
            return zone
        end
    end
    return nil
end

function SolitaireUI:onTap(arg, ges)
    local pos = ges.pos
    local zone = self:findTouchZone(pos.x, pos.y)

    if not zone then
        self.selected_source = nil
        self:refreshUI()
        return true
    end

    self.hint_highlight = nil

    -- Mark game as started on first interaction
    if not self.game_started then
        self.game_started = true
    end

    if zone.type == "stock" then
        self.selected_source = nil
        self.game:drawFromStock()
        self:saveGame()
        self:refreshUI()
        return true
    end

    if zone.type == "waste" then
        if self.selected_source then
            self.selected_source = nil
        else
            if #self.game.waste > 0 then
                self.selected_source = {type = "waste"}
            end
        end
        self:refreshUI()
        return true
    end

    if zone.type == "foundation" then
        if self.selected_source then
            local success = false
            if self.selected_source.type == "waste" then
                success = self.game:moveToFoundation("waste", nil, zone.index)
            elseif self.selected_source.type == "tableau" then
                local col = self.game.tableau[self.selected_source.index]
                if self.selected_source.card_pos == #col then
                    success = self.game:moveToFoundation("tableau",
                        self.selected_source.index, zone.index)
                end
            end
            self.selected_source = nil
            if success then
                self:saveGame()
                if self.game:checkWin() then
                    self:showWinMessage()
                end
            end
        end
        self:refreshUI()
        return true
    end

    if zone.type == "tableau" then
        if self.selected_source then
            local success = false
            if self.selected_source.type == "waste" then
                success = self.game:moveToTableau("waste", nil, nil, zone.index)
            elseif self.selected_source.type == "tableau" then
                if self.selected_source.index ~= zone.index then
                    success = self.game:moveToTableau("tableau",
                        self.selected_source.index,
                        self.selected_source.card_pos,
                        zone.index)
                end
            elseif self.selected_source.type == "foundation" then
                success = self.game:moveToTableau("foundation",
                    self.selected_source.index, nil, zone.index)
            end
            self.selected_source = nil
            if success then
                self:saveGame()
                if self.game:checkWin() then
                    self:showWinMessage()
                end
            end
        else
            local col = self.game.tableau[zone.index]
            if #col > 0 then
                local card_pos = zone.card_pos
                if col[card_pos] and col[card_pos].face_up then
                    self.selected_source = {
                        type = "tableau",
                        index = zone.index,
                        card_pos = card_pos
                    }
                end
            end
        end
        self:refreshUI()
        return true
    end

    return true
end

function SolitaireUI:onHold(arg, ges)
    local pos = ges.pos
    local zone = self:findTouchZone(pos.x, pos.y)

    if zone then
        if zone.type == "waste" and #self.game.waste > 0 then
            local card = self.game.waste[#self.game.waste]
            for f = 1, 4 do
                if self.game:canPlaceOnFoundation(card, f) then
                    self.game:moveToFoundation("waste", nil, f)
                    self:saveGame()
                    if self.game:checkWin() then
                        self:showWinMessage()
                    end
                    break
                end
            end
        elseif zone.type == "tableau" then
            local col = self.game.tableau[zone.index]
            if #col > 0 then
                local card = col[#col]
                if card.face_up then
                    for f = 1, 4 do
                        if self.game:canPlaceOnFoundation(card, f) then
                            self.game:moveToFoundation("tableau", zone.index, f)
                            self:saveGame()
                            if self.game:checkWin() then
                                self:showWinMessage()
                            end
                            break
                        end
                    end
                end
            end
        end
    end

    self.selected_source = nil
    self:refreshUI()
    return true
end

-- mode can be:
--   "ui"      – no flash, good quality. Use for selection changes and single-card moves.
--   "partial" – full flash to clear ghosting. Use when the whole board changes.
--   "full"    – reserved for open/close.
function SolitaireUI:refreshUI(mode)
    self.touch_zones = {}
    self:buildUI()
    UIManager:setDirty(self, mode or "ui")
end

function SolitaireUI:newGame()
    -- Record loss for the current game if it was started and not won
    if self.game_started and not self.game:checkWin() and self.game.moves > 0 then
        self.stats:recordLoss(self.game.draw_mode)
    end

    self.game:deal()
    self.game:setDrawMode(self.draw_mode_pref)
    self.selected_source = nil
    self.hint_highlight = nil
    self.game_started = false
    self:deleteSave()
    self:refreshUI("partial")
end

function SolitaireUI:undoMove()
    if self.game:undo() then
        self.selected_source = nil
        self.hint_highlight = nil
        self:saveGame()
        self:refreshUI("partial")
    else
        UIManager:show(InfoMessage:new{
            text = _("Nothing to undo."),
            timeout = 1,
        })
    end
end

function SolitaireUI:showHint()
    local hint = self.game:getHint()
    if hint then
        self.hint_highlight = hint
        self:refreshUI()

        UIManager:scheduleIn(2, function()
            self.hint_highlight = nil
            if self[1] then
                self:refreshUI()
            end
        end)
    else
        UIManager:show(InfoMessage:new{
            text = _("No moves available. Try drawing from stock."),
            timeout = 2,
        })
    end
end

function SolitaireUI:autoMove()
    local moved = true
    local total_moves = 0

    while moved and total_moves < 52 do
        moved = self.game:autoMoveToFoundation()
        if moved then
            total_moves = total_moves + 1
        end
    end

    if total_moves > 0 then
        self:saveGame()
    end

    self:refreshUI(total_moves > 0 and "partial" or "ui")

    if self.game:checkWin() then
        self:showWinMessage()
    elseif total_moves == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No cards can be automatically moved to foundations."),
            timeout = 2,
        })
    end
end

function SolitaireUI:toggleDrawMode()
    if self.game.draw_mode == 1 then
        self.draw_mode_pref = 3
    else
        self.draw_mode_pref = 1
    end
    self.game:setDrawMode(self.draw_mode_pref)
    self:saveSettings()
    self:saveGame()

    local mode_name = self.draw_mode_pref == 3 and "Draw 3" or "Draw 1"
    UIManager:show(InfoMessage:new{
        text = string.format(_("Switched to %s mode"), mode_name),
        timeout = 1,
    })

    self:refreshUI("partial")
end

function SolitaireUI:showMoreMenu()
    -- Show a simple menu with Stats, Leaderboard, Reset Stats
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    dialog = ButtonDialog:new{
        title = _("Solitaire"),
        buttons = {
            {
                {
                    text = _("Statistics"),
                    callback = function()
                        UIManager:close(dialog)
                        self:showStats()
                    end,
                },
            },
            {
                {
                    text = _("Leaderboard"),
                    callback = function()
                        UIManager:close(dialog)
                        self:showLeaderboard()
                    end,
                },
            },
            {
                {
                    text = _("Reset Statistics"),
                    callback = function()
                        UIManager:close(dialog)
                        self:confirmResetStats()
                    end,
                },
            },
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function SolitaireUI:showStats()
    local text = self.stats:getStatsText()
    UIManager:show(InfoMessage:new{
        text = text,
        width = math.floor(self.screen_width * 0.8),
    })
end

function SolitaireUI:showLeaderboard()
    local text = self.stats:getLeaderboardText()
    UIManager:show(InfoMessage:new{
        text = text,
        width = math.floor(self.screen_width * 0.8),
    })
end

function SolitaireUI:confirmResetStats()
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    dialog = ButtonDialog:new{
        title = _("Reset Statistics"),
        text = _("Are you sure you want to reset all statistics and leaderboard data? This cannot be undone."),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Reset"),
                    callback = function()
                        UIManager:close(dialog)
                        self.stats:reset()
                        UIManager:show(InfoMessage:new{
                            text = _("Statistics have been reset."),
                            timeout = 2,
                        })
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function SolitaireUI:showWinMessage()
    local elapsed = self.game:getElapsedTime()
    local time_str = self.game:formatTime(elapsed)

    -- Stop timer
    self.game:stopTimer()

    -- Record win in stats
    self.stats:recordWin(
        self.game.score,
        self.game.moves,
        elapsed,
        self.game.draw_mode
    )

    -- Check if this is a new best
    local extra = ""
    if self.game.score >= self.stats.best_score then
        extra = "\n🏆 New Best Score!"
    end
    if self.stats.best_time == elapsed then
        extra = extra .. "\n⚡ New Best Time!"
    end
    if self.stats.fewest_moves == self.game.moves then
        extra = extra .. "\n🎯 New Fewest Moves!"
    end

    self:deleteSave()
    self.game_started = false

    UIManager:show(InfoMessage:new{
        text = string.format(
            _("Congratulations! You won!\n\nMoves: %d\nScore: %d\nTime: %s\nMode: Draw-%d%s\n\nWin Streak: %d"),
            self.game.moves, self.game.score, time_str,
            self.game.draw_mode, extra, self.stats.current_win_streak
        ),
    })
end

function SolitaireUI:onClose()
    self:saveGame()
    -- Stop the timer refresh
    self.game:stopTimer()
    UIManager:close(self)
    return true
end

function SolitaireUI:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

return SolitaireUI
