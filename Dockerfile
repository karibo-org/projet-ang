# ---- builder stage: Debian slim with node & python tools ----
FROM debian:bookworm-slim AS builder

# metadata
LABEL maintainer="soozey.officiel@gmail.com"
ENV DEBIAN_FRONTEND=noninteractive

# tools we need: rsync, ca-certificates, git (optional), curl, bash, node & npm, python (for detection)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl rsync bash git \
       python3 python3-distutils python3-venv \
       nodejs npm \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# copy entire repo into builder stage
# Using a single COPY ensures Docker cache is efficient
COPY . /src

# ensure builder script is present and executable (if you use builder/build.sh)
# if you don't have builder/build.sh, the script below will still work using fallback logic
RUN chmod +x /src/builder/build.sh 2>/dev/null || true

# run the builder script if present, otherwise run an internal default process
# the builder script should create /src/dist as final output
RUN if [ -x /src/builder/build.sh ]; then \
      echo "Running provided builder/build.sh"; \
      /src/builder/build.sh; \
    else \
      echo "No builder/build.sh found - running default build steps"; \
      mkdir -p /src/dist; \
      # Node project: try npm build
      if [ -f package.json ]; then \
        echo "Detected package.json -> running npm install && npm run build (if present)"; \
        npm install --no-audit --no-fund || true; \
        npm run build --if-present || true; \
        if [ -d dist ]; then rsync -a --delete --exclude='.git' --exclude='node_modules' /src/dist/ /src/dist/ || true; fi; \
        if [ -d build ]; then rsync -a --delete --exclude='.git' --exclude='node_modules' /src/build/ /src/dist/ || true; fi; \
      else \
        # Python or static: copy files to /src/dist
        echo "No package.json -> treating as python/static -> copying files to /src/dist"; \
        rsync -a --delete --exclude='.git' --exclude='builder' --exclude='dist' --exclude='node_modules' --exclude='venv' --exclude='__pycache__' /src/ /src/dist/; \
      fi; \
    fi

# ensure /src/dist exists
RUN if [ ! -d /src/dist ]; then mkdir -p /src/dist; fi

# remove dev-only files from dist to keep runtime small
RUN rm -rf /src/dist/.git /src/dist/builder /src/dist/node_modules || true

# ---- runtime stage: small nginx to serve static files ----
FROM nginx:alpine AS runtime

# expose default http port
EXPOSE 80

# copy built static output into nginx html folder
# we expect builder to have produced /src/dist
COPY --from=builder /src/dist /usr/share/nginx/html

# optional: small default index if nothing was put in dist
RUN if [ -z "$(ls -A /usr/share/nginx/html 2>/dev/null || true)" ]; then \
      echo '<!doctype html><meta charset="utf-8"><title>Empty</title><h1>No build output</h1>' > /usr/share/nginx/html/index.html; \
    fi

# run nginx in foreground
CMD ["nginx", "-g", "daemon off;"]

