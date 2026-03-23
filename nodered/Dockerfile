ARG NODE_RED_BASE_IMAGE=nodered/node-red:4.1.1
FROM ${NODE_RED_BASE_IMAGE}

WORKDIR /data
COPY --chown=node-red:root package.json /data/package.json
COPY --chown=node-red:root package-lock.json /data/package-lock.json
RUN npm install --unsafe-perm --no-update-notifier --no-fund --omit=dev

WORKDIR /usr/src/node-red
RUN mkdir -p /usr/src/node-red/course
COPY --chown=node-red:root settings.js /usr/src/node-red/course/settings.js
COPY --chown=node-red:root flows.json /usr/src/node-red/course/flows.json
COPY --chown=node-red:root entrypoint.sh /usr/src/node-red/course/entrypoint.sh
RUN chmod 755 /usr/src/node-red/course/entrypoint.sh

ENTRYPOINT ["/usr/src/node-red/course/entrypoint.sh"]
