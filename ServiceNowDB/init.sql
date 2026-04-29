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


-- ============================================================
--  Seed Data – ServiceNow Electronics Customer Care
-- ============================================================

-- ─── CATEGORIES ──────────────────────────────────────────────
INSERT INTO categories (category_id, name, description) VALUES
  (1,  'Electronics',            'All electronic hardware and devices'),
  (2,  'Laptops & Computers',    'Laptop, desktop and workstation issues'),
  (3,  'Mobile Devices',         'Smartphones and tablets'),
  (4,  'Printers & Scanners',    'Printing and scanning devices'),
  (5,  'Networking Equipment',   'Routers, switches, access points'),
  (6,  'Audio & Video',          'Headphones, speakers, monitors, TVs'),
  (7,  'Wearables',              'Smart watches and fitness trackers'),
  (8,  'Smart Home',             'Smart speakers, hubs, IoT devices'),
  (9,  'Gaming',                 'Consoles, controllers, accessories'),
  (10, 'Software / Firmware',    'OS, drivers, and firmware updates');

-- set parent
UPDATE categories SET parent_id = 1 WHERE category_id IN (2,3,4,5,6,7,8,9,10);

-- ─── USERS ───────────────────────────────────────────────────
INSERT INTO users (user_id, username, full_name, email, phone, role, department) VALUES
  ('a1000000-0000-0000-0000-000000000001','jsmith',    'John Smith',     'jsmith@acme.com',       '+1-555-0101','customer','Finance'),
  ('a1000000-0000-0000-0000-000000000002','mjones',    'Mary Jones',     'mjones@acme.com',       '+1-555-0102','customer','Operations'),
  ('a1000000-0000-0000-0000-000000000003','rlee',      'Robert Lee',     'rlee@acme.com',         '+1-555-0103','customer','Marketing'),
  ('a1000000-0000-0000-0000-000000000004','akim',      'Alice Kim',      'akim@acme.com',         '+1-555-0104','customer','HR'),
  ('a1000000-0000-0000-0000-000000000005','bpatel',    'Bob Patel',      'bpatel@acme.com',       '+1-555-0105','customer','Legal'),
  ('a1000000-0000-0000-0000-000000000006','schan',     'Sara Chan',      'schan@acme.com',        '+1-555-0106','customer','Engineering'),
  ('a1000000-0000-0000-0000-000000000007','dwilson',   'David Wilson',   'dwilson@acme.com',      '+1-555-0107','customer','Sales'),
  ('a1000000-0000-0000-0000-000000000008','lmartinez', 'Laura Martinez', 'lmartinez@acme.com',    '+1-555-0108','customer','Procurement'),
  -- Agents
  ('b2000000-0000-0000-0000-000000000001','agent_emma',  'Emma Thompson',  'e.thompson@support.com','+1-555-0201','agent','IT Support'),
  ('b2000000-0000-0000-0000-000000000002','agent_kai',   'Kai Nakamura',   'k.nakamura@support.com','+1-555-0202','agent','IT Support'),
  ('b2000000-0000-0000-0000-000000000003','agent_priya', 'Priya Sharma',   'p.sharma@support.com',  '+1-555-0203','agent','IT Support'),
  -- Manager
  ('c3000000-0000-0000-0000-000000000001','mgr_tom',     'Tom Brennan',    't.brennan@support.com', '+1-555-0301','manager','IT Support');

