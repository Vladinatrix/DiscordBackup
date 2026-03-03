#!/bin/bash
# ==============================================================================
# Version: 0.2.11
# Description: Unified Installer for DCORDBK Archival Suite & Hierarchical UI
# Target OS: CentOS 9 Stream / RHEL 9
# ==============================================================================

# --- COLORS ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# --- DEFAULTS ---
TARGET_BIN=""
TARGET_ROOT=""
DO_INSTALL=false
IS_SYSTEM="false"

echo -e "${BLUE}"
echo "========================================================"
echo "    DCORDBK UNIFIED INSTALLER (v0.2.11)"
echo "========================================================"
echo -e "${NC}"

for arg in "$@"; do
    case $arg in
        --prefix=*)
            CUSTOM_PATH="${arg#*=}"
            TARGET_BIN="$CUSTOM_PATH/bin"
            TARGET_ROOT="$CUSTOM_PATH/discord_archive"
            DO_INSTALL=true
            if [ "$EUID" -eq 0 ]; then IS_SYSTEM="true"; fi
            shift
            ;;
        --help)
            echo "Usage: ./installdbk.bash [OPTIONS]"
            echo "  --prefix=<PATH>   Install to custom directory"
            exit 0
            ;;
    esac
done

if [ "$DO_INSTALL" = false ]; then
    echo "Choose installation type:"
    echo "  1) User Install (Strict Local Confinement - Recommended)"
    echo "  2) System Install (Requires Sudo)"
    echo "  3) Custom Install"
    read -p "Select option [1-3]: " OPTION

    case $OPTION in
        1) 
            TARGET_BIN="$HOME/bin"; TARGET_ROOT="$HOME/Discord_Archive" 
            IS_SYSTEM="false" 
            ;;
        2) 
            if [ "$EUID" -ne 0 ]; then echo -e "${RED}Error: System install requires sudo.${NC}"; exit 1; fi
            TARGET_BIN="/usr/local/bin"; TARGET_ROOT="/usr/local/discord_archive" 
            IS_SYSTEM="true"
            ;;
        3) 
            read -p "Target Bin: " TARGET_BIN
            read -p "Target Storage: " TARGET_ROOT 
            if [ "$EUID" -eq 0 ]; then IS_SYSTEM="true"; else IS_SYSTEM="false"; fi
            ;;
        *) echo "Invalid option."; exit 1 ;;
    esac
fi

echo -e "\n${BLUE}>>> Installing to:${NC}\n    Binaries: $TARGET_BIN\n    Storage:  $TARGET_ROOT\n    System Mode: $IS_SYSTEM\n"
read -p "Proceed? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then exit 0; fi

if ! mkdir -p "$TARGET_BIN" "$TARGET_ROOT/.conf/.tmp" 2>/dev/null; then
    echo -e "${RED}CRITICAL ERROR: Permission denied creating target directories.${NC}"
    exit 1
fi

echo -e "${GREEN}>>> Directories created.${NC}"

# ==============================================================================
# FILE 1: dcordbk (Master Wrapper & Relational Discovery Engine)
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
export DBK_CRON_LOG="PLACEHOLDER_CRON_LOG"

export DBK_DISCORD_BINARY="/usr/local/bin/DiscordChatExporter.Cli"

# Token Ingestion
if [ -f "$DBK_TOKEN_FILE" ]; then
    export DBK_TOKEN=$(cat "$DBK_TOKEN_FILE")
else
    export DBK_TOKEN=""
fi

# Ledger Version 3.0 (Relational Format: ID|Type|ParentGID|Category|Name)
LEDGER_VERSION="3.0"
BLUE='\033[0;34m'; NC='\033[0m'

# Internal Log Rotation (Prevents infinite log growth without needing sudo/logrotate)
if [ "$IS_SYSTEM" == "true" ]; then
    if [ ! -f "/etc/logrotate.d/dcordbk" ]; then
        cat << ROTATE_EOF | sudo tee "/etc/logrotate.d/dcordbk" >/dev/null 2>&1
$DBK_EXEC_LOG
$DBK_CRON_LOG {
    monthly; rotate 12; missingok; notifempty; create 0644 root root
}
ROTATE_EOF
    fi
