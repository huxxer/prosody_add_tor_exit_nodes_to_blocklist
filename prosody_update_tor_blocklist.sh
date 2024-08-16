#!/bin/bash

# Creator: Huxx
# Date: 16.08.2024
#
# https://jabbers.one


################
#### README ####
################

# This script adds IPs of tor exit nodes to registration_blocklist to prevent the registration of accounts via tor.
# The prosody module module_register_limits must be activated and the option register_blocklist { } must be present in the prosody config.
# https://prosody.im/doc/modules/mod_register_limits
#
# After executing the script reload the modules with mod_reload_modules or restart the prosody server.
# https://modules.prosody.im/mod_reload_modules
#
# The list of https://www.dan.me.uk/torlist/?exit can be fetched every 30 minutes. Else the website owner may block your server.

#################
#### LICENSE ####
#################

# MIT License
#
# Copyright (c) 2024 Huxx
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


################
#### CONFIG ####
################

#URL tor exit nodes list
tor_exit_nodes="https://www.dan.me.uk/torlist/?exit"

#Path to prosody config
prosody_cfg="/etc/prosody/prosody.cfg.lua"

# Set to true or false to enable/disable logging
log_enable=true

# Path to log file
log_file="/var/log/prosody_update_tor_blocklist.log"

# Timestamp format for logs
log_timestamp_format="%d-%m-%Y %H:%M:%S"

#Prosody user that have ownership on prosody config
prosody_user="prosody"

#Prosody group that have ownership on prosody config
prosody_group="prosody"

# Set to true or false to enable/disable custom blocks. The entries of custom_blocks will be added at the beginning of registration_blocklist.
custom_blocks_enable=true

# Add custom IPs to the register blocklist. One IP per line. Double quote the IP and add a comma at the end of each line.
custom_blocks=$(cat <<EOF
"54.37.140.42",
EOF
)

#Dont set both variables prosody_restart and prosody_reload to true. Set only one of each to true.
# Set to true to restart the server if the script is successful.
prosody_restart=false

#Set to true to reload the server if the script is successful. Remember that the module mod_reload_modules must be activated and configured.
prosody_reload=true

############################################
#### Please do not edit after this line ####
############################################


# Function to log messages with a timestamp
log_message() {
    local message="$1"
    local timestamp=$(date +"$log_timestamp_format")
    if [ "$log_enable" = true ]; then
        echo "$timestamp - $message" | tee -a "$log_file"
    else
        echo "$timestamp - $message"
    fi
}

# Ensure the log file exists if logging is enabled
if [ "$log_enable" = true ]; then
    if [ ! -f "$log_file" ]; then
        touch "$log_file"
    fi
fi

# Function to check the format of custom blocks
check_custom_blocks_format() {
    while IFS= read -r line; do
        if [[ ! "$line" =~ ^\".*\",$ ]]; then
            log_message "Please check custom_blocks variable for double quote and comma at the end of each line"
            exit 1
        fi
    done <<< "$custom_blocks"
}

# Check the format of custom blocks and ensure it does not contain the default placeholder
if [ "$custom_blocks_enable" = true ]; then
    check_custom_blocks_format
    if grep -q '"1.2.3.4",' <<< "$custom_blocks"; then
        log_message "Please update custom_blocks variable to contain actual IP addresses and not IP 1.2.3.4"
        exit 1
    fi
fi

# Download the content to a temporary file
temp_file=$(mktemp)
response=$(curl -s "$tor_exit_nodes")
echo "$response" > "$temp_file"

# Check if the response contains the rate limit message
if echo "$response" | grep -q "Umm... You can only fetch the data every 30 minutes - sorry."; then
    log_message "Umm... You can only fetch the tor exit nodes data every 30 minutes - sorry"
    # Clean up the temporary file
    rm "$temp_file"
    exit 1
fi

# Format the content of the downloaded temp file with each line in double quotes and ending with a comma
replacement=$(awk '{print "\"" $0 "\","}' "$temp_file" | sed '$ s/,$//')

# Conditionally combine custom blocks with the formatted replacement content
if [ "$custom_blocks_enable" = true ]; then
    replacement_with_custom="$custom_blocks"$'\n'"$replacement"
else
    replacement_with_custom="$replacement"
fi

# Check if registration_blocklist = { } exists in the prosody configuration file
if grep -q 'registration_blocklist = {' "$prosody_cfg"; then
    # Use awk to replace the content between registration_blocklist = { } and retain the closing brace
    awk -v replacement="$replacement_with_custom" '
    BEGIN { inside_block=0 }
    /registration_blocklist = \{/ { print; print replacement; inside_block=1; next }
    /\}/ { if (inside_block) { print; inside_block=0; next } }
    { if (!inside_block) print }
    ' "$prosody_cfg" > temp.txt && mv temp.txt "$prosody_cfg"

    # Count the entries in registration_blocklist
    count=$(awk '/registration_blocklist = \{/{flag=1; next} /}/{flag=0} flag' "$prosody_cfg" | grep -c '.*')
    log_message "Updated registration_blocklist with $count entries."

    # Change ownership of the prosody configuration file
    chown "$prosody_user":"$prosody_group" "$prosody_cfg"

    # Restart or reload prosody service if configured
    if [ "$prosody_restart" = true ] && [ "$prosody_reload" = true ]; then
        log_message "Please change prosody_restart or prosody_reload to false. Only one solution is possible."
    elif [ "$prosody_restart" = true ]; then
        log_message "Restarting prosody service."
        sudo service prosody restart
    elif [ "$prosody_reload" = true ]; then
        log_message "Reloading prosody service."
        sudo service prosody reload
    fi

    # Clean up the temporary file
    rm "$temp_file"
else
    log_message "Please add registration_blocklist { } to your prosody config"
    # Clean up the temporary file
    rm "$temp_file"
    exit 1
fi
