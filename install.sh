#!/usr/bin/env bash
# Antigravity Linux Installer
# Installs/updates Google Antigravity 2.0 and, optionally, Antigravity IDE on Debian/Ubuntu.
# It resolves the latest official Google tarballs from https://antigravity.google/download.
set -euo pipefail

ORIGINAL_ARGS=("$@")
PROJECT_NAME="antigravity-linux"
DOWNLOAD_PAGE="https://antigravity.google/download"
CLI_INSTALLER="https://antigravity.google/cli/install.sh"
INSTALL_DESKTOP=1
INSTALL_IDE=0
INSTALL_CLI=0
EXPLICIT_PRODUCT=0
INSTALL_NAUTILUS=1
INSTALL_DEPS=1
DO_UNINSTALL=0
DO_STATUS=0
DO_PRINT_DOWNLOADS=0
FORCE=0
YES=0
DEFAULT_INSTALLER_URL="https://quitearpit.github.io/antigravity-linux/install.sh"
INSTALLER_URL="${ANTIGRAVITY_LINUX_INSTALLER_URL:-$DEFAULT_INSTALLER_URL}"
IS_TUI_ACTIVE=0
tmpdir=""

cleanup_tui() {
  if [ "$IS_TUI_ACTIVE" -eq 1 ]; then
    IS_TUI_ACTIVE=0
    tput cnorm >&4 2>/dev/null || true
    tput rmcup >&4 2>/dev/null || true
    exec 3<&- 2>/dev/null || true
    exec 4>&- 2>/dev/null || true
  fi
}

cleanup_all() {
  cleanup_tui
  rm -rf "${tmpdir:-}"
}

log() {
  if [ "$IS_TUI_ACTIVE" -eq 1 ]; then
    printf '   %s\n' "$*" >&4
  else
    printf '%s\n' "$*"
  fi
}

warn() {
  if [ "$IS_TUI_ACTIVE" -eq 1 ]; then
    printf '   \033[1;33mWARN:\033[0m %s\n' "$*" >&4
  else
    printf 'WARN: %s\n' "$*" >&2
  fi
}

err() {
  if [ "$IS_TUI_ACTIVE" -eq 1 ]; then
    printf '   \033[1;31mERROR:\033[0m %s\n' "$*" >&4
    cleanup_tui
  else
    printf 'ERROR: %s\n' "$*" >&2
  fi
  exit 1
}

need() { command -v "$1" >/dev/null 2>&1 || err "Required command not found: $1"; }

download_file() {
  local url="$1"
  local dest="$2"
  if [ "$IS_TUI_ACTIVE" -eq 1 ]; then
    printf '   ' >&4
    curl -fL --progress-bar --retry 3 -o "$dest" "$url" 2>&4
    printf '\n' >&4
  elif [ -t 1 ]; then
    curl -fL --progress-bar --retry 3 -o "$dest" "$url"
  else
    curl -fsSL --retry 3 -o "$dest" "$url"
  fi
}

extract_archive() {
  local archive="$1"
  local dest="$2"
  if [ "$IS_TUI_ACTIVE" -eq 1 ]; then
    printf '   Extracting archive... ' >&4
    tar -xzf "$archive" -C "$dest" --checkpoint=500 --checkpoint-action=dot >&4 2>&4
    printf '\r\033[K   Extracting archive: Done.\n' >&4
  elif [ -t 1 ]; then
    printf 'Extracting archive... '
    tar -xzf "$archive" -C "$dest" --checkpoint=500 --checkpoint-action=dot
    printf '\r\033[KExtracting archive: Done.\n'
  else
    tar -xzf "$archive" -C "$dest"
  fi
}

usage() {
  cat <<'USAGE'
Antigravity Linux Installer

Usage:
  install.sh [install|update] [options]
  install.sh --status
  install.sh --print-downloads
  install.sh --uninstall

Default:
  Installs or updates Antigravity 2.0 desktop app system-wide.

Options:
  --desktop              Install/update Antigravity 2.0 desktop app only (default)
  --ide                  Install/update Antigravity IDE only
  --all                  Install/update Antigravity 2.0 desktop app + Antigravity IDE
  --cli                  Also run Google's official Antigravity CLI installer
  --no-nautilus          Skip GNOME Files/Nautilus context-menu helper
  --no-apt               Do not install apt dependencies automatically
  --force                Reinstall even when the recorded version matches
  --install-url URL      Store URL used by the antigravity-linux update command
  --status               Show installed helper-managed apps and versions
  --print-downloads      Print the resolved official Google tarball URLs
  --uninstall            Remove helper-managed Antigravity desktop/IDE files
  -y, --yes              Non-interactive; assume yes where possible
  -h, --help             Show this help

Recommended GitHub Pages one-liner:
  INSTALLER_URL="https://YOUR_GITHUB_USERNAME.github.io/antigravity-linux/install.sh"; \
  curl -fsSL "$INSTALLER_URL" | sudo -E env ANTIGRAVITY_LINUX_INSTALLER_URL="$INSTALLER_URL" bash -s -- --all

Update after install:
  sudo antigravity-linux update --all
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    install|update) ;;
    --desktop) INSTALL_DESKTOP=1; INSTALL_IDE=0; EXPLICIT_PRODUCT=1 ;;
    --ide) INSTALL_DESKTOP=0; INSTALL_IDE=1; EXPLICIT_PRODUCT=1 ;;
    --all) INSTALL_DESKTOP=1; INSTALL_IDE=1; EXPLICIT_PRODUCT=1 ;;
    --cli) INSTALL_CLI=1; EXPLICIT_PRODUCT=1 ;;
    --no-nautilus) INSTALL_NAUTILUS=0 ;;
    --no-apt) INSTALL_DEPS=0 ;;
    --force) FORCE=1 ;;
    --install-url)
      shift
      [ $# -gt 0 ] || err "--install-url needs a URL"
      INSTALLER_URL="$1"
      ;;
    --status) DO_STATUS=1 ;;
    --print-downloads) DO_PRINT_DOWNLOADS=1 ;;
    --uninstall) DO_UNINSTALL=1 ;;
    -y|--yes) YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1" ;;
  esac
  shift
