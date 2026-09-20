#!/bin/bash
# ==============================================================================
# Version: 1.3.2 (Sorted Server Cron List & Display Alignment Edition)
# Description: Unified Installer, Engine Generator & Interactive Mission Control
# Target OS: RHEL / CentOS Stream / Debian / Ubuntu (Linux x64)
# Engineered by GuppyGIRL and Hope Lockwood. Maintained by GuppyGIRL and Yui Kirigaya.
# ==============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

REAL_SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || echo "$0")
CURRENT_SCRIPT_DIR=$(dirname "$REAL_SCRIPT_PATH")

if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    REAL_USER="$(whoami)"
    REAL_HOME="$HOME"
fi

TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
UNIQ_ID="dcordbk-$$-${RANDOM}"
STAGE_DIR="/tmp/${UNIQ_ID}"

PERM_LOG_DIR="$REAL_HOME/.dcordbk/logs"
mkdir -p "$PERM_LOG_DIR" 2>/dev/null
chown -R "$REAL_USER:" "$REAL_HOME/.dcordbk" 2>/dev/null

LOG_FILE="$PERM_LOG_DIR/dcordbk_session_${TIMESTAMP}.log"
RET_RESTORE_POINT_FILE=""

TARGET_BIN=""
TARGET_ROOT=""
DO_INSTALL=false
IS_SYSTEM="false"

log_msg() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

filter_known_noise() {
    grep -v -E "(no crontab for |find: ‘/proc/[0-9]+’: No such file or directory|find: File system loop detected)"
}

probe_sudo_and_exec() {
    local pass_args=("$@")
    if [ "$EUID" -eq 0 ]; then
        return 0
    fi
    echo -e "${BLUE}>>> Administrative privileges required for this action.${NC}"
    read -p "Can I use sudo to perform system tasks? [y/N] " CAN_SUDO < /dev/tty
    if [[ "$CAN_SUDO" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}>>> Escalating via sudo -E (preserving environment context)...${NC}"
        exec sudo -E "$REAL_SCRIPT_PATH" "${pass_args[@]}"
    else
        echo -e "${RED}>>> User declined sudo. Aborting system-level operation.${NC}"
        exit 1
    fi
}

create_restore_point() {
    log_msg "${BLUE}>>> Creating System Restore Point...${NC}"
    local snap_file="$REAL_HOME/.dcordbk_rollback_${TIMESTAMP}.tar.gz"

    mkdir -p "$STAGE_DIR/files" "$STAGE_DIR/crons"
    echo "IS_SYSTEM=$([ "$EUID" -eq 0 ] && echo "true" || echo "false")" > "$STAGE_DIR/manifest.txt"
    echo "TIMESTAMP=$TIMESTAMP" >> "$STAGE_DIR/manifest.txt"
    echo "CREATED_BY=$REAL_USER" >> "$STAGE_DIR/manifest.txt"

    local known_bins=("$REAL_HOME/bin" "/usr/local/bin" "/usr/bin" "/opt/dcordbk/bin")
    local known_roots=("$REAL_HOME/Discord_Archive" "/usr/local/discord_archive" "/opt/dcordbk/discord_archive")
    local bin_files=("dcordbk" "dbkworker.sh" "dbkui" "dbk-cron-runner.sh" "DiscordChatExporter.Cli" "dcordbk-installer.bash" "dcordbk-uninstaller.bash")

    for bdir in "${known_bins[@]}"; do
        for b in "${bin_files[@]}"; do
            if [ -f "$bdir/$b" ]; then
                mkdir -p "$STAGE_DIR/files$bdir"
                cp -p "$bdir/$b" "$STAGE_DIR/files$bdir/" 2>/dev/null
            fi
        done
    done

    for rdir in "${known_roots[@]}"; do
        if [ -d "$rdir/.conf" ]; then
            mkdir -p "$STAGE_DIR/files$rdir"
            cp -rp "$rdir/.conf" "$STAGE_DIR/files$rdir/" 2>/dev/null
        fi
    done

    for user in $(cut -f1 -d: /etc/passwd 2>/dev/null); do
        if crontab -u "$user" -l 2>/dev/null | grep -qE "dcordbk|dbk-cron-runner"; then
            crontab -u "$user" -l 2>/dev/null > "$STAGE_DIR/crons/cron_${user}.bak"
        fi
    done

    [ -f "/etc/logrotate.d/dcordbk" ] && cp -p "/etc/logrotate.d/dcordbk" "$STAGE_DIR/logrotate_dcordbk" 2>/dev/null

    tar -czf "$snap_file" -C "$STAGE_DIR" . 2>/dev/null
    chown "$REAL_USER:" "$snap_file" 2>/dev/null
    chmod 600 "$snap_file" 2>/dev/null

    rm -rf "$STAGE_DIR"
    log_msg "${GREEN}>>> Restore Point Archived: $snap_file${NC}"
    RET_RESTORE_POINT_FILE="$snap_file"
}

perform_rollback() {
    local target_snap="$1"

    if [ -z "$target_snap" ]; then
        log_msg "${BLUE}>>> Scanning for available restore points in $REAL_HOME...${NC}"
        local snaps=($(ls -t "$REAL_HOME"/.dcordbk_rollback_*.tar.gz 2>/dev/null))
        if [ ${#snaps[@]} -eq 0 ]; then
            log_msg "${RED}ERROR: No restore points found in $REAL_HOME.${NC}"
            exit 1
        fi

        echo "Available Restore Points:"
        for i in "${!snaps[@]}"; do
            echo "  $((i+1))) ${snaps[$i]}"
        done
        read -p "Select restore point [1-${#snaps[@]}]: " SEL < /dev/tty
        target_snap="${snaps[$((SEL-1))]}"
    fi

    if [ ! -f "$target_snap" ]; then
        log_msg "${RED}CRITICAL ERROR: Selected restore point file not found.${NC}"
        exit 1
    fi

    log_msg "${BLUE}>>> Restoring system state from: $target_snap${NC}"
    mkdir -p "$STAGE_DIR"
    trap 'rm -rf "$STAGE_DIR"' EXIT

    tar -xzf "$target_snap" -C "$STAGE_DIR"

    if [ -d "$STAGE_DIR/files" ]; then
        cp -af "$STAGE_DIR/files/." / 2>/dev/null
    fi

    if [ -f "$STAGE_DIR/logrotate_dcordbk" ] && [ "$EUID" -eq 0 ]; then
        cp -pf "$STAGE_DIR/logrotate_dcordbk" /etc/logrotate.d/dcordbk 2>/dev/null
    fi

    if [ -d "$STAGE_DIR/crons" ]; then
        for cbak in "$STAGE_DIR/crons"/cron_*.bak; do
            if [ -f "$cbak" ]; then
                local user=$(basename "$cbak" | sed -e 's/^cron_//' -e 's/\.bak$//')
                crontab -u "$user" "$cbak" 2>/dev/null
            fi
        done
    fi

    log_msg "${GREEN}>>> ROLLBACK SUCCESSFUL. System restored from $target_snap.${NC}"
    exit 0
}

uninstall_reset() {
    local purge_token="${1:-true}"
    probe_sudo_and_exec --uninstall-reset "$([ "$purge_token" == "false" ] && echo "--keep-token")"

    if [ "$purge_token" == "false" ]; then
        log_msg "${BLUE}>>> Standard Uninstall mode: Preserving authorization token (.token)...${NC}"
    else
        read -p "Execute zero-state scrub across /home, /usr, /var, /opt, /etc, /tmp? [y/N] " CONFIRM < /dev/tty
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then exit 0; fi
    fi

    create_restore_point
    local snap_file="$RET_RESTORE_POINT_FILE"

    log_msg "\n${BLUE}>>> Scanning filesystem for DCORDBK footprints...${NC}"
    local file_list="/tmp/${UNIQ_ID}_files.txt"
    local dir_list="/tmp/${UNIQ_ID}_dirs.txt"
    touch "$file_list" "$dir_list"

    SEARCH_ROOTS=""
    for r in /home /usr /var /opt /etc /tmp; do [ -d "$r" ] && SEARCH_ROOTS="$SEARCH_ROOTS $r"; done

    find $SEARCH_ROOTS \
        \( -path "/mnt" -o -path "/proc" -o -path "/sys" -o -path "/dev" -o -path "/run" -o -path "/tmp/dcordbk*" -o -path "$CURRENT_SCRIPT_DIR*" -o -path "*/.dcordbk/logs*" \) -prune -o \
        -type f \( \
            -name "dcordbk" -o \
            -name "dbkworker.sh" -o \
            -name "dbkui" -o \
            -name "dbk-cron-runner.sh" -o \
            -name "DiscordChatExporter.Cli" -o \
            -name "dcordbk-installer.bash" -o \
            -name "dcordbk-uninstaller.bash" -o \
            -name ".token" -o \
            -name "id_map.txt" -o \
            -name "cron_targets.txt" -o \
            -name "default_cron.conf" -o \
            -name "dbk_*.log*" \
        \) -print 2>&1 | filter_known_noise | while read -r f; do
            if [[ "$f" == "$REAL_SCRIPT_PATH" ]] || [[ "$f" == *"/workarea/"* ]] || [[ "$f" == *"/.git/"* ]] || [[ "$f" == *.tar.xz ]] || [[ "$f" == *.tar.gz ]] || [[ "$f" == *session.log* ]]; then
                continue
            fi
            echo "$f" >> "$file_list"
        done

    if [ "$purge_token" == "false" ]; then
        grep -v -E "\.token$" "$file_list" > "${file_list}.tmp" 2>/dev/null && mv "${file_list}.tmp" "$file_list"
    fi

    find $SEARCH_ROOTS \
        \( -path "/mnt" -o -path "/proc" -o -path "/sys" -o -path "/dev" -o -path "/run" -o -path "/tmp/dcordbk*" -o -path "$CURRENT_SCRIPT_DIR*" -o -path "*/.dcordbk/logs*" \) -prune -o \
        -type d \( -name "discord_archive" -o -name "Discord_Archive" -o -name ".dcordbk*" \) -print 2>&1 | filter_known_noise | while read -r d; do
            if [[ "$d" == *"/workarea/"* ]] || [[ "$d" == *"/.git"* ]] || [[ "$d" == "$CURRENT_SCRIPT_DIR"* ]] || [[ "$d" == *"/.dcordbk/logs"* ]]; then
                continue
            fi
            echo "$d" >> "$dir_list"
        done

    log_msg "${BLUE}>>> Purging discovered components...${NC}"
    while read -r f; do [ -f "$f" ] && rm -vf "$f" | tee -a "$LOG_FILE"; done < "$file_list"
    while read -r d; do
        if [ -d "$d" ]; then
            find "$d" -mindepth 1 ! -name "*.tar.xz" ! -name "*.tar.gz" ! -name "*session.log*" ! -name ".token" -delete 2>/dev/null
            rmdir "$d" 2>/dev/null
        fi
    done < "$dir_list"

    for user in $(cut -f1 -d: /etc/passwd 2>/dev/null); do
        if crontab -u "$user" -l 2>/dev/null | grep -qE "dcordbk|dbk-cron-runner"; then
            crontab -u "$user" -l 2>/dev/null | sed -e '/dcordbk/d' -e '/dbk-cron-runner/d' -e '/# === DBK CRON/,/# === END DBK CRON/d' | crontab -u "$user" - 2>/dev/null
        fi
    done

    [ -f "/etc/logrotate.d/dcordbk" ] && rm -vf /etc/logrotate.d/dcordbk 2>/dev/null
    rm -f "$file_list" "$dir_list"

    log_msg "\n${GREEN}UNINSTALL COMPLETE.${NC}"
    log_msg "Session Audit Log preserved at: $LOG_FILE"
    log_msg "Restore point preserved at: $snap_file"
}

# --- ARGUMENT PARSING ---

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --prefix=*)
            CUSTOM_PATH="${1#*=}"
            TARGET_BIN="$CUSTOM_PATH/bin"
            TARGET_ROOT="$CUSTOM_PATH/discord_archive"
            DO_INSTALL=true
            if [ "$EUID" -eq 0 ]; then IS_SYSTEM="true"; else IS_SYSTEM="false"; fi
            shift
            ;;
        --restore-point)
            create_restore_point
            exit 0
            ;;
        --uninstall)
            uninstall_reset "false"
            exit 0
            ;;
        --uninstall-reset)
            uninstall_reset "true"
            exit 0
            ;;
        --rollback)
            shift
            perform_rollback "$1"
            exit 0
            ;;
        --help)
            echo "Usage: ./dcordbk-installer.bash [OPTIONS]"
            echo "  --prefix=<PATH>     Install to custom directory"
            echo "  --restore-point     Generate an immediate timestamped system snapshot"
            echo "  --rollback [FILE]   Restore system state from a specific snapshot"
            echo "  --uninstall         Purge suite binaries and crons while preserving token"
            echo "  --uninstall-reset   Perform zero-state system reset including tokens"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# --- INTERACTIVE INSTALLATION MENU ---

