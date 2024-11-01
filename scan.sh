#!/bin/bash

# Define the start time for 15 months ago in ISO 8601 format
start_time=$(date -u -d '15 months ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v-15m +"%Y-%m-%dT%H:%M:%SZ")

# Define the end time as the current time in ISO 8601 format
end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# List all regions
regions=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)

for region in $regions
do
    echo "Checking region: $region"
    # List all instances in the region along with HttpTokens setting
    aws ec2 describe-instances --region "$region" \
        --query 'Reservations[].Instances[].[InstanceId, MetadataOptions.HttpTokens]' \
        --output text | while read instanceid httptokens
    do
        # Function to query a CloudWatch metric and return its sum as an integer
        get_metric_sum() {
            metric_name="$1"
            metric_data=$(aws cloudwatch get-metric-statistics --metric-name "$metric_name" --namespace AWS/EC2 --statistics Sum --start-time "$start_time" --end-time "$end_time" --period 2592000 --dimensions Name=InstanceId,Value="$instanceid" --region "$region" --output text)
            
            metric_sum=$(echo "$metric_data" | grep -oE '[0-9]+(\.[0-9]+)?' | head -n1)
            
            if [ -z "$metric_sum" ]; then
                echo "0"
            else
                # Converting the metric sum to an integer
                printf "%.0f\n" "$metric_sum"
            fi
        }

        # Retrieve metric sums as integers
        no_token=$(get_metric_sum "MetadataNoToken")
        no_token_rejected=$(get_metric_sum "MetadataNoTokenRejected")

        # Initialize message
        message=""

        # Check the metrics and construct the message
        if [ "$no_token" -gt 0 ] || [ "$no_token_rejected" -gt 0 ]; then
            message="WARNING: Instance $instanceid in $region has "
            if [ "$no_token" -gt 0 ] && [ "$no_token_rejected" -gt 0 ]; then
                message+="$no_token occurrence(s) of the MetadataNoToken metric and $no_token_rejected occurrence(s) of the MetadataNoTokenRejected metric in the past 15 months"
            elif [ "$no_token" -gt 0 ]; then
                message+="$no_token occurrence(s) of the MetadataNoToken metric in the past 15 months"
            else
                message+="$no_token_rejected occurrence(s) of the MetadataNoTokenRejected metric in the past 15 months"
            fi
            message+=" - IMDSv2 is $httptokens."
        else
            message="No attempt to use IMDSv1 was detected from Instance $instanceid in $region in the past 15 months - IMDSv2 is $httptokens."
        fi

        echo "$message"
    done
done
