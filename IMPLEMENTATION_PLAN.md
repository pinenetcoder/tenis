# IMPLEMENTATION_PLAN.md — Multi-tenancy + Club Membership

> **Handoff-документ.** Написан так, чтобы новая сессия (или другой разработчик) могла забрать его, прочитать сверху вниз и начать работу без дополнительного контекста.
>
> **Эпик:** перевод платформы Tenis на гибридную модель «клубы + индивидуальные тренеры», с полноценной сущностью игрока, членством и всеми потоками UX присоединения к клубу.
>
> **Горизонт:** 6–10 недель (по 1 milestone в неделю).
>
> **Версия документа:** 1.0 · 2026-04.

---

## Содержание

0. [Как читать этот документ](#0-как-читать-этот-документ)
1. [Цели и не-цели](#1-цели-и-не-цели)
2. [Что уже есть в кодовой базе](#2-что-уже-есть-в-кодовой-базе)
3. [Ключевые архитектурные решения (зафиксированы)](#3-ключевые-архитектурные-решения-зафиксированы)
4. [Milestone-план (7 вех)](#4-milestone-план-7-вех)
5. [M1 — Schema foundation](#m1--schema-foundation)
6. [M2 — Backend RPC + views](#m2--backend-rpc--views)
7. [M3 — Публичная страница клуба + join](#m3--публичная-страница-клуба--join)
8. [M4 — Invite-система](#m4--invite-система)
9. [M5 — Админ-членство (review/remove/merge)](#m5--админ-членство-reviewremove-merge)
10. [M6 — Player profile «Мои клубы»](#m6--player-profile-мои-клубы)
11. [M7 — Интеграция с турниром (soft-prompt)](#m7--интеграция-с-турниром-soft-prompt)
12. [Edge-cases (мастер-чеклист)](#12-edge-cases-мастер-чеклист)
13. [i18n: новые ключи](#13-i18n-новые-ключи)
14. [Стратегия миграции данных](#14-стратегия-миграции-данных)
15. [План тестирования](#15-план-тестирования)
16. [Rollout / feature flags](#16-rollout--feature-flags)
17. [Открытые вопросы (требуют решения продукта)](#17-открытые-вопросы-требуют-решения-продукта)
18. [Быстрый старт для новой сессии](#18-быстрый-старт-для-новой-сессии)

---

## 0. Как читать этот документ

**Если ты открыл этот файл в новой сессии:**

1. Прочитай [секцию 18 — Быстрый старт](#18-быстрый-старт-для-новой-сессии). Это 5-минутный брифинг.
2. Прочитай [`FEATURE_ANALYSIS.md` секция 4](FEATURE_ANALYSIS.md) — архитектурное обоснование этих решений.
3. Прочитай [`CLAUDE.md`](CLAUDE.md) — правила проекта.
4. Прочитай [`supabase/schema.sql`](supabase/schema.sql) — текущая схема БД.
5. Вернись сюда и запускай milestones по порядку (M1 → M7).

**Не делай** в одной PR больше одного milestone. Каждый milestone независимо разворачивается и откатывается.

**Не пропускай** M1 и M2 — это фундамент, без них остальное не соберётся.

---

## 1. Цели и не-цели

### Цели
- **Unified Organization** — клубы и тренеры в одной сущности с `type` enum.
- **Player как first-class** — один человек = одна запись на всю платформу.
- **Membership с ролями и статусами** — явное явление, не автоматическое.
- **Full UX join flow** — страница клуба, invite, self-join, admin review, выход.
- **Migration без потерь** — существующие клубы, турниры, участники перенесены.

### Не-цели (явно отложены за горизонт этого эпика)
- ❌ ELO и rating recalculation (отдельный эпик M8+).
- ❌ Платные подписки / Stripe / взносы.
- ❌ Клубный магазин / членские карты / NFC.
- ❌ Team tournaments (клуб vs клуб).
- ❌ Club-level analytics dashboard.
- ❌ Миграция i18n на отдельные файлы (остаёмся на [`src/i18n/messages.js`](src/i18n/messages.js)).
- ❌ Light theme (отдельный эпик).

---

## 2. Что уже есть в кодовой базе

### 2.1. Релевантные таблицы ([`supabase/schema.sql`](supabase/schema.sql))

| Таблица | Статус | Примечание |
|---|---|---|
| `tournaments` | ✅ | уже имеет `club_id` (не используется) |
| `entries` | ✅ | имеет `user_id` (nullable), `display_name`, `contact` |
| `entry_members` | ✅ | `full_name` — строка (кандидат на `player_id`) |
| `matches`, `match_sets` | ✅ | источник правды для статистики |
| `tournament_admins` | ✅ | роли `owner`, `editor` (роль `counter` декларирована, но не создана) |
| `clubs` | ✅ | будет мигрировано в `organizations` |
| `platform_admins` | ✅ | super-admin |
| `user_profiles` | ✅ | имя + телефон |

### 2.2. Релевантные компоненты и views

| Путь | Зачем |
|---|---|
| [`src/views/PublicTournamentView.vue`](src/views/PublicTournamentView.vue) | добавим soft-prompt «Вступить в клуб» после регистрации (M7) |
| [`src/views/PlayerProfileView.vue`](src/views/PlayerProfileView.vue) | добавим вкладку «Мои клубы» (M6) |
| [`src/views/ClubRegistrationView.vue`](src/views/ClubRegistrationView.vue) | не меняем, но учитываем — клуб после регистрации автоматически становится `organizations` записью |
| [`src/views/SuperAdminDashboardView.vue`](src/views/SuperAdminDashboardView.vue) | обновить SQL: `clubs` → `organizations WHERE type='club'` |
| [`src/views/AdminTournamentView.vue`](src/views/AdminTournamentView.vue) | НЕ трогаем в этом эпике (единственная гигантская view, trigger отдельного эпика декомпозиции) |
| [`src/views/AdminTournamentListView.vue`](src/views/AdminTournamentListView.vue) | фильтр по клубам, если пользователь — владелец клуба |
| [`src/router/index.js`](src/router/index.js) | добавим новые routes (M3, M4, M5) |
| [`src/stores/auth.js`](src/stores/auth.js) | добавим `currentPlayer`, `activeMemberships[]` в state |
| [`src/lib/supabase.js`](src/lib/supabase.js) | не меняем |
| [`src/i18n/messages.js`](src/i18n/messages.js) | пачка новых ключей (см. [секцию 13](#13-i18n-новые-ключи)) |

### 2.3. Существующие RPC, которые мы ПЕРЕиспользуем

- `create_tournament(...)` — **расширяем**, добавляем параметр `p_org_id`.
- `register_entry(...)` — **расширяем**, после создания entry возвращаем `player_id`.
- `add_tournament_admin_by_email(...)` — оставляем без изменений.
- `approve_club`, `reject_club`, `register_club` — оставляем, но внутри перекладываем на `organizations`.

---

## 3. Ключевые архитектурные решения (зафиксированы)

> Эти решения приняты на этапе дизайна. Не пересматриваем их в рамках этого эпика. Если возникает сомнение — уточняем у продукта, но по умолчанию — делаем как здесь.

- **R1.** Клуб и тренер — один тип сущности `organizations` с полем `type enum 'club' | 'coach'`.
- **R2.** Игрок — глобальная сущность. Связь с организацией — через `org_memberships`.
- **R3.** Один игрок может быть в нескольких организациях одновременно. Политика «только один клуб» — на уровне бизнес-логики, не схемы.
- **R4.** Статусы membership: `pending / active / inactive / banned / rejected / expired / pending_payment`.
- **R5.** Роли membership: `member / student / admin / external`.
- **R6.** `contact_hash` — normalize(phone) ∪ normalize(email), SHA-256. Ключ для автосклейки player'ов.
- **R7.** Регистрация на турнир клуба **не создаёт** membership. Это разные решения.
- **R8.** После регистрации на турнир клуба — **мягкий non-blocking промпт** «Вступить в клуб?».
- **R9.** Публичный клуб (auto_approve) — instant join. Закрытый — через admin review.
- **R10.** Invite expires после 30 дней. После expire — только повторная отправка админом.
- **R11.** Soft-delete игрока: имя → «Удалённый игрок», `contact_hash` → null, матчи сохраняются.
- **R12.** Ghost-players (без `user_id`) склеиваются с аккаунтом автоматически при совпадении `contact_hash` во время регистрации.
- **R13.** Publicity игрока: глобальный профиль (имя, avatar, W/L, ELO) — публичный по умолчанию. Контакты — private.
- **R14.** Primary club для игрока — опциональный флаг в `org_memberships.is_primary` (только один `true` на player).

---

## 4. Milestone-план (7 вех)

| # | Название | Длительность | Что отдельно релизуется | Блокирует |
|---|---|---|---|---|
| M1 | Schema foundation | 3 дня | миграция БД, без UI-изменений | всё |
| M2 | Backend RPC + views | 4 дня | RPC готовы, тестируются curl/psql | M3–M7 |
| M3 | Страница клуба + self-join | 5 дней | `/clubs/:slug` живой, можно вступать | M4, M7 |
| M4 | Invite-система | 5 дней | админ отправляет, игрок принимает | M5 |
| M5 | Admin членство (review/remove/merge) | 5 дней | полное управление членами | M6 |
| M6 | Player profile «Мои клубы» | 3 дня | вкладка + empty state | — |
| M7 | Турнирная интеграция (soft-prompt) | 2 дня | promot после регистрации | — |

**Итого:** ~27 рабочих дней = 5–6 недель при 1 разработчике.

---

## M1 — Schema foundation

**Цель:** обновить БД, подготовить сущности. Никаких UI-изменений.

### M1.1. Миграция (одна SQL-миграция, атомарная)

Создать файл [`supabase/migrations/20260501_multitenancy.sql`](supabase/migrations/20260501_multitenancy.sql):

```sql
-- === 1. organizations (объединяет clubs + coach) ===
CREATE TYPE org_type AS ENUM ('club', 'coach');

CREATE TABLE organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text UNIQUE NOT NULL,
  type org_type NOT NULL,
  name text NOT NULL,
  description text,
  logo_url text,
  city text,
  country text,
  owner_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  plan text DEFAULT 'free',
  auto_approve_members boolean DEFAULT true,    -- открытый/закрытый клуб
  is_active boolean DEFAULT true,                -- soft-disable от super-admin
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX idx_org_owner ON organizations(owner_user_id);
CREATE INDEX idx_org_type ON organizations(type);
CREATE TRIGGER set_updated_at BEFORE UPDATE ON organizations
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- === 2. players (глобальная сущность) ===
CREATE TABLE players (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
  display_name text NOT NULL,
  avatar_url text,
  contact_hash text,                -- sha256(normalize(phone|email))
  birth_year int,
  gender text CHECK (gender IN ('male', 'female', 'other')),
  country text,
  merged_into uuid REFERENCES players(id) ON DELETE SET NULL,
  is_deleted boolean DEFAULT false,  -- soft delete
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE UNIQUE INDEX idx_players_contact ON players(contact_hash) WHERE contact_hash IS NOT NULL AND is_deleted = false;
CREATE INDEX idx_players_user ON players(user_id);
CREATE TRIGGER set_updated_at BEFORE UPDATE ON players
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- === 3. org_memberships ===
CREATE TYPE membership_role AS ENUM ('member', 'student', 'admin', 'external');
CREATE TYPE membership_status AS ENUM (
  'pending', 'active', 'inactive', 'banned', 'rejected', 'expired', 'pending_payment'
);
CREATE TYPE membership_visibility AS ENUM ('full', 'stats_only', 'hidden');

CREATE TABLE org_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  role membership_role NOT NULL DEFAULT 'member',
  status membership_status NOT NULL DEFAULT 'pending',
  visibility membership_visibility NOT NULL DEFAULT 'full',
  is_primary boolean DEFAULT false,
  invited_by uuid REFERENCES auth.users(id),
  review_note text,                  -- причина reject/ban
  joined_at timestamptz,             -- NULL пока pending
  expires_at timestamptz,            -- для platных подписок
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(org_id, player_id)
);

CREATE INDEX idx_memberships_org ON org_memberships(org_id);
CREATE INDEX idx_memberships_player ON org_memberships(player_id);
CREATE INDEX idx_memberships_status ON org_memberships(status);
-- Только один is_primary на player:
CREATE UNIQUE INDEX idx_memberships_primary ON org_memberships(player_id)
  WHERE is_primary = true;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON org_memberships
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- === 4. org_invites ===
CREATE TABLE org_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  token text UNIQUE NOT NULL DEFAULT encode(gen_random_bytes(24), 'base64url'),
  contact_email text,
  contact_phone text,
  contact_hash text NOT NULL,
  player_id uuid REFERENCES players(id),       -- если уже есть player
  role membership_role NOT NULL DEFAULT 'member',
  message text,
  invited_by uuid NOT NULL REFERENCES auth.users(id),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'expired', 'revoked')),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '30 days'),
  accepted_at timestamptz,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX idx_invites_token ON org_invites(token);
CREATE INDEX idx_invites_org ON org_invites(org_id);
CREATE INDEX idx_invites_contact ON org_invites(contact_hash);

-- === 5. tournaments: добавить org_id ===
ALTER TABLE tournaments ADD COLUMN org_id uuid REFERENCES organizations(id) ON DELETE RESTRICT;
CREATE INDEX idx_tournaments_org ON tournaments(org_id);

-- === 6. entry_members: добавить player_id ===
ALTER TABLE entry_members ADD COLUMN player_id uuid REFERENCES players(id) ON DELETE SET NULL;
CREATE INDEX idx_entry_members_player ON entry_members(player_id);

-- === 7. RLS policies ===
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE players ENABLE ROW LEVEL SECURITY;
ALTER TABLE org_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE org_invites ENABLE ROW LEVEL SECURITY;

CREATE POLICY "organizations_public_read" ON organizations
  FOR SELECT USING (is_active = true OR auth.uid() = owner_user_id OR is_platform_admin());

CREATE POLICY "organizations_owner_write" ON organizations
  FOR ALL USING (auth.uid() = owner_user_id OR is_platform_admin());

CREATE POLICY "players_public_read" ON players
  FOR SELECT USING (is_deleted = false);

CREATE POLICY "players_self_update" ON players
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "memberships_visible" ON org_memberships
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM players p WHERE p.id = player_id AND p.user_id = auth.uid())
    OR is_org_admin(org_id)
    OR is_platform_admin()
  );

-- (продолжение policies — см. M1.3)

-- === 8. Realtime ===
ALTER PUBLICATION supabase_realtime ADD TABLE organizations, org_memberships, org_invites;
```

### M1.2. Data migration (внутри той же миграции, в отдельном DO-блоке)

```sql
DO $$
DECLARE
  user_rec record;
  new_org_id uuid;
BEGIN
  -- 1. Перенос clubs → organizations
  INSERT INTO organizations (id, slug, type, name, description, logo_url, city, country, owner_user_id, is_active, created_at)
  SELECT id, slug, 'club', name, description, logo_url, city, NULL, owner_id, status = 'active', created_at
  FROM clubs
  WHERE status = 'active';

  -- 2. Для каждого tournament_admin (owner), у которого нет клубной org — создаём personal coach org
  FOR user_rec IN
    SELECT DISTINCT ta.user_id, COALESCE(up.display_name, au.email) as display_name
    FROM tournament_admins ta
    JOIN auth.users au ON au.id = ta.user_id
    LEFT JOIN user_profiles up ON up.user_id = ta.user_id
    WHERE ta.role = 'owner'
      AND NOT EXISTS (SELECT 1 FROM organizations o WHERE o.owner_user_id = ta.user_id)
  LOOP
    INSERT INTO organizations (slug, type, name, owner_user_id)
    VALUES (
      'coach-' || substring(user_rec.user_id::text, 1, 8),
      'coach',
      user_rec.display_name || ' (coach)',
      user_rec.user_id
    ) RETURNING id INTO new_org_id;
  END LOOP;

  -- 3. tournaments.org_id: сначала пытаемся club_id, потом — owner personal coach
  UPDATE tournaments t SET org_id = t.club_id WHERE t.club_id IS NOT NULL;

  UPDATE tournaments t SET org_id = (
    SELECT o.id FROM organizations o
    JOIN tournament_admins ta ON ta.user_id = o.owner_user_id
    WHERE ta.tournament_id = t.id AND ta.role = 'owner'
    LIMIT 1
  ) WHERE t.org_id IS NULL;

  -- 4. Создать players из entry_members (distinct by contact_hash)
  -- Функция normalize_contact определяется в M2
  INSERT INTO players (display_name, contact_hash)
  SELECT DISTINCT ON (e.contact)
    em.full_name,
    encode(digest(regexp_replace(e.contact, '\s|-|\+', '', 'g'), 'sha256'), 'hex')
  FROM entry_members em
  JOIN entries e ON e.id = em.entry_id
  WHERE e.contact IS NOT NULL;

  -- 5. Линкуем entry_members на players
  UPDATE entry_members em SET player_id = p.id
  FROM players p, entries e
  WHERE em.entry_id = e.id
    AND p.contact_hash = encode(digest(regexp_replace(e.contact, '\s|-|\+', '', 'g'), 'sha256'), 'hex');

  -- 6. Post-migration sanity
  ASSERT (SELECT count(*) FROM tournaments WHERE org_id IS NULL) = 0,
    'Some tournaments have no org_id after migration';
END $$;

-- После успешной миграции:
ALTER TABLE tournaments ALTER COLUMN org_id SET NOT NULL;
```

### M1.3. Helper-функции, нужные для RLS

```sql
CREATE OR REPLACE FUNCTION is_org_admin(p_org_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM organizations o
    WHERE o.id = p_org_id AND o.owner_user_id = auth.uid()
  ) OR EXISTS (
    SELECT 1 FROM org_memberships m
    JOIN players p ON p.id = m.player_id
    WHERE m.org_id = p_org_id
      AND m.role = 'admin'
      AND m.status = 'active'
      AND p.user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION normalize_contact(p_contact text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT regexp_replace(lower(trim(p_contact)), '\s|-|\+', '', 'g');
$$;

CREATE OR REPLACE FUNCTION hash_contact(p_contact text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT encode(digest(normalize_contact(p_contact), 'sha256'), 'hex');
$$;
```

### M1.4. Acceptance criteria для M1

- [ ] Миграция применяется на чистой и на существующей БД без ошибок.
- [ ] `SELECT count(*) FROM tournaments WHERE org_id IS NULL` = 0.
- [ ] `SELECT count(*) FROM entry_members WHERE player_id IS NULL` близок к 0 (допустимы edge-cases без contact).
- [ ] Все существующие функции (`generate_bracket`, `register_entry` и т.д.) продолжают работать.
- [ ] `npm run build` проходит без ошибок (frontend не сломан).
- [ ] Нет визуальных изменений в UI.

### M1.5. Rollback

Скрипт `supabase/migrations/20260501_multitenancy_rollback.sql` (на всякий случай):

```sql
DROP TABLE IF EXISTS org_invites CASCADE;
DROP TABLE IF EXISTS org_memberships CASCADE;
ALTER TABLE entry_members DROP COLUMN IF EXISTS player_id;
ALTER TABLE tournaments DROP COLUMN IF EXISTS org_id;
DROP TABLE IF EXISTS players CASCADE;
DROP TABLE IF EXISTS organizations CASCADE;
DROP TYPE IF EXISTS org_type, membership_role, membership_status, membership_visibility CASCADE;
```

---

## M2 — Backend RPC + views

**Цель:** все операции над членством и игроками через RPC. Frontend — только `supabase.rpc()`.

### M2.1. RPC для игроков

```sql
-- Создать/переиспользовать player по contact
CREATE OR REPLACE FUNCTION upsert_player(
  p_display_name text,
  p_contact text,         -- phone or email
  p_user_id uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid;
  v_hash text;
BEGIN
  v_hash := hash_contact(p_contact);

  -- 1. Попытка найти по user_id
  IF p_user_id IS NOT NULL THEN
    SELECT id INTO v_player_id FROM players WHERE user_id = p_user_id AND is_deleted = false LIMIT 1;
    IF v_player_id IS NOT NULL THEN RETURN v_player_id; END IF;
  END IF;

  -- 2. Попытка найти по contact_hash
  SELECT id INTO v_player_id FROM players
    WHERE contact_hash = v_hash AND is_deleted = false LIMIT 1;

  IF v_player_id IS NOT NULL THEN
    -- привязываем user_id, если пришёл
    IF p_user_id IS NOT NULL THEN
      UPDATE players SET user_id = p_user_id WHERE id = v_player_id AND user_id IS NULL;
    END IF;
    RETURN v_player_id;
  END IF;

  -- 3. Создаём нового
  INSERT INTO players (user_id, display_name, contact_hash)
  VALUES (p_user_id, p_display_name, v_hash)
  RETURNING id INTO v_player_id;

  RETURN v_player_id;
END $$;

-- Merge (для дубликатов)
CREATE OR REPLACE FUNCTION merge_players(p_keep uuid, p_drop uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  IF NOT is_platform_admin() THEN RAISE EXCEPTION 'Only platform admin can merge'; END IF;

  UPDATE entry_members SET player_id = p_keep WHERE player_id = p_drop;

  -- Memberships: если в одной org есть оба — оставляем keep, drop удаляем
  DELETE FROM org_memberships
    WHERE player_id = p_drop
      AND org_id IN (SELECT org_id FROM org_memberships WHERE player_id = p_keep);
  UPDATE org_memberships SET player_id = p_keep WHERE player_id = p_drop;

  UPDATE players SET merged_into = p_keep, is_deleted = true WHERE id = p_drop;
END $$;

-- Soft-delete (GDPR)
CREATE OR REPLACE FUNCTION delete_player(p_player_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  -- только сам игрок или super-admin
  IF NOT EXISTS (SELECT 1 FROM players WHERE id = p_player_id AND user_id = auth.uid())
     AND NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  UPDATE players SET
    display_name = 'Удалённый игрок',
    contact_hash = NULL,
    avatar_url = NULL,
    birth_year = NULL,
    user_id = NULL,
    is_deleted = true
  WHERE id = p_player_id;

  UPDATE org_memberships SET status = 'inactive' WHERE player_id = p_player_id;
END $$;
```

### M2.2. RPC для membership

```sql
-- Self-join (открытый клуб)
CREATE OR REPLACE FUNCTION join_organization(p_org_slug text)
RETURNS jsonb  -- { membership_id, status, needs_approval }
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_org organizations%ROWTYPE;
  v_player_id uuid;
  v_existing org_memberships%ROWTYPE;
  v_new_status membership_status;
BEGIN
  SELECT * INTO v_org FROM organizations WHERE slug = p_org_slug AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'Organization not found'; END IF;

  SELECT id INTO v_player_id FROM players WHERE user_id = auth.uid() AND is_deleted = false;
  IF v_player_id IS NULL THEN RAISE EXCEPTION 'Create player profile first'; END IF;

  -- Существующая membership?
  SELECT * INTO v_existing FROM org_memberships WHERE org_id = v_org.id AND player_id = v_player_id;

  IF FOUND THEN
    IF v_existing.status IN ('active', 'pending') THEN
      RETURN jsonb_build_object('membership_id', v_existing.id, 'status', v_existing.status, 'already', true);
    END IF;
    IF v_existing.status = 'banned' THEN
      RAISE EXCEPTION 'You are banned from this club';
    END IF;
    -- inactive / rejected / expired → можно reapply
  END IF;

  v_new_status := CASE WHEN v_org.auto_approve_members THEN 'active' ELSE 'pending' END;

  INSERT INTO org_memberships (org_id, player_id, status, joined_at, role)
  VALUES (v_org.id, v_player_id, v_new_status,
          CASE WHEN v_new_status = 'active' THEN now() ELSE NULL END, 'member')
  ON CONFLICT (org_id, player_id) DO UPDATE SET
    status = v_new_status,
    joined_at = CASE WHEN v_new_status = 'active' THEN now() ELSE NULL END,
    review_note = NULL;

  RETURN jsonb_build_object(
    'status', v_new_status,
    'needs_approval', NOT v_org.auto_approve_members
  );
END $$;

-- Leave
CREATE OR REPLACE FUNCTION leave_organization(p_org_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  UPDATE org_memberships
    SET status = 'inactive', expires_at = now()
    WHERE org_id = p_org_id
      AND player_id = (SELECT id FROM players WHERE user_id = auth.uid() AND is_deleted = false);
END $$;

-- Admin approve pending
CREATE OR REPLACE FUNCTION approve_membership(p_membership_id uuid, p_note text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE v_org_id uuid;
BEGIN
  SELECT org_id INTO v_org_id FROM org_memberships WHERE id = p_membership_id;
  IF NOT is_org_admin(v_org_id) THEN RAISE EXCEPTION 'Forbidden'; END IF;

  UPDATE org_memberships SET
    status = 'active', joined_at = now(), review_note = p_note
  WHERE id = p_membership_id AND status = 'pending';
END $$;

-- Admin reject pending
CREATE OR REPLACE FUNCTION reject_membership(p_membership_id uuid, p_note text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_org_id uuid;
BEGIN
  SELECT org_id INTO v_org_id FROM org_memberships WHERE id = p_membership_id;
  IF NOT is_org_admin(v_org_id) THEN RAISE EXCEPTION 'Forbidden'; END IF;
  UPDATE org_memberships SET status = 'rejected', review_note = p_note WHERE id = p_membership_id;
END $$;

-- Admin remove (soft)
CREATE OR REPLACE FUNCTION remove_membership(p_membership_id uuid, p_ban boolean, p_note text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_org_id uuid;
BEGIN
  SELECT org_id INTO v_org_id FROM org_memberships WHERE id = p_membership_id;
  IF NOT is_org_admin(v_org_id) THEN RAISE EXCEPTION 'Forbidden'; END IF;
  UPDATE org_memberships SET
    status = CASE WHEN p_ban THEN 'banned' ELSE 'inactive' END,
    review_note = p_note,
    expires_at = now()
  WHERE id = p_membership_id;
END $$;

-- Admin direct add
CREATE OR REPLACE FUNCTION admin_add_member(
  p_org_id uuid,
  p_display_name text,
  p_contact text,
  p_role membership_role DEFAULT 'member'
) RETURNS uuid  -- membership_id
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_player_id uuid; v_membership_id uuid;
BEGIN
  IF NOT is_org_admin(p_org_id) THEN RAISE EXCEPTION 'Forbidden'; END IF;
  v_player_id := upsert_player(p_display_name, p_contact, NULL);
  INSERT INTO org_memberships (org_id, player_id, role, status, joined_at, invited_by)
  VALUES (p_org_id, v_player_id, p_role, 'active', now(), auth.uid())
  ON CONFLICT (org_id, player_id) DO UPDATE SET
    status = 'active', joined_at = now(), role = p_role
  RETURNING id INTO v_membership_id;
  RETURN v_membership_id;
END $$;

-- Set primary club
CREATE OR REPLACE FUNCTION set_primary_club(p_org_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_player_id uuid;
BEGIN
  SELECT id INTO v_player_id FROM players WHERE user_id = auth.uid();
  UPDATE org_memberships SET is_primary = false WHERE player_id = v_player_id;
  UPDATE org_memberships SET is_primary = true
    WHERE player_id = v_player_id AND org_id = p_org_id AND status = 'active';
END $$;
```

### M2.3. RPC для invites

```sql
CREATE OR REPLACE FUNCTION create_invite(
  p_org_id uuid,
  p_contact text,
  p_display_name text DEFAULT NULL,
  p_role membership_role DEFAULT 'member',
  p_message text DEFAULT NULL
) RETURNS jsonb  -- { invite_id, token, contact, already_member boolean }
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_hash text; v_player_id uuid; v_email text; v_phone text;
  v_invite_id uuid; v_token text; v_already boolean := false;
BEGIN
  IF NOT is_org_admin(p_org_id) THEN RAISE EXCEPTION 'Forbidden'; END IF;

  v_hash := hash_contact(p_contact);
  IF p_contact ~ '@' THEN v_email := p_contact; ELSE v_phone := p_contact; END IF;

  SELECT id INTO v_player_id FROM players WHERE contact_hash = v_hash AND is_deleted = false;
  IF v_player_id IS NOT NULL THEN
    SELECT true INTO v_already FROM org_memberships
      WHERE org_id = p_org_id AND player_id = v_player_id AND status = 'active';
    IF v_already THEN
      RETURN jsonb_build_object('already_member', true);
    END IF;
  END IF;

  -- Если нет player — создаём ghost
  IF v_player_id IS NULL AND p_display_name IS NOT NULL THEN
    v_player_id := upsert_player(p_display_name, p_contact, NULL);
  END IF;

  INSERT INTO org_invites (org_id, contact_email, contact_phone, contact_hash, player_id, role, message, invited_by)
  VALUES (p_org_id, v_email, v_phone, v_hash, v_player_id, p_role, p_message, auth.uid())
  RETURNING id, token INTO v_invite_id, v_token;

  -- Pending membership
  IF v_player_id IS NOT NULL THEN
    INSERT INTO org_memberships (org_id, player_id, role, status, invited_by)
    VALUES (p_org_id, v_player_id, p_role, 'pending', auth.uid())
    ON CONFLICT (org_id, player_id) DO NOTHING;
  END IF;

  RETURN jsonb_build_object('invite_id', v_invite_id, 'token', v_token, 'already_member', false);
END $$;

CREATE OR REPLACE FUNCTION accept_invite(p_token text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_invite org_invites%ROWTYPE; v_player_id uuid;
BEGIN
  SELECT * INTO v_invite FROM org_invites WHERE token = p_token AND status = 'pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'Invite not found or expired'; END IF;
  IF v_invite.expires_at < now() THEN
    UPDATE org_invites SET status = 'expired' WHERE id = v_invite.id;
    RAISE EXCEPTION 'Invite expired';
  END IF;

  -- Гарантируем что player привязан к текущему user
  SELECT id INTO v_player_id FROM players WHERE user_id = auth.uid();
  IF v_player_id IS NULL THEN
    -- регистрация была через OAuth, player ещё не создан → создаём
    v_player_id := upsert_player(
      COALESCE((SELECT display_name FROM user_profiles WHERE user_id = auth.uid()), 'Игрок'),
      COALESCE(v_invite.contact_email, v_invite.contact_phone),
      auth.uid()
    );
  END IF;

  -- Привязать ghost-player к текущему user, если invite был на ghost
  IF v_invite.player_id IS NOT NULL AND v_invite.player_id != v_player_id THEN
    -- Merge: ghost → настоящий
    PERFORM merge_players(v_player_id, v_invite.player_id);
  END IF;

  UPDATE org_invites SET status = 'accepted', accepted_at = now() WHERE id = v_invite.id;

  INSERT INTO org_memberships (org_id, player_id, role, status, joined_at, invited_by)
  VALUES (v_invite.org_id, v_player_id, v_invite.role, 'active', now(), v_invite.invited_by)
  ON CONFLICT (org_id, player_id) DO UPDATE SET
    status = 'active', joined_at = now(), role = v_invite.role;

  RETURN jsonb_build_object('org_id', v_invite.org_id);
END $$;

CREATE OR REPLACE FUNCTION reject_invite(p_token text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE org_invites SET status = 'rejected' WHERE token = p_token AND status = 'pending';
END $$;

CREATE OR REPLACE FUNCTION revoke_invite(p_invite_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_org_id uuid;
BEGIN
  SELECT org_id INTO v_org_id FROM org_invites WHERE id = p_invite_id;
  IF NOT is_org_admin(v_org_id) THEN RAISE EXCEPTION 'Forbidden'; END IF;
  UPDATE org_invites SET status = 'revoked' WHERE id = p_invite_id;
END $$;

-- Нужна Edge Function или cron для:
CREATE OR REPLACE FUNCTION expire_old_invites() RETURNS void
LANGUAGE sql AS $$
  UPDATE org_invites SET status = 'expired'
    WHERE status = 'pending' AND expires_at < now();
$$;
```

### M2.4. Views для статистики

```sql
CREATE OR REPLACE VIEW v_player_stats_global AS
SELECT
  p.id as player_id,
  p.display_name,
  count(*) FILTER (WHERE m.winner_side = em.slot) as wins,
  count(*) FILTER (WHERE m.winner_side IS NOT NULL AND m.winner_side != em.slot) as losses
FROM players p
LEFT JOIN entry_members em ON em.player_id = p.id
LEFT JOIN entries e ON e.id = em.entry_id
LEFT JOIN matches m ON (m.entry_a_id = e.id OR m.entry_b_id = e.id)
WHERE p.is_deleted = false
GROUP BY p.id, p.display_name;

CREATE OR REPLACE FUNCTION v_player_stats_by_org(p_org_id uuid, p_player_id uuid)
RETURNS TABLE(wins bigint, losses bigint, tournaments_played bigint)
LANGUAGE sql STABLE AS $$
  SELECT
    count(*) FILTER (WHERE m.winner_side = em.slot) as wins,
    count(*) FILTER (WHERE m.winner_side IS NOT NULL AND m.winner_side != em.slot) as losses,
    count(DISTINCT t.id) as tournaments_played
  FROM matches m
  JOIN tournaments t ON t.id = m.tournament_id
  JOIN entries e ON (e.id = m.entry_a_id OR e.id = m.entry_b_id)
  JOIN entry_members em ON em.entry_id = e.id
  WHERE t.org_id = p_org_id AND em.player_id = p_player_id;
$$;
```

### M2.5. Расширить существующие RPC

**`register_entry`** — после создания entry вызывать `upsert_player` и линковать `entry_members.player_id`.

**`create_tournament`** — добавить обязательный параметр `p_org_id`. Если не передан — выставляется personal coach org.

### M2.6. Acceptance для M2

- [ ] Все RPC тестируются через psql / Supabase SQL Editor.
- [ ] Happy path `join_organization` + `leave_organization` + `create_invite` + `accept_invite`.
- [ ] Bancheck: `join_organization` на banned клубе падает с internal exception.
- [ ] Merge-тест: создать 2 player с разным именем, один contact → merge → матчи обоих под keep_id.

---

## M3 — Публичная страница клуба + self-join

**Цель:** живая `/clubs/:slug`, рабочий self-join.

### M3.1. Новые файлы

| Путь | Что |
|---|---|
| [`src/views/ClubPageView.vue`](src/views/ClubPageView.vue) | публичная страница клуба |
| [`src/components/ClubHeader.vue`](src/components/ClubHeader.vue) | hero: логотип, название, город, кнопка «Вступить» |
| [`src/components/ClubTournamentsList.vue`](src/components/ClubTournamentsList.vue) | список турниров клуба |
| [`src/components/ClubMembersPreview.vue`](src/components/ClubMembersPreview.vue) | preview активных членов (top-12 аватаров) |
| [`src/components/JoinClubButton.vue`](src/components/JoinClubButton.vue) | кнопка с логикой (login → join → state) |
| [`src/components/JoinClubModal.vue`](src/components/JoinClubModal.vue) | confirm-модалка (для закрытого клуба) |

### M3.2. Route

В [`src/router/index.js`](src/router/index.js):
```js
{ path: '/clubs/:slug', component: () => import('../views/ClubPageView.vue') }
```

### M3.3. Поведение `JoinClubButton.vue`

```
State 1: not logged in
  → [Войти и вступить]    → redirect to /player/login?redirect=/clubs/:slug&action=join

State 2: logged in, no membership
  → [Вступить в клуб]     → вызов RPC join_organization
    → open club          → "Вы в клубе! ✓"
    → closed club        → "Заявка отправлена, ждите одобрения"
    → banned             → "Доступ ограничен, обратитесь к клубу"

State 3: logged in, membership active
  → [Вы член клуба ★]   → dropdown: Сделать основным / Покинуть клуб

State 4: logged in, membership pending
  → [Заявка на рассмотрении]    → disabled
    мини-текст "Админ уведомлён, мы сообщим, как только одобрят"
```

### M3.4. Auth-guard handling redirect

В [`src/router/index.js`](src/router/index.js) и [`src/stores/auth.js`](src/stores/auth.js): поддержать query `?redirect=...&action=join`. После успешного OAuth — вернуться на /clubs/:slug с автоматическим триггером кнопки «Вступить».

### M3.5. `auth.js` state extension

```js
// Добавить в Pinia auth store:
state: () => ({
  // ... existing
  currentPlayer: null,            // { id, display_name, avatar_url }
  memberships: [],                // [{ org_id, org_slug, role, status, is_primary }]
}),
actions: {
  async loadPlayerContext() {
    if (!this.user) return;
    const { data: player } = await supabase.from('players').select('*')
      .eq('user_id', this.user.id).maybeSingle();
    if (player) {
      this.currentPlayer = player;
      const { data: m } = await supabase.from('org_memberships')
        .select('*, organizations(slug, name, logo_url)')
        .eq('player_id', player.id).eq('status', 'active');
      this.memberships = m ?? [];
    }
  }
}
```

Вызывается после logIn и на старте приложения (если есть session).

### M3.6. Acceptance M3

- [ ] `/clubs/forum-vilnius` рендерится, показывает турниры и превью членов.
- [ ] Кнопка «Вступить» работает для 4 состояний выше.
- [ ] После вступления в открытый клуб видно членство сразу.
- [ ] После подачи заявки в закрытый клуб — видно «на рассмотрении».
- [ ] i18n на ru/en/lt для всех новых строк.

---

## M4 — Invite-система

**Цель:** админ приглашает → игрок принимает.

### M4.1. Новые файлы

| Путь | Что |
|---|---|
| [`src/views/ClubAdminInvitesView.vue`](src/views/ClubAdminInvitesView.vue) | `/admin/clubs/:slug/invites` — список, «создать», revoke |
| [`src/views/InviteAcceptView.vue`](src/views/InviteAcceptView.vue) | `/invites/:token` — landing для приглашённого |
| [`src/components/InviteComposer.vue`](src/components/InviteComposer.vue) | модалка: 3 вкладки (из tournaments / email / phone), роль, сообщение |
| [`src/components/InviteCard.vue`](src/components/InviteCard.vue) | карточка в списке приглашений с действиями |

### M4.2. Routes

```js
{ path: '/admin/clubs/:slug/invites', component: ClubAdminInvitesView, meta: { requiresClubAdmin: true } },
{ path: '/invites/:token', component: InviteAcceptView }
```

### M4.3. InviteComposer: 3 таба

**Tab 1: Из прошлых участников** — `SELECT DISTINCT player_id, display_name FROM entry_members em JOIN entries e ON e.id = em.entry_id JOIN tournaments t ON t.id = e.tournament_id WHERE t.org_id = :org_id AND em.player_id NOT IN (SELECT player_id FROM org_memberships WHERE org_id = :org_id AND status = 'active')`. Чекбоксы, выбор роли, send-all.

**Tab 2: По email** — textarea с email-ами через запятую. Валидация формата.

**Tab 3: По телефону** — то же для телефонов.

Общее сообщение (текстовое поле), одна роль для всех.

### M4.4. Email шаблон (Supabase Edge Function `send-invite`)

Нужна Edge Function:
```
POST /functions/v1/send-invite
{ invite_id: uuid }
```
Читает invite, рендерит email (из шаблона на ru/en/lt в зависимости от locale владельца) и отправляет через Resend/SendGrid. Ссылка в письме: `https://<host>/invites/<token>`.

Шаблон:
```
Тема: Клуб {{club_name}} приглашает вас

Здравствуйте, {{player_name}}!

{{inviter_name}} из клуба {{club_name}} приглашает вас стать {{role_translated}}.

{{#if message}}
Сообщение: "{{message}}"
{{/if}}

[ Принять ]: https://<host>/invites/{{token}}
[ Отклонить ]: https://<host>/invites/{{token}}?action=reject

Приглашение действительно 30 дней.
```

**Отложено на будущее:** Telegram и SMS. В M4 только email.

### M4.5. InviteAcceptView

```
1. На mount: GET org_invites WHERE token = :token (через public RPC get_invite_preview).
   Если not found / expired / revoked → показать соответствующий error.
2. Рендер: логотип клуба, название, город, сообщение, роль.
3. Если ?action=reject в URL → сразу вызываем reject_invite, показываем success.
4. Иначе 2 кнопки:
   [ Принять ]  → если не залогинен → login flow → accept_invite → redirect на /clubs/:slug
   [ Отклонить ] → reject_invite → success screen
5. Button [ Позже ] → просто закрываем, token остаётся валидным до expires_at.
```

### M4.6. Acceptance M4

- [ ] Админ создаёт invite по email, в списке видит status='pending'.
- [ ] Игрок открывает ссылку, принимает → membership.status='active'.
- [ ] Истёкший invite → падает с readable error.
- [ ] Повторный accept того же token — idempotent.
- [ ] Ghost-player склеивается с реальным на accept.

---

## M5 — Admin членство

**Цель:** полное управление членами клуба.

### M5.1. Новые файлы

| Путь | Что |
|---|---|
| [`src/views/ClubAdminLayoutView.vue`](src/views/ClubAdminLayoutView.vue) | обёртка с вкладками (Турниры, Члены, Приглашения, Настройки) |
| [`src/views/ClubAdminMembersView.vue`](src/views/ClubAdminMembersView.vue) | `/admin/clubs/:slug/members` |
| [`src/components/MembersList.vue`](src/components/MembersList.vue) | таблица: аватар, имя, роль, статус, actions |
| [`src/components/PendingApprovalsCard.vue`](src/components/PendingApprovalsCard.vue) | pending-заявки сверху с кнопками approve/reject |
| [`src/components/AddMemberDirectModal.vue`](src/components/AddMemberDirectModal.vue) | поиск player + 1-клик add |
| [`src/components/RemoveMemberModal.vue`](src/components/RemoveMemberModal.vue) | с reason и ban-checkbox |
| [`src/components/PlayerMergeTool.vue`](src/components/PlayerMergeTool.vue) | только для platform-admin: merge дубликатов |

### M5.2. Routes

```js
{ path: '/admin/clubs/:slug', redirect: to => `/admin/clubs/${to.params.slug}/members` },
{ path: '/admin/clubs/:slug/members', component: ClubAdminMembersView, meta: { requiresClubAdmin: true } }
```

### M5.3. requiresClubAdmin guard

В [`src/router/index.js`](src/router/index.js):
```js
router.beforeEach(async (to) => {
  if (to.meta.requiresClubAdmin) {
    const slug = to.params.slug;
    const { data } = await supabase.rpc('is_org_admin_by_slug', { p_slug: slug });
    if (!data) return { path: '/' };
  }
});
```

Нужен RPC `is_org_admin_by_slug(p_slug)` — wrapper над `is_org_admin`.

### M5.4. Acceptance M5

- [ ] Админ видит pending-заявки сверху.
- [ ] Approve / reject работают, уведомления игроку.
- [ ] Add direct → player добавлен с `status='active'`.
- [ ] Remove → `status='inactive'`, ban → `status='banned'`.
- [ ] Platform-admin видит merge-tool и может объединять дубликаты.

---

## M6 — Player profile «Мои клубы»

**Цель:** в профиле игрока — список клубов, управление.

### M6.1. Модификация существующего файла

[`src/views/PlayerProfileView.vue`](src/views/PlayerProfileView.vue) — добавить секцию «Мои клубы».

### M6.2. Новые компоненты

| Путь | Что |
|---|---|
| [`src/components/MyClubsSection.vue`](src/components/MyClubsSection.vue) | список membership + «Найти клубы» |
| [`src/components/MyClubCard.vue`](src/components/MyClubCard.vue) | карточка одной membership |
| [`src/components/NoClubsEmptyState.vue`](src/components/NoClubsEmptyState.vue) | empty state + CTA |
| [`src/components/LeaveClubDialog.vue`](src/components/LeaveClubDialog.vue) | confirm выхода |

### M6.3. Behavior

```
empty state:
  "Вы пока не состоите ни в одном клубе.
   В клубе вы получаете: анонсы, внутренние лиги, клубный рейтинг.
   [ Найти клуб ] [ Посмотреть мои прошлые турниры ]"

with memberships:
  [Logo] Forum Vilnius          ★ основной
         Member since Mar 2026
         [ Покинуть ] [ Перейти в клуб ]
  [Logo] Coach Petrov (coach)
         Student since Jan 2026
         [ Покинуть ] [ Перейти к тренеру ]
```

«Найти клуб» → `/clubs` (листинг, отложен на будущий эпик) ИЛИ `/clubs?near=vilnius` если есть гео. В этом эпике — просто текст «Функция листинга клубов скоро появится» и ссылка на главный тур-лист.

### M6.4. Acceptance M6

- [ ] Empty state для player без memberships.
- [ ] Список membership с правильными бэйджами.
- [ ] «Покинуть» работает + confirm.
- [ ] «Сделать основным» (через dropdown в карточке).

---

## M7 — Турнирная интеграция (soft-prompt)

**Цель:** после регистрации на турнир — non-blocking «Вступить в клуб?».

### M7.1. Модификации

[`src/views/PublicTournamentView.vue`](src/views/PublicTournamentView.vue) — после успешной регистрации:

```vue
<div v-if="registrationSuccess && tournament.org && !isMemberOfOrg(tournament.org_id)"
     class="club-soft-prompt">
  <div class="soft-prompt-logo"><img :src="tournament.org.logo_url" /></div>
  <div class="soft-prompt-body">
    <h4>{{ $t('softPrompt.title', { clubName: tournament.org.name }) }}</h4>
    <p>{{ $t('softPrompt.desc') }}</p>
  </div>
  <div class="soft-prompt-actions">
    <button @click="joinClub">{{ $t('softPrompt.join') }}</button>
    <button @click="dismissPrompt">{{ $t('softPrompt.notNow') }}</button>
  </div>
</div>
```

### M7.2. Dismiss-механика

При клике «Не сейчас» — запись в `localStorage.softPromptDismissed_<org_id> = timestamp`. Повторно не показывать 90 дней.

### M7.3. Acceptance M7

- [ ] Первая регистрация на турнир клуба — prompt появляется.
- [ ] Клик «Не сейчас» — prompt исчезает, не показывается на этом турнире.
- [ ] Игрок уже член клуба — prompt не показывается вообще.

---

## 12. Edge-cases (мастер-чеклист)

Каждый пункт должен быть покрыт либо в RPC, либо в UI. Номера соответствуют edge-case таблице из обсуждения join-flow.

| # | Кейс | Где реализован |
|---|---|---|
| 1 | Дубликат по contact_hash при регистрации | `upsert_player` (M2.1) |
| 2 | Повторное «Вступить», уже member | `join_organization` ON CONFLICT (M2.2) |
| 3 | Повторная подача, уже pending | `join_organization` ранний return |
| 4 | Banned игрок пытается вступить | `join_organization` RAISE EXCEPTION |
| 5 | Expired invite | `accept_invite` check `expires_at`, set `status='expired'` |
| 6 | Invite на email, user регистрируется другим email | M4.5 — accept через token не требует совпадения email |
| 7 | 2 аккаунта у одного человека | `merge_players` (M2.1) + Admin tool M5 |
| 8 | Minor < 18 | валидация в UI регистрации (отдельный эпик, не в этом) |
| 9 | Оплачиваемое членство | отложено за горизонт |
| 10 | Клуб забанен super-admin | `is_active=false` в `organizations` + route guard |
| 11 | Игрок из клуба A в турнире клуба B | M7 soft-prompt только если НЕ член |
| 12 | Invite ждёт, user регистрируется → автолинк | `accept_invite` находит invite по contact_hash matching |
| 13 | Ghost + реальный user совпали | `merge_players` в `accept_invite` |
| 14 | GDPR delete | `delete_player` (M2.1) |
| 15 | Клуб уходит с платформы | `organizations.is_active = false` + export ручной (отложено) |
| 16 | Skill-gated клуб | отложено, M5 не делает проверку уровня |
| 17 | Cancel subscription during active | отложено |
| 18 | Primary club | `set_primary_club` (M2.2) + UI M6 |

---

## 13. i18n: новые ключи

Все добавить в [`src/i18n/messages.js`](src/i18n/messages.js) в 3 локалях (ru, en, lt). Структура:

```js
clubs: {
  page: {
    join: 'Вступить в клуб',
    joinPending: 'Заявка на рассмотрении',
    memberBadge: 'Вы член клуба',
    primaryBadge: 'Основной клуб',
    leaveClub: 'Покинуть клуб',
    setPrimary: 'Сделать основным',
    membersCount: '{count} членов',
    tournamentsList: 'Турниры клуба',
  },
  join: {
    success: 'Добро пожаловать в клуб {clubName}!',
    pending: 'Заявка отправлена. Мы уведомим вас, когда администратор её одобрит.',
    banned: 'Доступ ограничен. Обратитесь к администрации клуба.',
    confirmLeave: 'Покинуть клуб {clubName}? История матчей останется видна клубу.',
  },
  invites: {
    page: {
      title: 'Приглашения в клуб',
      create: 'Отправить приглашение',
      statusPending: 'Ожидает',
      statusAccepted: 'Принято',
      statusRejected: 'Отклонено',
      statusExpired: 'Просрочено',
      revoke: 'Отозвать',
      resend: 'Повторить',
    },
    composer: {
      tabPast: 'Из прошлых участников',
      tabEmail: 'По email',
      tabPhone: 'По телефону',
      selectRole: 'Роль',
      message: 'Сообщение (опционально)',
      send: 'Отправить приглашения',
    },
    accept: {
      title: 'Клуб {clubName} приглашает вас',
      role: 'Роль',
      invitedBy: 'Пригласил',
      accept: 'Принять',
      reject: 'Отклонить',
      later: 'Позже',
      expired: 'Приглашение просрочено. Попросите клуб отправить новое.',
      revoked: 'Приглашение было отозвано.',
      notFound: 'Приглашение не найдено.',
    },
  },
  admin: {
    members: {
      title: 'Члены клуба',
      pendingTitle: 'Ожидают одобрения',
      approve: 'Одобрить',
      reject: 'Отклонить',
      addDirect: 'Добавить напрямую',
      remove: 'Удалить из клуба',
      removeReason: 'Причина (опционально)',
      banPermanent: 'Забанить навсегда',
    },
  },
  profile: {
    myClubs: {
      title: 'Мои клубы',
      empty: 'Вы пока не состоите ни в одном клубе.',
      emptyCta: 'Найти клуб',
      sinceDate: 'Член с {date}',
    },
  },
  softPrompt: {
    title: 'Хотите вступить в клуб {clubName}?',
    desc: 'Получайте анонсы будущих турниров и играйте внутренние лиги.',
    join: 'Вступить',
    notNow: 'Не сейчас',
  },
},
```

---

## 14. Стратегия миграции данных

Миграция в M1 выполняется в одном DO-блоке, атомарно. Но если что-то пойдёт не так:

1. **Staging first.** Применить на стейджинге с копией production-данных.
2. **Backup** перед применением: `pg_dump > backup_pre_multitenancy.sql`.
3. **Acceptance smoke**: после миграции запустить [M1.4](#m14-acceptance-criteria-для-m1).
4. **Roll-forward preferred over rollback.** Если после миграции что-то сломано — чинить, а не откатывать (откат теряет только что заполненные `player_id`).

### Ручные корректировки после M1

- Найти players без display_name — заполнить default из entry_members.
- Найти players с подозрительными contact_hash (коллизии) — отметить для ручного merge.
- Sanity: каждый tournament имеет org_id, каждый entry — player в entry_members.

---

## 15. План тестирования

### Unit
- `upsert_player`: дубликат по hash, новый player, привязка user_id.
- `join_organization`: 4 статуса клуба (open, closed, banned-user, already-active).
- `accept_invite`: expired, valid, ghost-merge.
- `merge_players`: no membership conflicts, duplicate memberships in same org.

### Integration (pg_prove или через Supabase SQL Editor)
- Полный цикл: register_entry → create player → join → leave.
- Invite цикл: create → accept → active membership.
- Tournament с org_id: create → register → entry.player_id linked.

### E2E (Playwright — отдельная задача, не в этом эпике)
- Цикл M3 вручную — должен работать end-to-end.

### Manual QA scenarios

1. Пользователь A создаёт клуб → видит себя в admin членства как owner (через personal coach org migration).
2. Пользователь B регистрируется на турнир клуба A → entry.player_id заполнен.
3. B видит soft-prompt «Вступить», нажимает — получает active membership.
4. A отправляет invite пользователю C по email.
5. C получает email (staging с mailhog), открывает, принимает → active membership.
6. A удаляет C с бан-флагом → C попытка вступить заново получает exception.

---

## 16. Rollout / feature flags

В этом эпике **НЕТ feature flag** — миграция схемы атомарна, откат через rollback.sql.

UI-фичи (M3–M7) можно постепенно включать через:
- Просто deploy новых routes — старые продолжают работать.
- `/clubs/:slug` — новый route, не конкурирует с существующими.
- Soft-prompt (M7) — добавляется к PublicTournamentView, по умолчанию показывается всем. Если нужно a/b-тестирование — обернуть в if с `import.meta.env.VITE_SHOW_CLUB_PROMPT`.

### Production rollout sequence

1. Week 1: M1 + M2 (невидимо).
2. Week 2: M3 (без анонса — dogfooding).
3. Week 3: M4 (дать 1 клубу попробовать).
4. Week 4: M5 + M6 (всё собрано).
5. Week 5: M7 + анонс в блоге + email на клубы.

---

## 17. Открытые вопросы (требуют решения продукта)

> Перед стартом M3 получить ответы. Перед M4 — тоже.

1. **Auto-approve default** для новых клубов? `auto_approve_members = true` (public) или `false` (по согласованию)? **Рекомендую `true`.**
2. **Personal coach org name** — что писать? «Иван Петров (coach)», «Тренер Иван Петров», или только имя? **Рекомендую «Иван Петров»** + пометка «Личный профиль тренера» в UI.
3. **Expose personal coach org публично?** Тренер может не хотеть, чтобы на `/clubs/coach-petrov` был виден список его учеников. **Рекомендую** — personal coach org public **только** если в ней ≥1 турнир создан.
4. **Email provider.** Resend, SendGrid, Postmark? **Рекомендую Resend** (простой API, ru-friendly, бесплатный tier).
5. **Тренер-admin внутри клуба** — в схеме есть role=`admin` в `org_memberships`. Но изначально мы говорили — «тренер-admin = role=admin + тег coach». **Остаётся ли тег?** Рекомендую: ввести `org_memberships.is_coach boolean` в отдельной миграции позже, сейчас обходимся role='admin'.
6. **Invite по телефону** — через SMS или просто храним для будущего? **Рекомендую** — хранить в invite, канал доставки = email (если есть) ИЛИ только в app (если есть user_id). SMS — отдельный эпик.
7. **Локаль email-шаблона** — берём из инвайтящего админа или из получателя (если есть `user_profiles.locale`)? **Рекомендую** — сначала из получателя если известен, иначе из админа.

---

## 18. Быстрый старт для новой сессии

> Если ты — новая сессия или новый разработчик, читай это первым.

**Что это:** handoff-документ для эпика мульти-тенантности платформы Tenis (тур-организация с клубами и тренерами).

**Откуда брать контекст:**
1. [`CLAUDE.md`](CLAUDE.md) — правила проекта, tech stack (Vue 3 + Supabase + Pinia).
2. [`FEATURE_ANALYSIS.md`](FEATURE_ANALYSIS.md), секция 4 — архитектурное обоснование решений.
3. [`supabase/schema.sql`](supabase/schema.sql) — текущая схема БД.
4. Сам этот файл, сверху вниз.

**Что уже решено (не пересматривать):**
- Клуб и тренер = одна сущность `organizations` с полем `type`.
- Игрок — global, один на платформу.
- Membership — явное действие, не автоматическое.
- Полный список в [секции 3](#3-ключевые-архитектурные-решения-зафиксированы).

**С чего начать:**

1. Прочитать [секцию 3](#3-ключевые-архитектурные-решения-зафиксированы) — архитектурные решения.
2. Прочитать [секцию 17](#17-открытые-вопросы-требуют-решения-продукта) — задать вопросы продукту.
3. После получения ответов — начать с [M1](#m1--schema-foundation).

**Порядок milestones (не нарушать):**
- M1 → M2 → M3 → M4 → M5 → M6 → M7.

**Один milestone = одна PR.** Не смешивать.

**Если застрял / не уверен:**
- Уточнить у пользователя (продукта) — не угадывать.
- Проверить edge-case по [секции 12](#12-edge-cases-мастер-чеклист).
- Проверить i18n ключи по [секции 13](#13-i18n-новые-ключи).

**Что НЕ делать (за пределы эпика):**
- ELO, рейтинги, глобальный лидерборд.
- Платные подписки.
- Light theme.
- Декомпозиция AdminTournamentView.vue (отдельный эпик).
- Swiss, double-elim, другие форматы сеток (отдельный эпик).

**Что сделано к моменту написания этого документа:**
- FEATURE_ANALYSIS.md с архитектурой (секция 4).
- feature-analysis.html — интерактивная визуализация.
- Обсуждение UX join flow (в одном из сообщений, сохранить его в MR description для контекста).

**Готов начинать? Открой [M1](#m1--schema-foundation).**

---

## Приложение A. Пример prompt для новой сессии

Вставь этот текст в новую сессию Claude Code:

> Мы реализуем multi-tenancy + club membership в проекте Tenis (Vue 3 + Supabase). Полный план — в `IMPLEMENTATION_PLAN.md` в корне проекта. Прочитай его, потом `FEATURE_ANALYSIS.md` секцию 4, потом `CLAUDE.md`, потом `supabase/schema.sql`. После этого задай мне [вопросы из секции 17](#17-открытые-вопросы-требуют-решения-продукта) по одному через AskUserQuestion. Когда получишь ответы, начни с Milestone M1 — напиши SQL-миграцию и data backfill. Не трогай UI в этом milestone.

---

**Конец документа. Версия 1.0.**
