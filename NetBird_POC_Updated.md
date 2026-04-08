# NetBird Self-Hosted VPN — Proof of Concept (POC) Document

**Project**: NetBird VPN Self-Hosted Infrastructure
**Date**: April 7, 2026
**Environment**: Azure VM (Ubuntu 24.04 LTS)
**Domain**: https://netbirdtest.fincart.com
**Status**: ✅ Successfully Deployed, Configured & Tested
**Version**: NetBird v0.67.2

---

## 1. Executive Summary

This document covers the end-to-end deployment of a self-hosted NetBird VPN on an Azure VM. NetBird is an open-source WireGuard-based mesh VPN that provides zero-trust network access. The deployment uses the latest combined-container architecture (v0.67.2) with embedded identity provider and Nginx reverse proxy for HTTPS termination. Azure AD (Microsoft Entra ID) SSO has been integrated for enterprise authentication.

In addition to the base VPN setup, this POC also covers dnsmasq-based private DNS resolution, enabling NetBird-connected peers to resolve Azure private endpoints and internal hostnames via URL (not just IP addresses).

### 1.1 Key Outcomes

- ✅ NetBird Management + Signal + Relay + STUN running in a single container
- ✅ Dashboard accessible via HTTPS at `https://netbirdtest.fincart.com`
- ✅ Azure AD SSO configured ("Continue with Fincart Azure SSO")
- ✅ Local email-based authentication also available
- ✅ Client successfully connected using setup key
- ✅ 1 peer connected and visible in dashboard
- ✅ dnsmasq deployed as private DNS — resolves Azure SQL, PostgreSQL, and web endpoints
- ✅ All NetBird peers can connect to DBs using domain names (not hardcoded IPs)
- ✅ DNS resolution verified: SQL Server (1433) and PostgreSQL (5432) endpoints working

---

## 2. Infrastructure Overview

### 2.1 Azure VM Details

| Property | Value |
|----------|-------|
| Hostname | `fincart-common-sonarqube-vm-001` |
| OS | Ubuntu 24.04.4 LTS |
| Public IP | `4.240.88.63` |
| NetBird IP | `100.79.166.156/16` |
| Domain | `netbirdtest.fincart.com` |
| Docker | v29.3.0 |
| Docker Compose | v5.1.0 |
| NetBird Server Version | v0.67.2 |
| dnsmasq IP (eth0 secondary) | `10.3.1.5` |

### 2.2 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        INTERNET                             │
└───────────┬─────────────────┬────────────────┬─────────────┘
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
│ Dashboard  │  │        netbird-server            │
│ (port 8080)│  │  Management + Signal + Relay     │
│            │  │  STUN (UDP 3478)                 │
│            │  │  Embedded IdP (OAuth2)           │
│            │  │  gRPC compat (port 33073)        │
└────────────┘  └──────────────────────────────────┘

NetBird Peers (WireGuard tunnel)
    └── Local Machine (100.x.x.x)
            └── DNS queries → 10.3.1.5:53 (dnsmasq on VM)
                    ├── Internal domains → Private IPs (10.x.x.x)
                    ├── Azure domains → 168.63.129.16
                    └── Public domains → 8.8.8.8
