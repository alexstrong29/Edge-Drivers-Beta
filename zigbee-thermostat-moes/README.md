# Moes Star Ring Smart Knob Thermostat Edge Driver

SmartThings Edge driver for the Moes Star Ring Smart Knob Thermostat - a wall-mounted dial thermostat controller (Model: _TZE204_lpedvtvr).

## About This Device

The Moes Star Ring is a mains-powered (hard-wired) wall thermostat with a rotating dial interface. It controls your heating system via relay output and provides an intuitive knob-based temperature control experience.

## Features

- Temperature measurement and display
- Heating setpoint control
- Multiple thermostat modes (Off, Heat, Auto)
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
- **Eco**: Uses the Eco mode temperature setting instead of the normal setpoint

## Device Capabilities

- **Temperature**: Current room temperature
- **Heating Setpoint**: Target temperature (adjustable in 0.5°C increments)
- **Thermostat Mode**: Current operating mode
- **Refresh**: Manually request current state from device

### Thermostat settings

These are controls on the device page (not the Settings page), and each shows the value the
thermostat reports. They use custom capabilities in the `dreamspace09858` namespace, defined in
`capabilities/`.

| Control | Range | DP |
|---|---|---|
| Eco mode temperature | 5–30°C | 0x71 |
| Temperature calibration | −9 to +9°C | 0x65 |
| Deadzone temperature | 1–5°C | 0x6E |
| Temperature sensor | Air / Both / Floor | 0x20 |
| Child lock | Locked / Unlocked | 0x27 |
| Display brightness | 0–100% | 0x30 |
| Screen timeout | Off / Short / Medium / Long | 0x72 |
| RGB backlight | On / Off | 0x73 |

To recreate a capability in another account, run `smartthings capabilities:create -n <namespace> -i capabilities/<name>.json`,
then `smartthings capabilities:presentation:create <namespace>.<name> 1 -i capabilities/<name>.presentation.json`.

## Troubleshooting

### Device not pairing
- Ensure the thermostat is in pairing mode (both buttons held for 5 seconds)
- Move the thermostat closer to the hub during pairing
- Try power-cycling the thermostat at the breaker

### Temperature not updating
- Use the Refresh capability to manually request an update
- Ensure the device is within Zigbee range

### Setpoint changes not applying
- Verify the thermostat is in Heat or Auto mode (not Off)
- Check that child lock is not enabled on the thermostat itself
- Try refreshing the device state

## Technical Details

**Device Type:** Wall-mounted smart dial thermostat
**Power:** Mains powered (hard-wired)
**Control:** Relay output for heating system

**Zigbee Information:**
- Manufacturer: _TZE204_lpedvtvr
- Model: TS0601
- Cluster: Tuya Private Cluster (0xEF00)

**Data Points:**
- DP 0x01: On/off
- DP 0x02: Preset (manual / temporary manual / program / eco; eco maps to the Eco mode)
- DP 0x10: Current temperature (0.1°C)
- DP 0x2F: Heating relay state (0 = heating)
- DP 0x32: Heating setpoint (0.1°C)
- Settings DPs: see the table above

Edit `src/init.lua` to add additional data point handlers. New settings only need an entry in the
`SETTINGS` table plus a matching custom capability.

## Support

For issues or questions:
1. Check the SmartThings IDE Live Logging for error messages
2. Verify the driver is properly installed on your hub
3. Ensure the thermostat firmware is up to date

## License

This driver is provided as-is for personal use with SmartThings Edge-compatible hubs.
