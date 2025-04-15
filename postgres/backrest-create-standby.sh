#!/bin/bash
# New: Source environment variables from the colocated .env file
source "$(dirname "$0")/.env"

CONFIG_PATH="/etc/pgbackrest/pgbackrest.conf"

# Check for an existing pgbackrest config file and warn about overwriting
if [ -f "$CONFIG_PATH" ]; then
	echo "Existing pgbackrest configuration found at $CONFIG_PATH:"
	cat "$CONFIG_PATH"
	read -p "This will be overwritten. Continue? (y/n): " conf_answer
	if [ "$conf_answer" != "y" ]; then
		echo "Exiting..."
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

# Ensure the pgbackrest config directory exists
sudo mkdir -p "$(dirname "$CONFIG_PATH")"

# Create new pgbackrest configuration file using the prompted values
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
echo "New pgbackrest configuration created at $CONFIG_PATH"

if command -v pgbackrest >/dev/null 2>&1; then
	read -p "pgbackrest is already installed. Do you want to reinstall? (y/n): " answer
	if [ "$answer" != "y" ]; then
		echo "Exiting..."
		exit 0
	fi
fi

#make sure pg backrest is installed
pgbackrest --version

sudo apt update
sudo apt install -y postgresql-client libpq-dev libssl-dev libyaml-dev liblz4-dev libzstd-dev

sudo apt install -y curl
curl -1sLf https://pgbackrest.org/apt/pgbackrest-release-$(lsb_release -cs).deb -o pgbackrest-release.deb
sudo dpkg -i pgbackrest-release.deb
sudo apt update

sudo apt install -y pgbackrest

# Prompt to stop PostgreSQL and restore backup
read -p "Press enter to stop PostgreSQL and restore the backup..."

PG_CONF="/etc/postgresql/17/main/postgresql.conf"
PG_DATA="/var/lib/postgresql/17/main"

sudo -u postgres psql -U postgres -d postgres -c "alter system set wal_level = 'replica';"
sudo -u postgres psql -U postgres -d postgres -c "alter system set archive_mode = 'off';"
sudo -u postgres psql -U postgres -d postgres -c "alter system set archive_command = 'pgbackrest --stanza=main archive-get %f %p';"

echo "⚠️  Stopping PostgreSQL to demote..."
systemctl stop postgresql@17-main

echo "✅ PostgreSQL stopped."

# Backup the current config file
cp "$PG_CONF" "$PG_CONF.bak"

echo "🔧 Updating PostgreSQL configuration for standby mode..."

echo "🔄 Performing pgbackrest standby restore..."
if ! sudo pgbackrest --stanza=main --type=standby --delta restore; then
  echo "❌ Restore failed!"
  exit 1
fi
echo "✅ Restore completed successfully."


# Ensure standby mode is enabled
rm -f "$PG_DATA/recovery.signal"
touch "$PG_DATA/standby.signal"

echo "✅ PostgreSQL is now configured for standby mode."

# Start PostgreSQL in standby mode
echo "🚀 Starting PostgreSQL in standby mode..."
systemctl start postgresql@17-main

echo "🎉 PostgreSQL is now running as a standby server!"
