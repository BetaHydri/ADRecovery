# Active Directory — Single Domain Recovery

Step-by-step procedure for recovering a single domain within the Contoso Active Directory forest.

## Overview

When a single domain is affected, one Domain Controller is restored from backup. Afterwards, trust passwords are renewed, remaining DCs are cleaned up via metadata removal, and new DCs are promoted to replace them.

---

## Prerequisites

- [ ] Windows Server installation media
- [ ] Windows Server Backup image of the DC to restore (stored on local drive or network share)
- [ ] Administrative credentials (`contoso\Administrator`)
- [ ] Network isolation for the restored DC during recovery

---

## Step-by-Step Procedure

### Step 1 — Restore the Domain Controller from Backup

The target DC (e.g., `DC01`) is restored using Windows Server Backup. Backups of the previous day are stored on drive `I:` of the respective system. If an older backup is needed, retrieve it from your backup system first.

- [ ] **1.1** Boot the server from Windows Server installation media.
- [ ] **1.2** Ensure the network adapter type is set to **E1000** (for virtual machines).
- [ ] **1.3** On the language/keyboard page, click **"Repair your computer"** (do **not** click "Install now").
- [ ] **1.4** Select **"Troubleshoot"** → **"System Image Recovery"**.
- [ ] **1.5** If prompted, select **"Windows Server 2016"** (or the matching OS version).
- [ ] **1.6** Choose the desired backup:
  - Accept the most recent backup (default), **or**
  - Select **"Select a System image"** to pick a specific backup.
  - To restore from a network share, click **"Advanced"** → **"Search for a System Image on the Network"**.
- [ ] **1.7** On the **"Choose additional restore options"** screen:
  - **Enable** the option to format and repartition disks if required.
  - **Disable** the option **"Automatically restart this computer after the restore"**.
- [ ] **1.8** Review the summary and click **"Finish"** to start the restore.
- [ ] **1.9** Wait for the restore to complete.

> **Important:** The `WindowsImageBackup` directory must be in the **root** of the drive, not in a subfolder.

---

### Step 2 — Disconnect from Network and Initial Verification

- [ ] **2.1** If the server was connected to the network during restore, **disconnect it now**.
- [ ] **2.2** Log on with the built-in Administrator account: `contoso\Administrator`.
- [ ] **2.3** Verify IP address, gateway, and DNS settings on the network adapter.
- [ ] **2.4** Open **Active Directory Users and Computers** and verify the directory is functional.
  - If name resolution fails, run `ipconfig /flushdns` and retry.
- [ ] **2.5** Verify SYSVOL is shared:
  ```cmd
  net share
  ```
  Confirm `SYSVOL` and `NETLOGON` shares are listed.
- [ ] **2.6** Run `whoami /all` and verify:
  - The account is the **RID-500** built-in Administrator.
  - The account is a member of **Domain Admins** and **Administrators**.

---

### Step 3 — Reset Passwords (if Security Incident)

> Perform this step only if the recovery is due to a security incident or suspected compromise.

- [ ] **3.1** Reset the **krbtgt** account password:
  ```cmd
  net user krbtgt <NewPassword> /domain
  ```
- [ ] **3.2** Reset the krbtgt password a **second time** (to invalidate both password hashes).

---

### Step 4 — Authoritative SYSVOL Restore (DFS-R)

- [ ] **4.1** Open **Active Directory Users and Computers**.
- [ ] **4.2** Enable **"Advanced Features"** and **"Users, Contacts, Groups and Computers as containers"** under the **View** menu.
- [ ] **4.3** Navigate to:
  ```
  Domain Controllers OU → DC01 → DFSR-LocalSettings → Domain System Volume → SYSVOL Subscription
  ```
- [ ] **4.4** Open the **Attribute Editor** tab:
  - Set `msDFSR-Options` to **1** (authoritative).
  - Ensure `msDFSR-Enabled` is **TRUE**.
- [ ] **4.5** Restart the DFS Replication service:
  ```cmd
  sc stop dfsr
  sc start dfsr
  ```
- [ ] **4.6** Open **Event Viewer** → **Applications and Services Logs → DFS Replication**:
  - Verify **Event ID 4602** is logged (SYSVOL initialization).
  - **Event ID 5008** (no replication partner) is expected at this point.

---

### Step 5 — Remove Metadata of Other Domain Controllers

All non-restored DCs must be removed from Active Directory.

- [ ] **5.1** Identify current FSMO role holders:
  ```cmd
  netdom query fsmo
  ```
- [ ] **5.2** Open **Active Directory Users and Computers**.
- [ ] **5.3** Delete computer accounts of **non-FSMO** DCs first:
  - Enable the option: *"This Domain Controller is permanently offline and can no longer be demoted using the Active Directory Domain Services Installation Wizard (DCPROMO)"*.
  - Confirm with **Delete** and acknowledge any warnings.
- [ ] **5.4** Delete computer accounts of remaining non-restored FSMO-holding DCs:
  - Confirm the additional warning about FSMO role transfer.
- [ ] **5.5** Verify FSMO roles were transferred:
  ```cmd
  netdom query fsmo
  ```
