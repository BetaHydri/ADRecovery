# Active Directory — Forest Recovery

Step-by-step procedure for recovering the entire Contoso Active Directory forest after a forest-wide failure.

## Overview

In a forest recovery, the **forest root domain DC** is restored first, followed by the PDC Emulator of each child domain. All other DCs are removed via metadata cleanup, then rebuilt and promoted. Trust relationships and FSMO roles are verified at each stage.

> **Reference:** [Microsoft AD Forest Recovery Guide](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/forest-recovery-guide/ad-forest-recovery-guide)

---

## Prerequisites

- [ ] Windows Server installation media
- [ ] Windows Server Backup images for the forest root DC and each child domain's PDC Emulator
- [ ] Enterprise Admin / Domain Admin credentials
- [ ] All existing DCs must be powered off or network-isolated before starting
- [ ] Documented topology: list of all DCs, FSMO role holders, sites, IP addresses

---

## Phase 1 — Identify the Problem and Plan Recovery

- [ ] **1.1** Determine the scope and cause of the failure.
- [ ] **1.2** Evaluate whether full forest recovery is necessary (last resort).
- [ ] **1.3** Identify which DC in each domain holds the best (most recent, clean) backup.
- [ ] **1.4** Isolate all remaining DCs from the network (power off or disconnect).

> **Microsoft guidance:** In many cases, total forest recovery should be the last option. Work with Microsoft Support to evaluate possible remedies.

---

## Phase 2 — Restore the Forest Root Domain Controller

The forest root DC (e.g., `DC-ROOT01.contoso.com`) is restored first.

### Step 2.1 — Restore from Backup

- [ ] **2.1.1** Boot from Windows Server installation media.
- [ ] **2.1.2** Set NIC type to **E1000** (VMs).
- [ ] **2.1.3** Select **"Repair your computer"** → **"Troubleshoot"** → **"System Image Recovery"**.
- [ ] **2.1.4** Select the OS version if prompted (e.g., Windows Server 2016).
- [ ] **2.1.5** Choose the backup to restore:
  - Most recent (default), or click **"Select a System image"** for a specific backup.
  - For network backups: **"Advanced"** → **"Search for a System Image on the Network"**.
- [ ] **2.1.6** Enable **format/repartition** if needed; disable **"Auto restart after restore"**.
- [ ] **2.1.7** Click **"Finish"** and wait for restore to complete.

> `WindowsImageBackup` must be in the root of the backup drive.

### Step 2.2 — Post-Restore Verification (Offline)

- [ ] **2.2.1** **Disconnect** the DC from the network if still connected.
- [ ] **2.2.2** Log on as `contoso\Administrator`.
- [ ] **2.2.3** Verify IP address, gateway, and DNS settings.
- [ ] **2.2.4** Open **Active Directory Users and Computers** — confirm the directory is accessible.
  - On name resolution issues: `ipconfig /flushdns`.
- [ ] **2.2.5** Verify SYSVOL/NETLOGON shares: `net share`.
- [ ] **2.2.6** Run `whoami /all`:
  - Must be the **RID-500** account.
  - Must be a member of **Enterprise Admins**, **Domain Admins**, **Schema Admins**.

### Step 2.3 — Reset Passwords (if Security Incident)

- [ ] **2.3.1** Reset `krbtgt` password:
  ```cmd
  net user krbtgt <NewPassword> /domain
  ```
- [ ] **2.3.2** Reset `krbtgt` password a **second time**.

### Step 2.4 — Authoritative SYSVOL Restore (DFS-R)

- [ ] **2.4.1** In **AD Users and Computers**, enable **Advanced Features** and **containers view**.
- [ ] **2.4.2** Navigate to:
  ```
  Domain Controllers OU → DC-ROOT01 → DFSR-LocalSettings → Domain System Volume → SYSVOL Subscription
  ```
- [ ] **2.4.3** In **Attribute Editor**:
  - Set `msDFSR-Options` = **1**
  - Verify `msDFSR-Enabled` = **TRUE**
