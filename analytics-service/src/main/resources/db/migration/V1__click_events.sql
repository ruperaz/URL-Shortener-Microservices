CREATE TABLE IF NOT EXISTS click_events (
    id BIGSERIAL PRIMARY KEY,
    code VARCHAR(32) NOT NULL,
    ts TIMESTAMP WITH TIME ZONE NOT NULL,
    user_agent TEXT,
    ip VARCHAR(128)
);
CREATE INDEX IF NOT EXISTS ix_click_code_ts ON click_events(code, ts);
