# NPC System Testing Guide

## Debug Mode
Debug mode is now **enabled by default** in `config/config.lua`. You will see detailed console logs showing:
- When NPCs are spawned/despawned
- When NPCs enter/exit combat
- Why NPCs attack (e.g., "was attacked", "player armed nearby", "ally guard attacked")
- All UI operations (add, update, delete NPCs)

## Testing Checklist

### 1. UI Functionality Tests

#### Opening the Dashboard
1. Type `/npcdashboard` in game
2. **Expected**: Dashboard opens, shows all existing NPCs
3. **Debug Log**: "Opening NPC Dashboard", "Received X NPCs from server for dashboard"

#### Creating a New NPC
1. Click "NPC erstellen" button
2. Select an NPC type from dropdown
3. Click "Position wählen"
4. Walk to desired location
5. Press ENTER
6. **Expected**: Coordinate picker closes, NPC appears at location
7. **Debug Logs**: 
   - Server: "addNPC called by player X"
   - Server: "Adding NPC: [name] ([model]) at x,y,z"
   - Server: "NPC added successfully, reloading all NPCs"
   - Client: "Syncing all NPCs - Total: X"
   - Client: "NPC spawned successfully: [name]"

#### Updating an NPC
1. Click on an NPC card in the list
2. Modify any settings (behavior, radius, weapon, etc.)
3. Click "Speichern"
4. **Expected**: NPC settings updated, respawns with new settings
5. **Debug Logs**:
   - Server: "updateNPC called by player X"
   - Server: "Updating NPC ID X: [name]"
   - Client: NPC despawns and respawns with new settings

#### Deleting an NPC
1. Click on an NPC card
2. Click "Löschen" button
3. Confirm deletion
4. **Expected**: NPC removed from game and list
5. **Debug Logs**:
   - Server: "deleteNPC called by player X for NPC ID X"
   - Server: "NPC deleted successfully"

### 2. Behavior Mode Tests

#### Passive NPCs (Passiv)
**Examples**: Chef, Medic, Businessman, Taxi Driver

**Test 1: No Combat Response**
1. Spawn a Passive NPC
2. Attack it with fists or weapon
3. **Expected**: NPC does NOT fight back, may flee
4. **Debug Log**: "Behavior: Passive (non-combat)"

#### Neutral NPCs (Neutral)
**Examples**: Dealer, Pilot, Mechanic, VIP

**Test 1: Defends When Attacked**
1. Spawn a Neutral NPC
2. Attack it directly
3. **Expected**: NPC fights back
4. **Debug Log**: "Neutral NPC defending itself: [name]"

