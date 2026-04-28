-- ============================================================
--  ServiceNow-style Customer Care Database
--  Schema: users, categories, incidents, tasks, resolutions
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─── USERS ───────────────────────────────────────────────────
CREATE TABLE users (
    user_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username      VARCHAR(60)  NOT NULL UNIQUE,
    full_name     VARCHAR(120) NOT NULL,
    email         VARCHAR(150) NOT NULL UNIQUE,
    phone         VARCHAR(30),
    role          VARCHAR(40)  NOT NULL DEFAULT 'customer',   -- customer | agent | manager
    department    VARCHAR(80),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ─── CATEGORIES ──────────────────────────────────────────────
CREATE TABLE categories (
    category_id   SERIAL PRIMARY KEY,
    name          VARCHAR(80)  NOT NULL,
    parent_id     INT REFERENCES categories(category_id),
    description   TEXT
);

-- ─── PRODUCTS (electronics catalogue) ───────────────────────
CREATE TABLE products (
    product_id    SERIAL PRIMARY KEY,
    sku           VARCHAR(40)  NOT NULL UNIQUE,
    name          VARCHAR(120) NOT NULL,
    brand         VARCHAR(60),
    category_id   INT REFERENCES categories(category_id),
    model_number  VARCHAR(80),
    release_year  SMALLINT,
    warranty_years SMALLINT DEFAULT 1,
    description   TEXT
);

-- ─── INCIDENTS (ServiceNow INC-style) ────────────────────────
CREATE TABLE incidents (
    incident_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    number             VARCHAR(20)  NOT NULL UNIQUE,          -- INC0001234
    short_description  VARCHAR(255) NOT NULL,
    description        TEXT,
    category_id        INT  REFERENCES categories(category_id),
    product_id         INT  REFERENCES products(product_id),
    caller_id          UUID REFERENCES users(user_id),
    assigned_to        UUID REFERENCES users(user_id),
    priority           SMALLINT NOT NULL DEFAULT 3            -- 1=Critical 2=High 3=Medium 4=Low
                        CHECK (priority BETWEEN 1 AND 4),
    state              VARCHAR(30) NOT NULL DEFAULT 'New'
                        CHECK (state IN ('New','In Progress','On Hold','Resolved','Closed','Cancelled')),
    impact             VARCHAR(20) DEFAULT 'Medium'
                        CHECK (impact IN ('High','Medium','Low')),
    urgency            VARCHAR(20) DEFAULT 'Medium'
                        CHECK (urgency IN ('High','Medium','Low')),
    opened_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at        TIMESTAMPTZ,
    closed_at          TIMESTAMPTZ,
    sla_due            TIMESTAMPTZ,
    resolution_code    VARCHAR(60),
    close_notes        TEXT
);

-- ─── WORK NOTES / JOURNAL ────────────────────────────────────
CREATE TABLE work_notes (
    note_id       SERIAL PRIMARY KEY,
    incident_id   UUID NOT NULL REFERENCES incidents(incident_id) ON DELETE CASCADE,
    author_id     UUID NOT NULL REFERENCES users(user_id),
    note_type     VARCHAR(20) NOT NULL DEFAULT 'work_note'    -- work_note | customer_update
                   CHECK (note_type IN ('work_note','customer_update')),
    body          TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── RESOLUTIONS ─────────────────────────────────────────────
CREATE TABLE resolutions (
    resolution_id   SERIAL PRIMARY KEY,
    incident_id     UUID NOT NULL UNIQUE REFERENCES incidents(incident_id) ON DELETE CASCADE,
    resolved_by     UUID NOT NULL REFERENCES users(user_id),
    resolution_code VARCHAR(60) NOT NULL,
    root_cause      TEXT,
    steps_taken     TEXT NOT NULL,
    kb_article      VARCHAR(30),                              -- KB0001234 reference
    customer_confirmed BOOLEAN DEFAULT FALSE,
    resolved_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── KNOWLEDGE BASE ARTICLES ─────────────────────────────────
CREATE TABLE kb_articles (
    article_id    SERIAL PRIMARY KEY,
    number        VARCHAR(20) NOT NULL UNIQUE,               -- KB0001234
    title         VARCHAR(255) NOT NULL,
    category_id   INT REFERENCES categories(category_id),
    body          TEXT NOT NULL,
    author_id     UUID REFERENCES users(user_id),
    views         INT DEFAULT 0,
    helpful_votes INT DEFAULT 0,
    published_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ─── INDEXES ─────────────────────────────────────────────────
CREATE INDEX idx_incidents_state      ON incidents(state);
CREATE INDEX idx_incidents_priority   ON incidents(priority);
CREATE INDEX idx_incidents_caller     ON incidents(caller_id);
CREATE INDEX idx_incidents_assigned   ON incidents(assigned_to);
CREATE INDEX idx_incidents_product    ON incidents(product_id);
CREATE INDEX idx_incidents_opened     ON incidents(opened_at);
CREATE INDEX idx_work_notes_incident  ON work_notes(incident_id);
CREATE INDEX idx_resolutions_incident ON resolutions(incident_id);

-- ─── USEFUL VIEW ─────────────────────────────────────────────
CREATE VIEW v_incident_summary AS
SELECT
    i.number,
    i.short_description,
    c.name          AS category,
    p.name          AS product,
    p.brand         AS brand,
    caller.full_name AS caller,
    agent.full_name  AS agent,
    i.priority,
    i.state,
    i.impact,
    i.urgency,
    i.opened_at,
    i.resolved_at,
    r.resolution_code,
    r.kb_article,
    r.customer_confirmed
FROM incidents i
LEFT JOIN categories c  ON c.category_id = i.category_id
LEFT JOIN products   p  ON p.product_id  = i.product_id
LEFT JOIN users   caller ON caller.user_id = i.caller_id
LEFT JOIN users   agent  ON agent.user_id  = i.assigned_to
LEFT JOIN resolutions r  ON r.incident_id  = i.incident_id;