else
    # Native User-Space Log Rotation (5MB Threshold)
    for LOG in "$DBK_EXEC_LOG" "$DBK_CRON_LOG"; do
        if [ -f "$LOG" ]; then
            LOG_SIZE=$(stat -c%s "$LOG" 2>/dev/null || echo 0)
            if [ "$LOG_SIZE" -gt 5242880 ]; then
                mv "$LOG" "${LOG}.old"
                touch "$LOG"
            fi
        fi
    done
fi

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

if [ -f "$ID_MAP_FILE" ] && [ "$DO_DISCOVER" = false ]; then
    if [[ "$(head -n 1 "$ID_MAP_FILE" 2>/dev/null)" != "# VERSION: $LEDGER_VERSION" ]]; then
        mv "$ID_MAP_FILE" "${ID_MAP_FILE%.txt}_$(date +%Y-%m-%d_%H-%M-%S).txt"
        echo -e "${BLUE}>>> Ledger outdated. Upgrading to v3.0 Relational Format...${NC}"
        DO_DISCOVER=true
    fi
fi

active_discovery() {
    echo "========================================================"
    echo " INITIATING ACTIVE DISCOVERY (Querying Discord API...)"
    echo "========================================================"
    
    mkdir -p "$DBK_TMP_DIR"
    echo ">>> Fetching Guilds (Servers)..."
    "$DBK_DISCORD_BINARY" guilds -t "$DBK_TOKEN" > "$DBK_TMP_DIR/guilds_raw.txt" 2>/dev/null
    
    grep -E "^[0-9]+[ \t]+\|" "$DBK_TMP_DIR/guilds_raw.txt" | awk -F'|' '{
        gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $2); print $1"|Guild|0|None|"$2
    }' > "$DBK_TMP_DIR/parsed_targets.txt"
    
    echo -n ">>> Fetching Categories and Channels "
    while IFS='|' read -r GID TYPE PARENT CAT GNAME; do
        if [ "$TYPE" == "Guild" ]; then
            echo -n "."
            "$DBK_DISCORD_BINARY" channels -g "$GID" -t "$DBK_TOKEN" > "$DBK_TMP_DIR/chans_${GID}.txt" 2>/dev/null
            grep -E "^[0-9]+[ \t]+\|" "$DBK_TMP_DIR/chans_${GID}.txt" | awk -v gid="$GID" -F'|' '{
                id=$1; cat=$2; name=$3; 
                if(name=="") { name=cat; cat="Uncategorized"; }
                gsub(/^[ \t]+|[ \t]+$/, "", id); gsub(/^[ \t]+|[ \t]+$/, "", cat); gsub(/^[ \t]+|[ \t]+$/, "", name);
                if(cat=="") cat="Uncategorized"; print id"|Channel|"gid"|"cat"|"name
            }' >> "$DBK_TMP_DIR/parsed_targets.txt"
            rm "$DBK_TMP_DIR/chans_${GID}.txt" 2>/dev/null
        fi
    done < <(grep "|Guild|" "$DBK_TMP_DIR/parsed_targets.txt")
    echo " Done."
    
    echo "# VERSION: $LEDGER_VERSION" > "$ID_MAP_FILE"
    sort -u -t'|' -k1,1 "$DBK_TMP_DIR/parsed_targets.txt" >> "$ID_MAP_FILE"
    rm -f "$DBK_TMP_DIR/"*.txt 2>/dev/null
    echo ">>> Discovery complete. Ledger updated."
}

if [ "$DO_DISCOVER" = true ]; then active_discovery; exit 0; fi

WORKER="$DBK_SCRIPT_DIR/dbkworker.sh"
"$WORKER" "${PASSTHROUGH_ARGS[@]}" 2>&1 | tee -a "$DBK_EXEC_LOG"
EOF

# ==============================================================================
# FILE 2: dbkworker.sh (Backend Engine & Post-Processing Harvester)
# ==============================================================================
cat << 'EOF' > "$TARGET_BIN/dbkworker.sh"
#!/bin/bash
if [ -z "$DBK_ROOT" ] || [ -z "$DBK_TOKEN" ]; then exit 1; fi
CMD="$DBK_DISCORD_BINARY"; DATE=$(date +%Y-%m-%d_%H-%M-%S)
if [ -t 1 ]; then IS_INTERACTIVE=true; else IS_INTERACTIVE=false; fi