-- ─── PRODUCTS (Electronics) ───────────────────────────────────
INSERT INTO products (sku, name, brand, category_id, model_number, release_year, warranty_years, description) VALUES
  ('LAP-DEL-001','Dell XPS 15 Laptop',             'Dell',       2, 'XPS-9530',     2023, 2, '15.6" OLED, Intel Core i9, 32 GB RAM, 1 TB SSD'),
  ('LAP-APL-001','Apple MacBook Pro 14"',          'Apple',      2, 'MK183LL/A',    2023, 1, 'M3 Pro chip, 18 GB unified memory, 512 GB SSD'),
  ('LAP-LEN-001','Lenovo ThinkPad X1 Carbon',      'Lenovo',     2, '21HM000BUS',   2023, 3, '14" IPS, Intel Core i7, 16 GB RAM, 512 GB SSD'),
  ('MOB-SAM-001','Samsung Galaxy S24 Ultra',       'Samsung',    3, 'SM-S928BZKGEUB',2024,1, '6.8" QHD+, 12 GB RAM, 256 GB, 200 MP camera'),
  ('MOB-APL-001','Apple iPhone 15 Pro',            'Apple',      3, 'MTQJ3LL/A',    2023, 1, '6.1" Super Retina XDR, A17 Pro, 256 GB'),
  ('MOB-GOG-001','Google Pixel 8 Pro',             'Google',     3, 'G1MNW',         2023, 3, '6.7" LTPO OLED, Tensor G3, 12 GB RAM'),
  ('PRN-HP-001', 'HP LaserJet Pro M404dn',         'HP',         4, 'W1A53A',        2022, 1, 'Mono laser, 40 ppm, duplex, Ethernet'),
  ('PRN-EPS-001','Epson EcoTank ET-4850',          'Epson',      4, 'C11CJ29201',    2021, 1, 'Inkjet, 4-colour, WiFi, ADF scanner'),
  ('NET-CIS-001','Cisco Meraki MX68',              'Cisco',      5, 'MX68-HW',       2022, 5, 'Cloud-managed security appliance, 450 Mbps'),
  ('NET-UBQ-001','Ubiquiti UniFi Dream Machine Pro','Ubiquiti',  5, 'UDM-PRO',       2021, 1, 'All-in-one gateway, 10G SFP+'),
  ('AUD-SON-001','Sony WH-1000XM5 Headphones',    'Sony',       6, 'WH1000XM5/B',   2022, 1, 'Over-ear ANC, 30h battery, LDAC'),
  ('MON-LG-001', 'LG UltraWide 34" Monitor',      'LG',         6, '34WN80C-B',     2022, 3, '3440x1440 IPS, USB-C 96W, HDR10'),
  ('WER-APL-001','Apple Watch Series 9',           'Apple',      7, 'MR9F3LL/A',     2023, 1, '45mm, GPS+Cellular, Always-on Retina'),
  ('WER-SAM-001','Samsung Galaxy Watch 6 Classic', 'Samsung',    7, 'SM-R960NZKAXAA',2023, 1, '47mm, Wear OS, BioActive sensor'),
  ('SMH-AMZ-001','Amazon Echo Show 10',            'Amazon',     8, 'B07VHZ41L8',    2021, 1, '10" HD display, 360° motion, Alexa'),
  ('GAM-SON-001','Sony PlayStation 5',             'Sony',       9, 'CFI-1215A01X',  2022, 1, '4K UHD Blu-ray, 825 GB SSD, DualSense'),
  ('GAM-MSF-001','Microsoft Xbox Series X',        'Microsoft',  9, 'RRT-00001',     2020, 1, '4K 120fps, 1 TB NVMe SSD, Quick Resume');

-- ─── INCIDENTS ───────────────────────────────────────────────
INSERT INTO incidents
  (incident_id, number, short_description, description,
   category_id, product_id,
   caller_id, assigned_to,
   priority, state, impact, urgency,
   opened_at, resolved_at, closed_at, sla_due,
   resolution_code, close_notes)
VALUES

-- INC0000001 – Dell XPS overheating (Resolved)
('e0000001-0000-0000-0000-000000000001',
 'INC0000001',
 'Dell XPS 15 shuts down unexpectedly due to overheating',
 'User reports that the laptop shuts down after 20-30 minutes of use. CPU temperature reaches 98°C under moderate load. Thermal paste may need replacement. Vents appear partially blocked.',
 2, 1,
 'a1000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000001',
 2,'Resolved','High','High',
 NOW()-INTERVAL '10 days', NOW()-INTERVAL '8 days', NOW()-INTERVAL '7 days',
 NOW()-INTERVAL '9 days',
 'Hardware Repair','Thermal paste replaced and fan cleaned. Issue resolved.'),

-- INC0000002 – MacBook Pro battery drain (Resolved)
('e0000002-0000-0000-0000-000000000002',
 'INC0000002',
 'MacBook Pro 14 battery draining from 100% to 0% in 3 hours',
 'User states battery life has degraded significantly over the past 2 weeks. Battery health shows 71% in System Information. Expected life is 8+ hours.',
 2, 2,
 'a1000000-0000-0000-0000-000000000002','b2000000-0000-0000-0000-000000000002',
 3,'Resolved','Medium','Medium',
 NOW()-INTERVAL '15 days', NOW()-INTERVAL '12 days', NOW()-INTERVAL '11 days',
 NOW()-INTERVAL '13 days',
 'Hardware Replacement','Battery replaced under warranty via Apple Authorised Service.'),

