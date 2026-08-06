# generate_file — web GUI scaffold

Two pieces, because GitHub Pages only serves static files and can't run
Julia itself:

```
index.html            → static frontend, deploy on GitHub Pages
backend/
  generate_server.jl  → tiny Julia HTTP API, deploy anywhere that runs a process
  Project.toml         → its two dependencies (HTTP, JSON3)
```

The frontend never runs Julia. It shows the `gallery/` file list, lets you
edit/paste source on the left, and POSTs that text to the backend, which
is where your actual Julia logic executes.

## 1. Backend

`generate_server.jl` exposes the logic from `src/generate_file.jl`, but
refactored so it never touches disk — a browser only has the text in
the textarea, not a filesystem path, so `isfile`/`read`/`write` don't
translate. `generate_content(s::AbstractString) -> String` does the same
timestamp-prepend transform, purely in memory.

Run it locally first:

```bash
cd backend
julia --project -e 'using Pkg; Pkg.instantiate()'
julia --project generate_server.jl
# -> generate_file backend listening on 0.0.0.0:8081
```

Quick test:

```bash
curl -X POST http://localhost:8081/generate \
  -H 'Content-Type: application/json' \
  -d '{"content": "println(\"hi\")"}'
```

To put it on the internet, deploy it anywhere that keeps a long-running
process alive — a Julia HTTP.jl server is not "serverless," it needs
somewhere to sit. A few options that have free/cheap tiers:

- **Fly.io** — `fly launch`, which will pick up `backend/Dockerfile` automatically
- **Render.com** — Julia isn't one of Render's native runtimes (Node, Python, Ruby, Go, Rust, Elixir), so choose **Docker** as the Language. Render then builds from `backend/Dockerfile` instead of using build/start command fields. Set:
  - Docker Build Context Directory: `backend`
  - Dockerfile Path: `backend/Dockerfile`
  - Docker Command: leave blank (the Dockerfile's `CMD` already starts the server)
- Any VPS you already have, run under `systemd` or `tmux`/`screen`

Whatever host you pick, note the public URL it gives you (e.g.
`https://your-app.onrender.com`) — you'll need it in step 2. Also update
`ALLOWED_ORIGIN` in `generate_server.jl` from `"*"` to your actual GitHub
Pages origin once you know it, so the API isn't wide open to any site.

## 2. Frontend (GitHub Pages)

Edit the `CONFIG` block near the bottom of `index.html`:

```js
const CONFIG = {
  GITHUB_OWNER:  "your-username",
  GITHUB_REPO:   "your-repo",
  GITHUB_BRANCH: "main",
  GALLERY_PATH:  "gallery",
  BACKEND_URL:   "https://your-backend-host/generate",
};
```

Then either:
- put `index.html` at the repo root and enable Pages → "Deploy from branch" → `/ (root)`, or
- put it in a `docs/` folder and point Pages at `/docs`.

Push, wait a minute for the Pages build, then open
`https://your-username.github.io/your-repo/`.

## What it does

- Top bar lists `.jl` files in `gallery/` (via the public GitHub API — no
  backend needed for this part, it's just static data).
- Clicking a file loads its raw content into the **source** pane.
- You can also just type/paste directly into **source**.
- **Generate** sends that text to the Julia backend and shows the
  timestamped result in **generated**.

## Known limitations

- The GitHub Contents API is unauthenticated here, so it's subject to
  GitHub's public rate limit (60 requests/hour per IP). Fine for a demo
  or low-traffic tool; add a token-based proxy if you outgrow that.
- `ALLOWED_ORIGIN = "*"` in the backend is deliberately permissive for
  getting started — tighten it before sharing the URL widely.