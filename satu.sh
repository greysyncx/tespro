#!/bin/bash

RED="\033[1;31m"
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RESET="\033[0m"
BOLD="\033[1m"
VERSION="1.6.1"

clear
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║         GreySync Protect + Panel Grey                ║"
echo "║                    Version $VERSION                       ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "${YELLOW}[1]${RESET} Pasang Protect & Build Panel"
echo -e "${YELLOW}[2]${RESET} Restore dari Backup Terakhir"
echo -e "${YELLOW}[3]${RESET} Pasang Protect Admin (remote)"
read -p "$(echo -e "${CYAN}Pilih opsi [1/2/3]: ${RESET}")" OPSI

# Candidate files (lebih luas)
API_SERVER_CONTROLLER_CANDIDATES=(
  "/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/ServerController.php"
  "/var/www/pterodactyl/app/Http/Controllers/Api/Client/ServersController.php"
  "/var/www/pterodactyl/app/Http/Controllers/Api/Servers/ServerController.php"
)

ADMIN_SERVICES_CANDIDATES=(
  "/var/www/pterodactyl/app/Services/Servers/ServerDeletionService.php"
)

CONTROLLER_USER="/var/www/pterodactyl/app/Http/Controllers/Admin/UserController.php"
VIEW_DIR="/var/www/pterodactyl/resources/views/admin"
BACKUP_DIR="backup_greysyncx"
mkdir -p "$BACKUP_DIR"

backup_file() {
    [ -f "$1" ] && cp "$1" "$BACKUP_DIR/$(basename "$1").$(date +%F-%H%M%S).bak"
}

