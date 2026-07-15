# CanaBotanica Upgraded Menu System

This package contains a customer menu and an admin dashboard designed to keep the public GoDaddy/Netlify URL unchanged while products and orders are managed from admin.

## Files

- `index.html` - customer menu, product browsing, filtering, cart, and order request form.
- `admin.html` - compact admin dashboard for products, order lifecycle, deleted orders, and publishing.
- `data/products.json` - normalized product source of truth extracted from the supplied PowerPoint deck.
- `data/orders.json` - starter order store for static/local use.
- `assets/config.js` - switch between local mode and Supabase mode.

## Recommended Publishing Flow

1. Deploy this folder to the existing Netlify site that your GoDaddy menu button already points to.
2. Keep the public customer URL stable, for example `https://menuuu-canabotanica.netlify.app/`.
3. Use `admin.html` for product changes.
4. Hide/archive products instead of deleting them.
5. Move unwanted orders to Deleted Orders instead of permanently erasing them.
6. The New Orders badge only counts orders where `status = "new"` and `seen = false`.

## Supabase Mode

For automatic admin-to-customer updates across devices, edit `assets/config.js`:

```js
window.CB_CONFIG = {
  mode: 'supabase',
  supabaseUrl: 'YOUR_SUPABASE_URL',
  supabaseAnonKey: 'YOUR_SUPABASE_ANON_KEY'
};
```

Create two Supabase tables named `products` and `orders`. Use `sku` as the conflict key for products and `id` for orders.

## Local Mode

The included default is local mode. It is useful for review, testing, and demos. Local mode saves edits in the browser used to make the edits; it does not sync across devices until Supabase is configured.

## Compliance Note

Customer-facing descriptions were softened to avoid medical or unsupported effect claims. Verify COAs, license requirements, and live availability before retail use.

