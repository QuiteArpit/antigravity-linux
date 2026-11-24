# Antigravity Linux Installer

```
 █████╗ ███╗   ██╗████████╗██╗ ██████╗ ██████╗  █████╗ ██╗   ██╗██╗████████╗██╗   ██╗
██╔══██╗████╗  ██║╚══██╔══╝██║██╔════╝ ██╔══██╗██╔══██╗██║   ██║██║╚══██╔══╝╚██╗ ██╔╝
███████║██╔██╗ ██║   ██║   ██║██║  ███╗██████╔╝███████║██║   ██║██║   ██║    ╚████╔╝
██╔══██║██║╚██╗██║   ██║   ██║██║   ██║██╔══██╗██╔══██║╚██╗ ██╔╝██║   ██║     ╚██╔╝
██║  ██║██║ ╚████║   ██║   ██║╚██████╔╝██║  ██║██║  ██║ ╚████╔╝ ██║   ██║      ██║
╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚═╝   ╚═╝      ╚═╝

                   ██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗
                   ██║     ██║████╗  ██║██║   ██║╚██╗██╔╝
                   ██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝
                   ██║     ██║██║╚██╗██║██║   ██║ ██╔██╗
                   ███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗
                   ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝
```

> **This is a community helper. Not affiliated with, endorsed by, or supported by Google.**

One-command Linux installer and updater for **Google Antigravity 2.0**, **Antigravity IDE**, and the official **Antigravity CLI (`agy`)** using Google's official release tarballs and scripts.

