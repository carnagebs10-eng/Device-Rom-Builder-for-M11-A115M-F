# Samsung Galaxy M11 Custom ROM Builder

An automated, GitHub Actions-powered tool that builds recovery-flashable custom ROM packages for the **Samsung Galaxy M11 (SM-M115F)** directly from any Generic System Image (GSI).

This builder extracts official Samsung stock AP firmware, deconstructs the dynamic `super.img` partition, swaps the stock system image with your target GSI, and repacks everything into a TWRP-compatible flashable ZIP.

---

## Features

* **Automated Pipeline:** Processes stock firmware and GSI images directly on GitHub cloud runners.
* **Smart Archive Handling:** Automatically detects and extracts `.tar`, `.tar.md5`, `.zip`, `.7z`, `.xz`, and `.lz4` files.
* **Dynamic Partition Packaging:** Unpacks `super.img`, swaps `system.img`, and rebuilds `super.new.img` according to Galaxy M11 partition table specs.
* **Optional Root Integration:** Built-in toggle to inject Magisk v30.7 directly into the flashable ZIP package.
* **Strict Safety Checks:** Error-trapped pipeline prevents corrupt or broken ZIP generation.

---

## Repository Structure

```text
├── .github/
│   └── workflows/
│       └── build.yml          # GitHub Actions workflow configuration
├── scripts/
│   └── build_m11.sh           # Core extraction, swapping, and repacking script
└── tools/                     # Binary utilities, updates, and addons
    ├── android/               # Recovery scripts and binaries
    ├── extra/                 # Super unpacking and repacking utilities
    └── zbin/                  # Configuration files and shell environment tools

```

---

## How to Use

1. Go to the **Actions** tab in your repository.
2. Select **Build Samsung M11 Custom ROM** from the workflow list.
3. Click **Run workflow** and fill in the parameters:
* **Firmware Link:** Direct URL to your Samsung Stock AP file (`.tar`, `.zip`, `.7z`).
* **GSI Link:** Direct URL to your base GSI image (`.img`, `.xz`, `.zip`, `.7z`).
* **GSI Name / Label:** Custom identifier for your base GSI system.
* **Output ROM Name:** File name for the final flashable ZIP artifact.
* **Include Magisk (Root):** Check the box to embed Magisk v30.7 for root access.


4. Click **Run workflow**. Once finished, download the flashable ZIP from the workflow **Artifacts** section.
