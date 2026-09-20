DCORDBK ARCHIVAL SUITE (v1.3.2 - September 19, 2026)

DCORDBK is a highly resilient, POSIX-compliant automated archival suite designed to interface with DiscordChatExporter.Cli. It provides a hierarchical, interactive Text User Interface (TUI) to configure, schedule, and manage local backups of Discord Direct Messages, Guilds (Servers), and Categories.

Engineered with a focus on absolute data retention, storage protection, and network efficiency, it is built to survive network drops, API rate limits, and cross-filesystem storage bridge latency. Version 1.3.2 introduces DrvFs Pre-Flight Mount Guards, Local Staging Buffer Pipelines, Sorted Per-Server Cron Management, Global Default Schedules, Dedicated Folder Siloing, and Token-Safe Uninstallation.

================================================================================
CORE FEATURES
================================================================================

- Interactive TUI (dbkui): A terminal control center built in native whiptail/bash. Configure, schedule, and manage backups without editing script files manually.
- Sorted Per-Server Cron Management: Automatically scans your relational ledger (id_map.txt) and populates all servers in your account. Active [ENABLED] servers are sorted first alphabetically by name, followed by [DISABLED] servers alphabetically.
- Non-Destructive Edit Protection: Modifying schedule expressions or output formats preserves the server's current status. Cron jobs require an explicit admin toggle action to enable.
- Global Default Cron Settings: Define default backup schedules (preset to Every Sunday at 2:00 AM: 0 2 * * 0) and default flags (--json --media) across all unconfigured servers via default_cron.conf.
- DrvFs Pre-Flight Mount Guard: Verifies that your storage path (such as a network or cloud mount) is actively attached via findmnt before executing any download, preventing accidental writes to unmounted local storage.
- Local Staging & Multi-Threaded Compression: Scraped messages and media download into a fast local Linux staging buffer (/tmp/dcordbk_stage_$$) and compress using multi-core xz (-9e -T0) before streaming the finished archive to target storage in a single operation, bypassing 9p/DrvFs latency.
- Dedicated Folder Siloing: Backups are routed into dedicated directories per server (e.g., /path/to/discord_archive/Server_Alpha/). Direct Messages are strictly isolated into a separate /path/to/discord_archive/Direct_Messages/ vault.
- Token-Safe Uninstallation: Run ./dcordbk-installer.bash --uninstall to purge suite binaries and scheduled crons while preserving your authorization token (.token) for fast redeployment.
- Decoupled Ad-Hoc Runner: Execute instant, on-demand backups directly from dbkui without interfering with automated cron schedules.

================================================================================
QUICK START & USAGE
================================================================================

1. Run the installer: bash dcordbk-installer.bash
2. Choose installation type: Select Option 1 (User Install) or Option 2 (System Install via sudo).
3. Launch Mission Control: Type dbkui in your terminal.
4. Paste your Discord Token when prompted. The suite will automatically map your accessible servers into the relational ledger (id_map.txt).
5. Select Option 2 (Automated Server Cron Management) to configure global defaults or toggle individual server schedules.
6. Select Option 1 (Ad-Hoc Backup Wizard) to run instant on-demand backups anytime.

================================================================================
ARCHITECTURE & FILE STRUCTURE
================================================================================

The suite is self-contained within your chosen installation path (e.g., /usr/local/ or ~/):

- bin/dcordbk: The Master Wrapper. Enforces pre-flight mount validation, log rotation, and execution dispatch.
- bin/dbkworker.sh: The Backend Engine. Manages local ext4 staging, DiscordChatExporter execution, and multi-core xz compression.
- bin/dbkui: The TUI State Machine. Renders the interactive configuration matrix, token setup, ad-hoc wizard, and sorted cron management.
- bin/DiscordChatExporter.Cli: Native Python CLI engine and media downloader.
- Archive/.conf/id_map.txt: The v3.0 Relational Ledger. A flat-file mapping of your Discord hierarchy.
- Archive/.conf/cron_targets.txt: Saved per-server schedule matrix and status tracking file.
- Archive/.conf/default_cron.conf: Global default schedule and flag preferences.
- Archive/.conf/.token: Secure local storage for your API token.
- Archive/.conf/dbk_execution.log: Execution runtime log.
- Archive/.conf/dbk_cron.log: Cron job activity log.

--------------------------------------------------------------------------------
Version: v1.3.2 | Released: September 19, 2026
