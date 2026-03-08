FROM node:20-bookworm-slim

ARG SKIP_GRAMMAR=false
ARG SKIP_BUILD_APP=false
ARG SKIP_DATASETS=false

ENV DEBIAN_FRONTEND=noninteractive
RUN echo "SKIP_GRAMMAR: $SKIP_GRAMMAR"
RUN echo "SKIP_BUILD_APP: $SKIP_BUILD_APP"
RUN echo "SKIP_DATASETS: $SKIP_DATASETS"
RUN apt-get update && apt-get install -y libatomic1 binutils file

# Install dependencies
RUN if [ "$SKIP_GRAMMAR" != "true" ] ; then apt-get update && apt-get install -y openjdk-17-jdk ; else echo "Skipping openjdk installation as grammar generation is skipped" ; fi
RUN if [ "$SKIP_DATASETS" != "true" ] ; then apt-get update && apt-get install -y git ; else echo "Skipping git installation as dataset fetch is skipped" ; fi
# Copy app
COPY . /home/node/app
RUN chown -R node:node /home/node/app

# Make data and database directories
RUN mkdir -p /database
RUN mkdir -p /data
RUN chown -R node:node /database
RUN chown -R node:node /data

# Switch to node user
USER node

# Set working directory
WORKDIR /home/node/app

# Install dependencies, generate grammar, and reduce size of kuzu node module
# Done in one step to reduce image size
RUN --mount=type=secret,id=NODE_AUTH_TOKEN,uid=1000 \
    if [ -f /run/secrets/NODE_AUTH_TOKEN ]; then \
      echo "//npm.pkg.github.com/:_authToken=$(cat /run/secrets/NODE_AUTH_TOKEN)" >> .npmrc; \
    fi && \
    npm install && \
    echo "=== DEBUG: kuzu package version ===" && \
    node -e "console.log(JSON.parse(require('fs').readFileSync('node_modules/@vela-engineering/kuzu/package.json')).version)" && \
    echo "=== DEBUG: kuzujs.node file ===" && \
    ls -la node_modules/@vela-engineering/kuzu/kuzujs.node 2>/dev/null || echo "kuzujs.node NOT FOUND" && \
    echo "=== DEBUG: readelf on kuzujs.node ===" && \
    (readelf --version-info node_modules/@vela-engineering/kuzu/kuzujs.node 2>/dev/null | grep "GLIBC_2.3[6-9]\|GLIBC_2.4" || echo "readelf not available or no high GLIBC") && \
    echo "=== DEBUG: file type ===" && \
    file node_modules/@vela-engineering/kuzu/kuzujs.node 2>/dev/null || true && \
    if [ "$SKIP_GRAMMAR" != "true" ] ; then npm run generate-grammar-prod ; else echo "Skipping grammar generation" ; fi && \
    rm -rf node_modules/@vela-engineering/kuzu/prebuilt node_modules/@vela-engineering/kuzu/kuzu-source && \
    (sed -i '/^\/\/npm.pkg.github.com/d' .npmrc 2>/dev/null || true)

# Fetch datasets
RUN if [ "$SKIP_DATASETS" != "true" ] ; then npm run fetch-datasets ; else echo "Skipping dataset fetch" ; fi

# Build app
RUN if [ "$SKIP_BUILD_APP" != "true" ] ; then npm run build ; else echo "Skipping build" ; fi

# Expose port
EXPOSE 8000

# Set environment variables
ENV NODE_ENV=production
ENV PORT=8000
ENV KUZU_DIR=/database

# Run app
ENTRYPOINT ["node", "src/server/index.js"]
