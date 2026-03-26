# Tenis Championship App

Vue 3 + Supabase веб-приложение для управления теннисными чемпионатами.

## Возможности

- Главная страница `/` — только вход организатора (Google OAuth)
- Панель `/admin` → `/admin/tournaments`: вкладки «Турниры» и «Настройки», фильтр списка, отдельная страница создания, страница управления турниром; публичная **ссылка** для зрителей
- Публичная страница `/tournaments/:slug` — только по ссылке от организатора: вкладки «Регистрация» и «Сетка», без логина
- Создание турнира (`singles` / `doubles`)
- Роли:
  - `admin` (Google OAuth, полное управление)
  - `spectator` (просмотр и регистрация по расшаренной ссылке)
- Саморегистрация участников с модерацией
- Жеребьёвка `single elimination`:
  - авто-рандом
  - ручной порядок
- Авто-BYE до ближайшей степени 2
- Ведение счёта по сетам (`best_of_3` / `best_of_5`)
- Live-обновления сетки через Supabase Realtime
- Интерфейс: RU / EN / LT

## Стек

- Frontend: Vite, Vue 3, Vue Router, Pinia, Vue I18n
- Backend: Supabase (Postgres, Auth, Realtime, RLS)

## Запуск

1. Установите зависимости:

```bash
npm install
```

2. Скопируйте `.env.example` в `.env` и заполните:

```bash
cp .env.example .env
```

3. Примените SQL из `supabase/schema.sql` в SQL Editor вашего проекта Supabase.

4. Запустите dev-сервер:

```bash
npm run dev
```

## Ключевые SQL-функции

- `register_entry(p_slug, p_entry_type, p_phone_or_email, p_member_one, p_member_two, p_display_name)`
- `generate_bracket(p_tournament_id, p_mode, p_manual_order)`
- `rebuild_bracket(p_tournament_id, p_mode, p_manual_order)`
- `update_match_sets(p_match_id, p_sets)`

## Структура

- `src/views/HomeView.vue` — страница входа организатора
- `src/views/PublicTournamentView.vue` — публичная страница турнира (по ссылке)
- `src/views/AdminLayout.vue` — каркас админки (вкладки, кнопка «Создать турнир»)
- `src/views/AdminTournamentListView.vue` — список турниров с фильтром
- `src/views/AdminTournamentCreateView.vue` — форма создания турнира
- `src/views/AdminSettingsView.vue` — настройки (язык, аккаунт)
- `src/views/AdminTournamentView.vue` — заявки, сетка, счёт, админы, ссылка для зрителей
- `supabase/schema.sql` — схема БД, RLS, функции
