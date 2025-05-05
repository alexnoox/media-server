#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Logger function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Check if .env file exists
if [ ! -f .env ]; then
    error ".env file not found. Please run install.sh first or create an .env file manually."
    exit 1
fi

# Update API keys function
update_api_key() {
    local service=$1
    local container=$2
    local env_var=$3
    
    log "Updating $service configuration..."
    
    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^$container$"; then
        warning "$service container ($container) is not running. Make sure to start it with 'docker compose up -d'"
        warning "Skipping $service API key update"
        return 1
    fi
    
    # Wait for the config.xml file to become available
    local timeout=60
    local config_file="./$container/config.xml"
    log "Waiting for $config_file to be available (timeout: ${timeout}s)..."
    
    local counter=0
    until [ -f "$config_file" ]
    do
        sleep 5
        counter=$((counter + 5))
        
        if [ $counter -ge $timeout ]; then
            error "Timeout waiting for $config_file to be available"
            warning "Skipping $service API key update"
            return 1
        fi
        
        log "Still waiting for $config_file... ($counter/$timeout seconds)"
    done
    
    # Extract API key and update .env file
    local api_key=$(sed -n 's/.*<ApiKey>\(.*\)<\/ApiKey>.*/\1/p' "$config_file")
    
    if [ -z "$api_key" ]; then
        warning "Failed to extract API key from $config_file"
        warning "Skipping $service API key update"
        return 1
    fi
    
    log "Found API key for $service"
    
    # Update .env file
    if grep -q "^$env_var=" .env; then
        sed -i.bak "s/^$env_var=.*/$env_var=$api_key/" .env && rm .env.bak
        log "Updated $env_var in .env file"
    else
        warning "$env_var not found in .env file"
        echo "$env_var=$api_key" >> .env
        log "Added $env_var to .env file"
    fi
    
    return 0
}

# Update API keys for each service
radarr_updated=false
sonarr_updated=false
prowlarr_updated=false
bazarr_updated=false
jellyfin_updated=false
plex_updated=false
tautulli_updated=false
overseerr_updated=false

update_api_key "Radarr" "radarr" "RADARR_API_KEY" && radarr_updated=true
update_api_key "Sonarr" "sonarr" "SONARR_API_KEY" && sonarr_updated=true
update_api_key "Prowlarr" "prowlarr" "PROWLARR_API_KEY" && prowlarr_updated=true

# Try to update Bazarr API key if container exists
if docker ps --format '{{.Names}}' | grep -q "^bazarr$"; then
    if [ -f "./bazarr/config/config.yaml" ]; then
        log "Updating Bazarr configuration..."
        api_key=$(grep "^auth_apikey:" ./bazarr/config/config.yaml | awk '{print $2}')
        if [ -n "$api_key" ]; then
            sed -i.bak "s/^BAZARR_API_KEY=.*/BAZARR_API_KEY=$api_key/" .env && rm .env.bak
            log "Updated BAZARR_API_KEY in .env file"
            bazarr_updated=true
        else
            warning "Bazarr API key not found in config.yaml"
        fi
    else
        warning "Bazarr config.yaml not found. Skipping Bazarr API key update."
    fi
fi

# Try to update Jellyfin API key if container exists
if docker ps --format '{{.Names}}' | grep -q "^jellyfin$"; then
    log "Note: Jellyfin API key update not implemented. Please get it from the Jellyfin dashboard."
    jellyfin_updated=true
fi

# Try to update Plex API key if container exists
if docker ps --format '{{.Names}}' | grep -q "^plex$"; then
    log "Note: Plex API key (X-Plex-Token) needs to be retrieved manually."
    log "You can get it by following instructions at: https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/"
    plex_updated=true
fi

# Try to update Tautulli API key if container exists
if docker ps --format '{{.Names}}' | grep -q "^tautulli$"; then
    if [ -f "./tautulli/config.ini" ]; then
        log "Updating Tautulli configuration..."
        api_key=$(grep "^api_key = " ./tautulli/config.ini | awk '{print $3}')
        if [ -n "$api_key" ]; then
            sed -i.bak "s/^TAUTULLI_API_KEY=.*/TAUTULLI_API_KEY=$api_key/" .env && rm .env.bak
            log "Updated TAUTULLI_API_KEY in .env file"
            tautulli_updated=true
        else
            warning "Tautulli API key not found in config.ini"
        fi
    else
        warning "Tautulli config.ini not found. Skipping Tautulli API key update."
    fi
fi

# Try to update Overseerr API key if container exists
if docker ps --format '{{.Names}}' | grep -q "^overseerr$"; then
    if [ -f "./overseerr/settings.json" ]; then
        log "Updating Overseerr configuration..."
        # Extract API key using grep and sed
        api_key=$(grep -o '"apiKey":"[^"]*"' ./overseerr/settings.json | sed 's/"apiKey":"//;s/"//')
        if [ -n "$api_key" ]; then
            sed -i.bak "s/^OVERSEERR_API_KEY=.*/OVERSEERR_API_KEY=$api_key/" .env && rm .env.bak
            log "Updated OVERSEERR_API_KEY in .env file"
            overseerr_updated=true
        else
            warning "Overseerr API key not found in settings.json"
        fi
    else
        warning "Overseerr settings.json not found. Skipping Overseerr API key update."
    fi
fi

# Restart containers that were updated
containers_to_restart=""

if $radarr_updated; then containers_to_restart="$containers_to_restart radarr"; fi
if $sonarr_updated; then containers_to_restart="$containers_to_restart sonarr"; fi
if $prowlarr_updated; then containers_to_restart="$containers_to_restart prowlarr"; fi
if $bazarr_updated; then containers_to_restart="$containers_to_restart bazarr"; fi
if $jellyfin_updated; then containers_to_restart="$containers_to_restart jellyfin"; fi
if $tautulli_updated; then containers_to_restart="$containers_to_restart tautulli"; fi
if $overseerr_updated; then containers_to_restart="$containers_to_restart overseerr"; fi

if [ -n "$containers_to_restart" ]; then
    log "Restarting updated containers:$containers_to_restart"
    docker compose restart $containers_to_restart
    log "Containers restarted successfully"
else
    warning "No containers needed to be restarted"
fi

log "${GREEN}Configuration update complete!${NC}"
log "Your media server should now be fully configured and running."
log "Access Homepage at https://media.YOUR_DOMAIN"