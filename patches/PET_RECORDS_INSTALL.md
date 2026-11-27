# Pet Heist Simulator — Pet identity and size patch

Branch: `fix/pet-hatch-flow`

This patch changes only the pet hatch/save/equip/Bag scripts. It does **not** modify egg pickup, egg transportation, egg placement, or the three-crack trigger.

## Important: these are replacement script sources, not an updated .rbxlx place file

The original place file is large, and the GitHub contents update for the binary place file did not complete. The replacement scripts below are committed as source files in `patches/`; they have not been inserted into `Test5_organized.rbxlx`. Do not assume the live Studio place is fixed until you replace the scripts as listed here.

## Replace these four existing scripts in Studio

Open the `fix/pet-hatch-flow` branch files and copy each complete source into the existing script with the same name:

| Existing Roblox Studio script | Replacement source in this branch |
|---|---|
| `ServerScriptService/EggServerScripts/PetHatchServer` | `patches/PetHatchServer.lua` |
| `ServerScriptService/PetServerScripts/PetToolServer` | `patches/PetToolServer.lua` |
| `StarterGui/PetBackpackGui/PetBackpackController` | `patches/PetBackpackController.lua` |
| `StarterPlayer/StarterPlayerScripts/PetHatchAnimation` | `patches/PetHatchAnimation.lua` |

Keep your existing `PetConfig`, pet models, `World1/PetTools` templates, and GUI objects. The scripts expect the current names and hierarchy.

## How the new system works

1. The server rolls the pet name, rarity, **scale**, and size tier once when the egg hatches.
2. The reveal animation receives that same scale. It does not roll a second size.
3. When the owner animation finishes, the client sends `HatchAnimationDone`; the server awards the record. An 18-second server timeout remains as a failsafe.
4. Each pet has a unique `PetId`. The DataStore saves `PetRecords` and also writes the old `Pets` count map for compatibility.
5. Old count-only saves are migrated into unique records with scale `1.0` / tier `Normal`, because their previous random size was never stored and cannot be reconstructed.
6. The custom Pet Bag shows only pets not currently in the hotbar/hand. Equip uses the pet's `PetId`; the server checks that ID exists in the player's saved/replicated records.
7. Unequip-all removes the pet Tools from Backpack and Character. Individual equipped pets are represented by their hotbar Tool and are hidden from the Pet Bag while equipped.

## Attributes on each pet record and Tool

- `PetId` — unique ID for that individual pet
- `PetName` — exact pet model/template name
- `Rarity` — pet rarity
- `PetScale` — rolled scale, 0.2–2.5
- `SizeTier` — Tiny, Normal, Big, or Giant
- `Mutation` — defaults to `None`
- `CreatedAt` — Unix timestamp
- `IsPetTool` — true only on the equipped Tool

The current Tool templates are Handle-and-weld assemblies, so the replacement equip script scales their parts, meshes, and weld offsets around the Handle. A template that has a Model descendant instead uses `Model:ScaleTo()`.

## Test checklist in Studio

- Test with a fresh player and hatch an egg.
- Confirm one record appears in `player.PetRecords` and the count increases in `player.PetInventory`.
- Confirm `PetScale` and `SizeTier` are set once and the reveal size matches that record.
- Equip from the Pet Bag; confirm the Tool has the same `PetId`, `PetScale`, and `SizeTier`.
- Confirm that equipped pet no longer appears in the Pet Bag.
- Unequip all, then confirm the pet returns to the Bag with the same ID and scale.
- Leave and rejoin; confirm the same record, scale, and tier load again.
- Test a legacy save with only `Pets`; confirm its pet counts are preserved.

## Safety note

Test first in a private Studio session with DataStore API access configured. The new script intentionally keeps the existing DataStore name `PlayerPets_v1` and migrates old count data rather than resetting it. Keep a backup copy of your place and test data before publishing.
