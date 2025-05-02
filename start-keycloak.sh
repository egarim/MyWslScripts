#!/bin/bash
cd $KEYCLOAK_DIR
export KEYCLOAK_ADMIN=admin
export KEYCLOAK_ADMIN_PASSWORD=yyz
./bin/kc.sh start-dev \
  --db=postgres \
  --db-url=jdbc:postgresql://$DB_HOST:$DB_PORT/$DB_NAME \
  --db-username=$DB_USER \
  --db-password=$DB_PASSWORD \
  --http-port=$KEYCLOAK_PORT \
  --http-host=0.0.0.0