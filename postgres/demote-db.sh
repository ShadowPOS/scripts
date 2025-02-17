#!/bin/bash

# Define PostgreSQL config directory and file
PG_CONF="/etc/postgresql/17/main/postgresql.conf"
PG_DATA="/var/lib/postgresql/17/main"

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

sudo -u postgres psql -U postgres -d postgres -c "alter system set wal_level to 'replica';"
sudo -u postgres psql -U postgres -d postgres -c "alter system set archive_mode to 'off';"
sudo -u postgres psql -U postgres -d postgres -c "alter system set archive_command to 'pgbackrest --stanza=main archive-get %f %p';"

# Ensure standby mode is enabled
rm -f "$PG_DATA/recovery.signal"
touch "$PG_DATA/standby.signal"

echo "✅ PostgreSQL is now configured for standby mode."

# Start PostgreSQL in standby mode
echo "🚀 Starting PostgreSQL in standby mode..."
systemctl start postgresql@17-main

echo "🎉 PostgreSQL is now running as a standby server!"