log_msg "${BLUE}========================================================"
log_msg "    DCORDBK UNIFIED SUITE & RESTORE ENGINE (v1.3.2)"
log_msg "    User Context: $REAL_USER ($REAL_HOME)"
log_msg "    Session Log:  $LOG_FILE"
log_msg "========================================================${NC}"

if [ "$DO_INSTALL" = false ]; then
    echo "Choose installation type:"
    echo "  1) User Install (Local Confinement - Recommended)"
    echo "  2) System Install (Requires Sudo)"
    read -p "Select option [1-2]: " OPTION < /dev/tty

    case $OPTION in
        1)
            TARGET_BIN="$REAL_HOME/bin"
            TARGET_ROOT="$REAL_HOME/Discord_Archive"
            IS_SYSTEM="false"
            DO_INSTALL=true
            ;;
        2)
            probe_sudo_and_exec --prefix=/usr/local
            TARGET_BIN="/usr/local/bin"
            TARGET_ROOT="/usr/local/discord_archive"
            IS_SYSTEM="true"
            DO_INSTALL=true
            ;;
        *)
            log_msg "${RED}Invalid option selected. Exiting.${NC}"
            exit 1
            ;;
    esac
fi

if [ -z "$TARGET_BIN" ] || [ -z "$TARGET_ROOT" ] || [ "$TARGET_BIN" = "/" ] || [ "$TARGET_ROOT" = "/" ]; then
    log_msg "${RED}CRITICAL ERROR: Installation paths unresolved or invalid ($TARGET_BIN / $TARGET_ROOT). Exiting safely.${NC}"
    exit 1
fi

log_msg "\n${BLUE}>>> Deploying DCORDBK Suite:${NC}"
log_msg "    Target Binaries: $TARGET_BIN"
log_msg "    Target Storage:  $TARGET_ROOT"
log_msg "    System Mode:     $IS_SYSTEM\n"

mkdir -p "$TARGET_BIN" "$TARGET_ROOT/.conf/.tmp" "$TARGET_ROOT/Direct_Messages" 2>/dev/null

cp -pf "$REAL_SCRIPT_PATH" "$TARGET_BIN/dcordbk-installer.bash" 2>/dev/null
chmod +x "$TARGET_BIN/dcordbk-installer.bash" 2>/dev/null

cat << 'EOF' > "$TARGET_BIN/dcordbk-uninstaller.bash"
#!/bin/bash
exec "$(dirname "$(readlink -f "$0")")/dcordbk-installer.bash" --uninstall "$@"
EOF
chmod +x "$TARGET_BIN/dcordbk-uninstaller.bash" 2>/dev/null

# ==============================================================================
# FILE 1: dcordbk (Master Wrapper)
# ==============================================================================
cat << 'EOF' > "$TARGET_BIN/dcordbk"
#!/bin/bash
export DBK_ROOT="PLACEHOLDER_PATH"
export IS_SYSTEM="PLACEHOLDER_IS_SYSTEM"
REAL_PATH=$(readlink -f "$0")
export DBK_SCRIPT_DIR=$(dirname "$REAL_PATH")
export DBK_CONF_DIR="$DBK_ROOT/.conf"
export DBK_ARCHIVE_DIR="$DBK_ROOT"
export DBK_TMP_DIR="$DBK_CONF_DIR/.tmp"
export ID_MAP_FILE="$DBK_CONF_DIR/id_map.txt"
export DBK_TOKEN_FILE="$DBK_CONF_DIR/.token"
export DBK_EXEC_LOG="PLACEHOLDER_EXEC_LOG"
export DBK_DISCORD_BINARY="PLACEHOLDER_BIN/DiscordChatExporter.Cli"

