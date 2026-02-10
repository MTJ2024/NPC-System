# NPC-System
Echtzeit NPC System für Owner - FiveM ESX Framework

## 🎯 Features

- **Vollständig funktionierendes UI-Dashboard** für NPC-Verwaltung
- **4 Verhaltensweisen** mit korrekter Kampflogik:
  - **Passiv**: Greift nie an, kann fliehen
  - **Neutral**: Verteidigt sich nur bei direktem Angriff
  - **Wache**: Verteidigt bei Angriff, bewaffneten Spielern in der Nähe, oder wenn Verbündete angegriffen werden
  - **Aggressiv**: Greift Spieler sofort bei Sichtkontakt im Radius an
- **Wachen helfen sich gegenseitig** - Wenn ein Wachmann angegriffen wird, kommen andere zu Hilfe
- **Waffenerkennung** - Wachen reagieren wenn Spieler Waffe zieht
- **Korrekte Bodenplatzierung** - NPCs schweben nicht mehr
- **Radius-basierte Aggression** - NPCs greifen IM Radius an, laufen nicht weg
- **Umfassendes Debug-Logging** - Verstehe genau was passiert

## 📋 Anforderungen

- FiveM Server
- ESX Framework (es_extended)
- oxmysql

## 🚀 Installation

1. Ressource in den `resources` Ordner kopieren
2. SQL-Datei importieren: `sql/npc_bodyguards.sql`
3. In `server.cfg` eintragen: `ensure npc-system`
4. Server neu starten

## 💻 Verwendung

### Dashboard öffnen
```
/npcdashboard
```
**Voraussetzung**: Admin oder Superadmin Gruppe

### NPC erstellen
1. Dashboard öffnen
2. "NPC erstellen" klicken
3. NPC-Typ auswählen (Polizist, Gangmitglied, etc.)
4. "Position wählen" → Zur gewünschten Position gehen → ENTER drücken
5. Einstellungen anpassen (Waffe, Verhalten, Radius, Bewegung)
6. Speichern

### NPC bearbeiten
1. In der Liste auf NPC-Karte klicken
2. Einstellungen ändern
3. "Speichern" klicken

### NPC löschen
1. NPC-Karte öffnen
2. "Löschen" klicken
3. Bestätigen

## 🎮 Verhaltensweisen erklärt

### Passiv (Passiv)
**Beispiele**: Koch, Sanitäter, Geschäftsmann, Taxifahrer

- Greift **nie** an
- Kann fliehen wenn bedroht
- Ideal für friedliche NPCs

### Neutral (Neutral)
**Beispiele**: Dealer, Pilot, Mechaniker, VIP

- Verteidigt sich **nur** bei direktem Angriff
- Reagiert **nicht** auf Waffen in der Nähe
- Stoppt Kampf wenn Spieler flieht
- Ideal für NPCs die sich wehren aber nicht provozieren

### Wache (Wache)
**Beispiele**: Polizist, Sheriff, Sicherheitskraft, Türsteher

- Greift an wenn:
  - Direkt angegriffen
  - Spieler zieht Waffe in der Nähe (innerhalb 70% Radius)
  - Ein anderer Wachmann in der Nähe angegriffen wird (bis 2x Radius)
- **Wachen helfen sich gegenseitig!**
- Kehrt zum Posten zurück wenn Kampf endet
- Flieht nie
- Ideal für Sicherheits-NPCs und Strafverfolgung

### Aggressiv (Aggressiv)
**Beispiele**: Gangmitglied, Mafia, Army

- Greift **sofort** an wenn Spieler den Radius betritt
- Keine Provokation nötig
- Verfolgt bis Spieler außer Reichweite
- Ideal für feindliche Territorien

## ⚙️ Einstellungen

### Radius
- Legt fest wie weit NPCs agieren/patrouillieren
- **Aggressiv-NPCs**: Greifen Spieler bei Eintritt in Radius an
- **Wache-NPCs**: Reagieren auf Bedrohungen im Radius
- **Bewegungs-NPCs**: Wandern innerhalb des Radius

### Bewegung
- **An**: NPC wandert im Radius herum
- **Aus**: NPC steht still am Spawn-Punkt (eingefroren)

### Waffe
7 Waffentypen verfügbar:
- Pistole, Maschinenpistole, Karabiner
- Messer, Schläger, Schraubenschlüssel
- Keine Waffe

### Ignorieren
- **Gruppen**: Admin, Superadmin, etc. (kommagetrennt)
- **Jobs**: Police, Ambulance, etc. (kommagetrennt)
- NPCs greifen ignorierte Spieler nicht an

