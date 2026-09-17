# RustDesk Server OSS on Railway

Self-host the [RustDesk](https://github.com/rustdesk/rustdesk) remote-desktop
server (124k stars) on Railway: **hbbs** (ID/rendezvous) + **hbbr** (relay),
with a persistent keypair and an auto-generated client configuration card.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.app/new?github_url=https://github.com/lNamelessl/rustdesk-railway-template)

## What you get

| Service | Binary | Persistence | Public endpoint |
|---|---|---|---|
| `hbbs` | `/usr/bin/hbbs` (ID/rendezvous server) | Volume at `/root` (Ed25519 keypair + `db_v2.sqlite3`) | TCP proxy on port **21116** |
| `hbbr` | `/usr/bin/hbbr` (relay server) | Volume at `/root` | TCP proxy on port **21117** |

Both services derive from the official [`rustdesk/rustdesk-server:1.1.16`](https://hub.docker.com/r/rustdesk/rustdesk-server)
image (pinned tag) with a static busybox layer added for the entrypoint and
diagnostics. The official binaries are used unmodified.

## The client config card

On every boot, the `hbbs` service prints — and writes to
`/root/client-config.txt` on the volume — a ready-to-paste configuration:

```
============================================================
 RustDesk client configuration
 RustDesk client > Settings > Network > ID/Relay Server
============================================================
ID Server:    <your-hbbs-proxy-domain>:<assigned-port>
Relay Server: <your-hbbr-proxy-domain>:<assigned-port>
Key:          <server public key>
============================================================
```

Copy those three values into **every RustDesk client**
(`Settings > Network > ID/Relay Server`), or import them via
`rustdesk.toml`. Find the card in the `hbbs` deploy logs or by reading
`client-config.txt` on the volume (`railway ssh -s hbbs -- /bin/busybox cat /root/client-config.txt`).

- `ID Server` is hbbs's own public TCP proxy (`RAILWAY_TCP_PROXY_DOMAIN:PORT`).
- `Relay Server` comes from the `RELAY_SERVERS` variable, pre-wired to hbbr's
  public TCP proxy.
- `Key` is the base64 public key from `/root/id_ed25519.pub`, generated once
  and persisted — losing it would break every configured client, which is why
  the volume is mandatory.

## How it works

- **One image, two roles.** The entrypoint picks the binary from the service
  name: a Railway service named like `*hbbr*` runs `hbbr`, anything else runs
  `hbbs` (override with the `ROLE` variable if you rename services).
- **`RELAY_SERVERS` is pre-wired** on `hbbs` to
  `${{hbbr.RAILWAY_TCP_PROXY_DOMAIN}}:${{hbbr.RAILWAY_TCP_PROXY_PORT}}` —
  hbbr's *public* address, because that is the address hbbs advertises to
  clients for relaying. It is passed to hbbs both as `-r` and as the
  `RELAY-SERVERS` env var (the exact name upstream reads).
- **`ALWAYS_USE_RELAY=Y` is baked in.** Railway exposes TCP only, so the UDP
  21116 NAT-punch path is unavailable. Every session goes through hbbr —
  same functionality, more relay bandwidth.
- **`TEST_HBBS=no` is baked in.** Upstream hbbs runs a loopback self-test at
  boot and exits the process if it fails; here listening is verified
  externally via TCP probes instead.

## Environment variables

| Variable | Service | Default | Notes |
|---|---|---|---|
| `RELAY_SERVERS` | hbbs | `${{hbbr.RAILWAY_TCP_PROXY_DOMAIN}}:${{hbbr.RAILWAY_TCP_PROXY_PORT}}` | Set automatically by the template. Public relay address advertised to clients. |
| `ROLE` | either | from service name | Force `hbbs` or `hbbr` if you rename services. |
| `DATA_DIR` | either | `/root` | Working dir (keypair, SQLite, config card). Keep the volume here. |
| `ALWAYS_USE_RELAY` | hbbs | `Y` (baked) | Set to anything else to attempt direct P2P (not recommended on Railway). |
| `TEST_HBBS` | hbbs | `no` (baked) | Upstream boot self-test address; `no` disables. |

No deploy-form prompts: deploy the template and everything wires itself up.

## Honest limitations

- **Relay-over-TCP mode.** Without UDP 21116, NAT type detection and direct
  P2P punching cannot work on Railway. All traffic relays through hbbr
  (bandwidth on your Railway plan is the variable cost — roughly 2x the
  screen-stream bitrate).
- **No web console.** The OSS server has no dashboard (that is
  [RustDesk Server Pro](https://rustdesk.com/pricing)). Management is the
  config card, logs, and the SQLite/keystore files on the volume.
- **Pinned image.** `rustdesk/rustdesk-server:1.1.16` is pinned for
  reproducibility; bump the tag in the `Dockerfile` to upgrade.

## Troubleshooting

- **Client shows "not ready" / key mismatch** — the client `Key` must exactly
  match the `Key:` line of the card. If the keypair was ever deleted from the
  volume, every client needs the new key re-entered.
- **Which ports matter?** hbbs TCP `21116` (ID server) and hbbr TCP `21117`
  (relay) are proxied. hbbs UDP `21116` (NAT punch) and websockets
  `21118`/`21119` (web client) are not proxied.
- **Check listeners** — `railway ssh -s hbbs -- /bin/busybox nc -z 127.0.0.1 21116`.
- **Rotating the key** — delete `id_ed25519` and `id_ed25519.pub` on the
  volume and redeploy; then update every client with the new `Key:` value.

## License

RustDesk Server OSS is [AGPL-3.0](https://github.com/rustdesk/rustdesk-server/blob/master/LICENSE).
This template is a deployment wrapper; RustDesk itself remains upstream's
property. Self-hosting your own server is free.
