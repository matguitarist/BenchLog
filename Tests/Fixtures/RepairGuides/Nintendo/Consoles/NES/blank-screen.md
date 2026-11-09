# Blank Screen

## Problem Description
A blank screen occurs when your NES powers on (solid power light) but displays nothing on the TV screen. Unlike the blinking red light issue, the power indicator remains solid, suggesting the console is running, but no video output is displayed.

![[blank_screen.jpg]]

## Symptoms
- Solid red power light (not blinking)
- No display on screen (black, blue, or static)
- May hear game audio but see no video
- Game may be running "blind" (responding to controller inputs)
- Different from the blinking light issue (which indicates lockout activation)

## Common Causes
1. **Faulty A/V cable or RF switch**
2. **Incorrect TV input or channel selection**
3. **Faulty video RAM (VRAM) chips**
4. **PPU (Picture Processing Unit) failure**
5. **Cold solder joints on video components**
6. **Corroded or damaged video output port**
7. **Issues with the game cartridge's video circuitry**
8. **Damaged motherboard traces**

## Required Tools
- Phillips screwdriver
- Flathead screwdriver (small)
- Multimeter
- Isopropyl alcohol (90%+ concentration)
- Cotton swabs
- Soldering iron and solder (for advanced repairs)
- Replacement A/V cables or RF switch (if needed)

## Diagnostic Procedure

### Step 1: Check External Connections
1. Verify all cables are firmly connected
2. For RF connections:
   - Ensure the RF switch is on channel 3 or 4
   - Make sure your TV is tuned to the matching channel
3. For A/V connections:
   - Confirm cables are plugged into correct inputs on the TV
   - Set TV to the correct input source
4. Try a different TV if possible

![[rf_switch.jpg]]

### Step 2: Test Different Video Output
If your NES has both RF and A/V outputs:
1. Try the alternate connection method
2. For RF-only NES, try a different RF switch if available
3. For A/V connections, try a different A/V cable

### Step 3: Check the Game Cartridge
1. Clean the game contacts with isopropyl alcohol
2. Try a different game if available
3. Ensure the game is properly inserted

### Step 4: Open the Console
1. Unplug all cables
2. Remove the six screws from the bottom
3. Lift off the top case
4. Remove the metal RF shield (7 screws)
5. Inspect for visible damage:
   - Look for corrosion on the motherboard
   - Check for bulging or leaking capacitors
   - Inspect for burnt components
   - Look for broken traces near the video output

![[motherboard_inspection.jpg]]

### Step 5: Test the PPU and VRAM (Advanced)
1. Locate the PPU chip (large square chip, often labeled RP2C02)
2. Check for:
   - Overheating (discoloration)
   - Physical damage
   - Cold solder joints on the pins
3. Locate the two VRAM chips (often near the PPU)
4. Check for similar issues

![[ppu_location.jpg]]

## Common Solutions

### For Cable/Connection Issues
1. Replace the RF switch or A/V cables
2. Clean the video output port with contact cleaner
3. If using RF, try an RF to coaxial adapter for modern TVs

![[av_cables.jpg]]

### For Internal Video Component Issues (Advanced)
1. **Cold Solder Joint Repair**:
   - Reflow solder on the PPU and VRAM chip pins
   - Check video output port solder connections
   - Look for and repair any cracked solder joints

2. **Chip Reseating**:
   - Carefully remove and reseat the PPU chip (requires specialized tools)
   - Clean chip legs and socket with contact cleaner

3. **Component Replacement** (Expert level):
   - Replace faulty VRAM chips (requires donor board or parts)
   - Replace PPU (very difficult, requires matching PPU type)

![[reflow_solder.jpg]]

### Software Reset Technique
Sometimes this can resolve temporary video issues:
1. Power on the NES with a game inserted
2. Press and hold Reset while the power is on
3. Release after 10-15 seconds
4. Power cycle the console and try again

## Special Cases

### Audio Works but No Video
This strongly suggests a PPU issue:
1. Verify the game is running by listening for proper game sounds
2. If you can control the game "blind" and hear appropriate sounds, the PPU or VRAM is likely failing

### Different Results with Different Games
1. Some games may work while others don't
2. Games with special chips (MMC3, etc.) may have different results
3. Test with the simplest games first (Super Mario Bros., etc.)

### Partial or Distorted Video
1. If you see partial video or strange patterns, the PPU may be partially working
2. Take photos of any patterns as they can help diagnose the specific issue

![[distorted_video.jpg]]

## Prevention
1. Handle the console gently to avoid connection issues
2. Store in a dry, dust-free environment
3. Use a surge protector to prevent electrical damage
4. For long-term storage, remove game cartridges

## Related Issues
- [[vertical-lines-or-stripes|Vertical Lines or Stripes]]
- [[cartridge-connection-issues]]
- [[power-supply-problems|Power Supply Problems]]
- [[blinking-red-light|Blinking Red Light]]
