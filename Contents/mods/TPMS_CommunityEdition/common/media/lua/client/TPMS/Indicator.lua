require "ISUI/ISImage"
local Core = require "TPMS/Core"
local Layout = require "TPMS/Layout"
local Indicator = {}

local SAMPLE_MS = 1000
local BLINK_MS = 250
local colors = {
    off = { r = 1, g = 1, b = 1, a = 0.4 },
    on = { r = 0.8, g = 0.62, b = 0, a = 1 },
    error = { r = 1, g = 0, b = 0, a = 0.6 },
    realistic = { r = 1, g = 1, b = 1, a = 1 },
}
local textures

local function noAction()
    return false
end

local function setVisible(image, visible)
    if image and image:getIsVisible() ~= visible then
        image:setVisible(visible)
        if not visible then
            image.mouseover = false
            if image.tooltipUI then
                image.tooltipUI:setVisible(false)
                image.tooltipUI:removeFromUIManager()
            end
        end
    end
end

local function hide(state)
    setVisible(state.light, false)
    setVisible(state.panel, false)
end

local function newImage(dashboard, texture)
    if not texture then return nil end
    local image = ISImage:new(0, 0, texture:getWidthOrig(), texture:getHeightOrig(), texture)
    image:initialise()
    image:instantiate()
    image.onclick, image.target = noAction, dashboard
    image:setVisible(false)
    dashboard:addChild(image)
    return image
end

local function resetLight(state)
    state.status, state.light.state = "off", "off"
    state.light.mouseovertext = getText("Tooltip_LTPMS_TPMS")
    state.blinkStart = nil
    hide(state)
end

-- Single place that clears everything sampled or derived from a vehicle, so
-- binding, creation and eligibility changes cannot drift apart.
local function resetState(state, vehicle)
    state.vehicle = vehicle
    state.tires, state.partCount, state.script = nil, nil, nil
    state.powered, state.nextSample, state.lastTime = false, 0, nil
    state.settings, state.eligible = nil, false
    state.background = nil
    state.tooltip = nil
    resetLight(state)
    state.layoutDirty = true
end

function Indicator.ensure(dashboard)
    if Layout.isPassenger(dashboard) or not dashboard.backgroundTex then return nil end
    if dashboard.__lawlyTPMS then return dashboard.__lawlyTPMS end
    if not textures then
        textures = {
            icon = getTexture("media/ui/tpms.png"),
            realistic = getTexture("media/ui/tpmsRD.png"),
            background = getTexture("media/ui/tpms_background.png"),
        }
    end
    if not textures.icon then return nil end
    local state = {
        textures = textures,
        panel = newImage(dashboard, textures.background),
        light = newImage(dashboard, textures.icon),
    }
    resetState(state, dashboard.vehicle)
    dashboard.__lawlyTPMS = state
    -- Preserve the public image fields used by the original mod.
    dashboard.TPMSLight, dashboard.TPMSBG = state.light, state.panel
    return state
end

function Indicator.invalidateLayout(dashboard)
    if dashboard.__lawlyTPMS then dashboard.__lawlyTPMS.layoutDirty = true end
end

local function bindVehicle(state, vehicle)
    -- A dashboard is reused between cars. Nothing sampled from the previous car
    -- survives a new seating/vehicle assignment, even for the same script model.
    resetState(state, vehicle)
end

function Indicator.setVehicle(dashboard, vehicle)
    local state = Indicator.ensure(dashboard)
    if not state then return end
    bindVehicle(state, vehicle)
    -- setVehicle runs when taking the driver's seat; sample synchronously instead
    -- of waiting for the previous vehicle's polling deadline or the next frame.
    Indicator.update(dashboard, true)
end

local function tooltip(status, settings)
    if status == "error" then return getText("Tooltip_LTPMS_Malfunction") end
    if status == "warn" then
        return getText("Tooltip_LTPMS_Pressure", math.floor(settings.warningThreshold * 100))
    end
    if status == "on" then
        return getText("Tooltip_LTPMS_Pressure", math.floor(settings.alertThreshold * 100))
    end
    return getText("Tooltip_LTPMS_TPMS")
end

local function sampleState(state, vehicle, powered, now, forceRead)
    if not forceRead and now < state.nextSample then return end
    local settings = Core.getSettings()
    local settingsChanged = state.settings ~= settings
    state.settings = settings
    state.eligible = Core.isEligible(vehicle, settings)
    local status = "off"
    if state.eligible and (powered or forceRead) then
        local partCount = vehicle:getPartCount()
        local script = vehicle:getScriptName()
        if not state.tires or state.partCount ~= partCount or state.script ~= script then
            state.tires = Core.collectTires(vehicle)
            state.partCount, state.script = partCount, script
        end
        status = Core.sample(state.tires, settings)
    end
    if not powered then status = "off" end
    if not state.eligible then
        -- The vehicle stopped matching the ubiquity/whitelist filter: drop any
        -- lit state immediately instead of waiting for the next sample.
        resetLight(state)
        state.nextSample = now + SAMPLE_MS
        return
    end
    if state.status ~= status or settingsChanged then
        -- Keep the blink phase while editing options if the status stays
        -- unchanged. A different warning state starts a fresh blink cycle.
        if state.status ~= status then
            state.blinkStart = (status == "warn" or status == "error") and now or nil
        end
        state.status, state.light.state = status, status
        state.light.mouseovertext = tooltip(status, settings)
    end
    state.nextSample = now + SAMPLE_MS
end

local function render(state, now, powered)
    local status = powered and state.status or "off"
    local lit = status ~= "off"
    if status == "warn" or status == "error" then
        lit = math.floor((now - (state.blinkStart or now)) / BLINK_MS) % 2 == 0
    end
    if state.realistic then
        state.light.backgroundColor = status == "error" and colors.error or colors.realistic
        setVisible(state.panel, false)
        setVisible(state.light, lit)
    else
        state.light.backgroundColor = lit and (status == "error" and colors.error or colors.on) or colors.off
        setVisible(state.panel, true)
        setVisible(state.light, true)
    end
end

function Indicator.update(dashboard, forceRead)
    local state = Indicator.ensure(dashboard)
    if not state then return end
    local vehicle = dashboard.vehicle
    if state.vehicle ~= vehicle then
        bindVehicle(state, vehicle)
        forceRead = true
    end
    if not vehicle then
        hide(state)
        state.nextSample = 0
        return
    end
    local now = getTimestampMs()
    if state.lastTime and now < state.lastTime then
        state.nextSample, state.blinkStart = 0, now
    end
    state.lastTime = now
    local powered = (vehicle:isEngineRunning() or vehicle:isKeysInIgnition())
        and vehicle:getBatteryCharge() > 0
    if powered ~= state.powered then
        state.powered, state.nextSample = powered, 0
    end
    sampleState(state, vehicle, powered, now, forceRead)
    -- Keep observing ignition and warning transitions while the HUD is hidden.
    if ISUIHandler and ISUIHandler.allUIVisible == false then
        hide(state)
        return
    end
    if not state.eligible or not Layout.update(dashboard, state) then
        hide(state)
        return
    end
    render(state, now, powered)
end

return Indicator