done

if [ "$(uname -s)" != "Linux" ]; then
  err "This installer is for Linux only."
fi

case "$(uname -m)" in
  x86_64|amd64) AG_PLATFORM="linux-x64"; DESKTOP_TOP="Antigravity-x64" ;;
  aarch64|arm64) AG_PLATFORM="linux-arm"; DESKTOP_TOP="Antigravity-arm64" ;;
  *) err "Unsupported CPU architecture: $(uname -m). Google currently provides x64 and ARM64 Linux builds." ;;
esac

require_root_or_reexec() {
  if [ "$(id -u)" -eq 0 ]; then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1 && [ -n "${BASH_SOURCE[0]:-}" ] && [ -r "${BASH_SOURCE[0]}" ] && [ "${BASH_SOURCE[0]}" != "bash" ] && [ "${BASH_SOURCE[0]}" != "sh" ]; then
    exec sudo -E env "ANTIGRAVITY_LINUX_INSTALLER_URL=$INSTALLER_URL" bash "${BASH_SOURCE[0]}" ${ORIGINAL_ARGS[@]+"${ORIGINAL_ARGS[@]}"}
  fi
  err "System-wide install needs root. Use: curl -fsSL <installer-url> | sudo -E env ANTIGRAVITY_LINUX_INSTALLER_URL=<installer-url> bash"
}

install_base_deps() {
  [ "$INSTALL_DEPS" -eq 1 ] || return 0
  if command -v apt-get >/dev/null 2>&1; then
    local packages=(ca-certificates curl tar python3 desktop-file-utils xdg-utils)
    local missing=()
    for pkg in "${packages[@]}"; do
      if ! dpkg -s "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
        missing+=("$pkg")
      fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
      export DEBIAN_FRONTEND=noninteractive
      log "Installing missing package dependencies: ${missing[*]}..."
      apt-get update
      apt-get install -y "${missing[@]}"
    fi
  elif command -v dnf >/dev/null 2>&1; then
    local packages=(ca-certificates curl tar python3 desktop-file-utils xdg-utils)
    local missing=()
    for pkg in "${packages[@]}"; do
      if ! rpm -q "$pkg" >/dev/null 2>&1; then
        missing+=("$pkg")
      fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
      log "Installing missing package dependencies: ${missing[*]}..."
      dnf install -y "${missing[@]}"
    fi
  else
    for c in curl tar python3; do need "$c"; done
  fi
}

install_deps() {
  [ "$INSTALL_DEPS" -eq 1 ] || return 0
  if [ "$INSTALL_NAUTILUS" -eq 1 ] && [ "$INSTALL_IDE" -eq 1 ]; then
    if command -v apt-get >/dev/null 2>&1; then
      if ! dpkg -s python3-nautilus 2>/dev/null | grep -q 'install ok installed'; then
        export DEBIAN_FRONTEND=noninteractive
        log "Installing missing package dependency: python3-nautilus..."
        if [ "$IS_TUI_ACTIVE" -eq 1 ]; then
          apt-get update >&4 2>&4
          apt-get install -y python3-nautilus >&4 2>&4
        else
          apt-get update
          apt-get install -y python3-nautilus
        fi
      fi
    elif command -v dnf >/dev/null 2>&1 && command -v nautilus >/dev/null 2>&1; then
      if ! rpm -q nautilus-python >/dev/null 2>&1; then
        log "Installing missing package dependency: nautilus-python..."
        if [ "$IS_TUI_ACTIVE" -eq 1 ]; then
          dnf install -y nautilus-python >&4 2>&4
        else
          dnf install -y nautilus-python
        fi
      fi
    fi
  fi
}

resolve_download_source() {
  local tmpdir="$1"
  local html="$tmpdir/download.html"
  local js="$tmpdir/download.js"
  curl -fsSL --compressed --retry 3 -o "$html" "$DOWNLOAD_PAGE"

  # Google's download page may embed tarball URLs directly in the HTML
  # (current Astro-based layout) or inside a separate JS bundle (older layout).
  # Try the HTML first; fall back to downloading a JS bundle if needed.
  if grep -qP 'https?:(?://|\\/\\/)[^"'\''<>\s)]+(?:/|\\/)linux-(x64|arm)(?:/|\\/)[^"'\''<>\s)]+\.tar\.gz' "$html"; then
    cp "$html" "$js"
    printf '%s\n' "$js"
    return 0
  fi

  local main_js_url
  main_js_url=$(python3 - "$html" "$DOWNLOAD_PAGE" <<'PY'
import re, sys
from pathlib import Path
from urllib.parse import urljoin
html = Path(sys.argv[1]).read_text(errors='replace')
page = sys.argv[2]
# Prefer the application bundle that contains the download data.
matches = re.findall(r'(?:src|href)=["\']([^"\']*main-[^"\']+\.js)["\']', html)
if not matches:
    matches = re.findall(r'(?:src|href)=["\']([^"\']+\.js)["\']', html)
if not matches:
    raise SystemExit('Could not find JavaScript bundle on the official Antigravity download page')
print(urljoin(page, matches[-1]))
PY
)
  curl -fsSL --compressed --retry 3 -o "$js" "$main_js_url"

  # If this JS bundle has no tarball URLs, fall back to searching the HTML.
  if ! grep -qP 'https?:(?://|\\/\\/)[^"'\''<>\s)]+(?:/|\\/)linux-(x64|arm)(?:/|\\/)[^"'\''<>\s)]+\.tar\.gz' "$js"; then
    cp "$html" "$js"
  fi

  printf '%s\n' "$js"
}

