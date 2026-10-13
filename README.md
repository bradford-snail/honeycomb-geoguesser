# Pin It

A GeoGuessr-style browser game for a custom map. A screenshot flashes for under a second, players pin the spot on the map before the timer runs out, and every finished game lands on a live public leaderboard.

Players don't need an account; they just enter a name. The game is hosted free on GitHub Pages, and Supabase provides the database, image storage, and live leaderboard.

## Repository layout

```
.
├── .github/workflows/deploy.yml   Publishes site/ to GitHub Pages on every push to main
├── site/                          The public game (the only folder that gets deployed)
│   ├── index.html
│   ├── app.css
│   ├── mapview.js                 Zoomable, pannable map shared with the admin tool
│   └── config.example.js          Template for your Supabase settings
├── admin/                         Admin tool, run on your own computer (never deployed)
│   ├── index.html
│   └── admin.css
└── supabase/
    └── schema.sql                 Tables, security rules, and server-side scoring
```

`site/config.js` holds your Supabase settings. It's ignored by git. GitHub Actions generates it during deployment, and you create your own copy for running things locally.

## Setup

### 1. Set up Supabase
1. Create a free project at supabase.com.
2. Open **SQL Editor > New query**, paste in all of `supabase/schema.sql`, and click **Run**.
3. Go to **Authentication > Sign In / Providers** and turn on **Allow anonymous sign-ins**. Turning on CAPTCHA protection on the same page (Cloudflare Turnstile is free) is also recommended.
4. Create your admin account:
   1. Go to **Authentication > Users > Add user**. Enter an email and password, and check "Auto confirm user."
   2. Copy the new user's **UID**.
   3. In the SQL Editor, run the following, replacing the placeholder with the UID:
      ```sql
      insert into public.admins (user_id) values ('PASTE-THE-UID-HERE');
      ```
5. From **Project Settings > API**, copy the **Project URL** and the **anon public** key. You'll need both in the next steps.

### 2. Create the GitHub repository
Create a new repository on GitHub. It needs to be public for GitHub Pages on a free plan. Then push these files to it:

```bash
cd pin-it
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/YOUR-USERNAME/YOUR-REPO.git
git push -u origin main
```

If you'd rather not use the command line, GitHub Desktop works too. Avoid uploading the files by drag-and-drop on github.com: the `.github` folder is hidden on most computers and is easy to leave out, and without it nothing deploys.

### 3. Connect GitHub to Supabase and turn on Pages
1. In the repository, go to **Settings > Secrets and variables > Actions > Variables** and add two repository variables:
   - `SUPABASE_URL`: your Project URL
   - `SUPABASE_ANON_KEY`: your anon public key
2. Go to **Settings > Pages** and set **Source** to **GitHub Actions**.
3. Go to **Actions > Deploy game to GitHub Pages** and click **Run workflow**. This is only needed the first time; after that, every push to `main` that changes `site/` deploys automatically.

The game is now live at `https://YOUR-USERNAME.github.io/YOUR-REPO/`.

### 4. Run the admin tool and add your content
The admin tool runs on your computer, using the files in your copy of the repository.

1. Copy `site/config.example.js` to `site/config.js` and fill in the same two values. You can also set `gameUrl` to your live game's address.
2. From the repository folder, start a local server:
   ```bash
   npx serve .
   ```
   This needs Node.js installed. Python works too: `python3 -m http.server 3000`.
3. Open `http://localhost:3000/admin/` and sign in with your admin account.
4. Upload the map image, add locations (choose a screenshot, click its exact spot on the map, and save), and adjust the settings.

Changes appear in the live game immediately, with no redeploy needed. Content lives in Supabase, not in the repository.

To test the game locally before pushing, open `http://localhost:3000/site/` while the server is running.

## Making changes
- **Game look and behavior:** edit the files in `site/` and push to `main`. The site redeploys in about a minute.
- **Map, locations, and settings:** use the admin tool. No code changes needed.
- **Database changes:** edit `supabase/schema.sql` for reference, and run the specific change in the Supabase SQL Editor. Re-running the whole file on an existing project will fail, because the tables already exist.

The repository is public, so anyone can read the admin tool's code. That's fine: the database rules reject every admin action from accounts that aren't on your admins list.

## How scoring stays fair
- **Answers stay hidden.** Players never receive the correct coordinates for a location until after they've guessed it.
- **Scores are calculated on the server.** The browser only sends where the pin was placed. A player can't send a made-up score.
- **The timer is enforced on the server too.** A guess that arrives well after time runs out scores 0.
- **Scores can only be written one way.** Each player's best score is updated only by the server when they finish a game. Players can't write to the leaderboard directly.
- **Games are rate-limited** to 40 per player per hour.

A few limits remain. A determined player could screenshot the flash with their own tools, or clear their browser to get a fresh identity and a new leaderboard entry. Players who replay often will also start to memorize locations, so adding more locations keeps the game fresh.

## Moderation
The **Leaderboard** section of the admin tool (`admin/`) lists players. **Remove** deletes an entry, which is useful for inappropriate names.

## Costs
Supabase's free tier includes 500 MB of database storage, 1 GB of file storage, and 2 GB of bandwidth per month. Screenshots are the main cost. Saving them as JPG or WebP around 1600px wide keeps each one in the low hundreds of KB.

Free projects pause after a week with no activity. You can resume one from the dashboard, or upgrade if the game gets steady traffic.
