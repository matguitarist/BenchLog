# Vertical Lines or Stripes

## Problem Description
Vertical lines or stripes appear on the screen during gameplay. These can be single or multiple lines, solid or flickering, and may appear across the entire screen or only in certain areas. This problem is related to the video output and processing circuitry of the NES.

![[vertical_lines.jpg]]

## Symptoms
- Vertical lines appearing on screen during gameplay
- Lines may be static or flickering
- Lines might be colored or white
- The issue may worsen as the console warms up
- Lines might appear only with certain games
- Sometimes accompanied by other visual artifacts
- Game may otherwise play normally

## Common Causes
1. **Faulty PPU (Picture Processing Unit)**
2. **Damaged VRAM (Video RAM) chips**
3. **Cold solder joints on video components**
4. **Poor connection between cartridge and 72-pin connector**
5. **Issues with the RF modulator or A/V circuitry**
6. **Overheating components**
7. **Damaged game cartridge**
8. **Power supply instability**

## Required Tools
- Phillips screwdriver
- Flathead screwdriver (small)
- Isopropyl alcohol (90%+ concentration)
- Cotton swabs
- Soldering iron and solder (for advanced repairs)
- Heat sink compound (optional)
- Compressed air
- Multimeter (for advanced troubleshooting)

## Diagnostic Procedure

### Step 1: Basic Checks
1. Try a different game cartridge to rule out game-specific issues
2. Clean the game contacts with isopropyl alcohol
3. Check if the issue appears immediately or develops over time
4. Test with a different TV/monitor if possible
5. Try both RF and A/V connections (if your NES has both)

### Step 2: Check 72-Pin Connector
1. Clean the 72-pin connector (see [[cartridge-connection-issues|Cartridge Connection Issues]] guide)
2. Inspect for bent or damaged pins
3. Try the game in different positions (slightly pushed up/down/left/right)

![[cartridge_position.jpg]]

### Step 3: Open the Console
1. Unplug all cables
2. Remove the six screws from the bottom
3. Lift off the top case
4. Remove the metal RF shield (7 screws)
5. Look for signs of:
   - Corrosion on the motherboard
   - Damaged components
   - Heat damage (discoloration)
   - Bulging or leaking capacitors

![[open_nes_inspection.jpg]]

### Step 4: Inspect Video Components
1. Locate the PPU chip (large square chip, often labeled RP2C02)
2. Check for overheating (may feel very hot during operation)
3. Look for cold solder joints (dull, cracked appearance)
4. Inspect the VRAM chips (usually near the PPU)
5. Check the RF modulator (metal box) for damage

![[video_components.jpg]]

## Common Solutions

### Solution 1: Heat-Related Fixes
If the lines appear as the system warms up:
1. Improve ventilation around the console
2. Consider adding small heat sinks to the PPU (advanced)
3. For temporary testing, use a small fan to cool the system

### Solution 2: Reseating Chips (Advanced)
1. Carefully remove the PPU chip using proper chip removal tools
2. Clean the legs and socket with contact cleaner
3. Reseat the chip, ensuring all pins align properly
4. Do the same for VRAM chips if necessary

![[chip_reseating.jpg]]

### Solution 3: Fixing Cold Solder Joints (Advanced)
1. Identify cold solder joints around:
   - PPU chip
   - VRAM chips
   - Video output components
2. Reflow solder on suspicious joints
3. Add fresh solder if necessary
4. Use proper soldering technique to avoid damage

![[cold_solder_fix.jpg]]

### Solution 4: RF/AV Improvements
1. For RF connections:
   - Replace the RF modulator cable
   - Use an RF to coaxial adapter for better quality
2. For AV connections:
   - Try a high-quality AV cable
   - Check for damage to the AV port

## Advanced Solutions

### PPU Replacement (Expert Level)
If the PPU is confirmed faulty:
1. Source a matching PPU chip (must match your NES model)
2. Requires advanced desoldering and soldering skills
3. Use proper anti-static precautions
4. Consider professional repair service

![[ppu_replacement.jpg]]

### Motherboard Troubleshooting
For persistent issues:
1. Use a multimeter to check for continuity between PPU and VRAM
2. Test power rails for correct voltage
3. Look for damaged traces on the motherboard
4. Test capacitors in the video circuit

## Different Types of Line Patterns and Their Causes

### Solid Vertical Lines
- Often indicates VRAM issues
- May be related to address line problems

### Flickering Vertical Lines
- Usually suggests timing or synchronization issues
- Could be PPU-related

### Colored Vertical Lines
- Often palette-related
- May indicate issues with the PPU's color generation

### Lines Only in Specific Areas
- May be game-specific
- Could indicate partial damage to video components

![[line_pattern_examples.jpg]]

## Prevention
1. Avoid overheating (keep in well-ventilated area)
2. Use a surge protector
3. Handle the console gently
4. Keep the console clean and dust-free
5. Store in a dry environment

## Related Issues
- [[blank-screen|Blank Screen]]
- [[cartridge-connection-issues|Cartridge Connection Issues]]
- [[game-freezing-or-glitching|Game Freezing or Glitching]]
- [[72-pin-connector-replacement|72-Pin Connector Replacement]]
