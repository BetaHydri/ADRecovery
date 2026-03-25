# Active Directory — Object Recovery

> **Author:** Jan Tiedemann | **Version:** 1.0.0 | **Last Updated:** 2026-03-24
>
> **Applies to:** Windows Server 2025, Windows Server 2022, Windows Server 2019, Windows Server 2016

Step-by-step procedure for recovering accidentally deleted Active Directory objects (users, groups, OUs) in the Contoso environment.

## Overview

Deleted AD objects can be recovered using:

1. **Active Directory Administrative Center** (Windows Server 2012+) — simplest method, uses the AD Recycle Bin.
2. **PowerShell** — scriptable recovery from the AD Recycle Bin.
3. **LDP.exe** — manual recovery when the Recycle Bin is not enabled or objects have passed the deleted object lifetime.

> **Prerequisite:** The **Active Directory Recycle Bin** feature must be enabled for methods 1 and 2. Once enabled, it cannot be disabled.

All examples use the domain `contoso.com`. Adjust domain names and distinguished names for your environment.

---

## Prerequisites

- [ ] Active Directory Recycle Bin enabled (recommended)
- [ ] Domain Admin or equivalent permissions
- [ ] Knowledge of the deleted object's name, location, or distinguishing attributes

---

## Method 1 — Active Directory Administrative Center (GUI)

### Step 1 — Open the Deleted Objects Container

- [ ] **1.1** Open **Active Directory Administrative Center** (dsac.exe).
- [ ] **1.2** In the left pane, click the domain name (e.g., `contoso`).
- [ ] **1.3** In the middle pane, double-click **"Deleted Objects"**.

### Step 2 — Restore Objects

- [ ] **2.1** Select the object(s) to restore (hold Ctrl/Shift for multiple selection).
- [ ] **2.2** Right-click and choose:
  - **"Restore"** — restores to the original location.
  - **"Restore To…"** — restores to an alternative OU.
- [ ] **2.3** Verify the restored objects in **Active Directory Users and Computers**.

---

## Method 2 — PowerShell

> **Script:** [`Restore-DeletedADObjects.ps1`](../scripts/Restore-DeletedADObjects.ps1) — automates single-user, SAM account, and OU recovery from the Recycle Bin.

### Recover a Single User

- [ ] **2.1** Find and restore a deleted user by display name:
  ```powershell
  Get-ADObject -Filter {displayName -eq "John Doe"} -IncludeDeletedObjects | Restore-ADObject
  ```
- [ ] **2.2** Verify in **Active Directory Users and Computers**.

### Recover a Single OU and Its Contents

Recovering an OU with nested objects requires restoring in order: top-level OU first, then child objects, then sub-OUs and their children.

**Example:** OU "Sales" contains users (Alice, Bob) and a sub-OU "Sales_Managers" with users (Carol, Dave).

- [ ] **2.3** Restore the top-level OU:
  ```powershell
  Get-ADObject -LDAPFilter "(msDS-LastKnownRDN=Sales)" -IncludeDeletedObjects | Restore-ADObject
  ```

- [ ] **2.4** Verify the OU is restored in AD Users and Computers.

- [ ] **2.5** Restore direct child objects of the OU:
  ```powershell
  Get-ADObject -SearchBase "CN=Deleted Objects,DC=contoso,DC=com" `
    -Filter {lastKnownParent -eq "OU=Sales,DC=contoso,DC=com"} `
    -IncludeDeletedObjects | Restore-ADObject
  ```

- [ ] **2.6** Verify Alice, Bob, and the sub-OU "Sales_Managers" are restored.

- [ ] **2.7** Restore objects inside the sub-OU:
  ```powershell
  Get-ADObject -SearchBase "CN=Deleted Objects,DC=contoso,DC=com" `
    -Filter {lastKnownParent -eq "OU=Sales_Managers,OU=Sales,DC=contoso,DC=com"} `
    -IncludeDeletedObjects | Restore-ADObject
  ```

- [ ] **2.8** Verify Carol and Dave are restored under `Sales_Managers`.

> **Note:** All objects in the Recycle Bin whose `lastKnownParent` matches will be restored — including objects that were intentionally deleted before the accidental OU deletion. Review the results carefully.

---

## Method 3 — LDP.exe (Manual Recovery)

Use this method when the AD Recycle Bin is not available, or for advanced troubleshooting.

### Step 1 — Configure LDP to Show Deleted Objects

- [ ] **1.1** Open LDP.exe (Start → Run → `ldp`).
- [ ] **1.2** Go to **Options** → **Controls**.
- [ ] **1.3** Expand **"Load Predefined"**, select **"Return deleted Objects"**, click **"OK"**.

### Step 2 — Connect and Bind

- [ ] **2.1** Click **Connection** → **Connect** → enter the DC name (e.g., `DC01.contoso.com`).
- [ ] **2.2** Click **Connection** → **Bind** → enter administrative credentials → click **OK**.

### Step 3 — Browse Deleted Objects

- [ ] **3.1** Click **View** → **Tree**.
- [ ] **3.2** Enter the base DN for deleted objects:
  ```
  CN=Deleted Objects,DC=contoso,DC=com
  ```
- [ ] **3.3** Expand the `Deleted Objects` container in the left pane.
- [ ] **3.4** Double-click objects to view their attributes in the right pane.

### Step 4 — Restore via LDP (Modify Operation)

- [ ] **4.1** Right-click the deleted object → **Modify**.
- [ ] **4.2** Set the following attributes:
  | Attribute | Value | Operation |
  |---|---|---|
  | `isDeleted` | *(leave empty)* | **Delete** |
  | `distinguishedName` | `CN=<ObjectName>,OU=<TargetOU>,DC=contoso,DC=com` | **Replace** |
- [ ] **4.3** Check the **"Extended"** checkbox.
- [ ] **4.4** Click **Run** to restore the object.
- [ ] **4.5** Verify the object in **Active Directory Users and Computers**.

---

## Important Notes

| Topic | Details |
|---|---|
| **Recycle Bin Lifetime** | Deleted objects remain recoverable for the tombstone lifetime (default: 180 days). After this period, objects are permanently removed. |
| **Object Attributes** | When restored from the Recycle Bin, all attributes (group memberships, etc.) are preserved. When restored from a tombstone (Recycle Bin disabled), most attributes are lost. |
| **Protected OUs** | If the OU had "Protect object from accidental deletion" enabled, re-enable it after restore. |
| **Group Memberships** | Verify group memberships after restoring user objects — back-links may need time to replicate. |

---

## References

- [Microsoft: Restore Deleted AD Objects](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/component-updates/ad-ds--get-adrecyclebin--step-by-step)
- [Microsoft: Active Directory Recycle Bin](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/get-started/adac/introduction-to-active-directory-administrative-center-enhancements--level-100-#ad_recycle_bin_mgmt)
- [TechNet: Restore Multiple Deleted AD Objects (Script Examples)](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/dd379509(v=ws.10))