MODE="DMS"; MEDIA=""; FORMAT="PlainText"; ARGS=()
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

if [ "$MODE" == "FULL" ]; then DIR_NAME="${DATE}_FULL";
elif [ "$MODE" == "DMS" ]; then DIR_NAME="${DATE}_DMS";
else DIR_NAME="${DATE}_SELECTIVE"; fi

OUT_BASE="$DBK_ARCHIVE_DIR/$DIR_NAME"

EXT=".txt"
if [ "$FORMAT" == "HtmlDark" ]; then EXT=".html"; fi
if [ "$FORMAT" == "Json" ]; then EXT=".json"; fi

if [ "$MODE" == "FULL" ]; then "$CMD" exportall -t "$DBK_TOKEN" $MEDIA --format "$FORMAT" --output "$OUT_BASE/%g - %c$EXT"
elif [ "$MODE" == "DMS" ]; then "$CMD" exportdm -t "$DBK_TOKEN" $MEDIA --format "$FORMAT" --output "$OUT_BASE/%c - %C$EXT"
elif [ "$MODE" == "SELECTIVE" ]; then
    for ITEM in "${ARGS[@]}"; do
        TYPE="${ITEM%%:*}"; ID="${ITEM##*:}"
        if [ "$TYPE" == "CHANNEL" ]; then 
            "$CMD" export -c "$ID" -t "$DBK_TOKEN" $MEDIA --format "$FORMAT" --output "$OUT_BASE/%g - %c$EXT"
        elif [ "$TYPE" == "GUILD" ]; then 
            "$CMD" exportguild -g "$ID" -t "$DBK_TOKEN" $MEDIA --format "$FORMAT" --output "$OUT_BASE/%g - %c$EXT"
        fi
    done
fi

