/* Run this file in the CHARACTER database only (acore_characters). */

/* Active transmogrifications: one row per transmogrified item GUID. */
CREATE TABLE IF NOT EXISTS `custom_transmogrification` (
  `GUID` INT UNSIGNED NOT NULL,
  `FakeEntry` INT UNSIGNED NOT NULL,
  `Owner` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`GUID`),
  KEY `idx_custom_transmog_owner` (`Owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

/* Metadata for each Essence item: which appearance it stores and the
   source item's class/subclass/inventory type for compatibility checks. */
CREATE TABLE IF NOT EXISTS `essence_tracking` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `essence_item_id` INT UNSIGNED NOT NULL,
  `original_item_name` VARCHAR(255) NOT NULL,
  `owner_guid` INT UNSIGNED NOT NULL,
  `appearance_entry` INT UNSIGNED NOT NULL,
  `source_class` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `source_subclass` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `source_inventory_type` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_essence_item` (`essence_item_id`),
  KEY `idx_essence_owner` (`owner_guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SELECT 'Character transmog tables installed.' AS `result`;
