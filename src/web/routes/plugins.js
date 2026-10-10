'use strict';

const express = require('express');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { requireRole } = require('../middleware/auth');
const plugins = require('../../services/plugins');
const asyncHandler = require('../middleware/asyncHandler');
const multer = require('multer');
const { execFileSync } = require('node:child_process');

const router = express.Router();
const upload = multer({ dest: os.tmpdir() });

router.get('/plugins', requireRole('admin'), (req, res) => {
  const items = plugins.list();
  res.render('plugins', { title: 'Plugins', active: 'plugins', plugins: items, enabledCount: items.filter((p) => p.enabled).length });
});

router.get('/api/plugins', requireRole('admin'), (req, res) => res.json({ ok: true, plugins: plugins.list() }));

router.post('/api/plugins/:id/enable', requireRole('admin'), (req, res) => {
  res.json({ ok: true, plugin: plugins.setEnabled(req.params.id, true), restartRequired: true });
});
router.post('/api/plugins/:id/disable', requireRole('admin'), (req, res) => {
  res.json({ ok: true, plugin: plugins.setEnabled(req.params.id, false), restartRequired: true });
});
router.delete('/api/plugins/:id', requireRole('admin'), (req, res) => {
  plugins.uninstall(req.params.id);
  res.json({ ok: true });
});

router.post('/api/plugins/install', requireRole('admin'), upload.single('plugin'), asyncHandler(async (req, res) => {
  if (!req.file) return res.status(400).json({ ok: false, error: 'Plugin ZIP is required.' });
  const work = `${req.file.path}.dir`;
  try {
    fs.mkdirSync(work, { recursive: true });
    const names = execFileSync('unzip', ['-Z1', req.file.path], { encoding: 'utf8' }).split(/\r?\n/).filter(Boolean);
    if (names.some((n) => n.startsWith('/') || n.includes('\0') || n.split('/').includes('..'))) {
      throw new Error('Unsafe ZIP path detected.');
    }
    // unzip is used only to unpack into a private temporary directory.
    // Plugin manifest validation happens before anything is installed.
    execFileSync('unzip', ['-q', '-o', req.file.path, '-d', work], { stdio: 'pipe' });
    let source = work;
    const entries = fs.readdirSync(work);
    if (entries.length === 1 && fs.statSync(path.join(work, entries[0])).isDirectory()) source = path.join(work, entries[0]);
    const manifest = plugins.installFromDirectory(source);
    res.status(201).json({ ok: true, plugin: manifest, restartRequired: true });
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
    fs.rmSync(req.file.path, { force: true });
  }
}));

module.exports = router;
