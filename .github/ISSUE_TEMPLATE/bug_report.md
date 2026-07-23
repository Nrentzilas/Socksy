---
name: Bug report
about: Something isn't working as expected
title: "[bug] "
labels: bug
---

**What happened**
A clear description of the bug.

**What you expected**
What you thought would happen instead.

**Steps to reproduce**
```bash
socksy ...
```

**Output of `socksy status --json`**
```json
```

**Environment**
- Distro / desktop (e.g. Fedora 43, GNOME):
- socksy version (`socksy --version`):
- gost version (from `socksy status`):
- Proxy type: SOCKS5 / HTTP(S), auth / no-auth, rotating / sticky

**Anything else**
Logs (`journalctl --user -u socksy-relay.service -n 50`), screenshots, etc.
Please redact credentials.
