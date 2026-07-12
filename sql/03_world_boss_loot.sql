/* Run in the WORLD database: acore_world.
   Adds Scroll of Deception / Scroll of Illusion to raid boss loot tables.

   Adjust the two @..._CHANCE variables below (percent, 0-100).
   Re-running this file is safe: it deletes previous scroll loot rows first. */

SET @DECEPTION := 23885;
SET @ILLUSION  := 35517;
SET @DECEPTION_CHANCE := 100;   /* percent */
SET @ILLUSION_CHANCE  := 100;   /* percent */

/* Raid maps: Onyxia, Naxxramas, Obsidian Sanctum, Eye of Eternity,
   Ulduar, Trial of the Crusader, Icecrown Citadel, Ruby Sanctum. */
SET @MAPS := '249,533,615,616,603,649,631,724';

/* Collect the loot IDs of every boss (rank 3) spawned in those maps,
   including their heroic/25-man difficulty entries (10H, 25N, 25H). */
DROP TEMPORARY TABLE IF EXISTS `tmp_boss_lootids`;
CREATE TEMPORARY TABLE `tmp_boss_lootids` (
  `lootid` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`lootid`)
);

-- Base difficulty (10N / 25N depending on spawn)
INSERT IGNORE INTO `tmp_boss_lootids`
SELECT ct.`lootid`
FROM `creature_template` ct
JOIN `creature` c ON c.`id1` = ct.`entry`
WHERE FIND_IN_SET(c.`map`, @MAPS)
  AND ct.`rank` = 3
  AND ct.`lootid` > 0;

-- Difficulty 1 (10H)
INSERT IGNORE INTO `tmp_boss_lootids`
SELECT dt.`lootid`
FROM `creature_template` ct
JOIN `creature` c ON c.`id1` = ct.`entry`
JOIN `creature_template` dt ON dt.`entry` = ct.`difficulty_entry_1`
WHERE FIND_IN_SET(c.`map`, @MAPS)
  AND ct.`rank` = 3
  AND dt.`lootid` > 0;

-- Difficulty 2 (25N)
INSERT IGNORE INTO `tmp_boss_lootids`
SELECT dt.`lootid`
FROM `creature_template` ct
JOIN `creature` c ON c.`id1` = ct.`entry`
JOIN `creature_template` dt ON dt.`entry` = ct.`difficulty_entry_2`
WHERE FIND_IN_SET(c.`map`, @MAPS)
  AND ct.`rank` = 3
  AND dt.`lootid` > 0;

-- Difficulty 3 (25H)
INSERT IGNORE INTO `tmp_boss_lootids`
SELECT dt.`lootid`
FROM `creature_template` ct
JOIN `creature` c ON c.`id1` = ct.`entry`
JOIN `creature_template` dt ON dt.`entry` = ct.`difficulty_entry_3`
WHERE FIND_IN_SET(c.`map`, @MAPS)
  AND ct.`rank` = 3
  AND dt.`lootid` > 0;

/* Idempotent: remove any previous scroll loot rows. */
DELETE FROM `creature_loot_template` WHERE `Item` IN (@DECEPTION, @ILLUSION);

INSERT INTO `creature_loot_template`
  (`Entry`, `Item`, `Reference`, `Chance`, `QuestRequired`, `LootMode`, `GroupId`, `MinCount`, `MaxCount`, `Comment`)
SELECT `lootid`, @DECEPTION, 0, @DECEPTION_CHANCE, 0, 1, 0, 1, 1, 'Scroll of Deception - transmog'
FROM `tmp_boss_lootids`;

INSERT INTO `creature_loot_template`
  (`Entry`, `Item`, `Reference`, `Chance`, `QuestRequired`, `LootMode`, `GroupId`, `MinCount`, `MaxCount`, `Comment`)
SELECT `lootid`, @ILLUSION, 0, @ILLUSION_CHANCE, 0, 1, 0, 1, 1, 'Scroll of Illusion - transmog'
FROM `tmp_boss_lootids`;

DROP TEMPORARY TABLE `tmp_boss_lootids`;

SELECT COUNT(*) AS `scroll_loot_rows`
FROM `creature_loot_template`
WHERE `Item` IN (@DECEPTION, @ILLUSION);