**Test 2: No Proactive Combat**
1. Stand near Neutral NPC
2. Pull out weapon (don't attack)
3. **Expected**: NPC does NOT attack (only responds to direct damage)

**Test 3: Stops Combat When Player Escapes**
1. Attack Neutral NPC
2. Run away beyond radius * 1.5
3. **Expected**: NPC stops fighting, returns to patrol/position
4. **Debug Log**: "Neutral NPC ending combat - player escaped"

#### Guard/Wache NPCs (Wache)
**Examples**: Police, Sheriff, Security, Bouncer

**Test 1: Attacks When Directly Attacked**
1. Spawn a Guard NPC
2. Attack it
3. **Expected**: Guard attacks back
4. **Debug Log**: "Guard NPC engaging combat: [name] - Reason: was attacked"

**Test 2: Attacks When Player Pulls Weapon Nearby**
1. Spawn a Guard NPC
2. Stand within 70% of its radius (e.g., if radius=15, stand within ~10m)
3. Pull out ANY weapon
4. **Expected**: Guard immediately attacks
5. **Debug Log**: "Guard NPC engaging combat: [name] - Reason: player armed nearby"

**Test 3: Guards Help Each Other**
1. Spawn 2-3 Guard NPCs close together (within 30m)
2. Attack ONE guard
3. **Expected**: ALL nearby guards attack you
4. **Debug Logs**: 
   - "Guard NPC engaging combat: [guard1] - Reason: was attacked"
   - "Nearby guard joining fight: [guard2]"
   - "Nearby guard joining fight: [guard3]"

**Test 4: Guards Return After Combat**
1. Get into combat with guard
2. Run far away (beyond radius * 2)
3. **Expected**: Guard stops chasing, returns to post
4. **Debug Log**: "Guard NPC ending combat - player too far"

#### Aggressive NPCs (Aggressiv)
**Examples**: Gang Member, Mafia, Army

**Test 1: Attacks on Sight**
1. Spawn an Aggressive NPC
2. Walk into its radius (e.g., 10m for Gang, 20m for Army)
3. **Expected**: NPC immediately attacks WITHOUT provocation
4. **Debug Log**: "Aggressive NPC attacking player in radius: [name]"

**Test 2: Stops When Player Leaves Radius**
1. Get into combat with Aggressive NPC
2. Run beyond radius * 1.5
3. **Expected**: NPC stops combat, returns to patrol
4. **Debug Log**: "Aggressive NPC ending combat - player too far"

### 3. Movement & Radius Tests

#### Stationary NPCs (Movement = 0/Off)
1. Spawn NPC with movement disabled
2. **Expected**: NPC stands still at spawn point, frozen
3. **Debug Log**: "Movement: Stationary"

**Test: Returns to Origin After Combat**
1. Attack stationary NPC (that can fight back)
2. Lead it away from spawn point
3. Run far away to end combat
4. **Expected**: NPC walks back to origin, freezes again
5. **Debug Log**: "Stationary NPC too far from origin, returning"

#### Wandering NPCs (Movement = 1/On)
1. Spawn NPC with movement enabled
2. **Expected**: NPC wanders around within radius
3. **Debug Log**: "Movement: Wandering"

**Test: Respawns If Wanders Too Far**
1. Watch wandering NPC
2. If it exceeds radius * 1.5 from spawn
3. **Expected**: NPC despawns and respawns at origin
4. **Debug Log**: "Moving NPC wandered too far, respawning: [name]"

### 4. Ground Placement Tests

**Test: NPCs Don't Float**
1. Spawn NPC on uneven terrain (hillside, stairs)
2. **Expected**: NPC stands on ground, not floating
3. Implementation: Uses `GetGroundZFor_3dCoord()` for proper Z placement

**Test: NPCs Spawn on Different Surfaces**
1. Spawn NPC on road
2. Spawn NPC on roof
3. Spawn NPC on beach
4. **Expected**: All NPCs correctly placed on ground surface

### 5. Weapon & Equipment Tests

**Test: NPCs Have Correct Weapons**
1. Spawn Police (should have WEAPON_PISTOL)
2. Spawn Army (should have WEAPON_CARBINERIFLE)
3. Spawn Gang Member (should have WEAPON_MICROSMG)
4. **Expected**: NPCs hold their configured weapons
5. **Debug Log**: "Weapon given: WEAPON_[type]"

**Test: Weaponless NPCs**
1. Spawn Businessman (no weapon)
2. **Expected**: NPC has no weapon, fists only

### 6. Ignore Settings Tests

**Test: Ignore by Group**
1. Spawn Guard NPC
2. Edit it, add your admin group to "Ignore Groups" (e.g., "admin,superadmin")
3. Attack the guard
4. **Expected**: Guard does NOT attack you

**Test: Ignore by Job**
1. Spawn Guard NPC  
2. Edit it, add "police" to "Ignore Jobs"
3. Set your job to police
4. Attack the guard
5. **Expected**: Guard does NOT attack you

### 7. Respawn Tests

**Test: Dead NPCs Respawn**
1. Spawn any NPC
2. Kill it
3. Wait 15 seconds (Config.DeadTimeout)
4. **Expected**: NPC respawns at original location
5. **Debug Logs**:
   - "NPC died: [name]"
   - (after 15s) "Respawning NPC: [name]"
   - "NPC respawned successfully: [name]"

### 8. Dashboard Categories

**Test: Category Filtering**
1. Open dashboard
2. Click on different categories:
   - **Strafverfolgung** (Police, Sheriff)
   - **Kriminelle** (Gang, Mafia, Dealer)
   - **Sicherheit** (Security, Bouncer)
   - **Militär** (Army)
   - **Rettungsdienste** (Medic, Firefighter)
   - **Zivilisten** (Everyone else)
3. **Expected**: Only NPCs of that category shown

**Test: Search Function**
1. Type in search box (e.g., "police")
2. **Expected**: Only matching NPCs shown

## Common Issues & Solutions

### Issue: "DENIED: Player is not admin"
**Solution**: Ensure you have admin or superadmin group in ESX

### Issue: NPCs not spawning
**Check**:
1. F8 console for errors
2. Database connection (oxmysql)
3. SQL table exists: `npc_dashboard_npcs`

### Issue: Dashboard not opening
**Check**:
1. Type `/npcdashboard` command
2. Check F8 console for JavaScript errors
3. Ensure ESX is loaded

### Issue: NPCs floating
**Solution**: Already fixed - now uses proper ground Z calculation

### Issue: All NPCs attack together (old behavior)
**Solution**: Already fixed - now behavior-specific combat

## Performance Notes

- Aggressive NPCs check player distance every 1 second
- Guard NPCs check for threats every 0.5 seconds
- Neutral NPCs check for attacks every 0.5 seconds
- Movement/despawn checks every 1 second
- Respawn checks every 0.5 seconds

All checks are optimized to only process existing, alive NPCs.

## Expected Debug Output Example

When everything works correctly, you should see console output like:
```
[NPC-SERVER-DEBUG] NPC Dashboard Server starting...
[NPC-SERVER-DEBUG] Resource started, loading NPCs from database...
[NPC-SERVER-DEBUG] Loaded 5 NPCs from database
[NPC-SERVER-DEBUG] Broadcasted NPCs to all clients
[NPC-DEBUG] Syncing all NPCs - Total: 5
[NPC-DEBUG] Setting up NPC: Polizist (Behavior: Wache)
[NPC-DEBUG]   Weapon given: WEAPON_PISTOL
[NPC-DEBUG]   Behavior: Guard (protective, will help allies)
[NPC-DEBUG]   Movement: Stationary
[NPC-DEBUG] NPC spawned successfully: Polizist
[NPC-DEBUG] Sync complete - Active NPCs: 5
```

## Need Help?

If something doesn't work:
1. Check F8 console for error messages
2. Look for red debug logs
3. Verify database contains NPC data
4. Ensure you're admin/superadmin
5. Check Config.Debug is true for detailed logs