```

### 2.3 Network Ports

| Port | Protocol | Service | Direction |
|------|----------|---------|-----------|
| 80 | TCP | Nginx (HTTP→HTTPS redirect) | Inbound |
| 443 | TCP | Nginx (HTTPS / gRPC / WebSocket) | Inbound |
| 33073 | TCP | Management gRPC (backward compat) | Inbound |
| 3478 | UDP | STUN server | Inbound |
| 53 | UDP/TCP | dnsmasq DNS (10.3.1.5 + 127.0.0.1) | Internal |
| 8080 | TCP | Dashboard container (localhost only) | Internal |
| 8081 | TCP | NetBird server container (localhost only) | Internal |

---

## 3. NetBird VPN Deployment

### 3.1 Pre-Requisites

- Azure VM running Ubuntu with Docker & Docker Compose
- Domain `netbirdtest.fincart.com` DNS A record pointing to `4.240.88.63`
- SSL certificates stored at `/etc/nginx/ssl/`
- Nginx installed and running
- Azure NSG with ports 80, 443, 33073, 3478 open

### 3.2 Installation Steps

#### Step 1: Clean Previous Installation

```bash
cd /opt/netbird
sudo docker compose down -v
sudo rm -rf /opt/netbird/*
```

#### Step 2: Download & Run Official Script

```bash
export NETBIRD_DOMAIN=netbirdtest.fincart.com
sudo curl -fsSL https://github.com/netbirdio/netbird/releases/latest/download/getting-started.sh -o getting-started.sh
sudo -E bash getting-started.sh
# When prompted: Reverse proxy → Option [2] Nginx
```

#### Step 3: Configure Nginx & Start Containers

```bash
sudo cp /opt/netbird/nginx-netbird.conf /etc/nginx/sites-available/netbird
sudo ln -sf /etc/nginx/sites-available/netbird /etc/nginx/sites-enabled/netbird
sudo nginx -t && sudo systemctl reload nginx
cd /opt/netbird && sudo docker compose up -d
```

#### Step 4: Connect NetBird Client

```bash
sudo netbird up \
  --management-url https://netbirdtest.fincart.com \
  --setup-key <YOUR_SETUP_KEY>
```

### 3.3 Issue Resolved — gRPC Port 33073

The client initially failed to connect because port `33073` was not exposed in `docker-compose.yml`.

**Fix** — add to `docker-compose.yml` under `netbird-server` ports:

```yaml
ports:
  - '127.0.0.1:8081:80'
  - '33073:33073'     # Added for gRPC backward compat
  - '3478:3478/udp'
```

Then restart:

```bash
cd /opt/netbird && sudo docker compose up -d
```

### 3.4 Azure AD SSO Integration

- App Registration created in Azure AD (Microsoft Entra ID)
- Redirect URI configured to NetBird dashboard URL
- Client ID and Secret added via Dashboard → Settings → Identity Providers → Microsoft Entra ID
- Login page now shows both: **"Continue with Email"** and **"Continue with Fincart Azure SSO"**

### 3.5 docker-compose.yml (Final)

```yaml
services:
  dashboard:
    image: netbirdio/dashboard:latest
    container_name: netbird-dashboard
    restart: unless-stopped
    networks: [netbird]
    ports:
      - '127.0.0.1:8080:80'
    env_file:
      - ./dashboard.env

  netbird-server:
    image: netbirdio/netbird-server:latest
    container_name: netbird-server
    restart: unless-stopped
    networks: [netbird]
    ports:
      - '127.0.0.1:8081:80'
      - '33073:33073'
      - '3478:3478/udp'
    volumes:
      - netbird_data:/var/lib/netbird
      - ./config.yaml:/etc/netbird/config.yaml
    command: ["--config", "/etc/netbird/config.yaml"]

volumes:
  netbird_data:

networks:
  netbird:
```

### 3.6 NetBird Final Status

| Component | Status | Details |
|-----------|--------|---------|
| NetBird Server | ✅ Running | v0.67.2, combined container |
| Dashboard | ✅ Accessible | https://netbirdtest.fincart.com |
| HTTPS/TLS | ✅ Working | Nginx + custom SSL certs |
| Embedded IdP | ✅ Working | Local email auth |
| Azure AD SSO | ✅ Working | Continue with Fincart Azure SSO |
| gRPC (management) | ✅ Working | Port 33073 exposed |
| Signal Server | ✅ Connected | Via combined container |
| Relay Server | ✅ Available | 2/2 relays |
| STUN Server | ✅ Listening | UDP 3478 |
| Peer Connection | ✅ Connected | 1/1 peers, IP 100.79.166.156/16 |

---

## 4. dnsmasq Private DNS Setup

To allow NetBird-connected peers to resolve Azure private endpoints using domain names (instead of hardcoded IPs), dnsmasq was deployed on the VPN VM as the authoritative DNS for internal domains.

### 4.1 Problem Statement

- Azure private endpoints use internal IPs (10.x.x.x) not accessible publicly
- Without custom DNS, clients resolve domains to public IPs and connections fail or route incorrectly
- dnsmasq provides per-domain DNS overrides and forwards unknown queries to Azure DNS or public DNS

### 4.2 Setup Steps

#### Step 1: Disable systemd-resolved (Free Port 53)

```bash
sudo systemctl disable systemd-resolved --now
sudo rm /etc/resolv.conf
echo 'nameserver 127.0.0.1' | sudo tee /etc/resolv.conf
sudo chattr +i /etc/resolv.conf   # Make immutable — prevents NetBird/cloud-init overwriting it
```

#### Step 2: Add Secondary IP 10.3.1.5 on eth0

Create `/etc/netplan/99-dnsmasq-bind.yaml`:

```yaml
network:
  version: 2
  ethernets:
    eth0:
      addresses: [10.3.1.5/24]
```

```bash
sudo netplan apply
ip addr show eth0 | grep 10.3.1.5   # Verify
```

#### Step 3: Install dnsmasq

```bash
sudo apt-get install -y dnsmasq
```

#### Step 4: Deploy Config Files

**`/etc/dnsmasq.conf`** — add/update:

```
listen-address=127.0.0.1,10.3.1.5
bind-interfaces
```

**`/etc/dnsmasq.d/azure-privatelink.conf`**:

```
listen-address=127.0.0.1,10.3.1.5
bind-interfaces

# SQL Server — forward to Azure DNS
server=/database.windows.net/168.63.129.16
server=/privatelink.database.windows.net/168.63.129.16

# SQL Server — private IP overrides
address=/uatfincart.database.windows.net/10.5.1.4
address=/stagefincart.database.windows.net/10.6.1.5

# PostgreSQL — forward to Azure DNS
server=/postgres.database.azure.com/168.63.129.16
server=/privatelink.postgres.database.azure.com/168.63.129.16

# PostgreSQL — private IP overrides
address=/fincart-uat-psqldb-001.postgres.database.azure.com/10.5.5.4
address=/fincart-stage-psqldb-001.postgres.database.azure.com/10.6.4.4
address=/fincart-prod-psqldb-001.postgres.database.azure.com/10.7.3.4

# Web — forward to Azure DNS
server=/privatelink.azurewebsites.net/168.63.129.16
server=/azurewebsites.net/168.63.129.16

# Web — private IP overrides
address=/uat-workpoint.azurewebsites.net/10.3.1.6
address=/uat-workpoint.fincart.com/10.3.1.6

# Public fallback
server=8.8.8.8
cache-size=1000
```

**`/etc/dnsmasq.d/mainfincart.conf`**:

```
address=/mainfincart.database.windows.net/10.7.1.4
```

#### Step 5: Start dnsmasq

```bash
sudo systemctl enable dnsmasq --now
sudo systemctl status dnsmasq
```

### 4.3 Issues Resolved During Setup

#### Issue 1: dnsmasq not listening on 127.0.0.1

**Symptom:** `nslookup` failing — `connection refused to 127.0.0.1#53`

**Cause:** Initial config only had `listen-address=10.3.1.5`. Since `resolv.conf` pointed to `127.0.0.1`, queries were going nowhere.

**Fix:**
```bash
sudo sed -i 's/^listen-address=.*/listen-address=127.0.0.1,10.3.1.5/' /etc/dnsmasq.conf
sudo sed -i 's/^listen-address=.*/listen-address=127.0.0.1,10.3.1.5/' /etc/dnsmasq.d/azure-privatelink.conf
sudo systemctl restart dnsmasq
```

#### Issue 2: PostgreSQL domains returning NXDOMAIN

**Symptom:** `nslookup fincart-uat-psqldb-001.postgres.database.azure.com` → NXDOMAIN

**Cause:** PostgreSQL domains were not in dnsmasq config. Azure Private DNS zones also weren't resolving via `168.63.129.16` because Private DNS Zone VNet links were not in scope of this VM.

**Fix:** Retrieved private IPs via Azure CLI and hardcoded them:

```bash
az network private-dns record-set a list \
  --resource-group Fincart_UAT_resources_India \
  --zone-name fincart-uat-psqldb-001-pdz.postgres.database.azure.com \
  --query "[].{Name:name, IP:aRecords[0].ipv4Address}" -o table

