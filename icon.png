/* Run in the WORLD database: acore_world.
   Removes all transmog scroll loot from raid bosses.

   Use this if you switch to DROP_MODE = "onkill" or "off" in the Lua script,
   or if you want to adjust the loot setup before re-running 03_world_boss_loot.sql.

   This is safe to run multiple times. */

DELETE FROM `creature_loot_template`
WHERE `Item` IN (23885, 35517)
  AND `Comment` LIKE '%transmog%';

SELECT COUNT(*) AS `scroll_loot_rows_remaining`
FROM `creature_loot_template`
WHERE `Item` IN (23885, 35517);
