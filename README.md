# Active Directory Recovery Documentation

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Author](https://img.shields.io/badge/author-Jan%20Tiedemann%20(Microsoft)-green)
![License](https://img.shields.io/badge/license-MIT-lightgrey)
![Windows Server](https://img.shields.io/badge/Windows%20Server-2016%20|%202019%20|%202022%20|%202025-0078D4)

> **Author:** Jan Tiedemann (Microsoft) | **Version:** 1.0.0 | **Last Updated:** 2026-03-24 | **Initial release:** not published 2012-04-12
>
> **Applies to:** Windows Server 2025, Windows Server 2022, Windows Server 2019, Windows Server 2016

This repository contains step-by-step recovery procedures for various Active Directory disaster scenarios. All documentation uses the **Contoso** sample environment and should be adapted to your specific topology before use.

## Sample Environment

| Property | Value |
|---|---|
| Forest Root Domain | `contoso.com` |
| Child Domain (example) | `corp.contoso.com` |
| Forest Functional Level | Windows Server 2016 (or higher) |
| Domain Functional Level | Windows Server 2016 (or higher) |
| Domain Controllers | Virtualized Windows Server 2016 / 2019 / 2022 / 2025 |
| Backup Method | Windows Server Backup (Full Server) |

## Recovery Guides

| Guide | Scenario |
|---|---|
| [Domain Recovery](docs/01-Domain-Recovery.md) | Single domain failure — restore one DC, clean up metadata, rebuild remaining DCs |
| [Forest Recovery](docs/02-Forest-Recovery.md) | Forest-wide failure — restore forest root DC first, then child domain DCs |
| [Object Recovery](docs/03-Object-Recovery.md) | Recover accidentally deleted AD objects (users, groups, OUs) from the AD Recycle Bin or authoritative restore |
| [SYSVOL Authoritative Restore](docs/04-SYSVOL-Recovery.md) | Authoritative DFS-R SYSVOL synchronization when SYSVOL is corrupt or inconsistent |
| [USN Rollback Recovery](docs/05-USN-Rollback-Recovery.md) | Detect and recover from USN rollback caused by unsupported snapshot/image restores |

## Prerequisites

- [ ] Active Directory backup strategy in place (Windows Server Backup or equivalent)
- [ ] Windows Server installation media available
- [ ] Administrative credentials (Domain Admin / Enterprise Admin)
- [ ] Network isolation capability (ability to disconnect DCs from the network during restore)
- [ ] Documented list of all Domain Controllers, their roles (FSMO), and IP addresses

## References

- [Microsoft: AD Forest Recovery Guide](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/forest-recovery-guide/ad-forest-recovery-guide)
- [Microsoft: Detect and Recover from USN Rollback](https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/detect-and-recover-from-usn-rollback)
- [Microsoft: AD Forest Recovery — Steps to Restore the Forest](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/forest-recovery-guide/ad-forest-recovery-steps-for-restoring-the-forest)
