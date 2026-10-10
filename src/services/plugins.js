'use strict';

// ForgeX extension runtime. Plugins are isolated by directory and loaded only
// when enabled. A plugin exports either a function(context) or an object with
// register(context). The context deliberately exposes small, explicit hooks
// instead of the Express app or database connection directly.

const fs = require('node:fs');
const path = require('node:path');
const db = require('../db');
const config = require('../config');
const logger = require('../logger')('plugins');

const ROOT = path.join(config.dataDir, 'plugins');
const loaded = new Map();
const hooks = new Map();

function ensureRoot() {
  fs.mkdirSync(ROOT, { recursive: true, mode: 0o750 });
}

function safeId(id) {
  return /^[a-z0-9][a-z0-9._-]{1,63}$/i.test(String(id));
}

function manifestFrom(dir) {
  const file = path.join(dir, 'plugin.json');
  if (!fs.existsSync(file)) throw new Error(`Missing plugin.json in ${dir}`);
  const m = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!safeId(m.id)) throw new Error('Plugin id must match [a-z0-9._-] and be 2-64 characters.');
  if (!m.name || !m.version) throw new Error('Plugin manifest requires name and version.');
  return {
    id: String(m.id), name: String(m.name), version: String(m.version),
    description: String(m.description || ''), author: String(m.author || ''),
    entry: String(m.entry || 'index.js'),
    permissions: Array.isArray(m.permissions) ? m.permissions.map(String) : [],
    forgex: m.forgex || '*',
  };
}

function list() {
  ensureRoot();
  return db.all('SELECT * FROM plugins ORDER BY name COLLATE NOCASE').map((p) => ({
    ...p,
    enabled: Boolean(p.enabled),
    installed: fs.existsSync(path.join(ROOT, p.id)),
  }));
}

function get(id) { return db.get('SELECT * FROM plugins WHERE id = ?', id); }

function registerHook(name, fn, pluginId) {
  if (typeof fn !== 'function') throw new TypeError(`Plugin hook ${name} must be a function`);
  if (!hooks.has(name)) hooks.set(name, []);
  hooks.get(name).push({ pluginId, fn });
}

function contextFor(id) {
  return {
    id,
    root: path.join(ROOT, id),
    version: require('../../package.json').version,
    on(name, fn) { registerHook(name, fn, id); },
    logger: logger.child({ plugin: id }),
    // HTTP routes are intentionally not exposed directly to plugins. Plugins
    // use lifecycle hooks and the documented public API surface instead; this
    // keeps extension code from bypassing ForgeX authentication middleware.
  };
}

function load(id, app) {
  if (loaded.has(id)) return loaded.get(id);
  const row = get(id);
  if (!row || !row.enabled) return null;
  const dir = path.join(ROOT, id);
  const manifest = manifestFrom(dir);
  const entry = path.resolve(dir, manifest.entry);
  if (!entry.startsWith(path.resolve(dir) + path.sep) || !fs.existsSync(entry)) throw new Error(`Plugin entry not found: ${manifest.entry}`);
  const mod = require(entry);
  const ctx = contextFor(id);
  const register = typeof mod === 'function' ? mod : mod && mod.register;
  if (typeof register !== 'function') throw new Error('Plugin entry must export a function or { register }.');
  register(ctx);
  const loadedPlugin = { ...manifest, module: mod };
  loaded.set(id, loadedPlugin);
  return loadedPlugin;
}

function loadEnabled(app) {
  ensureRoot();
  for (const p of list()) {
    if (!p.enabled || !p.installed) continue;
    try { load(p.id, app); logger.info('Loaded ForgeX plugin.', { id: p.id, version: p.version }); }
    catch (err) { logger.error({ err, plugin: p.id }, 'Failed to load ForgeX plugin.'); }
  }
  return loaded.size;
}

function installFromDirectory(sourceDir) {
  ensureRoot();
  const manifest = manifestFrom(sourceDir);
  const target = path.join(ROOT, manifest.id);
  fs.cpSync(sourceDir, target, { recursive: true, force: true });
  // Validate entry before changing the DB.
  manifestFrom(target);
  db.run(`INSERT INTO plugins(id,name,version,description,author,entry,enabled)
    VALUES(?,?,?,?,?,?,1)
    ON CONFLICT(id) DO UPDATE SET name=excluded.name,version=excluded.version,
      description=excluded.description,author=excluded.author,entry=excluded.entry,
      updated_at=datetime('now')`, manifest.id, manifest.name, manifest.version,
    manifest.description, manifest.author, manifest.entry);
  return manifest;
}

function setEnabled(id, enabled) {
  const r = db.run("UPDATE plugins SET enabled=?, updated_at=datetime('now') WHERE id=?", enabled ? 1 : 0, id);
  if (!r.changes) throw new Error('Plugin not found.');
  if (!enabled) loaded.delete(id);
  return get(id);
}

function uninstall(id) {
  if (!safeId(id)) throw new Error('Invalid plugin id.');
  loaded.delete(id);
  db.run('DELETE FROM plugins WHERE id=?', id);
  fs.rmSync(path.join(ROOT, id), { recursive: true, force: true });
}

async function emit(name, payload) {
  const entries = hooks.get(name) || [];
  for (const { fn, pluginId } of entries) {
    try { await fn(payload); } catch (err) { logger.error({ err, plugin: pluginId, hook: name }, 'Plugin hook failed.'); }
  }
}

module.exports = { ROOT, list, get, loadEnabled, installFromDirectory, setEnabled, uninstall, emit, safeId };