# --- Pre-Flight Mount Guard Check ---
if ! findmnt "$DBK_ROOT" >/dev/null 2>&1; then
    echo -e "\033[0;31m[CRITICAL ERROR] Storage root '$DBK_ROOT' is not actively mounted!\033[0m" >&2
    echo -e "\033[0;31mExecution halted to prevent writing to unmounted local storage.\033[0m" >&2
    exit 100
fi

if [ -f "$DBK_TOKEN_FILE" ]; then export DBK_TOKEN=$(cat "$DBK_TOKEN_FILE" | tr -d '\r\n'); else export DBK_TOKEN=""; fi

LEDGER_VERSION="3.0"
BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
PASSTHROUGH_ARGS=(); DO_DISCOVER=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--discover) DO_DISCOVER=true; shift ;;
        *) PASSTHROUGH_ARGS+=("$1"); shift ;;
    esac
done

if [ -z "$DBK_TOKEN" ] && [ "$DO_DISCOVER" = true ]; then
    echo -e "${RED}ERROR: No Discord Token found. Please run 'dbkui' to configure.${NC}"
    exit 1
fi

active_discovery() {
    echo "========================================================"
    echo " INITIATING ACTIVE DISCOVERY (Querying Discord API...)"
    echo "========================================================"

    mkdir -p "$DBK_TMP_DIR"
    echo ">>> Fetching Guilds (Servers)..."
    "$DBK_DISCORD_BINARY" guilds -t "$DBK_TOKEN" | tee "$DBK_TMP_DIR/guilds_raw.txt"

    grep -E "^[0-9]+[ \t]+\|" "$DBK_TMP_DIR/guilds_raw.txt" | awk -F'|' '{
        gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $2); print $1"|Guild|0|None|"$2
    }' > "$DBK_TMP_DIR/parsed_targets.txt"

    echo ">>> Fetching Categories and Channels..."
    while IFS='|' read -r GID TYPE PARENT CAT GNAME; do
        if [ "$TYPE" == "Guild" ]; then
            echo ">>> Fetching channels for Guild: $GNAME ($GID)..."
            "$DBK_DISCORD_BINARY" channels -g "$GID" -t "$DBK_TOKEN" | tee "$DBK_TMP_DIR/chans_${GID}.txt"
            grep -E "^[0-9]+[ \t]+\|" "$DBK_TMP_DIR/chans_${GID}.txt" | awk -v gid="$GID" -F'|' '{
                id=$1; cat=$2; name=$3;
                if(name=="") { name=cat; cat="Uncategorized"; }
                gsub(/^[ \t]+|[ \t]+$/, "", id); gsub(/^[ \t]+|[ \t]+$/, "", cat); gsub(/^[ \t]+|[ \t]+$/, "", name);
                if(cat=="") cat="Uncategorized"; print id"|Channel|"gid"|"cat"|"name
            }' >> "$DBK_TMP_DIR/parsed_targets.txt"
            rm -f "$DBK_TMP_DIR/chans_${GID}.txt"
        fi
    done < <(grep "|Guild|" "$DBK_TMP_DIR/parsed_targets.txt")

    echo "# VERSION: $LEDGER_VERSION" > "$ID_MAP_FILE"
    sort -u -t'|' -k1,1 "$DBK_TMP_DIR/parsed_targets.txt" >> "$ID_MAP_FILE"
    rm -f "$DBK_TMP_DIR/"*.txt
    echo ">>> Discovery complete. Ledger updated at $ID_MAP_FILE."
}

if [ "$DO_DISCOVER" = true ]; then active_discovery; exit 0; fi

WORKER="$DBK_SCRIPT_DIR/dbkworker.sh"
[ -f "$WORKER" ] && "$WORKER" "${PASSTHROUGH_ARGS[@]}" 2>&1 | tee -a "$DBK_EXEC_LOG"
EOF

# ==============================================================================
# FILE 2: dbkworker.sh (Backend Engine)
# ==============================================================================
cat << 'EOF' > "$TARGET_BIN/dbkworker.sh"
#!/bin/bash
if [ -z "$DBK_ROOT" ] || [ -z "$DBK_TOKEN" ]; then exit 1; fi

# --- Pre-Flight Mount Guard Check ---
if ! findmnt "$DBK_ROOT" >/dev/null 2>&1; then
    echo -e "\033[0;31m[CRITICAL ERROR] Storage root '$DBK_ROOT' is not actively mounted!\033[0m" >&2
    echo -e "\033[0;31mExecution halted to prevent writing to unmounted local storage.\033[0m" >&2
    exit 100
fi

CMD="$DBK_DISCORD_BINARY"; DATE=$(date +%Y-%m-%d_%H-%M-%S)
STAGE_DIR="/tmp/dcordbk_stage_$$"
mkdir -p "$STAGE_DIR"
trap 'rm -rf "$STAGE_DIR"' EXIT

if [ -t 1 ]; then IS_INTERACTIVE=true; else IS_INTERACTIVE=false; fi

MODE="DMS"; MEDIA=""; FORMAT="Json"; ARGS=()
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -A|--all) MODE="FULL"; shift ;;
        -D|--dms) MODE="DMS"; shift ;;
        -c|--channel) MODE="SELECTIVE"; ARGS+=("CHANNEL:$2"); shift 2 ;;
        -g|--guild) MODE="SELECTIVE"; ARGS+=("GUILD:$2"); shift 2 ;;
        -m|--media) MEDIA="--media"; shift ;;
        --html) FORMAT="HtmlDark"; shift ;;
        --json) FORMAT="Json"; shift ;;
        --text) FORMAT="PlainText"; shift ;;
        *) shift ;;
    esac
done

# --- Determine Destination Subdirectory and Filename Base ---
if [ "$MODE" == "DMS" ]; then
    DEST_SUBDIR="$DBK_ARCHIVE_DIR/Direct_Messages"
    DIR_NAME="${DATE}_DMS"
