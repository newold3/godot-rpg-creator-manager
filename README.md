# 🧙‍♂️ Godot RPG Creator - Launcher

![Godot 4](https://img.shields.io/badge/Godot-v4.x-478cbf?logo=godot-engine&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey)
![License](https://img.shields.io/badge/License-MIT-green)
![Status](https://img.shields.io/badge/Status-Beta-orange)

**The official hub to create, manage, and launch your Godot RPG Creator projects.**

<p align="center"><img width="1158" height="660" alt="image" src="https://github.com/user-attachments/assets/fd7af548-e739-4c1a-bd00-a038c42f309b" /></p>

This tool acts as a central "Hub" (similar to Unity Hub or the Epic Games Launcher or the godot Launcher) specifically designed for the **Godot RPG Creator** ecosystem. It allows you to download the latest version of the RPG engine, manage your existing projects, and keep everything updated automatically.

---

## 🚀 Download & Installation

To get started, head over to the **[Releases](../../releases)** page and download the version that best suits your needs:

### 📦 Option A: Full Offline Bundle (Recommended)
> **Filename:** `RPG_Creator_Full_Offline.zip` (~1GB)

Includes the Launcher **and** a local copy of the RPG Engine Template.
* ✅ **Instant Installation:** No internet connection required to create your first project.
* ✅ **Best for slow internet connections.**
* **How it works:** The launcher detects the bundled template and installs it immediately without downloading anything.

### ⚡ Option B: Lite Installer
> **Filename:** `RPG_Creator_Lite.zip` (~15MB)

Includes **only** the Launcher executable.
* ⚠️ **Requires Internet:** When creating your first project, the Launcher will automatically download the latest version of the engine template from GitHub.
* ✅ **Lightweight and fast to download initially.**

---

## ⚠️ Note for Linux & macOS Users

Since I primarily develop on Windows, the Linux and macOS builds are currently **experimental and untested**. If you encounter any issues, please report them in the [Issues](../../issues) tab!

### 🐧 Linux

If the application does not start when double-clicked, you likely need to grant it execution permissions.

1. Open your terminal in the folder where you extracted the file.
2. Run the following command:
```bash
   chmod +x godot_rpg_creator_manager.x86_64
```
3. Try running it again.

### 🍎 macOS

The application is not digitally signed (Apple Developer ID), so macOS Gatekeeper will likely block it by default, claiming it is "damaged" or from an "unidentified developer".

To open it:

1. Right-click (or Control+Click) on the `.app` file.
2. Select **Open** from the context menu.
3. Click **Open** in the warning dialog that appears.

If you still get a "File is damaged" error, open the Terminal and run:
```bash
xattr -cr "Godot RPG Creator manager.app"
```


## ✨ Key Features

* **Project Management:** View all your RPG projects in a clean interface. Sort by name, path, or last modified date.
* **Drag & Drop Import:** Simply drag an existing project folder onto the window to import it into your list.
* **One-Click Creation:** Automatically handles cloning, configuring, and preparing the base RPG template for you.
* **Hybrid Update System:**
	* **The Launcher:** Updates itself by detecting new releases on GitHub.
	* **Your Projects:** Detects if your project is running on an older version of the RPG engine and update it.
* **Integrated Tools:** Rename, Duplicate, Remove (with Trash bin support), and Open in Editor.

---

## 🛠️ How to Use

1.  Unzip the downloaded file into a folder of your choice (e.g., `Desktop/GodotRPGCreator`).
2.  Run `godot_rpg_creator_manager.exe` (Windows) or the binary for your OS.
3.  **To create a new game:**
	* Click on **+ CREATE**.
	* Select an empty folder.
	* The Launcher will install the necessary files.
4.  **To edit a game:**
	* Double-click your project or select **EDIT** to open the custom Godot editor.

---

## 🏗️ Project Architecture

This ecosystem is split into two repositories to ensure easy maintenance and faster updates:

1.  **[Godot-RPG-Creator-Launcher](.) (This Repository):**
	* The desktop tool (the `.exe`).
	* Written in Godot, it handles file management, downloads, and the UI.
	
2.  **[Godot-RPG-Template](https://github.com/newold3/Godot-RPG-Creator):**
	* The "Engine" or "Base Template".
	* Contains all the RPG logic (combat systems, inventory, maps, etc.).
	* The Launcher downloads the source code from *that* repository when you create a game.

> **Note:** If you are looking for the source code of the RPG game mechanics to contribute, please visit the Template repository.

---

## 🤝 Contributing & Support

This project is free and open-source under the **MIT** license.

* 🐛 **Report Bugs:** Use the [Issues](../../issues) tab in this repository if the Launcher is not working correctly.
* 💡 **Suggestions:** If you have ideas for the RPG engine mechanics, please post them in the Template repository.

**Support the Development:**
If you enjoy this tool and want to ensure its future development, please consider supporting me on Patreon:

[![Patreon](https://img.shields.io/badge/Support%20me-Patreon-red?style=for-the-badge&logo=patreon)](https://www.patreon.com/Newold13)

---

## 📜 License

Copyright © 2025-2026 **Newold**.
Distributed under the MIT License. See `LICENSE` for more information.