EXPORT_EXIT=$?
if [ "$MODE" == "DMS" ] && [ -d "$OUT_BASE" ]; then
    for file in "$OUT_BASE"/*; do
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
        mv "$DBK_TMP_DIR/sorted_map.txt" "$DBK_CONF_DIR/id_map.txt"
    fi
fi

if [ $EXPORT_EXIT -eq 0 ] && [ -d "$OUT_BASE" ]; then
    if [ "$IS_INTERACTIVE" = true ]; then 
        echo -e "\n>>> Export complete. Compressing payload (Multi-core enabled)..."
        # -v on tar outputs file streams to stderr so the user can see progress, -T0 on xz enables multi-threading
        tar -C "$DBK_ARCHIVE_DIR" -cvf - "$DIR_NAME" | xz -9e -T0 > "${OUT_BASE}.tar.xz"
    else 
        # Silent cron run
        tar -C "$DBK_ARCHIVE_DIR" -cf - "$DIR_NAME" | xz -9e -T0 > "${OUT_BASE}.tar.xz"
    fi
    rm -rf "$OUT_BASE"
elif [ -d "$OUT_BASE" ]; then
    rm -rf "$OUT_BASE"
    if [ "$IS_INTERACTIVE" = true ]; then echo -e "\n>>> Run aborted or failed. Staging directory cleaned."; fi
fi
EOF

# ==============================================================================
# FILE 3: dbkui (Hierarchical Configuration UI & Failsafe Runner)
# ==============================================================================
cat << 'EOF' > "$TARGET_BIN/dbkui"
#!/bin/bash
export DBK_ROOT="PLACEHOLDER_PATH"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONF_DIR="$DBK_ROOT/.conf"
ID_MAP="$CONF_DIR/id_map.txt"
CRON_TARGETS="$CONF_DIR/cron_targets.txt"
CRON_RUNNER="$SCRIPT_DIR/dbk-cron-runner.sh"
TOKEN_FILE="$CONF_DIR/.token"
BLUE='\033[0;34m'; NC='\033[0m'

# --- Token Verification & Auto-Scan Phase ---
if [ ! -f "$TOKEN_FILE" ] || [ -z "$(cat "$TOKEN_FILE")" ]; then
    NEW_TOKEN=$(whiptail --title "Authentication Required" --inputbox "Welcome to the Discord Archive Suite.\n\nPlease paste your Discord Authorization Token to continue:" 12 65 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$NEW_TOKEN" ]; then
        clear; echo "A Discord Token is required to operate this suite. Exiting."; exit 1
    fi
    # Save the token
    echo "$NEW_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    
    # Immediately trigger the first-time discovery scan
    clear
    echo -e "${BLUE}========================================================${NC}"
    echo " TOKEN ACCEPTED. INITIATING AUTOMATIC DISCOVERY..."
    echo -e "${BLUE}========================================================${NC}"
    sleep 1
    "$SCRIPT_DIR/dcordbk" -d
    echo -e "\n>>> Discovery Complete. Press ENTER to open Mission Control."
    read

elif [ ! -f "$ID_MAP" ] || [ ! -s "$ID_MAP" ]; then 
    clear
    echo -e "${BLUE}========================================================${NC}"
    echo " MISSING LEDGER DETECTED. INITIATING AUTOMATIC DISCOVERY..."
    echo -e "${BLUE}========================================================${NC}"
    sleep 1
    "$SCRIPT_DIR/dcordbk" -d
    echo -e "\n>>> Discovery Complete. Press ENTER to open Mission Control."
    read
fi

config_card() {
    local TID="$1"; local TNAME="$2"; local TTYPE="$3"
    local S_B="OFF"; local S_T="OFF"; local S_M="OFF"
    
    if grep -q "^$TID|" "$CRON_TARGETS" 2>/dev/null; then
        local REC=$(grep "^$TID|" "$CRON_TARGETS")
        if [ "$(echo "$REC" | cut -d'|' -f4)" == "1" ]; then S_B="ON"; fi
        if [ "$(echo "$REC" | cut -d'|' -f5)" == "1" ]; then S_T="ON"; fi
        if [ "$(echo "$REC" | cut -d'|' -f6)" == "1" ]; then S_M="ON"; fi
    fi

    local CHOICES=$(whiptail --title "Automated Schedule: ${TNAME:0:20}" --cancel-button "Back" --checklist "Use SPACE to toggle, ENTER to confirm.\nOptions for $TTYPE:" 15 65 3 \
        "BACKUP" "Enable Automated Backup" $S_B "TEXT" "Plain Text Format" $S_T "MEDIA" "Include Images/Video" $S_M 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return 1
    
    local N_B=0; local N_T=0; local N_M=0
    if [[ $CHOICES == *"\"BACKUP\""* ]]; then N_B=1; fi
    if [[ $CHOICES == *"\"TEXT\""* ]]; then N_T=1; fi
    if [[ $CHOICES == *"\"MEDIA\""* ]]; then N_M=1; fi
    
    touch "$CRON_TARGETS"
    sed -i "/^$TID|/d" "$CRON_TARGETS"
    echo "$TID|$TTYPE|$TNAME|$N_B|$N_T|$N_M" >> "$CRON_TARGETS"

    if [ "$TTYPE" == "Guild" ] && [ "$N_B" == "1" ]; then
        local OVERLAPS_EXIST=false
        for cid in $(grep "|Channel|$TID|" "$ID_MAP" | cut -d'|' -f1); do
            if grep -q "^$cid|" "$CRON_TARGETS" 2>/dev/null; then OVERLAPS_EXIST=true; break; fi
        done

        if [ "$OVERLAPS_EXIST" = true ]; then
            local DEDUPE_CHOICE=$(whiptail --title "Overlapping Rules" --cancel-button "Skip" --checklist \
            "WARNING: Channels in this server have custom rules.\nThis will cause DOUBLE-BACKUPS.\nUse SPACE to deduplicate (purge custom channel rules):" 15 70 1 \
            "DEDUPLICATE" "Purge overlapping channel rules" ON 3>&1 1>&2 2>&3)
            
            if [[ $DEDUPE_CHOICE == *"\"DEDUPLICATE\""* ]]; then
                for cid in $(grep "|Channel|$TID|" "$ID_MAP" | cut -d'|' -f1); do
                    sed -i "/^$cid|/d" "$CRON_TARGETS" 2>/dev/null
                done
            fi
        fi
    fi
    return 0
}

mass_config_cat() {
    local GID="$1"; local CAT="$2"
    local CHOICES=$(whiptail --title "Mass Config: ${CAT:0:30}" --cancel-button "Back" --checklist "Use SPACE to toggle. Applies to ALL in $CAT:" 15 65 3 \
        "BACKUP" "Enable Backup" ON "TEXT" "Plain Text" ON "MEDIA" "Include Media" OFF 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return
    
    local N_B=0; local N_T=0; local N_M=0
    [[ $CHOICES == *"\"BACKUP\""* ]] && N_B=1
    [[ $CHOICES == *"\"TEXT\""* ]] && N_T=1
    [[ $CHOICES == *"\"MEDIA\""* ]] && N_M=1

    while IFS='|' read -r cid ctype pgid ccat cname; do
        if [[ ! "$cid" =~ ^[0-9]+$ ]]; then continue; fi
        if [ "$pgid" == "$GID" ] && [ "$ccat" == "$CAT" ]; then
            sed -i "/^$cid|/d" "$CRON_TARGETS" 2>/dev/null
            echo "$cid|Channel|$cname|$N_B|$N_T|$N_M" >> "$CRON_TARGETS"
        fi
    done < "$ID_MAP"
    
    sed -i "/^$GID|Guild|/d" "$CRON_TARGETS" 2>/dev/null
    whiptail --msgbox "Applied to all channels in $CAT." 8 40
}

menu_channels() {
    local GID="$1"; local CAT="$2"
    while true; do
        local opts=()
        while IFS='|' read -r id type pgid ccat name; do
            if [[ ! "$id" =~ ^[0-9]+$ ]]; then continue; fi
            if [ "$pgid" == "$GID" ] && [ "$ccat" == "$CAT" ]; then
                if grep -q "^$id|.*|1|.*" "$CRON_TARGETS" 2>/dev/null; then s="[ON ]"; else s="[OFF]"; fi
                opts+=("$id" "$s ${name:0:40}")
            fi
        done < "$ID_MAP"
        if [ ${#opts[@]} -eq 0 ]; then whiptail --msgbox "No channels found." 8 40; break; fi
        
        local sel=$(whiptail --title "Channels in ${CAT:0:20}" --cancel-button "Back" --menu "Select Channel:" 22 70 14 "${opts[@]}" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && break
        [ -z "$sel" ] && break
        config_card "$sel" "$(grep "^$sel|" "$ID_MAP" | cut -d'|' -f5)" "Channel"
    done
}

menu_categories() {
    local GID="$1"
    while true; do
        local opts=()
        while read -r c; do
            if [ -n "$c" ]; then opts+=("$c" "Folder"); fi
        done < <(grep "|Channel|$GID|" "$ID_MAP" | cut -d'|' -f4 | sort -u)
        if [ ${#opts[@]} -eq 0 ]; then whiptail --msgbox "No categories found." 8 40; break; fi
        
        local sel=$(whiptail --title "Categories" --cancel-button "Back" --menu "Select Category:" 20 60 10 "${opts[@]}" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && break
        [ -z "$sel" ] && break
        
        local act=$(whiptail --menu "Action for ${sel:0:30}:" --cancel-button "Back" 15 50 2 "1" "Mass Configure All Channels" "2" "Select Individual Channels" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && continue
        if [ "$act" == "1" ]; then mass_config_cat "$GID" "$sel"; elif [ "$act" == "2" ]; then menu_channels "$GID" "$sel"; fi
    done
}

menu_servers() {
    while true; do
        local opts=()
        while IFS='|' read -r id type pgid cat name; do
            if [[ ! "$id" =~ ^[0-9]+$ ]]; then continue; fi
            if [ "$type" == "Guild" ]; then
                if grep -q "^$id|.*|1|.*" "$CRON_TARGETS" 2>/dev/null; then s="[GLOBAL ON]"; else s="[CUSTOM/OFF]"; fi
                opts+=("$id" "$s ${name:0:40}")
            fi
        done < <(grep "|Guild|" "$ID_MAP")
        if [ ${#opts[@]} -eq 0 ]; then whiptail --msgbox "No Servers found." 8 40; break; fi
        
        local sel=$(whiptail --title "Servers" --cancel-button "Back" --menu "Select Server:" 22 75 14 "${opts[@]}" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && break
        [ -z "$sel" ] && break
        
        local name=$(grep "^$sel|" "$ID_MAP" | cut -d'|' -f5)
        local act=$(whiptail --menu "Server: ${name:0:30}" --cancel-button "Back" 15 60 2 "1" "Configure Entire Server Backup" "2" "Custom (By Category)" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && continue
        if [ "$act" == "1" ]; then config_card "$sel" "$name" "Guild"; elif [ "$act" == "2" ]; then menu_categories "$sel"; fi
    done
}

menu_dms() {
    while true; do
        local opts=()
        while IFS='|' read -r id type pgid cat name; do
            if [[ ! "$id" =~ ^[0-9]+$ ]]; then continue; fi
            if [ "$type" == "DM" ]; then
                if grep -q "^$id|.*|1|.*" "$CRON_TARGETS" 2>/dev/null; then s="[ON ]"; else s="[OFF]"; fi
                opts+=("$id" "$s ${name:0:40}")
            fi
        done < <(grep "|DM|" "$ID_MAP")
        
        if [ ${#opts[@]} -eq 0 ]; then 
            if whiptail --title "Primer Harvest Required" --yesno "No DMs mapped yet.\n\nRun a quick DM sync now to populate this menu?" 10 50; then
                clear
                echo ">>> Running Global DM Harvest..."
                "$SCRIPT_DIR/dcordbk" -D
                echo ">>> Harvest complete. Press ENTER to reload menu."
                read
                continue
            else
                break
            fi
        fi
        
        local sel=$(whiptail --title "Direct Messages" --cancel-button "Back" --menu "Select DM:" 22 70 14 "${opts[@]}" 3>&1 1>&2 2>&3)
    
        [ $? -ne 0 ] && break
        [ -z "$sel" ] && break
        config_card "$sel" "$(grep "^$sel|" "$ID_MAP" | cut -d'|' -f5)" "DM"
    done
}

menu_backup_options() {
    while true; do
        local SUB=$(whiptail --menu "Automated Cron Settings:" --cancel-button "Back" 15 50 2 "1" "Direct Messages" "2" "Servers (Guilds)" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && break
        [ -z "$SUB" ] && break
        if [ "$SUB" == "1" ]; then menu_dms; elif [ "$SUB" == "2" ]; then menu_servers; fi
    done
}

write_to_cron() {
    cat << 'RUNNER_EOF' > "$CRON_RUNNER"
#!/bin/bash
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CRON_TARGETS="$DBK_ROOT/.conf/cron_targets.txt"
WRAPPER="$SCRIPT_DIR/dcordbk"

echo "=== CRON EXECUTION STARTED: $(date) ==="
echo ">>> Executing Active Discovery pre-sync to map new channels..."
"$WRAPPER" -d

echo ">>> Launching automated backup targets..."
while IFS='|' read -r ID TYPE NAME BACKUP TEXT MEDIA; do
    if [[ ! "$ID" =~ ^[0-9]+$ ]]; then continue; fi
    if [ "$BACKUP" == "1" ]; then
        ARGS=(); if [ "$TYPE" == "Guild" ]; then ARGS+=("-g" "$ID"); else ARGS+=("-c" "$ID"); fi
        if [ "$TEXT" == "1" ]; then ARGS+=("--text"); fi; if [ "$MEDIA" == "1" ]; then ARGS+=("--media"); fi
        "$WRAPPER" "${ARGS[@]}"
    fi
done < "$CRON_TARGETS"
echo "=== CRON EXECUTION COMPLETE: $(date) ==="
RUNNER_EOF

    chmod +x "$CRON_RUNNER"
    sed -i "s|DBK_ROOT=.*|DBK_ROOT=\"$DBK_ROOT\"|g" "$CRON_RUNNER"
    
    local SCHED=$(whiptail --cancel-button "Cancel" --radiolist "Select automation frequency:" 15 50 3 "DAILY" "3:00 AM" OFF "WEEKLY" "Sun 3:00 AM" ON "MONTHLY" "1st 3:00 AM" OFF 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return
    [ -z "$SCHED" ] && return
    
    if [ "$SCHED" == "DAILY" ]; then CRON_STR="0 3 * * *"; elif [ "$SCHED" == "WEEKLY" ]; then CRON_STR="0 3 * * 0"; else CRON_STR="0 3 1 * *"; fi
    
    TMPDIR="$CONF_DIR/.tmp"
    local TMP_CRON=$(mktemp)
    crontab -l 2>/dev/null | sed -e '/dcordbk/d' -e '/dbk-cron-runner/d' -e '/MONTHLY FULL/d' -e '/WEEKLY PARTIAL/d' -e '/Target:/d' -e '/^# ----*/d' -e '/# === DBKUI/,/# === END DBKUI/d' > "$TMP_CRON"
    
    echo "# === DBKUI AUTOMATED CRON ===" >> "$TMP_CRON"
    echo "$CRON_STR $CRON_RUNNER >> \"PLACEHOLDER_CRON_LOG\" 2>&1" >> "$TMP_CRON"
    echo "# === END DBKUI ===" >> "$TMP_CRON"
    
    crontab "$TMP_CRON"; rm -f "$TMP_CRON"
    whiptail --msgbox "System Crontab sanitized and updated.\nSchedule: $SCHED\n\nCron Execution logs are securely routed to your Config Directory." 10 70
}

