NetBird Self-Hosted VPN
Proof of Concept (POC) Document

Project
NetBird VPN Self-Hosted Infrastructure
Date
April 7, 2026
Environment
Azure VM (Ubuntu 24.04 LTS)
Domain
https://netbirdtest.fincart.com
Status
Successfully Deployed, Configured & Tested
Version
NetBird v0.67.2


1. Executive Summary
This document covers the end-to-end deployment of a self-hosted NetBird VPN on an Azure VM. NetBird is an open-source WireGuard-based mesh VPN that provides zero-trust network access. The deployment uses the latest combined-container architecture (v0.67.2) with embedded identity provider and Nginx reverse proxy for HTTPS termination. Azure AD (Microsoft Entra ID) SSO has been integrated for enterprise authentication.

In addition to the base VPN setup, this POC also covers dnsmasq-based private DNS resolution, enabling NetBird-connected peers to resolve Azure private endpoints and internal hostnames via URL (not just IP addresses).

1.1 Key Outcomes
    • NetBird Management + Signal + Relay + STUN running in a single container
    • Dashboard accessible via HTTPS at https://netbirdtest.fincart.com
    • Azure AD SSO configured ("Continue with Fincart Azure SSO")
    • Local email-based authentication also available
    • Client successfully connected using setup key
    • 1 peer connected and visible in dashboard
    • dnsmasq deployed as private DNS — resolves Azure SQL, PostgreSQL, and web endpoints
    • All NetBird peers can connect to DBs using domain names (not hardcoded IPs)
    • DNS resolution verified: SQL Server (1433) and PostgreSQL (5432) endpoints working


2. Infrastructure Overview
2.1 Azure VM Details
Property
Value
Hostname
fincart-common-sonarqube-vm-001
OS
Ubuntu 24.04.4 LTS
Public IP
4.240.88.63
NetBird IP
100.79.166.156/16
Domain
netbirdtest.fincart.com
Docker
v29.3.0
Docker Compose
v5.1.0
NetBird Server Version
v0.67.2
dnsmasq IP (eth0 secondary)
10.3.1.5

2.2 Network Ports
Port
Protocol
Service
Direction
80
TCP
Nginx (HTTP→HTTPS redirect)
Inbound
443
TCP
Nginx (HTTPS / gRPC / WebSocket)
Inbound
33073
TCP
Management gRPC (backward compat)
Inbound
3478
UDP
STUN server
Inbound
53
UDP/TCP
dnsmasq DNS (10.3.1.5 + 127.0.0.1)
Internal
8080
TCP
Dashboard container (localhost only)
Internal
8081
TCP
NetBird server container (localhost only)
Internal


3. NetBird VPN Deployment
3.1 Pre-Requisites
    • Azure VM running Ubuntu with Docker & Docker Compose
    • Domain netbirdtest.fincart.com DNS A record pointing to 4.240.88.63
    • SSL certificates stored at /etc/nginx/ssl/
    • Nginx installed and running
    • Azure NSG with ports 80, 443, 33073, 3478 open

