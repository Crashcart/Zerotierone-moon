# TODO

## Review Items

- [ ] **Review Synology | ZeroTier Documentation** — https://docs.zerotier.com/synology/

  Key notes from docs:
  - Synology DSM 7 no longer allows third-party apps to run as root — ZeroTier must be run via **Docker**
  - Install ZeroTier via Docker container (the old Synology SPK package no longer works reliably)
  - The Synology Docker GUI is unreliable; use the **Docker CLI** for all operations
  - After the container starts, use `zerotier-cli` to join a network and authorize the NAS node
  - General NAS docs: https://docs.zerotier.com/nas/
  - Community plugin: https://github.com/yunifyorg/ZeroTierSynology