This project does **not** mirror, modify, or redistribute Google Antigravity. The installer dynamically resolves the latest official Google downloads from [https://antigravity.google/download](https://antigravity.google/download) at install/update time, integrates them cleanly into your desktop environment, and manages updates with a full-screen interactive TUI.


## Features

- **Interactive TUI Installer & Updater:**
  - Full-screen terminal wizard with ASCII branding and a 3-step progress stepper.
  - **Live Version Comparison:** Queries Google releases in real-time and compares with locally installed versions (`(v2.35.0 installed • Up to date)` or `(v2.34.0 installed ➜ v2.35.0 update available)`).
  - **In-TUI Live Progress:** Live download progress bars (`curl --progress-bar`) and file extraction counters streamed inside the TUI.
  - **Force Reinstall Toggle:** Re-download and overwrite existing installations directly from the interactive menu without needing CLI flags.
  - Completion summary with a `"Press any key to exit"` prompt that cleanly restores your terminal.
- **Official Google Downloads:** Resolves official tarballs dynamically at runtime with zero third-party repackaging.
- **Comprehensive Component Management:**
  - **Antigravity 2.0 Desktop:** Autonomous AI agent application.
  - **Antigravity IDE:** Code development studio.
  - **Antigravity CLI (`agy`):** Installs and updates Google's official CLI command, dropping root privileges to user space (`~/.local/bin/agy`).
  - **Nautilus Context Menu:** Optional GNOME Files right-click menu integration (auto-disabled on systems without Nautilus, such as Fedora KDE).
- **Multi-Distro Support:** Native automatic dependency resolution for Debian/Ubuntu (`apt-get`) and Fedora/RHEL (`dnf`).
- **Offline-First Script Caching:**
  - Automatically caches the installer locally at `/etc/antigravity-linux/install.sh`.
  - Auto-checks for new installer versions on GitHub Pages with syntax validation (`bash -n`).
  - Falls back gracefully to the locally cached installer if network is offline or remote is unreachable.
- **Desktop & Launcher Integration:**
  - High-resolution application icons extracted directly from tarball ASAR bundles.
  - Desktop entries (`.desktop`) with proper MIME associations and window classes.
  - System-wide command-line launchers: `antigravity`, `antigravity-ide`, `antigravity-linux`.
- **Security:** Preserves Electron/Chromium sandbox setuid permissions (`4755`) instead of running with `--no-sandbox`.

## Minimum Requirements
> `glibc >= 2.28, glibcxx >= 3.4.25 (e.g. Ubuntu 20+, Debian 10+, Fedora 36+, RHEL 8+)`

## Interactive Setup (Recommended)

Run the one-liner to launch the interactive TUI installer:

```bash
INSTALLER_URL="https://quitearpit.github.io/antigravity-linux/install.sh"
curl -fsSL "$INSTALLER_URL" | sudo -E env ANTIGRAVITY_LINUX_INSTALLER_URL="$INSTALLER_URL" bash
```

Use the interactive wizard to select components, toggle Force Reinstall, and observe real-time download and extraction progress.

## Non-Interactive & Headless Installs

Append `-y` (or specific flags) to run non-interactively in automated scripts or CI/CD pipelines:

Install Desktop app and IDE:

```bash
INSTALLER_URL="https://quitearpit.github.io/antigravity-linux/install.sh"
curl -fsSL "$INSTALLER_URL" | sudo -E env ANTIGRAVITY_LINUX_INSTALLER_URL="$INSTALLER_URL" bash -s -- --all -y
```

Install Antigravity 2.0 Desktop only:

```bash
INSTALLER_URL="https://quitearpit.github.io/antigravity-linux/install.sh"
curl -fsSL "$INSTALLER_URL" | sudo -E env ANTIGRAVITY_LINUX_INSTALLER_URL="$INSTALLER_URL" bash -s -- --desktop -y
```

Install Antigravity IDE only:

```bash
INSTALLER_URL="https://quitearpit.github.io/antigravity-linux/install.sh"
curl -fsSL "$INSTALLER_URL" | sudo -E env ANTIGRAVITY_LINUX_INSTALLER_URL="$INSTALLER_URL" bash -s -- --ide -y
```

## Update & Maintenance

Once installed, use the helper commands anytime:

- **Launch Interactive Updater (TUI):**
  ```bash
  sudo antigravity-linux
  ```
  *(Or `sudo antigravity-linux update --all`)*

- **Update Desktop App (Pre-selected in TUI):**
  ```bash
  sudo update-antigravity
  ```

- **Update IDE (Pre-selected in TUI):**
  ```bash
  sudo update-antigravity-ide
  ```

- **Silent / Automated Updates:**
  Pass `-y` to skip the TUI:
  ```bash
  sudo antigravity-linux update --all -y
  ```

## Status

Check installed versions, paths, and update helper status:

```bash
antigravity-linux --status
```

## Uninstall

Remove helper-managed binaries, desktop entries, icons, and local cached installer:

```bash
sudo antigravity-linux --uninstall
```

*(User settings, configs, and projects in home directories are left completely untouched.)*

## Options

```text
--desktop          Install or update Antigravity 2.0 desktop app
--ide              Install or update Antigravity IDE
--all              Install or update both Desktop app and IDE
--cli              Run Google's official Antigravity CLI installer/updater
--no-nautilus      Skip GNOME Files/Nautilus context-menu helper
--no-apt           Skip automatic dependency installation
--force            Reinstall even when the recorded version matches
--install-url URL  Store the custom update helper URL
--status           Show installed helper-managed apps and versions
--print-downloads  Print resolved official Google tarball URLs
--uninstall        Remove helper-managed installation
-y, --yes          Non-interactive; assume yes where possible
```

## What it installs

| Component | Path |
|---|---|
| Antigravity 2.0 | `/opt/antigravity` |
| Antigravity IDE | `/opt/antigravity-ide` |
| Antigravity CLI | `~/.local/bin/agy` |
| System Launchers | `/usr/local/bin/antigravity`, `/usr/local/bin/antigravity-ide` |
| Update Manager | `/usr/local/bin/antigravity-linux` |
| Helper Commands | `/usr/local/bin/update-antigravity`, `/usr/local/bin/update-antigravity-ide` |
| Cached Installer | `/etc/antigravity-linux/install.sh` |
| Desktop Entries | `/usr/share/applications/antigravity*.desktop` |
| High-Res Icons | `/usr/share/icons/hicolor/512x512/apps/` |
| Nautilus Helper | `/usr/share/nautilus-python/extensions/open-in-antigravity-ide.py` |

## Supported systems

Designed for modern Linux distributions (glibc >= 2.28):

- **Debian / Ubuntu / Linux Mint / Pop!_OS** (`apt-get`)
- **Fedora / RHEL / CentOS Stream / Rocky Linux** (`dnf`)
- **Arch Linux / openSUSE / other distributions** (requires manual installation of prerequisites)

### Automatic Dependency Management

On supported package managers, the installer checks for missing tools and installs them automatically (unless `--no-apt` is passed):

- **Debian/Ubuntu (`apt-get`)**: `ca-certificates`, `curl`, `tar`, `python3`, `desktop-file-utils`, `xdg-utils`, and `python3-nautilus` (optional).
- **Fedora/RHEL (`dnf`)**: `ca-certificates`, `curl`, `tar`, `python3`, `desktop-file-utils`, `xdg-utils`, and `nautilus-python` (optional).

On other Linux distributions, ensure the following core tools are installed:

- `bash`, `curl`, `tar`, `python3`, `desktop-file-utils`, `xdg-utils`

## GitHub Pages setup

This repository includes a GitHub Actions workflow at `.github/workflows/pages.yml` that deploys the `docs/` directory to GitHub Pages.

1. Use this repository, `QuiteArpit/antigravity-linux`, or fork it under your own account.
2. Push your changes to the `main` branch.
3. Open **Settings → Pages**.
4. Set **Build and deployment → Source** to **GitHub Actions**.
5. Run or wait for the **Deploy GitHub Pages** workflow.
6. Your installer will be available at:

```text
https://quitearpit.github.io/antigravity-linux/install.sh
```

## Local development

Clone the repository:

```bash
git clone https://github.com/QuiteArpit/antigravity-linux.git
cd antigravity-linux
```

Run local checks:

```bash
bash scripts/check.sh
```

Sync the GitHub Pages copy of the installer:

```bash
bash scripts/sync-site.sh
```

Install from the local checkout:

```bash
sudo bash install.sh --all
```

## Security notes

This installer uses `sudo` because it installs system-wide files under `/opt`, `/usr/local/bin`, `/usr/share/applications`, and `/usr/share/icons`.

For safer review before running:

```bash
curl -fsSL "https://quitearpit.github.io/antigravity-linux/install.sh" -o install.sh
less install.sh
sudo bash install.sh --all
```

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

> Read the [contributing guidelines](CONTRIBUTING.md) for more information.

The easiest way to contribute is to check whether this works smoothly on your OS and if any issues arise, [open an issue](https://github.com/QuiteArpit/antigravity-linux/issues/new), describe the problem, your system details, and screenshots (if possible).

### Currently Confirmed OSes

- Ubuntu 24.04 LTS & 26.04
- Debian 12 / 13
- Fedora 40 / 41 / 42 / 43 / 44 (KDE Plasma & GNOME)

## License

MIT. See [LICENSE](LICENSE).
