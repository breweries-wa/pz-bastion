-- ============================================================
-- Bastion_HUD.lua  (media/lua/client/)
-- Small always-on panel in the top-right corner.
-- Shows: settlers, food days, water days, noise score / budget.
-- Refreshes every 5 seconds via OnTick counter.
-- ============================================================
print("[Bastion] HUD loading")

-- ── Constants ─────────────────────────────────────────────────────────────────

local PANEL_W      = 190
local PANEL_H      = 90
local MARGIN_RIGHT = 10
local MARGIN_TOP   = 70    -- below the default PZ HUD row
local REFRESH_TICKS = 150  -- ~5 s at 30 tps

-- ── Panel class ───────────────────────────────────────────────────────────────

BastionHUD = ISPanel:derive("BastionHUD")

function BastionHUD:new(x, y)
    local o = ISPanel.new(self, x, y, PANEL_W, PANEL_H)
    o.backgroundColor = { r=0, g=0, b=0, a=0.55 }
    o.borderColor     = { r=0.5, g=0.4, b=0.7, a=0.9 }
    o.tickCounter     = 0
    o.data            = {}   -- cached display data
    return o
end

-- ── Data refresh ──────────────────────────────────────────────────────────────

function BastionHUD:refresh()
    local player = getSpecificPlayer(0)
    if not player then self.data = {}; return end

    local username = player:getUsername()
    local world    = ModData.get(Bastion.DATA_KEY) or {}
    local rec      = world[username]

    if not rec then
        self.data = { active = false }
        return
    end

    local settlers   = rec.settlers or {}
    local noiseScore = rec.noiseScore or 0
    local budgetKey  = rec.noiseBudgetLevel or "Normal"
    local budget     = Bastion.NOISE_BUDGETS[budgetKey] or 6

    -- Noise colour: green if under budget, yellow if at, red if over.
    local noiseR, noiseG, noiseB
    if noiseScore <= budget then
        noiseR, noiseG, noiseB = 0.4, 1.0, 0.4
    elseif noiseScore <= budget * 1.5 then
        noiseR, noiseG, noiseB = 1.0, 0.9, 0.2
    else
        noiseR, noiseG, noiseB = 1.0, 0.35, 0.35
    end

    -- Food colour: green > 7 days, yellow 3-7, red < 3.
    local fd = rec.foodDays or 0
    local foodR, foodG, foodB
    if fd > 7 then
        foodR, foodG, foodB = 0.4, 1.0, 0.4
    elseif fd >= 3 then
        foodR, foodG, foodB = 1.0, 0.9, 0.2
    else
        foodR, foodG, foodB = 1.0, 0.35, 0.35
    end

    -- Water colour: same thresholds (days supply).
    local wd = rec.waterDays or 0
    local waterR, waterG, waterB
    if wd > 7 then
        waterR, waterG, waterB = 0.4, 1.0, 0.4
    elseif wd >= 3 then
        waterR, waterG, waterB = 1.0, 0.9, 0.2
    else
        waterR, waterG, waterB = 1.0, 0.35, 0.35
    end

    self.data = {
        active    = true,
        settlers  = #settlers,
        foodDays  = math.floor(fd),
        waterDays = math.floor(wd),
        noise     = noiseScore,
        budget    = budget,
        budgetKey = budgetKey,
        noiseR = noiseR, noiseG = noiseG, noiseB = noiseB,
        foodR  = foodR,  foodG  = foodG,  foodB  = foodB,
        waterR = waterR, waterG = waterG, waterB = waterB,
    }
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

function BastionHUD:prerender()
    ISPanel.prerender(self)
end

function BastionHUD:render()
    local d = self.data
    if not d or not d.active then
        -- Draw a tiny "no bastion" hint so the player knows the HUD is there.
        self:drawText("No active bastion", 8, 8, 0.5, 0.5, 0.5, 0.8,
                      UIFont.Small)
        return
    end

    local y    = 6
    local dx   = 8
    local step = 16

    -- Title
    self:drawText("⬡ BASTION", dx, y, 0.8, 0.65, 1.0, 1.0, UIFont.Small)
    y = y + step + 2

    -- Settlers
    self:drawText("Settlers: " .. d.settlers,
                  dx, y, 0.85, 0.85, 0.85, 1.0, UIFont.Small)
    y = y + step

    -- Food
    self:drawText("Food: " .. d.foodDays .. " day" .. (d.foodDays == 1 and "" or "s"),
                  dx, y, d.foodR, d.foodG, d.foodB, 1.0, UIFont.Small)
    y = y + step

    -- Water
    self:drawText("Water: " .. d.waterDays .. " day" .. (d.waterDays == 1 and "" or "s"),
                  dx, y, d.waterR, d.waterG, d.waterB, 1.0, UIFont.Small)
    y = y + step

    -- Noise
    self:drawText("Noise: " .. d.noise .. " / " .. d.budget
                  .. "  [" .. d.budgetKey .. "]",
                  dx, y, d.noiseR, d.noiseG, d.noiseB, 1.0, UIFont.Small)
end

-- ── Update (tick) ─────────────────────────────────────────────────────────────

function BastionHUD:update()
    ISPanel.update(self)
    self.tickCounter = self.tickCounter + 1
    if self.tickCounter >= REFRESH_TICKS then
        self.tickCounter = 0
        self:refresh()
    end
end

-- ── Module API ────────────────────────────────────────────────────────────────

local hudInstance = nil

function BastionHUD.show()
    if hudInstance then return end

    local sw = getCore():getScreenWidth()
    local x  = sw - PANEL_W - MARGIN_RIGHT
    local y  = MARGIN_TOP

    hudInstance = BastionHUD:new(x, y)
    hudInstance:initialise()
    hudInstance:addToUIManager()
    hudInstance:refresh()
end

function BastionHUD.hide()
    if hudInstance then
        hudInstance:removeFromUIManager()
        hudInstance = nil
    end
end

function BastionHUD.toggle()
    if hudInstance then BastionHUD.hide() else BastionHUD.show() end
end

-- Auto-show when a game starts.
Events.OnGameStart.Add(function()
    BastionHUD.show()
end)

print("[Bastion] HUD done")