elif [ "$MODE" == "SELECTIVE" ] && [ ${#ARGS[@]} -gt 0 ]; then
    FIRST_ID="${ARGS[0]##*:}"
    TARGET_NAME=$(grep "^$FIRST_ID|" "$DBK_CONF_DIR/id_map.txt" 2>/dev/null | cut -d'|' -f5 | head -n 1 | sed 's/[^a-zA-Z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//; s/_$//')
    if [ -z "$TARGET_NAME" ]; then TARGET_NAME="Server_${FIRST_ID}"; fi
    DEST_SUBDIR="$DBK_ARCHIVE_DIR/$TARGET_NAME"
    DIR_NAME="${DATE}_${TARGET_NAME}"
else
    DEST_SUBDIR="$DBK_ARCHIVE_DIR/Full_Backups"
    DIR_NAME="${DATE}_FULL"
fi

mkdir -p "$DEST_SUBDIR" "$STAGE_DIR/$DIR_NAME"
LOCAL_OUT_BASE="$STAGE_DIR/$DIR_NAME"

EXT=".json"
if [ "$FORMAT" == "HtmlDark" ]; then EXT=".html"; fi
if [ "$FORMAT" == "PlainText" ]; then EXT=".txt"; fi

echo ">>> Launching export run into local staging [$LOCAL_OUT_BASE]..."
if [ "$MODE" == "FULL" ]; then 
    "$CMD" exportall -t "$DBK_TOKEN" $MEDIA --format "$FORMAT" --output "$LOCAL_OUT_BASE/%g - %c$EXT"
elif [ "$MODE" == "DMS" ]; then 
    "$CMD" exportdm -t "$DBK_TOKEN" $MEDIA --format "$FORMAT" --output "$LOCAL_OUT_BASE/%c - %C$EXT"
elif [ "$MODE" == "SELECTIVE" ]; then
    for ITEM in "${ARGS[@]}"; do
        TYPE="${ITEM%%:*}"; ID="${ITEM##*:}"
        if [ "$TYPE" == "CHANNEL" ]; then
            "$CMD" export -c "$ID" -t "$DBK_TOKEN" $MEDIA --format "$FORMAT" --output "$LOCAL_OUT_BASE/%g - %c$EXT"
        elif [ "$TYPE" == "GUILD" ]; then
            "$CMD" exportguild -g "$ID" -t "$DBK_TOKEN" $MEDIA --format "$FORMAT" --output "$LOCAL_OUT_BASE/%g - %c$EXT"
        fi
    done
fi

EXPORT_EXIT=$?

if [ "$MODE" == "DMS" ] && [ -d "$LOCAL_OUT_BASE" ]; then
    for file in "$LOCAL_OUT_BASE"/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            id=$(echo "$filename" | grep -oE "^[0-9]+")
            if [ -n "$id" ]; then
                name=$(echo "$filename" | sed -E "s/^[0-9]+ - //; s/\.[^.]+$//")
                if ! grep -q "^$id|" "$DBK_CONF_DIR/id_map.txt" 2>/dev/null; then
                    echo "$id|DM|0|None|$name" >> "$DBK_CONF_DIR/id_map.txt"
                fi
            fi
        fi
    done
    if [ -f "$DBK_CONF_DIR/id_map.txt" ]; then
        head -n 1 "$DBK_CONF_DIR/id_map.txt" > "$DBK_TMP_DIR/sorted_map.txt"
        grep -v "^#" "$DBK_CONF_DIR/id_map.txt" | sort -u -t'|' -k1,1 >> "$DBK_TMP_DIR/sorted_map.txt"
        mv -f "$DBK_TMP_DIR/sorted_map.txt" "$DBK_CONF_DIR/id_map.txt"
    fi
fi

if [ $EXPORT_EXIT -eq 0 ] && [ -d "$LOCAL_OUT_BASE" ]; then
    echo -e "\n>>> Export complete. Compressing payload locally (Multi-core enabled)..."
    tar -C "$STAGE_DIR" -cvf - "$DIR_NAME" | xz -9e -T0 > "$STAGE_DIR/${DIR_NAME}.tar.xz"
    echo -e ">>> Streaming final archive payload to destination [$DEST_SUBDIR/]:"
    mv "$STAGE_DIR/${DIR_NAME}.tar.xz" "$DEST_SUBDIR/"
    echo -e ">>> Archive payload successfully placed at: $DEST_SUBDIR/${DIR_NAME}.tar.xz"
elif [ -d "$LOCAL_OUT_BASE" ]; then
    echo -e "\n>>> Run aborted or failed. Local staging cleared."
fi
EOF

# ==============================================================================
# FILE 3: dbkui (Hierarchical Configuration & Ad-Hoc Mission Control)
# ==============================================================================
cat << 'EOF' > "$TARGET_BIN/dbkui"
#!/bin/bash
export DBK_ROOT="PLACEHOLDER_PATH"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONF_DIR="$DBK_ROOT/.conf"
ID_MAP="$CONF_DIR/id_map.txt"
CRON_TARGETS="$CONF_DIR/cron_targets.txt"
DEFAULT_CRON_FILE="$CONF_DIR/default_cron.conf"
TOKEN_FILE="$CONF_DIR/.token"
BLUE='\033[0;34m'; NC='\033[0m'

SECURITY_DISCLAIMER="Friendly Security Note: Please keep your authorization token safe and do not share it with others.\n\nJust a friendly heads-up from down the road: your Discord token is stored in plain text locally and is not encrypted—that is simply by Discord's design for local client authorization, not ours! If you have concerns about how local tokens are handled, you might want to have a quick chat with the folks over at Discord."

load_global_defaults() {
    DEFAULT_CRON_EXPR="0 2 * * 0"
    DEFAULT_CRON_FLAGS="--json --media"
    if [ -f "$DEFAULT_CRON_FILE" ]; then
        source "$DEFAULT_CRON_FILE" 2>/dev/null
    fi
}

save_global_defaults() {
    echo "DEFAULT_CRON_EXPR=\"$DEFAULT_CRON_EXPR\"" > "$DEFAULT_CRON_FILE"
    echo "DEFAULT_CRON_FLAGS=\"$DEFAULT_CRON_FLAGS\"" >> "$DEFAULT_CRON_FILE"
}

sync_crontab() {
    local tmp_cron="/tmp/dbk_crontab_$$"
    crontab -l 2>/dev/null | sed '/# === DBK CRON START ===/,/# === DBK CRON END ===/d' > "$tmp_cron"

    if [ -f "$CRON_TARGETS" ] && [ -s "$CRON_TARGETS" ]; then
        echo "# === DBK CRON START ===" >> "$tmp_cron"
        while IFS='|' read -r GID GNAME CRON_EXPR FLAGS STATUS; do
            if [ -n "$GID" ] && [ -n "$CRON_EXPR" ] && [ "$STATUS" == "ENABLED" ]; then
                echo "$CRON_EXPR $SCRIPT_DIR/dcordbk -g $GID $FLAGS >> $CONF_DIR/dbk_cron.log 2>&1" >> "$tmp_cron"
            fi
        done < "$CRON_TARGETS"
        echo "# === DBK CRON END ===" >> "$tmp_cron"
    fi

    crontab "$tmp_cron" 2>/dev/null
    rm -f "$tmp_cron"
}

prompt_token_wizard() {
    whiptail --title "Discord Authorization Setup" --msgbox "$SECURITY_DISCLAIMER" 14 70 < /dev/tty > /dev/tty
    NEW_TOKEN=$(whiptail --title "Authentication Required" --inputbox "Please paste your Discord Authorization Token to continue:" 12 70 3>&1 1>&2 2>&3 < /dev/tty | tr -d '"')
    if [ -z "$NEW_TOKEN" ]; then
        echo "A Discord Token is required to operate this suite. Exiting."; exit 1
    fi
    mkdir -p "$CONF_DIR"
    echo "$NEW_TOKEN" | tr -d '\r\n' > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"

    echo -e "${BLUE}========================================================${NC}"
    echo " TOKEN ACCEPTED. INITIATING AUTOMATIC DISCOVERY..."
    echo -e "${BLUE}========================================================${NC}"
    sleep 1
    "$SCRIPT_DIR/dcordbk" -d
    echo -e "\n>>> Discovery Complete. Press ENTER to open Mission Control."
    read -r < /dev/tty
}

if [ ! -f "$TOKEN_FILE" ] || [ -z "$(cat "$TOKEN_FILE" 2>/dev/null)" ]; then
    prompt_token_wizard
elif [ ! -f "$ID_MAP" ] || [ ! -s "$ID_MAP" ]; then
    echo -e "${BLUE}========================================================${NC}"
    echo " MISSING LEDGER DETECTED. INITIATING AUTOMATIC DISCOVERY..."
    echo -e "${BLUE}========================================================${NC}"
    sleep 1
    "$SCRIPT_DIR/dcordbk" -d
    echo -e "\n>>> Discovery Complete. Press ENTER to open Mission Control."
    read -r < /dev/tty
fi

menu_default_cron_config() {
    load_global_defaults
    while true; do
        DEF_INFO="Current Global Defaults for New/Unconfigured Servers:\n\n"
        DEF_INFO+="Expression: $DEFAULT_CRON_EXPR\n"
        DEF_INFO+="Flags:      $DEFAULT_CRON_FLAGS\n\n"
        DEF_INFO+="Schedule Syntax: [Min(0-59) Hour(0-23) Day(1-31) Month(1-12) DayOfWeek(0-6, 0=Sun)]"

        DEF_ACT=$(whiptail --title "Global Default Cron Configuration" --cancel-button "Back" --menu "$DEF_INFO" 18 80 3 \
            "1" "Edit Default Cron Schedule Expression" \
            "2" "Edit Default Output Format & Media Flags" \
            "3" "Save and Return" 3>&1 1>&2 2>&3 < /dev/tty | tr -d '"')

        [ -z "$DEF_ACT" ] || [ "$DEF_ACT" == "3" ] && break

        case $DEF_ACT in
            1)
                EXPR_HELP="Set Global Default Schedule Expression:\n\n"
                EXPR_HELP+="Syntax: MINUTE HOUR DAY MONTH DAY_OF_WEEK\n"
                EXPR_HELP+="  0 2 * * 0   -> Every Sunday at 2:00 AM (Default)\n"
                EXPR_HELP+="  0 0 * * *   -> Daily at Midnight\n"

                NEW_DEF_EXPR=$(whiptail --title "Global Default Expression" --inputbox "$EXPR_HELP" 15 70 "$DEFAULT_CRON_EXPR" 3>&1 1>&2 2>&3 < /dev/tty | tr -d '"')
                if [ -n "$NEW_DEF_EXPR" ]; then
                    DEFAULT_CRON_EXPR="$NEW_DEF_EXPR"
                    save_global_defaults
                    whiptail --msgbox "Global default expression updated to '$DEFAULT_CRON_EXPR'." 8 60 < /dev/tty > /dev/tty
                fi
                ;;
            2)
                FMT_HELP="Select Global Default Export Format:\n"
                FMT_HELP+="  1) JSON (--json)        - Structured raw API payload (Default)\n"
                FMT_HELP+="  2) HTML Dark (--html)   - Styled dark-theme browser document\n"
                FMT_HELP+="  3) Plain Text (--text)  - Compact text logs"

                NEW_FMT=$(whiptail --title "Global Default Format" --menu "$FMT_HELP" 16 70 3 \
                    "1" "JSON (--json)" \
                    "2" "HTML Dark (--html)" \
                    "3" "Plain Text (--text)" 3>&1 1>&2 2>&3 < /dev/tty | tr -d '"')

                [ -z "$NEW_FMT" ] && continue

                NEW_DEF_FLAGS="--json"
                if [ "$NEW_FMT" == "2" ]; then NEW_DEF_FLAGS="--html"; elif [ "$NEW_FMT" == "3" ]; then NEW_DEF_FLAGS="--text"; fi

                if whiptail --title "Global Default Media" --yesno "Download media attachments (images/videos) by default?" 10 65 < /dev/tty > /dev/tty; then
                    NEW_DEF_FLAGS="$NEW_DEF_FLAGS --media"
                fi

                DEFAULT_CRON_FLAGS="$NEW_DEF_FLAGS"
                save_global_defaults
                whiptail --msgbox "Global default flags updated to '$DEFAULT_CRON_FLAGS'." 8 60 < /dev/tty > /dev/tty
                ;;
        esac
    done
}