- [ ] **2.4.4** Restart DFS-R:
  ```cmd
  sc stop dfsr
  sc start dfsr
  ```
- [ ] **2.4.5** Check Event Viewer → **DFS Replication** log:
  - **Event 4602** = SYSVOL initialized (expected).
  - **Event 5008** = no replication partner found (expected at this stage).

### Step 2.5 — Remove Metadata of Other Forest Root DCs

- [ ] **2.5.1** Run:
  ```cmd
  netdom query fsmo
  ```
- [ ] **2.5.2** In **AD Users and Computers**, delete all non-restored DC computer accounts:
  - Check *"This Domain Controller is permanently offline…"*.
  - Delete non-FSMO holders first, then FSMO holders (confirm role transfer warnings).
- [ ] **2.5.3** Verify FSMO roles transferred:
  ```cmd
  netdom query fsmo
  ```
- [ ] **2.5.4** If not transferred, seize all roles:
  ```powershell
  Move-ADDirectoryServerOperationMasterRole -Identity "DC-ROOT01" -OperationMasterRole 0,1,2,3,4 -Force
  ```
  > `0`=PDCEmulator, `1`=RIDMaster, `2`=InfrastructureMaster, `3`=SchemaMaster, `4`=DomainNamingMaster
- [ ] **2.5.5** In **Active Directory Sites and Services**, remove deleted DC entries.
- [ ] **2.5.6** Remove DNS records of deleted DCs from `_msdcs`, forward, and reverse zones.
- [ ] **2.5.7** Remove deleted DCs from **Name Servers** tab of all DNS zones.

### Step 2.6 — Reset the RID Pool

- [ ] **2.6.1** Open properties of `CN=RID Manager$,CN=System,DC=contoso,DC=com` (Advanced View).
- [ ] **2.6.2** Edit `rIDAvailablePool` — raise the upper 32-bit value.
- [ ] **2.6.3** Invalidate the local RID pool:
  ```powershell
  $Domain = New-Object System.DirectoryServices.DirectoryEntry
  $DomainSid = $Domain.objectSid
  $RootDSE = New-Object System.DirectoryServices.DirectoryEntry("LDAP://RootDSE")
  $RootDSE.UsePropertyCache = $false
  $RootDSE.Put("invalidateRidPool", $DomainSid.Value)
  ```
- [ ] **2.6.4** Create a test user → initial error expected (new pool allocation) → delete test user.

### Step 2.7 — Reset Computer Account Password

- [ ] **2.7.1** Run **twice**:
  ```powershell
  Reset-ComputerMachinePassword
  ```

### Step 2.8 — Reset Trust Passwords

- [ ] **2.8.1** Reset trust password from this domain's side:
  ```cmd
  netdom trust contoso.com /domain:<TrustedDomainName> /resetOneSide /passwordT:<TrustPassword> /userO:<AdminAccount> /passwordO:*
  ```
- [ ] **2.8.2** Reset from the other domain's side (later, after both sides are online):
  ```cmd
  netdom trust <TrustedDomainName> /domain:contoso.com /resetOneSide /passwordT:<TrustPassword> /userO:<AdminAccount> /passwordO:*
  ```

### Step 2.9 — Remove Global Catalog Temporarily

- [ ] **2.9.1** In **AD Sites and Services** → DC-ROOT01 → **NTDS Settings** → uncheck **"Global Catalog"**.

### Step 2.10 — Configure Time Synchronization

- [ ] **2.10.1** Verify registry:
  ```
  HKLM\SYSTEM\CurrentControlSet\Services\W32Time\Config
  ```
  - `MaxNegPhaseCorrection` ≤ **172800**
  - `MaxPosPhaseCorrection` ≤ **172800**
- [ ] **2.10.2** Set time source:
  ```
  HKLM\SYSTEM\CurrentControlSet\Services\W32Time\Parameters\Type
  ```
  - Forest root PDC Emulator: **NTP** (configure an external NTP source)
  - All other DCs: **NT5DS**

> **The forest root DC must remain disconnected from the network until Phase 3 (child domain recovery) is complete.**

---

## Phase 3 — Restore Child Domain Controllers

