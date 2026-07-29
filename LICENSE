/* Run in the WORLD database: acore_world.
   Completely removes all transmog items and data.

   WARNING: This deletes the four item templates, all boss loot rows,
   and sets Essence bonding back to 0. Players with scrolls or essences
   in their bags will see "Item not found" errors after restart.

   Use this only when completely uninstalling the transmog system. */

-- Remove boss loot rows
DELETE FROM `creature_loot_template`
WHERE `Item` IN (23885, 35517)
  AND `Comment` LIKE '%transmog%';

-- Remove item templates
DELETE FROM `item_template`
WHERE `entry` IN (23885, 35517, 24315, 38567);

SELECT 'Transmog items and boss loot removed from world database.' AS `result`;
