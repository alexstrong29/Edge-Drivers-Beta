-- Moes Star Ring Smart Knob Thermostat Edge Driver
-- Wall-mounted dial thermostat controller
-- Supports _TZE204_lpedvtvr

local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"

local ThermostatMode = capabilities.thermostatMode
local ThermostatHeatingSetpoint = capabilities.thermostatHeatingSetpoint
local TemperatureMeasurement = capabilities.temperatureMeasurement
local Battery = capabilities.battery

-- Tuya cluster constants
local TUYA_CLUSTER = 0xEF00
local TUYA_SET_DATA = 0x00
local TUYA_REPORT_DATA = 0x01
local TUYA_SET_TIME = 0x24

-- Tuya DP (Data Point) constants for Moes Star Ring thermostat
-- Based on working Home Assistant ZHA quirk
local DP_SYSTEM_MODE = 0x01  -- System on/off (boolean)
local DP_PRESET_MODE = 0x02  -- Preset mode (enum: 0=manual, 1=temp_manual, 2=program, 3=eco)
local DP_TEMPERATURE = 0x10  -- Current temperature (value, divide by 10 for °C)
local DP_MIN_TEMP = 0x12     -- Minimum temperature limit (18 decimal)
local DP_FACTORY_RESET = 0x1C -- Factory reset (28 decimal)
local DP_SENSOR_MODE = 0x20  -- Sensor selection: 0=Air, 1=Both, 2=Floor (32 decimal)
local DP_MAX_TEMP = 0x22     -- Maximum temperature limit (34 decimal)
local DP_CHILD_LOCK = 0x27   -- Child lock (39 decimal)
local DP_VALVE_STATE = 0x2F  -- Heating state (47 decimal)
local DP_DISPLAY_BRIGHTNESS = 0x30 -- Display brightness 1-100 (48 decimal)
local DP_SETPOINT = 0x32     -- Target setpoint (50 decimal)
local DP_TEMP_CALIBRATION = 0x65 -- Temperature calibration -10 to 10 (101 decimal)
local DP_EXTERNAL_TEMP = 0x6D -- External temperature input (109 decimal)
local DP_DEADZONE_TEMP = 0x6E -- Deadzone temperature 0-5 (110 decimal)
local DP_MAX_TEMP_LIMIT = 0x6F -- Max temperature limit 1-45 (111 decimal)
local DP_MIN_TEMP_LIMIT = 0x70 -- Min temperature limit 1-30 (112 decimal)
local DP_ECO_TEMP = 0x71     -- Eco temperature 5-30 (113 decimal)
local DP_SCREEN_TIME = 0x72  -- Screen time set (114 decimal)
local DP_RGB_BACKLIGHT = 0x73 -- RGB backlight (115 decimal)
local DP_BATTERY = 0x23      -- Battery level

local PRESET_MANUAL = 0
local PRESET_TEMP_MANUAL = 1
local PRESET_PROGRAM = 2
local PRESET_ECO = 3

local SENSOR_AIR = 0
local SENSOR_BOTH = 1
local SENSOR_FLOOR = 2

local SCREEN_OFF = 0
local SCREEN_SHORT = 1
local SCREEN_MEDIUM = 2
local SCREEN_LONG = 3