-- INC0000003 – Samsung Galaxy S24 Ultra screen cracked (In Progress)
('e0000003-0000-0000-0000-000000000003',
 'INC0000003',
 'Samsung Galaxy S24 Ultra display cracked after drop',
 'Device was dropped from approximately 1 metre. Display shows large crack across top-right quadrant with touch unresponsive in that area. Requesting screen replacement.',
 3, 4,
 'a1000000-0000-0000-0000-000000000003','b2000000-0000-0000-0000-000000000003',
 3,'In Progress','Medium','Medium',
 NOW()-INTERVAL '3 days', NULL, NULL,
 NOW()+INTERVAL '2 days',
 NULL, NULL),

-- INC0000004 – iPhone 15 Pro not connecting to corporate WiFi (Resolved)
('e0000004-0000-0000-0000-000000000004',
 'INC0000004',
 'iPhone 15 Pro unable to connect to corporate WPA2-Enterprise WiFi',
 'After iOS 17.3 update the device no longer connects to the corporate SSID. Error: "Cannot join this network." Other devices on same iOS version connect fine. Certificate-based auth suspected.',
 3, 5,
 'a1000000-0000-0000-0000-000000000004','b2000000-0000-0000-0000-000000000001',
 2,'Resolved','High','High',
 NOW()-INTERVAL '6 days', NOW()-INTERVAL '5 days', NOW()-INTERVAL '4 days',
 NOW()-INTERVAL '5 days 12 hours',
 'Configuration Change','MDM certificate re-pushed via Jamf. Device can now join corporate SSID.'),

-- INC0000005 – HP LaserJet paper jam (Resolved)
('e0000005-0000-0000-0000-000000000005',
 'INC0000005',
 'HP LaserJet Pro M404dn recurring paper jam in Tray 2',
 'Paper jams occur on every 3rd–5th print job. Error code 13.B2.D1 displayed. Tray 2 pick roller suspected. Printer is 18 months old and high-volume.',
 4, 7,
 'a1000000-0000-0000-0000-000000000005','b2000000-0000-0000-0000-000000000002',
 3,'Resolved','Medium','Low',
 NOW()-INTERVAL '20 days', NOW()-INTERVAL '18 days', NOW()-INTERVAL '17 days',
 NOW()-INTERVAL '18 days',
 'Hardware Repair','Pick roller replaced. Printer cleaned. Test pages successful.'),

-- INC0000006 – Epson EcoTank ink not recognised (New)
('e0000006-0000-0000-0000-000000000006',
 'INC0000006',
 'Epson EcoTank ET-4850 showing "Ink not recognised" after refill',
 'After filling ink tanks with Epson 542 ink, the printer displays "The following ink is not recognised." All four colours affected. Firmware version 04.23.EN.',
 4, 8,
 'a1000000-0000-0000-0000-000000000006', NULL,
 4,'New','Low','Low',
 NOW()-INTERVAL '1 day', NULL, NULL,
 NOW()+INTERVAL '4 days',
 NULL, NULL),

-- INC0000007 – Cisco Meraki MX68 VPN tunnel dropping (In Progress)
('e0000007-0000-0000-0000-000000000007',
 'INC0000007',
 'Cisco Meraki MX68 site-to-site VPN drops every 2 hours',
 'The AutoVPN tunnel between HQ (MX68) and Branch (MX67) goes down every ~2 hours and takes 5 minutes to re-establish. Affects 30+ users. Meraki dashboard shows "VPN connectivity" warnings. IKEv2 SA renegotiation suspected.',
 5, 9,
 'a1000000-0000-0000-0000-000000000007','b2000000-0000-0000-0000-000000000003',
 1,'In Progress','High','High',
 NOW()-INTERVAL '1 day', NULL, NULL,
 NOW()-INTERVAL '12 hours',
 NULL, NULL),

