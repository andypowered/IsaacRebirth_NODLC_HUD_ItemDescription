# Isaac Rebirth No-DLC Kit v1.0

> Item descriptions (EID Rebirth) + stat HUD (MissingHUD2) for **The Binding of Isaac: Rebirth v1.05 without DLC**.

![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)
![Game](https://img.shields.io/badge/game-Rebirth%20v1.05%20(no%20DLC)-orange)
![Version](https://img.shields.io/badge/kit-v1.0-green)

---
# Language

EN
[RU](https://github.com/andypowered/The-Binding-of-Isaac-Rebirth-HUD-Item-Description-/blob/main/readme_ru.md)

## Repository map

```
├── HUD/
|   └── MissingHUD2.exe
├── payload/
├── INSTALL.bat 
├── Install.ps1 
├── UNINSTALL.bat
├── Uninstall.ps1
├── readme.md
└── readme_ru.md       
```

## 📖 What is this?

Two independent parts bundled together:

### 1. EID Rebirth — item & trinket descriptions
The base game has no Lua mod support, so descriptions are **baked directly into the item images**. Text appears on the item at the pedestal, in shops, at the Devil Room, etc. This is not a hover tooltip — it's part of the item's picture.

### 2. MissingHUD2 v1.4.0 — character stat HUD
A small overlay on the left showing speed, range, tear rate, shot speed, damage, luck, and deal chance. It runs as a separate process and **does not modify game files**.

> ⚠️ **For base Rebirth only.** Not compatible with Afterbirth, Afterbirth+, or Repentance.

---

## ✅ Requirements

- Windows 10/11 (Windows 7/8.1 works with PowerShell 5.1)
- The Binding of Isaac: Rebirth **v1.05, no DLC**
- Administrator rights for installing into Program Files (the installer requests UAC)
- Close the game and MissingHUD2 before installing

---

## 🚀 Installation

1. Extract the archive anywhere (paths with spaces/Cyrillic are fine).
2. Close the game if running.
3. Run `INSTALL.bat`.
4. Confirm the UAC prompt.
5. Choose description language:
   - `[1]` Русский — Russian text on item images
   - `[2]` English — original EID English descriptions
6. Optionally create a desktop shortcut for the HUD.
7. Wait for **"Installation complete"**.

**The installer:**
- Copies EID files into the game's `resources` folder
- Replaces **431 images** (341 items + 90 trinkets) with Russian versions if selected
- Backs up any existing files it overwrites
- Writes an install manifest for clean removal
- Installs MissingHUD2 into the user's app data folder

If the game isn't found automatically (non-Steam install), you'll be asked to point to the folder containing `isaac-ng.exe` and `resources`.

---

## 🎮 In-Game

### Item descriptions
- Walk up to a pedestal item — its description appears **on the image**
- Works in shops, Devil Rooms, and elsewhere
- Card, rune, and pill descriptions remain English (base game fonts may not render Cyrillic for these)

### HUD
1. Launch the game and enter a run.
2. Start the HUD via one of:
   - Desktop shortcut **"Isaac Rebirth HUD"**
   - `START_HUD.bat` in the `HUD` folder
   - `START_HUD_ADMIN.bat` if the normal launcher fails
3. The HUD appears on the left **only during a run**.
4. To hide it, close MissingHUD2 (X button or Task Manager). No game restart needed.

### HUD settings
- `MHUD2.prefs` in the HUD folder. Defaults to a **compact layout**: no shot counter, no tear height, no angel/devil split for deal chance.
- Adjust via the MissingHUD2 window (checkboxes and precision).
- Restart the HUD after changing settings.

---

## 🇷🇺 Russian descriptions

The Russian replacement is **unofficial**. It combines Russian EID descriptions rendered in the **Press Start 2P** pixel font. It's a fan translation — expect occasional inaccuracies or outdated details for some items. The English EID variant remains more canonical.

Only item and trinket images are localized. `pocketitems.xml` (cards, runes, pills) stays English.

---

## 🗑️ Uninstallation

1. Close the game and MissingHUD2.
2. Run `UNINSTALL.bat`.
3. Confirm UAC if prompted.
4. Confirm removal.

**The uninstaller:**
- Removes only files placed by this kit
- Restores overwritten files from backups
- Leaves files you modified after installation untouched (and logs them)
- Removes the HUD and its shortcut; backups and logs are preserved
- Backups kept at: `%LOCALAPPDATA%\IsaacRebirthNoDLCKit\backup\<timestamp>\`
  You can delete these manually once you've confirmed the game works.
- Uninstall log: `%LOCALAPPDATA%\IsaacRebirthNoDLCKit\uninstall_log_<date>.json`

---

## 🛠️ Troubleshooting

### Game not found
- Point to the folder manually
- Verify it contains `isaac-ng.exe` and `resources`

### "No write permission"
- Right-click `INSTALL.bat` → **Run as administrator**

### HUD doesn't appear
- HUD only runs **during a run**, not in the main menu
- Start the game, enter a run, then launch the HUD
- Try `START_HUD_ADMIN.bat`
- Antivirus may block DLL injection — add the `HUD` folder to exclusions if you trust MissingHUD2
- Close and relaunch the HUD after entering a run

### Descriptions don't appear
- Restart the game
- Confirm `resources` now contains a `gfx` folder plus `animations.b` and `pocketitems.xml`
- Make sure you didn't install into the wrong game folder
- If another mod modifies the same `gfx` files, conflicts can occur. Uninstall the kit, verify game files in Steam, then reinstall.

### Game won't launch / black screen
- Run `UNINSTALL.bat`
- In Steam: Properties → Installed Files → **Verify integrity**
- Reinstall the kit if needed

> Steam's "Verify integrity" may restore stock files. You can reinstall afterward. It's best to run `UNINSTALL.bat` first.

---

## ℹ️ Good to know

- The kit doesn't touch saves and doesn't require new ones.
- EID Rebirth **doesn't disable achievements** — it's a resource swap, not a Lua mod.
- MissingHUD2 doesn't modify game files.
- Use of third-party injectors is at your own risk.
- Don't install/uninstall while the game is running.
- If another graphical mod is present, the installer backs up replaced files, but mod conflicts are still possible.
- The kit contains no DLC and doesn't unlock DLC content.

---

## 🔧 Manual installation (no installer)

1. Copy the contents of `payload\EID` into the game's `resources` folder (you should get `resources\gfx`, `resources\animations.b`, `resources\pocketitems.xml`).
2. For Russian, copy `payload\RU\gfx` over `resources\gfx` (overwrite).
3. Copy the `HUD` folder anywhere and run `START_HUD.bat` during a run.

> Manual installation creates **no backups** and can't be cleanly removed via `UNINSTALL.bat`. Use the installer when possible.

---

## 📦 Contents & versions

| Component | Details |
|---|---|
| EID Rebirth (External Item Descriptions, Rebirth version) | 1226 files, including 344 PNGs in `collectibles` (341 items + 3 utility) and 90 trinket images |
| Russian replacement | 431 images (341 items + 90 trinkets) |
| MissingHUD2 v1.4.0 | `MissingHUD2.exe`, `MissingHUD2Hook.dll` |
| Font for Russian images | Press Start 2P (SIL OFL 1.1) |

Details and links: `THIRD_PARTY_NOTICES.txt`
Exact versions, dates, sizes: `VERSION.txt`
Licenses: `LICENSES` folder

---

## ⚖️ Disclaimer

This is an unofficial fan kit. *The Binding of Isaac: Rebirth* and all original assets belong to Edmund McMillen, Nicalis, and their rights holders. EID belongs to Wofsauge and project contributors. MissingHUD2 belongs to Trevor Meehl / networkMe. The kit is provided **as is**, without warranty. Back up your saves and game before use.

---

## 📄 License

See `LICENSES` folder. Third-party notices in `THIRD_PARTY_NOTICES.txt`.
