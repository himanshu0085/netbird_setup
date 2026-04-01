# NetBird Self-Hosted VPN — Deployment Walkthrough

## Deployment Summary

Successfully deployed a production-ready self-hosted NetBird VPN on Azure VM (`ubuntu@4.240.88.63`) at **https://netbirdtest.fincart.com** using the modern combined-container architecture (v0.67.1).

---

## What Was Done

### Phase 1: Cleanup & Prerequisites ✅

- **Removed old legacy NetBird installation** (4 separate containers: management, signal, dashboard, coturn — management was crash-looping)
- Stopped all containers, removed volumes and old configs from `/opt/netbird/`
- Verified `jq` installed (v1.7), Docker Compose (v5.1.0)
- Confirmed SSL certs exist at `/etc/nginx/ssl/netbird_fullchain.pem` and `/etc/nginx/ssl/netbird_key.pem`
- Confirmed port 8080 was free

### Phase 2: Official Script Execution ✅

Ran `getting-started.sh` with `NETBIRD_DOMAIN=netbirdtest.fincart.com` and Nginx option `[2]`.

**Generated files in `/opt/netbird/`:**

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Combined `netbird-server` + dashboard containers |
| `config.yaml` | Server config (replaces old `management.json`) |
| `dashboard.env` | Dashboard environment variables |
| `nginx-netbird.conf` | Nginx reverse proxy template |

### Phase 3: Nginx Configuration ✅

Updated `nginx-netbird.conf` with correct SSL paths and installed to `/etc/nginx/sites-available/netbird`.

**Key routing rules configured:**

| Path | Protocol | Backend |
|------|----------|---------|
| `/relay`, `/ws-proxy/*` | WebSocket | `127.0.0.1:8081` (netbird-server) |
| `/signalexchange.SignalExchange/*`, `/management.ManagementService/*` | gRPC | `127.0.0.1:8081` |
| `/api/*`, `/oauth2/*` | HTTP | `127.0.0.1:8081` |
| `/*` (catch-all) | HTTP | `127.0.0.1:8080` (dashboard) |

### Phase 4: Services Started & Validated ✅

**Container Status:**
```
NAME                IMAGE                             STATUS         PORTS
netbird-dashboard   netbirdio/dashboard:latest        Up (stable)    127.0.0.1:8080→80
netbird-server      netbirdio/netbird-server:latest   Up (stable)    127.0.0.1:8081→80, 0.0.0.0:3478→3478/udp
```

**Endpoint Validation:**

| Endpoint | Expected | Actual | Status |
|----------|----------|--------|--------|
| `https://netbirdtest.fincart.com/` | Dashboard HTML | `200` | ✅ |
| `https://netbirdtest.fincart.com/api/accounts` | Auth challenge | `401 JSON` | ✅ |
| `https://netbirdtest.fincart.com/oauth2/.well-known/openid-configuration` | OIDC config | `200` | ✅ |
| Dashboard setup page | `/setup` form | Renders correctly | ✅ |

### Dashboard Screenshot

![NetBird Setup Page](/home/himanshuparashar/.gemini/antigravity/brain/8f941359-c3ce-47d9-b2cf-7a9cfc04d309/netbird_setup_page.png)

---

## Remaining Manual Steps

### Phase 5: Create Admin Account

1. Open **https://netbirdtest.fincart.com** in your browser
2. You'll be redirected to `/setup` — the "Welcome to NetBird" page shown above
3. Fill in:
   - **Name**: Your name
   - **Email**: Your admin email
   - **Password**: Strong password (min 8 chars)
4. Click **Create Admin Account**
5. You'll be logged into the NetBird Dashboard

> [!IMPORTANT]
> The `/setup` page is only available when no users exist. After creating the first admin, it redirects to the login page permanently.

---

### Phase 6: Add Azure AD (Microsoft Entra ID)

#### Step 1: In NetBird Dashboard
1. Go to **Settings → Identity Providers**
2. Click **Add Identity Provider**
3. Select **Microsoft Entra ID**
4. **Copy the Redirect URL** that NetBird provides

#### Step 2: In Azure Portal
1. Go to **Azure Active Directory → App Registrations → New Registration**
2. Configure:
   - **Name**: `NetBird VPN`
   - **Supported account types**: Accounts in this organizational directory only (Single tenant)
   - **Redirect URI**: Select **Web**, paste the Redirect URL from NetBird
