-- EmmyLua stubs for PZ's Lua-side UI classes.
-- These are not loaded by PZ at runtime — EmmyLua only.
-- Covers the subset of the API used by Bastion_Window.lua.

-- ── UIFont ────────────────────────────────────────────────────────────────────

---@class UIFont
---@field Small  UIFont
---@field Medium UIFont
---@field Large  UIFont
UIFont = {}

-- ── ISUIElement (common base) ─────────────────────────────────────────────────

---@class ISUIElement
---@field width           number
---@field height          number
---@field backgroundColor { r:number, g:number, b:number, a:number }
---@field borderColor     { r:number, g:number, b:number, a:number }
local ISUIElement = {}

---@param text  string
---@param x     number
---@param y     number
---@param r     number
---@param g     number
---@param b     number
---@param a     number
---@param font  UIFont
function ISUIElement:drawText(text, x, y, r, g, b, a, font) end

---@param x number
---@param y number
---@param w number
---@param h number
---@param a number
---@param r number
---@param g number
---@param b number
function ISUIElement:drawRect(x, y, w, h, a, r, g, b) end

---@param w number
function ISUIElement:setWidth(w) end

---@param h number
function ISUIElement:setHeight(h) end

---@param x number
function ISUIElement:setX(x) end

---@param y number
function ISUIElement:setY(y) end

---@return number
function ISUIElement:getX() end

---@return number
function ISUIElement:getY() end

---@param visible boolean
function ISUIElement:setVisible(visible) end

function ISUIElement:initialise() end
function ISUIElement:addToUIManager() end
function ISUIElement:removeFromUIManager() end
function ISUIElement:bringToTop() end

---@param child ISUIElement
function ISUIElement:addChild(child) end

-- ── ISPanel ───────────────────────────────────────────────────────────────────

---@class ISPanel : ISUIElement
ISPanel = {}

---@param self  ISPanel
---@param x     number
---@param y     number
---@param w     number
---@param h     number
---@return ISPanel
function ISPanel.new(self, x, y, w, h) end

function ISPanel:render() end
function ISPanel:prerender() end
function ISPanel:update() end

---@param name string
---@return ISPanel
function ISPanel:derive(name) end

-- ── ISButton ──────────────────────────────────────────────────────────────────

---@class ISButton : ISUIElement
---@field noiseLevelTag string|nil
ISButton = {}

---@param x       number
---@param y       number
---@param w       number
---@param h       number
---@param title   string
---@param target  table
---@param onclick fun(target:table)
---@return ISButton
function ISButton:new(x, y, w, h, title, target, onclick) end

-- ── ISScrollingListBox ────────────────────────────────────────────────────────

---@class ISScrollingListBoxItem
---@field text string
---@field item any

---@class ISScrollingListBox : ISUIElement
---@field itemheight  number
---@field doDrawItem  fun(listbox:ISScrollingListBox, y:number, item:ISScrollingListBoxItem, alt:boolean):number
---@field items       ISScrollingListBoxItem[]
---@field selected    integer
ISScrollingListBox = {}

---@param x number
---@param y number
---@param w number
---@param h number
---@return ISScrollingListBox
function ISScrollingListBox:new(x, y, w, h) end

function ISScrollingListBox:clear() end

---@param text string
---@param data any
function ISScrollingListBox:addItem(text, data) end

---@return number
function ISScrollingListBox:getWidth() end
