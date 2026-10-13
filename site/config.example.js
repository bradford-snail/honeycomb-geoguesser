// Local development: copy this file to config.js and fill in your values.
// On GitHub Pages, config.js is generated automatically from repository variables
// (see .github/workflows/deploy.yml), so you never need to commit it.
//
// Find both values in Supabase → Project Settings → API Keys.
// The publishable key (starts with sb_publishable_) is designed to be public;
// the database rules protect everything.
window.PINIT_CONFIG = {
  supabaseUrl: "https://YOUR-PROJECT.supabase.co",
  supabaseKey: "sb_publishable_...",
  // Optional: the live game's address, used by the admin tool's "Open the game" link
  gameUrl: ""
};