# Results:
# afbe01f1d143  →  10.5.5.4
# eafbf497dad9  →  10.6.4.4
# de10c163073e  →  10.7.3.4
```

Added `address=/` entries to `azure-privatelink.conf` and restarted dnsmasq.

#### Issue 3: Port 53 conflict with NetBird

**Symptom:** dnsmasq failed to start after adding `100.79.166.156` to `listen-address`:
```
dnsmasq: failed to create listening socket for 100.79.166.156: Address already in use
```

**Cause:** NetBird daemon was already bound to `100.79.166.156:53` for its own DNS handling.

**Fix:** Kept dnsmasq bound only to `127.0.0.1` and `10.3.1.5`. Configured NetBird Dashboard nameserver to use `10.3.1.5` (not `100.79.166.156`) as the DNS target IP.

### 4.4 NetBird Dashboard DNS Configuration

To allow all NetBird peers to use domain names, a Custom Nameserver was added in **NetBird Dashboard → DNS → Nameservers → Add Nameserver → Custom DNS**:

| Field | Value |
|-------|-------|
| Name | `fincart-dns` |
| Description | `Fincart private DNS via dnsmasq VM` |
| Nameserver IP | `10.3.1.5` |
| Port | `53` |
| Match Domains | `database.windows.net`, `postgres.database.azure.com`, `azurewebsites.net`, `fincart.com` |
| Distribution Groups | `All` |
| Status | Enabled |

After saving, clients must reconnect:

```bash
sudo netbird down && sudo netbird up
```

---

## 5. DNS to Private IP Mapping

### 5.1 SQL Server (Port 1433)

| Domain | Private IP | Resource Group | Status |
|--------|-----------|----------------|--------|
| `uatfincart.database.windows.net` | `10.5.1.4` | Fincart_UAT_resources_India | ✅ Verified |
| `stagefincart.database.windows.net` | `10.6.1.5` | Fincart_Stage_Resources | ✅ Verified |
| `mainfincart.database.windows.net` | `10.7.1.4` | Fincart_Resources_India | ✅ Verified |

### 5.2 PostgreSQL (Port 5432)

| Domain | Private IP | Private DNS Zone | Status |
|--------|-----------|-----------------|--------|
| `fincart-uat-psqldb-001.postgres.database.azure.com` | `10.5.5.4` | fincart-uat-psqldb-001-pdz | ✅ Verified |
| `fincart-stage-psqldb-001.postgres.database.azure.com` | `10.6.4.4` | fincart-stage-psqldb-001.private | ✅ Verified |
| `fincart-prod-psqldb-001.postgres.database.azure.com` | `10.7.3.4` | fincart-prod-psqldb-001.private | ✅ Verified |

### 5.3 Web Endpoints

| Domain | Private IP | Status |
|--------|-----------|--------|
| `uat-workpoint.azurewebsites.net` | `10.3.1.6` | ✅ Verified |
| `uat-workpoint.fincart.com` | `10.3.1.6` | ✅ Verified |

---

## 6. Full Verification Results

### 6.1 VM-Side Verification

```bash
# Run all checks at once
echo "=== DNSMASQ SERVICE ===" && \
sudo systemctl status dnsmasq --no-pager | grep -E "Active|Main PID" && \
echo "=== PORT 53 BINDING ===" && \
sudo ss -tulnp | grep ':53' && \
echo "=== IP ADDRESS ===" && \
ip addr show eth0 | grep 'inet ' && \
echo "=== RESOLV.CONF ===" && \
cat /etc/resolv.conf && lsattr /etc/resolv.conf && \
echo "=== NETBIRD STATUS ===" && \
sudo netbird status | grep -E "Management|Signal|Relays|Peers|NetBird IP" && \
echo "=== DNS TESTS ===" && \
nslookup uatfincart.database.windows.net 127.0.0.1 | grep -E "Name|Address" && \
nslookup fincart-uat-psqldb-001.postgres.database.azure.com 127.0.0.1 | grep -E "Name|Address" && \
echo "=== PORT TESTS ===" && \
nc -zv -w 5 uatfincart.database.windows.net 1433 && \
nc -zv -w 5 fincart-uat-psqldb-001.postgres.database.azure.com 5432
```

### 6.2 DNS Resolution Verification

| Domain | Expected IP | Resolved Via | Status |
|--------|------------|-------------|--------|
| `uatfincart.database.windows.net` | `10.5.1.4` | dnsmasq (127.0.0.1) | ✅ |
| `stagefincart.database.windows.net` | `10.6.1.5` | dnsmasq (127.0.0.1) | ✅ |
| `mainfincart.database.windows.net` | `10.7.1.4` | dnsmasq (127.0.0.1) | ✅ |
| `fincart-uat-psqldb-001.postgres...` | `10.5.5.4` | dnsmasq (127.0.0.1) | ✅ |
| `fincart-stage-psqldb-001.postgres...` | `10.6.4.4` | dnsmasq (127.0.0.1) | ✅ |
| `fincart-prod-psqldb-001.postgres...` | `10.7.3.4` | dnsmasq (127.0.0.1) | ✅ |
| `uat-workpoint.azurewebsites.net` | `10.3.1.6` | dnsmasq (127.0.0.1) | ✅ |
| `uat-workpoint.fincart.com` | `10.3.1.6` | dnsmasq (127.0.0.1) | ✅ |
| `google.com` | Public IP | 8.8.8.8 fallback | ✅ |

### 6.3 Port Connectivity Verification

| Host | Port | Result |
|------|------|--------|
| `uatfincart.database.windows.net` (10.5.1.4) | 1433 | ✅ Succeeded |
| `stagefincart.database.windows.net` (10.6.1.5) | 1433 | ✅ Succeeded |
| `mainfincart.database.windows.net` (10.7.1.4) | 1433 | ✅ Succeeded |
| `fincart-uat-psqldb-001.postgres...` (10.5.5.4) | 5432 | ✅ Succeeded |
| `fincart-stage-psqldb-001.postgres...` (10.6.4.4) | 5432 | ✅ Succeeded |
| `fincart-prod-psqldb-001.postgres...` (10.7.3.4) | 5432 | ✅ Succeeded |

### 6.4 Client-Side DNS Verification (Local Machine via NetBird)

After NetBird Dashboard nameserver configured to `10.3.1.5`:

```bash
nslookup uatfincart.database.windows.net
# Server: 127.0.0.53
# Name: uatfincart.database.windows.net
# Address: 10.5.1.4  ✅

