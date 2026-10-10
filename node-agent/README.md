# ForgeX Node Agent — Release

Docker-only node agent for ForgeX. It provisions and controls ForgeX-managed containers and sends authenticated heartbeats to the panel.

## Run

```bash
export MINEFORGE_NODE_ID=node_xxx
export MINEFORGE_NODE_TOKEN=mfnode_xxx
export MINEFORGE_PANEL_URL=https://panel.example.com
export MINEFORGE_NODE_PORT=8080
export MINEFORGE_DATA_ROOT=/var/lib/mineforge
node node-agent/agent.js
```

The node must have Docker Engine available and the selected TCP daemon port reachable from the panel.

Remote extra bind paths are intentionally restricted to `MINEFORGE_DATA_ROOT` to prevent a compromised panel request from mounting arbitrary host paths.
