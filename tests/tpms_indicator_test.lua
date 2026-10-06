-- Run from the repository root with Lua 5.1 (newproxy supplies real userdata).
-- The Fengari runner can supply the same newproxy(true) primitive via its C API.
package.path = "Contents/mods/TPMS_CommunityEdition/common/media/lua/client/?.lua;" .. package.path
package.preload["ISUI/ISImage"] = function() return true end

local function texture(width, height)
    local value = newproxy(true)
    getmetatable(value).__index = {
        getWidthOrig = function() return width end,
        getHeightOrig = function() return height end,
    }
    assert(type(value) == "userdata", "Texture regression requires userdata, not a table")
    return value
end

local icon, realisticIcon = texture(24, 24), texture(17, 17)
local textures = {
    ["media/ui/tpms.png"] = icon,
    ["media/ui/tpmsRD.png"] = realisticIcon,
    ["media/ui/tpms_background.png"] = texture(25, 25),
}
function getTexture(path) return textures[path] end
function getText(key) return key end
local now = 0
function getTimestampMs() return now end
SandboxVars = { LTPMS = {} }
ISUIHandler = { allUIVisible = true }

ISImage = {}
function ISImage:new(x, y, width, height, tex)
    local image = { x=x, y=y, width=width, height=height, texture=tex, visible=true }
    function image:initialise() end
    function image:instantiate() end
    function image:getIsVisible() return self.visible end
    function image:setVisible(visible) self.visible = visible end
    function image:setX(value) self.x = value end
    function image:setY(value) self.y = value end
    function image:setWidth(value) self.width = value end
    function image:setHeight(value) self.height = value end
    return image
end

local scale = 1
local function round(value) return math.floor(value + 0.5) end
local anchors = {
    standard = { stop={231,139} }, heavy = { stop={169,137} },
    sport = { stop={120,162}, door={411,162} },
}
YourDash = { MODOPT_ID = "RealisticDash", GetScale = function() return scale end }
function YourDash.GetLayoutPoint(dashboard, section, point)
    local anchor = anchors[dashboard.__YourDashFamily][point]
    if anchor then return round(anchor[1] * scale), round(anchor[2] * scale) end
end

local function vehicle(pressure)
    local tires = {}
    for index = 1, 4 do
        local tire = { pressure=pressure, capacity=100, condition=100, item={}, wheelIndex=index-1 }
        function tire:getCategory() return "tire" end
        function tire:getWheelIndex() return self.wheelIndex end
        function tire:getInventoryItem() return self.item end
        function tire:getCondition() return self.condition end
        function tire:getContainerCapacity() return self.capacity end
        function tire:getContainerContentAmount() return self.pressure end
        tires[index] = tire
    end
    local car = { tires=tires, tire=tires[1], keys=true, running=false, battery=1, script="Base.CarLuxury" }
    function car:getScriptName() return self.script end
    function car:getPartCount() return #self.tires end
    function car:getPartByIndex(index) return self.tires[index+1] end
    function car:isEngineRunning() return self.running end
    function car:isKeysInIgnition() return self.keys end
    function car:getBatteryCharge() return self.battery end
    return car
end

local function dashboard(car, family, accent)
    local background = {}
    function background:getX() return 3 end
    function background:getY() return 2 end
    function background:getWidth() return round(758 * scale) end
    function background:getHeight() return round(179 * scale) end
    local dash = { vehicle=car, backgroundTex=background,
        __YourDashFamily=family or "sport", __YourDashAccent=accent or "lux" }
    function dash:addChild() end
    return dash
end

local Indicator = require "TPMS/Indicator"
local Core = require "TPMS/Core"
local function assertColor(light, r, g, b)
    local color = light.backgroundColor
    assert(color.r == r and color.g == g and color.b == b and color.a == 1,
        "unexpected warning color or opacity")
end
local passed = 0
local function test(name, callback)
    now, scale = 0, 1
    ISUIHandler.allUIVisible = true
    SandboxVars.LTPMS = {}
    callback()
    passed = passed + 1
    print("PASS " .. name)
end

test("key already inserted, engine stopped, low pressure: visible immediately", function()
    local dash = dashboard(vehicle(60))
    Indicator.setVehicle(dash, dash.vehicle)
    local state = dash.__lawlyTPMS
    assert(state.status == "on")
    assert(state.light.visible, "low-pressure lamp must be visible with Java-style texture userdata")
    assert(state.light.texture == icon and not state.panel.visible)
    assert(state.light.width == 17 and state.light.height == 17, "keep RD dimensions")
    assertColor(state.light, 1, 1, 0)
end)

test("critical pressure blinks amber; missing tire stays red with the engine stopped", function()
    local dash = dashboard(vehicle(40))
    Indicator.setVehicle(dash, dash.vehicle)
    local state = dash.__lawlyTPMS
    assert(state.status == "warn" and state.light.visible)
    assertColor(state.light, 1, 0.62, 0)
    now = 250; Indicator.update(dash)
    assert(not state.light.visible)
    now = 500; Indicator.update(dash)
    assert(state.light.visible)
    dash.vehicle.tire.item = nil
    now = 1000; Indicator.update(dash)
    assert(state.status == "error" and state.light.visible)
    assertColor(state.light, 1, 0, 0)
    now = 1250; Indicator.update(dash)
    assert(state.light.visible, "red faults must not blink")
    assertColor(state.light, 1, 0, 0)
end)

