DCORDBK ARCHIVAL SUITE (v0.2.5)

DCORDBK is a highly resilient, POSIX-compliant automated archival suite designed to interface with DiscordChatExporter.Cli. It provides a hierarchical, interactive Text User Interface (TUI) to configure, schedule, and manage local backups of Discord Direct Messages, Guilds (Servers), and Categories.

Engineered with a focus on absolute data retention and portability, it is built to survive network drops, API limitations, and long-term OS migrations without relying on external databases or complex rendering libraries.

================================================================================
CORE FEATURES
================================================================================

- Interactive TUI (dbkui): A Midnight Commander-style terminal menu built entirely in native whiptail/bash. Configure entire servers, specific categories, or individual channels without touching a command line.
- Network-Resilient Harvesting: Actively intercepts and parses output filenames on the fly. If the Discord API drops your connection (or you press Ctrl-C), the suite gracefully maps all data acquired prior to the crash before cleaning the staging area.
- Relational Ledger (v3.0): Dynamically queries the Discord API to build a local, flat-file relational database of your accessible environment (Guild -> Category -> Channel).
- Automated Cron Management: Translates your UI configuration matrix into a consolidated runner script and safely injects it into your system's crontab alongside native log rotation (/var/log/).
- Forum Support: Automatically injects thread-inclusion parameters to seamlessly back up Discord "Forum" channels without API errors.
- Maximum Compression: Archives are piped directly into tar and xz (Level 9) for an incredibly small, text-only storage footprint.

================================================================================
PREREQUISITES
================================================================================

Before installing DCORDBK, ensure the host system has the following dependencies:

1. DiscordChatExporter.Cli: The underlying C# engine. Must be installed globally.
   Path expected: /usr/local/bin/DiscordChatExporter.Cli
2. Whiptail: Required for the TUI. Standard on RHEL/CentOS.
   sudo dnf install newt (CentOS/RHEL)
   sudo apt install whiptail (Debian/Ubuntu)
3. Standard POSIX Tools: awk, grep, sed, tar, xz.

================================================================================
INSTALLATION
================================================================================

1. Make the installer executable:
   chmod +x installdbk.bash

2. Run the installer:
   ./installdbk.bash

Deployment Targets:
The interactive installer will prompt you for a deployment path:
- User Install (Recommended): Deploys binaries to ~/bin and archives to ~/Discord_Archive.
- System Install: Deploys globally to /usr/local/bin and /usr/local/discord_archive (Requires sudo).
- Custom: Allows arbitrary pathing (Must use absolute paths).

================================================================================
USAGE (THE INTERFACE)
================================================================================

The primary method of interaction is the Mission Control TUI.

Simply run: dbkui

The Mission Control Menu:
1. Configure Backup Options: Navigate your mapped Discord environment. Select DMs, Entire Servers, or drill down into specific Categories to explicitly toggle Backup (Y/N), Text (Y/N), and Media (Y/N) configurations.
2. Write to Cron: Compiles your saved configuration matrix into an execution runner and schedules it (Daily, Weekly, or Monthly) into the system crontab.
3. Run Active Backup Now: Immediately executes the compiled configuration matrix in the foreground, streaming the native Spectre.Console progress bars to your terminal.

================================================================================
ADVANCED / CLI USAGE (dcordbk)
================================================================================

While dbkui handles configuration, the underlying master wrapper (dcordbk) can be invoked manually for immediate, one-off tasks outside the scheduled matrix.

Usage: dcordbk [TARGET] [OPTIONS]

TARGETS:
  -A, --all            Backup EVERYTHING (All Servers + DMs)
  -D, --dms            Backup DMs only
  -c <ID>              Backup specific Channel ID
  -g <ID>              Backup specific Guild ID

UTILITY:
  -d, --discover       Force an API query to rebuild the local ID ledger.
  -l, --list           List all mapped IDs from the local ledger.

The "Invisible DM" Limitation:
The Discord API strictly prohibits active polling of Direct Messages without an associated Server ID. Consequently, DMs do not automatically appear in the ledger. 

To populate the DM matrix in dbkui, you must run a "Primer Harvest". The TUI will automatically detect if your DM ledger is empty and offer to run a quick background sync to capture your contact list.

================================================================================
ARCHITECTURE & FILE STRUCTURE
================================================================================

The suite is entirely self-contained within your chosen installation target.

- bin/dcordbk: The Master Wrapper. Handles API polling, log rotation escalation, and execution dispatch.
- bin/dbkworker.sh: The Heavy Lifter. Executes the C# binary, harvests network-resilient telemetry, and handles tar.xz compression.
- bin/dbkui: The State Machine. Renders the interactive configuration matrix and handles deduplication logic.
- bin/dbk-cron-runner.sh: (Auto-Generated). The bridge script read by crontab to execute your configured matrix.
- Archive/.conf/id_map.txt: The v3.0 Relational Ledger. A flat-file mapping of your Discord hierarchy.
- Archive/.conf/cron_targets.txt: Your saved configuration matrix database. 

Log Files:
Execution logs are safely rotated monthly via /etc/logrotate.d/dcordbk and stored at:
- /var/log/dbk_monthly.log
- /var/log/dbk_weekly.log

--------------------------------------------------------------------------------
Engineered by Hope Lockwood. Maintained by Yui Kirigaya.
