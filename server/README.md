# BenchLog server

One shared library for every BenchLog device in the shop. The Mac keeps its own full copy
and works offline; the server holds the copy everyone syncs with, hands out ticket and
invoice numbers, and stores photos and files.

It needs Node 24 or later and nothing else (no `npm install`: SQLite is built into Node).

## Run it with Docker (a NAS or an always-on Mac)

```sh
cd server
docker build -t benchlog-server .
docker run -d --name benchlog --restart unless-stopped \
  -p 8420:8420 -v benchlog-data:/data benchlog-server
docker logs benchlog        # shows the library token, once
```

On a Mac, OrbStack or Docker Desktop runs it. To keep the data in a folder of your own
(a NAS share, for example) instead of the `benchlog-data` volume, use
`-v /path/to/folder:/data`. The server runs as user 1000, so that folder must be writable
by it: `sudo chown 1000:1000 /path/to/folder`, or add `--user "$(id -u):$(id -g)"` to
`docker run`.

## Run it without Docker

```sh
cd server
DATA_DIR=~/BenchLogServer npm start
```

Settings, all optional: `PORT` (8420), `DATA_DIR` (`./data`), `BENCHLOG_TOKEN` (instead of
the token file).

## Connect BenchLog

In BenchLog, open **Settings > Sync**, enter the server's address
(`http://192.168.1.20:8420`, or its Tailscale name) and the token, then **Connect**.
The first Mac uploads its library; the next devices join it.

## From away: Tailscale

Leave port 8420 closed on the router. Install Tailscale on the server's machine and on your
devices; BenchLog then reaches the server at `http://<machine>.<tailnet>.ts.net:8420`
wherever you are, encrypted by Tailscale. For HTTPS on the tailnet:
`tailscale serve --bg 8420`, then use `https://<machine>.<tailnet>.ts.net`.

## Back it up

Everything is in the data folder: `library.sqlite`, `files/`, and `token`. Each Mac also
keeps a full copy, and BenchLog's own backups still run.

## Test

```sh
cd server && npm test
```

The API is in `src/server.js`; the sync rules in `../docs/SCHEMA.md`.
