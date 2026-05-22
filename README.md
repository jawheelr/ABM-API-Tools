# 🍎 Apple Business Manager Device Unassign Tool

A macOS Bash utility for bulk unassigning devices from an MDM server in Apple Business Manager using the official Business API.

Designed for enterprise administrators managing large device inventories and integrated with [swiftDialog](https://github.com/swiftDialog/swiftDialog?utm_source=chatgpt.com) for a modern user experience. 🚀

---

# ✨ Features

* 📦 Bulk unassign devices from an MDM server in ABM
* 📄 CSV-driven serial number processing
* 🖥️ Native macOS GUI prompts using `swiftDialog` and `osascript`
* 🔐 ES256 JWT authentication generation
* 🎟️ OAuth2 access token retrieval
* 📚 Batch processing with retry logic
* 📊 Live progress window with success/failure counters
* 🧹 Handles UTF-8 BOM cleanup automatically
* ⏳ Rate limit handling (`HTTP 429`)
* 🏢 Supports large enterprise device inventories safely in batches

---

# 🛠️ Requirements

## 🍏 macOS Dependencies

* Bash
* `jq`
* `openssl`
* `curl`
* `xxd`
* `swiftDialog`

Install `jq` via [Homebrew](https://brew.sh?utm_source=chatgpt.com):

```bash
brew install jq
```

Install `swiftDialog`:

[swiftDialog Releases](https://github.com/swiftDialog/swiftDialog/releases?utm_source=chatgpt.com)

---

# 🔑 Apple Business Manager Requirements

You must have:

* An active Apple Business Manager account
* 🔓 Access to the Business API
* 🔐 A generated API key pair (`.pem`)
* 🪪 Client ID
* 🏷️ Key ID
* 🖧 MDM Server ID

Official documentation:

* [Apple Business Manager API Documentation](https://developer.apple.com/documentation/applebusinessapi?utm_source=chatgpt.com)
* [Apple OAuth Documentation](https://developer.apple.com/documentation/sign_in_with_apple/generate_and_validate_tokens?utm_source=chatgpt.com)

---

# ⚙️ How It Works

## 1️⃣ Prompt for Required Information

The script prompts the administrator for:

* 🪪 Client ID
* 🏷️ Key ID
* 🖧 MDM Server ID
* 🔐 PEM private key
* 📄 CSV file containing serial numbers

---

## 2️⃣ Generate JWT

The script dynamically builds and signs an ES256 JWT using OpenSSL. 🔒

Authentication flow:

```text
PEM Key -> JWT -> OAuth Token -> ABM API Access
```

---

## 3️⃣ Retrieve OAuth Access Token

The JWT is exchanged for a Business API access token via Apple's OAuth endpoint. 🎟️

---

## 4️⃣ Read and Clean CSV

The script:

* 🧹 Removes UTF-8 BOM if present
* ✂️ Trims whitespace
* 🚫 Ignores blank lines
* 📥 Loads serials into memory

CSV format example:

```csv
C02ABCDEFG
C02HIJKLMN
C02OPQRSTU
```

> ⚠️ CSV should contain serial numbers only.

---

## 5️⃣ Batch Processing

Devices are processed in configurable batches. 📦

Default:

```bash
BATCH_SIZE=50
```

Each batch:

* 🏗️ Builds API payload
* 📡 Sends request to ABM
* 🔁 Handles retries
* 📈 Updates progress UI

---

## 6️⃣ Live Progress Window

Uses `swiftDialog` command files to provide:

* 📊 Progress bar
* 📦 Current batch
* 📈 Devices processed
* ✅ Success count
* ❌ Failure count

---

# 🧭 Example Workflow

```text
Launch Script
    ↓
Enter ABM Credentials
    ↓
Select CSV
    ↓
Select PEM Key
    ↓
JWT Generated
    ↓
OAuth Token Retrieved
    ↓
Devices Processed in Batches
    ↓
Completion Summary Displayed
```

---

# 🎨 Configuration

## 🖼️ Branding Variables

Customize icons and overlays:

```bash
sjicon="/opt/stjudeicon.icns"
sjlogo="/opt/sj_logo_icon.png"
```

---

## 📦 Batch Size

Modify batch size depending on API throughput requirements:

```bash
BATCH_SIZE=50
```

---

# 🚨 Error Handling

The script includes handling for:

| Scenario                    | Behavior                |
| --------------------------- | ----------------------- |
| ⚠️ Missing required fields  | Script exits            |
| ❌ Invalid OAuth response    | Displays failure        |
| ⏳ API rate limiting         | Automatic retry         |
| 🚫 Batch submission failure | Counts failed devices   |
| 🧹 UTF-8 BOM CSV issue      | Automatically corrected |

---

# 🔒 Security Notes

* 🔐 Private PEM keys are never uploaded externally except for JWT signing
* 🎟️ Access tokens are generated dynamically at runtime
* 💾 No credentials are stored locally by the script
* ⏱️ OAuth tokens are short-lived

---

# 📡 Example API Payload

```json
{
  "data": {
    "type": "orgDeviceActivities",
    "attributes": {
      "activityType": "UNASSIGN_DEVICES"
    }
  }
}
```

---

# ▶️ Running the Script

Make executable:

```bash
chmod +x abmUnassign.sh
```

Run:

```bash
./abmUnassign.sh
```

---

# 💼 Recommended Use Cases

* 📴 Offboarding devices from MDM
* 🔄 Migrating between MDM platforms
* 🧹 Bulk cleanup of stale device assignments
* 🏢 Enterprise provisioning workflows
* 🤖 Automated operational support tooling

---

# ⚠️ Known Limitations

* 🍏 macOS only
* 🖥️ Requires GUI access for dialogs
* 🔑 Requires valid Apple Business Manager API access
* 📄 Assumes serial-only CSV formatting

---

# 🚀 Future Improvements

Potential enhancements:

* 🏫 Apple School Manager support
* 📝 Logging export
* 📋 Detailed per-device result reporting
* 🔗 Jamf Pro integration
* 🔍 API activity polling
* 🛑 Cancel-safe execution
* ⚡ Parallel batch submission
* 🖱️ Drag-and-drop CSV support

---

# 👨‍💻 Author

Created by Jarred Wheeler 🍏

---

# 📜 License

MIT License

---

# ⚖️ Disclaimer

This project is not affiliated with or endorsed by Apple. Use at your own risk in accordance with your organization's security and operational policies.
