# Shotgun — campus ride board

A ride board for students who live on campus. Drivers post trips and open seats, riders request a seat, and the driver approves. Contact details unlock only for approved riders, and everyone splits the gas fairly.

## Features

- **Campus-only sign-in.** One-time email link, restricted to your campus email domain. No passwords.
- **Seat requests with approval.** Riders request a seat with a short message; drivers approve or decline.
- **Sealed contact details.** A driver's phone or handle is visible only to riders they approved.
- **Ride requests too.** Students without a car post where they need to go, and drivers offer to take them.
- **Live board.** New rides and approvals show up without refreshing.
- **Trip types.** Weekend trips, airport runs, home for break, errand runs, concerts and events.
- **Gas split calculator** with tolls, round trips, and a "driver rides free" option.
- Night-drive design with an animated hero, light and dark themes, works on phones.

## How privacy and encryption work

| Layer | What protects it |
|---|---|
| Who can sign in | Supabase email magic links, checked against your campus domain in the page **and** in the database rules |
| Who can read rides | Postgres row level security: only signed-in campus accounts |
| Who can read contact details | Row level security on `ride_contacts`: only the ride's owner and riders they approved |
| Data in transit | HTTPS (GitHub Pages and Supabase both enforce it) |
| Data at rest | Supabase encrypts the database at rest |

The Supabase **anon key** in `config.js` is designed to be public. It can only do what the row level security rules in `supabase/schema.sql` allow, so it's safe to commit. Never put the **service_role** key in this repo.

## Setup (about 15 minutes)

### 1. Create the database
1. Make a free account at [supabase.com](https://supabase.com) and create a new project.
2. Open **SQL Editor → New query**, paste all of `supabase/schema.sql`, and click **Run**.
   - If your campus email isn't `@ucsc.edu`, change `ucsc.edu` in the `is_campus()` function first.

### 2. Turn on email sign-in
1. Go to **Authentication → Sign In / Providers** and make sure **Email** is enabled.
2. Go to **Authentication → URL Configuration**. Set **Site URL** to your GitHub Pages address, e.g. `https://<username>.github.io/shotgun/`, and add the same address under **Redirect URLs**.
3. Supabase's built-in email sender is rate-limited and meant for testing. Before inviting lots of students, connect your own SMTP provider under **Authentication → Emails → SMTP Settings**.

### 3. Connect the site
Open `config.js` and paste in your **Project URL** and **anon public key** from **Project Settings → API**. Set `CAMPUS_DOMAIN` and `CAMPUS_NAME`.

### 4. Publish on GitHub Pages
1. Push this folder to a GitHub repo (or upload the files on github.com).
2. **Settings → Pages → Deploy from a branch**, choose `main` and `/ (root)`, save.
3. Your site goes live at `https://<username>.github.io/<repo>/` in a minute or two.

Without `config.js` filled in, the site runs in **demo mode** with sample rides saved only in your browser, so you can try it out first.

## Files

```
index.html            the whole app (HTML, CSS, JS)
config.js             your Supabase URL, anon key, and campus domain
supabase/schema.sql   tables, security rules, and live-update setup
```

## Tech

Plain HTML, CSS, and JavaScript with [supabase-js](https://github.com/supabase/supabase-js) v2 from a CDN. No build step. Fonts: Chakra Petch and IBM Plex Sans.

## Before launch

- Have a few friends test sign-in, posting, requesting, and approving.
- Consider adding a "report a post" option and a short code of conduct.
- Check with your campus about any rules for student-run services.
