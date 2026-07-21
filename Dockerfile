# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=ghcr.io/scverse/rapids-singlecell-cu12@sha256:733ff6eb8086203d202c895bd3eda7b47d1c743e0f76255368617330609b6ca2
FROM ${BASE_IMAGE}

ARG USER_NAME=analyst
ARG USER_UID=1000
ARG USER_GID=1000

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ENV PATH=/opt/conda/bin:/opt/conda/envs/r-sc/bin:${PATH} \
    CONDARC=/etc/conda/condarc \
    PIP_CONFIG_FILE=/etc/pip.conf \
    R_PROFILE=/etc/R/Rprofile.site \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

USER root

# Use TUNA for Ubuntu packages while preserving NVIDIA's repository entries.
RUN if [[ -f /etc/apt/sources.list.d/ubuntu.sources ]]; then \
      sed -i \
        -e 's|http://archive.ubuntu.com/ubuntu/|https://mirrors.tuna.tsinghua.edu.cn/ubuntu/|g' \
        -e 's|http://security.ubuntu.com/ubuntu/|https://mirrors.tuna.tsinghua.edu.cn/ubuntu/|g' \
        /etc/apt/sources.list.d/ubuntu.sources; \
    fi; \
    apt-get -qq update; \
    apt-get -q -o=Dpkg::Use-Pty=0 install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      less \
      locales \
      nano \
      procps \
      rsync; \
    apt-get -q clean; \
    rm -rf /var/lib/apt/lists/*

COPY config/condarc /etc/conda/condarc
COPY config/pip.conf /etc/pip.conf
COPY config/Rprofile.site /etc/R/Rprofile.site
COPY env/requirements-python.txt /tmp/requirements-python.txt
COPY env/environment-r.yml /tmp/environment-r.yml

# Preserve the upstream GPU stack and add only analysis-facing tools.
RUN /opt/conda/bin/python -m pip install \
      --no-cache-dir \
      --upgrade-strategy only-if-needed \
      --requirement /tmp/requirements-python.txt; \
    mamba env create --file /tmp/environment-r.yml; \
    mamba clean --all --yes; \
    rm -f /tmp/requirements-python.txt /tmp/environment-r.yml

# Create or adapt a non-root account to match the host UID/GID.
RUN if ! getent group "${USER_GID}" >/dev/null; then \
      groupadd --gid "${USER_GID}" "${USER_NAME}"; \
    fi; \
    uid_owner="$(getent passwd "${USER_UID}" | cut -d: -f1 || true)"; \
    name_uid="$(getent passwd "${USER_NAME}" | cut -d: -f3 || true)"; \
    if [[ -n "${name_uid}" && "${name_uid}" != "${USER_UID}" ]]; then \
      echo "Username ${USER_NAME} already has UID ${name_uid}; choose another CONTAINER_USER" >&2; \
      exit 1; \
    elif [[ -n "${uid_owner}" && "${uid_owner}" != "${USER_NAME}" ]]; then \
      usermod --login "${USER_NAME}" --home "/home/${USER_NAME}" --move-home "${uid_owner}"; \
      usermod --gid "${USER_GID}" --shell /bin/bash "${USER_NAME}"; \
    elif [[ -n "${name_uid}" ]]; then \
      usermod --gid "${USER_GID}" --home "/home/${USER_NAME}" --shell /bin/bash "${USER_NAME}"; \
    else \
      useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USER_NAME}"; \
    fi; \
    install -d -o "${USER_UID}" -g "${USER_GID}" "/home/${USER_NAME}"; \
    printf '%s\n' \
      'source /opt/conda/etc/profile.d/conda.sh' \
      'conda activate base' \
      >> "/home/${USER_NAME}/.bashrc"; \
    chown "${USER_UID}:${USER_GID}" "/home/${USER_NAME}/.bashrc"

COPY scripts/entrypoint.sh /usr/local/bin/single-cell-workbench-entrypoint
COPY scripts/smoke-test.sh /usr/local/bin/single-cell-workbench-smoke-test
RUN chmod 0755 \
      /usr/local/bin/single-cell-workbench-entrypoint \
      /usr/local/bin/single-cell-workbench-smoke-test

WORKDIR /workspace
USER ${USER_UID}:${USER_GID}

ENTRYPOINT ["/usr/local/bin/single-cell-workbench-entrypoint"]
CMD ["sleep", "infinity"]
