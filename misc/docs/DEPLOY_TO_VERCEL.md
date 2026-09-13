# Deploy this repo to Vercel

Recommended setup to deploy the U-Konek web frontend.

### Option 1: Monorepo Setup with `web` Root (Recommended)
1. In Vercel Project Settings > General:
   - **Framework Preset**: Other
   - **Root Directory**: `web`
   - **Build Command**: (leave empty / Override: OFF)
   - **Output Directory**: **LEAVE EMPTY / Override: OFF** *(Do NOT set this to `public` or `web/public`, otherwise Vercel drops the `src/` directory and CSS/JS will return 404!)*
2. Vercel will automatically read `web/vercel.json` and serve both `public/` and `src/`.

### Option 2: Root Directory as `/`
If your Vercel project's Root Directory is `/`:
- **Root Directory**: `/`
- **Build Command**: (leave empty / Override: OFF)
- **Output Directory**: **LEAVE EMPTY / Override: OFF** *(Do NOT set this to `web/public`)*
- Vercel will automatically read the root `vercel.json` and route requests to `web/public/` and `web/src/`.

### Why did CSS not load previously?
If **Output Directory** in Vercel settings was set to `web/public`, Vercel only deployed the HTML files inside `web/public` and excluded the `src/css` and `src/js` folders completely. Keeping Output Directory empty ensures the entire web application is deployed.