adhoc_wizard() {
    while true; do
        local TARGET_TYPE=$(whiptail --title "Ad-Hoc Backup Wizard" --cancel-button "Back" --menu "Select what you want to backup right now:" 15 60 3 \
            "1" "Entire Server (Guild)" \
            "2" "Specific Channel" \
            "3" "Direct Message" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && return
        [ -z "$TARGET_TYPE" ] && return
        
        local SELECTED_ID=""
        local SELECTED_NAME=""
        local ARGS=()
        
        if [ "$TARGET_TYPE" == "1" ]; then
            local opts=()
            while IFS='|' read -r id type pgid cat name; do
                if [[ "$id" =~ ^[0-9]+$ ]] && [ "$type" == "Guild" ]; then opts+=("$id" "${name:0:40}"); fi
            done < <(grep "|Guild|" "$ID_MAP")
            if [ ${#opts[@]} -eq 0 ]; then whiptail --msgbox "No Servers found in ledger." 8 40; continue; fi
            SELECTED_ID=$(whiptail --title "Ad-Hoc: Select Server" --menu "Choose a Server:" 22 75 14 "${opts[@]}" 3>&1 1>&2 2>&3)
            [ $? -ne 0 ] && continue
            ARGS+=("-g" "$SELECTED_ID")
            SELECTED_NAME="$(grep "^$SELECTED_ID|" "$ID_MAP" | cut -d'|' -f5)"
            
        elif [ "$TARGET_TYPE" == "2" ]; then
            local opts=()
            while IFS='|' read -r id type pgid cat name; do
                if [[ "$id" =~ ^[0-9]+$ ]] && [ "$type" == "Channel" ]; then 
                    local sname=$(grep "^$pgid|" "$ID_MAP" | cut -d'|' -f5 | cut -c1-15)
                    opts+=("$id" "[$sname] ${name:0:30}"); 
                fi
            done < <(grep "|Channel|" "$ID_MAP")
            if [ ${#opts[@]} -eq 0 ]; then whiptail --msgbox "No Channels found in ledger." 8 40; continue; fi
            SELECTED_ID=$(whiptail --title "Ad-Hoc: Select Channel" --menu "Choose a Channel:" 22 75 14 "${opts[@]}" 3>&1 1>&2 2>&3)
            [ $? -ne 0 ] && continue
            ARGS+=("-c" "$SELECTED_ID")
            SELECTED_NAME="$(grep "^$SELECTED_ID|" "$ID_MAP" | cut -d'|' -f5)"
            
        elif [ "$TARGET_TYPE" == "3" ]; then
            local opts=()
            while IFS='|' read -r id type pgid cat name; do
                if [[ "$id" =~ ^[0-9]+$ ]] && [ "$type" == "DM" ]; then opts+=("$id" "${name:0:40}"); fi
            done < <(grep "|DM|" "$ID_MAP")
            if [ ${#opts[@]} -eq 0 ]; then whiptail --msgbox "No DMs mapped yet. Run a Primer Harvest via the Setup menu." 8 60; continue; fi
            SELECTED_ID=$(whiptail --title "Ad-Hoc: Select DM" --menu "Choose a DM:" 22 75 14 "${opts[@]}" 3>&1 1>&2 2>&3)
            [ $? -ne 0 ] && continue
            ARGS+=("-c" "$SELECTED_ID")
            SELECTED_NAME="$(grep "^$SELECTED_ID|" "$ID_MAP" | cut -d'|' -f5)"
        fi
        
        # Format and Media Selection
        local FORMAT_CHOICE=$(whiptail --title "Ad-Hoc: Format" --radiolist "Select output format for $SELECTED_NAME:" 15 60 3 \
            "1" "Plain Text (Fastest)" ON \
            "2" "HTML Dark (Readable)" OFF \
            "3" "JSON (For data parsing)" OFF 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && continue
        
        if [ "$FORMAT_CHOICE" == "2" ]; then ARGS+=("--html"); elif [ "$FORMAT_CHOICE" == "3" ]; then ARGS+=("--json"); else ARGS+=("--text"); fi
        
        if whiptail --title "Ad-Hoc: Media" --yesno "Download media (images, videos, attachments) for this run?\n\nNote: This significantly increases backup time and disk usage." 10 60; then
            ARGS+=("--media")
        fi
        
        # Execute in foreground
        clear
        echo -e "${BLUE}========================================================${NC}"
        echo " LAUNCHING AD-HOC BACKUP: $SELECTED_NAME"
        echo -e "${BLUE}========================================================${NC}"
        sleep 1
        "$SCRIPT_DIR/dcordbk" "${ARGS[@]}"
        
        echo -e "\n>>> Ad-Hoc Backup Complete. Press ENTER to return to menu."
        read
        return
    done
}

reset_and_rescan() {
    if whiptail --title "WARNING" --yesno "This will wipe your current server/channel list and re-download your active matrix from Discord. Your saved backups will NOT be deleted.\n\nProceed?" 10 50; then
        clear
        echo ">>> Flushing internal ledger..."
        rm -f "$ID_MAP"
        rm -f "$CRON_TARGETS"
        echo ">>> Ledger flushed. Initiating Active Discovery..."
        sleep 1
        "$SCRIPT_DIR/dcordbk" -d
        echo ">>> Discovery Complete. Press ENTER to return to menu."
        read
    fi
}

while true; do
    CHOICE=$(whiptail --title "Mission Control" --cancel-button "Exit" --menu "Select action (ESC twice to quit):" 16 60 5 \
        "1" "Configure Automated Backups" \
        "2" "Write to Cron Schedule" \
        "3" "Run Ad-Hoc Backup Wizard" \
        "4" "Reset and Rescan Discord" \
        "5" "Exit" 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then clear; exit 0; fi
    
    case $CHOICE in
        1) menu_backup_options ;;
        2) write_to_cron ;;
        3) adhoc_wizard ;;
        4) reset_and_rescan ;;
        5|"") clear; exit 0 ;;
    esac
done
EOF

# ==============================================================================
# PATCH, PERMISSIONS, AND INITIALIZATION
# ==============================================================================
sed -i "s|PLACEHOLDER_PATH|$TARGET_ROOT|g" "$TARGET_BIN/dcordbk" "$TARGET_BIN/dbkui"
sed -i "s|PLACEHOLDER_IS_SYSTEM|$IS_SYSTEM|g" "$TARGET_BIN/dcordbk"

if [ "$IS_SYSTEM" == "true" ]; then
    sed -i "s|PLACEHOLDER_CRON_LOG|/var/log/dbk_cron.log|g" "$TARGET_BIN/dcordbk" "$TARGET_BIN/dbkui"
    sed -i "s|PLACEHOLDER_EXEC_LOG|/var/log/dbk_execution.log|g" "$TARGET_BIN/dcordbk"
else
    sed -i "s|PLACEHOLDER_CRON_LOG|$TARGET_ROOT/.conf/dbk_cron.log|g" "$TARGET_BIN/dcordbk" "$TARGET_BIN/dbkui"
    sed -i "s|PLACEHOLDER_EXEC_LOG|$TARGET_ROOT/.conf/dbk_execution.log|g" "$TARGET_BIN/dcordbk"
fi

chmod +x "$TARGET_BIN/dcordbk" "$TARGET_BIN/dbkworker.sh" "$TARGET_BIN/dbkui"

echo -e "${GREEN}>>> Files generated and executable.${NC}"
if [[ ":$PATH:" != *":$TARGET_BIN:"* ]]; then echo -e "${RED}WARNING: $TARGET_BIN is not in your \$PATH.${NC}"; fi

echo -e "\n${GREEN}Installation Complete. Type 'dbkui' to configure your Token and begin.${NC}"
