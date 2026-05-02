# opencode-setup

One-command setup for [OpenCode](https://opencode.ai) with oh-my-openagent, GSD workflow, and full skill ecosystem.

```bash
curl -fsSL https://raw.githubusercontent.com/Liber1917/opencode-setup/main/setup-opencode-complete.sh | bash
```

Or clone and run:

```bash
git clone https://github.com/Liber1917/opencode-setup.git
cd opencode-setup
./setup-opencode-complete.sh
```

## What This Does

Configures a production-ready OpenCode environment from scratch:

```
~/.config/opencode/
├── opencode.json           ← provider + plugin config
├── oh-my-openagent.json    ← agent model routing
├── node_modules/           ← oh-my-openagent plugin
├── get-shit-done/          ← GSD workflow (auto-cloned)
└── skills/                 ← symlinked skill library

~/.claude/
└── settings.json           ← hooks config
```

**Zero assumptions.** No pre-installed skills, no GSD, no npm — the script handles everything.

## Scripts

| Script | Purpose |
|--------|---------|
| `setup-opencode-complete.sh` | Full install from scratch (recommended) |
| `setup-opencode-portable.sh` | Custom paths via env vars |
| `setup-opencode.sh` | Quick setup for standard environments |
| `backup-opencode-config.sh` | Backup existing config before changes |

## Configuration

After running the setup script, edit your API key:

```bash
nano ~/.config/opencode/opencode.json
```

```json
{
  "provider": {
    "anthropic": {
      "options": {
        "apiKey": "<your-key>",
        "baseURL": "https://api.anthropic.com"
      }
    }
  }
}
```

For proxy endpoints (e.g. claude-code.club), change `baseURL`.

### Model Routing

Edit `~/.config/opencode/oh-my-openagent.json` to assign different models per agent/category:

```json
{
  "agents": {
    "oracle": {"model": "anthropic/claude-opus-4-6"},
    "explore": {"model": "anthropic/claude-sonnet-4-6"},
    "sisyphus-junior": {"model": "anthropic/claude-sonnet-4-6"}
  },
  "categories": {
    "ultrabrain": {"model": "anthropic/claude-opus-4-6"},
    "quick": {"model": "anthropic/claude-haiku-4-6"}
  }
}
```

## Custom Paths

Override default locations via environment variables:

```bash
export OPENCODE_CONFIG_DIR=/custom/opencode
export CLAUDE_CONFIG_DIR=/custom/claude
export ORCHESTRA_SKILLS_DIR=/custom/orchestra
export AGENTS_SKILLS_DIR=/custom/agents
./setup-opencode-portable.sh
```

## What Gets Installed

### Agents (10)

| Agent | Role |
|-------|------|
| hephaestus | Build and implement |
| oracle | Architecture, debugging, high-IQ reasoning |
| librarian | External docs, OSS code search |
| explore | Codebase pattern discovery |
| multimodal-looker | PDF/image analysis |
| prometheus | Planning and strategy |
| metis | Pre-planning consultant |
| momus | Plan review and critique |
| atlas | Knowledge management |
| sisyphus-junior | Focused task execution |

### Categories (8)

| Category | Domain |
|----------|--------|
| visual-engineering | Frontend, UI/UX, CSS |
| ultrabrain | Hard logic, algorithms |
| deep | Autonomous problem-solving |
| artistry | Creative/unconventional approaches |
| quick | Single-file trivial changes |
| unspecified-low | Low effort misc |
| unspecified-high | High effort misc |
| writing | Documentation, prose |

### GSD Workflow

Automatically installed. Provides project lifecycle management:
- `/gsd-new-project` → Initialize project
- `/gsd-plan-phase` → Create execution plans
- `/gsd-execute-phase` → Execute with atomic commits
- `/gsd-progress` → Track status
- `/gsd-help` → Full command list

## Requirements

- OpenCode ≥ 1.4.6
- Node.js / npm (auto-installed if missing)
- git (for GSD clone)

## Troubleshooting

**"未检测到 OpenCode 环境"** — Run inside an OpenCode terminal session.

**npm install fails** — Install Node.js manually:
```bash
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs
```

**GSD clone fails** — Clone manually:
```bash
git clone https://github.com/OpenAgentsInc/gsd.git ~/.config/opencode/get-shit-done
```

**Config not taking effect** — Restart OpenCode after changes.

## License

MIT