-- INC0000008 – Ubiquiti access point offline (Resolved)
('e0000008-0000-0000-0000-000000000008',
 'INC0000008',
 'Ubiquiti UAP-AC-Pro access point showing offline in controller',
 'Two access points on Floor 3 went offline following a UniFi controller 7.4 upgrade. LEDs show steady white (adopted) but no clients can connect. SSH reachable.',
 5, 10,
 'a1000000-0000-0000-0000-000000000008','b2000000-0000-0000-0000-000000000001',
 2,'Resolved','High','Medium',
 NOW()-INTERVAL '5 days', NOW()-INTERVAL '4 days', NOW()-INTERVAL '3 days',
 NOW()-INTERVAL '4 days 6 hours',
 'Software Fix','Downgraded AP firmware to 6.5.54 via SSH. APs re-adopted and clients reconnecting.'),

-- INC0000009 – Sony WH-1000XM5 ANC not working (Resolved)
('e0000009-0000-0000-0000-000000000009',
 'INC0000009',
 'Sony WH-1000XM5 active noise cancellation not functioning',
 'ANC toggle in Sony Headphones Connect app has no effect. Background noise fully audible. Issue started after firmware 2.1.0 update. Factory reset attempted without success.',
 6, 11,
 'a1000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000002',
 3,'Resolved','Low','Medium',
 NOW()-INTERVAL '12 days', NOW()-INTERVAL '10 days', NOW()-INTERVAL '9 days',
 NOW()-INTERVAL '10 days',
 'Software Fix','Rolled back to firmware 2.0.1 via Sony firmware recovery tool. ANC functional.'),

-- INC0000010 – LG UltraWide monitor no signal via USB-C (Resolved)
('e0000010-0000-0000-0000-000000000010',
 'INC0000010',
 'LG 34WN80C-B monitor shows no signal when connected via USB-C to ThinkPad',
 'Monitor connected to Lenovo ThinkPad X1 Carbon via USB-C cable. Monitor displays "No Signal" though laptop detects an external display. HDMI connection works fine. USB-C power delivery also not working.',
 6, 12,
 'a1000000-0000-0000-0000-000000000002','b2000000-0000-0000-0000-000000000003',
 3,'Resolved','Medium','Medium',
 NOW()-INTERVAL '8 days', NOW()-INTERVAL '6 days', NOW()-INTERVAL '5 days',
 NOW()-INTERVAL '6 days',
 'Hardware Replacement','USB-C cable replaced with Thunderbolt 4 certified cable. Signal and power delivery working.'),

-- INC0000011 – Apple Watch not syncing health data (On Hold)
('e0000011-0000-0000-0000-000000000011',
 'INC0000011',
 'Apple Watch Series 9 health data not syncing to iPhone Health app',
 'Heart rate, sleep, and step data collected on watch but not appearing in iPhone Health app. iCloud sync enabled. Watch paired correctly. Both devices on latest OS. Issue started 4 days ago.',
 7, 13,
 'a1000000-0000-0000-0000-000000000003','b2000000-0000-0000-0000-000000000001',
 4,'On Hold','Low','Low',
 NOW()-INTERVAL '4 days', NULL, NULL,
 NOW()+INTERVAL '3 days',
 NULL,'Awaiting Apple support case response.'),

-- INC0000012 – PlayStation 5 disc drive not reading (In Progress)
('e0000012-0000-0000-0000-000000000012',
 'INC0000012',
 'PS5 disc edition not reading game discs – CE-100028-1 error',
 'PS5 displays error CE-100028-1 when inserting any physical disc. The console can play digital games fine. Error appeared after last system software update 7.61. Drive makes clicking sound on insert.',
 9, 16,
 'a1000000-0000-0000-0000-000000000004','b2000000-0000-0000-0000-000000000002',
 2,'In Progress','Medium','High',
 NOW()-INTERVAL '2 days', NULL, NULL,
 NOW()+INTERVAL '1 day',
 NULL, NULL),