3.2 Installation Steps
Step 1: Clean Previous Installation
cd /opt/netbird
sudo docker compose down -v
sudo rm -rf /opt/netbird/*

Step 2: Download & Run Official Script
export NETBIRD_DOMAIN=netbirdtest.fincart.com
sudo -E bash getting-started.sh
When prompted: Reverse proxy → Option [2] Nginx

Step 3: Configure Nginx & Start Containers
sudo cp /opt/netbird/nginx-netbird.conf /etc/nginx/sites-available/netbird
sudo ln -sf /etc/nginx/sites-available/netbird /etc/nginx/sites-enabled/netbird
sudo nginx -t && sudo systemctl reload nginx
cd /opt/netbird && sudo docker compose up -d

Step 4: Connect NetBird Client
sudo netbird up --management-url https://netbirdtest.fincart.com --setup-key <KEY>

3.3 Issue Resolved — gRPC Port 33073
The client initially failed to connect because port 33073 was not exposed in docker-compose.yml. Fix:
ports:
  - '33073:33073'   # Added for gRPC backward compat

3.4 Azure AD SSO Integration
    • App Registration created in Azure AD (Microsoft Entra ID)
    • Redirect URI configured to NetBird dashboard URL
    • Client ID and Secret added to NetBird Dashboard → Settings → Identity Providers
    • Login page now shows both: "Continue with Email" and "Continue with Fincart Azure SSO"

3.5 NetBird Final Status
Component
Status
Details
NetBird Server
Running
v0.67.2, combined container
Dashboard
Accessible
https://netbirdtest.fincart.com
HTTPS/TLS
Working
Nginx + custom SSL certs
Embedded IdP
Working
Local email auth
Azure AD SSO
Working
Continue with Fincart Azure SSO
gRPC (management)
Working
Port 33073 exposed
Signal Server
Connected
Via combined container
Relay Server
Available
2/2 relays
STUN Server
Listening
UDP 3478
Peer Connection
Connected
1/1 peers, IP 100.79.166.156/16


4. dnsmasq Private DNS Setup
To allow NetBird-connected peers to resolve Azure private endpoints using domain names (instead of hardcoded IPs), dnsmasq was deployed on the VPN VM as the authoritative DNS for internal domains.

4.1 Problem Statement
    • Azure private endpoints use internal IPs (10.x.x.x) not accessible publicly
    • Without custom DNS, clients resolve domains to public IPs and connections fail
    • dnsmasq provides per-domain DNS overrides and forwards unknown queries to Azure DNS or public DNS

4.2 Setup Steps
Step 1: Disable systemd-resolved (Free Port 53)
sudo systemctl disable systemd-resolved --now
sudo rm /etc/resolv.conf
echo 'nameserver 127.0.0.1' | sudo tee /etc/resolv.conf
sudo chattr +i /etc/resolv.conf   # Make immutable

Step 2: Add Secondary IP 10.3.1.5 on eth0
# /etc/netplan/99-dnsmasq-bind.yaml
network:
  version: 2
  ethernets:
    eth0:
      addresses: [10.3.1.5/24]
sudo netplan apply

Step 3: Install dnsmasq
sudo apt-get install -y dnsmasq

Step 4: Deploy Config Files
/etc/dnsmasq.d/azure-privatelink.conf
listen-address=127.0.0.1,10.3.1.5
bind-interfaces
server=/database.windows.net/168.63.129.16
server=/privatelink.database.windows.net/168.63.129.16
address=/uatfincart.database.windows.net/10.5.1.4
address=/stagefincart.database.windows.net/10.6.1.5
server=/postgres.database.azure.com/168.63.129.16
server=/privatelink.postgres.database.azure.com/168.63.129.16
address=/fincart-uat-psqldb-001.postgres.database.azure.com/10.5.5.4
address=/fincart-stage-psqldb-001.postgres.database.azure.com/10.6.4.4
address=/fincart-prod-psqldb-001.postgres.database.azure.com/10.7.3.4
server=/privatelink.azurewebsites.net/168.63.129.16
server=/azurewebsites.net/168.63.129.16
address=/uat-workpoint.azurewebsites.net/10.3.1.6
address=/uat-workpoint.fincart.com/10.3.1.6
server=8.8.8.8
cache-size=1000

/etc/dnsmasq.d/mainfincart.conf
address=/mainfincart.database.windows.net/10.7.1.4

Step 5: Start dnsmasq
sudo systemctl enable dnsmasq --now

4.3 Issues Resolved During Setup
Issue 1: dnsmasq not listening on 127.0.0.1
Initial config only had listen-address=10.3.1.5. nslookup was failing because resolv.conf pointed to 127.0.0.1. Fix: Added 127.0.0.1 to listen-address in both dnsmasq.conf and azure-privatelink.conf.

Issue 2: PostgreSQL domains returning NXDOMAIN
postgres.database.azure.com domains were not in dnsmasq config. Azure Private DNS zones also weren't resolving via 168.63.129.16 because Private DNS Zone VNet links were not in scope. Private IPs were retrieved via Azure CLI:
az network private-dns record-set a list --resource-group Fincart_UAT_resources_India \
  --zone-name fincart-uat-psqldb-001-pdz.postgres.database.azure.com \
  --query "[].{Name:name, IP:aRecords[0].ipv4Address}" -o table
Result: IPs hardcoded in dnsmasq config (10.5.5.4, 10.6.4.4, 10.7.3.4).

Issue 3: Port 53 conflict with NetBird
NetBird daemon was already bound to 100.79.166.156:53. Attempting to add this IP to dnsmasq's listen-address caused startup failure. Resolution: dnsmasq bound only to 127.0.0.1 and 10.3.1.5. NetBird Dashboard configured to use 10.3.1.5 as the custom nameserver IP.

4.4 NetBird Dashboard DNS Configuration
To allow all NetBird peers to resolve internal domains using domain names (not IPs), a Custom Nameserver was configured in NetBird Dashboard → DNS → Nameservers:

Field
Value
Name
fincart-dns
Description
Fincart private DNS via dnsmasq VM
Nameserver IP
10.3.1.5
Port
53
Match Domains
database.windows.net, postgres.database.azure.com, azurewebsites.net, fincart.com
Distribution Groups
All
Status
Enabled

After saving and running sudo netbird down && sudo netbird up on client machines, all domain names resolve to private IPs automatically.


5. DNS to Private IP Mapping
5.1 SQL Server (Port 1433)
Domain
Private IP
Resource Group
Status
uatfincart.database.windows.net
10.5.1.4
Fincart_UAT_resources_India
Verified
stagefincart.database.windows.net
10.6.1.5
Fincart_Stage_Resources
Verified
mainfincart.database.windows.net
10.7.1.4
Fincart_Resources_India
Verified

5.2 PostgreSQL (Port 5432)
Domain
Private IP
Private DNS Zone
Status
fincart-uat-psqldb-001.postgres.database.azure.com
10.5.5.4
fincart-uat-psqldb-001-pdz.postgres.database.azure.com
Verified
fincart-stage-psqldb-001.postgres.database.azure.com
10.6.4.4
fincart-stage-psqldb-001.private.postgres.database.azure.com
Verified
fincart-prod-psqldb-001.postgres.database.azure.com
10.7.3.4
fincart-prod-psqldb-001.private.postgres.database.azure.com
Verified

5.3 Web Endpoints
Domain
Private IP
Status
uat-workpoint.azurewebsites.net
10.3.1.6
Verified
uat-workpoint.fincart.com
10.3.1.6
Verified


6. Full Verification Results
6.1 VM-Side Verification
Check
Command
Result
dnsmasq service
systemctl status dnsmasq
active (running)
Port 53 binding
ss -tulnp | grep ':53'
127.0.0.1:53 + 10.3.1.5:53
IP 10.3.1.5 on eth0
ip addr show eth0
Present
resolv.conf immutable
lsattr /etc/resolv.conf
i flag set
NetBird Management
netbird status
Connected
NetBird Signal
netbird status
Connected
NetBird Relays
netbird status
2/2 Available
NetBird Peers
netbird status
1/1 Connected

6.2 DNS Resolution Verification
Domain
Expected IP
Resolved Via
Status
uatfincart.database.windows.net
10.5.1.4
dnsmasq (127.0.0.1)
Verified
stagefincart.database.windows.net
10.6.1.5
dnsmasq (127.0.0.1)
Verified
mainfincart.database.windows.net
10.7.1.4
dnsmasq (127.0.0.1)
Verified
fincart-uat-psqldb-001.postgres...
10.5.5.4
dnsmasq (127.0.0.1)
Verified
fincart-stage-psqldb-001.postgres...
10.6.4.4
dnsmasq (127.0.0.1)
Verified
fincart-prod-psqldb-001.postgres...
10.7.3.4
dnsmasq (127.0.0.1)
Verified
uat-workpoint.azurewebsites.net
10.3.1.6
dnsmasq (127.0.0.1)
Verified
uat-workpoint.fincart.com
10.3.1.6
dnsmasq (127.0.0.1)
Verified
google.com
Public IP
8.8.8.8 fallback
Verified

6.3 Port Connectivity Verification
Host
Port
Result
uatfincart.database.windows.net (10.5.1.4)
1433
Succeeded
stagefincart.database.windows.net (10.6.1.5)
1433
Succeeded
mainfincart.database.windows.net (10.7.1.4)
1433
Succeeded
fincart-uat-psqldb-001.postgres... (10.5.5.4)
5432
Succeeded
fincart-stage-psqldb-001.postgres... (10.6.4.4)
5432
Succeeded
fincart-prod-psqldb-001.postgres... (10.7.3.4)
5432
Succeeded

6.4 Client-Side DNS Verification (Local Machine via NetBird)
After NetBird Dashboard nameserver was set to 10.3.1.5, local machine nslookup results:

Domain
Resolved IP
Status
uatfincart.database.windows.net
10.5.1.4
Verified
fincart-uat-psqldb-001.postgres.database.azure.com
10.5.5.4
Verified
fincart-stage-psqldb-001.postgres.database.azure.com
10.6.4.4
Verified
fincart-prod-psqldb-001.postgres.database.azure.com
10.7.3.4
Verified


7. File Locations Reference
File
Path
Purpose
Docker Compose
/opt/netbird/docker-compose.yml
Container orchestration
Server Config
/opt/netbird/config.yaml
NetBird server settings
Dashboard Env
/opt/netbird/dashboard.env
Dashboard environment
Nginx Config
/etc/nginx/sites-available/netbird
Reverse proxy
SSL Certificate
/etc/nginx/ssl/netbird_fullchain.pem
TLS cert chain
SSL Key
/etc/nginx/ssl/netbird_key.pem
TLS private key
dnsmasq Main Config
/etc/dnsmasq.conf
dnsmasq base config
Azure DNS Config
/etc/dnsmasq.d/azure-privatelink.conf
SQL, PostgreSQL, Web DNS rules
Fincart DNS Config
/etc/dnsmasq.d/mainfincart.conf
mainfincart SQL entry
Netplan Config
/etc/netplan/99-dnsmasq-bind.yaml
Secondary IP 10.3.1.5 on eth0
resolv.conf
/etc/resolv.conf
Points to 127.0.0.1, immutable
NetBird Data
Docker volume netbird_data
SQLite DB + state


8. Operational Commands
8.1 NetBird
# Check container status
cd /opt/netbird && sudo docker compose ps

# View real-time logs
sudo docker compose logs -f netbird-server

# Client status
sudo netbird status

# Restart NetBird client
sudo netbird down && sudo netbird up

8.2 dnsmasq
# Check service
sudo systemctl status dnsmasq

# Restart
sudo systemctl restart dnsmasq

# Check port bindings
sudo ss -tulnp | grep ':53'

# Test DNS resolution
nslookup uatfincart.database.windows.net
nslookup fincart-uat-psqldb-001.postgres.database.azure.com

8.3 Reboot Persistence Check
sudo reboot
# After reboot:
sudo systemctl status dnsmasq
sudo netbird status
dig @10.3.1.5 uatfincart.database.windows.net +short
ip addr show eth0 | grep 10.3.1.5


9. Final Summary
Component
Status
Notes
NetBird Server v0.67.2
Running
Combined container (Mgmt+Signal+Relay+STUN)
Dashboard HTTPS
Accessible
https://netbirdtest.fincart.com
Azure AD SSO
Working
Fincart Azure SSO login enabled
Peer Connection
Connected
1/1 peers, 100.79.166.156
dnsmasq on 127.0.0.1:53
Running
Bound + persistent
dnsmasq on 10.3.1.5:53
Running
NetBird nameserver target
resolv.conf
Immutable
nameserver 127.0.0.1
SQL Server DNS (all 3)
Resolved
10.5.1.4, 10.6.1.5, 10.7.1.4
PostgreSQL DNS (all 3)
Resolved
10.5.5.4, 10.6.4.4, 10.7.3.4
SQL Port 1433 (all 3)
Reachable
nc -zv verified
PostgreSQL Port 5432 (all 3)
Reachable
nc -zv verified
NetBird Dashboard Nameserver
Configured
10.3.1.5 for private domains
Client URL Resolution
Working
Domain names resolve to private IPs
Public DNS Fallback
Working
Via 8.8.8.8
Reboot Persistent
Verified
All services auto-start


POC Status: SUCCESSFUL

Document prepared as part of NetBird VPN POC for Fincart infrastructure.
