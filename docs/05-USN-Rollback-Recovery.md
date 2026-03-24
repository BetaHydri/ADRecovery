# Active Directory — USN Rollback Detection and Recovery

> **Applies to:** Windows Server 2025, Windows Server 2022, Windows Server 2019, Windows Server 2016

Step-by-step procedure for detecting and recovering from a USN (Update Sequence Number) rollback on a Windows Server Domain Controller.

## Overview

A **USN rollback** occurs when an older version of the Active Directory database is incorrectly restored or pasted into place — typically by restoring a VM snapshot or disk image instead of using a supported AD-aware backup/restore method.

When a USN rollback happens, modifications on the affected DC do not replicate to other DCs, yet no replication errors are reported. This leads to **silent data inconsistency** across the forest.

> **Reference:** [Microsoft: Detect and Recover from USN Rollback](https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/detect-and-recover-from-usn-rollback)

---

## What Causes USN Rollback?

| Cause | Description |
|---|---|
| VM snapshot restore | Reverting a DC VM to a previous snapshot without using AD-aware restore |
| Disk image copy | Copying a previously saved VHD/VMDK back onto a DC |
| Disk subsystem rollback | SAN or storage-level snapshot rollback of the volume hosting `ntds.dit` |
| Broken mirror boot | Booting from the old half of a broken disk mirror |
| Imaging tools | Using tools like Norton Ghost to restore a DC's OS drive |

> **Windows Server 2012+ with Hyper-V Generation ID:** VMs on Hyper-V (2012+) with Generation ID support detect snapshot restores automatically and reset the Invocation ID, preventing USN rollback. This does **not** apply to other hypervisors unless they also support VM Generation ID.

---

## Symptoms of USN Rollback

- **Event ID 2095** in the Directory Services event log.
- The **Net Logon** service is paused automatically (authentication may fail).
- User/computer accounts created on the affected DC don't appear on other DCs.
- Password changes made on the affected DC are not replicated.
- `repadmin /showreps` may show replication as successful (silent inconsistency).
- Registry key exists:
  ```
  HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NTDS\Parameters
  Value: "Dsa Not Writable" = 0x4
  ```

---

## Prerequisites

- [ ] Access to the affected DC and at least one healthy DC
- [ ] Domain Admin / Enterprise Admin credentials
- [ ] Understanding of which DC is affected (check Event ID 2095)

---

## Step-by-Step Detection

### Step 1 — Check for Event ID 2095

- [ ] **1.1** On the suspected DC, open **Event Viewer** → **Applications and Services Logs** → **Directory Service**.
- [ ] **1.2** Look for **Event ID 2095** with source `Microsoft-Windows-ActiveDirectory_DomainService`.
- [ ] **1.3** The event text will indicate that a remote DC detected the local DC is using already-acknowledged USN numbers.

### Step 2 — Check the Registry

- [ ] **2.1** Open Registry Editor on the affected DC.
- [ ] **2.2** Navigate to:
  ```
  HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NTDS\Parameters
  ```
- [ ] **2.3** Check for the value `Dsa Not Writable`:
  - Value `0x4` = **USN rollback detected**.

> **Warning:** Do **NOT** manually delete or modify the `Dsa Not Writable` value. This would put the DC in a permanently unsupported state with inconsistent AD data.

### Step 3 — Verify Net Logon Service

- [ ] **3.1** Check the Net Logon service status:
  ```cmd
  sc query netlogon
  ```
- [ ] **3.2** If the service is **paused**, this confirms USN rollback quarantine is active.

---

## Step-by-Step Recovery

There are **three approaches** to recover from a USN rollback. Choose the most appropriate one:

---

### Option A — Forcefully Demote and Re-Promote the DC (Recommended)

This is the **safest and most common** approach.

- [ ] **A.1** Force-demote the affected DC:
  ```powershell
  Uninstall-ADDSDomainController -ForceRemoval -DemoteOperationMasterRole
  ```
  > **Note:** On Windows Server 2008/2008 R2, `dcpromo /forceremoval` was used instead. This is not available on Server 2012 and later.

- [ ] **A.2** Shut down the demoted server.