test("inclusive 75% and 50% thresholds apply to each of the four tires", function()
    local cases = {{100,"off"}, {75.01,"off"}, {75,"on"}, {50.01,"on"}, {50,"warn"}, {0,"warn"}}
    for index = 1, 4 do
        for _, case in ipairs(cases) do
            local car = vehicle(100)
            car.tires[index].pressure = case[1]
            local dash = dashboard(car)
            Indicator.setVehicle(dash, car)
            assert(dash.__lawlyTPMS.status == case[2], "wrong threshold for tire " .. index)
            assert(dash.TPMSLight.visible == (case[2] ~= "off"))
            if case[2] == "on" then assertColor(dash.TPMSLight, 1, 1, 0) end
            if case[2] == "warn" then assertColor(dash.TPMSLight, 1, 0.62, 0) end
        end
    end
end)

test("pressure is a ratio of nominal capacity, not a fixed absolute amount", function()
    local car = vehicle(100)
    car.tires[3].capacity, car.tires[3].pressure = 40, 30
    local dash = dashboard(car)
    Indicator.setVehicle(dash, car)
    assert(dash.__lawlyTPMS.status == "on")
    car.tires[3].pressure = 20; now = 1000; Indicator.update(dash)
    assert(dash.__lawlyTPMS.status == "warn")
end)

test("missing tire on any wheel takes priority over critical pressure", function()
    for index = 1, 4 do
        local car = vehicle(40)
        car.tires[index].item = nil
        local dash = dashboard(car)
        Indicator.setVehicle(dash, car)
        assert(dash.__lawlyTPMS.status == "error")
        assertColor(dash.TPMSLight, 1, 0, 0)
        now = now + 250; Indicator.update(dash)
        assert(dash.TPMSLight.visible)
    end
end)

test("invalid or failed pressure readings display steady red and recover", function()
    local faults = {
        function(t) t.pressure = nil end,
        function(t) t.pressure = "invalid" end,
        function(t) t.pressure = -1 end,
        function(t) t.pressure = 0/0 end,
        function(t) t.pressure = math.huge end,
        function(t) t.capacity = 0 end,
        function(t) t.capacity = nil end,
        function(t) t.capacity = math.huge end,
        function(t) t.condition = 0 end,
        function(t) t.getContainerContentAmount = function() error("sensor read failed") end end,
        function(t) t.getContainerContentAmount = nil end,
    }
    for _, applyFault in ipairs(faults) do
        local car = vehicle(100)
        local tire = car.tires[4]
        applyFault(tire)
        local dash = dashboard(car)
        Indicator.setVehicle(dash, car)
        assert(dash.__lawlyTPMS.status == "error" and dash.TPMSLight.visible)
        now = now + 250; Indicator.update(dash)
        assert(dash.TPMSLight.visible)
        assertColor(dash.TPMSLight, 1, 0, 0)
        tire.pressure, tire.capacity, tire.condition = 100, 100, 100
        tire.getContainerContentAmount = function(self) return self.pressure end
        now = now + 1000; Indicator.update(dash)
        assert(dash.__lawlyTPMS.status == "off" and not dash.TPMSLight.visible)
    end
end)

