# Blinking Red Light

## Problem Description
The blinking red power light (also called the "red light of death") is the most common issue with the original front-loading NES. When you insert a game and power on the console, instead of playing the game, the power light repeatedly flashes on and off, and the screen remains blank or shows a solid color.

![[blinking_red_light.jpg]]

## Symptoms
- Power light blinks on and off continuously
- No game appears on screen
- Sometimes accompanied by a gray or colored screen
- The blinking occurs even with known working games
- May happen on some cartridges but not others
- Console may occasionally boot games after multiple attempts

## Common Causes
1. **Dirty or oxidized 72-pin connector** (most common)
2. **Dirty game cartridge contacts**
3. **Faulty 10NES lockout/CIC chip**
4. **Poor connection between cartridge and console**
5. **Bent pins in the 72-pin connector**
6. **Damaged game cartridge**
7. **Corroded components on the motherboard**
8. **Faulty power supply**

## Required Tools
- Phillips screwdriver
- Flathead screwdriver (small)
- Cotton swabs
- Isopropyl alcohol (90%+ concentration)
- Brass/copper polish (optional)
- Rubber eraser (optional)
- Security bit screwdriver (for opening game cartridges)
- Needle-nose pliers (for 72-pin adjustment)

## Diagnostic Procedure

### Step 1: Try Basic Cartridge Fixes
1. Remove the game cartridge
2. Clean the contacts with isopropyl alcohol and a cotton swab
3. Try another game cartridge if available
4. Try the "wiggle method" - insert the cart, then wiggle it side to side

![[cartridge_cleaning.jpg]]

### Step 2: Clean the 72-Pin Connector
1. Unplug the NES and remove all cartridges
2. Use a Phillips screwdriver to remove the 6 screws from the bottom of the console
3. Lift off the top half of the case
4. Remove the metal RF shield (7 screws)
5. Disconnect the ribbon cables for the controllers and power/reset
6. Remove the cartridge tray (4 screws)
7. Remove the 72-pin connector by pulling up firmly
8. Clean thoroughly with isopropyl alcohol and cotton swabs
9. Allow to dry completely before reinstalling

![[72pin_connector_removal.jpg]]

### Step 3: Adjust 72-Pin Connector
If cleaning doesn't work, adjust the pins for better contact:
1. Remove the 72-pin connector as described above
2. Use a small screwdriver or needle to gently bend each pin inward slightly
3. The goal is to create more tension when a cartridge is inserted
4. Be gentle - only bend pins about 5-10 degrees

![[pin_adjustment.jpg]]

### Step 4: Disable the Lockout Chip (More Advanced)
The 10NES lockout chip can cause blinking even with clean connections:
1. Locate the CIC/lockout chip on the motherboard (usually labeled "3193A")
2. Using wire cutters, carefully cut pin 4 of the chip

Alternatively (safer method):
1. Connect pins 4 and 7 with a small piece of wire
2. Solder in place

![[lockout_chip.jpg]]

## Common Solutions

### Solution 1: Replacement 72-Pin Connector
If cleaning and adjusting doesn't work, replace the connector:
1. Purchase a replacement 72-pin connector
2. Remove the old connector (as described above)
3. Align and install the new connector
4. Reassemble the console
5. Test with a known working game

![[replacement_connector.jpg]]

### Solution 2: Boil the 72-Pin Connector (Unconventional but Effective)
This method has shown surprising success:
1. Remove the 72-pin connector
2. Place in boiling water for 5-10 minutes
3. Remove and let dry completely (24+ hours)
4. Reinstall and test

### Solution 3: "Blowing" Method (Temporary Fix)
The classic but not recommended long-term solution:
1. Blow firmly into the cartridge contacts
2. Insert into NES and try again
3. Note: This actually works temporarily, but moisture from breath can cause corrosion long-term

## Prevention
1. Always store games in protective cases or sleeves
2. Periodically clean game contacts with isopropyl alcohol
3. Insert and remove cartridges gently
4. Consider disabling the lockout chip permanently
5. Don't leave games inserted in the console for extended periods
6. Keep the console dust-free

## When to Replace the 72-Pin Connector
Consider replacement when:
- Cleaning and adjustment don't resolve the issue
- You've tried multiple known working games
- The connector shows physical damage or extreme wear
- Games are extremely loose or tight when inserted

## Related Issues
- [[cartridge-connection-issues|Cartridge Connection Issues]]
- [[blank-screen|Blank Screen]]
- [[game-freezing-or-glitching|Game Freezing or Glitching]]
- [[72-pin-connector-replacement|72-Pin Connector Replacement]]