-- INC0000013 – Xbox Series X overheating (Resolved)
('e0000013-0000-0000-0000-000000000013',
 'INC0000013',
 'Xbox Series X shutting down mid-game with overheating error',
 'Console shuts off during graphically intensive games after 45–60 minutes. Displays overheating warning. Placed in open entertainment unit. Vents appear clear. Ambient temp ~24°C.',
 9, 17,
 'a1000000-0000-0000-0000-000000000005','b2000000-0000-0000-0000-000000000003',
 2,'Resolved','Medium','High',
 NOW()-INTERVAL '14 days', NOW()-INTERVAL '12 days', NOW()-INTERVAL '11 days',
 NOW()-INTERVAL '12 days',
 'Hardware Repair','Internal fan replaced by Microsoft service centre. 48-hour soak test passed.'),

-- INC0000014 – Google Pixel camera app crashing (Resolved)
('e0000014-0000-0000-0000-000000000014',
 'INC0000014',
 'Google Pixel 8 Pro camera app crashes immediately on open',
 'Camera app shows loading spinner then crashes to home screen. Occurs in both default and GCam apps. Other apps function normally. Device has 128 GB free. Last update was Android 14 QPR2.',
 3, 6,
 'a1000000-0000-0000-0000-000000000006','b2000000-0000-0000-0000-000000000001',
 3,'Resolved','Medium','Medium',
 NOW()-INTERVAL '9 days', NOW()-INTERVAL '7 days', NOW()-INTERVAL '6 days',
 NOW()-INTERVAL '7 days',
 'Software Fix','Cleared camera app cache and data. Re-granted permissions. Issue resolved post factory reset.'),

-- INC0000015 – Amazon Echo Show offline (Closed)
('e0000015-0000-0000-0000-000000000015',
 'INC0000015',
 'Amazon Echo Show 10 showing offline in Alexa app after WiFi change',
 'Corporate WiFi SSID was renamed during network refresh. Echo Show 10 no longer connects and shows offline in Alexa app. Device is in a conference room with no physical access currently.',
 8, 15,
 'a1000000-0000-0000-0000-000000000007','b2000000-0000-0000-0000-000000000002',
 4,'Closed','Low','Low',
 NOW()-INTERVAL '22 days', NOW()-INTERVAL '20 days', NOW()-INTERVAL '19 days',
 NOW()-INTERVAL '20 days',
 'Configuration Change','Device factory reset and re-provisioned with new SSID credentials via Alexa app.');

-- ─── WORK NOTES ──────────────────────────────────────────────
INSERT INTO work_notes (incident_id, author_id, note_type, body, created_at) VALUES

('e0000001-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000001','work_note',
 'Ran HWiNFO64 – CPU package hitting 97°C under 40% load. Thermal compound visibly dried out. Scheduling hardware repair.', NOW()-INTERVAL '10 days'),
('e0000001-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000001','work_note',
 'Replaced thermal paste with Arctic MX-6. Cleaned fan and heatsink. Max temp now 72°C under full load. 2-hour soak test passed.', NOW()-INTERVAL '8 days'),
('e0000001-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000001','customer_update',
 'Your laptop has been repaired and is ready for collection. Temperatures are now within normal range.', NOW()-INTERVAL '8 days'),

('e0000002-0000-0000-0000-000000000002','b2000000-0000-0000-0000-000000000002','work_note',
 'Battery cycle count: 812. Health 71%. Apple support confirmed warranty replacement eligible. Booking with Apple Authorised Service Provider.', NOW()-INTERVAL '14 days'),
('e0000002-0000-0000-0000-000000000002','b2000000-0000-0000-0000-000000000002','customer_update',
 'Battery has been replaced under warranty. Expected battery life restored to 10–12 hours.', NOW()-INTERVAL '12 days'),

('e0000003-0000-0000-0000-000000000003','b2000000-0000-0000-0000-000000000003','work_note',
 'Physical damage confirmed. Checking warranty – physical damage not covered. Obtaining quote for out-of-warranty screen replacement from Samsung service.', NOW()-INTERVAL '2 days'),
('e0000003-0000-0000-0000-000000000003','b2000000-0000-0000-0000-000000000003','customer_update',
 'Screen replacement quote received: £249. Awaiting your approval to proceed.', NOW()-INTERVAL '1 day'),

('e0000004-0000-0000-0000-000000000004','b2000000-0000-0000-0000-000000000001','work_note',
 'Investigated MDM profiles – SCEP certificate had expired post-iOS 17.3 update. Pushing renewed cert via Jamf Pro.', NOW()-INTERVAL '6 days'),
