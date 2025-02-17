#!/bin/bash

# Added: Define ANSI color codes and helper functions for colored and emoji outputs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}✅ $1${NC}"; }
warn()    { echo -e "${YELLOW}❗ $1${NC}"; }
error()   { echo -e "${RED}❌ $1${NC}"; }
process() { echo -e "${CYAN}🚀 $1${NC}"; }

# New: Source environment variables from the colocated .env file
source "$(dirname "$0")/.env"

CONFIG_PATH="/etc/pgbackrest/pgbackrest.conf"
PG_VERSION=17

# Check for an existing pgbackrest config file and warn about overwriting
if [ -f "$CONFIG_PATH" ]; then
	warn "Existing pgbackrest configuration found at $CONFIG_PATH:"
	cat "$CONFIG_PATH"
	read -p "This will be overwritten. Continue? (y/n): " conf_answer
	if [ "$conf_answer" != "y" ]; then
		error "Exiting..."
		exit 0
	fi
fi

# Prompt for required S3 environment variables if not set
for var in PGBR_S3_ENDPOINT PGBR_S3_KEY PGBR_S3_KEY_SECRET PGBR_S3_BUCKET; do
    if [ -z "${!var}" ]; then
		read -p "Enter value for $var: " value
		export "$var"="$value"
    fi
done

process "Ensuring pgbackrest config directory exists"
sudo mkdir -p "$(dirname "$CONFIG_PATH")"

process "Creating new pgbackrest configuration file"
cat <<EOF | sudo tee "$CONFIG_PATH" > /dev/null
[global]
repo1-type=s3
repo1-path=/pgbackrest
repo1-s3-uri-style=path
repo1-s3-endpoint=${PGBR_S3_ENDPOINT}
repo1-s3-region=auto
repo1-s3-key=${PGBR_S3_KEY}
repo1-s3-key-secret=${PGBR_S3_KEY_SECRET}
repo1-s3-bucket=${PGBR_S3_BUCKET}
repo1-cipher-type=none

[main]
pg1-path=/var/lib/postgresql/17/main
pg1-user=postgres
EOF
info "New pgbackrest configuration created at $CONFIG_PATH"

if command -v pgbackrest >/dev/null 2>&1; then
	read -p "pgbackrest is already installed. Do you want to reinstall? (y/n): " answer
	if [ "$answer" != "y" ]; then
		error "Exiting..."
		exit 0
	fi
fi

process "Checking pgbackrest installation"
pgbackrest --version

process "Updating apt and installing required packages"
sudo apt update
sudo apt install -y postgresql-client libpq-dev libssl-dev libyaml-dev liblz4-dev libzstd-dev

sudo apt install -y curl
process "Downloading pgbackrest release package"
curl -1sLf https://pgbackrest.org/apt/pgbackrest-release-$(lsb_release -cs).deb -o pgbackrest-release.deb
sudo dpkg -i pgbackrest-release.deb
sudo apt update

sudo apt install -y pgbackrest

#update /etc/postgresql/{PG_VERSION}/main/postgresql.conf to include:

process "Updating PostgreSQL configuration"
sudo -u postgres psql -U postgres -d postgres -c "alter system set wal_level to 'replica';"
sudo -u postgres psql -U postgres -d postgres -c "alter system set archive_mode to 'on';"
sudo -u postgres psql -U postgres -d postgres -c "alter system set archive_command to 'pgbackrest --stanza=main archive-push %p';"
sudo -u postgres psql -U postgres -d postgres -c "alter system set max_wal_size to '1GB';"
sudo -u postgres psql -U postgres -d postgres -c "alter system set min_wal_size to '80MB';"
sudo -u postgres psql -U postgres -d postgres -c "alter system set checkpoint_timeout to '300s';"
sudo -u postgres psql -U postgres -d postgres -c "alter system set archive_timeout to '30s';"

process "Restarting PostgreSQL"
sudo systemctl restart postgresql

process "Setting up and checking pgbackrest stanza 'main'"
sudo -u postgres pgbackrest --stanza=main --log-level-console=info stanza-create
sudo -u postgres pgbackrest --stanza=main --log-level-console=info check

process "Initiating pgbackrest backup for stanza 'main'"
sudo -u postgres pgbackrest --stanza=main backup