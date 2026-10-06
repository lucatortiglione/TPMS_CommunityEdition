-- RD layout points are already scaled. Scale only our offsets and icon size.
local Layout = {}
local floor = math.floor
local anchors = {
    -- Center the 17px TPMS above the 20px STOP lamp, leaving a 6px gap at 1x.
    standard = { point = "stop", dx = 2, dy = -23, x = 233, y = 116 },
    heavy = { point = "stop", dx = 32, dy = 0, x = 201, y = 137 },
    sport = { point = "door", dx = -26, dy = 0, x = 385, y = 162 },
}

local function round(value)
    return floor(value + 0.5)
end

-- getTexture can hand back an empty placeholder or nil on failure.
local function usableTexture(texture)
    if not texture then return false end
    local ok, width, height = pcall(function()
        return texture:getWidthOrig(), texture:getHeightOrig()
    end)
    return ok and type(width) == "number" and type(height) == "number"
        and width > 0 and height > 0
end

local function resolveAnchor(dashboard, family, scale)
    local anchor = anchors[family] or anchors.standard
    local x, y = round(anchor.x * scale), round(anchor.y * scale)
    local yd = YourDash
    if not (yd and yd.GetLayoutPoint) then return x, y end
    local ax, ay = yd.GetLayoutPoint(dashboard, "warnings", "tpms")
    if ax == nil or ay == nil then
        -- A future RD release or add-on can supply a dedicated TPMS slot.
        ax, ay = yd.GetLayoutPoint(dashboard, "warnings", anchor.point)
        if ax ~= nil and ay ~= nil then
            ax, ay = ax + round(anchor.dx * scale), ay + round(anchor.dy * scale)
        end
    end
    if ax == nil or ay == nil then return x, y end
    return ax, ay
end

function Layout.isPassenger(dashboard)
    return dashboard.__paxChildrenCreated ~= nil or dashboard.__paxRetracted ~= nil
        or dashboard.Type == "YourDashPassengerDashboard"
end

function Layout.update(dashboard, state)
    local background = dashboard.backgroundTex
    if not background then return false end
    local yd = YourDash
    local realistic = dashboard.__YourDashPatched == true
        or (yd ~= nil and yd.MODOPT_ID == "RealisticDash" and dashboard.__YourDashFamily ~= nil)
    local family = realistic and (dashboard.__YourDashFamily or "standard") or "vanilla"
    local scale = realistic and yd and yd.GetScale and yd.GetScale() or 1
    if type(scale) ~= "number" or scale ~= scale or scale <= 0 or scale == math.huge then scale = 1 end
    local bx, by = background:getX(), background:getY()
    local bw, bh = background:getWidth(), background:getHeight()
    if not state.layoutDirty and state.family == family and state.scale == scale
        and state.textureStatus == state.status
        and state.bx == bx and state.by == by and state.bw == bw and state.bh == bh
        and state.background == background then return true end

    local x, y = 205, 56
    if realistic then
        x, y = resolveAnchor(dashboard, family, scale)
    end
    local light = state.light
    local texture = state.textures.icon
    if state.status == "on" or state.status == "warn" then
        texture = state.textures.yellow or texture
    elseif state.status == "error" then
        texture = state.textures.red or texture
    end
    if not usableTexture(texture) then texture = state.textures.icon end
    if not usableTexture(texture) then return false end
    light.texture = texture
    local width, height = round(texture:getWidthOrig() * scale), round(texture:getHeightOrig() * scale)
    x = math.max(0, math.min(x, bw - width))
    y = math.max(0, math.min(y, bh - height))
    light:setX(bx + x)
    light:setY(by + y)
    light:setWidth(width)
    light:setHeight(height)
    light.scaledWidth, light.scaledHeight = width, height
    if state.panel then
        state.panel:setX(bx + x - 4)
        state.panel:setY(by + y - 4)
    end
    state.realistic, state.family, state.scale = realistic, family, scale
    state.textureStatus = state.status
    state.bx, state.by, state.bw, state.bh = bx, by, bw, bh
    state.background, state.layoutDirty = background, false
    return true
end

return Layout
