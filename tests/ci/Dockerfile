ARG TEST_IMAGE
FROM ${TEST_IMAGE}

# Give the image a real service manager, then install exactly what the installer installs.
RUN if command -v apk >/dev/null; then \
      apk add --no-cache bash coreutils; \
    else \
      apt-get update && apt-get install -y --no-install-recommends bash systemd systemd-sysv dbus; \
    fi
COPY sing-box.sh /tmp/sing-box.sh
RUN bash -c 'source /tmp/sing-box.sh; install_dependencies' && rm /tmp/sing-box.sh

ENV container=docker
