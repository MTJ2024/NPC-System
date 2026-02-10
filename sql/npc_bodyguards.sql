-- Löscht alte Tabelle, falls vorhanden
DROP TABLE IF EXISTS `npc_dashboard_npcs`;

-- Neue NPC-Tabelle anlegen
CREATE TABLE `npc_dashboard_npcs` (
  `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(64) NOT NULL,
  `model` VARCHAR(64) NOT NULL,
  `weapon` VARCHAR(64) DEFAULT NULL,
  `behavior` VARCHAR(32) DEFAULT NULL,
  `radius` INT DEFAULT 10,
  `x` FLOAT NOT NULL,
  `y` FLOAT NOT NULL,
  `z` FLOAT NOT NULL,
  `heading` FLOAT DEFAULT 0.0,
  `violent` TINYINT(1) DEFAULT 0,
  `movement` TINYINT(1) DEFAULT 0,
  `ignoreGroups` VARCHAR(255) DEFAULT '',   -- <--- NEU: Gruppen-Ausnahmen (Komma getrennt)
  `ignoreJobs` VARCHAR(255) DEFAULT '',      -- <--- NEU: Jobs-Ausnahmen (Komma getrennt)
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Optional: Indexe für schnellere Suche
CREATE INDEX idx_model ON npc_dashboard_npcs (model);
CREATE INDEX idx_behavior ON npc_dashboard_npcs (behavior);

-- Optional: Ein Beispiel-NPC zum Testen (kannst du löschen)
INSERT INTO npc_dashboard_npcs
  (`name`, `model`, `weapon`, `behavior`, `radius`, `x`, `y`, `z`, `heading`, `violent`, `movement`, `ignoreGroups`, `ignoreJobs`)
VALUES
  ('Test Soldier', 's_m_y_soldier_01', 'WEAPON_CARBINERIFLE', 'Neutral', 20, 100.0, 200.0, 30.0, 90.0, 1, 1, 'admin', 'police');