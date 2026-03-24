# Active Directory — Forest Recovery

> **Author:** Jan Tiedemann (Microsoft) | **Version:** 1.0.0 | **Last Updated:** 2026-03-24
>
> **Applies to:** Windows Server 2025, Windows Server 2022, Windows Server 2019, Windows Server 2016

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
- [ ] **2.1.4** Select the OS version if prompted (e.g., **Windows Server 2022** or **Windows Server 2025**).
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
- [ ] **2.3.3** If **gMSA (Group Managed Service Accounts)** are in use, plan to re-create them — an attacker may have retrieved the KDS root key, enabling a [Golden gMSA attack](https://learn.microsoft.com/en-us/troubleshoot/windows-server/windows-security/recover-from-golden-gmsa-attack).

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
- [ ] **2.4.6** If this DC holds **FSMO roles**, set the following registry value so the DC does not wait for initial replication before advertising:
  ```
  HKLM\System\CurrentControlSet\Services\NTDS\Parameters
  Value: "Repl Perform Initial Synchronizations" (REG_DWORD) = 0
  ```
  > Reset this value to **1** (or delete the entry) after the forest is fully recovered.

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
- [ ] **2.5.8** Speed up DNS SRV record removal for each deleted DC:
  ```cmd
  nltest /dsderegdns:<DeletedDC.contoso.com>
  ```

### Step 2.6 — Reset the RID Pool

- [ ] **2.6.1** Open properties of `CN=RID Manager$,CN=System,DC=contoso,DC=com` (Advanced View).
- [ ] **2.6.2** Edit `rIDAvailablePool` — raise the upper 32-bit value by at least **100,000** (Microsoft recommendation).
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

### Step 3.1 — Restore Child Domain PDC Emulator from Backup

The procedure below is for one child domain (e.g., `DC-CHILD01.corp.contoso.com`). **Repeat for every child domain** in the forest.

- [ ] **3.1.1** Boot `DC-CHILD01` from Windows Server installation media.
- [ ] **3.1.2** Set NIC type to **E1000** (VMs).
- [ ] **3.1.3** Select **"Repair your computer"** → **"Troubleshoot"** → **"System Image Recovery"**.
- [ ] **3.1.4** Select the backup to restore (most recent or a specific image). For network backups: **"Advanced"** → **"Search for a System Image on the Network"**.
- [ ] **3.1.5** Enable **format/repartition** if needed; disable **"Auto restart after restore"**. Click **"Finish"** and wait.

### Step 3.2 — Post-Restore Verification (Offline)

- [ ] **3.2.1** **Disconnect** the child DC from the network.
- [ ] **3.2.2** Log on as `contoso\Administrator` (Enterprise Admin account from the forest root).
- [ ] **3.2.3** Verify IP address, gateway, and DNS settings on the network adapter.
- [ ] **3.2.4** Open **Active Directory Users and Computers** — confirm the child domain directory is accessible. On name resolution issues run `ipconfig /flushdns`.
- [ ] **3.2.5** Verify SYSVOL and NETLOGON shares are present:
  ```cmd
  net share
  ```
- [ ] **3.2.6** Run `whoami /all` — confirm the account is RID-500 and a member of **Domain Admins**.

### Step 3.3 — Reset Passwords (if Security Incident)

> Skip this step if the recovery is **not** related to a security breach.

- [ ] **3.3.1** Reset the child domain's `krbtgt` password:
  ```cmd
  net user krbtgt <NewPassword> /domain
  ```
- [ ] **3.3.2** Reset the `krbtgt` password a **second time** (this invalidates all existing Kerberos tickets, forcing clients to re-authenticate):
  ```cmd
  net user krbtgt <AnotherNewPassword> /domain
  ```

> **Why twice?** Active Directory keeps the current and previous krbtgt password hashes. Resetting twice ensures both hashes are replaced, fully invalidating any stolen tickets.

- [ ] **3.3.3** If **gMSA (Group Managed Service Accounts)** are in use in this child domain, plan to re-create them — see [Golden gMSA attack recovery](https://learn.microsoft.com/en-us/troubleshoot/windows-server/windows-security/recover-from-golden-gmsa-attack).

### Step 3.4 — Authoritative SYSVOL Restore (DFS-R)

- [ ] **3.4.1** In **Active Directory Users and Computers**, enable **View** → **Advanced Features** and **Users, Contacts, Groups and Computers as containers**.
- [ ] **3.4.2** Navigate to the child DC's SYSVOL subscription object:
  ```
  Domain Controllers OU
    → DC-CHILD01
      → DFSR-LocalSettings
        → Domain System Volume
          → SYSVOL Subscription
  ```
- [ ] **3.4.3** Open the **Attribute Editor** tab and set:
  - `msDFSR-Options` = **1** (marks this DC as the authoritative SYSVOL source for the child domain)
  - `msDFSR-Enabled` = **TRUE**
- [ ] **3.4.4** Restart the DFS Replication service:
  ```cmd
  sc stop dfsr
  sc start dfsr
  ```
- [ ] **3.4.5** Open **Event Viewer** → **Applications and Services Logs** → **DFS Replication**:
  - **Event 4602** = SYSVOL initialized successfully (expected).
  - **Event 5008** = no replication partner found (expected — other DCs are offline).
- [ ] **3.4.6** If this child DC holds **FSMO roles**, set the registry value to skip initial sync wait:
  ```
  HKLM\System\CurrentControlSet\Services\NTDS\Parameters
  Value: "Repl Perform Initial Synchronizations" (REG_DWORD) = 0
  ```
  > Reset to **1** after forest recovery is complete.

### Step 3.5 — Remove Metadata of Non-Restored Child Domain DCs

- [ ] **3.5.1** Identify current FSMO role holders in the child domain:
  ```cmd
  netdom query fsmo
  ```
- [ ] **3.5.2** In **Active Directory Users and Computers**, delete the computer accounts of all non-restored child domain DCs:
  - Check *"This Domain Controller is permanently offline and can no longer be demoted using DCPROMO"*.
  - Delete DCs that do **not** hold FSMO roles first.
  - Then delete remaining non-restored FSMO-holding DCs (confirm the role transfer warning).
- [ ] **3.5.3** In **Active Directory Sites and Services**, right-click and delete the server entries for each removed DC. Confirm any warnings.
- [ ] **3.5.4** Verify that FSMO roles were automatically transferred to `DC-CHILD01`:
  ```cmd
  netdom query fsmo
  ```

### Step 3.6 — Seize FSMO Roles (if Not Auto-Transferred)

If `netdom query fsmo` still shows a deleted DC as a role holder:

- [ ] **3.6.1** Open an administrative PowerShell console and seize the three child-domain roles:
  ```powershell
  Move-ADDirectoryServerOperationMasterRole -Identity "DC-CHILD01" -OperationMasterRole PDCEmulator, RIDMaster, InfrastructureMaster -Force
  ```
  > **Note:** Child domains hold 3 roles (PDCEmulator, RIDMaster, InfrastructureMaster). The forest-wide roles (SchemaMaster, DomainNamingMaster) are only in the forest root domain.
- [ ] **3.6.2** Confirm:
  ```cmd
  netdom query fsmo
  ```

### Step 3.7 — Clean Up DNS Records

- [ ] **3.7.1** Open **DNS Manager** on the child DC.
- [ ] **3.7.2** In the forward lookup zone for `corp.contoso.com`, delete all **A**, **AAAA**, and **SRV** records pointing to removed DCs.
- [ ] **3.7.3** In the `_msdcs.contoso.com` zone, delete records for removed DCs (search under `_tcp`, `_udp`, `_sites`, `dc`, `gc`, `pdc`).
- [ ] **3.7.4** In the reverse lookup zone, delete **PTR** records for removed DCs.
- [ ] **3.7.5** Open Properties of each DNS zone → **Name Servers** tab → remove entries for deleted DCs.

### Step 3.8 — Reset the RID Pool for the Child Domain

> **Why?** After a restore, the DC may try to assign RIDs (Relative Identifiers) that were already used before the backup. Raising the pool and invalidating the local cache prevents duplicate SID creation.

- [ ] **3.8.1** In **Active Directory Users and Computers** (with **Advanced Features** enabled), navigate to:
  ```
  corp.contoso.com → System → RID Manager$
  ```
  Or locate it via ADSI Edit / Attribute Editor at:
  ```
  CN=RID Manager$,CN=System,DC=corp,DC=contoso,DC=com
  ```
- [ ] **3.8.2** Open the **Attribute Editor** tab and edit the `rIDAvailablePool` attribute:
  - The value is a 64-bit number. The **upper 32 bits** represent the pool ceiling. Increase it by **100,000** (Microsoft recommendation) to ensure no overlap with previously issued RIDs.
  - Example: If the current value is `4611686014132422708`, calculate the new value by adding `10000 × 2^32` to the existing value using a calculator or PowerShell:
    ```powershell
    # Read current value, then compute the new ceiling
    # Example — adjust to your actual value:
    $current = 4611686014132422708
    $increment = 100000 * [math]::Pow(2, 32)
    $new = $current + $increment
    Write-Host "New rIDAvailablePool value: $new"
    ```
- [ ] **3.8.3** Invalidate the DC's local RID cache so it requests a fresh pool:
  ```powershell
  $Domain = New-Object System.DirectoryServices.DirectoryEntry
  $DomainSid = $Domain.objectSid
  $RootDSE = New-Object System.DirectoryServices.DirectoryEntry("LDAP://RootDSE")
  $RootDSE.UsePropertyCache = $false
  $RootDSE.Put("invalidateRidPool", $DomainSid.Value)
  ```
- [ ] **3.8.4** Verify by creating a test user in **Active Directory Users and Computers**:
  - An error on the first attempt is **expected** — it means a new RID pool is being allocated.
  - Try creating the user again — it should succeed now.
  - Delete the test user afterwards.

### Step 3.9 — Reset the Computer Account Password (Twice)

> **Why twice?** The DC's machine account password is used for secure channel communication. After a restore, the password stored in AD may not match the local password. Resetting it twice ensures both the current and previous password slots are updated, preventing Kerberos authentication issues.

- [ ] **3.9.1** Open an administrative PowerShell console on the child DC.
- [ ] **3.9.2** Run the reset command **two times**, waiting a few seconds between each:
  ```powershell
  Reset-ComputerMachinePassword
  Reset-ComputerMachinePassword
  ```

### Step 3.10 — Reset Trust Passwords Between Child Domain and Forest Root

> **Why?** The trust between the child domain and the forest root uses a shared password. After restoring from backup, this password is out of sync, causing trust validation failures.

- [ ] **3.10.1** On the **child DC**, reset the trust to the forest root domain:
  ```cmd
  netdom trust corp.contoso.com /domain:contoso.com /resetOneSide /passwordT:<TrustPassword> /userO:contoso\Administrator /passwordO:*
  ```
  > Replace `<TrustPassword>` with a new strong password. You will be prompted for the password of `contoso\Administrator`.

- [ ] **3.10.2** On the **forest root DC**, reset the trust from its side (both sides must use the **same** `<TrustPassword>`):
  ```cmd
  netdom trust contoso.com /domain:corp.contoso.com /resetOneSide /passwordT:<TrustPassword> /userO:corp\Administrator /passwordO:*
  ```

- [ ] **3.10.3** If the child domain has trusts with other forests or external domains, reset those as well using the same `netdom trust` pattern.

- [ ] **3.10.4** Verify the trust (after network reconnection in Phase 4):
  ```cmd
  nltest /sc_verify:contoso.com
  ```

### Step 3.11 — Remove Global Catalog Temporarily

> **Why?** The Global Catalog on the restored DC contains stale data from the backup. Removing the GC flag forces a full rebuild of the partial attribute set from replication after reconnection, ensuring consistency.

- [ ] **3.11.1** Open **Active Directory Sites and Services**.
- [ ] **3.11.2** Navigate to: **Sites** → *your site* → **Servers** → **DC-CHILD01** → **NTDS Settings**.
- [ ] **3.11.3** Right-click **NTDS Settings** → **Properties**.
- [ ] **3.11.4** **Uncheck** the **"Global Catalog"** checkbox → click **OK**.

> The GC will be re-enabled in Phase 4 (Step 4.5) after replication is confirmed healthy.

### Step 3.12 — Configure Time Synchronization

> **Why?** Kerberos authentication fails if the time difference between a DC and a client exceeds 5 minutes. After a restore, the DC's clock may be at the backup timestamp instead of the current time.

- [ ] **3.12.1** Open Registry Editor and verify time correction limits:
  ```
  HKLM\SYSTEM\CurrentControlSet\Services\W32Time\Config
  ```
  - `MaxNegPhaseCorrection` = **172800** (allows up to 48 hours backward correction)
  - `MaxPosPhaseCorrection` = **172800** (allows up to 48 hours forward correction)

- [ ] **3.12.2** Set the time source type:
  ```
  HKLM\SYSTEM\CurrentControlSet\Services\W32Time\Parameters\Type
  ```
  - Set to **NT5DS** (child domain DCs synchronize time from the forest root PDC Emulator via the domain hierarchy).
  - **Only** the forest root PDC Emulator uses **NTP** (configured in Phase 2, Step 2.10).

- [ ] **3.12.3** Restart the Windows Time service:
  ```cmd
  net stop w32time
  net start w32time
  w32tm /resync
  ```

> **The child DC must remain disconnected from the network until all child domains have completed Steps 3.1–3.12.**

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
- [ ] **5.2** Promote to Domain Controller via Server Manager or PowerShell:
  ```powershell
  Install-ADDSDomainController -DomainName "contoso.com" -Credential (Get-Credential)
  ```
  > On **Windows Server 2022/2025**, you can alternatively use **virtualized DC cloning** to rapidly deploy additional DCs. See [Microsoft: Virtualized Domain Controller Deployment](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/get-started/virtual-dc/virtualized-domain-controller-deployment-and-configuration).
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
