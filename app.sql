CREATE TABLE seen (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ip TEXT NOT NULL,
    account_id INTEGER NOT NULL
);

CREATE TABLE account (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    name TEXT NOT NULL UNIQUE,
    email TEXT NOT NULL,
    password TEXT NOT NULL,
    last_seen DATETIME,
    active INTEGER DEFAULT 1,
    expires DATETIME
);