test("spare tires are excluded while all four road wheels are monitored", function()
    local car = vehicle(100)
    local spare = vehicle(0).tire
    spare.wheelIndex, spare.item = -1, nil
    car.tires[5] = spare
    local tires = Core.collectTires(car)
    assert(#tires == 4 and Core.sample(tires) == "off")
end)

test("key and battery transitions bypass the sampling deadline", function()
    local dash = dashboard(vehicle(60))
    Indicator.setVehicle(dash, dash.vehicle)
    local state = dash.__lawlyTPMS
    dash.vehicle.keys = false; now = 10; Indicator.update(dash)
    assert(not state.light.visible)
    dash.vehicle.keys = true; now = 20; Indicator.update(dash)
    assert(state.light.visible)
    dash.vehicle.battery = 0; now = 30; Indicator.update(dash)
    assert(not state.light.visible)
    dash.vehicle.battery = 1; now = 40; Indicator.update(dash)
    assert(state.light.visible)
    dash.vehicle.keys, dash.vehicle.running = false, true
    now = 50; Indicator.update(dash)
    assert(state.light.visible)
end)

test("healthy tires, hidden UI, exit and re-entry", function()
    local dash = dashboard(vehicle(100))
    Indicator.setVehicle(dash, dash.vehicle)
    assert(not dash.__lawlyTPMS.light.visible)
    dash.vehicle.tire.pressure = 60; now = 1000; Indicator.update(dash)
    assert(dash.__lawlyTPMS.light.visible)
    ISUIHandler.allUIVisible = false; Indicator.update(dash)
    assert(not dash.__lawlyTPMS.light.visible)
    ISUIHandler.allUIVisible = true; Indicator.update(dash)
    assert(dash.__lawlyTPMS.light.visible)
    dash.vehicle = nil; Indicator.setVehicle(dash, nil)
    assert(not dash.__lawlyTPMS.light.visible)
    dash.vehicle = vehicle(60); Indicator.setVehicle(dash, dash.vehicle)
    assert(dash.__lawlyTPMS.light.visible)
end)

test("invalid texture falls back, invalid fallback hides the light", function()
    local dash = dashboard(vehicle(60))
    Indicator.setVehicle(dash, dash.vehicle)
    local state = dash.__lawlyTPMS
    local original = state.textures.realistic
    for _, invalid in ipairs({false, {}, texture(0,17), 42}) do
        state.textures.realistic = invalid
        Indicator.invalidateLayout(dash); Indicator.update(dash)
        assert(state.light.visible and state.light.texture == icon)
    end
    state.textures.icon = texture(0,0)
    Indicator.invalidateLayout(dash); Indicator.update(dash)
    assert(not state.light.visible)
    state.textures.icon, state.textures.realistic = icon, original
end)

test("luxury position scales and changing accent invalidates layout", function()
    local dash = dashboard(vehicle(60))
    Indicator.setVehicle(dash, dash.vehicle)
    local state = dash.__lawlyTPMS
    for _, size in ipairs({0.75, 1, 1.4, 2}) do
        scale = size; Indicator.update(dash)
        assert(state.light.x == 3 + round(120*size) + round(-26*size))
        assert(state.light.y + state.light.height <= 2 + round(179*size))
        assert(state.light.x + state.light.width < 3 + round(120*size), "must not overlap STOP")
    end
    scale = 1; dash.__YourDashAccent = "sport"; Indicator.update(dash)
    assert(state.light.x == 388 and state.anchorFamily == "sport")
    dash.__YourDashAccent = "lux"; Indicator.update(dash)
    assert(state.light.x == 97 and state.anchorFamily == "luxury")
    dash.__YourDashAccent = nil; Indicator.update(dash)
    assert(state.light.x == 97)
end)

test("standard, heavy and vanilla positions remain unchanged", function()
    for _, case in ipairs({{"standard",236,118}, {"heavy",204,139}}) do
        local dash = dashboard(vehicle(60), case[1], "base")
        Indicator.setVehicle(dash, dash.vehicle)
        assert(dash.TPMSLight.x == case[2] and dash.TPMSLight.y == case[3])
    end
    local dash = dashboard(vehicle(60))
    dash.__YourDashFamily, dash.__YourDashAccent = nil, nil
    Indicator.setVehicle(dash, dash.vehicle)
    assert(dash.TPMSLight.visible and dash.TPMSBG.visible)
    assert(dash.TPMSLight.x == 208 and dash.TPMSLight.y == 58)
    assert(dash.TPMSLight.texture == icon)
    local passenger = { Type="YourDashPassengerDashboard" }
    assert(Indicator.ensure(passenger) == nil)
end)

test("yellow, blinking amber and steady red reuse identical geometry on every dashboard", function()
    local profiles = {{"standard","base"}, {"heavy","base"}, {"sport","sport"}, {"sport","lux"}, {"vanilla"}}
    for _, profile in ipairs(profiles) do
        for _, size in ipairs({0.75, 1, 1.4, 2}) do
            scale = size
            local car = vehicle(100)
            local dash = dashboard(car, profile[1], profile[2])
            local vanilla = profile[1] == "vanilla"
            if vanilla then dash.__YourDashFamily, dash.__YourDashAccent = nil, nil end
            Indicator.setVehicle(dash, car)
            local light = dash.TPMSLight
            local geometry = {light.x, light.y, light.width, light.height}
            local function unchanged()
                assert(light.x == geometry[1] and light.y == geometry[2])
                assert(light.width == geometry[3] and light.height == geometry[4])
            end
            car.tires[4].pressure = 75; now = now + 1000; Indicator.update(dash)
            assertColor(light, 1, 1, 0); unchanged()
            now = now + 250; Indicator.update(dash)
            assert(light.visible); assertColor(light, 1, 1, 0); unchanged()
            car.tires[4].pressure = 50; now = now + 1000; Indicator.update(dash)
            assertColor(light, 1, 0.62, 0); unchanged()
            now = now + 250; Indicator.update(dash)
            if vanilla then
                assert(light.backgroundColor.a == 0.4, "vanilla blink uses the unlit icon")
            else
                assert(not light.visible)
            end
            unchanged()
            car.tires[4].item = nil; now = now + 1000; Indicator.update(dash)
            assertColor(light, 1, 0, 0); unchanged()
            for frame = 1, 5 do
                now = now + 250; Indicator.update(dash)
                assert(light.visible); assertColor(light, 1, 0, 0); unchanged()
            end
            car.tires[4].item, car.tires[4].pressure = {}, 100
            now = now + 1000; Indicator.update(dash)
            assert(dash.__lawlyTPMS.status == "off"); unchanged()
        end
    end
end)

print("Passed " .. passed .. " TPMS regression scenarios")
