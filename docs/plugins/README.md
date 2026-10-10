# ForgeX Plugins

ForgeX plugins are trusted server-side extensions. A plugin is a directory containing `plugin.json` and its entry module. Plugins run inside the ForgeX Node.js process, so only install code you trust.

## Manifest

```json
{
  "id": "discord-notifier",
  "name": "Discord Notifier",
  "version": "1.0.0",
  "description": "Send server lifecycle notifications to Discord.",
  "author": "Example",
  "entry": "index.js",
  "permissions": ["events", "network"]
}
```

## Entry module

```js
module.exports.register = (forgex) => {
  forgex.on('server:started', async ({ serverId, actor }) => {
    // Call your integration here.
  });

  forgex.on('server:stopped', async ({ serverId, actor }) => {
    // Call your integration here.
  });
};
```

## Lifecycle hooks currently exposed

- `server:started`
- `server:stopped`
- `server:restarted`
- `server:killed`

More hooks can be added without changing the plugin contract.

## Installation

Administrators can install a plugin ZIP from **Administration → Plugins**. The ZIP must contain `plugin.json` and the declared entry file. ForgeX validates ZIP paths before extraction.

Enabling, disabling, installing, and removing a plugin requires a ForgeX restart before runtime hooks are active.
