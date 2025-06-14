#!/bin/bash
# Cryptovik "alert_solana_bot.sh" Script
# github link here
# Stand with Ukraine!
# If you want - Donate to script author



# Declaring associative arrays
declare -A validators_clusters
declare -A validators_names
declare -A validators_enabled
declare -A validators_delinquent_start
declare -A validators_alert_count
declare -A last_alert_time  # Array for storing the time of the last notification

# filling arrays

validators_clusters["IDENTITY1"]="-um"
validators_names["IDENTITY1"]="Name_for_IDENTITY1"
validators_enabled["IDENTITY1"]=1

validators_clusters["IDENTITY2"]="-um"
validators_names["IDENTITY2"]="Name_for_IDENTITY2"
validators_enabled["IDENTITY2"]=1

validators_clusters["IDENTITY3"]="-um"
validators_names["IDENTITY3"]="Name_for_IDENTITY3"
validators_enabled["IDENTITY3"]=1


# 
# validators_clusters["TESTNET_IDENTITY1"]="-ut"
# validators_names["TESTNET_IDENTITY1"]="Name_for_TESTNET_IDENTITY1"
# validators_enabled["TESTNET_IDENTITY1"]=1
# 



# Parameters
check_interval=5  # Check interval in seconds
alert_threshold=3  # Minimum number of true for an alarm
alert_repeat_interval=300  # Repeat alarm every 5 minutes
delinquent_slot_distance=20  # The moment the script notices the delink

bot_token="<BOT_TOKEN>"
chat_id="<CHAT_ID>"

log_file="/root/solana_validator_monitor.log"
touch $log_file

log_message() {
    local message=$1
    echo "$(date -u '+%Y-%m-%d %H:%M:%S %Z') - $message" | tee -a "$log_file"
}

send_alert() {
    local name=$1
    local message=$2
    local icon=$3
    local additional_message=$4
    log_message "Sending alert for $name: $message"
    
	response=$(curl -s -X POST "https://api.telegram.org/bot$bot_token/sendMessage" \
        -d chat_id=$chat_id \
        -d text="$icon *${name}* — ${message}%0A${additional_message}" \
        -d parse_mode="Markdown")
	log_message "Telegram response: $response"
}

check_validator() {
    local pubkey=$1
    local cluster=$2
    local name=$3
    local enabled=$4

    if [ $enabled -eq 0 ]; then
        return
    fi

    delinquent_status=$(solana $cluster validators --delinquent-slot-distance $delinquent_slot_distance --output json-compact | jq -r --arg identityPubkey "$pubkey" '.validators[] | select(.identityPubkey == $identityPubkey)' | jq -r '.delinquent')
    
    if [ "$delinquent_status" == "true" ]; then
        log_message "$name is delinquent"
        
        if [ -z "${validators_delinquent_start[$pubkey]}" ]; then
            validators_delinquent_start[$pubkey]=$(date +%s)
            validators_alert_count[$pubkey]=1
            send_alert "$name" "is delinquent!" "🚨"
		else
			((validators_alert_count[$pubkey]++))
			local current_time=$(date +%s)
			
			# Checking whether the interval for re-notification has passed
			if [ ${validators_alert_count[$pubkey]} -eq $alert_threshold ] || [ $((current_time - ${last_alert_time[$pubkey]:-0})) -ge $alert_repeat_interval ]; then
				delinquent_duration=$(( (current_time - ${validators_delinquent_start[$pubkey]}) / 60 ))
				
				# If the duration is 0 minutes, we simply skip this notification.
				if [ $delinquent_duration -gt 0 ]; then
					send_alert "$name" "is still delinquent! (for $delinquent_duration minutes)" "❗"
					last_alert_time[$pubkey]=$current_time  # Updating the time of the last notification
				fi
			fi
		fi
    else
        if [ -n "${validators_delinquent_start[$pubkey]}" ]; then
            delinquent_duration=$(( ($(date +%s) - ${validators_delinquent_start[$pubkey]}) / 60 ))
            send_alert "$name" "is no longer delinquent!" "✅" "Was delinquent for $delinquent_duration minutes"
            unset validators_delinquent_start[$pubkey]
            unset validators_alert_count[$pubkey]
        fi
        log_message "$name is not delinquent"
    fi
}

while true; do
    for pubkey in "${!validators_clusters[@]}"; do
        check_validator "$pubkey" "${validators_clusters[$pubkey]}" "${validators_names[$pubkey]}" "${validators_enabled[$pubkey]}"
    done
    sleep $check_interval
done