resolve_download_from_bundle() {
  local js="$1"
  local product="$2"
  python3 - "$js" "$AG_PLATFORM" "$product" <<'PY'
import html, re, sys
from pathlib import Path
from urllib.parse import unquote
bundle = html.unescape(Path(sys.argv[1]).read_text(errors='replace'))
platform = sys.argv[2]
product = sys.argv[3]

# Normalize escaped slashes sometimes found in JS string literals.
text = bundle.replace('\\/', '/')

def fail(msg):
    raise SystemExit(msg)

def version_from_url(url):
    decoded = unquote(url)
    # Known current layouts include antigravity-hub/<version>/ and stable/<version>/.
    for pattern in (r'/antigravity-hub/([^/]+)/', r'/stable/([^/]+)/', r'/(\d+\.\d+\.\d+(?:-[^/]+)?)/'):
        m = re.search(pattern, decoded)
        if m:
            return m.group(1).split('-', 1)[0]
    return 'unknown'

if product == 'desktop':
    # Support both JS-object notation (id:"antigravity-2") and HTML attribute (id="antigravity-2").
    markers      = ['id:"antigravity-2"',   'id="antigravity-2"']
    next_markers = ['id:"antigravity-cli"',  'id="antigravity-cli"']
    filename_patterns = [r'Antigravity\.tar\.gz']
    label = 'Antigravity 2.0'
elif product == 'ide':
    markers      = ['id:"antigravity-ide"',  'id="antigravity-ide"']
    next_markers = ['id:"antigravity-sdk"',  'id="antigravity-sdk"']
    filename_patterns = [r'Antigravity%20IDE\.tar\.gz', r'Antigravity\+IDE\.tar\.gz', r'Antigravity IDE\.tar\.gz']
    label = 'Antigravity IDE'
else:
    fail(f'Unknown product: {product}')

sections = []
for marker, next_marker in zip(markers, next_markers):
    start = text.find(marker)
    if start != -1:
        end = text.find(next_marker, start)
        sections.append(text[start:end if end != -1 else None])
        break
sections.append(text)

for section in sections:
    for filename_re in filename_patterns:
        pattern = r'https?://[^"\'\s<>)]*/' + re.escape(platform) + r'/' + filename_re
        matches = re.findall(pattern, section)
        if matches:
            url = matches[-1]
            print(version_from_url(url), url)
            sys.exit(0)

fail(f'Could not find official {label} tarball for {platform} in Google download bundle')
PY
}

resolve_desktop_download() { resolve_download_from_bundle "$1" desktop; }
resolve_ide_download() { resolve_download_from_bundle "$1" ide; }

asar_extract_icon_png() {
  local asar="$1"
  local out="$2"
  python3 - "$asar" "$out" <<'PY'
import json, struct, sys
from pathlib import Path
asar = Path(sys.argv[1])
out = Path(sys.argv[2])
with asar.open('rb') as f:
    f.read(4)
    header_size = struct.unpack('<I', f.read(4))[0]
    f.read(4)
    json_size = struct.unpack('<I', f.read(4))[0]
    header = json.loads(f.read(json_size).decode())
icon = header.get('files', {}).get('icon.png')
if not icon:
    raise SystemExit('icon.png not found in app.asar')
with asar.open('rb') as f:
    f.seek(8 + header_size + int(icon['offset']))
    out.write_bytes(f.read(int(icon['size'])))
PY
}

safe_replace_dir() {
  local newdir="$1"
  local target="$2"
  rm -rf "${target}.previous"
  if [ -d "$target" ]; then
    mv "$target" "${target}.previous"
  fi
  mv "$newdir" "$target"
}

fix_chrome_sandbox() {
  local sandbox="$1"
  if [ -f "$sandbox" ]; then
    chown root:root "$sandbox"
    chmod 4755 "$sandbox"
  fi
}

refresh_desktop_caches() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q /usr/share/icons/hicolor >/dev/null 2>&1 || true
  fi
}

installed_version() {
  local file="$1"
  cat "$file" 2>/dev/null || true
}

install_desktop_app() {
  local tmpdir="$1"
  local js="$2"
  local version url
  read -r version url < <(resolve_desktop_download "$js")
  local root="/opt/antigravity"
  local target="$root/$DESKTOP_TOP/antigravity"
  local version_file="$root/.antigravity-linux-version"
  local current_ver
  current_ver=$(installed_version "$version_file")

  if [ "$FORCE" -eq 0 ] && [ -x "$target" ] && [ "$current_ver" = "$version" ]; then
    log "Antigravity 2.0 ($version) is already up to date."
    return
  fi

  if [ -x "$target" ] && [ -n "$current_ver" ]; then
    if [ "$current_ver" != "$version" ]; then
      log "Updating Antigravity 2.0 from $current_ver to $version for $AG_PLATFORM from Google..."
    else
      log "Reinstalling Antigravity 2.0 $version for $AG_PLATFORM (--force)..."
    fi
  else
    log "Downloading Antigravity 2.0 $version for $AG_PLATFORM from Google..."
  fi

  local archive="$tmpdir/Antigravity.tar.gz"
  download_file "$url" "$archive"
  tar -tzf "$archive" > "$tmpdir/desktop-list.txt"
  local top_dir
  top_dir=$(sed -n '1{s#/.*##;p;q}' "$tmpdir/desktop-list.txt")
  [ "$top_dir" = "$DESKTOP_TOP" ] || err "Unexpected Antigravity archive layout: $top_dir"
  extract_archive "$archive" "$tmpdir"
  [ -x "$tmpdir/$top_dir/antigravity" ] || err "Antigravity launcher not found inside tarball."

  local icon_staged="$tmpdir/antigravity.png"
  if [ -f "$tmpdir/$top_dir/resources/app.asar" ]; then
    asar_extract_icon_png "$tmpdir/$top_dir/resources/app.asar" "$icon_staged" || warn "Could not extract desktop icon; continuing."
  fi

  rm -rf "${root}.new"
  mkdir -p "${root}.new"
  cp -a "$tmpdir/$top_dir" "${root}.new/"
  printf '%s\n' "$version" > "${root}.new/.antigravity-linux-version"
  printf '%s\n' "$url" > "${root}.new/.antigravity-linux-source-url"
  fix_chrome_sandbox "${root}.new/$top_dir/chrome-sandbox"
  safe_replace_dir "${root}.new" "$root"

  ln -sfn "$root/$top_dir/antigravity" /usr/local/bin/antigravity
  mkdir -p /usr/share/icons/hicolor/512x512/apps /usr/share/applications
  if [ -f "$icon_staged" ]; then
    install -m 0644 "$icon_staged" /usr/share/icons/hicolor/512x512/apps/antigravity.png
  fi
  cat > /usr/share/applications/antigravity.desktop <<DESKTOP
[Desktop Entry]
Name=Antigravity
Comment=Google Antigravity 2.0 agent platform
Exec=/usr/local/bin/antigravity %U
Icon=antigravity
Terminal=false
Type=Application
Categories=Development;IDE;
StartupNotify=true
StartupWMClass=Antigravity
DESKTOP
  refresh_desktop_caches
  log "Deployed Antigravity 2.0 $version at $root/$top_dir"
}

