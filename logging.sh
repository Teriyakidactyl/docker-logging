#!/bin/bash
# --------------------------------------------------------------------------
# Modular logging functions with ENV config
# --------------------------------------------------------------------------

# Load ENV config if available
CONFIG_FILE="$(dirname "${BASH_SOURCE[0]}")/logging_config.sh"
if [ -f "$CONFIG_FILE" ]; then
    # Source the environment variables from the config file
    source "$CONFIG_FILE"
else
    # Display warning about missing config
    echo "Warning: Logging config file not found at $CONFIG_FILE"
fi

# Load app-specific config if available
APP_CONFIG_FILE="$(dirname "${BASH_SOURCE[0]}")/logging_app_config.sh"
if [ -f "$APP_CONFIG_FILE" ]; then
    # Store original values before loading app config
    ORIG_LOG_FILTER_SKIP="$LOG_FILTER_SKIP"
    ORIG_LOG_FILTER_INCLUDE="$LOG_FILTER_INCLUDE"
    ORIG_LOG_COLOR_LINE_RULES="$LOG_COLOR_LINE_RULES"
    ORIG_LOG_COLOR_WORD_RULES="$LOG_COLOR_WORD_RULES"
    
    # Source the app-specific config
    source "$APP_CONFIG_FILE"
    
    # Process comma-separated extensions marked with + prefix
    for var in LOG_FILTER_SKIP LOG_FILTER_INCLUDE LOG_COLOR_LINE_RULES LOG_COLOR_WORD_RULES; do
        if [[ "${!var}" == +* ]]; then
            # Remove the + and get the original value
            addition="${!var:1}"
            orig_val=$(eval echo \$ORIG_$var)
            
            if [ -z "$orig_val" ]; then
                # If original wasn't set, just use the new values
                export $var="$addition"
            else
                # Combine values
                export $var="$orig_val,$addition"
            fi
        fi
    done
fi

# --------------------------------------------------------------------------
# Core Logging Functions
# --------------------------------------------------------------------------

timestamp() {
    local line="$1"
    local current_date=$(date "+%m/%d/%Y")
    local current_time=$(date "+%H:%M:%S")
    local formatted_date=""
    local formatted_time=""
    local output_line="$line"
    
    # Extract date if present
    if [[ $line =~ ([0-9]{2}/[0-9]{2}/[0-9]{4}) ]]; then
        formatted_date="${BASH_REMATCH[1]}"
        output_line="${line#*${BASH_REMATCH[0]}}"
    else
        formatted_date="$current_date"
    fi

    # Extract time if present, discard trailing ':'
    if [[ $line =~ ([0-9]{2}:[0-9]{2}:[0-9]{2})(: )? ]]; then
        formatted_time="${BASH_REMATCH[1]}"
        # If we already removed the date portion, check if time is still in the line
        if [[ "$output_line" == *"${BASH_REMATCH[0]}"* ]]; then
            output_line="${output_line#*${BASH_REMATCH[0]}}"
        fi
    else
        formatted_time="$current_time"
    fi
    
    # Clean up any resulting double spaces - using bash string operations instead of sed
    # Replace double spaces with single space
    while [[ "$output_line" == *"  "* ]]; do
        output_line="${output_line//  / }"
    done
    
    # Remove leading and trailing spaces
    output_line="${output_line## }"
    output_line="${output_line%% }"
    
    # Return both timestamp components and the modified line
    echo "${formatted_date}|${formatted_time}|${output_line}"
}

filter() {
    local line="$1"
    
    # Skip empty lines
    [[ -z "$line" ]] && return 1
    
    # Skip lines with LOG_FILTER_SKIP matches from config
    if [[ -n "$LOG_FILTER_SKIP" ]]; then
        IFS=',' read -ra FILTER_ITEMS <<< "$LOG_FILTER_SKIP"
        for item in "${FILTER_ITEMS[@]}"; do
            [[ "$line" == *"$item"* ]] && return 1
        done
    fi
    
    # Only include lines with LOG_FILTER_INCLUDE matches (if specified)
    if [[ -n "$LOG_FILTER_INCLUDE" ]]; then
        local match_found=0
        IFS=',' read -ra INCLUDE_ITEMS <<< "$LOG_FILTER_INCLUDE"
        for item in "${INCLUDE_ITEMS[@]}"; do
            if [[ "$line" == *"$item"* ]]; then
                match_found=1
                break
            fi
        done
        [[ $match_found -eq 0 ]] && return 1
    fi
    
    return 0
}

