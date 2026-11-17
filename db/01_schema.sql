-- =====================================================================
-- LiVrai - Création du schéma de la base de données (PostgreSQL 18)
-- =====================================================================
-- Ordre de création imposé par les clés étrangères.
-- "user" et "order" sont des mots réservés : toujours les écrire entre guillemets.
-- Le script est exécuté dans une transaction : en cas d'erreur, rien n'est créé.

BEGIN;

-- ---------------------------------------------------------------------
-- Types énumérés (listes de valeurs fermées)
-- ---------------------------------------------------------------------

CREATE TYPE user_role AS ENUM ('CUSTOMER', 'SALES', 'DELIVERY');

CREATE TYPE order_status AS ENUM (
    'PENDING',
    'CANCELLED',
    'ACCEPTED',
    'REJECTED',
    'IN_DELIVERY',
    'DELIVERED'
);

CREATE TYPE invoice_status AS ENUM ('DRAFT', 'ISSUED');

-- ---------------------------------------------------------------------
-- Clients (entreprises)
-- ---------------------------------------------------------------------

CREATE TABLE customer (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_name  VARCHAR(255) NOT NULL,
    siret         CHAR(14)     NOT NULL UNIQUE,
    email         VARCHAR(255) NOT NULL,
    phone         VARCHAR(20),
    sales_rep_id  BIGINT,       -- clé étrangère ajoutée après la création de "user"
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT customer_siret_format CHECK (siret ~ '^[0-9]{14}$')
);

COMMENT ON COLUMN customer.sales_rep_id IS 'Commercial qui suit le client, NULL si le client est autonome';

-- ---------------------------------------------------------------------
-- Contacts d'un client
-- ---------------------------------------------------------------------

CREATE TABLE contact (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id  BIGINT       NOT NULL REFERENCES customer (id),
    last_name    VARCHAR(100) NOT NULL,
    first_name   VARCHAR(100) NOT NULL,
    job_title    VARCHAR(100),
    email        VARCHAR(255),
    phone        VARCHAR(20)
);

CREATE INDEX contact_customer_idx ON contact (customer_id);

-- ---------------------------------------------------------------------
-- Carnet d'adresses d'un client
-- ---------------------------------------------------------------------

CREATE TABLE address (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id   BIGINT       NOT NULL REFERENCES customer (id),
    label         VARCHAR(100) NOT NULL,
    line1         VARCHAR(255) NOT NULL,
    line2         VARCHAR(255),
    postal_code   VARCHAR(10)  NOT NULL,
    city          VARCHAR(100) NOT NULL,
    country_code  CHAR(2)      NOT NULL DEFAULT 'FR'
);

CREATE INDEX address_customer_idx ON address (customer_id);

-- ---------------------------------------------------------------------
-- Utilisateurs (comptes de connexion)
-- ---------------------------------------------------------------------

CREATE TABLE "user" (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email          VARCHAR(255) NOT NULL UNIQUE,
    password_hash  VARCHAR(255) NOT NULL,
    role           user_role    NOT NULL,
    contact_id     BIGINT       UNIQUE REFERENCES contact (id),
    last_name      VARCHAR(100),
    first_name     VARCHAR(100),
    active         BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),

    -- Un client est toujours rattaché à un contact, un employé LiVrai jamais
    CONSTRAINT user_contact_by_role CHECK ((role = 'CUSTOMER') = (contact_id IS NOT NULL)),

    -- Nom et prénom : portés par le contact pour un client, par "user" pour un employé
    CONSTRAINT user_names_by_role CHECK (
        (role = 'CUSTOMER'  AND last_name IS NULL     AND first_name IS NULL)
     OR (role <> 'CUSTOMER' AND last_name IS NOT NULL AND first_name IS NOT NULL)
    )
);

COMMENT ON COLUMN "user".email IS 'Email de connexion, distinct de l''email du contact';
COMMENT ON COLUMN "user".active IS 'Un compte est désactivé, jamais supprimé, pour conserver l''historique';

-- Référence circulaire customer -> "user" : ajoutée une fois les deux tables créées
ALTER TABLE customer
    ADD CONSTRAINT customer_sales_rep_fk FOREIGN KEY (sales_rep_id) REFERENCES "user" (id);

CREATE INDEX customer_sales_rep_idx ON customer (sales_rep_id);

-- ---------------------------------------------------------------------
-- Jetons de renouvellement (refresh tokens), révocables
-- ---------------------------------------------------------------------

CREATE TABLE refresh_token (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT       NOT NULL REFERENCES "user" (id),
    token_hash  VARCHAR(255) NOT NULL UNIQUE,
    expires_at  TIMESTAMPTZ  NOT NULL,
    revoked     BOOLEAN      NOT NULL DEFAULT FALSE
);

CREATE INDEX refresh_token_user_idx ON refresh_token (user_id);

COMMENT ON COLUMN refresh_token.token_hash IS 'Empreinte du jeton, le jeton lui-même n''est jamais stocké';

-- ---------------------------------------------------------------------
-- Factures
-- ---------------------------------------------------------------------

