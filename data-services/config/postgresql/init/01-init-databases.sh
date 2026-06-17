#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER temporal WITH PASSWORD 'temporal';
    CREATE DATABASE temporal OWNER temporal;
    GRANT ALL PRIVILEGES ON DATABASE temporal TO temporal;

    CREATE USER besteltool WITH PASSWORD 'besteltool' CREATEDB;
    CREATE DATABASE besteltool OWNER besteltool;
    GRANT ALL PRIVILEGES ON DATABASE besteltool TO besteltool;

    CREATE USER forgejo WITH PASSWORD 'forgejo';
    CREATE DATABASE forgejo OWNER forgejo;
    GRANT ALL PRIVILEGES ON DATABASE forgejo TO forgejo;
EOSQL