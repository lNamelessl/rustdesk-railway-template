Deploy your own RustDesk remote-desktop server on Railway in one click — **hbbs** (ID/rendezvous server) and **hbbr** (relay server) from the official `rustdesk/rustdesk-server:1.1.16` OSS image, with persistent keypairs and a copy-paste client configuration card generated for you at boot.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.app/new?github_url=https://github.com/lNamelessl/rustdesk-railway-template)

**What gets provisioned**

- `hbbs` service — the ID/rendezvous server on TCP 21116 via a Railway TCP proxy, with a persistent volume at `/root` holding the Ed25519 keypair (`id_ed25519` / `id_ed25519.pub`) and the device database (`db_v2.sqlite3`).
- `hbbr` service — the relay server on TCP 21117 via a Railway TCP proxy, with its own persistent volume.
- Zero deploy-form prompts. `RELAY_SERVERS` on hbbs is pre-wired to hbbr's public proxy address, and `ALWAYS_USE_RELAY=Y` + `TEST_HBBS=no` are baked into the image.

**First steps after deploying**

1. Open the `hbbs` deploy logs and copy the **client configuration card** (also written to `/root/client-config.txt` on the volume): ID server, relay server, and public key.
2. Install the [RustDesk client](https://rustdesk.com/) on your machines, open `Settings > Network > ID/Relay Server`, and paste the three values.
3. Connect from anywhere — sessions relay through your own hbbr.

**Good to know**

- Railway exposes TCP only, so the UDP NAT-punch path is unavailable: every session relays through hbbr (`ALWAYS_USE_RELAY=Y` is baked in for deterministic behavior). Same functionality, more relay bandwidth — bandwidth on your plan is the variable cost (roughly 2x the screen-stream bitrate).
- The OSS server has no web console (that is RustDesk Server Pro). Management is the config card, service logs, and the files on the volume.
- The server is AGPL-3.0 licensed; self-hosting your own instance is free.

# Deploy and Host

## About Hosting

Two Railway services run the official RustDesk OSS binaries from one pinned Docker image (`rustdesk/rustdesk-server:1.1.16`, plus a static busybox layer for the entrypoint and diagnostics). `hbbs` listens on TCP 21116 (ID/rendezvous) and `hbbr` on TCP 21117 (relay), each published through a Railway TCP proxy. Each service has a persistent volume at `/root` where hbbs keeps its Ed25519 keypair and SQLite database — the keypair must survive redeploys or every configured client breaks, which is why volumes are part of the template. hbbs prints and writes a client configuration card (`ID Server` / `Relay Server` / `Key`) to its logs and to `/root/client-config.txt` on every boot. The only environment variable, `RELAY_SERVERS`, is pre-configured as an expression pointing at hbbr's public proxy address — you deploy first and configure clients second.

## Why Deploy

RustDesk is the most-starred open-source remote-desktop project (124k+ stars), and running the server yourself means your screens never touch a third-party relay. Doing that on a home connection requires port forwarding, a static address, and manual key management; Railway gives you public TCP endpoints, persistent volumes, and one-click redeploys instead. The template wires the two servers together correctly out of the box — the relay address hbbs advertises to clients points at hbbr's public proxy — and regenerates the client configuration card on every boot, which is the part most self-hosters get wrong by hand.

## Common Use Cases

- Personal remote access: reach your home lab or office workstation from anywhere with your own server in the middle.
- Family or small-team support: help friends or colleagues by connecting to their RustDesk client through a relay you control.
- Privacy-conscious support businesses: the OSS server relays sessions without a third party seeing them; no web console or license needed to operate it.
- Developing or testing RustDesk clients against a self-hosted rendezvous/relay pair that can be redeployed from scratch in one click.

## Dependencies for

### Deployment Dependencies

- `rustdesk/rustdesk-server:1.1.16` — official OSS server image (pinned), extended with a static busybox layer (`busybox:1.37.0-musl`) that provides the shell for the entrypoint and in-container diagnostics. No external databases or services are required: hbbs persists to SQLite on its volume.
- Railway networking: one TCP proxy per service (hbbs 21116, hbbr 21117) and one persistent volume per service mounted at `/root`.
- Clients: the free [RustDesk client](https://rustdesk.com/) on at least two machines, configured with the ID server, relay server, and public key from the generated config card.