('e0000004-0000-0000-0000-000000000004','b2000000-0000-0000-0000-000000000001','customer_update',
 'Certificate has been updated. Please go to Settings > WiFi and re-connect to the corporate SSID.', NOW()-INTERVAL '5 days'),

('e0000007-0000-0000-0000-000000000007','b2000000-0000-0000-0000-000000000003','work_note',
 'Reviewing Meraki dashboard event logs. VPN tunnel renegotiation every 7200s matches IKEv2 SA lifetime. Suspecting NAT-T keepalive mismatch with ISP device.', NOW()-INTERVAL '20 hours'),
('e0000007-0000-0000-0000-000000000007','b2000000-0000-0000-0000-000000000003','work_note',
 'Opened Meraki support case #MRK-2024-88341. Escalated to Priority 1. ISP MTU also being investigated.', NOW()-INTERVAL '10 hours'),
('e0000007-0000-0000-0000-000000000007','b2000000-0000-0000-0000-000000000003','customer_update',
 'We have escalated this to Cisco Meraki support. A fix is being tested – we will update you within 4 hours.', NOW()-INTERVAL '8 hours'),

('e0000012-0000-0000-0000-000000000012','b2000000-0000-0000-0000-000000000002','work_note',
 'Rebuilt database via Safe Mode – disc drive still fails. Hardware fault suspected. Logging with Sony repair portal.', NOW()-INTERVAL '1 day'),
('e0000012-0000-0000-0000-000000000012','b2000000-0000-0000-0000-000000000002','customer_update',
 'Sony repair centre has been booked. Collection arranged for tomorrow. Estimated turnaround 5–7 business days.', NOW()-INTERVAL '12 hours');

-- ─── RESOLUTIONS ─────────────────────────────────────────────
INSERT INTO resolutions
  (incident_id, resolved_by, resolution_code, root_cause, steps_taken, kb_article, customer_confirmed, resolved_at)
VALUES

('e0000001-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000001',
 'Hardware Repair',
 'Thermal paste had degraded after 2 years of use causing CPU thermal throttling and emergency shutdown.',
 '1. Removed bottom panel and heatsink assembly. 2. Cleaned old thermal paste from CPU and GPU dies. 3. Applied Arctic MX-6 compound. 4. Cleaned fan blades. 5. Reassembled and ran 2-hour stress test. 6. Confirmed temps below 75°C under full load.',
 'KB0000101', TRUE, NOW()-INTERVAL '8 days'),

('e0000002-0000-0000-0000-000000000002','b2000000-0000-0000-0000-000000000002',
 'Hardware Replacement',
 'Battery cell degradation (71% health, 812 cycles) causing insufficient charge retention.',
 '1. Confirmed battery health via System Information. 2. Checked warranty eligibility (within 2 years). 3. Booked Apple Authorised Service Provider. 4. Battery replaced with OEM part. 5. Calibration cycle performed. 6. Confirmed 10h+ battery life post replacement.',
 'KB0000102', TRUE, NOW()-INTERVAL '12 days'),

('e0000004-0000-0000-0000-000000000004','b2000000-0000-0000-0000-000000000001',
 'Configuration Change',
 'iOS 17.3 update cleared existing SCEP/MDM certificates required for WPA2-Enterprise 802.1X authentication.',
 '1. Identified expired MDM certificate in Jamf Pro. 2. Generated new SCEP certificate via internal CA. 3. Pushed certificate profile to affected device via Jamf. 4. Instructed user to forget and re-join corporate SSID. 5. Verified connectivity and email sync.',
 'KB0000103', TRUE, NOW()-INTERVAL '5 days'),

('e0000005-0000-0000-0000-000000000005','b2000000-0000-0000-0000-000000000002',
 'Hardware Repair',
 'Tray 2 pick roller worn beyond service life (high-volume print environment). Error 13.B2.D1 = Tray 2 pick assembly fault.',
 '1. Ordered HP pick roller kit RM1-9168. 2. Powered off and removed Tray 2. 3. Replaced pick roller and separation pad. 4. Cleaned paper path with IPA wipe. 5. Ran 200-page test print job. 6. No further jams observed.',
 'KB0000104', TRUE, NOW()-INTERVAL '18 days'),

