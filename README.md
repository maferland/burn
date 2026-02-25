<div align="center">
<h1>🔥 Burn</h1>

<img src="assets/icon.png" width="128" height="128" alt="Burn Icon">

<p>Track your Claude Code spending from the macOS menu bar</p>
</div>

---

<p align="center">
  <img src="assets/popover.png" width="400" alt="Burn screenshot showing menu bar popover with daily spend, 7-day chart, and monthly total">
</p>

See today's cost at a glance. Click for a 7-day chart and monthly total.

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

- **Click** — Popover with today's cost, 7-day bar chart, and monthly total
- **Refresh** — Manual refresh button, or auto-refresh every 1–30 minutes
- **Menu bar display** — Show icon only, dollar amount, or both
- **Start at Login** — Run automatically when you log in
- **Quit** — ⌘Q

## Privacy

Burn reads Claude Code session data directly from `~/.claude/projects/`. Model pricing is fetched from [LiteLLM](https://github.com/BerriAI/litellm) and cached locally. No data collection. No analytics.

## Requirements

- macOS 14 (Sonoma) or later

## Support

If Burn helps you track your spending, consider buying me a coffee:

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow?style=for-the-badge&logo=buy-me-a-coffee)](https://buymeacoffee.com/maferland)

## License

MIT — see [LICENSE](LICENSE)