menu_server_crons() {
    load_global_defaults
    while true; do
        if [ ! -f "$ID_MAP" ] || [ ! -s "$ID_MAP" ]; then
            whiptail --title "Ledger Missing" --msgbox "No server ledger found (id_map.txt). Run active discovery first." 10 65 < /dev/tty > /dev/tty
            break
        fi

        CRON_MAIN_CHOICE=$(whiptail --title "Automated Server Cron Management" --cancel-button "Back" --menu "Select cron management action:" 18 80 3 \
            "1" "Manage Individual Server Crons" \
            "2" "Configure Global Default Cron Settings" \
            "3" "Browse Active Enabled Crons" 3>&1 1>&2 2>&3 < /dev/tty | tr -d '"')

        [ -z "$CRON_MAIN_CHOICE" ] && break

        case $CRON_MAIN_CHOICE in
            1)
                while true; do
                    touch "$CRON_TARGETS"
                    
                    tmp_enabled="/tmp/dbk_enabled_$$"
                    tmp_disabled="/tmp/dbk_disabled_$$"
                    :> "$tmp_enabled"
                    :> "$tmp_disabled"

                    while IFS='|' read -r id type pgid cat name; do
                        if [[ "$id" =~ ^[0-9]+$ ]] && [ "$type" == "Guild" ]; then
                            cron_entry=$(grep "^$id|" "$CRON_TARGETS" 2>/dev/null)
                            if [ -n "$cron_entry" ]; then
                                cexpr=$(echo "$cron_entry" | cut -d'|' -f3)
                                cflags=$(echo "$cron_entry" | cut -d'|' -f4)
                                cstatus=$(echo "$cron_entry" | cut -d'|' -f5)
                                [ -z "$cstatus" ] && cstatus="ENABLED"
                            else
                                cstatus="DISABLED"
                                cexpr="$DEFAULT_CRON_EXPR"
                                cflags="$DEFAULT_CRON_FLAGS"
                            fi

                            if [ "$cstatus" == "ENABLED" ]; then
                                echo "$name|$id|$cstatus|$cexpr|$cflags" >> "$tmp_enabled"
                            else
                                echo "$name|$id|$cstatus|$cexpr|$cflags" >> "$tmp_disabled"
                            fi
                        fi
                    done < <(grep "|Guild|" "$ID_MAP")

                    guild_opts=()

                    # Sort ENABLED servers alphabetically by name
                    if [ -s "$tmp_enabled" ]; then
                        while IFS='|' read -r name id cstatus cexpr cflags; do
                            guild_opts+=("$id" "$name [ENABLED] ($cexpr $cflags)")
                        done < <(sort -f -t'|' -k1,1 "$tmp_enabled")
                    fi

                    # Sort DISABLED servers alphabetically by name
                    if [ -s "$tmp_disabled" ]; then
                        while IFS='|' read -r name id cstatus cexpr cflags; do
                            guild_opts+=("$id" "$name [DISABLED] ($cexpr $cflags)")
                        done < <(sort -f -t'|' -k1,1 "$tmp_disabled")
                    fi

                    rm -f "$tmp_enabled" "$tmp_disabled"

                    if [ ${#guild_opts[@]} -eq 0 ]; then
                        whiptail --msgbox "No Servers discovered in ledger map." 8 45 < /dev/tty > /dev/tty
                        break
                    fi

                    SEL_GID=$(whiptail --title "Select Server Cron Target (Sorted: ENABLED first, then Alphabetical)" --cancel-button "Back" --menu "Choose Server to Configure:" 22 95 14 "${guild_opts[@]}" 3>&1 1>&2 2>&3 < /dev/tty | tr -d '"')

                    [ -z "$SEL_GID" ] && break

                    SEL_GNAME="$(grep "^$SEL_GID|" "$ID_MAP" | cut -d'|' -f5)"

                    while true; do
                        CURRENT_ENTRY=$(grep "^$SEL_GID|" "$CRON_TARGETS" 2>/dev/null)

                        if [ -n "$CURRENT_ENTRY" ]; then
                            CUR_EXPR=$(echo "$CURRENT_ENTRY" | cut -d'|' -f3)
                            CUR_FLAGS=$(echo "$CURRENT_ENTRY" | cut -d'|' -f4)
                            CUR_STATE=$(echo "$CURRENT_ENTRY" | cut -d'|' -f5)
                            [ -z "$CUR_STATE" ] && CUR_STATE="ENABLED"
                        else
                            CUR_STATE="DISABLED"
                            CUR_EXPR="$DEFAULT_CRON_EXPR"
                            CUR_FLAGS="$DEFAULT_CRON_FLAGS"
                        fi

                        GUIDE_MSG="Server: $SEL_GNAME ($SEL_GID)\n"
                        GUIDE_MSG+="Status: $CUR_STATE | Schedule: $CUR_EXPR | Flags: $CUR_FLAGS\n\n"
                        GUIDE_MSG+="Note: Editing Schedule or Flags preserves 'DISABLED' status.\n"
                        GUIDE_MSG+="Cron execution requires an explicit admin toggle to ENABLE."

                        EDIT_ACT=$(whiptail --title "Configuring: $SEL_GNAME" --cancel-button "Back" --menu "$GUIDE_MSG" 18 80 4 \
                            "1" "Toggle Status (Currently $CUR_STATE)" \
                            "2" "Edit Cron Schedule Expression" \
                            "3" "Edit Output Format & Media Flags" \
                            "4" "Return to Server List" 3>&1 1>&2 2>&3 < /dev/tty | tr -d '"')

                        [ -z "$EDIT_ACT" ] || [ "$EDIT_ACT" == "4" ] && break

                        case $EDIT_ACT in
                            1)
                                if [ "$CUR_STATE" == "ENABLED" ]; then
                                    NEW_STATE="DISABLED"
                                else
                                    NEW_STATE="ENABLED"
                                fi
                                sed -i "/^$SEL_GID|/d" "$CRON_TARGETS"
                                echo "$SEL_GID|$SEL_GNAME|$CUR_EXPR|$CUR_FLAGS|$NEW_STATE" >> "$CRON_TARGETS"
                                sync_crontab
                                whiptail --title "Status Updated" --msgbox "Automated cron status changed to $NEW_STATE for $SEL_GNAME." 8 60 < /dev/tty > /dev/tty
                                ;;
                            2)
                                EXPR_HELP="Edit Cron Schedule for $SEL_GNAME:\n\n"
                                EXPR_HELP+="Syntax: MINUTE HOUR DAY MONTH DAY_OF_WEEK\n"
                                EXPR_HELP+="  0 2 * * 0   -> Every Sunday at 2:00 AM (Default)\n"
                                EXPR_HELP+="  0 0 * * *   -> Daily at Midnight\n\n"
                                EXPR_HELP+="Enter 5-part expression:"

                                NEW_EXPR=$(whiptail --title "Edit Schedule Expression" --inputbox "$EXPR_HELP" 16 70 "$CUR_EXPR" 3>&1 1>&2 2>&3 < /dev/tty | tr -d '"')

                                if [ -n "$NEW_EXPR" ]; then
                                    sed -i "/^$SEL_GID|/d" "$CRON_TARGETS"
                                    echo "$SEL_GID|$SEL_GNAME|$NEW_EXPR|$CUR_FLAGS|$CUR_STATE" >> "$CRON_TARGETS"
                                    sync_crontab
                                    whiptail --msgbox "Schedule expression updated to '$NEW_EXPR'. Status remains $CUR_STATE." 8 60 < /dev/tty > /dev/tty
                                fi
                                ;;
                            3)
                                FMT_HELP="Select Export Output Format:\n"
                                FMT_HELP+="  1) JSON (--json)        - Structured raw API payload (Default)\n"
                                FMT_HELP+="  2) HTML Dark (--html)   - Styled dark-theme browser document\n"
                                FMT_HELP+="  3) Plain Text (--text)  - Compact text logs"

                                NEW_FMT=$(whiptail --title "Output Format" --menu "$FMT_HELP" 16 70 3 \
                                    "1" "JSON (--json)" \
                                    "2" "HTML Dark (--html)" \
                                    "3" "Plain Text (--text)" 3>&1 1>&2 2>&3 < /dev/tty | tr -d '"')

                                [ -z "$NEW_FMT" ] && continue

                                NEW_FLAGS="--json"
                                if [ "$NEW_FMT" == "2" ]; then NEW_FLAGS="--html"; elif [ "$NEW_FMT" == "3" ]; then NEW_FLAGS="--text"; fi

                                if whiptail --title "Media Attachments" --yesno "Download media attachments (images/videos) during scheduled cron runs?" 10 65 < /dev/tty > /dev/tty; then
                                    NEW_FLAGS="$NEW_FLAGS --media"
                                fi

                                sed -i "/^$SEL_GID|/d" "$CRON_TARGETS"
                                echo "$SEL_GID|$SEL_GNAME|$CUR_EXPR|$NEW_FLAGS|$CUR_STATE" >> "$CRON_TARGETS"
                                sync_crontab
                                whiptail --msgbox "Flags updated to '$NEW_FLAGS'. Status remains $CUR_STATE." 8 60 < /dev/tty > /dev/tty
                                ;;
                        esac
                    done
                done
                ;;
            2)
                menu_default_cron_config
                ;;
            3)
                if [ -f "$CRON_TARGETS" ] && [ -s "$CRON_TARGETS" ]; then
                    VIEW_FILE="/tmp/dbk_cron_view_$$"
                    echo "==========================================================================================" > "$VIEW_FILE"
                    echo "                                ACTIVE ENABLED SERVER CRONS                               " >> "$VIEW_FILE"
                    echo "==========================================================================================" >> "$VIEW_FILE"
                    printf "%-20s | %-16s | %-18s | %s\n" "SERVER NAME" "GUILD ID" "SCHEDULE" "FLAGS" >> "$VIEW_FILE"
                    echo "------------------------------------------------------------------------------------------" >> "$VIEW_FILE"
                    while IFS='|' read -r GID GNAME CRON_EXPR FLAGS STATUS; do
                        if [ "$STATUS" == "ENABLED" ]; then
                            printf "%-20.20s | %-16s | %-18s | %s\n" "$GNAME" "$GID" "$CRON_EXPR" "$FLAGS" >> "$VIEW_FILE"
                        fi
                    done < "$CRON_TARGETS"
                    echo "==========================================================================================" >> "$VIEW_FILE"
                    whiptail --title "Enabled Server Crons" --textbox "$VIEW_FILE" 22 95 < /dev/tty > /dev/tty
                    rm -f "$VIEW_FILE"
                else
                    whiptail --title "No Crons Active" --msgbox "No active server crons enabled." 8 45 < /dev/tty > /dev/tty
                fi
                ;;
        esac
    done
}