## 🐛 Debug-Modus

Debug-Modus ist **standardmäßig aktiviert** in `config/config.lua`:
```lua
Config.Debug = true
```

Du siehst dann in der F8-Konsole:
```
[NPC-DEBUG] Syncing all NPCs - Total: 5
[NPC-DEBUG] Setting up NPC: Polizist (Behavior: Wache)
[NPC-DEBUG] Guard NPC engaging combat: Polizist - Reason: player armed nearby
[NPC-DEBUG] Nearby guard joining fight: Sheriff
```

Zum Deaktivieren: `Config.Debug = false`

## 📖 Dokumentation

- **TESTING.md** - Umfassende Test-Anleitung für alle Funktionen
- **FIXES.md** - Detaillierte Übersicht aller Fehlerbehebungen

## 🔧 Konfiguration

Siehe `config/config.lua` für:
- Lebenspunkte (Standard: 250)
- Respawn-Zeit (Standard: 15 Sekunden)
- Radius (Standard: 15m)
- Invincibility-Einstellungen
- Spezial-NPC Konfigurationen

## 21 NPC-Typen verfügbar

### Strafverfolgung
- Polizist (Pistole, Wache, 15m)
- Sheriff (Pistole, Wache, 15m)

### Kriminelle
- Gangmitglied (Maschinenpistole, Aggressiv, 10m)
- Mafia (Pistole, Aggressiv, 10m)
- Dealer (Pistole, Neutral, 10m)

### Sicherheit
- Sicherheitskraft (Pistole, Wache, 15m)
- Türsteher (Schläger, Wache, 10m)

### Militär
- Army (Karabiner, Aggressiv, 20m)

### Rettungsdienste
- Sanitäter (Keine Waffe, Passiv, 10m)
- Feuerwehrmann (Keine Waffe, Passiv, 10m)
- Arzt (Keine Waffe, Passiv, 10m)

### Zivilisten
- Koch mit Messer (Messer, Passiv, 8m)
- Pilot mit Pistole (Pistole, Neutral, 10m)
- Mechaniker mit Schraubenschlüssel (Schraubenschlüssel, Neutral, 8m)
- Geschäftsmann (Keine Waffe, Passiv, 8m)
- VIP (Keine Waffe, Neutral, 8m)
- Taxifahrer (Keine Waffe, Passiv, 8m)
- Obdachloser (Keine Waffe, Passiv, 8m)
- Jogger (Keine Waffe, Passiv, 8m)
- Bauarbeiter (Keine Waffe, Neutral, 10m)
- Landwirt (Keine Waffe, Passiv, 10m)

## ❓ Problembehebung

### Dashboard öffnet sich nicht
- Stelle sicher du bist Admin/Superadmin
- Prüfe F8-Konsole auf Fehler
- Stelle sicher ESX geladen ist

### NPCs spawnen nicht
- Prüfe F8-Konsole auf Fehler
- Stelle sicher oxmysql läuft
- Prüfe ob SQL-Tabelle existiert: `npc_dashboard_npcs`

### NPCs reagieren nicht
- Aktiviere Debug-Modus und prüfe Logs
- Stelle sicher NPC hat korrektes Verhalten eingestellt
- Prüfe ob du in "Ignorieren"-Liste bist

## 🔐 Sicherheit

- Nur Admins/Superadmins können Dashboard nutzen
- Validierung aller Server-Anfragen
- Nur erlaubte Modelle/Waffen verwendbar
- CodeQL Security Scan: 0 Schwachstellen gefunden

## 📝 Changelog

### Version 2.0 (Aktuell)
- ✅ **BEHOBEN**: NPCs schweben nicht mehr (korrekte Bodenplatzierung)
- ✅ **BEHOBEN**: Verhaltensweisen funktionieren jetzt korrekt
- ✅ **NEU**: Wachen helfen sich gegenseitig
- ✅ **NEU**: Waffenerkennung für Wachen
- ✅ **NEU**: Radius = Aggressionszone (nicht Fluchtzone)
- ✅ **NEU**: Umfassendes Debug-Logging
- ✅ **BEHOBEN**: Alle UI-Funktionen funktionieren
- ✅ **BEHOBEN**: Aggressiv-NPCs greifen im Radius an
- ✅ **VERBESSERT**: Performance optimiert

## 👨‍💻 Support

Bei Problemen:
1. Aktiviere Debug-Modus
2. Prüfe F8-Konsole
3. Lese TESTING.md für Test-Anleitungen
4. Lese FIXES.md für technische Details

## 📄 Lizenz

Dieses Projekt ist für die Verwendung auf FiveM-Servern vorgesehen.