install_ide_app() {
  local tmpdir="$1"
  local js="$2"
  local version url
  read -r version url < <(resolve_ide_download "$js")
  local root="/opt/antigravity-ide"
  local install_dir="Antigravity-IDE"
  local version_file="$root/.antigravity-linux-version"
  local current_ver
  current_ver=$(installed_version "$version_file")

  if [ "$FORCE" -eq 0 ] && [ -x "$root/$install_dir/antigravity-ide" ] && [ "$current_ver" = "$version" ]; then
    log "Antigravity IDE ($version) is already up to date."
    return
  fi

  if [ -x "$root/$install_dir/antigravity-ide" ] && [ -n "$current_ver" ]; then
    if [ "$current_ver" != "$version" ]; then
      log "Updating Antigravity IDE from $current_ver to $version for $AG_PLATFORM from Google..."
    else
      log "Reinstalling Antigravity IDE $version for $AG_PLATFORM (--force)..."
    fi
  else
    log "Downloading Antigravity IDE $version for $AG_PLATFORM from Google..."
  fi

  local archive="$tmpdir/Antigravity-IDE.tar.gz"
  download_file "$url" "$archive"
  tar -tzf "$archive" > "$tmpdir/ide-list.txt"
  local top_dir
  top_dir=$(sed -n '1{s#/.*##;p;q}' "$tmpdir/ide-list.txt")
  [ "$top_dir" = "Antigravity IDE" ] || err "Unexpected Antigravity IDE archive layout: $top_dir"
  extract_archive "$archive" "$tmpdir"
  [ -x "$tmpdir/$top_dir/antigravity-ide" ] || err "Antigravity IDE launcher not found inside tarball."

  rm -rf "${root}.new"
  mkdir -p "${root}.new/$install_dir"
  cp -a "$tmpdir/$top_dir/." "${root}.new/$install_dir/"
  printf '%s\n' "$version" > "${root}.new/.antigravity-linux-version"
  printf '%s\n' "$url" > "${root}.new/.antigravity-linux-source-url"
  fix_chrome_sandbox "${root}.new/$install_dir/chrome-sandbox"
  safe_replace_dir "${root}.new" "$root"

  ln -sfn "$root/$install_dir/antigravity-ide" /usr/local/bin/antigravity-ide
  mkdir -p /usr/share/icons/hicolor/512x512/apps /usr/share/applications
  local icon_source="$root/$install_dir/resources/app/resources/linux/code.png"
  if [ -f "$icon_source" ]; then
    install -m 0644 "$icon_source" /usr/share/icons/hicolor/512x512/apps/antigravity-ide.png
  fi
  cat > /usr/share/applications/antigravity-ide.desktop <<DESKTOP
[Desktop Entry]
Name=Antigravity IDE
Comment=Google Antigravity IDE
Exec=/usr/local/bin/antigravity-ide %F
Icon=antigravity-ide
Terminal=false
Type=Application
Categories=Development;IDE;
MimeType=inode/directory;text/plain;application/x-code-workspace;application/x-antigravity-workspace;x-scheme-handler/antigravity-ide;
StartupNotify=true
StartupWMClass=antigravity-ide
DESKTOP
  refresh_desktop_caches
  log "Deployed Antigravity IDE $version at $root/$install_dir"
}

install_nautilus_extension() {
  [ "$INSTALL_NAUTILUS" -eq 1 ] || return 0
  [ "$INSTALL_IDE" -eq 1 ] || return 0
  if ! command -v nautilus >/dev/null 2>&1; then
    return 0
  fi
  if ! python3 - <<'PY' >/dev/null 2>&1
try:
    import gi
    gi.require_version('Nautilus', '4.0')
except Exception:
    raise SystemExit(1)
PY
  then
    warn "Skipping Nautilus extension because Python Nautilus bindings are unavailable."
    return 0
  fi
  mkdir -p /usr/share/nautilus-python/extensions
  cat > /usr/share/nautilus-python/extensions/open-in-antigravity-ide.py <<'PY'
import subprocess
from urllib.parse import unquote, urlparse
from gi.repository import Nautilus, GObject

class OpenInAntigravityIDE(GObject.GObject, Nautilus.MenuProvider):
    def _path(self, file_info):
        uri = file_info.get_uri()
        parsed = urlparse(uri)
        if parsed.scheme != 'file':
            return None
        return unquote(parsed.path)

    def get_file_items(self, files):
        if not files or len(files) != 1:
            return []
        path = self._path(files[0])
        if not path:
            return []
        item = Nautilus.MenuItem(
            name='OpenInAntigravityIDE::open',
            label='Open in Antigravity IDE',
            tip='Open this folder or file in Antigravity IDE'
        )
        item.connect('activate', lambda _item: subprocess.Popen(['antigravity-ide', path]))
        return [item]

    def get_background_items(self, folder):
        path = self._path(folder)
        if not path:
            return []
        item = Nautilus.MenuItem(
            name='OpenInAntigravityIDE::open_background',
            label='Open Folder in Antigravity IDE',
            tip='Open the current folder in Antigravity IDE'
        )
        item.connect('activate', lambda _item: subprocess.Popen(['antigravity-ide', path]))
        return [item]
PY
  log "Installed Nautilus context-menu helper. Restart Files/Nautilus to see it."
}

