<div align="center">
<h1>🔥 Burn</h1>

<img src="assets/icon.png" width="128" height="128" alt="Burn Icon">

<p>Track your Claude Code and Codex spending from the macOS menu bar</p>

<p><a href="https://burn.maferland.com">burn.maferland.com</a></p>
</div>

---

<p align="center">
  <img src="assets/popover.png" width="400" alt="Burn screenshot showing menu bar popover with today's burn rate, pace against a typical day, and per-model breakdown">
</p>

See today's burn rate at a glance, projected against a typical day. Switch to Week or Month, or flip the header chip between Claude, Codex, or everything combined.

## Install

**Homebrew** (recommended):
```bash
brew install --cask maferland/tap/burn
```

**Manual**: Download DMG from [Releases](https://github.com/maferland/burn/releases), open it, drag `Burn.app` to Applications.

**Build from source**:
```bash
git clone https://github.com/maferland/burn.git
cd burn
make install
```

## Usage

Run `Burn`. A flame icon appears in your menu bar with today's spend.

- **Click** — Popover with today's burn rate, pace against a typical day, and per-model breakdown
- **Refresh** — Manual refresh button, or auto-refresh every 1–30 minutes
- **Providers** — Connect Claude Code and Codex; scope the popover to one or view them combined
- **Start at Login** — Run automatically when you log in
- **Quit** — ⌘Q

## Extensions

Burn can show extra signals next to the cost. Extensions contribute a menu bar segment and a popover tab. They're toggled in **Settings → Extensions**.

### PRs

Tracks pull requests opened and merged today, this week, and this month, with your typical pace for that scope.

Requires the [GitHub CLI](https://cli.github.com/) authenticated:

```bash
brew install gh
gh auth login
```

In **Settings → Extensions → PRs**, add one or more hosts. For GitHub, set the org(s) to filter, comma-separated (e.g. `acme, maferland`) — leave empty to count every PR you can see. For self-hosted Gitea or Forgejo, add a host (e.g. `git.example.com`) with an access token carrying the `read:issue` scope, generated at `https://<host>/user/settings/applications`. Tokens go to your Keychain, never to disk in plain text.

### Limits

Shows how close your Claude and Codex plan limits are to resetting, with a warning when a window crosses 85% used.

## Privacy

Burn reads Claude Code session data directly from `~/.claude/projects/` and Codex session data from its local CLI logs. PR and Limits extensions call the GitHub/Gitea/Forgejo and provider plan APIs you configure. Model pricing is fetched from [LiteLLM](https://github.com/BerriAI/litellm) and cached locally. No data collection. No analytics.

## Requirements

- macOS 14 (Sonoma) or later

## Support

If Burn helps you track your spending, consider buying me a coffee:

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow?style=for-the-badge&logo=buy-me-a-coffee)](https://buymeacoffee.com/maferland)

## License

MIT — see [LICENSE](LICENSE)
