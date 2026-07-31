-- Guaranteed-analysis panel per portion (grams), matching the app's Product
-- model: crude protein, crude fat, crude fiber, moisture. Nullable — older
-- rows and quick adds simply don't have them.
alter table public.products
  add column if not exists protein_g  numeric(7,1),
  add column if not exists fat_g      numeric(7,1),
  add column if not exists fiber_g    numeric(7,1),
  add column if not exists moisture_g numeric(7,1);