install_manager_command() {
  local default_url="https://quitearpit.github.io/antigravity-linux/install.sh"
  local installer_url="${INSTALLER_URL:-$default_url}"
  local cache_dir="/etc/antigravity-linux"
  mkdir -p "$cache_dir"

  # Cache the currently running installer script locally
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -r "${BASH_SOURCE[0]}" ] && [ "${BASH_SOURCE[0]}" != "bash" ] && [ "${BASH_SOURCE[0]}" != "sh" ]; then
    if ! [ "${BASH_SOURCE[0]}" -ef "$cache_dir/install.sh" ]; then
      cp -f "${BASH_SOURCE[0]}" "$cache_dir/install.sh"
    fi
    chmod 0755 "$cache_dir/install.sh"
  elif [ ! -f "$cache_dir/install.sh" ]; then
    curl -fsSL --connect-timeout 5 "$installer_url" -o "$cache_dir/install.sh" 2>/dev/null && chmod 0755 "$cache_dir/install.sh" || true
  fi

  cat > /usr/local/bin/antigravity-linux <<SH
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_URL="$installer_url"
CACHE_DIR="$cache_dir"
LOCAL_SCRIPT="\$CACHE_DIR/install.sh"

if [ "\$(id -u)" -ne 0 ]; then
  exec sudo -E "\$0" "\$@"
fi

mkdir -p "\$CACHE_DIR"

TMP_FETCH=\$(mktemp "\$CACHE_DIR/install.sh.XXXXXX" 2>/dev/null || mktemp /tmp/install.sh.XXXXXX)
FETCH_OK=0

if curl -fsSL --connect-timeout 5 --retry 1 -H "Cache-Control: max-age=300" "\$SCRIPT_URL" -o "\$TMP_FETCH" 2>/dev/null; then
  if bash -n "\$TMP_FETCH" 2>/dev/null; then
    chmod 0755 "\$TMP_FETCH"
    mv -f "\$TMP_FETCH" "\$LOCAL_SCRIPT"
    FETCH_OK=1
  fi
fi
rm -f "\$TMP_FETCH" 2>/dev/null || true

if [ ! -f "\$LOCAL_SCRIPT" ]; then
  echo "ERROR: Failed to fetch latest installer from \$SCRIPT_URL and no local cached installer was found." >&2
  exit 1
fi

if [ "\$FETCH_OK" -eq 0 ]; then
  echo "Notice: Remote unreachable; running with locally cached installer (\$LOCAL_SCRIPT)." >&2
fi

exec bash "\$LOCAL_SCRIPT" "\$@"
SH
  chmod +x /usr/local/bin/antigravity-linux

  cat > /usr/local/bin/update-antigravity <<'SH'
#!/usr/bin/env bash
exec antigravity-linux update --desktop "$@"
SH
  chmod +x /usr/local/bin/update-antigravity

  cat > /usr/local/bin/update-antigravity-ide <<'SH'
#!/usr/bin/env bash
exec antigravity-linux update --ide "$@"
SH
  chmod +x /usr/local/bin/update-antigravity-ide
}

print_status() {
  log "Antigravity Linux status"
  if [ -x /usr/local/bin/antigravity ] || [ -d /opt/antigravity ]; then
    log "- Antigravity 2.0: installed ($(installed_version /opt/antigravity/.antigravity-linux-version))"
    log "  Command: /usr/local/bin/antigravity"
  else
    log "- Antigravity 2.0: not installed"
  fi
  if [ -x /usr/local/bin/antigravity-ide ] || [ -d /opt/antigravity-ide ]; then
    log "- Antigravity IDE: installed ($(installed_version /opt/antigravity-ide/.antigravity-linux-version))"
    log "  Command: /usr/local/bin/antigravity-ide"
  else
    log "- Antigravity IDE: not installed"
  fi
  local user_home=""
  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ]; then
    user_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6 || echo "")
  fi
  local cli_path=""
  if [ -n "$user_home" ] && [ -x "$user_home/.local/bin/agy" ]; then
    cli_path="$user_home/.local/bin/agy"
  elif [ -x /usr/local/bin/agy ]; then
    cli_path="/usr/local/bin/agy"
  elif command -v agy >/dev/null 2>&1; then
    cli_path=$(command -v agy)
  fi
  if [ -n "$cli_path" ]; then
    local cli_ver=""
    if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ] && [ -n "$user_home" ] && [[ "$cli_path" == "$user_home"* ]]; then
      cli_ver=$(sudo -u "$SUDO_USER" "$cli_path" --version 2>/dev/null | head -n1 || echo "")
    else
      cli_ver=$("$cli_path" --version 2>/dev/null | head -n1 || echo "")
    fi
    log "- Antigravity CLI: installed (${cli_ver:-active} at $cli_path)"
  else
    log "- Antigravity CLI: not installed"
  fi
  if [ -x /usr/local/bin/antigravity-linux ]; then
    log "- Update helper: installed (/usr/local/bin/antigravity-linux)"
  else
    log "- Update helper: not installed"
  fi
}

print_downloads() {
  need curl
  need python3
  local tmp_parent="${TMPDIR:-/var/tmp}"
  local tmpdir
  tmpdir=$(mktemp -d "$tmp_parent/$PROJECT_NAME.XXXXXX")
  trap 'rm -rf "${tmpdir:-}"' RETURN
  local js
  js=$(resolve_download_source "$tmpdir")
  if [ "$INSTALL_DESKTOP" -eq 1 ]; then
    local version url
    read -r version url < <(resolve_desktop_download "$js")
    log "Antigravity 2.0 $version: $url"
  fi
  if [ "$INSTALL_IDE" -eq 1 ]; then
    local version url
    read -r version url < <(resolve_ide_download "$js")
    log "Antigravity IDE $version: $url"
  fi
}

