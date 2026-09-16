# Trivia

Live site: [swestdahl.github.io/trivia](https://swestdahl.github.io/trivia/)

A customizable, self-paced party trivia game with team photos, automatic scoring, a live leaderboard, and a shared Bonus Photos album.

## Architecture

- Next.js static export hosted by GitHub Pages
- Supabase Postgres for quiz data, teams, answers, and scores
- Supabase Storage for team and party photos
- Supabase passwordless authentication for the host dashboard

## Setup

1. Create a Supabase project.
2. Run `supabase/schema.sql` in its SQL editor.
3. Copy `.env.example` to `.env.local` and add the project URL and anon key.
4. Run `pnpm install` and `pnpm dev`.
5. Set `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` in the Pages workflow. These are public browser credentials; never add a service-role key.
6. In the repository Pages settings, choose **GitHub Actions** as the publishing source.

The first person who signs into `/admin/` and claims the controls becomes the administrator.
