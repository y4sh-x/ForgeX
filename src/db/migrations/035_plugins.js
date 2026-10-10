'use strict';

function up(db) {
  db.exec(`
    CREATE TABLE plugins (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      version TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      author TEXT NOT NULL DEFAULT '',
      entry TEXT NOT NULL DEFAULT 'index.js',
      enabled INTEGER NOT NULL DEFAULT 1,
      installed_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE INDEX idx_plugins_enabled ON plugins(enabled);
  `);
}

module.exports = { up };
