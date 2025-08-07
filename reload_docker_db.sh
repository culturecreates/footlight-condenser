#!/bin/sh

# Copy dump file to container
docker compose cp latest.dump.1 db:/tmp/latest.dump

# Restore database in container
docker compose exec db pg_restore --verbose --clean --no-acl --no-owner -h localhost -U postgres -d footlight_condenser_development /tmp/latest.dump