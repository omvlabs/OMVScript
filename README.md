# OmVScript

OmVScript is a modular, script-first provisioning toolkit created by **Om Vataliya (omvlabs)**.  
It allows any Linux system to be converted into different roles such as:

- Developer Workstation  
- Server Host  
- NAS Machine  
- Docker App Host  

It includes:  
• Interactive menus  
• Search bar for apps  
• Install multiple packages at once  
• Deploy Docker apps with port mapping  
• Auto-create persistent data directories  
• Auto-start containers on reboot  
• Curated developer, server, NAS, and Docker environments  

Future Phase → **OmVOS** (your own Linux distribution based on these modules)

---

# ⭐ Quickstart

Always inspect scripts before running them.

```bash
curl -fsSL https://raw.githubusercontent.com/omvlabs/OmVScript/main/install.sh -o /tmp/omvscript-install.sh
less /tmp/omvscript-install.sh
sudo bash /tmp/omvscript-install.sh
```

One-line execution (NOT recommended until you inspect):

```bash
curl -fsSL https://raw.githubusercontent.com/omvlabs/OmVScript/main/install.sh | sudo bash
```

---

# 📁 Repo Structure

OmVScript/
 ├─ install.sh (Main interactive bootstrap installer)
 ├─ modules/
 │   ├─ docker/
 │   │   └─ docker-images.sh (Universal Docker image deployer with search + ports)
 │   ├─ docker-check.sh (Ensures Docker is installed)
 │   ├─ apps/
 │   │   ├─ server-apps.sh (Search-based Server App installer)
 │   │   └─ nas-apps.sh (Search-based NAS App installer)
 │   └─ developer/
 │       └─ dev-packages.sh (Developer environment installer with search)
 ├─ scripts/
 │   └─ generate-sha256sums.sh (Release checksum generator)
 ├─ .github/
 │   └─ workflows/
 │       └─ ci.yml (shellcheck, validations, artifact creation)
 ├─ .gitignore
 └─ README.md (this file)

---

# 🧩 Installer Capabilities

The OmVScript installer allows you to choose categories such as:

1. Developer Environment  
2. Server Apps  
3. NAS Apps  
4. Docker Images  
5. Ensure Docker  
6. Exit  

Inside each category is a **search bar**, allowing you to filter and install items quickly.

### Developer Tools (search & multi-select)
• VS Code  
• Python + venv  
• Node (NVM)  
• Git  
• Go  
• Java (JDK)  
• Pyenv  
• More…

### Server Apps (search & multi-select)
• Portainer  
• CasaOS  
• Traefik  
• Gitea  
• GitLab CE  
• Metabase  
• Vaultwarden  
• Adminer  
• Nginx  
• Apache  
• Postgres  
• Redis  

### NAS Apps (search & multi-select)
• OpenMediaVault (official installer recommended)  
• MinIO  
• Syncthing  
• Duplicati  
• Nextcloud (compose recommended)  
• TrueNAS (not installable on Linux; guidance only)

### Docker Image Deployer (universal module)
• Search curated images  
• Deploy multiple images  
• Set custom ports  
• Auto-create persistent data  
• Restart policies  
• Supports custom images not in the list  

Example features (conceptually):  
- Deploy nginx → maps 80:80 → creates data dir  
- Deploy postgres → prompts for POSTGRES_PASSWORD  
- Deploy redis → maps 6379:6379  
- Deploy custom image:tag → asks for host:container port pair  

---

# 🛡 Idempotency & Safety

• Modules check before reinstalling  
• Containers are not overwritten  
• No destructive disk operations  
• NAS systems like OMV and TrueNAS show warnings instead of forcing installs  
• Everything logs to: `/var/log/omvscript.log`

---

# 🐞 Logging & Troubleshooting

Main log file:

`/var/log/omvscript.log`

If a module fails, you can manually re-run it:

```bash
curl -fsSL https://raw.githubusercontent.com/omvlabs/OmVScript/main/modules/developer/dev-packages.sh -o /tmp/dev.sh
sudo bash /tmp/dev.sh
```

Check container logs:

```bash
docker logs <container-name>
```

---

# 🔐 Security Policy

If you discover a security vulnerability, report it privately:


Do NOT open a public issue for sensitive findings.

Include:  
• Steps to reproduce  
• Impact  
• Logs if possible  
• OS environment  

---

# 🤝 Contributing

Basic rules:  
• Write small, modular scripts  
• Must use `bash` and `set -euo pipefail`  
• No secrets inside code  
• Must run shellcheck clean  
• PRs must have clear descriptions  

---

# 🌈 Code of Conduct (Short)

Be respectful and inclusive.  
Harassment or abusive behavior is not tolerated.  
Report incidents privately to the maintainer.

---

# ⚙️ CI / Release Info

• GitHub Actions run shellcheck  
• Optional SHA256 artifacts are generated using scripts/generate-sha256sums.sh  
• Releases should include SHA256 files so users can verify integrity  

---

Made with ❤️ to simplify provisioning and make Linux automation modular and accessible.
