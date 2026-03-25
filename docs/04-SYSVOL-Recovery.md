# Active Directory — Authoritative SYSVOL Restore (DFS-R)

> **Author:** Jan Tiedemann | **Version:** 1.0.0 | **Last Updated:** 2026-03-24
>
> **Applies to:** Windows Server 2025, Windows Server 2022, Windows Server 2019, Windows Server 2016

Step-by-step procedure for performing an authoritative DFS-R SYSVOL synchronization when SYSVOL is corrupt, inconsistent, or missing on Domain Controllers.

## Overview

During an authoritative SYSVOL restore, the DFS-R service is stopped on all DCs, one DC is marked as the authoritative source, and all other DCs perform a non-authoritative (initial) replication from it. This ensures a clean, consistent SYSVOL across the domain.

> **Reference:** [Microsoft: Force Authoritative and Non-Authoritative Synchronization for DFSR-Replicated SYSVOL](https://support.microsoft.com/en-us/help/2218556)

---

## Prerequisites

- [ ] Identify the DC with the most current and valid SYSVOL content
- [ ] Domain Admin credentials
- [ ] Access to **Active Directory Users and Computers** or **ADSI Edit**
- [ ] Administrative command prompt on all DCs

---

## Step-by-Step Procedure

### Step 1 — Identify the Authoritative DC

> **Script:** [`Find-AuthoritativeDC.ps1`](../scripts/Find-AuthoritativeDC.ps1) — automates step 1 by inspecting all DCs and recommending the best candidate.

- [ ] **1.1** Determine which Domain Controller has the correct/current SYSVOL content.
  - This will be the **authoritative source** (e.g., `DC01.contoso.com`).

  **How to identify the correct DC:**

  **a) Compare SYSVOL content across DCs**

  List the policies and scripts in the SYSVOL share on each DC and compare file counts, sizes, and timestamps:
  ```powershell
  # Run on each DC or remotely against each DC's SYSVOL share
  Get-ChildItem "\\DC01\SYSVOL\contoso.com\Policies" -Recurse | Measure-Object -Property Length -Sum
  Get-ChildItem "\\DC02\SYSVOL\contoso.com\Policies" -Recurse | Measure-Object -Property Length -Sum
  ```
  The DC with the most complete and up-to-date set of Group Policy Objects (GPOs) and scripts is typically the best candidate.

  **b) Check the PDC Emulator role holder**

  The PDC Emulator is the default authoritative source for Group Policy editing and SYSVOL changes. Unless it was compromised or rebuilt, it usually holds the most current content:
  ```powershell
  Get-ADDomain | Select-Object -ExpandProperty PDCEmulator
  ```

  **c) Verify DFS-R replication health**

  Check which DCs have a healthy DFS-R state and recent successful replication:
  ```powershell
  # List DFS-R backlog from each DC to the candidate authoritative DC
  dfsrdiag backlog /sendingmember:DC02 /receivingmember:DC01 /rgname:"Domain System Volume" /rfname:"SYSVOL Share"
  ```
  ```powershell
  # Check DFS-R service state on each DC
  Get-Service DFSR -ComputerName DC01, DC02, DC03 | Select-Object MachineName, Status
  ```

  **d) Inspect last-modified timestamps on GPOs**

  Compare the `gPCMachineExtensionNames` or `whenChanged` attributes, or simply check the file system timestamps of `GPT.INI` files across DCs:
  ```powershell
  # Compare GPT.INI timestamps across DCs
  @('DC01','DC02','DC03') | ForEach-Object {
      $path = "\\$_\SYSVOL\contoso.com\Policies\{GPO-GUID}\GPT.INI"
      if (Test-Path $path) {
          [PSCustomObject]@{
              DC           = $_
              LastWriteTime = (Get-Item $path).LastWriteTime
          }
      }
  }
  ```

  **e) Review the DFS Replication event log**

  On each DC, look for recent Event IDs **4602** (successful init), **4604** (initial replication completed), or errors like **4612** (SYSVOL not replicated):
  ```powershell
  Get-WinEvent -LogName "DFS Replication" -MaxEvents 20 |
      Where-Object { $_.Id -in 4602, 4604, 4612, 4614 } |
      Format-Table TimeCreated, Id, Message -Wrap
  ```

  > **Decision rule:** Choose the DC that (1) holds the PDC Emulator role **and** has complete, current SYSVOL content, **or** (2) if the PDC Emulator is unavailable/compromised, the DC with the most recent and complete policy files and a healthy DFS-R state.

- [ ] **1.2** All other DCs will perform non-authoritative sync from this source.
  - Document which DC is selected as authoritative and which DCs are non-authoritative before proceeding.
  - Ensure the authoritative DC is reachable from all other DCs over the network.

---

### Step 2 — Mark the Authoritative DC

