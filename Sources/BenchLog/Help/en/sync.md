# Sync and the Shop Server

With a **BenchLog server** on your shop network, every Mac shares one library. Each Mac keeps a full copy and works offline; changes go both ways a few seconds after you make them, and every minute.

## Set up the server

The server runs on an always-on Mac or a NAS, with Docker or with Node 24.

```
cd server
docker build -t benchlog-server .
docker run -d --name benchlog --restart unless-stopped \
  -p 8420:8420 -v benchlog-data:/data benchlog-server
docker logs benchlog
```

The last command shows the **token**, once. On a Mac, OrbStack or Docker Desktop runs Docker. The `server` folder and its README are in BenchLog's source on GitHub.

To reach the server away from the shop, install Tailscale on the server and on each Mac, and use the server's Tailscale name as its address.

## Connect the first Mac

1. Open **Settings > Sync**.
2. Enter the server's address, such as `http://bench-mac.local:8420`, and the token.
3. Choose **Test Connection**, then **Connect**. The library goes up to the server.

## Join from another Mac

The server holds one library. To use it on another Mac:

1. On the first Mac, copy the **library key** from Settings > Sync.
2. On the other Mac, enter the address and the token, then the library key, and choose **Replace This Mac’s Library…**. BenchLog backs up that Mac's library first.

## What you see

- The bottom of the sidebar shows when the library last synced, and **Sync Now**.
- **Offline** means the server is out of reach. Keep working: changes wait and go when it is back. New repairs take numbers from a reserve of ticket numbers.
- Invoices and credit notes need the server, so their numbers never repeat.
- Device passcodes are sealed with the library key before they leave the Mac. Keep the key safe: without it, a new Mac cannot join.