print_success_summary() {
  log ""
  log "Antigravity Linux operation complete."
  log ""
  log "Status:"
  if [ "$INSTALL_DESKTOP" -eq 1 ] || [ -x /usr/local/bin/antigravity ]; then
    local v
    v=$(installed_version /opt/antigravity/.antigravity-linux-version)
    log "- Antigravity 2.0: installed (v${v:-unknown}) -> /usr/local/bin/antigravity"
  fi
  if [ "$INSTALL_IDE" -eq 1 ] || [ -x /usr/local/bin/antigravity-ide ]; then
    local v
    v=$(installed_version /opt/antigravity-ide/.antigravity-linux-version)
    log "- Antigravity IDE: installed (v${v:-unknown}) -> /usr/local/bin/antigravity-ide"
  fi
  local user_home=""
  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ]; then
    user_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6 || echo "")
  fi
  local cli_path=""
  if [ -n "$user_home" ] && [ -x "$user_home/.local/bin/agy" ]; then
    cli_path="$user_home/.local/bin/agy"
  elif [ -x /usr/local/bin/agy ]; then
    cli_path="/usr/local/bin/agy"
  elif command -v agy >/dev/null 2>&1; then
    cli_path=$(command -v agy)
  fi
  if [ -n "$cli_path" ]; then
    local cli_ver=""
    if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ] && [ -n "$user_home" ] && [[ "$cli_path" == "$user_home"* ]]; then
      cli_ver=$(sudo -u "$SUDO_USER" "$cli_path" --version 2>/dev/null | head -n1 || echo "")
    else
      cli_ver=$("$cli_path" --version 2>/dev/null | head -n1 || echo "")
    fi
    log "- Antigravity CLI: installed (v${cli_ver:-active} at $cli_path)"
  fi
  log ""
  log "Quick Commands:"
  log "- Launchers:  antigravity  |  antigravity-ide  |  agy"
  log "- TUI Update / Reinstall: sudo antigravity-linux"
  log "- Helper Updaters:        sudo update-antigravity  |  sudo update-antigravity-ide"
  log "- Status Check:           antigravity-linux --status"
  log "- Full Uninstall:         sudo antigravity-linux --uninstall"
  if [ "$INSTALL_IDE" -eq 1 ] && [ "$INSTALL_NAUTILUS" -eq 1 ] && command -v nautilus >/dev/null 2>&1; then
    log ""
    log "Folder open integration: use your file manager's Open With menu, or Nautilus context menu after restarting Files."
  fi
}

start_tui() {
  local tty_in="/dev/tty"
  if [ ! -r "$tty_in" ] || [ ! -w "$tty_in" ]; then
    return 1
  fi
  exec 3<"$tty_in"
  exec 4>"$tty_in"
  IS_TUI_ACTIVE=1
  tput smcup >&4 2>/dev/null || true
  tput civis >&4 2>/dev/null || true
  return 0
}

