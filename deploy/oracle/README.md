# Pedidos360 DB (branch db)

Oracle runs in the pre-existing rootless Podman container `oracle-free-lite` under Linux user `ubuntu`.

Observed deployment:
- Image: `container-registry.oracle.com/database/free:latest-lite`
- Host port 1521 mapped to container port 1521
- Existing persistent named volume `OracleDBData`, mounted at `/opt/oracle/oradata`
- Service unit `oracle-existing-container.service` starts/stops the **existing** container; it never creates or removes containers or volumes.

Only after inspecting the container and verifying the existing named volume, install the unit on DB host as the `ubuntu` user:

```bash
mkdir -p ~/.config/systemd/user
cp deploy/oracle/oracle-existing-container.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable oracle-existing-container.service
sudo loginctl enable-linger ubuntu
systemctl --user start oracle-existing-container.service
systemctl --user status oracle-existing-container.service --no-pager
podman ps --format 'table {{.Names}}\t{{.Status}}'
```

Do not use `sudo podman`; the container and volume belong to the rootless user. Do not delete `OracleDBData` or create another Oracle container. No credentials belong in Git. Service installation and startup are intentionally separate from publishing these files.
