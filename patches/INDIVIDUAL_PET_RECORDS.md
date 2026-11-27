# Individual Pet Records — integration notes

This branch now includes a data helper for the next pet-system migration.

## Record schema

Each owned pet is a record keyed by a unique `PetId`:

- `PetName`, `Rarity`
- `PetScale` (0.2–2.5), `SizeTier`
- `Mutation` (defaults to `None`)
- `Attributes` (extensible per-pet values)
- `CreatedAt`

## Important migration limitation

The current PlayerPets_v1 data only stores counts by pet name. It never stored the original scale for existing pets, so their old exact sizes cannot be reconstructed. The helper migrates those legacy copies as scale 1 / Normal. New hatch records must roll a scale once on the server and save it immediately.

## Required wiring before this is live

1. Add this file as `ReplicatedStorage/Config/PetInstanceData`.
2. Change PetHatchServer profile data to hold `PetRecords`; load via `MigrateLegacy`, and save `PetRecords` alongside a compatibility `Pets` count map.
3. On hatch, server-roll `PetConfig.RollPetScale()`, create one record with `PetInstanceData.New`, save it, and replicate its PetId and attributes.
4. Clone the matching pet Tool and set all attributes from the record. Apply the same `PetScale` to its pet model using `PetConfig.ApplyPetScale`.
5. Change PetBackpackController equip/unequip requests from pet name to PetId. PetToolServer must validate that exact PetId belongs to the player, and equip/unequip by PetId rather than matching pet names.
6. Rebuild the inventory cards from individual records. Continue deriving count badges from `CountByName` for existing collection UI.

Do not deploy this helper alone: until steps 2–6 are wired into the existing scripts, the running game will continue using the old count-only inventory.
