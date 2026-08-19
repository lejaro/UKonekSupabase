# Deploy this repo to Vercel

Recommended minimal setup to deploy the static frontend located at `frontend/web`.

1. Import the repository into Vercel (https://vercel.com/new)
2. In the Project Settings during import:
   - **Framework Preset**: Other
   - **Root Directory**: /
   - **Build Command**: (leave empty)
   - **Output Directory**: `frontend/web/html`

Notes:
- The repository contains a static web frontend under `frontend/web`. The site's entry page is `frontend/web/html/index.html`; set the Output Directory to `frontend/web/html` when importing.
- If you need serverless functions, move them into a top-level `api/` directory (Vercel will treat each file as a Serverless Function).
- Supabase-related backend (in `supabase/`) should remain deployed separately (Supabase project). Set required environment variables in Vercel for any client keys used by the frontend.
- Optional: add a root `package.json` and a build step if you later introduce a build tool or framework (React, Next.js, etc.).

If you want, I can:
- Add an `api/` placeholder with an example serverless function
- Add a root `package.json` with a no-op `build` script for Vercel detection