('e0000008-0000-0000-0000-000000000008','b2000000-0000-0000-0000-000000000001',
 'Software Fix',
 'UniFi controller 7.4 pushed incompatible firmware version to UAP-AC-Pro APs causing driver crash.',
 '1. SSH into affected APs (ssh admin@<ip>). 2. Confirmed firmware version 6.6.55 (incompatible). 3. Downloaded firmware 6.5.54 from Ubiquiti CDN. 4. Applied via: fwupdate -d <url>. 5. APs rebooted and re-adopted. 6. Pinned firmware version in controller to prevent auto-update.',
 'KB0000105', TRUE, NOW()-INTERVAL '4 days'),

('e0000009-0000-0000-0000-000000000009','b2000000-0000-0000-0000-000000000002',
 'Software Fix',
 'Sony firmware 2.1.0 introduced ANC regression. Roll back to 2.0.1 restores functionality.',
 '1. Downloaded Sony Firmware Recovery Tool v2.3. 2. Connected headphones via USB-C to PC. 3. Selected "Firmware recovery" and 2.0.1 target version. 4. Recovery completed in 8 minutes. 5. Reconnected via Bluetooth and tested ANC – fully operational. 6. Disabled auto-update in Sony Headphones Connect app.',
 'KB0000106', TRUE, NOW()-INTERVAL '10 days'),

('e0000010-0000-0000-0000-000000000010','b2000000-0000-0000-0000-000000000003',
 'Hardware Replacement',
 'Generic USB-C cable used did not support DisplayPort Alt Mode or USB-PD required by the LG 34WN80C-B.',
 '1. Tested with known-good Thunderbolt 4 cable (Belkin F2CD082). 2. Display and power delivery worked immediately. 3. Supplied user with TB4-certified cable. 4. Updated procurement guidance to specify TB4 cable requirement for USB-C monitor deployments.',
 'KB0000107', TRUE, NOW()-INTERVAL '6 days'),

('e0000013-0000-0000-0000-000000000013','b2000000-0000-0000-0000-000000000003',
 'Hardware Repair',
 'Xbox Series X internal cooling fan bearing had failed, reducing airflow to <40% of rated capacity.',
 '1. Booked Microsoft Authorised Repair Centre. 2. Fan assembly replaced with OEM Microsoft part. 3. Console ran 48-hour stress test (Furmark equivalent via Game Pass titles). 4. Temps within Microsoft spec (<55°C under sustained load). 5. Returned to user.',
 'KB0000108', TRUE, NOW()-INTERVAL '12 days'),

('e0000014-0000-0000-0000-000000000014','b2000000-0000-0000-0000-000000000001',
 'Software Fix',
 'Android 14 QPR2 update corrupted camera app permissions and cache, preventing initialisation.',
 '1. Settings > Apps > Camera > Storage > Clear Cache. 2. Clear Data. 3. Settings > Apps > Camera > Permissions – re-granted Camera, Microphone, Location. 4. Issue persisted. 5. Factory reset performed after data backup to Google One. 6. Camera fully functional post-reset.',
 'KB0000109', TRUE, NOW()-INTERVAL '7 days'),

('e0000015-0000-0000-0000-000000000015','b2000000-0000-0000-0000-000000000002',
 'Configuration Change',
 'Echo Show 10 stores WiFi credentials locally and cannot auto-discover SSID changes.',
 '1. Gained physical access to conference room. 2. Factory reset device (Settings > Device Options > Reset to Factory Defaults). 3. Re-ran Alexa setup via Alexa app. 4. Connected to new SSID with updated credentials. 5. Re-linked to room calendar and conference room profile. 6. Verified Alexa voice control operational.',
 'KB0000110', TRUE, NOW()-INTERVAL '20 days');

-- ─── KNOWLEDGE BASE ARTICLES ─────────────────────────────────
INSERT INTO kb_articles (number, title, category_id, body, author_id, views, helpful_votes, published_at) VALUES
('KB0000101','How to replace thermal paste on Dell XPS 15 laptops',2,
 'Applies to: Dell XPS 15 9510, 9520, 9530. Symptoms: high CPU temps (>90°C), unexpected shutdowns. Resolution: Replace thermal paste using Arctic MX-6 or Kryonaut. See Dell Service Manual chapter 7 for disassembly steps. Expected CPU max temp post-repair: <78°C.',
 'b2000000-0000-0000-0000-000000000001',142,87, NOW()-INTERVAL '30 days'),