nslookup fincart-uat-psqldb-001.postgres.database.azure.com
# Server: 127.0.0.53
# Name: fincart-uat-psqldb-001.postgres.database.azure.com
# Address: 10.5.5.4  ✅
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
| dnsmasq Main Config | `/etc/dnsmasq.conf` | dnsmasq base config |
| Azure DNS Config | `/etc/dnsmasq.d/azure-privatelink.conf` | SQL, PostgreSQL, Web DNS rules |
| Fincart DNS Config | `/etc/dnsmasq.d/mainfincart.conf` | mainfincart SQL entry |
| Netplan Config | `/etc/netplan/99-dnsmasq-bind.yaml` | Secondary IP 10.3.1.5 on eth0 |
| resolv.conf | `/etc/resolv.conf` | Points to 127.0.0.1, immutable |
| NetBird Data | Docker volume `netbird_data` | SQLite DB + state |

---

## 8. Operational Commands

### NetBird

```bash
# Check container status
cd /opt/netbird && sudo docker compose ps

# View real-time logs
sudo docker compose logs -f netbird-server

# Restart containers
cd /opt/netbird && sudo docker compose restart

# Upgrade to latest
cd /opt/netbird && sudo docker compose pull && sudo docker compose up -d --force-recreate

# Client status
sudo netbird status

# Reconnect client
sudo netbird down && sudo netbird up
```

