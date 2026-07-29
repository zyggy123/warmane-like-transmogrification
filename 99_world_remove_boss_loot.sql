/* Run in the WORLD database: acore_world.
   Choose how the transmog scrolls bind.

   Bonding values: 0 = no binding (tradable / AH), 1 = Bind on Pickup.

   The ESSENCE (38567) must always stay Bind on Pickup: its stored appearance
   is tracked per owner, so a traded Essence would not work for the recipient.
   Both variants below therefore force the Essence to BoP.

   Pick ONE variant, uncomment it, and run this file. Default = tradable. */

/* ── Variant A: TRADABLE scrolls (default) ─────────────────────────────
   Scrolls can be traded and put on the Auction House. */
UPDATE `item_template` SET `bonding` = 0 WHERE `entry` IN (23885, 35517, 24315);

/* ── Variant B: SOULBOUND scrolls ──────────────────────────────────────
   Scrolls bind on pickup; whoever loots them must use them. */
-- UPDATE `item_template` SET `bonding` = 1 WHERE `entry` IN (23885, 35517, 24315);

/* Essence: always Bind on Pickup (see note above). */
UPDATE `item_template` SET `bonding` = 1 WHERE `entry` = 38567;

SELECT `entry`, `name`, `bonding` FROM `item_template`
WHERE `entry` IN (23885, 35517, 24315, 38567) ORDER BY `entry`;
