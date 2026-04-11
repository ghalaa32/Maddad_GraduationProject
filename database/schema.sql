-- =============================================================================
-- Maddad Project - PostgreSQL Database Schema
-- =============================================================================
-- Covers: users, profiles, relationships, accounts, scores, tasks, rewards,
--         transactions, notifications, and session management.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- ENUM TYPES
-- ---------------------------------------------------------------------------

CREATE TYPE user_type AS ENUM ('parent', 'child');

CREATE TYPE relationship_type AS ENUM ('mother', 'father', 'guardian', 'other');

CREATE TYPE account_type AS ENUM ('checking', 'savings', 'reward');

CREATE TYPE score_type AS ENUM (
    'academic',
    'behavior',
    'homework',
    'attendance',
    'task_completion'
);

CREATE TYPE task_type AS ENUM ('homework', 'chore', 'learning_goal', 'health_goal');

CREATE TYPE task_status AS ENUM ('pending', 'in_progress', 'completed', 'cancelled');

CREATE TYPE task_priority AS ENUM ('Low', 'Medium', 'High');

CREATE TYPE transaction_type AS ENUM (
    'deposit',
    'withdrawal',
    'reward',
    'purchase',
    'transfer'
);

-- ---------------------------------------------------------------------------
-- HELPER: auto-update updated_at column via trigger function
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- TABLE: users
-- Stores authentication credentials for both parents and children.
-- ---------------------------------------------------------------------------

CREATE TABLE users (
    id                BIGSERIAL       PRIMARY KEY,
    user_type         user_type       NOT NULL,
    email             VARCHAR(255)    NOT NULL,
    password_hash     VARCHAR(255)    NOT NULL,
    first_name        VARCHAR(100)    NOT NULL,
    last_name         VARCHAR(100)    NOT NULL,
    date_of_birth     DATE,
    phone_number      VARCHAR(20),
    profile_image_url VARCHAR(255),
    is_active         BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT users_email_unique UNIQUE (email)
);

CREATE INDEX idx_users_email     ON users (email);
CREATE INDEX idx_users_user_type ON users (user_type);

CREATE TRIGGER set_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- ---------------------------------------------------------------------------
-- TABLE: parent_profiles
-- Extended profile information for parent users.
-- ---------------------------------------------------------------------------