- [ ] **5.6** If roles were **not** transferred, seize them:
  ```powershell
  Move-ADDirectoryServerOperationMasterRole -Identity "DC01" -OperationMasterRole 0,1,2 -Force
  ```
  > Roles: `0` = PDCEmulator, `1` = RIDMaster, `2` = InfrastructureMaster. For the forest root domain, add `3` (SchemaMaster) and `4` (DomainNamingMaster).
- [ ] **5.7** In **Active Directory Sites and Services**, remove server entries for the deleted DCs.
- [ ] **5.8** Remove DNS records for deleted DCs from:
  - `_msdcs` zone
  - Forward lookup zone
  - Reverse lookup zone
- [ ] **5.9** Remove deleted DCs from the **Name Servers** tab of all DNS zones.

---

### Step 6 — Reset the RID Pool

- [ ] **6.1** Open the properties of `CN=RID Manager$,CN=System,DC=corp,DC=contoso,DC=com`.
  - (Enable **Advanced View** and **Users, Contacts, Groups and Computers as containers**.)
- [ ] **6.2** On the **Attribute Editor** tab, edit `rIDAvailablePool` — increase the upper 32 bits to raise the pool.
- [ ] **6.3** Invalidate the current DC's RID pool:
  ```powershell
  $Domain = New-Object System.DirectoryServices.DirectoryEntry
  $DomainSid = $Domain.objectSid
  $RootDSE = New-Object System.DirectoryServices.DirectoryEntry("LDAP://RootDSE")
  $RootDSE.UsePropertyCache = $false
  $RootDSE.Put("invalidateRidPool", $DomainSid.Value)
  ```
- [ ] **6.4** Create a test user in **Active Directory Users and Computers**.
  - An initial error is **expected** — it indicates a new pool is being allocated.
  - Delete the test user afterwards.

---

### Step 7 — Reset Computer Account Password

- [ ] **7.1** Run the following command **twice** in an administrative PowerShell console:
  ```powershell
  Reset-ComputerMachinePassword
  ```

---

### Step 8 — Reset Trust Passwords

- [ ] **8.1** On the restored DC, reset the trust password for each trusted domain:
  ```cmd
  netdom trust corp.contoso.com /domain:<TrustedDomainName> /resetOneSide /passwordT:<TrustPassword> /userO:<AdminAccount> /passwordO:*
  ```
- [ ] **8.2** On each trusted domain, reset the trust from their side:
  ```cmd
  netdom trust <TrustedDomainName> /domain:corp.contoso.com /resetOneSide /passwordT:<TrustPassword> /userO:<AdminAccount> /passwordO:*
  ```

> Replace `<TrustPassword>` with a new password that must match on both sides. Replace `<AdminAccount>` with an administrative account in the respective domain.

---

### Step 9 — Temporarily Remove Global Catalog

- [ ] **9.1** Open **Active Directory Sites and Services**.
- [ ] **9.2** Navigate to the restored DC's site → Servers → DC01 → **NTDS Settings**.
- [ ] **9.3** Open Properties and **uncheck** "Global Catalog".

---

### Step 10 — Configure Time Synchronization

- [ ] **10.1** Verify the following registry values under:
  ```
  HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\W32Time\Config
  ```
  - `MaxNegPhaseCorrection` = **172800** (or less)
  - `MaxPosPhaseCorrection` = **172800** (or less)
- [ ] **10.2** Check the time source type under:
  ```
  HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\W32Time\Parameters\Type
  ```
  - On the **PDC Emulator** of the forest root domain (`contoso.com`): set to **NTP**.
  - On all other DCs: set to **NT5DS**.

> **The Domain Controller must remain disconnected from the network until all steps above are complete.**

---

### Step 11 — Reconnect and Verify

- [ ] **11.1** Connect the restored DC to the network.
- [ ] **11.2** Verify DNS configuration (delegations, forwarders, root hints).
- [ ] **11.3** Force replication via **Active Directory Sites and Services**:
  - If no replication connections exist, create temporary manual connections.
- [ ] **11.4** Run diagnostic commands:
  ```cmd
  repadmin /viewlist *
  repadmin /showrepl
  nltest /dclist:contoso.com
  dcdiag /e /q
  dcdiag /e /test:dns
  ```
- [ ] **11.5** Re-enable **Global Catalog** on the DC:
  - In **Active Directory Sites and Services** → NTDS Settings → check "Global Catalog".
  - Verify **Event ID 1119** in the Directory Services event log.

---

### Step 12 — Rebuild Remaining Domain Controllers

- [ ] **12.1** Install new Windows Server instances.
- [ ] **12.2** Promote each server to Domain Controller using `dcpromo` or **Server Manager**.
- [ ] **12.3** Restore original DNS server configuration on the first DC's network adapter.

---

## References

- [Microsoft: AD Forest Recovery Guide](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/forest-recovery-guide/ad-forest-recovery-guide)
- [Microsoft: KB216498 — How to remove data in AD after an unsuccessful domain controller demotion](https://support.microsoft.com/en-us/help/216498)
- [Microsoft: Transfer or Seize FSMO Roles](https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/transfer-or-seize-operation-master-roles-in-ad-ds)
