# Tennis Championship App

## Overview

Web-application for organizing tennis tournaments with single-elimination brackets, live scoring, and real-time updates. Supports singles and doubles categories with public spectator links.

## Tech Stack

- **Frontend:** Vue 3 (Composition API, `<script setup>`) + Vue Router 4 + Pinia 3
- **Backend:** Supabase (PostgreSQL, Auth, Realtime)
- **Auth:** Google OAuth via Supabase (admins + players)
- **i18n:** Vue I18n (ru/en/lt), default locale `ru`, stored in `localStorage` key `champ_locale`
- **Build:** Vite 7
- **Styling:** Custom vanilla CSS with design tokens (no Tailwind/SCSS), dark theme support

## Project Structure

```
src/
  components/
    BracketBoard.vue          # Main bracket visualization
    BracketMatchCard.vue      # Individual match card in bracket
    InfiniteCanvas.vue        # Zoom/pan canvas for bracket rendering
    LanguageSwitcher.vue      # RU/EN/LT locale selector
    LiveScoreViewerModal.vue  # Read-only live score display (spectator)
    LiveScoringModal.vue      # Point-by-point scoring input (admin)
    RegistrationForm.vue      # Public player registration form
    ScoreEditor.vue           # Final set score editing
  i18n/
    index.js                  # Vue I18n config
    messages.js               # All translation strings (~30K)
  lib/
    supabase.js               # Supabase client init
    useTennisScoring.js       # Tennis scoring composable (points/games/sets/tiebreaks/undo)
    entryDisplay.js           # Player name display helper
    shareLink.js              # Tournament link generation
  router/
    index.js                  # Route definitions + auth guard
  stores/
    auth.js                   # Pinia auth store (user, session, playerProfile, Google OAuth)
  views/
    HomeView.vue              # Admin login page
    AdminLayout.vue           # Admin wrapper with nav
    AdminTournamentListView.vue
    AdminTournamentCreateView.vue
    AdminTournamentView.vue   # Main admin page (5 tabs: Entries, Bracket, Scores, Admins, Settings) - LARGEST FILE
    AdminSettingsView.vue     # User settings
    PlayerLoginView.vue       # Player login page (Google OAuth)
    PlayerLayout.vue          # Player area wrapper
    PlayerProfileView.vue     # Player profile + tournament history
    PublicTournamentView.vue  # Public tournament page (registration + bracket)
  App.vue                     # Root component
  main.js                     # App entry point
  styles.css                  # Global styles (~42K)
supabase/
  schema.sql                  # Full database schema with RLS, functions, triggers
```

## Routes

| Path | View | Auth |
|------|------|------|
| `/` | HomeView | No (redirects to `/admin/tournaments` if logged in) |
| `/tournaments/:slug` | PublicTournamentView | No |
| `/player/login` | PlayerLoginView | No |
| `/player/profile` | PlayerProfileView | Yes |
| `/admin/tournaments` | AdminTournamentListView | Yes |
| `/admin/tournaments/new` | AdminTournamentCreateView | Yes |
| `/admin/tournaments/:id` | AdminTournamentView | Yes |
| `/admin/settings` | AdminSettingsView | Yes |

## Database (Supabase PostgreSQL)

### Key Tables

- **player_profiles** - player accounts linked to auth.users (display_name, phone, email, avatar_url)
- **tournaments** - name, slug, category (singles/doubles), status (draft/registration_open/closed/in_progress/completed), set_format, draw_mode
- **tournament_admins** - roles: owner, editor, counter (`counter` can only run live scoring)
- **entries** - player registrations with approval status (pending/approved/rejected), seed_order, optional user_id link
- **entry_members** - individual player names (for doubles)
- **matches** - bracket matches linked via `next_match_id` + `next_slot`, match_status
- **match_sets** - set scores per match
- **bracket_versions** - bracket snapshots for undo
- **live_scores** - real-time point-by-point scoring state with JSON state, history, and optimistic revision

### Key PL/pgSQL Functions

- `create_tournament()`, `register_entry()`
- `generate_bracket()`, `rebuild_bracket()` - single-elimination bracket generation
- `update_match_sets()` - save scores + auto-propagate winner
- `swap_bracket_slots()`, `apply_bracket_layout()` - manual bracket arrangement
- `form_random_pairs()`, `form_manual_pairs()`, `split_pairs()` - doubles pairing
- `start_live_match()`, `record_point()`, `stop_live_match()` - live scoring lifecycle and point entry
- `add_tournament_admin_by_email()` - co-organizer management

### Security

- RLS enabled on all tables
- `is_tournament_admin()` function for access checks
- Public read for published tournaments, admin write for organizers

### Realtime

Tables `tournaments`, `entries`, `matches`, `match_sets`, `tournament_admins`, `live_scores` are in `supabase_realtime` publication.

## Key Architecture Patterns

- **Bracket:** Canvas-based (`InfiniteCanvas.vue`) with zoom/pan. Matches linked as tree via `next_match_id`/`next_slot`. Winner auto-propagates via DB trigger.
- **Live Scoring:** `useTennisScoring.js` composable formats live state and mirrors tennis scoring concepts (points, games, sets, tiebreaks, deuce/advantage, undo history). Authoritative point application runs in Supabase RPC and state syncs via Supabase Realtime.
- **Doubles:** Two modes - `pre_agreed` (register as pair) and `pick_random` (register solo, admin forms pairs).
- **Tournaments accessed by slug** (user-friendly URLs for public sharing).

## Dev Setup

```bash
# Required: .env with VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
npm install
npm run dev      # http://localhost:5173
npm run build    # Production build to dist/
```

## General Rules

- Always answer, provide progress updates, and write implementation plans in Russian unless the user explicitly asks for another language.
- This is primarily a TypeScript project. Always use TypeScript (not JavaScript) for new files and maintain strict typing. Check for build errors (`npm run build`) after making changes.

## UI/Frontend Development

- When modifying UI components, never remove existing elements (selects, dropdowns, inputs) unless explicitly asked. Always verify the rendered output preserves all original interactive elements after refactoring.
- Before making multi-file UI changes, list all interactive elements in the affected components. After changes, confirm none were removed or altered unintentionally.

## Database

- Before referencing database columns or tables, always read the current schema (`supabase/schema.sql` or migration files) to confirm they exist. Never assume column names.
- When writing Supabase RPC calls, verify function signatures against the schema before using them.

## Conventions

- All components use Vue 3 `<script setup>` syntax
- State management via Pinia (single `auth` store)
- DB logic lives in PL/pgSQL functions, frontend calls them via `supabase.rpc()`
- i18n keys structured as `section.subsection.key` (e.g., `tournament.status.draft`)
- No CSS framework - all styles in `styles.css` with CSS custom properties