Repeat this phase for each child domain. The **PDC Emulator** of each child domain is restored first.

### Step 3.1 — Restore Child Domain PDC Emulator

Repeat Steps 2.1 through 2.10 for the child domain DC (e.g., `DC-CHILD01.corp.contoso.com`):

- [ ] **3.1.1** Restore from backup (same procedure as Step 2.1).
- [ ] **3.1.2** Post-restore verification on `corp.contoso.com` domain — log on as `contoso\Administrator`.
- [ ] **3.1.3** Reset passwords if security incident.
- [ ] **3.1.4** Authoritative SYSVOL restore.
- [ ] **3.1.5** Remove metadata of non-restored child domain DCs.
- [ ] **3.1.6** Seize FSMO roles (child domain roles: PDCEmulator, RIDMaster, InfrastructureMaster):
  ```powershell
  Move-ADDirectoryServerOperationMasterRole -Identity "DC-CHILD01" -OperationMasterRole 0,1,2 -Force
  ```
- [ ] **3.1.7** Clean up Sites and Services / DNS.
- [ ] **3.1.8** Reset RID Pool for the child domain.
- [ ] **3.1.9** Reset computer account password (twice).
- [ ] **3.1.10** Reset trust passwords between child domain and forest root.
- [ ] **3.1.11** Remove Global Catalog temporarily.
- [ ] **3.1.12** Configure time source to **NT5DS**.

---

## Phase 4 — Reconnect and Verify the Forest

After all first DCs per domain are restored and old DCs are disconnected:

- [ ] **4.1** Connect all restored DCs to the network.
- [ ] **4.2** Verify DNS configuration (delegations, forwarders, root hints, conditional forwarders).
- [ ] **4.3** Force replication via **Active Directory Sites and Services**.
  - Create temporary manual replication connections if none exist.
- [ ] **4.4** Run diagnostics:
  ```cmd
  repadmin /viewlist *
  repadmin /showrepl
  nltest /dclist:contoso.com
  nltest /dclist:corp.contoso.com
  dcdiag /e /q
  dcdiag /e /test:dns
  ```
- [ ] **4.5** Re-enable **Global Catalog** on all restored DCs:
  - AD Sites and Services → NTDS Settings → check **"Global Catalog"**.
  - Verify **Event ID 1119** in the **Directory Services** event log.
- [ ] **4.6** Verify trust relationships:
  ```cmd
  nltest /sc_verify:contoso.com
  nltest /sc_verify:corp.contoso.com
  ```

---

## Phase 5 — Rebuild Remaining Domain Controllers

- [ ] **5.1** Install fresh Windows Server on each replacement DC.
- [ ] **5.2** Promote to Domain Controller via Server Manager or `Install-ADDSDomainController`.
- [ ] **5.3** Verify replication after each promotion:
  ```cmd
  repadmin /showrepl
  dcdiag /q
  ```
- [ ] **5.4** Restore original DNS server settings on the first restored DCs' network adapters.
- [ ] **5.5** Restore any additional services (DHCP, Certificate Authority, etc.) as needed.

---

## Summary Checklist

| Phase | Description | Status |
|---|---|---|
| 1 | Identify problem and plan | ☐ |
| 2 | Restore forest root DC | ☐ |
| 3 | Restore child domain DCs | ☐ |
| 4 | Reconnect and verify | ☐ |
| 5 | Rebuild remaining DCs | ☐ |

---

## References

- [Microsoft: AD Forest Recovery Guide](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/forest-recovery-guide/ad-forest-recovery-guide)
- [Microsoft: Steps to Restore the Forest](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/forest-recovery-guide/ad-forest-recovery-steps-for-restoring-the-forest)
- [Microsoft: Perform Initial Recovery](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/forest-recovery-guide/ad-forest-recovery-perform-initial-recovery)
- [Microsoft: KB216498 — Remove data after unsuccessful DC demotion](https://support.microsoft.com/en-us/help/216498)
- [Microsoft: Transfer or Seize FSMO Roles](https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/transfer-or-seize-operation-master-roles-in-ad-ds)