menu_configuration() {
    while true; do
        CURRENT_TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null | tr -d '\r\n')
        MASKED_TOKEN="${CURRENT_TOKEN:0:12}********************"

        SUB_CHOICE=$(whiptail --title "Configuration & Security Settings" --cancel-button "Back" --menu "Examine and manage system tracking parameters:" 18 70 5 \
            "1" "View / Edit Authorization Token" \
            "2" "Examine System Paths" \
            "3" "View Target Ledger Map (id_map.txt)" \
            "4" "Back to Main Menu" 3>&1 1>&2 2>&3 < /dev/tty | tr -d '"')

        [ -z "$SUB_CHOICE" ] && break

        case $SUB_CHOICE in
            1)
                whiptail --title "Security Notice & Token Status" --msgbox "$SECURITY_DISCLAIMER\n\nActive Token: $MASKED_TOKEN" 16 72 < /dev/tty > /dev/tty
                if whiptail --title "Update Token" --yesno "Would you like to replace your active authorization token now?" 10 60 < /dev/tty > /dev/tty; then
                    UPDATED_TOKEN=$(whiptail --title "New Authorization Token" --inputbox "Paste new token string:" 12 70 3>&1 1>&2 2>&3 < /dev/tty | tr -d '"')
                    if [ -n "$UPDATED_TOKEN" ]; then
                        echo "$UPDATED_TOKEN" | tr -d '\r\n' > "$TOKEN_FILE"
                        chmod 600 "$TOKEN_FILE"
                        whiptail --msgbox "Authorization token updated successfully." 8 45 < /dev/tty > /dev/tty
                        "$SCRIPT_DIR/dcordbk" -d
                    fi
                fi
                ;;
            2)
                whiptail --title "System Path Diagnostics" --msgbox "Storage Root (DBK_ROOT): $DBK_ROOT\nConfig Dir: $CONF_DIR\nExecutable Bin: $SCRIPT_DIR\nToken Path: $TOKEN_FILE" 14 70 < /dev/tty > /dev/tty
                ;;
            3)
                if [ -f "$ID_MAP" ]; then
                    whiptail --title "Target Ledger (First 20 Entries)" --textbox "$ID_MAP" 22 75 < /dev/tty > /dev/tty
                else
                    whiptail --msgbox "Ledger map file does not exist yet. Run discovery." 8 50 < /dev/tty > /dev/tty
                fi
                ;;
            4|"") break ;;
        esac
    done
}