- [ ] **A.3** On a **healthy DC**, clean up the metadata:
  ```cmd
  ntdsutil
  metadata cleanup
  connections
  connect to server <HealthyDC.contoso.com>
  quit
  select operation target
  list domains
  select domain <number>
  list sites
  select site <number>
  list servers in site
  select server <number>
  quit
  remove selected server
  ```
  Or use AD Users and Computers to delete the DC's computer account (with the "permanently offline" option).

- [ ] **A.4** If the affected DC held FSMO roles, seize them on a healthy DC:
  ```powershell
  Move-ADDirectoryServerOperationMasterRole -Identity "HealthyDC" -OperationMasterRole <RoleNumbers> -Force
  ```

- [ ] **A.5** Clean up DNS records for the removed DC.

- [ ] **A.6** Restart the demoted server.

- [ ] **A.7** Re-promote the server as a new Domain Controller:
  ```powershell
  Install-ADDSDomainController -DomainName "contoso.com" -Credential (Get-Credential)
  ```

- [ ] **A.8** If the DC was a **Global Catalog**, re-enable it:
  - AD Sites and Services → NTDS Settings → check "Global Catalog".

- [ ] **A.9** If the DC previously held FSMO roles, transfer them back:
  ```powershell
  Move-ADDirectoryServerOperationMasterRole -Identity "Re-promotedDC" -OperationMasterRole <RoleNumbers>
  ```

- [ ] **A.10** Verify replication:
  ```cmd
  repadmin /showrepl
  dcdiag /q
  ```

---

### Option B — Restore from a Valid System State Backup

Use this if a valid system state backup exists from **before** the USN rollback occurred.

- [ ] **B.1** Verify that a system state backup exists that predates the snapshot/image restore that caused the rollback.
- [ ] **B.2** Boot the affected DC into **Directory Services Restore Mode (DSRM)**:
  - Restart and press **F8** → select **"Directory Services Restore Mode"**.
- [ ] **B.3** Restore the system state:
  ```cmd
  wbadmin start systemstaterecovery -version:<BackupVersion>
  ```
- [ ] **B.4** Restart the DC normally.
- [ ] **B.5** Verify the Invocation ID has been reset:
  ```cmd
  repadmin /showrepl
  ```
  - A new Invocation ID indicates proper recovery.
- [ ] **B.6** Verify replication health:
  ```cmd
  dcdiag /q
  repadmin /showrepl
  ```

---

### Option C — Reset the Invocation ID (Virtual DCs Only)

Use this only for virtual DCs when no system state backup is available.

- [ ] **C.1** Stop the AD DS service:
  ```cmd
  net stop ntds
  ```
- [ ] **C.2** Use `ntdsutil` to set a new Invocation ID:
  ```cmd
  ntdsutil
  activate instance ntds
  files
  set path db "<path_to_ntds.dit>"
  quit
  quit
  ```
  > Consult [Microsoft documentation](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/dd363553(v=ws.10)) for the complete procedure.
- [ ] **C.3** Restart the AD DS service:
  ```cmd
  net start ntds
  ```
- [ ] **C.4** Verify replication with:
  ```cmd
  repadmin /showrepl
  dcdiag /q
  ```

---

## Prevention Best Practices

| Practice | Description |
|---|---|
| **Never restore VM snapshots** on DCs | Use only AD-aware backup tools (Windows Server Backup, DPM, etc.) |
| **Use VM Generation ID** | Ensure your hypervisor supports Generation ID (Hyper-V 2012+, VMware 6.7+) |
| **Disable snapshots** for DC VMs | Configure hypervisor policies to prevent accidental snapshot creation |
| **Monitor Event ID 2095** | Set up alerts for this event across all DCs |
| **Regular AD backups** | Maintain system state backups within the tombstone lifetime |
| **Document restore procedures** | Ensure all administrators know to use AD-aware restore methods only |

---

## References

- [Microsoft: Detect and Recover from USN Rollback (KB875495)](https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/detect-and-recover-from-usn-rollback)
- [Microsoft: Virtualized Domain Controller Deployment and Configuration](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/get-started/virtual-dc/virtualized-domain-controller-deployment-and-configuration)
- [Microsoft: AD DS in Virtual Hosting Environments](https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/ad-dc-in-virtual-hosting-environment)
- [Microsoft: Clean up AD DS Server Metadata](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/deploy/ad-ds-metadata-cleanup)
- [Microsoft: Transfer or Seize FSMO Roles](https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/transfer-or-seize-operation-master-roles-in-ad-ds)
