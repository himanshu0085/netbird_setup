# NetBird Self-Hosted VPN — Proof of Concept (POC) Document

**Project**: NetBird VPN Self-Hosted Infrastructure  
**Date**: April 1, 2026  
**Environment**: Azure VM (Ubuntu 24.04 LTS)  
**Domain**: https://netbirdtest.fincart.com  
**Status**: ✅ Successfully Deployed & Tested  

---

## 1. Executive Summary

This document covers the end-to-end deployment of a **self-hosted NetBird VPN** on an Azure VM. NetBird is an open-source WireGuard-based mesh VPN that provides zero-trust network access. The deployment uses the latest **combined-container architecture (v0.67.1)** with embedded identity provider and Nginx reverse proxy for HTTPS termination. Azure AD (Microsoft Entra ID) SSO has been integrated for enterprise authentication.

### Key Outcomes
- ✅ NetBird Management + Signal + Relay + STUN running in a single container
- ✅ Dashboard accessible via HTTPS at `https://netbirdtest.fincart.com`
- ✅ Azure AD SSO configured ("Continue with Fincart Azure SSO")
- ✅ Local email-based authentication also available
- ✅ Client successfully connected using setup key
- ✅ 1 peer connected and visible in dashboard

---

## 2. Infrastructure Overview

### 2.1 Azure VM Details

| Property | Value |
|----------|-------|
| **Hostname** | `fincart-common-sonarqube-vm-001` |
| **OS** | Ubuntu 24.04.4 LTS |
| **Public IP** | `4.240.88.63` |
| **Domain** | `netbirdtest.fincart.com` |
| **SSH Key** | `sonarvm-key.pem` |
| **Docker** | v29.3.0 |
| **Docker Compose** | v5.1.0 |

### 2.2 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     INTERNET                                │
└───────────┬─────────────────┬────────────────┬──────────────┘
            │ TCP 443         │ TCP 33073      │ UDP 3478
            ▼                 │                │
┌───────────────────────┐     │                │
│   Nginx (SSL/TLS)     │     │                │
│   - HTTPS termination │     │                │
│   - gRPC proxying     │     │                │
│   - WebSocket proxy   │     │                │
└──┬────────────────┬───┘     │                │
   │                │         │                │
   ▼                ▼         ▼                ▼
┌────────────┐  ┌──────────────────────────────────┐
│ Dashboard  │  │      netbird-server              │
│ (port 8080)│  │  ┌─────────────────────────────┐ │
│            │  │  │ Management (API + gRPC)     │ │
│ netbirdio/ │  │  │ Signal Server              │ │
│ dashboard  │  │  │ Relay Server (WebSocket)   │ │
│            │  │  │ STUN Server (UDP 3478)     │ │
│            │  │  │ Embedded IdP (Dex/OAuth2)  │ │
│            │  │  │ gRPC compat (port 33073)   │ │
│            │  │  └─────────────────────────────┘ │
│            │  │  Port 8081 (HTTP)                │
└────────────┘  └──────────────────────────────────┘
```

### 2.3 Network Ports

| Port | Protocol | Service | Direction |
|------|----------|---------|-----------|
| 80 | TCP | Nginx (HTTP→HTTPS redirect) | Inbound |
| 443 | TCP | Nginx (HTTPS / gRPC / WebSocket) | Inbound |
| 33073 | TCP | Management gRPC (backward compat) | Inbound |
| 3478 | UDP | STUN server | Inbound |
| 8080 | TCP | Dashboard container (localhost only) | Internal |
| 8081 | TCP | NetBird server container (localhost only) | Internal |

---

## 3. Pre-Requisites

### 3.1 What Was Already In Place
- Azure VM running Ubuntu with Docker & Docker Compose
- Domain `netbirdtest.fincart.com` DNS A record pointing to `4.240.88.63`
- SSL certificates stored at:
  - `/etc/nginx/ssl/netbird_fullchain.pem`
  - `/etc/nginx/ssl/netbird_key.pem`
- Nginx installed and running
- Azure NSG with ports 80, 443, 8080, 10000, 33073 open

### 3.2 Software Installed During Setup
- `jq` (v1.7) — JSON processor required by NetBird scripts

---

## 4. Step-by-Step Deployment

### Step 1: Clean Up Previous Installation

An older legacy NetBird installation (multi-container: management, signal, dashboard, coturn) was running with the management container crash-looping.

```bash
# SSH into the VM
ssh -i sonarvm-key.pem ubuntu@4.240.88.63

