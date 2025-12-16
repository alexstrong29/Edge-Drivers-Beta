# Moes Star Ring Smart Knob Thermostat Edge Driver

SmartThings Edge driver for the Moes Star Ring Smart Knob Thermostat - a wall-mounted dial thermostat controller (Model: _TZE204_IPEDVTVR).

## About This Device

The Moes Star Ring is a battery-powered wall thermostat with a rotating dial interface. It controls your heating system via relay output and provides an intuitive knob-based temperature control experience.

## Features

- Temperature measurement and display
- Heating setpoint control
- Multiple thermostat modes (Off, Heat, Auto)
- Battery level monitoring
- Standard SmartThings thermostat interface

## Installation

### Method 1: SmartThings CLI (Recommended)

1. Install the SmartThings CLI if you haven't already:
   ```bash
   npm install -g @smartthings/cli
   ```

2. Login to your SmartThings account:
   ```bash
   smartthings login
   ```

3. Navigate to the driver directory:
   ```bash
   cd moes-star-thermostat
   ```

4. Package and install the driver:
   ```bash
   smartthings edge:drivers:package .
   smartthings edge:drivers:install
   ```

5. Select your hub when prompted

### Method 2: Developer Workspace

1. Create a new channel in the SmartThings Developer Workspace
2. Upload the driver package
3. Invite your hub to the channel
4. Install the driver from the SmartThings mobile app

## Pairing Instructions

1. Ensure the driver is installed on your SmartThings hub
2. Put your hub into pairing mode (Add Device → Scan Nearby)
3. Reset the Moes Star Ring thermostat:
   - Press and hold both side buttons on the thermostat for ~5 seconds
   - The display should flash or show a pairing indicator
4. The device should appear in the SmartThings app as "Moes Star Ring Thermostat"

**Note:** The Star Ring is a wall-mounted dial thermostat that controls your heating system via relay. Make sure it's properly wired to your heating system before pairing.

## Supported Modes

- **Off**: Thermostat is disabled
- **Heat**: Manual heating mode - maintains set temperature
- **Auto**: Automatic scheduling mode (if configured in thermostat)

## Device Capabilities

- **Temperature**: Current room temperature
- **Heating Setpoint**: Target temperature (adjustable in 0.5°C increments)
- **Thermostat Mode**: Current operating mode
- **Battery**: Battery level percentage
- **Refresh**: Manually request current state from device

## Troubleshooting

### Device not pairing
- Ensure the thermostat is in pairing mode (both buttons held for 5 seconds)
- Move the thermostat closer to the hub during pairing
- Try removing and re-installing the batteries

### Temperature not updating
- Use the Refresh capability to manually request an update
- Check battery level - low battery can affect communication
- Ensure the device is within Zigbee range

### Setpoint changes not applying
- Verify the thermostat is in Heat or Auto mode (not Off)
- Check that child lock is not enabled on the thermostat itself
- Try refreshing the device state

## Technical Details

**Device Type:** Wall-mounted smart dial thermostat
**Power:** Battery powered (typically 2x AA)
**Control:** Relay output for heating system

**Zigbee Information:**
- Manufacturer: _TZE204_IPEDVTVR
- Model: TS0601
- Cluster: Tuya Private Cluster (0xEF00)

**Data Points:**
- DP 0x04: Operating mode
- DP 0x10: Heating setpoint
- DP 0x18: Current temperature
- DP 0x23: Battery level
- DP 0x28: Child lock
- DP 0x68: Window detection
- DP 0x6C: Heating relay state

## Customization

The driver can be modified to add additional features:
- Window detection alerts
- Child lock control
- Heating relay state display
- Advanced scheduling
- Temperature offset calibration

Edit the `src/init.lua` file to add additional data point handlers.

## Support

For issues or questions:
1. Check the SmartThings IDE Live Logging for error messages
2. Verify the driver is properly installed on your hub
3. Ensure the thermostat firmware is up to date

## License

This driver is provided as-is for personal use with SmartThings Edge-compatible hubs.
