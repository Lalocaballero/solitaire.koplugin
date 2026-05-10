local Game = {}

-- Card suits and their properties
Game.SUITS = {
    {name = "hearts",   symbol = "♥", color = "red"},
    {name = "diamonds", symbol = "♦", color = "red"},
    {name = "clubs",    symbol = "♣", color = "black"},
    {name = "spades",   symbol = "♠", color = "black"},
}

Game.RANKS = {"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"}

function Game:new()
    local o = {
        stock = {},
        waste = {},
        foundations = {{}, {}, {}, {}},
        tableau = {{}, {}, {}, {}, {}, {}, {}},
        selected = nil,
        moves = 0,
        score = 0,
        -- Draw mode: 1 = draw one, 3 = draw three
        draw_mode = 1,
        -- How many cards were drawn in the last draw (for display purposes)
        last_draw_count = 0,
        -- Timer
        start_time = nil,
        elapsed_time = 0,
        timer_running = false,
        -- Undo history
        history = {},
        max_history = 100,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

-- Deep copy a card
function Game:copyCard(card)
    if not card then return nil end
    return {
        suit = card.suit,
        rank = card.rank,
        face_up = card.face_up,
    }
end

-- Deep copy a pile of cards
function Game:copyPile(pile)
    local copy = {}
    for i, card in ipairs(pile) do
        copy[i] = self:copyCard(card)
    end
    return copy
end

function Game:isValidCard(card)
    return type(card) == "table" and
        type(card.suit) == "number" and card.suit >= 1 and card.suit <= 4 and
        type(card.rank) == "number" and card.rank >= 1 and card.rank <= 13 and
        type(card.face_up) == "boolean"
end

function Game:isValidPile(pile)
    if type(pile) ~= "table" then
        return false
    end
    for _, card in ipairs(pile) do
        if not self:isValidCard(card) then
            return false
        end
    end
    return true
end

function Game:isValidPileGroup(piles, expected_count)
    if type(piles) ~= "table" then
        return false
    end
    for i = 1, expected_count do
        if not self:isValidPile(piles[i]) then
            return false
        end
    end
    return true
end

-- Save current state to history (call before making a move)
function Game:saveState()
    local state = {
        stock = self:copyPile(self.stock),
        waste = self:copyPile(self.waste),
        foundations = {
            self:copyPile(self.foundations[1]),
            self:copyPile(self.foundations[2]),
            self:copyPile(self.foundations[3]),
            self:copyPile(self.foundations[4]),
        },
        tableau = {
            self:copyPile(self.tableau[1]),
            self:copyPile(self.tableau[2]),
            self:copyPile(self.tableau[3]),
            self:copyPile(self.tableau[4]),
            self:copyPile(self.tableau[5]),
            self:copyPile(self.tableau[6]),
            self:copyPile(self.tableau[7]),
        },
        moves = self.moves,
        score = self.score,
    }
    
    table.insert(self.history, state)
    
    -- Limit history size
    if #self.history > self.max_history then
        table.remove(self.history, 1)
    end
end

-- Undo last move
function Game:undo()
    if #self.history == 0 then
        return false
    end
    
    local state = table.remove(self.history)
    
    self.stock = state.stock
    self.waste = state.waste
    self.foundations = state.foundations
    self.tableau = state.tableau
    self.moves = state.moves
    self.score = state.score
    
    return true
end

-- Check if undo is available
function Game:canUndo()
    return #self.history > 0
end

-- Clear history (call when starting new game)
function Game:clearHistory()
    self.history = {}
end

function Game:createCard(suit_idx, rank_idx)
    return {
        suit = suit_idx,
        rank = rank_idx,
        face_up = false,
    }
end

function Game:createDeck()
    local deck = {}
    for suit = 1, 4 do
        for rank = 1, 13 do
            table.insert(deck, self:createCard(suit, rank))
        end
    end
    return deck
end

function Game:shuffle(deck)
    math.randomseed(os.time())
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
    return deck
end

function Game:deal()
    local deck = self:shuffle(self:createDeck())
    
    -- Reset all piles
    self.stock = {}
    self.waste = {}
    self.foundations = {{}, {}, {}, {}}
    self.tableau = {{}, {}, {}, {}, {}, {}, {}}
    self.selected = nil
    self.moves = 0
    self.score = 0
    self.last_draw_count = 0
    
    -- Reset and start timer
    self.elapsed_time = 0
    self.start_time = os.time()
    self.timer_running = true
    
    -- Clear undo history for new game
    self:clearHistory()
    
    -- Deal to tableau
    local card_idx = 1
    for col = 1, 7 do
        for row = 1, col do
            local card = deck[card_idx]
            card.face_up = (row == col)
            table.insert(self.tableau[col], card)
            card_idx = card_idx + 1
        end
    end
    
    -- Remaining cards go to stock
    for i = card_idx, 52 do
        deck[i].face_up = false
        table.insert(self.stock, deck[i])
    end
end

function Game:getCardColor(card)
    return self.SUITS[card.suit].color
end

function Game:getCardDisplay(card)
    if not card.face_up then
        return "▒▒▒"
    end
    return self.RANKS[card.rank] .. self.SUITS[card.suit].symbol
end

function Game:canPlaceOnTableau(card, target_pile)
    if #target_pile == 0 then
        return card.rank == 13
    end
    
    local top_card = target_pile[#target_pile]
    if not top_card.face_up then
        return false
    end
    
    local diff_color = self:getCardColor(card) ~= self:getCardColor(top_card)
    local one_lower = card.rank == top_card.rank - 1
    
    return diff_color and one_lower
end

function Game:canPlaceOnFoundation(card, foundation_idx)
    local foundation = self.foundations[foundation_idx]
    
    if #foundation == 0 then
        return card.rank == 1
    end
    
    local top_card = foundation[#foundation]
    
    local same_suit = card.suit == top_card.suit
    local one_higher = card.rank == top_card.rank + 1
    
    return same_suit and one_higher
end

function Game:drawFromStock()
    -- Save state before move
    self:saveState()
    
    if #self.stock == 0 then
        if #self.waste == 0 then
            -- Remove saved state since no move was made
            table.remove(self.history)
            return false
        end
        while #self.waste > 0 do
            local card = table.remove(self.waste)
            card.face_up = false
            table.insert(self.stock, card)
        end
        self.last_draw_count = 0
        self.score = math.max(0, self.score - 20)
        return true
    end
    
    -- Draw 1 or 3 cards depending on draw_mode
    local cards_to_draw = math.min(self.draw_mode, #self.stock)
    self.last_draw_count = cards_to_draw
    for i = 1, cards_to_draw do
        local card = table.remove(self.stock)
        card.face_up = true
        table.insert(self.waste, card)
    end
    return true
end

-- Set draw mode (1 or 3)
function Game:setDrawMode(mode)
    if mode == 1 or mode == 3 then
        self.draw_mode = mode
    end
end

-- Timer functions
function Game:startTimer()
    self.start_time = os.time()
    self.timer_running = true
end

function Game:stopTimer()
    if self.timer_running and self.start_time then
        self.elapsed_time = self.elapsed_time + (os.time() - self.start_time)
        self.start_time = nil
        self.timer_running = false
    end
end

function Game:getElapsedTime()
    local total = self.elapsed_time
    if self.timer_running and self.start_time then
        total = total + (os.time() - self.start_time)
    end
    return total
end

function Game:formatTime(seconds)
    if not seconds then seconds = self:getElapsedTime() end
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%d:%02d", mins, secs)
end

function Game:moveToFoundation(source_type, source_idx, foundation_idx)
    local source_pile
    local card
    
    if source_type == "waste" then
        if #self.waste == 0 then return false end
        card = self.waste[#self.waste]
        source_pile = self.waste
    elseif source_type == "tableau" then
        if #self.tableau[source_idx] == 0 then return false end
        card = self.tableau[source_idx][#self.tableau[source_idx]]
        if not card.face_up then return false end
        source_pile = self.tableau[source_idx]
    else
        return false
    end
    
    if not self:canPlaceOnFoundation(card, foundation_idx) then
        return false
    end
    
    -- Save state before move
    self:saveState()
    
    -- Move the card
    table.remove(source_pile)
    table.insert(self.foundations[foundation_idx], card)
    
    -- Flip newly exposed card
    if source_type == "tableau" and #source_pile > 0 then
        local new_top = source_pile[#source_pile]
        if not new_top.face_up then
            new_top.face_up = true
            self.score = self.score + 5
        end
    end
    
    self.moves = self.moves + 1
    self.score = self.score + 10
    return true
end

function Game:moveToTableau(source_type, source_idx, card_pos, target_col)
    local cards_to_move = {}
    local source_pile
    
    if source_type == "waste" then
        if #self.waste == 0 then return false end
        cards_to_move = {self.waste[#self.waste]}
        source_pile = self.waste
    elseif source_type == "tableau" then
        source_pile = self.tableau[source_idx]
        if card_pos > #source_pile then return false end
        
        if not source_pile[card_pos].face_up then return false end
        
        for i = card_pos, #source_pile do
            table.insert(cards_to_move, source_pile[i])
        end
    elseif source_type == "foundation" then
        local foundation = self.foundations[source_idx]
        if #foundation == 0 then return false end
        cards_to_move = {foundation[#foundation]}
        source_pile = foundation
    else
        return false
    end
    
    if #cards_to_move == 0 then return false end
    
    if not self:canPlaceOnTableau(cards_to_move[1], self.tableau[target_col]) then
        return false
    end
    
    -- Save state before move
    self:saveState()
    
    -- Remove cards from source
    if source_type == "tableau" then
        for i = 1, #cards_to_move do
            table.remove(source_pile)
        end
    else
        table.remove(source_pile)
    end
    
    -- Add cards to target
    for _, card in ipairs(cards_to_move) do
        table.insert(self.tableau[target_col], card)
    end
    
    -- Flip newly exposed card
    if source_type == "tableau" and #source_pile > 0 then
        local new_top = source_pile[#source_pile]
        if not new_top.face_up then
            new_top.face_up = true
            self.score = self.score + 5
        end
    end
    
    self.moves = self.moves + 1
    if source_type == "foundation" then
        self.score = math.max(0, self.score - 15)
    else
        self.score = self.score + 5
    end
    
    return true
end

function Game:autoMoveToFoundation()
    local moved = false
    
    -- Check waste
    if #self.waste > 0 then
        local card = self.waste[#self.waste]
        for f = 1, 4 do
            if self:canPlaceOnFoundation(card, f) then
                if self:moveToFoundation("waste", nil, f) then
                    moved = true
                    break
                end
            end
        end
    end
    
    -- Check tableau
    if not moved then
        for t = 1, 7 do
            if #self.tableau[t] > 0 then
                local card = self.tableau[t][#self.tableau[t]]
                if card.face_up then
                    for f = 1, 4 do
                        if self:canPlaceOnFoundation(card, f) then
                            if self:moveToFoundation("tableau", t, f) then
                                moved = true
                                break
                            end
                        end
                    end
                end
            end
            if moved then break end
        end
    end
    
    return moved
end

function Game:checkWin()
    for f = 1, 4 do
        if #self.foundations[f] ~= 13 then
            return false
        end
    end
    return true
end

function Game:getHint()
    -- Check waste to foundation
    if #self.waste > 0 then
        local card = self.waste[#self.waste]
        for f = 1, 4 do
            if self:canPlaceOnFoundation(card, f) then
                return {type = "waste_to_foundation", foundation = f}
            end
        end
    end
    
    -- Check tableau to foundation
    for t = 1, 7 do
        if #self.tableau[t] > 0 then
            local card = self.tableau[t][#self.tableau[t]]
            if card.face_up then
                for f = 1, 4 do
                    if self:canPlaceOnFoundation(card, f) then
                        return {type = "tableau_to_foundation", tableau = t, foundation = f}
                    end
                end
            end
        end
    end
    
    -- Check waste to tableau
    if #self.waste > 0 then
        local card = self.waste[#self.waste]
        for t = 1, 7 do
            if self:canPlaceOnTableau(card, self.tableau[t]) then
                return {type = "waste_to_tableau", tableau = t}
            end
        end
    end
    
    -- Check tableau to tableau
    for from = 1, 7 do
        for card_idx = 1, #self.tableau[from] do
            local card = self.tableau[from][card_idx]
            if card.face_up then
                for to = 1, 7 do
                    if from ~= to and self:canPlaceOnTableau(card, self.tableau[to]) then
                        if card.rank ~= 13 or #self.tableau[to] > 0 or card_idx > 1 then
                            return {type = "tableau_to_tableau", from = from, to = to, card_idx = card_idx}
                        end
                    end
                end
            end
        end
    end
    
    -- Suggest draw
    if #self.stock > 0 or #self.waste > 0 then
        return {type = "draw"}
    end
    
    return nil
end

-- Convert game state to saveable data
function Game:toSaveData()
    -- Freeze timer before saving
    local elapsed = self:getElapsedTime()
    return {
        stock = self:copyPile(self.stock),
        waste = self:copyPile(self.waste),
        foundations = {
            self:copyPile(self.foundations[1]),
            self:copyPile(self.foundations[2]),
            self:copyPile(self.foundations[3]),
            self:copyPile(self.foundations[4]),
        },
        tableau = {
            self:copyPile(self.tableau[1]),
            self:copyPile(self.tableau[2]),
            self:copyPile(self.tableau[3]),
            self:copyPile(self.tableau[4]),
            self:copyPile(self.tableau[5]),
            self:copyPile(self.tableau[6]),
            self:copyPile(self.tableau[7]),
        },
        moves = self.moves,
        score = self.score,
        draw_mode = self.draw_mode,
        last_draw_count = self.last_draw_count,
        elapsed_time = elapsed,
        -- Don't save history to keep file small
    }
end

-- Load game state from saved data
function Game:fromSaveData(data)
    if type(data) ~= "table" then return false end

    local stock = data.stock or {}
    local waste = data.waste or {}
    local foundations = data.foundations or {{}, {}, {}, {}}
    local tableau = data.tableau or {{}, {}, {}, {}, {}, {}, {}}

    if not self:isValidPile(stock) or
        not self:isValidPile(waste) or
        not self:isValidPileGroup(foundations, 4) or
        not self:isValidPileGroup(tableau, 7) then
        return false
    end

    self.stock = stock
    self.waste = waste
    self.foundations = foundations
    self.tableau = tableau
    self.moves = data.moves or 0
    self.score = data.score or 0
    self.draw_mode = data.draw_mode or 1
    self.last_draw_count = data.last_draw_count or 0
    self.elapsed_time = data.elapsed_time or 0
    self.start_time = os.time()
    self.timer_running = true
    self:clearHistory()
    
    return true
end

return Game