### dnsmasq

```bash
# Check service
sudo systemctl status dnsmasq

# Restart
sudo systemctl restart dnsmasq

# Check port bindings
sudo ss -tulnp | grep ':53'

# Test DNS resolution
nslookup uatfincart.database.windows.net
nslookup fincart-uat-psqldb-001.postgres.database.azure.com

# Debug mode
sudo dnsmasq --no-daemon --log-facility=- 2>&1
```

### Reboot Persistence Check

```bash
sudo reboot

# After reboot run:
sudo systemctl status dnsmasq && \
sudo netbird status && \
dig @10.3.1.5 uatfincart.database.windows.net +short && \
ip addr show eth0 | grep 10.3.1.5
```

### Troubleshooting

| Problem | Debug Command |
|---------|--------------|
| dnsmasq start fail | `sudo dnsmasq --no-daemon --log-facility=- 2>&1` |
| Port 53 conflict | `sudo ss -tulnp | grep ':53'` |
| 10.3.1.5 missing | `ip addr show eth0` |
| NetBird disconnect | `sudo journalctl -u netbird -n 50` |
| resolv.conf changed | `lsattr /etc/resolv.conf` |
| DNS not resolving | `dig @10.3.1.5 uatfincart.database.windows.net +short` |

---

## 9. Azure NSG Requirements

