#!/usr/bin/env bash

TRY_LOOP="20"
AIRFLOW_DIR=${AIRFLOW_VOLUME:-/airflow_git_repo}
AIRFLOW_HOME=${AIRFLOW_HOME:-/usr/local/airflow}
# If the user is root
if [ "$(id -u)" = "0" ]; then
  GOSU_AIRFLOW="gosu airflow"

  # If the airflow diectory exists
  if [ -d "$AIRFLOW_DIR" ]; then
      # get uid/gid of airflow diectory
      USER_UID=`ls -nd $AIRFLOW_DIR | cut -f3 -d' '`
      USER_GID=`ls -nd $AIRFLOW_DIR | cut -f4 -d' '`

      # get the current uid/gid of airflow user inside container
      AIRFLOW_UID=`getent passwd airflow | cut -f3 -d: || true`
      AIRFLOW_GID=`getent group airflow | cut -f3 -d: || true`

      # if they don't match, adjust
      if [ ! -z "$USER_GID" -a "$USER_GID" != "$AIRFLOW_GID" ]; then
        groupmod -g ${USER_GID} airflow
        chgrp -R airflow $AIRFLOW_HOME
      fi
      if [ ! -z "$USER_UID" -a "$USER_UID" != "$AIRFLOW_UID" ]; then
        usermod -u ${USER_UID} airflow
        chown -R airflow $AIRFLOW_HOME
      fi
  fi
fi

# if env.list is present, load it
if [ -e "/env.list" ]; then
    export $(grep -v '^#' /env.list | xargs)
fi

: "${REDIS_HOST:="redis"}"
: "${REDIS_PORT:="6379"}"
: "${REDIS_PASSWORD:=""}"

: "${POSTGRES_HOST:="postgres"}"
: "${POSTGRES_PORT:="5432"}"
: "${POSTGRES_USER:="airflow"}"
: "${POSTGRES_PASSWORD:="airflow"}"
: "${POSTGRES_DB:="airflow"}"
: "${PYPI_URL:="https://pypi.org/simple"}"
: "${AWS_REGION:="us-east-1"}"

# Defaults and back-compat
: "${AIRFLOW__CORE__FERNET_KEY:=${FERNET_KEY:=$(python -c "from cryptography.fernet import Fernet; FERNET_KEY = Fernet.generate_key().decode(); print(FERNET_KEY)")}}"
: "${AIRFLOW__CORE__EXECUTOR:=${EXECUTOR:-Sequential}Executor}"

export \
  AIRFLOW__CELERY__BROKER_URL \
  AIRFLOW__CELERY__RESULT_BACKEND \
  AIRFLOW__CORE__EXECUTOR \
  AIRFLOW__CORE__FERNET_KEY \
  AIRFLOW__CORE__LOAD_EXAMPLES \
  AIRFLOW__CORE__SQL_ALCHEMY_CONN \


# Load DAGs exemples (default: Yes)
if [[ -z "$AIRFLOW__CORE__LOAD_EXAMPLES" && "${LOAD_EX:=n}" == n ]]
then
  AIRFLOW__CORE__LOAD_EXAMPLES=False
fi

if [ ! -z "$PYPI_PASS_SECRET" ]; then
  virtualenv /tmp/awscli
  source /tmp/awscli/bin/activate
  pip install --upgrade awscli
  export PYPI_PASSWORD=$(aws secretsmanager get-secret-value --region $AWS_REGION --secret-id $PYPI_PASS_SECRET --query SecretString --output=text | jq -r '.[]')
  deactivate
fi

if [ ! -z "$PYPI_USER" ]  && [ ! -z "$PYPI_PASSWORD" ]; then
  export PYPI_URL=$(echo "$PYPI_URL" | sed "s/PYPI_USER:PYPI_PASSWORD/$PYPI_USER:$PYPI_PASSWORD/")
fi

# Install custom python package if requirements.txt is present
if [ -e "/requirements.txt" ]; then
    ${GOSU_AIRFLOW} $(which pip) install --user -i ${PYPI_URL} -r /requirements.txt
fi

if [ -n "$REDIS_PASSWORD" ]; then
    REDIS_PREFIX=:${REDIS_PASSWORD}@
else
    REDIS_PREFIX=
fi

wait_for_port() {
  local name="$1" host="$2" port="$3"
  local j=0
  while ! nc -z "$host" "$port" >/dev/null 2>&1 < /dev/null; do
    j=$((j+1))
    if [ $j -ge $TRY_LOOP ]; then
      echo >&2 "$(date) - $host:$port still not reachable, giving up"
      exit 1
    fi
    echo "$(date) - waiting for $name... $j/$TRY_LOOP"
    sleep 5
  done
}

if [ "$AIRFLOW__CORE__EXECUTOR" != "SequentialExecutor" ]; then
  AIRFLOW__CORE__SQL_ALCHEMY_CONN="postgresql+psycopg2://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"
  AIRFLOW__CELERY__RESULT_BACKEND="db+postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"
  wait_for_port "Postgres" "$POSTGRES_HOST" "$POSTGRES_PORT"
fi

if [ "$AIRFLOW__CORE__EXECUTOR" = "CeleryExecutor" ]; then
  AIRFLOW__CELERY__BROKER_URL="redis://$REDIS_PREFIX$REDIS_HOST:$REDIS_PORT/1"
  wait_for_port "Redis" "$REDIS_HOST" "$REDIS_PORT"
fi

case "$1" in
  webserver)
    ${GOSU_AIRFLOW} airflow upgradedb
    if [ "$AIRFLOW__CORE__EXECUTOR" = "LocalExecutor" ]; then
      # With the "Local" executor it should all run in one container.
      ${GOSU_AIRFLOW} airflow scheduler &
    fi
    exec ${GOSU_AIRFLOW} airflow webserver
    ;;
  worker|scheduler)
    # To give the webserver time to run initdb.
    sleep 10
    exec ${GOSU_AIRFLOW} airflow "$@"
    ;;
  flower)
    exec ${GOSU_AIRFLOW} airflow "$@"
    ;;
  version)
    exec ${GOSU_AIRFLOW} airflow "$@"
    ;;
  *)
    # The command is something like bash, not an airflow subcommand. Just run it in the right environment.
    exec ${GOSU_AIRFLOW} "$@"
    ;;
esac
