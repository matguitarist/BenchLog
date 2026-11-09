# Xbox Version Identification

## Why Version Identification Matters
The original Xbox went through several hardware revisions during its lifecycle (2001-2006). Knowing which version you have is crucial for:
- Determining whether your clock capacitor needs removal
- Finding compatible replacement parts
- Following the correct repair procedures
- Understanding which modifications are compatible
- Identifying known issues specific to your version

![[xbox_versions.jpg]]

## Identification Methods

### Method 1: Manufacturing Date and Serial Number
Look at the bottom of your Xbox for a sticker with manufacturing information:

1. **Manufacturing Date**:
   - Format: YYYY-MM-DD (Year-Month-Day)
   - Generally correlates with version:
     - 2001-2002: Likely v1.0
     - 2002-2003: Likely v1.1-1.2
     - 2003-2004: Likely v1.3-1.4
     - 2004-2005: Likely v1.5-1.6

2. **Serial Number**:
   - The first line after "MADE IN MEXICO" or "MADE IN CHINA"
   - Contains manufacturing information but requires decoding

![[xbox_serial_number.jpg]]

### Method 2: Video Encoder Type (Easiest External Method)
Look at the AV port on the back of your Xbox:

1. **High-Definition AV Pack Port**:
   - **Focus video chip** (metal shielding visible inside port): v1.0
   - **Conexant video chip** (black plastic inside port): v1.1-1.5
   - **Xcalibur video chip** (gold/yellow inside port): v1.6

![[av_port_versions.jpg]]

### Method 3: Opening the Console (Most Accurate)
This method requires opening your Xbox (follow steps in the [[Clock Capacitor Leakage]] guide):

#### Power Supply Identification
1. **v1.0**: 1.2A power supply, large and heavy
2. **v1.1**: 1.2A power supply, similar to v1.0
3. **v1.2-1.5**: 1.0A power supply, slightly smaller
4. **v1.6**: 1.0A power supply, different design with more ventilation

![[power_supply_versions.jpg]]

#### Motherboard Identification
Each version has distinct motherboard features:

1. **Version 1.0**:
   - NVIDIA GPU marked "NVIDIA XGPU A02"
   - 1 MB Samsung TSOP flash chip
   - 12 video RAM chips
   - IDE connector with white boot ROM
   - Gold clock capacitor near IDE connector

2. **Version 1.1**:
   - "NVIDIA XGPU A03" GPU
   - 1 MB Samsung TSOP flash chip
   - 4 video RAM chips
   - IDE connector with white boot ROM
   - Gold clock capacitor

3. **Version 1.2**:
   - "NVIDIA XGPU A03" GPU
   - No TSOP flash chip (Focus flash chip instead)
   - 4 video RAM chips
   - Black IDE connector
   - Gold clock capacitor

4. **Version 1.3**:
   - Similar to 1.2 but with different component placement
   - Gold clock capacitor
   - Different trace layout near the GPU

5. **Version 1.4**:
   - Similar to 1.3
   - Gold clock capacitor
   - Minor component changes

6. **Version 1.5**:
   - Similar to 1.4
   - Black clock capacitor instead of gold
   - LPC debug port present

7. **Version 1.6/1.6b**:
   - "NVIDIA XGPU A05" GPU
   - Smaller CPU heatsink
   - No separate RAM chips (integrated into CPU package)
   - No clock capacitor, or different style that should NOT be removed
   - LPC debug port missing or covered

![[motherboard_identifiers.jpg]]

## Version-Specific Notes

### Version 1.0
- Most prone to overheating
- Clock capacitor should be removed
- TSOP flashable (good for modding)
- Loudest fan noise
- Most power-hungry version

### Version 1.1-1.5
- Clock capacitor should be removed
- TSOP flashable (v1.1-1.2) or requires specialized techniques (v1.3-1.5)
- Good balance of reliability and mod-friendliness
- Improved cooling over v1.0

### Version 1.6/1.6b
- NO clock capacitor removal (has different type or required for operation)
- NOT TSOP flashable (requires modchip for BIOS mods)
- Least power consumption
- Quietest operation
- Most reliable when stock
- Different HDD security sector format

![[version_comparison.jpg]]

## DVD Drive Identification
The DVD drive model can also help identify your Xbox version:

1. **Thomson (Philips)**: 
   - Found in early v1.0-1.1 consoles
   - Has "Thomson" branding
   - Known for rubber belt issues

2. **Phillips VAD6011/21**:
   - Common in v1.1-1.3 consoles
   - Similar to Thomson but more reliable
   - Black casing with Phillips branding

3. **Samsung SDG-605**:
   - Found in v1.2-1.4 consoles
   - Generally reliable
   - Black housing with Samsung branding

4. **Hitachi-LG GDR-8163B**:
   - Found in v1.6 consoles
   - Most reliable drive
   - Black housing with different tray mechanism

![[dvd_drive_models.jpg]]

## Kernel Version
On-screen kernel version (visible during boot or in settings):

1. **5713**: Early v1.0 (debug units)
2. **5838**: Most v1.0 consoles
3. **5849**: v1.1-v1.2 consoles
4. **5858**: v1.3-v1.5 consoles
5. **5960**: v1.6 consoles

![[kernel_versions.jpg]]

## Clock Capacitor Location by Version
Finding and identifying the clock capacitor:

1. **v1.0-1.1**: Gold 1F 2.5V capacitor near IDE connector
2. **v1.2-1.4**: Gold 1F 2.5V capacitor near IDE connector, slightly different position
3. **v1.5**: Black 1F 2.5V capacitor near IDE connector
4. **v1.6**: Different type or missing - should NOT be removed

![[clock_capacitor_locations.jpg]]

## Version-Specific Repair Considerations

### Clock Capacitor Removal
- **v1.0-1.5**: Remove the clock capacitor to prevent damage
- **v1.6**: Do NOT remove the clock capacitor

### Hard Drive Compatibility
- **v1.0-1.5**: Similar HDD security format
- **v1.6**: Different HDD security sector format, requires specific preparation

### BIOS Modding
- **v1.0-1.2**: Easily TSOP flashable
- **v1.3-1.5**: Requires additional steps for TSOP flashing
- **v1.6**: Not TSOP flashable, requires modchip

### Power Supply Replacement
- **v1.0-1.1**: Use 1.2A power supply models
- **v1.2-1.6**: Use 1.0A power supply models
- Power supplies are not directly interchangeable between all versions

## Special Xbox Editions

### Xbox "Debug" Kits
- Development units used by game developers
- Usually transparent green or black cases
- Different boot sequence
- 8GB hard drive
- Additional ports and features

### Limited Edition Consoles
Different cosmetic editions exist, but internal hardware typically matches the standard version from the same time period:

1. **Crystal**: Transparent case (usually v1.4)
2. **Halo Special Edition**: Green case with game logo (usually v1.4-1.5)
3. **Kasumi Blue**: Blue case (Japanese market, v1.4)
4. **Mountain Dew**: Green promotional case (v1.4)

![[special_editions.jpg]]

## Documenting Your Xbox
Once you've identified your Xbox version, consider:

1. Making note of the version on the case
2. Documenting the serial number
3. Noting any specific known issues for that version
4. Taking pictures of the motherboard for future reference

## Related Guides
- [[clock-capacitor-leakage|Clock Capacitor Leakage]]
- [[hard-drive-failure|Hard Drive Failure]]
- [[frag-error|FRAG Error (Flashing Red and Green)]]
- [[power-supply-issues|Power Supply Issues]]