#!/bin/bash

# ==============================================================================
# Container Base Script
# ==============================================================================
# 
# This script serves as the foundation for container initialization and monitoring.
# It sources configuration files, manages system logging, configures cron jobs,
# launches and monitors the main application process.
#
# The script is designed to be executed by tini as the primary entrypoint for
# various container types, maintaining a consistent initialization pattern
# while allowing for customization through hook directories.
#
# Functions:
#   main - Primary execution flow, launches and monitors application process
#   uptime - Calculates and formats container uptime
#   run_cron_hooks - Executes periodic tasks based on schedule
#   initialize_cron - Sets up cron tracking variables
#   auto_source_directory - Sources all scripts in a directory in numerical order
#   run_hooks - Executes hook scripts in a specified directory
#   shutdown - Handles graceful container termination
#
# Environment Variables:
#   APP_COMMAND - Command to execute as the main application process
#   APP_ARGS - Arguments to pass to the main application process
#   APP_COMMAND_PREFIX - Prefix for the application command
#   APP_FILES - Directory containing application files
#   APP_EXE - Executable filename for the application
#   APP_NAME - Name of the application for logging purposes
#   LOG_UPTIME - Whether to log uptime periodically (default: true)
#   CRON_DAILY_HOUR - Hour of day to run daily tasks (default: 03)
#   CRON_WEEKLY_DAY - Day of week to run weekly tasks (default: 0/Sunday)
#   CRON_WEEKLY_HOUR - Hour of day to run weekly tasks (default: 04)
#   CRON_MONTHLY_DAY - Day of month to run monthly tasks (default: 01)
#   CRON_MONTHLY_HOUR - Hour of day to run monthly tasks (default: 05)
#   SCRIPTS - Base directory for scripts
#   LOGS - Directory for log files
#
# Dependencies:
#   - tini (as the init process)
#   - logging.sh from container directory
#   - Hook directories (optional): 
#     - /hooks/startup
#     - /hooks/hourly
#     - /hooks/daily
#     - /hooks/weekly
#     - /hooks/monthly
#     - /hooks/loop
#     - /hooks/pre-update
#     - /hooks/post-update
#     - /hooks/shutdown
#

# tini → up.sh → $APP_COMMAND
# NOTE presumes this repo is cloned to $SCRIPTS/container

set -euo pipefail

# Source required files
source /etc/environment
source $SCRIPTS/container/logging.sh

# Set container start time if not already set
CONTAINER_START_TIME=${CONTAINER_START_TIME:-$(date -u +%s)}