colorize() {
    local line="$1"
    local colored=false

    # Define tput color variables
    local RED=$(tput setaf 1)
    local GREEN=$(tput setaf 2)
    local YELLOW=$(tput setaf 3)
    local BLUE=$(tput setaf 4)
    local MAGENTA=$(tput setaf 5)
    local CYAN=$(tput setaf 6)
    local WHITE=$(tput setaf 7)
    local BOLD=$(tput bold)
    local NC=$(tput sgr0) # Reset all attributes

    # Define color rules from config if available
    local -A line_rules=()
    local -A word_rules=()
    
    # Load rules from config - no defaults in code
    if [[ -n "$LOG_COLOR_LINE_RULES" ]]; then
        # Parse the comma-separated config format "pattern1:color1,pattern2:color2"
        IFS=',' read -ra RULE_PAIRS <<< "$LOG_COLOR_LINE_RULES"
        for pair in "${RULE_PAIRS[@]}"; do
            local pattern="${pair%%:*}"
            local color="${pair##*:}"
            
            # Convert color name to variable
            case "$color" in
                "RED") color_var="$RED" ;;
                "GREEN") color_var="$GREEN" ;;
                "YELLOW") color_var="$YELLOW" ;;
                "BLUE") color_var="$BLUE" ;;
                "MAGENTA") color_var="$MAGENTA" ;;
                "CYAN") color_var="$CYAN" ;;
                "WHITE") color_var="$WHITE" ;;
                "BOLD_RED") color_var="${BOLD}${RED}" ;;
                "BOLD_GREEN") color_var="${BOLD}${GREEN}" ;;
                "BOLD_YELLOW") color_var="${BOLD}${YELLOW}" ;;
                "BOLD_BLUE") color_var="${BOLD}${BLUE}" ;;
                "BOLD_MAGENTA") color_var="${BOLD}${MAGENTA}" ;;
                "BOLD_CYAN") color_var="${BOLD}${CYAN}" ;;
                "BOLD_WHITE") color_var="${BOLD}${WHITE}" ;;
                *) color_var="$WHITE" ;;
            esac
            
            line_rules["$pattern"]="$color_var"
        done
    fi
    
    if [[ -n "$LOG_COLOR_WORD_RULES" ]]; then
        # Parse word rules similar to line rules
        IFS=',' read -ra RULE_PAIRS <<< "$LOG_COLOR_WORD_RULES"
        for pair in "${RULE_PAIRS[@]}"; do
            local pattern="${pair%%:*}"
            local color="${pair##*:}"
            
            # Convert color name to variable
            case "$color" in
                "RED") color_var="$RED" ;;
                "GREEN") color_var="$GREEN" ;;
                "YELLOW") color_var="$YELLOW" ;;
                "BLUE") color_var="$BLUE" ;;
                "MAGENTA") color_var="$MAGENTA" ;;
                "CYAN") color_var="$CYAN" ;;
                "WHITE") color_var="$WHITE" ;;
                "BOLD_RED") color_var="${BOLD}${RED}" ;;
                "BOLD_GREEN") color_var="${BOLD}${GREEN}" ;;
                "BOLD_YELLOW") color_var="${BOLD}${YELLOW}" ;;
                "BOLD_BLUE") color_var="${BOLD}${BLUE}" ;;
                "BOLD_MAGENTA") color_var="${BOLD}${MAGENTA}" ;;
                "BOLD_CYAN") color_var="${BOLD}${CYAN}" ;;
                "BOLD_WHITE") color_var="${BOLD}${WHITE}" ;;
                *) color_var="$WHITE" ;;
            esac
            
            word_rules["$pattern"]="$color_var"
        done
    fi

    # Format whole line on any match
    for regex in "${!line_rules[@]}"; do
        if [[ $line =~ $regex ]]; then
            line=$(echo "${line_rules[$regex]}${line}${NC}")
        fi
    done

    # Only format match
    for regex in "${!word_rules[@]}"; do
        while [[ $line =~ $regex ]]; do
            matched_part="${BASH_REMATCH[0]}"
            styled_part="${word_rules[$regex]}${matched_part}${NC}"
            line="${line/${matched_part}/${styled_part}}"
        done
    done

    echo "$line"
}