adhoc_wizard() {
    while true; do
        TARGET_TYPE=$(whiptail --title "Ad-Hoc Backup Wizard" --cancel-button "Back" --menu "Select backup target:" 16 65 4 \
            "1" "Entire Server (Guild)" \
            "2" "Specific Channel" \
            "3" "Specific Direct Message" \
            "4" "All Direct Messages (Global Vault)" 3>&1 1>&2 2>&3 < /dev/tty | tr -d '"')
        [ -z "$TARGET_TYPE" ] && return

        SELECTED_ID=""; SELECTED_NAME=""; ARGS=()

        if [ "$TARGET_TYPE" == "1" ]; then
            opts=()
            while IFS='|' read -r id type pgid cat name; do
                if [[ "$id" =~ ^[0-9]+$ ]] && [ "$type" == "Guild" ]; then opts+=("$id" "${name:0:40}"); fi
            done < <(grep "|Guild|" "$ID_MAP")
            [ ${#opts[@]} -eq 0 ] && { whiptail --msgbox "No Servers in ledger." 8 40 < /dev/tty > /dev/tty; continue; }
            SELECTED_ID=$(whiptail --title "Ad-Hoc: Server" --menu "Choose Server:" 22 75 14 "${opts[@]}" 3>&1 1>&2 2>&3 < /dev/tty | tr -d '"')
            [ -z "$SELECTED_ID" ] && continue
            ARGS+=("-g" "$SELECTED_ID")
            SELECTED_NAME="$(grep "^$SELECTED_ID|" "$ID_MAP" | cut -d'|' -f5)"

        elif [ "$TARGET_TYPE" == "2" ]; then
            opts=()
            while IFS='|' read -r id type pgid cat name; do
                if [[ "$id" =~ ^[0-9]+$ ]] && [ "$type" == "Channel" ]; then
                    sname=$(grep "^$pgid|" "$ID_MAP" | cut -d'|' -f5 | cut -c1-15)
                    opts+=("$id" "[$sname] ${name:0:30}")
                fi
            done < <(grep "|Channel|" "$ID_MAP")
            [ ${#opts[@]} -eq 0 ] && { whiptail --msgbox "No Channels in ledger." 8 40 < /dev/tty > /dev/tty; continue; }
            SELECTED_ID=$(whiptail --title "Ad-Hoc: Channel" --menu "Choose Channel:" 22 75 14 "${opts[@]}" 3>&1 1>&2 2>&3 < /dev/tty | tr -d '"')
            [ -z "$SELECTED_ID" ] && continue
            ARGS+=("-c" "$SELECTED_ID")
            SELECTED_NAME="$(grep "^$SELECTED_ID|" "$ID_MAP" | cut -d'|' -f5)"

        elif [ "$TARGET_TYPE" == "3" ]; then
            opts=()
            while IFS='|' read -r id type pgid cat name; do
                if [[ "$id" =~ ^[0-9]+$ ]] && [ "$type" == "DM" ]; then opts+=("$id" "${name:0:40}"); fi
            done < <(grep "|DM|" "$ID_MAP")
            [ ${#opts[@]} -eq 0 ] && { whiptail --msgbox "No DMs mapped yet. Run a DM sync first." 8 50 < /dev/tty > /dev/tty; continue; }
            SELECTED_ID=$(whiptail --title "Ad-Hoc: DM" --menu "Choose DM:" 22 75 14 "${opts[@]}" 3>&1 1>&2 2>&3 < /dev/tty | tr -d '"')
            [ -z "$SELECTED_ID" ] && continue
            ARGS+=("-c" "$SELECTED_ID")
            SELECTED_NAME="$(grep "^$SELECTED_ID|" "$ID_MAP" | cut -d'|' -f5)"

        elif [ "$TARGET_TYPE" == "4" ]; then
            ARGS+=("-D")
            SELECTED_NAME="Global DM Vault"
        fi

        FORMAT_CHOICE=$(whiptail --title "Ad-Hoc: Format" --radiolist "Select format for $SELECTED_NAME:" 15 60 3 \
            "1" "JSON (Data Parsing)" ON \
            "2" "HTML Dark (Readable)" OFF \
            "3" "Plain Text (Fastest)" OFF 3>&1 1>&2 2>&3 < /dev/tty | tr -d '"')
        [ -z "$FORMAT_CHOICE" ] && continue

        if [ "$FORMAT_CHOICE" == "2" ]; then ARGS+=("--html"); elif [ "$FORMAT_CHOICE" == "3" ]; then ARGS+=("--text"); else ARGS+=("--json"); fi

        if whiptail --title "Ad-Hoc: Media" --yesno "Download media attachments for this run?" 10 60 < /dev/tty > /dev/tty; then
            ARGS+=("--media")
        fi

        echo -e "${BLUE}========================================================${NC}"
        echo " LAUNCHING AD-HOC BACKUP: $SELECTED_NAME"
        echo -e "${BLUE}========================================================${NC}"
        sleep 1
        "$SCRIPT_DIR/dcordbk" "${ARGS[@]}"
        echo -e "\n>>> Backup Complete. Press ENTER to return to Mission Control."
        read -r < /dev/tty
        return
    done
}

while true; do
    CHOICE=$(whiptail --title "Mission Control" --cancel-button "Exit" --menu "Select action (ESC twice to quit):" 18 70 7 \
        "1" "Run Ad-Hoc Backup Wizard" \
        "2" "Automated Server Cron Management" \
        "3" "Configuration & Token Management" \
        "4" "Create System Restore Point" \
        "5" "Rollback System State" \
        "6" "Reset & Rescan Discord Ledger" \
        "7" "Exit" 3>&1 1>&2 2>&3 < /dev/tty | tr -d '"')

    if [ -z "$CHOICE" ]; then exit 0; fi

    case $CHOICE in
        1) adhoc_wizard ;;
        2) menu_server_crons ;;
        3) menu_configuration ;;
        4) "$SCRIPT_DIR/dcordbk-installer.bash" --restore-point; read -r < /dev/tty ;;
        5) "$SCRIPT_DIR/dcordbk-installer.bash" --rollback; read -r < /dev/tty ;;
        6) "$SCRIPT_DIR/dcordbk" -d; read -r < /dev/tty ;;
        7|"") exit 0 ;;
    esac
done
EOF

# ==============================================================================
# FILE 4: DiscordChatExporter.Cli (Verbose Native Python Engine + Native Media Downloader)
# ==============================================================================
cat << 'EOF' > "$TARGET_BIN/DiscordChatExporter.Cli"
#!/usr/bin/env python3
import sys, os, json, argparse, urllib.request, urllib.error, time

API_BASE = "https://discord.com/api/v9"
BASE_DELAY = float(os.environ.get("DBK_API_DELAY", "0.5"))

def req(endpoint, token, retries=5):
    headers = {"Authorization": token, "User-Agent": "Mozilla/5.0"}
    url = f"{API_BASE}{endpoint}" if endpoint.startswith("/") else endpoint
    print(f"[API QUERY] GET -> {url}")
    
    time.sleep(BASE_DELAY)

    for attempt in range(retries):
        request = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(request) as resp:
                rem = resp.headers.get("X-RateLimit-Remaining")
                lim = resp.headers.get("X-RateLimit-Limit")
                
                if rem is not None and lim is not None:
                    try:
                        r_val, l_val = int(rem), int(lim)
                        if l_val > 0 and (r_val / l_val) < 0.5:
                            print(f"[RATE GOVERNOR] Capacity at {r_val}/{l_val} (<50%). Injecting 1.0s pacing delay...")
                            time.sleep(1.0)
                    except ValueError:
                        pass

                data = json.loads(resp.read().decode('utf-8'))
                print(f"[API SUCCESS] Response size: {len(str(data))} bytes")
                return data
        except urllib.error.HTTPError as e:
            if e.code == 429:
                retry_after = 2.0
                try:
                    body = json.loads(e.read().decode('utf-8'))
                    retry_after = float(body.get('retry_after', 2.0))
                except Exception:
                    pass
                print(f"[API RATE LIMIT 429] Discord requested backoff. Pausing for {retry_after:.2f}s (Attempt {attempt+1}/{retries})...")
                time.sleep(retry_after + 0.5)
            else:
                sys.stderr.write(f"[API HTTP ERROR {e.code}] {e.reason} on {url}\n")
                return None
        except Exception as e:
            sys.stderr.write(f"[API REQUEST ERROR] {e} on {url}\n")
            return None
    return None

def download_media_file(url, destination_folder):
    os.makedirs(destination_folder, exist_ok=True)
    filename = url.split("/")[-1].split("?")[0]
    dest_path = os.path.join(destination_folder, filename)
    if os.path.exists(dest_path):
        return
    try:
        print(f"  [MEDIA DOWNLOAD] -> {filename}")
        req_obj = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req_obj) as resp, open(dest_path, "wb") as out_f:
            out_f.write(resp.read())
        time.sleep(0.15)
    except Exception as e:
        sys.stderr.write(f"  [MEDIA ERROR] Failed downloading {filename}: {e}\n")

