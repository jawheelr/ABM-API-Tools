# 🍎 Apple Business Manager Device Action Tool

A macOS-based administrative utility for managing Apple Business Manager (ABM) device assignments and releases using Apple Business Manager APIs and Jamf Pro APIs.

Built for Apple device administrators who need a fast, scalable, and user-friendly workflow for:

* ✅ Unassigning devices from ABM MDM servers
* ✅ Releasing (disowning) devices from Apple Business Manager through Jamf Pro
* ✅ Processing single serial numbers or bulk CSV imports
* ✅ Using a modern SwiftDialog-based UI for operator workflows

---

# ✨ Features

## 🔓 ABM Device Unassign

Remove device assignments from an Apple Business Manager MDM server using the Apple Business API.

### Includes:

* ES256 JWT generation
* OAuth token exchange
* Batch processing
* API payload construction
* Serial normalization

---

## 🗑️ Jamf Pro Device Release / Disown

Release devices from Apple Business Manager using Jamf Pro’s Device Enrollment API integration.

### Includes:

* Jamf OAuth authentication
* ADE/DEP enrollment discovery
* Automated Device Enrollment validation
* API token lifecycle management
* Device existence verification before release

---

## 📦 Flexible Input Methods

Supports:

* Single serial number input
* CSV serial import

Serials are automatically:

* Trimmed
* Uppercased
* Sanitized

---

## 🖥️ SwiftDialog UI

Provides a clean and interactive administrator experience with:

* Workflow selection
* Dynamic forms
* Progress bars
* Batch processing status
* Error dialogs
* Completion summaries

---

# 🛠 Requirements

## Operating System

* macOS

---

## Required Applications / Tools

### Required CLI Utilities

The following binaries must exist on the system:

| Tool      | Purpose             |
| --------- | ------------------- |
| `jq`      | JSON parsing        |
| `curl`    | API communication   |
| `openssl` | JWT signing         |
| `xxd`     | Binary conversion   |
| `uuidgen` | JWT JTI generation  |
| `plutil`  | macOS plist parsing |

---

## Required UI Dependency

### SwiftDialog

This script requires:

* [swiftDialog](https://github.com/swiftDialog/swiftDialog)

Expected installation path:

```bash
/usr/local/bin/dialog
```

---

# 🔐 Permissions & API Requirements

## Apple Business Manager API Requirements

For **Unassign (ABM)** workflows, you must have:

### Apple Business Manager:

* API Access enabled
* Business API Client ID
* Key ID
* Private PEM key
* MDM Server ID

### Required Apple API Scope

```text
business.api
```

---

## Jamf Pro API Requirements

For **Release (Disown)** workflows, the Jamf API role must include:

### Required Privileges

| Privilege                                  | Purpose                |
| ------------------------------------------ | ---------------------- |
| Read Device Enrollment Program Instances   | Load ADE instances     |
| Update Device Enrollment Program Instances | Release/disown devices |

---

# 🔄 Workflow Overview

# 1️⃣ Select Action

The administrator chooses:

* `Unassign (ABM)`
* `Release (MDM)`

---

# 2️⃣ Authenticate

Depending on workflow:

## ABM Workflow

Uses:

* ES256 JWT signing
* Apple OAuth token exchange

## Jamf Workflow

Uses:

* Jamf Pro OAuth Client Credentials flow

---

# 3️⃣ Load Devices

Choose:

* Single Serial
* CSV Import

All serials are normalized to uppercase.

---

# 4️⃣ Batch Processing

Devices are processed in configurable batches.

Default:

```bash
BATCH_SIZE=50
```

---

# 5️⃣ Live Progress UI

SwiftDialog displays:

* Current batch
* Total processed
* Success count
* Failure count

---

# 📂 CSV Formatting

CSV imports should contain one serial number per line.

Example:

```text
C02ABC12345
C02ABC67890
C02ABC11111
```

No headers required.

---

# 🧠 Smart Validation

The script includes multiple validation safeguards.

## Jamf ADE Validation

Before release/disown operations:

* Devices are checked against the selected ADE instance
* Missing serials are identified before processing

---

## OAuth Token Validation

The script automatically:

* Refreshes expired tokens
* Invalidates Jamf tokens at exit

---

## Error Handling

Handles:

* Missing dependencies
* Invalid credentials
* Jamf privilege failures
* Invalid ADE session tokens
* Empty serial imports
* API failures

---

# 🚀 Usage

## Make Executable

```bash
chmod +x abm-device-action-tool.sh
```

---

## Run Script

```bash
./abm-device-action-tool.sh
```

---

# 📸 User Experience

The script provides:

* Native macOS dialogs
* Guided administrator workflows
* Interactive progress windows
* Clear error messaging
* Final completion summary

---

## 🧱 Project Structure
```
.
├── assets/
│   └── images
├── docs/
│   └── usage.md
├── examples/
│   └── sample_run.md
├── scripts/
│   ├── Applications (coming soon?)
│   ├── Windows (coming soon?)
│   └── macOS
│      └── abm-device-action-tool.sh
└── README.md
```

---

# 🔐 Security Notes

## Private Key Handling

The PEM key is:

* Loaded locally
* Never uploaded
* Used only for JWT signing

---

## Token Security

Jamf OAuth tokens are:

* Cached temporarily
* Automatically invalidated at script exit

---

# ⚠️ Important Notes

## Unassign vs Release

### Unassign (ABM)

Removes MDM server assignment only.

The device:

* Remains in Apple Business Manager
* Can be reassigned later

---

### Release / Disown (MDM)

Permanently removes the device from Apple Business Manager.

⚠️ This action is irreversible.

Once released:

* The device can no longer be reassigned in ABM
* ADE enrollment is permanently removed

---

# 🧩 Current Limitations

* Jamf Pro is currently the only supported MDM for release/disown
* CSV parsing expects one serial per line
* Requires macOS due to SwiftDialog and Apple tooling

---

# 🛣️ Future Enhancements

Potential roadmap items:

* Support additional MDM vendors
* Improved CSV parsing with headers
* Logging export
* Retry logic for failed batches
* API rate limiting controls
* Dark mode optimized dialogs
* Enhanced reporting output

---

# 👨‍💻 Author

## Jarred Wheeler

Sr. Infrastructure Engineer

---

# 📜 License

MIT License

---

# 🙌 Acknowledgements

* Apple Business Manager API
* Jamf Pro API
* swiftDialog Project
* macOS Admin Community

---

# ⭐ Disclaimer

Use at your own risk.

## _Releasing/disowning devices from Apple Business Manager is permanent and irreversible. Always validate device lists before processing large batches._
