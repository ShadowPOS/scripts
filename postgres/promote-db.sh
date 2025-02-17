#!/bin/bash

# Define PostgreSQL config directory and file
PG_CONF="/etc/postgresql/17/main/postgresql.conf"

echo "🚀 Promoting the standby to primary..."
pg_ctlcluster 17 main promote

echo "✅ Standby promoted to primary."

# Wait a few seconds to ensure promotion is complete
sleep 5

echo "🔧 Updating WAL configuration..."
# Backup the current config file
cp "$PG_CONF" "$PG_CONF.bak"

sudo -u postgres psql -U postgres -d postgres -c "alter system set wal_level to 'replica';"
sudo -u postgres psql -U postgres -d postgres -c "alter system set archive_mode to 'on';"
sudo -u postgres psql -U postgres -d postgres -c "alter system set archive_timeout to '60s';"
sudo -u postgres psql -U postgres -d postgres -c "alter system set archive_command to 'pgbackrest --stanza=main archive-push %p';"

echo "✅ WAL settings updated."

# Reload PostgreSQL to apply changes without restarting
echo "🔄 Reloading PostgreSQL configuration..."
pg_ctlcluster 17 main reload

echo "🎉 Standby successfully promoted and WAL settings updated!"