def fetch_all_messages(channel_id, token):
    all_msgs = []
    before_id = None
    batch_count = 0
    while True:
        batch_count += 1
        endpoint = f"/channels/{channel_id}/messages?limit=100"
        if before_id: endpoint += f"&before={before_id}"
        print(f"[FETCH BATCH {batch_count}] Requesting messages for channel {channel_id}...")
        batch = req(endpoint, token)
        if not batch or len(batch) == 0:
            print(f"[FETCH COMPLETE] Finished retrieving {len(all_msgs)} total messages.")
            break
        all_msgs.extend(batch)
        print(f"  -> Batch size: {len(batch)} messages. Cumulative total: {len(all_msgs)}")
        before_id = batch[-1]['id']
    return list(reversed(all_msgs))

def export_channel(channel_id, token, output_pattern, fmt, media, gname="Guild", cname="Channel", catname="Category"):
    print(f"[EXPORT START] Channel: {channel_id} | Format: {fmt} | Media: {media}")
    messages = fetch_all_messages(channel_id, token)
    if messages is None or len(messages) == 0:
        print(f"[EXPORT NOTICE] No messages retrieved for channel {channel_id}.")
        return

    out_file = output_pattern.replace("%g", gname).replace("%c", cname).replace("%C", catname)
    ext = ".json" if fmt == "Json" else ".html" if fmt == "HtmlDark" else ".txt"
    if not out_file.endswith(ext): out_file += ext

    target_path = os.path.abspath(out_file)
    print(f"[WRITING FILE] Destination: {target_path}")
    os.makedirs(os.path.dirname(target_path), exist_ok=True)
    with open(target_path, "w", encoding="utf-8") as f:
        if fmt == "Json":
            json.dump(messages, f, indent=2)
        else:
            for m in messages:
                author = m.get("author", {}).get("username", "Unknown")
                content = m.get("content", "")
                ts = m.get("timestamp", "")
                f.write(f"[{ts}] {author}: {content}\n")
    print(f"[EXPORT COMPLETE] Written to {target_path}")

    if media and messages:
        media_dir = os.path.join(os.path.dirname(target_path), "attachments")
        print(f"[MEDIA PIPELINE] Extracting attachments for channel {channel_id}...")
        for m in messages:
            for att in m.get("attachments", []):
                att_url = att.get("url")
                if att_url:
                    download_media_file(att_url, media_dir)

def export_guild(guild_id, token, output_pattern, fmt, media):
    print(f"[GUILD EXPORT] Fetching guild details for {guild_id}...")
    guild_data = req(f"/guilds/{guild_id}", token)
    gname = guild_data.get('name', 'Guild') if guild_data else 'Guild'
    
    chans = req(f"/guilds/{guild_id}/channels", token)
    if not chans:
        print(f"[GUILD EXPORT ERROR] Could not fetch channels for guild {guild_id}.")
        return
    
    cats = {c['id']: c['name'] for c in chans if c.get('type') == 4}
    for c in chans:
        if c.get('type') in (0, 5):
            cname = c.get('name', 'Channel')
            catname = cats.get(c.get('parent_id'), 'Uncategorized')
            export_channel(c['id'], token, output_pattern, fmt, media, gname, cname, catname)

def export_dm(token, output_pattern, fmt, media):
    print("[DM EXPORT] Fetching Direct Message conversations...")
    dms = req("/users/@me/channels", token)
    if not dms:
        print("[DM EXPORT ERROR] Could not fetch DM channels.")
        return
    
    for dm in dms:
        dm_id = dm['id']
        recipients = dm.get('recipients', [])
        if len(recipients) > 0:
            cname = ", ".join([r.get('username', 'User') for r in recipients])
        else:
            cname = dm.get('name', f"DM_{dm_id}")
        export_channel(dm_id, token, output_pattern, fmt, media, "Direct Messages", cname, "Direct Messages")

def export_all(token, output_pattern, fmt, media):
    print("[FULL BACKUP] Initiating complete account archive...")
    export_dm(token, output_pattern, fmt, media)
    
    guilds = req("/users/@me/guilds", token)
    if guilds:
        for g in guilds:
            export_guild(g['id'], token, output_pattern, fmt, media)

def main():
    parser = argparse.ArgumentParser(description="Verbose Native Discord CLI Engine")
    subparsers = parser.add_subparsers(dest="command")

    p_g = subparsers.add_parser("guilds")
    p_g.add_argument("-t", "--token", required=True)

    p_c = subparsers.add_parser("channels")
    p_c.add_argument("-g", "--guild", required=True)
    p_c.add_argument("-t", "--token", required=True)

    p_exp = subparsers.add_parser("export")
    p_exp.add_argument("-c", "--channel", required=True)
    p_exp.add_argument("-t", "--token", required=True)
    p_exp.add_argument("--output", required=True)
    p_exp.add_argument("--format", default="Json")
    p_exp.add_argument("--media", action="store_true")

    p_eg = subparsers.add_parser("exportguild")
    p_eg.add_argument("-g", "--guild", required=True)
    p_eg.add_argument("-t", "--token", required=True)
    p_eg.add_argument("--output", required=True)
    p_eg.add_argument("--format", default="Json")
    p_eg.add_argument("--media", action="store_true")

    p_edm = subparsers.add_parser("exportdm")
    p_edm.add_argument("-t", "--token", required=True)
    p_edm.add_argument("--output", required=True)
    p_edm.add_argument("--format", default="Json")
    p_edm.add_argument("--media", action="store_true")

    p_eall = subparsers.add_parser("exportall")
    p_eall.add_argument("-t", "--token", required=True)
    p_eall.add_argument("--output", required=True)
    p_eall.add_argument("--format", default="Json")
    p_eall.add_argument("--media", action="store_true")

    args, _ = parser.parse_known_args()

    if args.command == "guilds":
        print(">>> Fetching Guild List...")
        guilds = req("/users/@me/guilds", args.token)
        if guilds:
            for g in guilds: print(f"{g['id']} | {g['name']}")
    elif args.command == "channels":
        print(f">>> Fetching Channel List for Guild {args.guild}...")
        chans = req(f"/guilds/{args.guild}/channels", args.token)
        if chans:
            cats = {c['id']: c['name'] for c in chans if c.get('type') == 4}
            for c in chans:
                if c.get('type') in (0, 2, 5):
                    print(f"{c['id']} | {cats.get(c.get('parent_id'), 'Uncategorized')} | {c['name']}")
    elif args.command == "export":
        export_channel(args.channel, args.token, args.output, args.format, args.media)
    elif args.command == "exportguild":
        export_guild(args.guild, args.token, args.output, args.format, args.media)
    elif args.command == "exportdm":
        export_dm(args.token, args.output, args.format, args.media)
    elif args.command == "exportall":
        export_all(args.token, args.output, args.format, args.media)

if __name__ == "__main__":
    main()
EOF

sed -i "s|PLACEHOLDER_PATH|$TARGET_ROOT|g" "$TARGET_BIN/dcordbk" "$TARGET_BIN/dbkui"
sed -i "s|PLACEHOLDER_BIN|$TARGET_BIN|g" "$TARGET_BIN/dcordbk"
sed -i "s|PLACEHOLDER_IS_SYSTEM|$IS_SYSTEM|g" "$TARGET_BIN/dcordbk"
sed -i "s|PLACEHOLDER_EXEC_LOG|$TARGET_ROOT/.conf/dbk_execution.log|g" "$TARGET_BIN/dcordbk"

chmod +x "$TARGET_BIN/dcordbk" "$TARGET_BIN/dbkworker.sh" "$TARGET_BIN/dbkui" "$TARGET_BIN/DiscordChatExporter.Cli" "$TARGET_BIN/dcordbk-installer.bash" "$TARGET_BIN/dcordbk-uninstaller.bash"
chown -R "$REAL_USER:" "$TARGET_ROOT" "$TARGET_BIN" 2>/dev/null
log_msg "${GREEN}>>> Deployment complete to $TARGET_BIN.${NC}"
