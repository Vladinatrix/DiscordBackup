# DCORDBK ARCHIVAL SUITE (v0.2.10)

DCORDBK is a highly resilient, POSIX-compliant automated archival suite designed to interface with `DiscordChatExporter.Cli`. It provides a hierarchical, interactive Text User Interface (TUI) to configure, schedule, and manage local backups of Discord Direct Messages, Guilds (Servers), and Categories.

Engineered with a focus on absolute data retention and portability, it is built to survive network drops, API limitations, and long-term OS migrations. **v0.2.10** introduces Strict Local Confinement, meaning all states, logs, and schedules operate entirely in user-space without requiring `sudo` privileges.

================================================================================
CORE FEATURES
================================================================================

- **Interactive TUI (dbkui):** A Midnight Commander-style terminal menu built entirely in native `whiptail`/`bash`. Configure entire servers, specific categories, or individual channels without touching a command line.
- **Dynamic Cron Pre-Sync:** Never manually update your server rules again. When executing scheduled backups, the suite silently queries Discord *first* to map any newly created channels, mathematically guaranteeing your "Entire Server" backups never miss a newly added chat room.
- **Strict Local Confinement:** Every execution log, cron log, token, and ledger map is strictly contained within your hidden `.conf/` directory. The suite features native 5MB log-rotation, keeping your system perfectly clean without touching `/var/log` or requiring root permissions.
- **Secure Token Ingestion:** Native, user-permission-locked (`chmod 600`) handling of your Discord Authorization Token to ensure zero-friction startups and seamless API bridging. 
- **Semantic File Naming:** Archive files are strictly formatted into human-readable outputs (`Server Name - Channel Name.html`), allowing you to navigate your archives without needing to decipher raw Discord IDs. 
- **Decoupled Ad-Hoc Runner:** Execute instant, on-demand backups directly from the UI without overriding or interfering with your automated `cron` schedules.

================================================================================
QUICK START & USAGE
================================================================================

1. Run the installer: `bash dcordbk-installer.bash` (Choose Option 1 for a User Install)
2. Launch Mission Control: Type `dbkui` in your terminal.
3. Paste your Discord Token when prompted. The suite will immediately and automatically map your accessible servers.
4. Select your backup targets and output formats (HTML, JSON, or Plain Text).
5. Select `Write to Cron Schedule` to establish your automated backup bridge. 

*Note: Discord limits token access to Direct Messages unless manually initialized. To populate the DM matrix in `dbkui`, select the Direct Messages menu to trigger a one-time "Primer Harvest".*

================================================================================
ARCHITECTURE & FILE STRUCTURE
================================================================================

The suite is entirely self-contained within your chosen installation target.

- `bin/dcordbk`: The Master Wrapper. Handles API polling, rootless log rotation, and execution dispatch.
- `bin/dbkworker.sh`: The Heavy Lifter. Executes the core C# binary, applies Semantic Naming templates, and handles `tar.xz` compression.
- `bin/dbkui`: The State Machine. Renders the interactive configuration matrix, token ingestion, and the isolated Ad-Hoc wizard.
- `Archive/.conf/dbk-cron-runner.sh`: (Auto-Generated). The bridge script read by `crontab` to execute the pre-sync and backup matrix.
- `Archive/.conf/id_map.txt`: The v3.0 Relational Ledger. A flat-file mapping of your Discord hierarchy.
- `Archive/.conf/cron_targets.txt`: Your saved configuration matrix database. 
- `Archive/.conf/.token`: Secure storage for your API bridge.
- `Archive/.conf/.tmp/`: A secure, temporary sandbox used during API parsing to prevent multi-user system snooping.

**Execution Logs:**
Execution and automated scheduling logs are securely maintained at:
- `Archive/.conf/dbk_execution.log`
- `Archive/.conf/dbk_cron.log`

--------------------------------------------------------------------------------
Engineered by GuppyGIRL, Hope Lockwood. Maintained by GuppyGIRL, Yui Kirigaya.