# Main --------------------------------------------------------------------------------------
main() {
    
    initialize_cron
    log_clean
    run_hooks "pre-startup" 

    # Check if APP_ARGS exists & Assemble APP_COMMAND
    if [ -n "$APP_ARGS" ]; then
        # Check if unexpanded variables are present by looking for $ character
        if [[ "$APP_ARGS" == *\$* ]]; then
            log "Unexpanded variables found in APP_ARGS - expanding now" "startup_script.sh"
            eval "APP_ARGS=\"$APP_ARGS\""
            export APP_ARGS
            log "APP_ARGS expanded successfully" "startup_script.sh"
            log "DEBUG: APP_ARGS=$APP_ARGS" "startup_script.sh"
        else
            log "APP_ARGS already expanded, continuing" "startup_script.sh"
        fi
        APP_COMMAND="$APP_COMMAND_PREFIX $APP_FILES/$APP_EXE $APP_ARGS"
    else
        log "WARNING: APP_ARGS not defined" "startup_script.sh"
        APP_COMMAND="$APP_COMMAND_PREFIX $APP_FILES/$APP_EXE"
    fi

    # Check for startup hook and override if present
    if [ -d "$HOOK_DIRECTORIES/startup" ] && [ "$(ls -A "$HOOK_DIRECTORIES/startup")" ]; then
        run_hooks "startup" 
        # TODO APP_PID needs to get captured in override
        # TODO >> $LOGS/$APP_EXE.log 2>&1 & needs to be in overide
        # TODO $APP_COMMAND could be overwritten with a script path? and the call could remain the same
    fi
    
    # Launch the main application process
    log "--------------------------------" "up.sh"
    log "" "up.sh"
    log "Launching application: $APP_NAME" "up.sh"
    { echo "$APP_COMMAND" | sed 's/ -/\n    -/g' | sed 's/ --/\n    --/g'; } | log_stdout "up.sh"
    log "--------------------------------" "up.sh"
    
    # Run the application in the background and capture its PID
    $APP_COMMAND >> $LOGS/$APP_EXE.log 2>&1 &
    APP_PID=$!
        
    # Verify the process started successfully
    if ! kill -0 $APP_PID > /dev/null 2>&1; then
        log "ERROR - Failed to start $APP_COMMAND"
        exit 1
    fi
    
    # Call log_tails function which tails all logs in $LOGS directory
    log_tails
    
    # Infinite loop while APP_PID is running
    while kill -0 $APP_PID > /dev/null 2>&1; do
        current_minute=$(date '+%M')

        # Remove leading zeros safely by using parameter expansion instead of sed
        current_minute=${current_minute#0}
        
        # Run scheduled cron hooks
        run_cron_hooks  
       
        # Sleep & wait (to maintain signal awareness)
        sleep 60 & 
        wait $!
    done
    
    log "ERROR - $APP_COMMAND @PID $APP_PID appears to have died! $(uptime)"
    exit 1  # Exit with error code to indicate abnormal termination
}

# Calculate and format container uptime
uptime() {
    local now=$(date -u +%s)    
    local uptime_seconds=$(( now - CONTAINER_START_TIME ))
    local days=$(( uptime_seconds / 86400 ))
    local hours=$(( (uptime_seconds % 86400) / 3600 ))
    local minutes=$(( (uptime_seconds % 3600) / 60 ))
    
    # Print uptime in a readable format
    echo "Container Uptime: ${days}d ${hours}h ${minutes}m"
}

# Execute scripts in a directory in numerical order
auto_source_directory() {
    local dir=$1
    
    if [ ! -d "$dir" ]; then
        log "Directory $dir does not exist, skipping" "hooks"
        return 0
    fi
    
    log "Auto-sourcing scripts in $dir" "hooks"
    
    # Find all executable files, sort them numerically
    local files=($(find "$dir" -type f -executable | sort))
    
    if [ ${#files[@]} -eq 0 ]; then
        log "No executable files found in $dir" "hooks"
        return 0
    fi
    
    # Source each file
    for file in "${files[@]}"; do
        local filename=$(basename "$file")
        log "Sourcing $filename" "hooks"
        
        # Source the file and capture any errors
        if ! source "$file"; then
            log "ERROR sourcing $filename" "hooks"
        fi
    done
    
    log "Completed auto-sourcing for $dir" "hooks"
}

# Run hook scripts in a specific directory
run_hooks() {
    local hook_type=$1
    local hook_dir="$HOOK_DIRECTORIES/$hook_type"
    
    if [ ! -d "$hook_dir" ]; then
        log "Hook directory $hook_dir does not exist, skipping" "hooks"
        return 0
    fi
    
    log "Running $hook_type hooks" "hooks"
    
    # Find all executable files, sort them numerically
    local files=($(find "$hook_dir" -type f -executable | sort))
    
    if [ ${#files[@]} -eq 0 ]; then
        log "No executable $hook_type hooks found" "hooks"
        return 0
    fi
    
    # Source each hook instead of executing it
    for hook in "${files[@]}"; do
        local hook_name=$(basename "$hook")
        log "Sourcing $hook_name" "hooks"
        
        # Source the hook in the current shell environment
        if ! source "$hook"; then
            log "ERROR sourcing $hook_name hook" "hooks"
        fi
    done
    
    log "Completed $hook_type hooks" "hooks"
}

# Run cron hooks based on schedule
run_cron_hooks() {
    # Get current time components using parameter expansion instead of sed
    local current_minute=$(date '+%M')
    current_minute=${current_minute#0}  # Remove leading zero safely
    
    local current_hour=$(date '+%H')
    local current_day=$(date '+%d')
    local current_week=$(date '+%U')  # Week number
    local current_month=$(date '+%m')
    
    # Check for and run hourly hooks
    if [ "$current_hour" != "$LAST_HOURLY_RUN" ]; then
        log "Running hourly hooks at hour $current_hour" "cron"
        run_hooks "hourly"
        LAST_HOURLY_RUN=$current_hour
    fi
    
    # Run daily hooks at the configured hour (default: 3 AM)
    local daily_hour=${CRON_DAILY_HOUR:-03}
    if [ "$current_hour" = "$daily_hour" ] && [ "$current_day" != "$LAST_DAILY_RUN" ]; then
        log "Running daily hooks (day $current_day)" "cron"
        run_hooks "daily"
        LAST_DAILY_RUN=$current_day  
    fi
    
    # Run weekly hooks (on configured day at configured hour, default: Sunday at 4 AM)
    local weekly_day=${CRON_WEEKLY_DAY:-0}  # 0 = Sunday
    local weekly_hour=${CRON_WEEKLY_HOUR:-04}
    if [ "$(date '+%w')" = "$weekly_day" ] && [ "$current_hour" = "$weekly_hour" ] && [ "$current_week" != "$LAST_WEEKLY_RUN" ]; then
        log "Running weekly hooks (week $current_week)" "cron"
        run_hooks "weekly"
        LAST_WEEKLY_RUN=$current_week
    fi
    
    # Run monthly hooks (on the configured day at configured hour, default: 1st at 5 AM)
    local monthly_day=${CRON_MONTHLY_DAY:-01}
    local monthly_hour=${CRON_MONTHLY_HOUR:-05}
    if [ "$(date '+%d')" = "$monthly_day" ] && [ "$current_hour" = "$monthly_hour" ] && [ "$current_month" != "$LAST_MONTHLY_RUN" ]; then
        log "Running monthly hooks (month $current_month)" "cron"
        run_hooks "monthly"
        LAST_MONTHLY_RUN=$current_month
    fi
    
    # Log uptime every 10 minutes if enabled
    if [ "${LOG_UPTIME:-true}" = "true" ] && (( current_minute % 10 == 0 )); then
        log "$(uptime)" "cron"
    fi
}

# Initialize cron system
initialize_cron() {
    # Initialize global variables to track last run times
    LAST_HOURLY_RUN=$(date +%H)
    LAST_DAILY_RUN=$(date +%d)
    LAST_WEEKLY_RUN=$(date +%U)  # Week number
    LAST_MONTHLY_RUN=$(date +%m)
    
    log "Cron system initialized" "cron"
}

# Graceful shutdown function for signals forwarded by Tini
shutdown() {
    log "Performing graceful shutdown..." && sync
    
    # Run shutdown hooks if they exist
    if [ -d "$HOOK_DIRECTORIES/shutdown" ]; then
        log "Running shutdown hooks..." && sync
        run_hooks "shutdown"
    fi
    
    # Stop tail processes
    if [ -n "$TAIL_PGID" ]; then
        log "Stopping tail processes..." && sync
        kill -TERM -$TAIL_PGID 2>/dev/null || true
    fi
    
    # Stop main application process if it's running
    if [ -n "$APP_PID" ] && kill -0 $APP_PID > /dev/null 2>&1; then
        log "Stopping application process (PID: $APP_PID)..." && sync
        kill -TERM $APP_PID 2>/dev/null
        
        # Wait for the process to terminate, with a timeout
        local total_timeout=9  # Docker typically gives 10 seconds
        local kill_threshold=$((total_timeout * 2 / 3))  # Send SIGKILL after ~2/3 of the timeout
        
        for ((i=0; i<total_timeout; i++)); do
            if ! kill -0 $APP_PID 2>/dev/null; then
                log "Application process terminated gracefully" && sync
                break
            fi
            sleep 1
            
            # If we've waited beyond our threshold, try SIGKILL as last resort
            if [ $i -eq $kill_threshold ]; then
                log "Application not responding to SIGTERM, sending SIGKILL..." && sync
                kill -KILL $APP_PID 2>/dev/null || true
            fi
        done
        
        # Add a warning if process still running after our timeout
        if kill -0 $APP_PID 2>/dev/null; then
            log "WARNING: Application still running - Docker may force termination" && sync
        fi
    fi
    
    log "Cleanup complete. Exiting." && sync
    exit 0
}

# Setup signal handlers - Tini will forward these signals to our process
trap 'log "Received signal: $?" && shutdown' SIGTERM SIGINT SIGQUIT EXIT

# Start the main function
main