# --------------------------------------------------------------------------
# Main Logging Functions
# --------------------------------------------------------------------------

log() {
    local caller_function="${FUNCNAME[1]}"
    local line="$1"
    local filename="${2:-$caller_function}"

    # Trim all whitespace characters, including newlines - using bash string operations instead of sed
    # Remove carriage returns and newlines
    line="${line//[$'\r\n']/}"
    
    # Trim leading and trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    
    # Apply custom cleanup patterns if defined in config
    if [[ -n "$LOG_FORMAT_CLEANUP" ]]; then
        IFS=',' read -ra CLEANUP_PATTERNS <<< "$LOG_FORMAT_CLEANUP"
        for pattern in "${CLEANUP_PATTERNS[@]}"; do
            # Be extra careful with sed - use a wrapper function
            line=$(safe_sed "$line" "$pattern")
        done
    else
        # Default cleanup - Strip the conan time stamp, ex. [2024.07.13-19.42.42:171]
        # Using pattern matching instead of sed
        if [[ "$line" =~ \[[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[0-9]{2}\.[0-9]{2}\.[0-9]{2}:[0-9]{3}\] ]]; then
            matched="${BASH_REMATCH[0]}"
            line="${line//$matched/}"
        fi
    fi
    
    # Skip empty lines
    [[ -z "$line" ]] && return
    
    # Apply filtering
    filter "$line" || return
    
    # Process timestamps
    local ts_result=$(timestamp "$line")
    local formatted_date=$(echo "$ts_result" | cut -d'|' -f1)
    local formatted_time=$(echo "$ts_result" | cut -d'|' -f2)
    line=$(echo "$ts_result" | cut -d'|' -f3-)
    
    # Construct the formatted line according to format template if available
    if [[ -n "$LOG_FORMAT_TEMPLATE" ]]; then
        # Replace placeholders using parameter expansion instead of sed
        local formatted_line="$LOG_FORMAT_TEMPLATE"
        formatted_line="${formatted_line//%DATE%/$formatted_date}"
        formatted_line="${formatted_line//%TIME%/$formatted_time}"
        formatted_line="${formatted_line//%FILE%/$filename}"
        formatted_line="${formatted_line//%MSG%/$line}"
    else
        # Use default format
        local formatted_line="${formatted_date} ${formatted_time} [${filename}]: ${line}"
    fi
    
    # Apply colorization
    local colored_line=$(colorize "$formatted_line")

    echo -e "$colored_line"
}

# A safe wrapper for sed to handle potential errors
safe_sed() {
    local input="$1"
    local pattern="$2"
    
    # Try to use sed, but catch errors
    local result
    result=$(echo "$input" | sed -E "$pattern" 2>/dev/null)
    
    # If sed fails, return the original input
    if [ $? -ne 0 ]; then
        echo "$input"
    else
        echo "$result"
    fi
}

log_tails() {
    # Create a new process group for all tails
    set -m  # Enable job control
    
    # Define the log files to monitor
    local LOG_FILES=($(find "$LOGS" -type f \( -name "*.log" -o -name "*log.txt" \)))

    # Tail each log file in the background
    for file in "${LOG_FILES[@]}"; do
        if [ -f "$file" ] && [ -r "$file" ]; then
            # Start tail in background
            tail -f "$file" | while IFS= read -r line; do
                log "$line" "$(basename "$file")"
            done &
        fi
    done
    
    # Store the process group ID instead of individual PIDs
    TAIL_PGID=$!
}

log_stdout() {
    local caller_function="${FUNCNAME[1]}"
    local filename="${1:-$caller_function}"
    while IFS= read -r line; do
        log "$line" "$filename"
    done
}

log_clean() {
    log "Starting log cleanup process..."

    # Define the number of days for gzip and deletion
    local days_to_gzip=${LOG_ROTATION_DAYS_TO_GZIP:-2}
    local days_to_delete=${LOG_ROTATION_DAYS_TO_DELETE:-4}

    # Gzip logs older than days_to_gzip
    find "$LOGS" -name "*.log" -type f -mtime +$days_to_gzip ! -name "*.gz" -exec gzip {} \;

    # Delete gzipped logs older than days_to_delete
    find "$LOGS" -name "*.gz" -mtime +$days_to_delete -delete

    log "Log cleanup process completed"
}
