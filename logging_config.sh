#!/bin/bash

# Logging Configuration Environment Variables
# --------------------------------------------------------

# Filtering options
# Comma-separated list of strings to skip if they appear in log lines
export LOG_FILTER_SKIP="Debug,Trace,Processing shader,Unloading stale assets"
  
# Comma-separated list of strings to ONLY include if they appear (leave empty to include all non-skipped)
export LOG_FILTER_INCLUDE=""

# Color formatting rules
# Line rules format: "regex pattern:COLOR_NAME"
# Available colors: RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE
# Prefix with BOLD_ for bold colors (e.g., BOLD_RED)
  
# Default line rules (each rule is applied to the entire line if pattern matches)
export LOG_COLOR_LINE_RULES="(Shader|HDR|shader|WARNING|Unloading|Total:|UnloadTime|Camera|Null|null|NULL):WHITE,(Valheim l-.*|Load world:.*|isModded:.*|Am I Host\?|version|world):YELLOW,(Connections|ZDOS:|sent:|recv:|New connection|queue|connecting|Connecting|socket|Socket|RPC|Accepting connection|socket|msg|Connected|Got connection|handshake):CYAN,(New peer connected|<color=orange>.*</color>|ZDOID):GREEN,(ERROR:|Exception|HDSRDP|wrong password):BOLD_RED,(Added .* locations,|Loaded .* locations|Loading .* zdos|save|Save|backup):MAGENTA,(Console: ):BLUE"
  
# Default word rules (only the matching word/pattern is colored, not the entire line)
# NOTE the variables in the list must exist!
# varExp|\\$SERVER_NAME|\\$SERVER_PASS|\\$WORLD_NAME):BOLD_YELLOW,
export LOG_COLOR_WORD_RULES="((?:ZDOID from ([\\w\\s]+) :):BOLD_GREEN,(SteamID \\d{17}|client \\d{17}|socket \\d{17}):BOLD_CYAN"

# Timestamp formatting
# Format for timestamps (standard, iso8601, compact)
export LOG_TIMESTAMP_FORMAT="standard"

# Log formatting
# Format template (use %DATE%, %TIME%, %FILE%, %MSG% as placeholders)
export LOG_FORMAT_TEMPLATE="%DATE% %TIME% [%FILE%]: %MSG%"
  
# Custom cleanup patterns (comma-separated sed patterns)
# Default example: Strip Conan timestamp format [YYYY.MM.DD-HH.MM.SS:MMM]
export LOG_FORMAT_CLEANUP="s/\\[[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}-[0-9]{2}\\.[0-9]{2}\\.[0-9]{2}:[0-9]{3}\\]//"

# Log rotation settings
# Number of days before compressing logs
export LOG_ROTATION_DAYS_TO_GZIP=2
# Number of days before deleting compressed logs
export LOG_ROTATION_DAYS_TO_DELETE=4