3. Click **Register**
4. Copy the **Application (client) ID**
5. Note your **Directory (tenant) ID** — the Issuer URL will be:
   ```
   https://login.microsoftonline.com/<TENANT_ID>/v2.0
   ```
6. Go to **Certificates & Secrets → New client secret**
   - Description: `NetBird VPN`
   - Expiry: Choose appropriate duration
   - Copy the **Secret Value** immediately (it won't be shown again)

#### Step 3: Back in NetBird Dashboard
1. Enter:
   - **Name**: `Azure AD` (display name for login button)
   - **Client ID**: The Application ID from Step 2
   - **Client Secret**: The secret value from Step 2
   - **Issuer**: `https://login.microsoftonline.com/<TENANT_ID>/v2.0`
2. Click **Save**
3. Azure AD login button will now appear on the login page

---

### Phase 7: Setup Keys & Client Connection

#### Generate a Setup Key
1. In the Dashboard, go to **Setup Keys** (left sidebar)
2. Click **Create Setup Key**
3. Configure:
   - **Name**: e.g., `Windows-Laptops`
   - **Type**: Reusable or One-off
   - **Expiry**: Set as needed
   - **Auto-groups**: Select groups to auto-assign
4. Copy the generated key

#### Connect a Client
```bash
# Install NetBird client (Linux)
curl -fsSL https://pkgs.netbird.io/install.sh | sh

# Connect using setup key
sudo netbird up \
  --management-url https://netbirdtest.fincart.com \
  --setup-key <YOUR_SETUP_KEY>

# Verify connection
sudo netbird status
```

For Windows/Mac, download from https://netbird.io/download and set:
- **Management URL**: `https://netbirdtest.fincart.com`
- **Setup Key**: Your generated key

---

## Azure NSG: Open UDP Ports

> [!WARNING]
> UDP port 3478 must be opened in your Azure NSG for STUN to work. Without this, peers behind NAT won't be able to connect.

Run in Azure CLI or configure via Portal:
```bash
# Open STUN port
az network nsg rule create \
  --resource-group <YOUR_RG> \
  --nsg-name <YOUR_NSG> \
  --name Allow-STUN-UDP \
  --priority 310 \
  --direction Inbound \
  --access Allow \
  --protocol Udp \
  --destination-port-ranges 3478

# Open TURN relay range (recommended)
az network nsg rule create \
  --resource-group <YOUR_RG> \
  --nsg-name <YOUR_NSG> \
  --name Allow-TURN-Relay-UDP \
  --priority 320 \
  --direction Inbound \
  --access Allow \
  --protocol Udp \
  --destination-port-ranges 49152-65535
```

---

## Debugging Reference

### Check container status
```bash
cd /opt/netbird && sudo docker compose ps
```

### View logs
```bash
# All logs
sudo docker compose -f /opt/netbird/docker-compose.yml logs -f

# Server only
sudo docker compose -f /opt/netbird/docker-compose.yml logs -f netbird-server

# Dashboard only
sudo docker compose -f /opt/netbird/docker-compose.yml logs -f dashboard
```

### Health check
```bash
curl http://localhost:9000/health
```

### Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| 502 Bad Gateway | Container not running | `cd /opt/netbird && sudo docker compose up -d` |
| Container crash loop | Bad config.yaml | Check logs, regenerate config |
| Auth errors | Invalid OIDC config | Verify Azure AD Client ID/Secret/Issuer |
| Peers can't connect | UDP 3478 blocked | Open in Azure NSG |
| gRPC errors | Nginx HTTP/2 issue | Ensure `http2` in nginx listen directive |

### Restart services
```bash
cd /opt/netbird && sudo docker compose restart
```

### Full rebuild (nuclear option)
```bash
cd /opt/netbird
sudo docker compose down -v
sudo docker compose up -d
```

---

## Architecture Summary

```
Internet → Nginx (443/SSL) → netbird-server (127.0.0.1:8081)  [Management + Signal + Relay + STUN]
                            → netbird-dashboard (127.0.0.1:8080) [UI]
         → Direct UDP :3478 → netbird-server                    [STUN]
```

**Version**: NetBird Server v0.67.1 (combined container architecture)
