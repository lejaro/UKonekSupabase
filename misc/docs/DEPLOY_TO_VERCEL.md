# Deploy this repo to Vercel

Recommended setup to deploy the U-Konek web frontend.

### Option 1: Standard Monorepo Setup (Recommended)
1. Import the repository in Vercel (https://vercel.com/new).
2. In Project Settings:
   - **Framework Preset**: Other
   - **Root Directory**: `web`
   - **Build Command**: (leave empty)
   - **Output Directory**: (leave empty)
3. Vercel will automatically read `web/vercel.json` and route `/` to `public/index.html`.

### Option 2: Root Directory Setup
If you prefer to leave Root Directory as `/`:
- Leave Root Directory as `/`
- Vercel will automatically read the root `vercel.json` which proxies `/` and assets to `web/`.