-- Helper functions
local function create_tuya_command(dp, data_type, data)
  local cmd_body = data_types.CharString("", false)
  cmd_body.value = string.char(dp) .. 
                   string.char(data_type) .. 
                   string.char(#data >> 8) .. 
                   string.char(#data & 0xFF) .. 
                   data
  return cmd_body
end

local function convert_temp_to_setpoint(temp_c)
  -- Convert temperature to format expected by thermostat (0.1°C units)
  return math.floor(temp_c * 10)
end

local function convert_setpoint_to_temp(setpoint)
  -- Convert from thermostat format (0.1°C units) to Celsius
  return setpoint / 10
end

-- Capability handlers
local function handle_thermostat_mode(driver, device, command)
  local mode = command.args.mode
  
  device.log.info("Setting thermostat mode to: " .. mode)
  
  if mode == "off" then
    -- Turn system off using DP 1
    local data = string.char(0)  -- false = off
    local cmd_body = create_tuya_command(DP_SYSTEM_MODE, 0x01, data) -- 0x01 = boolean type
    device:send(zcl_clusters.basic_id:build_cluster_specific_command(
      device,
      TUYA_CLUSTER,
      TUYA_SET_DATA,
      cmd_body.value
    ))
    
  elseif mode == "heat" then
    -- Turn system on (DP 1) and set to manual mode (DP 2)
    local data_on = string.char(1)  -- true = on
    local cmd_body_on = create_tuya_command(DP_SYSTEM_MODE, 0x01, data_on)
    device:send(zcl_clusters.basic_id:build_cluster_specific_command(
      device,
      TUYA_CLUSTER,
      TUYA_SET_DATA,
      cmd_body_on.value
    ))
    
    -- Set preset to manual
    local data_preset = string.char(PRESET_MANUAL)
    local cmd_body_preset = create_tuya_command(DP_PRESET_MODE, 0x04, data_preset) -- 0x04 = enum type
    device:send(zcl_clusters.basic_id:build_cluster_specific_command(
      device,
      TUYA_CLUSTER,
      TUYA_SET_DATA,
      cmd_body_preset.value
    ))
    
  elseif mode == "auto" then
    -- Turn system on and set to program mode
    local data_on = string.char(1)
    local cmd_body_on = create_tuya_command(DP_SYSTEM_MODE, 0x01, data_on)
    device:send(zcl_clusters.basic_id:build_cluster_specific_command(
      device,
      TUYA_CLUSTER,
      TUYA_SET_DATA,
      cmd_body_on.value
    ))
    
    -- Set preset to program
    local data_preset = string.char(PRESET_PROGRAM)
    local cmd_body_preset = create_tuya_command(DP_PRESET_MODE, 0x04, data_preset)
    device:send(zcl_clusters.basic_id:build_cluster_specific_command(
      device,
      TUYA_CLUSTER,
      TUYA_SET_DATA,
      cmd_body_preset.value
    ))
  else
    device.log.warn("Unsupported mode: " .. mode)
    return
  end
end

local function handle_heating_setpoint(driver, device, command)
  local setpoint_c = command.args.setpoint
  -- Convert to 0.1°C units (e.g., 20.5°C -> 205)
  local setpoint_value = convert_temp_to_setpoint(setpoint_c)
  
  device.log.info(string.format("Setting temperature to %.1f°C (raw value: %d)", setpoint_c, setpoint_value))
  
  -- Build data payload (4 bytes, big-endian)
  local data = string.char((setpoint_value >> 24) & 0xFF) ..
               string.char((setpoint_value >> 16) & 0xFF) ..
               string.char((setpoint_value >> 8) & 0xFF) ..
               string.char(setpoint_value & 0xFF)
  
  local cmd_body = create_tuya_command(DP_SETPOINT, 0x02, data) -- 0x02 = value type
  
  -- Send using cluster-specific command
  device:send(zcl_clusters.basic_id:build_cluster_specific_command(
    device,
    TUYA_CLUSTER,
    TUYA_SET_DATA,
    cmd_body.value
  ))
end

-- Tuya cluster handler
local function tuya_handler(driver, device, zb_rx)
  device.log.info("=== TUYA HANDLER CALLED ===")
  
  local data = zb_rx.body.zcl_body.body_bytes
  
  device.log.info(string.format("Received data length: %d bytes", #data))
  
  if #data < 4 then
    device.log.warn("Data too short, need at least 4 bytes")
    return
  end
  
  local dp = data:byte(1)
  local data_type = data:byte(2)
  local data_len = (data:byte(3) << 8) | data:byte(4)
  
  if #data < 4 + data_len then
    return
  end
  
  local dp_data = data:sub(5, 4 + data_len)
  
  -- Log all received data points for debugging
  device.log.info(string.format("Received Tuya DP: %d, Type: %d, Len: %d", dp, data_type, data_len))
  
  if dp == DP_TEMPERATURE then
    -- Temperature in 0.1°C units
    local temp_raw = (dp_data:byte(1) << 24) | (dp_data:byte(2) << 16) | 
                     (dp_data:byte(3) << 8) | dp_data:byte(4)
    local temp_c = temp_raw / 10
    device.log.info(string.format("DP16 Current temperature: %.1f°C (raw: %d)", temp_c, temp_raw))
    device:emit_event(TemperatureMeasurement.temperature({value = temp_c, unit = "C"}))
    -- Also show raw value in battery for debugging
    device:emit_event(Battery.battery(math.min(100, math.max(0, temp_raw % 101))))
    
  elseif dp == DP_SETPOINT then
    -- Setpoint comes in 0.1°C units (e.g., 200 for 20.0°C)
    local setpoint_raw = (dp_data:byte(1) << 24) | (dp_data:byte(2) << 16) | 
                         (dp_data:byte(3) << 8) | dp_data:byte(4)
    local setpoint_c = convert_setpoint_to_temp(setpoint_raw)
    device.log.info(string.format("DP50 Target setpoint: %.1f°C (raw: %d)", setpoint_c, setpoint_raw))
    device:emit_event(ThermostatHeatingSetpoint.heatingSetpoint({value = setpoint_c, unit = "C"}))
    
  elseif dp == DP_SYSTEM_MODE then
    -- DP 1: System on/off (boolean)
    local is_on = dp_data:byte(1) == 1
    if is_on then
      -- When on, check preset mode to determine if heat or auto
      -- For now just report heat, preset will refine this
      device:emit_event(ThermostatMode.thermostatMode("heat"))
    else
      device:emit_event(ThermostatMode.thermostatMode("off"))
    end
    
  elseif dp == DP_PRESET_MODE then
    -- DP 2: Preset mode determines auto vs manual
    local preset = dp_data:byte(1)
    if preset == PRESET_MANUAL or preset == PRESET_TEMP_MANUAL then
      device:emit_event(ThermostatMode.thermostatMode("heat"))
    elseif preset == PRESET_PROGRAM then
      device:emit_event(ThermostatMode.thermostatMode("auto"))
    elseif preset == PRESET_ECO then
      device:emit_event(ThermostatMode.thermostatMode("heat"))  -- eco is still manual heating
    end
    
  elseif dp == DP_BATTERY then
    local battery_level = dp_data:byte(1)
    device.log.info(string.format("Battery: %d%%", battery_level))
    -- Don't emit battery here since we're using it for debug display
    -- device:emit_event(Battery.battery(battery_level))
    
  elseif dp == DP_CHILD_LOCK then
    local locked = dp_data:byte(1) == 1
    device.log.info(string.format("Child lock: %s", locked and "ON" or "OFF"))
    device:set_field("child_lock", locked, {persist = true})
    
  elseif dp == DP_VALVE_STATE then
    local heating = dp_data:byte(1) == 0  -- Note: inverted in HA quirk (Idle if x else Heat)
    device.log.info(string.format("Heating state: %s", heating and "heating" or "idle"))
    device:set_field("heating_state", heating, {persist = true})
    
  elseif dp == DP_DISPLAY_BRIGHTNESS then
    local brightness = dp_data:byte(1)
    device.log.info(string.format("Display brightness: %d", brightness))
    device:set_field("display_brightness", brightness, {persist = true})
    
  elseif dp == DP_MIN_TEMP then
    local min_temp_raw = (dp_data:byte(1) << 24) | (dp_data:byte(2) << 16) | 
                         (dp_data:byte(3) << 8) | dp_data:byte(4)
    local min_temp = min_temp_raw / 10
    device.log.info(string.format("Min temperature: %.1f°C", min_temp))
    device:set_field("min_temperature", min_temp, {persist = true})
    
  elseif dp == DP_MAX_TEMP then
    local max_temp_raw = (dp_data:byte(1) << 24) | (dp_data:byte(2) << 16) | 
                         (dp_data:byte(3) << 8) | dp_data:byte(4)
    local max_temp = max_temp_raw / 10
    device.log.info(string.format("Max temperature: %.1f°C", max_temp))
    device:set_field("max_temperature", max_temp, {persist = true})
    
  elseif dp == DP_ECO_TEMP then
    local eco_temp_raw = (dp_data:byte(1) << 24) | (dp_data:byte(2) << 16) | 
                         (dp_data:byte(3) << 8) | dp_data:byte(4)
    local eco_temp = eco_temp_raw / 10
    device.log.info(string.format("Eco temperature: %.1f°C", eco_temp))
    device:set_field("eco_temperature", eco_temp, {persist = true})
    
  elseif dp == DP_TEMP_CALIBRATION then
    local cal_raw = (dp_data:byte(1) << 24) | (dp_data:byte(2) << 16) | 
                    (dp_data:byte(3) << 8) | dp_data:byte(4)
    -- Handle as signed integer
    if cal_raw > 0x7FFFFFFF then
      cal_raw = cal_raw - 0x100000000
    end
    device.log.info(string.format("Temperature calibration: %d", cal_raw))
    device:set_field("temp_calibration", cal_raw, {persist = true})
    
  elseif dp == DP_SENSOR_MODE then
    local sensor_mode = dp_data:byte(1)
    local mode_name = (sensor_mode == SENSOR_AIR) and "Air" or 
                      (sensor_mode == SENSOR_BOTH) and "Both" or
                      (sensor_mode == SENSOR_FLOOR) and "Floor" or "Unknown"
    device.log.info(string.format("Sensor mode: %s (%d)", mode_name, sensor_mode))
    device:set_field("sensor_mode", sensor_mode, {persist = true})
    
  elseif dp == DP_SCREEN_TIME then
    local screen_time = dp_data:byte(1)
    local time_name = (screen_time == SCREEN_OFF) and "Off" or 
                      (screen_time == SCREEN_SHORT) and "Short" or
                      (screen_time == SCREEN_MEDIUM) and "Medium" or
                      (screen_time == SCREEN_LONG) and "Long" or "Unknown"
    device.log.info(string.format("Screen time: %s (%d)", time_name, screen_time))
    device:set_field("screen_time", screen_time, {persist = true})
    
  elseif dp == DP_RGB_BACKLIGHT then
    local backlight = dp_data:byte(1) == 1
    device.log.info(string.format("RGB backlight: %s", backlight and "ON" or "OFF"))
    device:set_field("rgb_backlight", backlight, {persist = true})
    
  elseif dp == DP_DEADZONE_TEMP then
    local deadzone = dp_data:byte(1)
    device.log.info(string.format("Deadzone temperature: %d°C", deadzone))
    device:set_field("deadzone_temp", deadzone, {persist = true})
    
  elseif dp == DP_MIN_TEMP_LIMIT then
    local min_limit_raw = (dp_data:byte(1) << 24) | (dp_data:byte(2) << 16) | 
                          (dp_data:byte(3) << 8) | dp_data:byte(4)
    local min_limit = min_limit_raw / 10
    device.log.info(string.format("Min temperature limit: %.1f°C", min_limit))
    device:set_field("min_temp_limit", min_limit, {persist = true})
    
  elseif dp == DP_MAX_TEMP_LIMIT then
    local max_limit_raw = (dp_data:byte(1) << 24) | (dp_data:byte(2) << 16) | 
                          (dp_data:byte(3) << 8) | dp_data:byte(4)
    local max_limit = max_limit_raw / 10
    device.log.info(string.format("Max temperature limit: %.1f°C", max_limit))
    device:set_field("max_temp_limit", max_limit, {persist = true})
    
  elseif dp == DP_EXTERNAL_TEMP then
    local ext_temp_raw = (dp_data:byte(1) << 24) | (dp_data:byte(2) << 16) | 
                         (dp_data:byte(3) << 8) | dp_data:byte(4)
    local ext_temp = ext_temp_raw / 10
    device.log.info(string.format("External temperature: %.1f°C", ext_temp))
    device:set_field("external_temp", ext_temp, {persist = true})
    
  else
    device.log.debug(string.format("Unhandled DP: %d (type: %d, len: %d)", dp, data_type, data_len))
  end
end

-- Device lifecycle handlers
local function device_init(driver, device)
  device:set_field("tuya_initialized", false)
end

local function device_added(driver, device)
  -- Set default capabilities
  device:emit_event(ThermostatMode.thermostatMode("heat"))
  device:emit_event(ThermostatHeatingSetpoint.heatingSetpoint({value = 20, unit = "C"}))
  device:emit_event(TemperatureMeasurement.temperature({value = 20, unit = "C"}))
  device:emit_event(Battery.battery(100))
  
  -- Set supported modes
  device:emit_event(ThermostatMode.supportedThermostatModes({"off", "heat", "auto"}))
  
  -- Set heating setpoint range (5°C to 35°C)
  device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpointRange({value = {minimum = 5, maximum = 35}, unit = "C"}))
  
  -- Bind to Tuya cluster to receive updates
  device:send(zcl_clusters.basic_id:build_bind_request(device, TUYA_CLUSTER))
  device.log.info("Binding to Tuya cluster for automatic updates")
  
  -- Set up periodic polling for history updates (every 5 minutes)
  device.thread:call_on_schedule(
    300,  -- 300 seconds = 5 minutes
    function()
      device.log.debug("Periodic refresh for history")
      device:refresh()
    end,
    "periodic_refresh"
  )
  
  -- Trigger a refresh to get actual values from device
  device:refresh()
end

local function device_info_changed(driver, device, event, args)
  -- Refresh device state on info change
  if not device:get_field("tuya_initialized") then
    device:set_field("tuya_initialized", true)
    device:refresh()
  end
  
  -- Handle preference changes
  if args.old_st_store.preferences then
    local prefs = device.preferences
    local old_prefs = args.old_st_store.preferences
    
    -- Display brightness changed
    if prefs.displayBrightness ~= old_prefs.displayBrightness then
      local brightness = prefs.displayBrightness or 50
      local data = string.char(brightness)
      local cmd_body = create_tuya_command(DP_DISPLAY_BRIGHTNESS, 0x02, string.char(0x00) .. string.char(0x00) .. string.char(0x00) .. data)
      device:send(zcl_clusters.basic_id:build_cluster_specific_command(device, TUYA_CLUSTER, TUYA_SET_DATA, cmd_body.value))
      device.log.info("Set display brightness to " .. brightness)
    end
    
    -- Child lock changed
    if prefs.childLock ~= old_prefs.childLock then
      local locked = prefs.childLock or false
      local data = string.char(locked and 1 or 0)
      local cmd_body = create_tuya_command(DP_CHILD_LOCK, 0x01, data)
      device:send(zcl_clusters.basic_id:build_cluster_specific_command(device, TUYA_CLUSTER, TUYA_SET_DATA, cmd_body.value))
      device.log.info("Set child lock to " .. (locked and "ON" or "OFF"))
    end
    
    -- Sensor mode changed
    if prefs.sensorMode ~= old_prefs.sensorMode then
      local mode = tonumber(prefs.sensorMode) or 0
      local data = string.char(mode)
      local cmd_body = create_tuya_command(DP_SENSOR_MODE, 0x04, data)
      device:send(zcl_clusters.basic_id:build_cluster_specific_command(device, TUYA_CLUSTER, TUYA_SET_DATA, cmd_body.value))
      device.log.info("Set sensor mode to " .. mode)
    end
    
    -- Screen time changed
    if prefs.screenTime ~= old_prefs.screenTime then
      local time = tonumber(prefs.screenTime) or 2
      local data = string.char(time)
      local cmd_body = create_tuya_command(DP_SCREEN_TIME, 0x04, data)
      device:send(zcl_clusters.basic_id:build_cluster_specific_command(device, TUYA_CLUSTER, TUYA_SET_DATA, cmd_body.value))
      device.log.info("Set screen time to " .. time)
    end
    
    -- RGB backlight changed
    if prefs.rgbBacklight ~= old_prefs.rgbBacklight then
      local enabled = prefs.rgbBacklight
      if enabled == nil then enabled = true end
      local data = string.char(enabled and 1 or 0)
      local cmd_body = create_tuya_command(DP_RGB_BACKLIGHT, 0x01, data)
      device:send(zcl_clusters.basic_id:build_cluster_specific_command(device, TUYA_CLUSTER, TUYA_SET_DATA, cmd_body.value))
      device.log.info("Set RGB backlight to " .. (enabled and "ON" or "OFF"))
    end
    
    -- Temperature calibration changed
    if prefs.tempCalibration ~= old_prefs.tempCalibration then
      local cal = prefs.tempCalibration or 0
      local data = string.char((cal >> 24) & 0xFF) .. string.char((cal >> 16) & 0xFF) .. 
                   string.char((cal >> 8) & 0xFF) .. string.char(cal & 0xFF)
      local cmd_body = create_tuya_command(DP_TEMP_CALIBRATION, 0x02, data)
      device:send(zcl_clusters.basic_id:build_cluster_specific_command(device, TUYA_CLUSTER, TUYA_SET_DATA, cmd_body.value))
      device.log.info("Set temperature calibration to " .. cal)
    end
    
    -- Deadzone temperature changed
    if prefs.deadzoneTemp ~= old_prefs.deadzoneTemp then
      local deadzone = prefs.deadzoneTemp or 1
      local data = string.char(deadzone)
      local cmd_body = create_tuya_command(DP_DEADZONE_TEMP, 0x02, string.char(0x00) .. string.char(0x00) .. string.char(0x00) .. data)
      device:send(zcl_clusters.basic_id:build_cluster_specific_command(device, TUYA_CLUSTER, TUYA_SET_DATA, cmd_body.value))
      device.log.info("Set deadzone temperature to " .. deadzone)
    end
    
    -- Eco temperature changed
    if prefs.ecoTemp ~= old_prefs.ecoTemp then
      local eco_temp = (prefs.ecoTemp or 18) * 10
      local data = string.char((eco_temp >> 24) & 0xFF) .. string.char((eco_temp >> 16) & 0xFF) ..
                   string.char((eco_temp >> 8) & 0xFF) .. string.char(eco_temp & 0xFF)
      local cmd_body = create_tuya_command(DP_ECO_TEMP, 0x02, data)
      device:send(zcl_clusters.basic_id:build_cluster_specific_command(device, TUYA_CLUSTER, TUYA_SET_DATA, cmd_body.value))
      device.log.info("Set eco temperature to " .. (prefs.ecoTemp or 18))
    end
  end
end

local function do_refresh(driver, device, command)
  device.log.info("Refreshing thermostat state")
  
  -- Request data from Tuya cluster - send empty query to get all DPs
  local empty_payload = data_types.CharString("", false)
  device:send(zcl_clusters.basic_id:build_cluster_specific_command(
    device,
    TUYA_CLUSTER,
    0x00,  -- Query/get data command
    empty_payload.value
  ))
end

-- Driver configuration
local moes_thermostat_driver = {
  supported_capabilities = {
    capabilities.thermostatMode,
    capabilities.thermostatHeatingSetpoint,
    capabilities.temperatureMeasurement,
    capabilities.battery,
    capabilities.refresh
  },
  
  capability_handlers = {
    [ThermostatMode.ID] = {
      [ThermostatMode.commands.setThermostatMode.NAME] = handle_thermostat_mode
    },
    [ThermostatHeatingSetpoint.ID] = {
      [ThermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = handle_heating_setpoint
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  
  zigbee_handlers = {
    cluster = {
      [TUYA_CLUSTER] = {
        [TUYA_REPORT_DATA] = tuya_handler,
        [TUYA_SET_DATA] = tuya_handler,  -- Also handle set data responses
        [0x02] = tuya_handler  -- Some devices use command 0x02 for responses
      }
    }
  },
  
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    infoChanged = device_info_changed
  },
  
  sub_drivers = {}
}

defaults.register_for_default_handlers(moes_thermostat_driver, moes_thermostat_driver.supported_capabilities)
local driver = ZigbeeDriver("moes-thermostat", moes_thermostat_driver)
driver:run()
