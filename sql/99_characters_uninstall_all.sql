/* Run in the CHARACTER database: acore_characters.
   Removes all transmog character data.

   WARNING: This deletes all active transmogrifications and all essence
   tracking records. Players will lose their transmog appearances and
   all essences in their bags will become empty.

   Use this only when completely uninstalling the transmog system or
   when you need to reset all transmog state. */

DROP TABLE IF EXISTS `custom_transmogrification`;
DROP TABLE IF EXISTS `essence_tracking`;

SELECT 'Transmog character data removed.' AS `result`;
