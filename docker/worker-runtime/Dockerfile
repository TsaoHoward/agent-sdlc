FROM node:22-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV WORKSPACE_ROOT=/workspace

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        bash \
        ca-certificates \
        git \
        openssh-client \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash worker \
    && mkdir -p "${WORKSPACE_ROOT}" /artifacts \
    && chown -R worker:worker "${WORKSPACE_ROOT}" /artifacts

COPY docker/worker-runtime/entrypoint.sh /usr/local/bin/worker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/worker-entrypoint.sh

USER worker
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/worker-entrypoint.sh"]
CMD ["bash"]
