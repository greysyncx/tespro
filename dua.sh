#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

RED="\033[1;31m"
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RESET="\033[0m"

VERSION="1.5.1"
BACKUP_DIR="/root/greysync_backupsx"
mkdir -p "$BACKUP_DIR"

clear
echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║              GreySync Protect — Auto Mode v${VERSION}         ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "${YELLOW}[1]${RESET} Pasang Protect GreyZ"
echo -e "${YELLOW}[2]${RESET} Restore dari Backup Terakhir"
read -p "$(echo -e "${CYAN}Pilih opsi [1/2]: ${RESET}")" MENU

backup_file() {
  local f="$1"
  [[ -f "$f" ]] && cp "$f" "$BACKUP_DIR/$(basename "$f").$(date +%F-%H%M%S).bak"
}

inject_api_user_update_protect() {
  local path="$1"
  echo -e "${YELLOW}⚙ Inject API anti-edit → ${path}${RESET}"
  backup_file "$path"

  if ! grep -q "use Illuminate\\Support\\Facades\\Auth;" "$path" 2>/dev/null; then
    sed -i '/^namespace /a use Illuminate\\Support\\Facades\\Auth;' "$path"
  fi

  awk -v admin_id="$ADMIN_ID" '
    BEGIN { in_func=0; inserted=0 }
    /public function update[[:space:]]*\(.*\)/ { print; in_func=1; next }
    in_func==1 {
      if (/\{/ && inserted==0) {
        print
        print "        // === GreySync Anti Edit Protect (API) ==="
        print "        $auth = $request->user() ?? Auth::user();"
        print "        if (!$auth || ($auth->id !== $user->id && $auth->id != " admin_id ")) {"
        print "            return response()->json([\"error\" => \"😹 Lu Siapa Mau Edit User Lain? Jasa Pasang Anti-Rusuh t.me/greysyncx\"], 403);"
        print "        }"
        inserted=1
        in_func=0
        next
      }
    }
    { print }
  ' "$path" > "$path.tmp" && mv "$path.tmp" "$path"

  echo -e "${GREEN}✔ Inject API user update selesai untuk $path${RESET}"
}

inject_admin_user_update_protect() {
  local path="$1"
  echo -e "${YELLOW}⚙ Inject Admin-web anti-edit → ${path}${RESET}"
  backup_file "$path"

  if ! grep -q "use Illuminate\\Support\\Facades\\Auth;" "$path" 2>/dev/null; then
    sed -i '/^namespace /a use Illuminate\\Support\\Facades\\Auth;' "$path"
  fi

  awk -v admin_id="$ADMIN_ID" '
    BEGIN { in_func=0; inserted=0 }
    /public function update[[:space:]]*\(.*\)/ { print; in_func=1; next }
    in_func==1 {
      if (/\{/ && inserted==0) {
        print
        print "        // === GreySync Anti Edit Protect (Admin) ==="
        print "        $auth = $request->user() ?? Auth::user();"
        print "        if (!$auth || ($auth->id !== $user->id && $auth->id != " admin_id ")) {"
        print "            return redirect()->back()->withErrors([\"error\" => \"😹 Lu Siapa Mau Edit User Lain? Jasa Pasang Anti-Rusuh t.me/greysyncx\"]);"
        print "        }"
        inserted=1
        in_func=0
        next
      }
    }
    { print }
  ' "$path" > "$path.tmp" && mv "$path.tmp" "$path"

  echo -e "${GREEN}✔ Inject Admin user update selesai untuk $path${RESET}"
}

inject_panel_index_guard() {
  local full="$1"
  echo -e "${YELLOW}⚙ Inject Panel index guard → ${full}${RESET}"
  backup_file "$full"

  if ! grep -q "use Illuminate\\Support\\Facades\\Auth;" "$full" 2>/dev/null; then
    sed -i '/^namespace /a use Illuminate\\Support\\Facades\\Auth;' "$full"
  fi

  awk -v admin_id="$ADMIN_ID" '
    BEGIN { found=0; inserted=0 }
    /public function index[[:space:]]*\(.*\)/ { print; found=1; next }
    found==1 && /^\s*{/ && inserted==0 {
      print;
      print "        // === GreySync Anti Intip Protect ===";
      print "        $user = Auth::user();";
      print "        if (!$user || $user->id != " admin_id ") {";
      print "            abort(403, \"❌ GreySync Protect: Mau Ngapain Bang? Jasa Pasang Anti-Rusuh t.me/greysyncx\");";
      print "        }";
      inserted=1;
      found=0;
      next;
    }
    { print }
  ' "$full" > "$full.tmp" && mv "$full.tmp" "$full"

  echo -e "${GREEN}✔ Panel index guard ditambahkan ke $full${RESET}"
}

# Candidate lists
API_CANDIDATES=(
  "/var/www/pterodactyl/app/Http/Controllers/Api/Application/Users/UserController.php"
  "/var/www/pterodactyl/app/Http/Controllers/Api/Users/UserController.php"
  "/var/www/pterodactyl/app/Http/Controllers/Api/Application/UserController.php"
)

ADMIN_CANDIDATES=(
  "/var/www/pterodactyl/app/Http/Controllers/Admin/UserController.php"
  "/var/www/pterodactyl/app/Http/Controllers/Admin/Users/UserController.php"
  "/var/www/pterodactyl/app/Http/Controllers/Admin/UsersController.php"
  "/var/www/pterodactyl/app/Http/Controllers/Admin/UserManagementController.php"
)

ADMIN_PANEL_DIR="/var/www/pterodactyl/app/Http/Controllers/Admin"
panel_targets=("Nodes/NodeController.php" "Nests/NestController.php" "Settings/IndexController.php" "LocationController.php")

PATCHED=()

if [[ "$MENU" == "1" ]]; then
  read -p "👤 Masukkan ID Admin Utama (contoh: 1): " ADMIN_ID
  if [[ -z "$ADMIN_ID" ]]; then
    echo -e "${RED}❌ Admin ID tidak boleh kosong.${RESET}"
    exit 1
  fi

  # inject API user update protection
  for p in "${API_CANDIDATES[@]}"; do
    if [[ -f "$p" ]]; then
      echo -e "${GREEN}✔ Found API UserController:${RESET} $p"
      inject_api_user_update_protect "$p"
      PATCHED+=("$p")
      break
    fi
  done

  # inject Admin user update protection
  for p in "${ADMIN_CANDIDATES[@]}"; do
    if [[ -f "$p" ]]; then
      echo -e "${GREEN}✔ Found Admin UserController:${RESET} $p"
      inject_admin_user_update_protect "$p"
      PATCHED+=("$p")
      break
    fi
  done

  # Protect Panel controllers (index) - inject guard to prevent browsing panels
  for t in "${panel_targets[@]}"; do
    full="$ADMIN_PANEL_DIR/$t"
    if [[ -f "$full" ]]; then
      echo -e "${GREEN}✔ Found Panel Controller:${RESET} $full"
      inject_panel_index_guard "$full"
      PATCHED+=("$full")
    fi
  done

  # Also try to find any Admin Servers controller and inject server-detail guard (show/view)
  FOUND_SERVERS=0
  while IFS= read -r f; do
    if [[ -f "$f" ]]; then
      echo -e "${GREEN}✔ Found possible Servers Controller:${RESET} $f"
      backup_file "$f"
      awk -v admin_id="$ADMIN_ID" '
        BEGIN { in_func=0; inserted=0 }
        /public function (show|view|index|details)[[:space:]]*\(.*Server.*\$server.*\)/ {
          print;
          in_func=1;
          next
        }
        in_func==1 {
          if (/^\s*{/ && inserted==0) {
            print;
            print "        // === GreySync Anti Intip Protect (Admin Servers) ===";
            print "        $user = auth()->user() ?? null;";
            print "        if (!$user || ($user->id !== $server->owner_id && $user->id != " admin_id ")) {";
            print "            abort(403, \"❌ Lu siapa mau intip detail server orang! Jasa Pasang Anti-Rusuh t.me/greysyncx\");";
            print "        }";
            inserted=1;
            in_func=0;
            next;
          }
        }
        { print }
      ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      PATCHED+=("$f")
      FOUND_SERVERS=1
    fi
  done < <(grep -RIl "class .*Server" /var/www/pterodactyl/app/Http/Controllers 2>/dev/null || true)

  echo
  if [[ ${#PATCHED[@]} -eq 0 ]]; then
    echo -e "${YELLOW}⚠ Tidak ditemukan file target untuk dipatch.${RESET}"
  else
    echo -e "${GREEN}✅ Proteksi berhasil diterapkan ke file:${RESET}"
    for f in "${PATCHED[@]}"; do
      echo -e "  • ${YELLOW}$f${RESET}"
    done
    echo -e "${CYAN}🛡  Sistem kini terlindungi dari edit & intip tidak sah.${RESET}"
  fi

elif [[ "$MENU" == "2" ]]; then
  echo -e "${CYAN}🔄 Memulihkan file dari backup terbaru...${RESET}"
  shopt -s nullglob
  LATEST_FILES=( "$BACKUP_DIR"/*.bak )
  if [[ ${#LATEST_FILES[@]} -eq 0 ]]; then
    echo -e "${RED}❌ Tidak ada file backup ditemukan.${RESET}"
    exit 1
  fi

  for bak in "${LATEST_FILES[@]}"; do
    fname=$(basename "$bak" | sed 's/\.[0-9-]*\.bak$//')
    find /var/www/pterodactyl -type f -name "$fname" -exec cp "$bak" {} \; 2>/dev/null || true
  done

  echo -e "${GREEN}✅ Semua file berhasil dikembalikan dari backup terbaru.${RESET}"
  echo -e "${CYAN}📁 Lokasi backup: ${YELLOW}$BACKUP_DIR${RESET}"
else
  echo -e "${RED}❌ Pilihan tidak valid.${RESET}"
  exit 1
fi