CREATE TABLE parent_profiles (
    id              BIGSERIAL       PRIMARY KEY,
    user_id         BIGINT          NOT NULL,
    occupation      VARCHAR(150),
    address         VARCHAR(255),
    city            VARCHAR(100),
    country         VARCHAR(100),
    postal_code     VARCHAR(20),
    bio             TEXT,

    -- Child information collected at registration
    child_name      VARCHAR(100),
    child_age_group VARCHAR(10),    -- '12-18' | '19-24' | '25-30' | '31-36'
    child_gender    VARCHAR(10),    -- 'ذكر' | 'أنثى'

    CONSTRAINT parent_profiles_user_id_unique UNIQUE (user_id),
    CONSTRAINT fk_parent_profiles_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------------
-- TABLE: child_profiles
-- Extended profile information for child users.
-- ---------------------------------------------------------------------------

CREATE TABLE child_profiles (
    id          BIGSERIAL   PRIMARY KEY,
    user_id     BIGINT      NOT NULL,
    grade_level INT,
    school_name VARCHAR(150),

    CONSTRAINT child_profiles_user_id_unique UNIQUE (user_id),
    CONSTRAINT fk_child_profiles_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------------
-- TABLE: parent_child_relationships
-- Explicit many-to-many mapping between parents and children, including
-- the relationship type (mother, father, guardian, other).
-- ---------------------------------------------------------------------------

CREATE TABLE parent_child_relationships (
    id                BIGSERIAL           PRIMARY KEY,
    parent_id         BIGINT              NOT NULL,
    child_id          BIGINT              NOT NULL,
    relationship_type relationship_type   NOT NULL,
    created_at        TIMESTAMPTZ         NOT NULL DEFAULT NOW(),

    CONSTRAINT parent_child_relationships_unique UNIQUE (parent_id, child_id),
    CONSTRAINT fk_pcr_parent
        FOREIGN KEY (parent_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_pcr_child
        FOREIGN KEY (child_id)  REFERENCES users (id) ON DELETE CASCADE
);

CREATE INDEX idx_pcr_parent_id ON parent_child_relationships (parent_id);
CREATE INDEX idx_pcr_child_id  ON parent_child_relationships (child_id);

-- ---------------------------------------------------------------------------
-- TABLE: accounts
-- Wallet / account balance tracking per user.
-- ---------------------------------------------------------------------------

CREATE TABLE accounts (
    id             BIGSERIAL       PRIMARY KEY,
    user_id        BIGINT          NOT NULL,
    account_type   account_type    NOT NULL,
    balance        NUMERIC(12, 2)  NOT NULL DEFAULT 0.00,
    currency       CHAR(3)         NOT NULL DEFAULT 'USD',
    account_number VARCHAR(50),
    created_at     TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT accounts_account_type_per_user UNIQUE (user_id, account_type),
    CONSTRAINT accounts_balance_non_negative CHECK (balance >= 0),
    CONSTRAINT fk_accounts_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

CREATE TRIGGER set_accounts_updated_at
    BEFORE UPDATE ON accounts
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- ---------------------------------------------------------------------------
-- TABLE: scores
-- Academic and behavioural performance records for children.
-- ---------------------------------------------------------------------------

CREATE TABLE scores (
    id             BIGSERIAL      PRIMARY KEY,
    child_id       BIGINT         NOT NULL,
    score_type     score_type     NOT NULL,
    subject        VARCHAR(100),
    score          NUMERIC(6, 2)  NOT NULL,
    max_score      NUMERIC(6, 2)  NOT NULL DEFAULT 100.00,
    percentage     NUMERIC(6, 2)  GENERATED ALWAYS AS
                       (ROUND(score / NULLIF(max_score, 0) * 100, 2)) STORED,
    date_assigned  DATE           NOT NULL,
    date_completed DATE,
    notes          TEXT,
    created_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW(),

    CONSTRAINT scores_max_score_positive CHECK (max_score > 0),
    CONSTRAINT fk_scores_child
        FOREIGN KEY (child_id) REFERENCES users (id) ON DELETE CASCADE
);

CREATE INDEX idx_scores_child_date ON scores (child_id, date_assigned);

CREATE TRIGGER set_scores_updated_at
    BEFORE UPDATE ON scores
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- ---------------------------------------------------------------------------
-- TABLE: tasks
-- Homework, chores, and learning / health goals assigned to children.
-- ---------------------------------------------------------------------------

CREATE TABLE tasks (
    id            BIGSERIAL       PRIMARY KEY,
    child_id      BIGINT          NOT NULL,
    title         VARCHAR(255)    NOT NULL,
    description   TEXT,
    task_type     task_type       NOT NULL,
    status        task_status     NOT NULL DEFAULT 'pending',
    priority      task_priority   NOT NULL DEFAULT 'medium',
    due_date      TIMESTAMPTZ,
    completed_at  TIMESTAMPTZ,
    reward_points INT             NOT NULL DEFAULT 0,
    created_by    BIGINT,
    created_at    TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT tasks_reward_points_non_negative CHECK (reward_points >= 0),
    CONSTRAINT fk_tasks_child
        FOREIGN KEY (child_id)   REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_tasks_created_by
        FOREIGN KEY (created_by) REFERENCES users (id) ON DELETE SET NULL
);

CREATE INDEX idx_tasks_child_status_due ON tasks (child_id, status, due_date);

CREATE TRIGGER set_tasks_updated_at
    BEFORE UPDATE ON tasks
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- ---------------------------------------------------------------------------
-- TABLE: rewards
-- Points earned by children and their redemption status.
-- ---------------------------------------------------------------------------

CREATE TABLE rewards (
    id            BIGSERIAL   PRIMARY KEY,
    child_id      BIGINT      NOT NULL,
    points_earned INT         NOT NULL,
    reward_type   VARCHAR(100),
    reason        TEXT,
    redeemed      BOOLEAN     NOT NULL DEFAULT FALSE,
    redeemed_at   TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT rewards_points_earned_positive CHECK (points_earned > 0),
    CONSTRAINT fk_rewards_child
        FOREIGN KEY (child_id) REFERENCES users (id) ON DELETE CASCADE
);

CREATE INDEX idx_rewards_child_created ON rewards (child_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- TABLE: transactions
-- Full ledger history of all monetary movements on an account.
-- ---------------------------------------------------------------------------

CREATE TABLE transactions (
    id               BIGSERIAL          PRIMARY KEY,
    account_id       BIGINT             NOT NULL,
    transaction_type transaction_type   NOT NULL,
    amount           NUMERIC(12, 2)     NOT NULL,
    balance_after    NUMERIC(12, 2)     NOT NULL,
    description      TEXT,
    related_task_id  BIGINT,
    created_at       TIMESTAMPTZ        NOT NULL DEFAULT NOW(),

    CONSTRAINT transactions_amount_non_zero CHECK (amount <> 0),
    CONSTRAINT fk_transactions_account
        FOREIGN KEY (account_id)      REFERENCES accounts (id) ON DELETE CASCADE,
    CONSTRAINT fk_transactions_task
        FOREIGN KEY (related_task_id) REFERENCES tasks (id) ON DELETE SET NULL
);

CREATE INDEX idx_transactions_account_created
    ON transactions (account_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- TABLE: notifications
-- In-app notifications for both parents and children.
-- ---------------------------------------------------------------------------

CREATE TABLE notifications (
    id                  BIGSERIAL    PRIMARY KEY,
    user_id             BIGINT       NOT NULL,
    notification_type   VARCHAR(50)  NOT NULL,
    title               VARCHAR(255) NOT NULL,
    message             TEXT,
    is_read             BOOLEAN      NOT NULL DEFAULT FALSE,
    related_entity_type VARCHAR(50),
    related_entity_id   BIGINT,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_notifications_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

CREATE INDEX idx_notifications_user_read_created
    ON notifications (user_id, is_read, created_at DESC);

-- ---------------------------------------------------------------------------
-- TABLE: sessions
-- Server-side session / token management for authentication.
-- ---------------------------------------------------------------------------

CREATE TABLE sessions (
    id            BIGSERIAL    PRIMARY KEY,
    user_id       BIGINT       NOT NULL,
    session_token VARCHAR(255) NOT NULL,
    ip_address    VARCHAR(45),
    user_agent    TEXT,
    expires_at    TIMESTAMPTZ  NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT sessions_token_unique UNIQUE (session_token),
    CONSTRAINT fk_sessions_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

CREATE INDEX idx_sessions_user_expires ON sessions (user_id, expires_at);
CREATE INDEX idx_sessions_token        ON sessions (session_token);

-- ---------------------------------------------------------------------------
-- ENUM TYPES (questionnaire)
-- ---------------------------------------------------------------------------

CREATE TYPE risk_level AS ENUM ('low', 'medium', 'high');

-- ---------------------------------------------------------------------------
-- TABLE: questionnaire_results
-- Stores each ASD screening assessment including raw answers, scores,
-- rule-based risk classification, and the ML model prediction.
-- Accumulates a dataset that can be used to retrain the ML model over time.
-- ---------------------------------------------------------------------------

CREATE TABLE questionnaire_results (
    id                    BIGSERIAL     PRIMARY KEY,
    user_id               BIGINT        NOT NULL,
    age_group             VARCHAR(10)   NOT NULL,   -- e.g. '12-18', '19-24'
    gender                VARCHAR(10)   NOT NULL,   -- 'ذكر' | 'أنثى'

    -- The 10 skill answers: 0 = نعم (typical), 1 = لا (concern)
    response_to_name      SMALLINT      NOT NULL CHECK (response_to_name      IN (0,1)),
    eye_contact           SMALLINT      NOT NULL CHECK (eye_contact           IN (0,1)),
    social_smile          SMALLINT      NOT NULL CHECK (social_smile          IN (0,1)),
    imitation             SMALLINT      NOT NULL CHECK (imitation             IN (0,1)),
    discrimination        SMALLINT      NOT NULL CHECK (discrimination        IN (0,1)),
    pointing_with_finger  SMALLINT      NOT NULL CHECK (pointing_with_finger  IN (0,1)),
    facial_expressions    SMALLINT      NOT NULL CHECK (facial_expressions    IN (0,1)),
    joint_attention       SMALLINT      NOT NULL CHECK (joint_attention       IN (0,1)),
    play_skills           SMALLINT      NOT NULL CHECK (play_skills           IN (0,1)),
    response_to_commands  SMALLINT      NOT NULL CHECK (response_to_commands  IN (0,1)),

    -- Scores and classification from the initial questionnaire
    initial_score         SMALLINT      NOT NULL,
    initial_risk          risk_level    NOT NULL,

    -- Answers updated after follow-up questions (NULL if follow-up not done)
    followup_answers      JSONB,
    final_score           SMALLINT,
    final_risk            risk_level,

    -- ML model prediction for the final risk level
    ml_risk               risk_level,
    ml_confidence         NUMERIC(5, 4),            -- e.g. 0.8732

    created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_questionnaire_results_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

CREATE INDEX idx_qr_user_created ON questionnaire_results (user_id, created_at DESC);
