ARG MONGO_BASE_IMAGE=mongo:8.0
FROM ${MONGO_BASE_IMAGE}

COPY init/ /docker-entrypoint-initdb.d/
RUN chmod 755 /docker-entrypoint-initdb.d/*.sh
