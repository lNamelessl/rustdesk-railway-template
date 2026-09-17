# RustDesk Server OSS on Railway.
#
# Derived from the official image `rustdesk/rustdesk-server:1.1.16` (classic
# flavor: `FROM scratch`, static binaries at /usr/bin/hbbs and /usr/bin/hbbr,
# WORKDIR /root). The official binaries are used unmodified — this layer only
# adds a static busybox (shell + nc + sha256sum for probes, and a shell for
# the entrypoint) and the Railway entrypoint script.
#
# Why not the upstream image directly?
#  - The classic image has no shell at all, so no config-card generation,
#    no signal forwarding, and no in-container diagnostics are possible.
#  - The upstream s6 flavor (docker/) supervises both processes in one
#    container and keeps data in /data — not the two-service model used here.

FROM busybox:1.37.0-musl AS busybox

FROM rustdesk/rustdesk-server:1.1.16

COPY --from=busybox /bin/busybox /bin/busybox

# exec-form RUN: the base image ships no shell, so RUN must invoke busybox
# directly. The classic base is FROM scratch, so installing applets into
# /bin cannot collide with anything — and it puts /bin/sh at the canonical
# path, which `railway ssh` requires to attach to the container.
RUN ["/bin/busybox", "--install", "-s", "/bin"]

COPY entrypoint.sh /entrypoint.sh
RUN ["/bin/busybox", "chmod", "755", "/entrypoint.sh"]

# The scratch base has no /etc/passwd or /etc/group. Container exec sessions
# (railway ssh) resolve the connecting user against these files; without them
# every exec session fails to spawn. The binaries themselves do not need them.
RUN ["/bin/busybox", "mkdir", "-p", "/etc"]
RUN ["/bin/busybox", "sh", "-c", "printf 'root:x:0:0:root:/root:/bin/sh\\n' > /etc/passwd && printf 'root:x:0:\\n' > /etc/group"]

# Runtime behavior baked into the image so the Railway template needs zero
# deploy-form prompts:
#  - ALWAYS_USE_RELAY=Y: force every session through hbbr. Railway exposes
#    TCP only, so the UDP 21116 NAT-punch path is unavailable; relayed
#    connections are the deterministic, supported mode here.
#  - TEST_HBBS=no: skip hbbs's built-in boot self-test (upstream runs a
#    loopback probe at startup and calls process::exit(1) if it fails).
#    Listening is verified externally via TCP probes instead.
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    ALWAYS_USE_RELAY=Y \
    TEST_HBBS=no

# hbbs: TCP 21116 (ID/rendezvous), UDP 21116 (unavailable on Railway),
# 21118 (websocket). hbbr: TCP 21117 (relay), 21119 (websocket).
EXPOSE 21115 21116 21116/udp 21117 21118 21119

# Role resolution happens in the entrypoint (ROLE override, or the service
# name: a Railway service named like *hbbr* runs hbbr, anything else hbbs).
ENTRYPOINT ["/bin/busybox", "sh", "/entrypoint.sh"]