| Rule | Priority | Direction | Protocol | Port | Purpose |
|------|----------|-----------|----------|------|---------|
| Allow-HTTP | 300 | Inbound | TCP | 80 | HTTP→HTTPS redirect |
| Allow-HTTPS | 301 | Inbound | TCP | 443 | Dashboard, API, WebSocket, gRPC |
| Allow-gRPC | 310 | Inbound | TCP | 33073 | Management gRPC (legacy clients) |
| Allow-STUN | 320 | Inbound | UDP | 3478 | STUN (NAT traversal) |
| Allow-TURN | 330 | Inbound | UDP | 49152-65535 | TURN relay (recommended) |

---

## 10. Final Summary

| Component | Status | Notes |
|-----------|--------|-------|
| NetBird Server v0.67.2 | ✅ Running | Combined container (Mgmt+Signal+Relay+STUN) |
| Dashboard HTTPS | ✅ Accessible | https://netbirdtest.fincart.com |
| Azure AD SSO | ✅ Working | Fincart Azure SSO login enabled |
| Peer Connection | ✅ Connected | 1/1 peers, 100.79.166.156 |
| dnsmasq on 127.0.0.1:53 | ✅ Running | Bound + persistent |
| dnsmasq on 10.3.1.5:53 | ✅ Running | NetBird nameserver target |
| resolv.conf | ✅ Immutable | nameserver 127.0.0.1 |
| SQL Server DNS (all 3) | ✅ Resolved | 10.5.1.4, 10.6.1.5, 10.7.1.4 |
| PostgreSQL DNS (all 3) | ✅ Resolved | 10.5.5.4, 10.6.4.4, 10.7.3.4 |
| SQL Port 1433 (all 3) | ✅ Reachable | nc -zv verified |
| PostgreSQL Port 5432 (all 3) | ✅ Reachable | nc -zv verified |
| NetBird Dashboard Nameserver | ✅ Configured | 10.3.1.5 for private domains |
| Client URL Resolution | ✅ Working | Domain names resolve to private IPs |
| Public DNS Fallback | ✅ Working | Via 8.8.8.8 |
| Reboot Persistent | ✅ Verified | All services auto-start |

---

> **POC Status: ✅ SUCCESSFUL**
>
> *Document prepared as part of NetBird VPN POC for Fincart infrastructure.*