run_stepper_wizard() {
  local latest_desktop_ver="$1"
  local latest_ide_ver="$2"

  local has_nautilus=0
  if command -v nautilus >/dev/null 2>&1; then
    has_nautilus=1
  fi

  local cur_desktop="" cur_ide="" cur_cli=""
  if [ -x /usr/local/bin/antigravity ] || [ -d /opt/antigravity ]; then
    cur_desktop=$(installed_version /opt/antigravity/.antigravity-linux-version)
  fi
  if [ -x /usr/local/bin/antigravity-ide ] || [ -d /opt/antigravity-ide ]; then
    cur_ide=$(installed_version /opt/antigravity-ide/.antigravity-linux-version)
  fi

  local user_home=""
  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ]; then
    user_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6 || echo "")
  fi
  local cli_bin=""
  if [ -n "$user_home" ] && [ -x "$user_home/.local/bin/agy" ]; then
    cli_bin="$user_home/.local/bin/agy"
  elif [ -x /usr/local/bin/agy ]; then
    cli_bin="/usr/local/bin/agy"
  elif command -v agy >/dev/null 2>&1; then
    cli_bin=$(command -v agy)
  fi
  if [ -n "$cli_bin" ]; then
    if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ] && [ -n "$user_home" ] && [[ "$cli_bin" == "$user_home"* ]]; then
      cur_cli=$(sudo -u "$SUDO_USER" "$cli_bin" --version 2>/dev/null | head -n1 || echo "")
    else
      cur_cli=$("$cli_bin" --version 2>/dev/null | head -n1 || echo "")
    fi
  fi

  # Dynamic descriptions based on installed vs latest release
  local desktop_desc=""
  if [ -n "$cur_desktop" ]; then
    if [ -n "$latest_desktop_ver" ] && [ "$cur_desktop" != "$latest_desktop_ver" ]; then
      desktop_desc="\033[1;33m(v$cur_desktop installed ➜ v$latest_desktop_ver update available)\033[0m"
    else
      desktop_desc="\033[90m(v${cur_desktop:-installed} • Up to date)\033[0m"
    fi
  else
    if [ -n "$latest_desktop_ver" ]; then
      desktop_desc="\033[90m(Not installed • v$latest_desktop_ver available)\033[0m"
    else
      desktop_desc="\033[90m(Google autonomous agent platform)\033[0m"
    fi
  fi

  local ide_desc=""
  if [ -n "$cur_ide" ]; then
    if [ -n "$latest_ide_ver" ] && [ "$cur_ide" != "$latest_ide_ver" ]; then
      ide_desc="\033[1;33m(v$cur_ide installed ➜ v$latest_ide_ver update available)\033[0m"
    else
      ide_desc="\033[90m(v${cur_ide:-installed} • Up to date)\033[0m"
    fi
  else
    if [ -n "$latest_ide_ver" ]; then
      ide_desc="\033[90m(Not installed • v$latest_ide_ver available)\033[0m"
    else
      ide_desc="\033[90m(Antigravity Code development studio)\033[0m"
    fi
  fi

  local cli_desc=""
  if [ -n "$cli_bin" ]; then
    cli_desc="\033[90m(v${cur_cli:-active} installed at $cli_bin)\033[0m"
  else
    cli_desc="\033[90m(Official agy terminal command)\033[0m"
  fi

  local nautilus_desc=""
  if [ $has_nautilus -eq 1 ]; then
    if [ -f /usr/share/nautilus-python/extensions/open-in-antigravity-ide.py ]; then
      nautilus_desc="\033[90m(Extension installed • Open With menu)\033[0m"
    else
      nautilus_desc="\033[90m(Right-click 'Open in Antigravity IDE')\033[0m"
    fi
  fi

  local force_desc="\033[90m(Re-download & reinstall even if already up to date)\033[0m"

  # Initial selections
  local opt_desktop=$INSTALL_DESKTOP
  local opt_ide=$INSTALL_IDE
  local opt_cli=$INSTALL_CLI
  local opt_nautilus=$INSTALL_NAUTILUS
  local opt_force=$FORCE

  local cursor=0
  if [ "$EXPLICIT_PRODUCT" -eq 1 ]; then
    if [ "$INSTALL_IDE" -eq 1 ] && [ "$INSTALL_DESKTOP" -eq 0 ]; then
      cursor=1
    elif [ "$INSTALL_CLI" -eq 1 ] && [ "$INSTALL_DESKTOP" -eq 0 ]; then
      cursor=2
    fi
  else
    opt_desktop=1
    opt_ide=1
    [ -n "$cli_bin" ] && opt_cli=1
    if [ "$INSTALL_NAUTILUS" -eq 1 ]; then
      opt_nautilus=$has_nautilus
    else
      opt_nautilus=0
    fi
  fi

  local total_opts=4
  [ $has_nautilus -eq 1 ] && total_opts=5

  render_wizard() {
    clear >&4
    printf '\n\n' >&4
    printf '\033[1;36m' >&4
    cat >&4 <<'BANNER'
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
BANNER
    printf '\033[0m' >&4
    printf '\n\033[1;37m   Interactive Installer & Updater (Linux %s)\033[0m\n' "$AG_PLATFORM" >&4
    printf '\033[90m   ─────────────────────────────────────────────────────────────────────────────\033[0m\n\n' >&4

    printf '   \033[1;32m[✓] 1. Architecture & Release Info\033[0m   (Target: %s, Latest: Desktop %s, IDE %s)\n' "$AG_PLATFORM" "${latest_desktop_ver:-unknown}" "${latest_ide_ver:-unknown}" >&4
    printf '   \033[1;36m[●] 2. Component Selection\033[0m         Choose packages to install, update, or reinstall\n' >&4
    printf '   \033[90m[ ] 3. Download & Deploy\033[0m           Fetch official Google release tarballs\n\n' >&4

    printf '   \033[1;37mSelect components to install or update:\033[0m\n\n' >&4

    local c0=" " c1=" " c2=" " c3=" " c4=" "
    [ $cursor -eq 0 ] && c0="\033[1;36m❯\033[0m"
    [ $cursor -eq 1 ] && c1="\033[1;36m❯\033[0m"
    [ $cursor -eq 2 ] && c2="\033[1;36m❯\033[0m"
    if [ $has_nautilus -eq 1 ]; then
      [ $cursor -eq 3 ] && c3="\033[1;36m❯\033[0m"
      [ $cursor -eq 4 ] && c4="\033[1;36m❯\033[0m"
    else
      [ $cursor -eq 3 ] && c4="\033[1;36m❯\033[0m"
    fi

    local d0="[ ]" d1="[ ]" d2="[ ]" d3="[ ]" d4="[ ]"
    [ $opt_desktop -eq 1 ] && d0="\033[1;32m[✓]\033[0m"
    [ $opt_ide -eq 1 ] && d1="\033[1;32m[✓]\033[0m"
    [ $opt_cli -eq 1 ] && d2="\033[1;32m[✓]\033[0m"
    [ $opt_nautilus -eq 1 ] && d3="\033[1;32m[✓]\033[0m"
    [ $opt_force -eq 1 ] && d4="\033[1;33m[✓]\033[0m"

    printf '   %b %b Antigravity 2.0 Desktop     %b\n' "$c0" "$d0" "$desktop_desc" >&4
    printf '   %b %b Antigravity IDE             %b\n' "$c1" "$d1" "$ide_desc" >&4
    printf '   %b %b Antigravity CLI (agy)       %b\n' "$c2" "$d2" "$cli_desc" >&4

    if [ $has_nautilus -eq 1 ]; then
      printf '   %b %b Nautilus Context Menu       %b\n' "$c3" "$d3" "$nautilus_desc" >&4
    else
      printf '     \033[90m[—] Nautilus Context Menu       (Disabled: Nautilus not detected on system)\033[0m\n' >&4
    fi

    printf '\n' >&4
    printf '   %b %b Force Reinstall / Overwrite %b\n\n' "$c4" "$d4" "$force_desc" >&4

    printf '\033[90m   ─────────────────────────────────────────────────────────────────────────────\033[0m\n' >&4
    printf '   \033[1;33mControls:\033[0m [↑/↓] Navigate  •  [Space] Toggle  •  [Enter] Proceed  •  [q] Quit\n' >&4
  }

  while true; do
    render_wizard
    IFS= read -rsn1 -u 3 key || true
    if [ "$key" = $'\x1b' ]; then
      read -rsn2 -u 3 -t 0.1 rest || true
      key+="$rest"
    fi

    case "$key" in
      $'\x1b[A'|k|K) # Up
        cursor=$(( (cursor - 1 + total_opts) % total_opts ))
        ;;
      $'\x1b[B'|j|J) # Down
        cursor=$(( (cursor + 1) % total_opts ))
        ;;
      " ") # Space (toggle)
        if [ $has_nautilus -eq 1 ]; then
          case $cursor in
            0) opt_desktop=$(( 1 - opt_desktop )) ;;
            1) opt_ide=$(( 1 - opt_ide )) ;;
            2) opt_cli=$(( 1 - opt_cli )) ;;
            3) opt_nautilus=$(( 1 - opt_nautilus )) ;;
            4) opt_force=$(( 1 - opt_force )) ;;
          esac
        else
          case $cursor in
            0) opt_desktop=$(( 1 - opt_desktop )) ;;
            1) opt_ide=$(( 1 - opt_ide )) ;;
            2) opt_cli=$(( 1 - opt_cli )) ;;
            3) opt_force=$(( 1 - opt_force )) ;;
          esac
        fi
        ;;
      "") # Enter (confirm)
        if [ $opt_desktop -eq 0 ] && [ $opt_ide -eq 0 ] && [ $opt_cli -eq 0 ]; then
          continue
        fi
        break
        ;;
      q|Q|$'\x03') # Quit
        cleanup_tui
        printf '\nOperation cancelled by user.\n'
        exit 0
        ;;
    esac
  done

  INSTALL_DESKTOP=$opt_desktop
  INSTALL_IDE=$opt_ide
  INSTALL_CLI=$opt_cli
  INSTALL_NAUTILUS=$opt_nautilus
  FORCE=$opt_force
}