> **Script:** [`Set-AuthoritativeSYSVOLRestore.ps1`](../scripts/Set-AuthoritativeSYSVOLRestore.ps1) — automates steps 2.1–2.4.

- [ ] **2.1** Open **Active Directory Users and Computers** on the authoritative DC.
- [ ] **2.2** Enable **"Advanced Features"** and **"Users, Contacts, Groups and Computers as containers"** under the **View** menu.
- [ ] **2.3** Navigate to the authoritative DC's DFS-R subscription object:
  ```
  Domain Controllers OU
    → DC01
      → DFSR-LocalSettings
        → Domain System Volume
          → SYSVOL Subscription
  ```
- [ ] **2.4** Open the **Attribute Editor** tab and set:
  | Attribute | Value |
  |---|---|
  | `msDFSR-Options` | **1** (authoritative) |
  | `msDFSR-Enabled` | **TRUE** |

> **Important:** The `msDFSR-Options` value of **1** marks this DC as the authoritative source for SYSVOL.

---

### Step 3 — Mark All Other DCs as Non-Authoritative

> **Script:** [`Set-NonAuthoritativeSYSVOL.ps1`](../scripts/Set-NonAuthoritativeSYSVOL.ps1) — automates steps 3, 5, 7, and 9.

For **each** other Domain Controller in the domain:

- [ ] **3.1** Navigate to the DC's SYSVOL Subscription object:
  ```
  CN=SYSVOL Subscription,CN=Domain System Volume,CN=DFSR-LocalSettings,CN=<DC Name>,OU=Domain Controllers,DC=contoso,DC=com
  ```
- [ ] **3.2** Set `msDFSR-Enabled` = **FALSE**.
- [ ] **3.3** Leave `msDFSR-Options` **unchanged** (do not modify).

---

### Step 4 — Force AD Replication

- [ ] **4.1** On the authoritative DC, force replication to all partners:
  ```cmd
  repadmin /syncall /d /e /P DC01.contoso.com DC=contoso,DC=com
  ```

---

### Step 5 — Stop DFS-R on Non-Authoritative DCs First

- [ ] **5.1** On each **non-authoritative** DC, stop the DFS Replication service:
  ```cmd
  sc stop dfsr
  ```
- [ ] **5.2** Verify **Event ID 4114** is logged in the **DFS Replication** event log:
  - This indicates SYSVOL is no longer being replicated.

---

### Step 6 — Restart DFS-R on the Authoritative DC

- [ ] **6.1** On the **authoritative** DC, restart the DFS Replication service:
  ```cmd
  sc stop dfsr
  sc start dfsr
  ```
- [ ] **6.2** Verify **Event ID 4602** in the **DFS Replication** event log:
  - This confirms SYSVOL initialization on the authoritative DC.

---

### Step 7 — Re-Enable DFS-R on Non-Authoritative DCs

For **each** non-authoritative DC:

- [ ] **7.1** Navigate to the DC's SYSVOL Subscription object (same path as Step 3.1).
- [ ] **7.2** Set `msDFSR-Enabled` = **TRUE**.

---

### Step 8 — Force AD Replication Again

- [ ] **8.1** Force replication from the authoritative DC:
  ```cmd
  repadmin /syncall /d /e /P DC01.contoso.com DC=contoso,DC=com
  ```

---

### Step 9 — Restart DFS-R on Non-Authoritative DCs

For **each** non-authoritative DC:

- [ ] **9.1** Run:
  ```cmd
  DFSRDIAG POLLAD
  ```
  Or restart the service:
  ```cmd
  sc start dfsr
  ```
- [ ] **9.2** Verify the following events in the **DFS Replication** event log:
  | Event ID | Meaning |
  |---|---|
  | **4614** | DFS-R detected SYSVOL requires initial replication |
  | **4604** | DFS-R successfully completed initial replication |

---

### Step 10 — Verify SYSVOL Shares

- [ ] **10.1** On each DC, verify SYSVOL and NETLOGON are shared:
  ```cmd
  net share
  ```
- [ ] **10.2** Confirm `SYSVOL` and `NETLOGON` appear in the output on every DC.

---

## Troubleshooting

| Symptom | Action |
|---|---|
| SYSVOL share not appearing | Wait for replication to complete; check DFS-R event log for errors. |
| Event 4612 (SYSVOL not replicated) | Ensure `msDFSR-Enabled` = TRUE and DFS-R service is running. |
| Replication timeout | Check network connectivity between DCs; verify AD replication with `repadmin /showrepl`. |

---

## References

- [Microsoft KB2218556: Force Authoritative/Non-Authoritative Sync for DFSR-Replicated SYSVOL](https://support.microsoft.com/en-us/help/2218556)
- [Microsoft: AD Forest Recovery — Perform Authoritative Sync of DFSR-Replicated SYSVOL](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/forest-recovery-guide/ad-forest-recovery-authoritative-recovery-sysvol)