# Stop and remove all old containers and volumes
cd /opt/netbird
sudo docker compose down -v

# Clean old configuration files
sudo rm -rf /opt/netbird/*
```

**Output:**
```
Container netbird-coturn-1 Stopped
Container netbird-management-1 Stopped
Container netbird-signal-1 Stopped
Container netbird-dashboard-1 Stopped
Volume netbird_mgmt-data Removed
Volume netbird_signal-data Removed
Network netbird_default Removed
```

---

### Step 2: Download Official Getting-Started Script

```bash
sudo mkdir -p /opt/netbird
cd /opt/netbird
sudo curl -fsSL https://github.com/netbirdio/netbird/releases/latest/download/getting-started.sh \
  -o getting-started.sh
```

---

### Step 3: Run the Installation Script

```bash
export NETBIRD_DOMAIN=netbirdtest.fincart.com
sudo -E bash getting-started.sh
```

When prompted, selected:
- **Reverse proxy**: Option `[2]` — Nginx (generates config template)
- **Docker network**: Empty (Nginx runs on host, not in Docker)

**Script Output:**
```
==========================================
  NGINX SETUP
==========================================

Generated: nginx-netbird.conf

Container ports (bound to 127.0.0.1):
  Dashboard:      8080
  NetBird Server: 8081 (all services)
```

### Step 4: Verify Generated Files

The script generated 4 files in `/opt/netbird/`:

```bash
ls -la /opt/netbird/
```

| File | Size | Purpose |
|------|------|---------|
| `docker-compose.yml` | 916B | Docker Compose with combined netbird-server + dashboard |
| `config.yaml` | 826B | Server configuration (embedded IdP, auth, STUN) |
| `dashboard.env` | 497B | Dashboard environment variables |
| `nginx-netbird.conf` | 3005B | Nginx reverse proxy template |

#### 4a. docker-compose.yml (Final Version)

```yaml
services:
  # UI dashboard
  dashboard:
    image: netbirdio/dashboard:latest
    container_name: netbird-dashboard
    restart: unless-stopped
    networks: [netbird]
    ports:
      - '127.0.0.1:8080:80'
    env_file:
      - ./dashboard.env
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"

  # Combined server (Management + Signal + Relay + STUN)
  netbird-server:
    image: netbirdio/netbird-server:latest
    container_name: netbird-server
    restart: unless-stopped
    networks: [netbird]
    ports:
      - '127.0.0.1:8081:80'
      - '33073:33073'        # gRPC backward compatibility
      - '3478:3478/udp'      # STUN
    volumes:
      - netbird_data:/var/lib/netbird
      - ./config.yaml:/etc/netbird/config.yaml
    command: ["--config", "/etc/netbird/config.yaml"]
    logging:
      driver: "json-file"
      options:
        max-size: "500m"
        max-file: "2"

volumes:
  netbird_data:

networks:
  netbird:
```

> [!IMPORTANT]
> Port `33073:33073` was added manually after initial deployment to support backward-compatible gRPC connections from NetBird clients v0.66.x and earlier.

#### 4b. config.yaml

```yaml
server:
  listenAddress: ":80"
  exposedAddress: "https://netbirdtest.fincart.com:443"
  stunPorts:
    - 3478
  metricsPort: 9090
  healthcheckAddress: ":9000"
  logLevel: "info"
  logFile: "console"

  authSecret: "<auto-generated>"
  dataDir: "/var/lib/netbird"

  auth:
    issuer: "https://netbirdtest.fincart.com/oauth2"
    signKeyRefreshEnabled: true
    dashboardRedirectURIs:
      - "https://netbirdtest.fincart.com/nb-auth"
      - "https://netbirdtest.fincart.com/nb-silent-auth"
    cliRedirectURIs:
      - "http://localhost:53000/"

  reverseProxy:
    trustedHTTPProxies:
      - "172.30.0.10/32"

  store:
    engine: "sqlite"
    encryptionKey: "<auto-generated>"
```

#### 4c. dashboard.env

```env
NETBIRD_MGMT_API_ENDPOINT=https://netbirdtest.fincart.com
NETBIRD_MGMT_GRPC_API_ENDPOINT=https://netbirdtest.fincart.com
AUTH_AUDIENCE=netbird-dashboard
AUTH_CLIENT_ID=netbird-dashboard
AUTH_CLIENT_SECRET=
AUTH_AUTHORITY=https://netbirdtest.fincart.com/oauth2
USE_AUTH0=false
AUTH_SUPPORTED_SCOPES=openid profile email groups
AUTH_REDIRECT_URI=/nb-auth
AUTH_SILENT_REDIRECT_URI=/nb-silent-auth
NGINX_SSL_PORT=443
LETSENCRYPT_DOMAIN=none
```

---

### Step 5: Configure Nginx Reverse Proxy

#### 5a. Update SSL Certificate Paths

```bash
# Update paths in the generated config
sudo sed -i "s|ssl_certificate /path/to/your/fullchain.pem;|ssl_certificate /etc/nginx/ssl/netbird_fullchain.pem;|" \
  /opt/netbird/nginx-netbird.conf
sudo sed -i "s|ssl_certificate_key /path/to/your/privkey.pem;|ssl_certificate_key /etc/nginx/ssl/netbird_key.pem;|" \
  /opt/netbird/nginx-netbird.conf
```

#### 5b. Install Nginx Config

```bash
sudo cp /opt/netbird/nginx-netbird.conf /etc/nginx/sites-available/netbird
sudo ln -sf /etc/nginx/sites-available/netbird /etc/nginx/sites-enabled/netbird
```

#### 5c. Test & Reload

```bash
sudo nginx -t && sudo systemctl reload nginx
```

**Output:**
```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

#### 5d. Final Nginx Configuration

```nginx
upstream netbird_dashboard {
    server 127.0.0.1:8080;
    keepalive 10;
}
upstream netbird_server {
    server 127.0.0.1:8081;
}

server {
    listen 80;
    server_name netbirdtest.fincart.com;
    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name netbirdtest.fincart.com;

    ssl_certificate /etc/nginx/ssl/netbird_fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/netbird_key.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    # Required for long-lived gRPC connections
    client_header_timeout 1d;
    client_body_timeout 1d;

    # WebSocket connections (relay, signal, management)
    location ~ ^/(relay|ws-proxy/) {
        proxy_pass http://netbird_server;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 1d;
    }

    # Native gRPC (signal + management)
    location ~ ^/(signalexchange\.SignalExchange|management\.ManagementService)/ {
        grpc_pass grpc://netbird_server;
        grpc_read_timeout 1d;
        grpc_send_timeout 1d;
        grpc_socket_keepalive on;
    }

    # HTTP routes (API + OAuth2)
    location ~ ^/(api|oauth2)/ {
        proxy_pass http://netbird_server;
        proxy_set_header Host $host;
    }

    # Dashboard (catch-all)
    location / {
        proxy_pass http://netbird_dashboard;
    }
}
```

---

### Step 6: Start Docker Containers

```bash
cd /opt/netbird
sudo docker compose up -d
```

**Output:**
```
Network netbird_netbird Created
Volume netbird_netbird_data Created
Container netbird-dashboard Created
Container netbird-server Created
Container netbird-dashboard Started
Container netbird-server Started
```

#### Verify Container Status

```bash
sudo docker compose ps
```

```
NAME                IMAGE                             STATUS         PORTS
netbird-dashboard   netbirdio/dashboard:latest        Up (stable)    127.0.0.1:8080→80
netbird-server      netbirdio/netbird-server:latest   Up (stable)    127.0.0.1:8081→80,
                                                                     0.0.0.0:3478→3478/udp,
                                                                     0.0.0.0:33073→33073/tcp
```

#### Check Server Logs

```bash
sudo docker compose logs netbird-server
```

```
INFO management/server/account.go:245: single account mode enabled
INFO combined/cmd/root.go:331: Signal server registered on port :80
INFO combined/cmd/root.go:336: Relay WebSocket handler added (path: /relay)
INFO management/internals/server/server.go:220: management server version 0.67.1
INFO combined/cmd/root.go:344: Relay server instance URL: rels://netbirdtest.fincart.com:443
INFO stun/server.go:71: STUN server listening on [::]:3478
```

---

### Step 7: Validate All Endpoints

```bash
# Dashboard (HTTPS)
curl -sk -o /dev/null -w '%{http_code}' https://netbirdtest.fincart.com/
# → 200 ✅

# API (auth challenge)
curl -sk https://netbirdtest.fincart.com/api/accounts
# → {"message":"no valid authentication provided","code":401} ✅

# OAuth2 OIDC Discovery
curl -sk -o /dev/null -w '%{http_code}' https://netbirdtest.fincart.com/oauth2/.well-known/openid-configuration
# → 200 ✅
```

---

### Step 8: Initial Admin Setup

Navigated to `https://netbirdtest.fincart.com` in browser → redirected to `/setup`:
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/a2947cd9-38c3-450f-8ba5-1c132d705dc8" />


Created admin account with:
- Name, Email, and strong password
- Clicked **"Create Admin Account"**

---

### Step 9: Azure AD (Microsoft Entra ID) SSO Integration

After admin login, Azure AD was configured via **Dashboard → Settings → Identity Providers → Add → Microsoft Entra ID**.

#### Azure Portal Configuration:
1. **App Registration** created in Azure AD
2. **Redirect URI** set to the URL provided by NetBird
3. **Client ID** and **Client Secret** generated
4. **Issuer URL**: `https://login.microsoftonline.com/<TENANT_ID>/v2.0`

#### Result — Login Page With Both Options:

<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/270ac0f6-fa37-469b-b0b2-11bf30fa8fba" />


The login page now shows:
- **"Continue with Email"** — Local embedded IdP
- **"Continue with Fincart Azure SSO"** — Azure AD integration

#### Azure AD Sign-In Page:

<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/ec86311e-2dd8-45e4-b939-7227cb03b62b" />


Clicking "Continue with Fincart Azure SSO" redirects to the standard Microsoft Sign-in page.

---

### Step 10: Generate Setup Key

In Dashboard → **Setup Keys** → **Create Setup Key**:
- Assigned name, type (reusable/one-off), and expiry
- Copied the generated key

---

### Step 11: Connect NetBird Client

```bash
# Client version
netbird version
# → 0.66.4

# Connect using setup key
sudo netbird up \
  --management-url https://netbirdtest.fincart.com \
  --setup-key 9FA94E00-823B-472F-B94E-EE14712688E4
```

**Output:**
```
Connected
```

#### Verify Client Status

```bash
sudo netbird status
```

```
OS: linux/amd64
Daemon version: 0.66.4
CLI version: 0.66.4
Profile: default
Management: Connected
Signal: Connected
Relays: 2/2 Available
FQDN: fincart-common-sonarqube-vm-001.netbird.selfhosted
NetBird IP: 100.79.166.156/16
Interface type: Kernel
Peers count: 1/1 Connected
```

✅ **All services connected. Peer visible in dashboard.**

---

## 5. Issue Encountered & Resolution

### Issue: Client Connection Timeout

**Symptom:**
```
Error: unable to get daemon status: rpc error: code = FailedPrecondition 
desc = failed connecting to Management Service : create connection: 
dial context: context deadline exceeded
```

**Root Cause Analysis:**
Client logs showed connection attempts to `4.240.88.63:33073` (the legacy gRPC backward-compatibility port). The `netbird-server` container runs gRPC on port 33073 internally, but this port was **not exposed** in the docker-compose.yml.

**Resolution:**
Added port mapping `33073:33073` to docker-compose.yml:

```diff
    ports:
      - '127.0.0.1:8081:80'
+     - '33073:33073'
      - '3478:3478/udp'
```

Restarted the container:
```bash
cd /opt/netbird && sudo docker compose up -d
```

Client connected successfully after this fix.

---

## 6. Azure NSG Requirements

The following ports must be open in the Azure Network Security Group:

| Rule | Priority | Direction | Protocol | Port | Purpose |
|------|----------|-----------|----------|------|---------|
| Allow-HTTP | 300 | Inbound | TCP | 80 | HTTP→HTTPS redirect |
| Allow-HTTPS | 301 | Inbound | TCP | 443 | Dashboard, API, WebSocket, gRPC |
| Allow-gRPC | 310 | Inbound | TCP | 33073 | Management gRPC (legacy clients) |
| Allow-STUN | 320 | Inbound | UDP | 3478 | STUN (NAT traversal) |
| Allow-TURN | 330 | Inbound | UDP | 49152-65535 | TURN relay (recommended) |

```bash
# Azure CLI commands to open required ports
az network nsg rule create --resource-group <RG> --nsg-name <NSG> \
  --name Allow-STUN-UDP --priority 320 --direction Inbound \
  --access Allow --protocol Udp --destination-port-ranges 3478

az network nsg rule create --resource-group <RG> --nsg-name <NSG> \
  --name Allow-gRPC --priority 310 --direction Inbound \
  --access Allow --protocol Tcp --destination-port-ranges 33073
```

---

## 7. File Locations Reference

| File | Path | Purpose |
|------|------|---------|
| Docker Compose | `/opt/netbird/docker-compose.yml` | Container orchestration |
| Server Config | `/opt/netbird/config.yaml` | NetBird server settings |
| Dashboard Env | `/opt/netbird/dashboard.env` | Dashboard environment |
| Nginx Config | `/etc/nginx/sites-available/netbird` | Reverse proxy |
| SSL Certificate | `/etc/nginx/ssl/netbird_fullchain.pem` | TLS cert chain |
| SSL Key | `/etc/nginx/ssl/netbird_key.pem` | TLS private key |
| NetBird Data | Docker volume `netbird_data` → `/var/lib/netbird` | SQLite DB + state |
| Client Logs | `/var/log/netbird/client.log` | Client-side logs |

---

## 8. Operational Commands

### Daily Operations

```bash
# Check container status
cd /opt/netbird && sudo docker compose ps

# View real-time logs
sudo docker compose -f /opt/netbird/docker-compose.yml logs -f

# Health check
curl http://localhost:9000/health

# Client status
sudo netbird status
```

### Maintenance

```bash
# Restart services
cd /opt/netbird && sudo docker compose restart

# Upgrade to latest version
cd /opt/netbird
sudo docker compose pull
sudo docker compose up -d --force-recreate

# Backup (before upgrades)
sudo docker compose stop netbird-server
sudo docker compose cp -a netbird-server:/var/lib/netbird/ ./backup/
sudo docker compose start netbird-server
```

### Troubleshooting

```bash
# Server logs
sudo docker compose -f /opt/netbird/docker-compose.yml logs --tail=50 netbird-server

# Client logs
sudo tail -100 /var/log/netbird/client.log

# Nginx logs
sudo tail -50 /var/log/nginx/error.log

# Check port bindings
sudo ss -tlnup | grep -E '(8080|8081|33073|3478|443|80)'
```

---

## 9. Next Steps / Recommendations

| # | Action | Priority |
|---|--------|----------|
| 1 | Open UDP 3478 and 49152-65535 in Azure NSG | 🔴 High |
| 2 | Connect additional client peers (Windows, Mac, Linux) | 🟡 Medium |
| 3 | Configure access control policies in Dashboard | 🟡 Medium |
| 4 | Set up network routes for internal resources | 🟡 Medium |
| 5 | Enable JWT group sync with Azure AD groups | 🟢 Low |
| 6 | Set up automated backups for NetBird data | 🟢 Low |
| 7 | Configure DNS within NetBird for internal name resolution | 🟢 Low |
| 8 | Plan production scaling (separate VM, HA) if needed | 🟢 Low |

---

## 10. Summary

| Component | Status | Details |
|-----------|--------|---------|
| NetBird Server | ✅ Running | v0.67.1, combined container |
| Dashboard | ✅ Accessible | `https://netbirdtest.fincart.com` |
| HTTPS/TLS | ✅ Working | Nginx + custom SSL certs |
| Embedded IdP | ✅ Working | Local email auth |
| Azure AD SSO | ✅ Working | "Continue with Fincart Azure SSO" |
| gRPC (management) | ✅ Working | Port 33073 exposed |
| Signal Server | ✅ Connected | Via combined container |
| Relay Server | ✅ Available | 2/2 relays |
| STUN Server | ✅ Listening | UDP 3478 |
| Client Connection | ✅ Connected | 1/1 peers, IP 100.79.166.156/16 |

**POC Status: ✅ SUCCESSFUL**

---

*Document prepared as part of NetBird VPN POC for Fincart infrastructure.*

