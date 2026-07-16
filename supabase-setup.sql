-- CanaBotanica live menu setup
-- Run this once in Supabase SQL Editor, then deploy index.html and admin.html to Netlify.

create extension if not exists pgcrypto;

create table if not exists public.menu_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

insert into public.menu_settings (key, value)
values ('admin_access_key', 'b5c0fb526a444791d4943c647cc1b0a8')
on conflict (key) do nothing;

create table if not exists public.menu_products (
  sku text primary key,
  product jsonb not null,
  sort_order integer not null default 9999,
  active boolean not null default true,
  hidden boolean not null default false,
  stock_status text not null default 'active',
  featured boolean not null default false,
  published_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists menu_products_public_idx
on public.menu_products (active, hidden, stock_status, sort_order);

create or replace view public.public_products as
select
  sku,
  sort_order,
  product
from public.menu_products
where active is true
  and hidden is false
  and coalesce(stock_status, 'active') not in ('hidden', 'inactive', 'archived')
order by sort_order asc, sku asc;

create table if not exists public.menu_orders (
  id uuid primary key default gen_random_uuid(),
  submitted_at timestamptz not null default now(),
  status text not null default 'new',
  seen boolean not null default false,
  first_name text,
  last_name text,
  customer_name text,
  phone text,
  email text,
  retailer_name text,
  retailer_address text,
  retailer_link text,
  license_number text,
  license_expiration text,
  order_date text,
  notes text,
  subtotal text,
  total_saving text,
  item_count integer,
  items_text text,
  order_text text,
  client_json jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.menu_order_items (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.menu_orders(id) on delete cascade,
  line_number integer,
  sku text,
  product_name text,
  category text,
  section text,
  format text,
  thc text,
  case_quantity integer,
  case_units integer,
  special_unit_price numeric,
  msrp_unit_price numeric,
  special_case_total numeric,
  msrp_case_total numeric,
  savings_per_case numeric,
  line_total numeric,
  line_text text,
  product_snapshot jsonb,
  created_at timestamptz not null default now()
);

create or replace function public._menu_admin_allowed(p_access_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.menu_settings
    where key = 'admin_access_key'
      and value = coalesce(p_access_key, '')
  );
$$;

create or replace function public.admin_publish_products(p_access_key text, p_products jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  published_count integer := 0;
begin
  if not public._menu_admin_allowed(p_access_key) then
    raise exception 'Invalid admin access key';
  end if;

  if jsonb_typeof(p_products) <> 'array' then
    raise exception 'p_products must be a JSON array';
  end if;

  for item in select * from jsonb_array_elements(p_products)
  loop
    insert into public.menu_products (
      sku,
      product,
      sort_order,
      active,
      hidden,
      stock_status,
      featured,
      published_at,
      updated_at
    )
    values (
      item->>'sku',
      coalesce(item->'product', '{}'::jsonb),
      coalesce((item->>'sort_order')::integer, 9999),
      coalesce((item->>'active')::boolean, true),
      coalesce((item->>'hidden')::boolean, false),
      coalesce(item->>'stock_status', 'active'),
      coalesce((item->>'featured')::boolean, false),
      now(),
      now()
    )
    on conflict (sku) do update set
      product = excluded.product,
      sort_order = excluded.sort_order,
      active = excluded.active,
      hidden = excluded.hidden,
      stock_status = excluded.stock_status,
      featured = excluded.featured,
      published_at = excluded.published_at,
      updated_at = now();

    if coalesce((item->>'active')::boolean, true)
      and not coalesce((item->>'hidden')::boolean, false)
      and coalesce(item->>'stock_status', 'active') not in ('hidden', 'inactive', 'archived') then
      published_count := published_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'received', jsonb_array_length(p_products),
    'published', published_count,
    'published_at', now()
  );
end;
$$;

create or replace function public.admin_products_feed(p_access_key text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select case
    when not public._menu_admin_allowed(p_access_key) then
      jsonb_build_object('products', '[]'::jsonb, 'error', 'Invalid admin access key')
    else
      jsonb_build_object(
        'products',
        coalesce(
          jsonb_agg(
            jsonb_build_object(
              'sku', sku,
              'sort_order', sort_order,
              'active', active,
              'hidden', hidden,
              'stock_status', stock_status,
              'featured', featured,
              'published_at', published_at,
              'updated_at', updated_at,
              'product', product
            )
            order by sort_order asc, sku asc
          ),
          '[]'::jsonb
        )
      )
    end
  from public.menu_products;
$$;

create or replace function public.submit_order(p_order jsonb, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  new_order_id uuid;
  item jsonb;
begin
  insert into public.menu_orders (
    submitted_at,
    status,
    seen,
    first_name,
    last_name,
    customer_name,
    phone,
    email,
    retailer_name,
    retailer_address,
    retailer_link,
    license_number,
    license_expiration,
    order_date,
    notes,
    subtotal,
    total_saving,
    item_count,
    items_text,
    order_text,
    client_json
  )
  values (
    coalesce((p_order->>'submitted_at')::timestamptz, now()),
    coalesce(p_order->>'status', 'new'),
    coalesce((p_order->>'seen')::boolean, false),
    p_order->>'first_name',
    p_order->>'last_name',
    p_order->>'customer_name',
    p_order->>'phone',
    p_order->>'email',
    p_order->>'retailer_name',
    p_order->>'retailer_address',
    p_order->>'retailer_link',
    p_order->>'license_number',
    p_order->>'license_expiration',
    p_order->>'order_date',
    p_order->>'notes',
    p_order->>'subtotal',
    p_order->>'total_saving',
    nullif(p_order->>'item_count', '')::integer,
    p_order->>'items_text',
    p_order->>'order_text',
    p_order->'client_json'
  )
  returning id into new_order_id;

  if jsonb_typeof(p_items) = 'array' then
    for item in select * from jsonb_array_elements(p_items)
    loop
      insert into public.menu_order_items (
        order_id,
        line_number,
        sku,
        product_name,
        category,
        section,
        format,
        thc,
        case_quantity,
        case_units,
        special_unit_price,
        msrp_unit_price,
        special_case_total,
        msrp_case_total,
        savings_per_case,
        line_total,
        line_text,
        product_snapshot
      )
      values (
        new_order_id,
        nullif(item->>'line_number', '')::integer,
        item->>'sku',
        item->>'product_name',
        item->>'category',
        item->>'section',
        item->>'format',
        item->>'thc',
        nullif(item->>'case_quantity', '')::integer,
        nullif(item->>'case_units', '')::integer,
        nullif(item->>'special_unit_price', '')::numeric,
        nullif(item->>'msrp_unit_price', '')::numeric,
        nullif(item->>'special_case_total', '')::numeric,
        nullif(item->>'msrp_case_total', '')::numeric,
        nullif(item->>'savings_per_case', '')::numeric,
        nullif(item->>'line_total', '')::numeric,
        item->>'line_text',
        item->'product_snapshot'
      );
    end loop;
  end if;

  return jsonb_build_object('ok', true, 'order_id', new_order_id);
end;
$$;

create or replace function public.admin_order_feed(p_access_key text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select case
    when not public._menu_admin_allowed(p_access_key) then
      jsonb_build_object('orders', '[]'::jsonb, 'error', 'Invalid admin access key')
    else
      jsonb_build_object(
        'orders',
        coalesce(
          jsonb_agg(
            jsonb_build_object(
              'id', o.id,
              'submitted_at', o.submitted_at,
              'status', o.status,
              'seen', o.seen,
              'first_name', o.first_name,
              'last_name', o.last_name,
              'customer_name', o.customer_name,
              'phone', o.phone,
              'email', o.email,
              'retailer_name', o.retailer_name,
              'retailer_address', o.retailer_address,
              'retailer_link', o.retailer_link,
              'license_number', o.license_number,
              'license_expiration', o.license_expiration,
              'order_date', o.order_date,
              'notes', o.notes,
              'subtotal', o.subtotal,
              'total_saving', o.total_saving,
              'item_count', o.item_count,
              'items_text', o.items_text,
              'order_text', o.order_text,
              'items', coalesce((
                select jsonb_agg(to_jsonb(i) order by i.line_number)
                from public.menu_order_items i
                where i.order_id = o.id
              ), '[]'::jsonb)
            )
            order by o.submitted_at desc
          ),
          '[]'::jsonb
        )
      )
    end
  from public.menu_orders o;
$$;

create or replace function public.admin_update_order_status(
  p_access_key text,
  p_order_id text,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public._menu_admin_allowed(p_access_key) then
    raise exception 'Invalid admin access key';
  end if;

  update public.menu_orders
  set
    status = lower(coalesce(p_status, status)),
    seen = case when lower(coalesce(p_status, status)) = 'new' then false else true end,
    deleted_at = case when lower(coalesce(p_status, status)) = 'deleted' then now() else deleted_at end,
    updated_at = now()
  where id = p_order_id::uuid;

  return jsonb_build_object('ok', true, 'order_id', p_order_id, 'status', lower(p_status));
end;
$$;

grant usage on schema public to anon;
grant select on public.public_products to anon;
grant execute on function public.submit_order(jsonb, jsonb) to anon;
grant execute on function public.admin_products_feed(text) to anon;
grant execute on function public.admin_order_feed(text) to anon;
grant execute on function public.admin_publish_products(text, jsonb) to anon;
grant execute on function public.admin_update_order_status(text, text, text) to anon;