CREATE TABLE invoice (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    number           VARCHAR(20)    NOT NULL UNIQUE,
    customer_id      BIGINT         NOT NULL REFERENCES customer (id),
    status           invoice_status NOT NULL DEFAULT 'DRAFT',
    issued_at        TIMESTAMPTZ,
    amount_excl_tax  NUMERIC(12,2),
    vat_rate         NUMERIC(4,2)   NOT NULL DEFAULT 20.00,
    amount_incl_tax  NUMERIC(12,2),

    -- Informations de facturation copiées à l'émission, puis figées
    billing_company_name  VARCHAR(255),
    billing_siret         CHAR(14),
    billing_line1         VARCHAR(255),
    billing_line2         VARCHAR(255),
    billing_postal_code   VARCHAR(10),
    billing_city          VARCHAR(100),
    billing_country_code  CHAR(2),

    -- Cible de la clé étrangère composite depuis "order"
    CONSTRAINT invoice_id_customer_uq UNIQUE (id, customer_id),

    CONSTRAINT invoice_vat_rate_range CHECK (vat_rate >= 0 AND vat_rate < 100),

    -- Une facture émise a forcément une date, des montants et ses informations de facturation
    CONSTRAINT invoice_issued_complete CHECK (
        status <> 'ISSUED'
        OR (
            issued_at IS NOT NULL
            AND amount_excl_tax IS NOT NULL
            AND amount_incl_tax IS NOT NULL
            AND billing_company_name IS NOT NULL
            AND billing_siret IS NOT NULL
            AND billing_line1 IS NOT NULL
            AND billing_postal_code IS NOT NULL
            AND billing_city IS NOT NULL
            AND billing_country_code IS NOT NULL
        )
    )
);

CREATE INDEX invoice_customer_status_idx ON invoice (customer_id, status);

COMMENT ON COLUMN invoice.amount_excl_tax IS 'Montant HT en euros, figé à l''émission';

-- ---------------------------------------------------------------------
-- Commandes (cycle de vie complet, jusqu'à la livraison)
-- ---------------------------------------------------------------------

CREATE TABLE "order" (
    id                     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reference              VARCHAR(20)   NOT NULL UNIQUE,
    customer_id            BIGINT        NOT NULL REFERENCES customer (id),
    ordered_by_id          BIGINT        NOT NULL REFERENCES "user" (id),
    status                 order_status  NOT NULL DEFAULT 'PENDING',
    volume                 NUMERIC(8,2)  NOT NULL,
    weight                 NUMERIC(10,2) NOT NULL,
    requested_date         DATE          NOT NULL,

    -- Adresses copiées depuis le carnet du client à la création, puis figées
    pickup_line1           VARCHAR(255)  NOT NULL,
    pickup_line2           VARCHAR(255),
    pickup_postal_code     VARCHAR(10)   NOT NULL,
    pickup_city            VARCHAR(100)  NOT NULL,
    pickup_country_code    CHAR(2)       NOT NULL,

    delivery_line1         VARCHAR(255)  NOT NULL,
    delivery_line2         VARCHAR(255),
    delivery_postal_code   VARCHAR(10)   NOT NULL,
    delivery_city          VARCHAR(100)  NOT NULL,
    delivery_country_code  CHAR(2)       NOT NULL,

    price_excl_tax         NUMERIC(10,2),
    delivered_at           TIMESTAMPTZ,
    invoice_id             BIGINT,
    created_at             TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT order_volume_positive CHECK (volume > 0),
    CONSTRAINT order_weight_positive CHECK (weight > 0),

    -- Le prix est fixé à l'acceptation, il est obligatoire ensuite
    CONSTRAINT order_price_when_accepted CHECK (
        status NOT IN ('ACCEPTED', 'IN_DELIVERY', 'DELIVERED')
        OR (price_excl_tax IS NOT NULL AND price_excl_tax > 0)
    ),

    -- Date de livraison renseignée si et seulement si la commande est livrée
    CONSTRAINT order_delivered_at_when_delivered CHECK (
        (status = 'DELIVERED') = (delivered_at IS NOT NULL)
    ),

    -- Seule une commande livrée peut être facturée
    CONSTRAINT order_invoice_when_delivered CHECK (
        invoice_id IS NULL OR status = 'DELIVERED'
    ),

    -- Une commande ne peut être rattachée qu'à une facture de son propre client
    CONSTRAINT order_invoice_same_customer_fk
        FOREIGN KEY (invoice_id, customer_id) REFERENCES invoice (id, customer_id)
);

-- Index adaptés aux listes paginées et filtrées
CREATE INDEX order_customer_status_idx ON "order" (customer_id, status);
CREATE INDEX order_status_requested_date_idx ON "order" (status, requested_date);
CREATE INDEX order_invoice_idx ON "order" (invoice_id);

COMMENT ON COLUMN "order".volume IS 'Volume en m3';
COMMENT ON COLUMN "order".weight IS 'Poids en kg';
COMMENT ON COLUMN "order".price_excl_tax IS 'Prix HT en euros, fixé par le service Livraisons à l''acceptation';

COMMIT;
