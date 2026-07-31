-- Richer food taxonomy (Kibble, Wet food, Treat, Meat, Fish, Vegetable,
-- Fruit, Dairy & egg, Grains, Supplement, Other). Legacy values stay valid so
-- old rows keep decoding; the app maps meal→kibble and addIn→other on read.
alter table public.products drop constraint if exists products_category_check;
alter table public.products add constraint products_category_check
  check (category in ('kibble','wet','treat','meat','fish','vegetable','fruit',
                      'dairy','grain','supplement','other','meal','addIn'));
alter table public.products alter column category set default 'other';