('KB0000102','MacBook Pro battery warranty replacement process',2,
 'Apple covers battery replacement if health drops below 80% within warranty period. Check via: Apple menu > System Information > Power. Book via Apple Authorised Service Provider. Provide proof of purchase. Turnaround: 3–5 business days.',
 'b2000000-0000-0000-0000-000000000002',98,61, NOW()-INTERVAL '25 days'),
('KB0000103','Fixing iOS 17.x WPA2-Enterprise WiFi certificate issues via Jamf',3,
 'iOS 17.x updates can expire MDM-pushed SCEP certificates. Resolution: In Jamf Pro, navigate to Devices > Configuration Profiles, re-issue the WiFi+Certificate profile to affected devices. Users must forget and re-join the SSID after the profile is installed.',
 'b2000000-0000-0000-0000-000000000001',213,178, NOW()-INTERVAL '20 days'),
('KB0000104','HP LaserJet Pro M404dn Tray 2 paper jam – error 13.B2.D1',4,
 'Error 13.B2.D1 indicates Tray 2 pick assembly failure. Order HP part RM1-9168 (pick roller kit). Replace roller and separation pad. High-volume environments (>2000 pages/month) should replace every 12 months preventively.',
 'b2000000-0000-0000-0000-000000000002',76,54, NOW()-INTERVAL '35 days'),
('KB0000105','Downgrading Ubiquiti UAP firmware after failed controller upgrade',5,
 'If UAP-AC-Pro APs go offline after a UniFi controller upgrade: SSH to AP, run: fwupdate -d https://dl.ubnt.com/unifi/firmware/U7PG2/6.5.54.13992/BZ.qca956x.v6.5.54.13992.200901.1142.bin. Pin the firmware version in controller Settings > Auto Upgrade to prevent recurrence.',
 'b2000000-0000-0000-0000-000000000003',189,134, NOW()-INTERVAL '10 days'),
('KB0000106','Rolling back Sony WH-1000XM5 firmware using recovery tool',6,
 'Sony firmware 2.1.0 causes ANC failure. Use Sony Firmware Recovery Tool v2.3 to roll back to 2.0.1. Connect headphones via USB-C (Bluetooth must be off). Select Recovery mode and 2.0.1 from the version list. Disable auto-update in Sony Headphones Connect app afterward.',
 'b2000000-0000-0000-0000-000000000002',445,389, NOW()-INTERVAL '15 days'),
('KB0000107','USB-C monitor no signal – cable compatibility guide',6,
 'For USB-C monitors requiring DisplayPort Alt Mode and Power Delivery (e.g. LG 34WN80C-B, Dell U3423WE), use only Thunderbolt 3/4 or USB4 certified cables. Recommended: Belkin F2CD082, CalDigit SOHO. Generic USB-C cables do not carry video signal.',
 'b2000000-0000-0000-0000-000000000003',267,241, NOW()-INTERVAL '12 days'),
('KB0000108','Xbox Series X overheating – fan replacement process',9,
 'Overheating on Xbox Series X after 45–60 minutes indicates fan failure. This repair requires Microsoft Authorised Service. Do not attempt self-repair as it voids warranty. Book via support.microsoft.com/devices. Typical turnaround 7–10 business days.',
 'b2000000-0000-0000-0000-000000000003',312,278, NOW()-INTERVAL '18 days'),
('KB0000109','Fixing Google Pixel camera app crash after Android update',3,
 'Post-update camera crashes: clear app cache and data first (Settings > Apps > Camera > Storage). Re-grant permissions. If unresolved, factory reset and restore from Google backup. Back up data to Google One before reset.',
 'b2000000-0000-0000-0000-000000000001',198,167, NOW()-INTERVAL '22 days'),
('KB0000110','Re-provisioning Amazon Echo Show after WiFi SSID change',8,
 'Echo Show devices cannot auto-connect to a renamed SSID. Factory reset is required: Settings > Device Options > Reset to Factory Defaults. Re-run Alexa app setup. Re-link calendar integrations and room profiles after setup.',
 'b2000000-0000-0000-0000-000000000002',134,98, NOW()-INTERVAL '28 days');