render_step3_header() {
  local latest_desktop_ver="$1"
  local latest_ide_ver="$2"
  clear >&4
  printf '\n\n' >&4
  printf '\033[1;36m' >&4
  cat >&4 <<'BANNER'
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
BANNER
  printf '\033[0m' >&4
  printf '\n\033[1;37m   Interactive Installer & Updater (Linux %s)\033[0m\n' "$AG_PLATFORM" >&4
  printf '\033[90m   ─────────────────────────────────────────────────────────────────────────────\033[0m\n\n' >&4

  printf '   \033[1;32m[✓] 1. Architecture & Release Info\033[0m   (Target: %s, Latest: Desktop %s, IDE %s)\n' "$AG_PLATFORM" "${latest_desktop_ver:-unknown}" "${latest_ide_ver:-unknown}" >&4

  local sel=()
  [ "$INSTALL_DESKTOP" -eq 1 ] && sel+=("Desktop")
  [ "$INSTALL_IDE" -eq 1 ] && sel+=("IDE")
  [ "$INSTALL_CLI" -eq 1 ] && sel+=("CLI")
  [ "$INSTALL_NAUTILUS" -eq 1 ] && sel+=("Nautilus")
  [ "$FORCE" -eq 1 ] && sel+=("Force Reinstall")
  local sel_summary
  sel_summary=$(IFS=', '; echo "${sel[*]}")

  printf '   \033[1;32m[✓] 2. Component Selection\033[0m         (Selected: %s)\n' "$sel_summary" >&4
  printf '   \033[1;36m[●] 3. Download & Deploy\033[0m           Processing selected components...\n\n' >&4
  printf '\033[90m   ─────────────────────────────────────────────────────────────────────────────\033[0m\n\n' >&4
  tput cnorm >&4 2>/dev/null || true
}

uninstall_all() {
  require_root_or_reexec
  rm -rf /opt/antigravity /opt/antigravity.new /opt/antigravity.previous /opt/antigravity-ide /opt/antigravity-ide.new /opt/antigravity-ide.previous /etc/antigravity-linux
  rm -f /usr/local/bin/antigravity /usr/local/bin/antigravity-ide /usr/local/bin/update-antigravity /usr/local/bin/update-antigravity-ide /usr/local/bin/antigravity-linux
  rm -f /usr/share/applications/antigravity.desktop /usr/share/applications/antigravity-ide.desktop
  rm -f /usr/share/icons/hicolor/512x512/apps/antigravity.png /usr/share/icons/hicolor/512x512/apps/antigravity-ide.png
  rm -f /usr/share/nautilus-python/extensions/open-in-antigravity-ide.py
  refresh_desktop_caches
  log "Removed helper-managed Antigravity files. User settings under home directories were left untouched."
}

main() {
  if [ "$DO_STATUS" -eq 1 ]; then
    print_status
    exit 0
  fi
  if [ "$DO_PRINT_DOWNLOADS" -eq 1 ]; then
    print_downloads
    exit 0
  fi
  if [ "$DO_UNINSTALL" -eq 1 ]; then
    uninstall_all
    exit 0
  fi

  require_root_or_reexec

  local tmp_parent="${TMPDIR:-/var/tmp}"
  mkdir -p "$tmp_parent"
  tmpdir=$(mktemp -d "$tmp_parent/$PROJECT_NAME.XXXXXX")
  trap cleanup_all EXIT INT TERM

  install_base_deps

  local js=""
  local latest_desktop_ver="" latest_ide_ver=""
  js=$(resolve_download_source "$tmpdir")
  read -r latest_desktop_ver _ < <(resolve_desktop_download "$js" 2>/dev/null || echo "")
  read -r latest_ide_ver _ < <(resolve_ide_download "$js" 2>/dev/null || echo "")

  local is_interactive=0
  if [ "$YES" -eq 0 ] && [ -t 1 ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
    is_interactive=1
  fi

  if [ "$is_interactive" -eq 1 ]; then
    if start_tui; then
      run_stepper_wizard "$latest_desktop_ver" "$latest_ide_ver"
      render_step3_header "$latest_desktop_ver" "$latest_ide_ver"
    fi
  fi

  install_deps
  [ "$INSTALL_DESKTOP" -eq 1 ] && install_desktop_app "$tmpdir" "$js"
  [ "$INSTALL_IDE" -eq 1 ] && install_ide_app "$tmpdir" "$js"
  install_nautilus_extension
  if [ "$INSTALL_CLI" -eq 1 ]; then
    log "Running Google's official Antigravity CLI installer/updater..."
    if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ]; then
      if [ "$IS_TUI_ACTIVE" -eq 1 ]; then
        sudo -u "$SUDO_USER" -H bash -lc "curl -fsSL '$CLI_INSTALLER' | bash" >&4 2>&4
      else
        sudo -u "$SUDO_USER" -H bash -lc "curl -fsSL '$CLI_INSTALLER' | bash"
      fi
    else
      if [ "$IS_TUI_ACTIVE" -eq 1 ]; then
        curl -fsSL "$CLI_INSTALLER" | bash >&4 2>&4
      else
        curl -fsSL "$CLI_INSTALLER" | bash
      fi
    fi
  fi
  install_manager_command

  if [ "$IS_TUI_ACTIVE" -eq 1 ]; then
    printf '\n\033[90m   ─────────────────────────────────────────────────────────────────────────────\033[0m\n' >&4
    printf '   \033[1;32m[✓] 3. Download & Deploy\033[0m           Complete!\n' >&4
    print_success_summary
    printf '\n\033[90m   ─────────────────────────────────────────────────────────────────────────────\033[0m\n' >&4
    printf '   \033[1;33mPress any key to exit...\033[0m ' >&4
    read -rsn1 -u 3 _discard || true
    printf '\n' >&4
    cleanup_tui
    print_success_summary
  else
    print_success_summary
  fi
}

main "$@"
