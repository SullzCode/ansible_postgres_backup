#!/bin/bash

# Prompt for IP address
echo "Enter the EC2 instance IP address:"
read ip_address

# Basic IP validation - check if it has 4 parts
if [[ $(echo "$ip_address" | tr '.' ' ' | wc -w) != 4 ]]; then
    echo "Invalid IP address format"
    exit 1
fi

# Connect to EC2
ssh -i ~/.ssh/your-key.pem ec2-user@$ip_address

