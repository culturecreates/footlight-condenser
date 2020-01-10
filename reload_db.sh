#!/bin/sh
pg_restore --verbose --clean --no-acl --no-owner -h localhost -U saumier -d footlight-condenser_development latest.dump