inject_api_intip_guard() {
    local path="$1"
    backup_file "$path"
    echo -e "${YELLOW}➤ Menambahkan guard Anti-Intip (API) ke: $path${RESET}"

    # tambahkan use Auth & DisplayException jika belum ada
    if ! grep -q "use Illuminate\\Support\\Facades\\Auth;" "$path" 2>/dev/null; then
        sed -i '/^namespace /a use Illuminate\\Support\\Facades\\Auth;' "$path"
    fi
    if ! grep -q "use Pterodactyl\\Exceptions\\DisplayException;" "$path" 2>/dev/null; then
        sed -i '/^namespace /a use Pterodactyl\\Exceptions\\DisplayException;' "$path"
    fi

    awk -v admin_id="$ADMIN_ID" '
    BEGIN { in_func=0; inserted=0 }
    # cari fungsi yang menerima Server $server (bisa show/view/index)
    /public function (show|view|index|details)[[:space:]]*\(.*Server.*\$server.*\)/ { print; in_func=1; next }
    in_func==1 {
      if (/^\s*{/ && inserted==0) {
        print;
        print "        // === GreySync Anti Intip Protect (API) ===";
        print "        $user = \$request->user() ?? Auth::user();";
        print "        if (!\$user || (\$user->id !== \$server->owner_id && \$user->id != " admin_id ")) {";
        print "            abort(403, \"❌ Lu siapa mau intip server orang! Jasa Pasang Anti-Rusuh t.me/greysyncx\");";
        print "        }";
        inserted=1;
        in_func=0;
        next;
      }
    }
    { print }
    ' "$path" > "$path.tmp" && mv "$path.tmp" "$path"

    echo -e "${GREEN}✔ Guard API ditambahkan.${RESET}"
}

inject_service_delete_guard() {
    local path="$1"
    backup_file "$path"
    echo -e "${YELLOW}➤ Menambahkan guard Delete Server (Service) ke: $path${RESET}"

    if ! grep -q "use Illuminate\\Support\\Facades\\Auth;" "$path" 2>/dev/null; then
        sed -i '/^namespace /a use Illuminate\\Support\\Facades\\Auth;\nuse Pterodactyl\\Exceptions\\DisplayException;' "$path"
    fi

    awk -v admin_id="$ADMIN_ID" '
    BEGIN { in_func=0; inserted=0 }
    /public function handle\(Server .* \$server\)/ { print; in_func=1; next }
    in_func==1 {
      if (/^\s*{/ && inserted==0) {
        print;
        print "        $user = Auth::user();";
        print "        if ($user && $user->id !== " admin_id ") {";
        print "            throw new DisplayException(\"🤬 Lu siapa mau hapus server orang?\\nJasa Pasang Anti-Rusuh t.me/greysyncx\");";
        print "        }";
        inserted=1;
        in_func=0;
        next;
      }
    }
    { print }
    ' "$path" > "$path.tmp" && mv "$path.tmp" "$path"

    echo -e "${GREEN}✔ Guard pada Service di tambahkan.${RESET}"
}

inject_blade_prevent() {
    local view="$1"
    backup_file "$view"
    echo -e "${YELLOW}➤ Menambahkan proteksi tambahan pada blade (sebagai cadangan): $view${RESET}"

    # Best-effort: jangan mengandalkan blade, tapi tambahkan small guard agar blade tetap tidak menampilkan server bila variabel tidak sesuai.
    sed -n '1,1p' "$view" >/dev/null 2>&1
    awk -v admin_id="$ADMIN_ID" '
    BEGIN { printed=0 }
    NR==1 {
      print "@php";
      print "    $user = auth()->user() ?? null;";
      print "    $ownerId = isset($server) ? ($server->owner_id ?? null) : null;";
      print "    if (!$user || ($user->id !== $ownerId && $user->id != " admin_id ")) {";
      print "        abort(403, \"❌ Lu siapa mau intip detail server orang! Jasa Pasang Anti-Rusuh t.me/greysyncx\");";
      print "    }";
      print "@endphp";
    }
    { print }
    ' "$view" > "$view.tmp" && mv "$view.tmp" "$view"

    echo -e "${GREEN}✔ Proteksi blade (cadangan) ditambahkan.${RESET}"
}

if [ "$OPSI" = "1" ]; then
    read -p "$(echo -e "${CYAN}👤 Masukkan User ID Admin Utama (contoh: 1): ${RESET}")" ADMIN_ID
    if [ -z "$ADMIN_ID" ]; then
        echo -e "${RED}❌ Admin ID tidak boleh kosong.${RESET}"
        exit 1
    fi

    echo -e "${YELLOW}➤ Membuat backup sebelum patch...${RESET}"
    [ -f "$CONTROLLER_USER" ] && cp "$CONTROLLER_USER" "$BACKUP_DIR/UserController.$(date +%F-%H%M%S).bak"

    # Patch ServerDeletionService jika ada
    for svc in "${ADMIN_SERVICES_CANDIDATES[@]}"; do
      if [ -f "$svc" ]; then
        inject_service_delete_guard "$svc"
      fi
    done

    # Patch API Server Controller (intip)
    FOUND_API=0
    for p in "${API_SERVER_CONTROLLER_CANDIDATES[@]}"; do
      if [ -f "$p" ]; then
        FOUND_API=1
        inject_api_intip_guard "$p"
        break
      fi
    done
    if [ $FOUND_API -eq 0 ]; then
      echo -e "${YELLOW}⚠ Tidak menemukan API ServerController standard di daftar candidate. Akan melakukan pencarian lebih luas...${RESET}"
      # pencarian lebih luas: cari file yang mengandung "namespace App\Http\Controllers\Api" dan "ServerController"
      while IFS= read -r f; do
        if [[ -f "$f" ]]; then
          inject_api_intip_guard "$f"
          FOUND_API=1
          break
        fi
      done < <(grep -RIl "class .*ServerController" /var/www/pterodactyl/app/Http/Controllers 2>/dev/null || true)
      [ $FOUND_API -eq 0 ] && echo -e "${YELLOW}⚠ Tetap tidak menemukan API ServerController untuk dipatch.${RESET}"
    fi

    # Patch admin blade view(s) (cadangan)
    # carikan view yang mungkin menampilkan server detail: resources/views/admin/servers/*
    for vf in $(find /var/www/pterodactyl/resources/views -type f -name "*.blade.php" 2>/dev/null); do
      # hanya patch file yang mengandung kata 'server' atau '$server'
      if grep -q "\$server" "$vf" 2>/dev/null || grep -qi "server" "$vf" 2>/dev/null; then
        # buat backup dan tambahkan small blade guard (cadangan)
        inject_blade_prevent "$vf"
      fi
    done

    echo -e "${GREEN}🎉 Protect v$VERSION (improved) selesai dipasang.${RESET}"

elif [ "$OPSI" = "2" ]; then
    echo -e "${CYAN}♻ Mengembalikan semua file dari backup terbaru...${RESET}"
    LATEST=$(ls -t "$BACKUP_DIR"/*.bak 2>/dev/null | head -n 1)
    if [ -z "$LATEST" ]; then
        echo -e "${RED}❌ Tidak ada backup ditemukan.${RESET}"
        exit 1
    fi
    for bak in "$BACKUP_DIR"/*.bak; do
      base=$(basename "$bak" | sed 's/\.[0-9-]*\.bak$//')
      # try to find target file by basename under project
      target=$(find /var/www/pterodactyl -type f -name "$base" 2>/dev/null | head -n 1)
      if [ -n "$target" ]; then
        cp "$bak" "$target"
        echo -e "${GREEN}✔ Dipulihkan: $target${RESET}"
      fi
    done
    echo -e "${GREEN}✅ Pemulihan selesai.${RESET}"

elif [ "$OPSI" = "3" ]; then
    bash <(curl -s https://raw.githubusercontent.com/greysyncx/protect/main/greyz.sh)
else
    echo -e "${RED}❌ Opsi tidak valid.${RESET}"
fi
