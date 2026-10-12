# SortBags
Bag sorting for 1.12 and 1.13.<br/>
__IMPORTANT: Use this branch for classic: https://github.com/shirsig/SortBags/tree/retail__<br/>
__IMPORTANT: The folder name must be "SortBags"__<br/>
__IMPORTANT: If you want buttons then get this too: https://github.com/shirsig/Cleanup__

```
/run SortBags() -- Sort bags
/run SortBankBags() -- Sort bank
/run SetSortBagsRightToLeft(Boolean) -- Set sort direction
/run GetSortBagsRightToLeft(): Boolean -- Get sort direction
/run SortBagsDump() -- Print each bag item and the block it sorts into
```

Items of the same kind stay together, with no empty slots inside a block. From the start of the sort:

1. Hearthstone (`hearth`)
2. Mounts (`mount`)
3. Special items (`special`)
4. Keys (`key`)
5. Tools (`tool`)
6. Gear (`gear`): outfit sets, then soulbound, then the rest, by slot
7. Ammo (`ammo`)
8. Potions, then elixirs and flasks (`potion`)
9. Food and drink (`food`)
10. Bandages (`bandage`)
11. Other consumables (`consumable`)
12. Conjured items (`conjured`)
13. Reagents (`reagent`), including soul shards
14. Quest items (`quest`)
15. Herbs (`herb`)
16. Enchanting materials (`enchant`)
17. Other profession materials (`trade`), grouped by bag family
18. Recipes (`recipe`)
19. Everything else (`other`)

Grey junk is not part of that run. It sits at the far end, and the empty slots are between your items and the junk. Changing the sort direction swaps which end that is. Junk that belongs in a specialty bag stays in that bag.

`SortBagsDump()` does nothing while a sort is running. Run it again if a line says `unloaded`.
