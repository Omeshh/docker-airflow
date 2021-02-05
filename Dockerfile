# VERSION 1.9.0_2
# DESCRIPTION: Basic Airflow container
# BUILD: docker build --rm -t kabbage-airflow .

FROM python:3.6-slim
LABEL maintainer="Omesh Patil"

# Never prompts the user for choices on installation/configuration of packages
ENV DEBIAN_FRONTEND noninteractive
ENV TERM linux

# Airflow
ARG AIRFLOW_VERSION=1.10.4
ARG AIRFLOW_HOME=/usr/local/airflow

# FreeTDS
ARG FREETDS_VERSION=1.00.109

# Install gosu for a better su+exec command
ARG GOSU_VERSION=1.10

# Define en_US.
ENV LANGUAGE en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV LC_CTYPE en_US.UTF-8
ENV LC_MESSAGES en_US.UTF-8

ENV SLUGIFY_USES_TEXT_UNIDECODE yes

RUN set -ex \
    && buildDeps=' \
        python3-dev \
        libkrb5-dev \
        libsasl2-dev \
        libssl-dev \
        libffi-dev \
        build-essential \
        libblas-dev \
        liblapack-dev \
        libpq-dev \
        git \
    ' \
    && apt-get update -yqq \
    && apt-get upgrade -yqq \
    && apt-get install -yqq --no-install-recommends \
        $buildDeps \
        python3-pip \
        python3-requests \
        default-libmysqlclient-dev \
        apt-utils \
        curl \
        rsync \
        netcat \
        locales \
        gnupg \
        vim \
        openssh-client \
        wget \
        gcc \
        jq \
    && sed -i 's/^# en_US.UTF-8 UTF-8$/en_US.UTF-8 UTF-8/g' /etc/locale.gen \
    && locale-gen \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    && useradd -ms /bin/bash -d ${AIRFLOW_HOME} airflow \
    && wget -O freetds.tar.gz "http://www.freetds.org/files/stable/freetds-${FREETDS_VERSION}.tar.gz" \
    && mkdir -p /usr/src/freetds \
    && tar -xzC /usr/src/freetds --strip-components=1 -f freetds.tar.gz \
    && rm freetds.tar.gz \
    && cd /usr/src/freetds \
    && ./configure \
        --disable-odbc \
        --disable-apps \
        --disable-server \
        --disable-pool \
        --datarootdir=/usr/src/freetds/data \
        --prefix=/usr \
    && make -j "$(nproc)" \
    && make install \
    && pip install -U pip setuptools wheel \
    && pip install Cython \
    && pip install pytz \
    && pip install pyOpenSSL \
    && pip install ndg-httpsclient \
    && pip install pyasn1 \
    && pip install psycopg2-binary \
    && pip install apache-airflow[crypto,celery,postgres,hive,jdbc,mysql,mssql,ldap,hdfs,s3,slack,vertica]==$AIRFLOW_VERSION \
    && pip install celery[redis]==4.1.1 \
    && pip install paramiko \
    && pip install virtualenv \
    && apt-get purge --auto-remove -yqq $buildDeps \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/* \
        /usr/share/man \
        /usr/share/doc \
        /usr/share/doc-base \
        /usr/src/freetds \
    && dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')" \
    && wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch" \
    && chmod +x /usr/local/bin/gosu \
    && gosu nobody true

COPY script/entrypoint.sh /entrypoint.sh
COPY config/airflow.cfg ${AIRFLOW_HOME}/airflow.cfg
COPY freetds.conf /etc/freetds/freetds.conf

RUN chown -R airflow: ${AIRFLOW_HOME}

EXPOSE 8080 5555 8793

WORKDIR ${AIRFLOW_HOME}
ENTRYPOINT ["/entrypoint.sh"]
CMD ["webserver"] # set default arg for entrypoint