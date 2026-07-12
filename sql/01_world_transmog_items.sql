/* Run in the WORLD database: acore_world. */
/* Warmane/client-known entries. The local core has no custom spell 38165,
   therefore spell 7420 is retained only as the item-use trigger. */
DROP TEMPORARY TABLE IF EXISTS `tmp_scroll_transmog_item`;

DROP TEMPORARY TABLE IF EXISTS `tmp_scroll_wotlk`;
CREATE TEMPORARY TABLE `tmp_scroll_wotlk` AS
SELECT * FROM `item_template` WHERE `entry`=38766 LIMIT 1;

DELETE FROM `item_template` WHERE `entry` IN (23885,35517,24315,38567);

UPDATE `tmp_scroll_wotlk` SET `entry`=23885, `name`='Scroll of Deception', `displayid`=6270, `Quality`=4, `description`='Use: Replicates the appearance of an item into an Essence.';
INSERT INTO `item_template` SELECT * FROM `tmp_scroll_wotlk`;

UPDATE `tmp_scroll_wotlk` SET `entry`=35517, `name`='Scroll of Illusion', `displayid`=1096, `Quality`=4, `description`='Use: Replicates a Legendary appearance into an Essence.';
INSERT INTO `item_template` SELECT * FROM `tmp_scroll_wotlk`;

UPDATE `tmp_scroll_wotlk` SET `entry`=24315, `name`='Scroll of Purification', `displayid`=1301, `Quality`=4, `description`='Use: Restores the original appearance of an item.';
INSERT INTO `item_template` SELECT * FROM `tmp_scroll_wotlk`;

/* Stackable=1: each Essence tracks its own source item per item GUID.
   Stacked essences would lose their per-GUID metadata. */
UPDATE `tmp_scroll_wotlk` SET `entry`=38567, `name`='Essence of Placeholder', `displayid`=5563, `Quality`=4, `MaxCount`=0, `Stackable`=1, `FlagsExtra`=0, `description`='Use: Apply the stored appearance to a compatible item.';
INSERT INTO `item_template` SELECT * FROM `tmp_scroll_wotlk`;

DROP TEMPORARY TABLE `tmp_scroll_wotlk`;

/* Spell 7420 (Enchant Chest - Minor Health) restricts client-side targeting to
   chest items via Spell.dbc EquippedItemInventoryTypeMask. Spell 47147
   ("Test On Use Enchant") has EquippedItemClass=-1 (targets any item) and an
   EMPTY description in Spell.dbc, so no misleading "DESTROYED" tooltip text
   appears. All real validation stays in the Lua script. */
UPDATE `item_template`
SET `spellid_1`=47147, `spelltrigger_1`=0, `spellcategory_1`=0,
    `spellcooldown_1`=-1, `spellcategorycooldown_1`=-1
WHERE `entry` IN (23885,35517,24315,38567);

/* Remove the temporary custom IDs after switching the Lua script. */
DELETE FROM `item_template` WHERE `entry` IN (60001,60002,60003,60004,60005);

SELECT `entry`, `name`, `displayid`, `Quality`
FROM `item_template`
WHERE `entry` IN (23885,35517,24315,38567)
ORDER BY `entry`;
