#!/bin/bash

# Domain to check and obtain SSL certificate for
domain="%DOMAIN%"

# Get the local IP address of the server
local_ip=$(ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)

while true; do
  # Get the current IP address the domain resolves to, bypassing caches
  domain_ip=$(dig +short +trace "$domain" | tail -n 1)

  # Check if the domain points to the local IP (substring match)
  if [[ "$domain_ip" == *"$local_ip"* ]]; then
    echo "Domain $domain is now pointing to $local_ip"

    certbot certonly --non-interactive --no-eff-email --no-redirect --email '%EMAIL_ADDRESS%' --standalone --domains $domain

    break
  else
    echo "Domain $domain is not yet pointing to $local_ip. Retrying in 60 seconds..."
    sleep 60
  fi
done
