Config = {}

-- === NPC Grundwerte ===

-- Standard-Lebenspunkte für NPCs (kann pro NPC überschrieben werden)
Config.DefaultHealth = 250

-- Aggro-/Patrouillenradius (Standard, kann pro NPC überschrieben werden)
Config.DefaultRadius = 15.0

-- Wie lange bleibt die Leiche nach dem Tod sichtbar (in ms)?
Config.DeadTimeout = 15000 -- 15 Sekunden

-- Wie lange dauert der Respawn, wenn NPC "wegverfolgt" despawnt wurde (in ms)?
Config.RespawnDelayIfFar = 30000 -- 30 Sekunden

-- Wieviel Zeit muss zwischen Patrouillenpunkten min/max liegen? (nur bewegende NPCs)
Config.PatrolWaitMin = 8000   -- ms
Config.PatrolWaitMax = 12000  -- ms

-- Sollen NPCs unverwundbar sein? (false = realistisch)
Config.NPCInvincible = false

-- Standardwaffe (kann pro NPC überschrieben werden)
Config.DefaultWeapon = "WEAPON_PISTOL"

-- Aggro durch Wanted-Level ab wieviel Sternen? (0 = auch schon bei 1 Stern)
Config.AggroWantedMin = 1

-- Respawn-Logik:
-- true = NPC wird NUR respawnt, wenn am Standort gestorben. false = immer nach DeadTimeout respawnen
Config.InstantRespawnAtOrigin = true

-- === Spezialkonfigurationen für einzelne NPCs ===
-- Hier kannst du pro NPC (per ID oder Namen) eigene Werte setzen, die alles überschreiben.
Config.SpecialNpcs = {
    -- Beispiel:
    -- ["npc_id_1"] = { health = 400, weapon = "WEAPON_SMG", radius = 20.0, invincible = false }
}

-- === Debug-Ausgaben aktivieren? ===
Config.Debug = false

-- === Sprach-Konfiguration ===
Config.Locale = "de"

-- === Weitere Einstellungen nach Wunsch ergänzen ===