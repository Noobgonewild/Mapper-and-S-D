# MMapper + Search & Destroy for Aardwolf (Mudlet)

Mudlet mapper and Search & Destroy (S&D) add-ons for Aardwolf MUD, distributed as native Mudlet packages.

Public Repository: [Noobgonewild/Mapper-and-S-D](https://github.com/Noobgonewild/Mapper-and-S-D)

---

## Key Highlights

> [!NOTE]
> **Download anywhere, install from anywhere!**
> You can download the package files (`.mpackage`) to **any folder on your computer** (such as your `Downloads` folder or Desktop). There is **no need** to move the package files into your Mudlet directory before installing, and you do **not** need to unzip or extract them. Mudlet handles package extraction and setup automatically.

> [!IMPORTANT]
> **Your Mudlet profile does not have to be named `Aardwolf`.**
> The add-ons use `getMudletHomeDir()`, loading files from whichever Mudlet profile is currently active. If your profile is named `AardwolfClient` or `Main`, the add-ons install and run cleanly there. `Aardwolf.db` is the default database filename, not the required profile name.

---

## Installation

### Step 1: Download the Packages

Download the two `.mpackage` files from [Noobgonewild/Mapper-and-S-D](https://github.com/Noobgonewild/Mapper-and-S-D) to anywhere on your system:

- [`mmapper.mpackage`](https://raw.githubusercontent.com/Noobgonewild/Mapper-and-S-D/main/mmapper.mpackage) — MMapper add-on
- [`SearchAndDestroy.mpackage`](https://raw.githubusercontent.com/Noobgonewild/Mapper-and-S-D/main/SearchAndDestroy.mpackage) — Search & Destroy add-on

> [!TIP]
> Keep the files wherever your browser saved them (e.g., `Downloads`). Do not extract them; `.mpackage` files are native Mudlet packages.

---

### Step 2: Install into Mudlet

Open Mudlet and connect to your Aardwolf character/profile (so your main game terminal window is open and active). Then install the packages using either method below:

#### Option A: Package Manager (Recommended)

1. In Mudlet, open the **Package Manager**:
   - Press `Alt+O`, or
   - Click **Toolbox** > **Package Manager** from the menu.
2. Click **Install** (or **Install New Package**).
3. Navigate to wherever you downloaded the files (e.g., your `Downloads` folder).
4. Install the packages in this order:
   1. **`mmapper.mpackage`** (Install first — S&D depends on MMapper)
   2. **`SearchAndDestroy.mpackage`** (Install second)
5. Save your Mudlet profile.

#### Option B: Drag and Drop (Fresh Installations)

> [!NOTE]
> Drag and drop is best suited for fresh, first-time installations. If you already have an older version of the add-on installed, Mudlet will not overwrite it via drag-and-drop — you must first uninstall the old package in **Package Manager** (`Alt+O`) or use **MCheck** to update automatically.

1. Make sure your active Mudlet game window is visible on screen.
2. Open your file browser to where you downloaded the `.mpackage` files.
3. Drag and drop **`mmapper.mpackage`** directly onto the open Mudlet window.
4. Drag and drop **`SearchAndDestroy.mpackage`** directly onto the open Mudlet window.

---

### Step 3: (Optional) Bring Old MUSHclient Databases

If you are a new player or do not have existing map/S&D data, **skip this step** — the add-ons will automatically create fresh, empty databases for you.

If you are migrating existing databases from MUSHclient:

1. In Mudlet, run this command to reveal and open your profile folder:
   ```text
   lua openMudletHomeDir()
   ```
   *(On older Mudlet versions, run `lua getMudletHomeDir()` to print the path).*
2. Fully close Mudlet and MUSHclient.
3. Copy your databases directly into that profile folder:
   - `Aardwolf.db` (Mapper rooms, exits, portals)
   - `SnDdb.db` (S&D mob sightings, keywords, history)
4. Reopen Mudlet. See [Moving your old MUSHclient databases](#moving-your-old-mushclient-databases) for full migration details.

---

### Step 4: Verify the Installation

Connect to Aardwolf in Mudlet and run:

```text
mapper database
snd db
```

- `mapper database`: Reports the database path, schema status, and room/exit count.
- `snd db`: Reports database status `FOUND`, an open SQLite connection, and mob/area counts.

If the current room does not appear immediately upon connecting, type:

```text
look
```

---

## Building the Visual Mudlet Map

`Aardwolf.db` is the live SQLite database used by MMapper for room, exit, and portal navigation. Mudlet's 2D visual map display uses a native binary format (`.dat`).

After copying a populated `Aardwolf.db`, build the visual map once by entering:

```text
mapper rebuild map
```

Allow the rebuild to finish. It generates the native visual map file:

```text
<Mudlet profile directory>/mmapper_converted_map.dat
```

If an individual area layout ever appears misaligned or shifted, stand inside that area and run:

```text
mapper rebuild layout
```

> [!CAUTION]
> Do **not** run `mapper native load Aardwolf.db`. `Aardwolf.db` is an SQLite database, while `mapper native load` expects Mudlet's converted `.dat` map file.

---

## Moving your old MUSHclient databases

The repository and packages provide the add-on code, sounds, and UI, but do not overwrite your databases. You can bring existing MUSHclient data or let the add-ons create new databases.

### What to Copy

In MUSHclient, databases live in the main application folder (revealed by MUSHclient's `GetInfo(66)`, usually the folder containing `MUSHclient.exe`).

| MUSHclient File | Mudlet Destination | Description |
| :--- | :--- | :--- |
| `Aardwolf.db` | `<Mudlet profile>/Aardwolf.db` | Rooms, exits, custom exits, portals, and bookmarks |
| `SnDdb.db` | `<Mudlet profile>/SnDdb.db` | Target areas, mob sighting records, keywords, and history |

> [!IMPORTANT]
> Note the exact capitalization: `SnDdb.db` has capital `S`, `D`, and `D`. File case is strictly enforced on Linux and macOS.

### Safe Migration Procedure

1. **Exit MUSHclient completely** so SQLite finishes pending writes and flushes WAL files.
2. **Exit Mudlet completely**.
3. Copy `Aardwolf.db` and `SnDdb.db` into your Mudlet profile folder (`lua openMudletHomeDir()`).
4. Reopen Mudlet and connect.

On first load, MMapper and S&D inspect database schemas and upgrade them automatically if needed. A timestamped backup is preserved before migration in:

```text
<Mudlet profile directory>/db_backups/
```

### If Mudlet already created empty databases

If you opened Mudlet before copying your MUSHclient files, empty databases may have been generated:

1. Run `mapper database` and `snd db` to check current room/mob counts.
2. If counts are zero and you want your old data:
   - Exit Mudlet completely.
   - Rename or delete the empty `Aardwolf.db` and `SnDdb.db`.
   - Copy your populated MUSHclient `.db` files into the profile directory.
   - Reopen Mudlet and run the verification commands again.

---

## First Commands

Once installed, use these commands to get started:

| Command | Description |
| :--- | :--- |
| `mapper help` | Show mapper command categories and topics |
| `mapper help all` | List all available mapper commands |
| `snd` | Show Search & Destroy main overview and active status |
| `xhelp` | Display comprehensive S&D command help |
| `snd window` | Toggle the S&D graphical interface window |
| `mapper window` | Toggle the mapper display window |

---

## Updating the Add-ons

Updating is safe because package updates never touch or overwrite your personal profile databases (`Aardwolf.db` and `SnDdb.db`):

### Via MCheck (Recommended — Fully Automated)
If you use [MCheck](https://raw.githubusercontent.com/Noobgonewild/Mudlet-scripts/main/mcheck-index.json), it detects installed add-ons, downloads verified packages, and handles the uninstall and reinstall cycle automatically.

> [!NOTE]
> MCheck scans and updates add-ons that are **already installed** in your active profile. It cannot perform a first-time installation of an uninstalled add-on. Once you have installed the packages via Option A or B above, MCheck manages all future updates seamlessly:

```text
mcheck scan
mcheck update <number>
```

### Via Package Manager (Manual Update)
Because Mudlet will not overwrite an existing package via drag-and-drop or direct re-installation, you must uninstall the old package first:

1. Download the new `mmapper.mpackage` and/or `SearchAndDestroy.mpackage` anywhere on your computer.
2. Open Mudlet's **Package Manager** (`Alt+O`).
3. Select the package to update (`SearchAndDestroy` and/or `mmapper`) and click **Uninstall**.
   *(Note: Uninstalling the package only removes the scripts/triggers; your databases `Aardwolf.db` and `SnDdb.db` and your personal settings remain completely untouched).*
4. Click **Install** (or drag and drop the newly downloaded files onto the Mudlet window) to install the updated version:
   - Install `mmapper.mpackage` first if updating both.
   - Install `SearchAndDestroy.mpackage` second.
5. Save your profile or reload if needed.

---

## Manual / Developer Setup (From Source)

If you are cloning or modifying the source repository directly rather than installing `.mpackage` files:

```text
<Mudlet profile directory>/
├── Aardwolf.db
├── SnDdb.db
├── mmapper/
│   ├── mm_package.xml
│   ├── mm_init.lua
│   └── ...all other mapper files
└── SearchAndDestroy/
    ├── SearchAndDestroy.xml
    ├── snd_main.lua
    └── ...all other S&D files and sounds
```

1. Clone or extract the repository.
2. Place the `mmapper` and `SearchAndDestroy` folders directly into your active Mudlet profile directory (`lua openMudletHomeDir()`).
3. Open Package Manager (`Alt+O`) and install:
   - `<profile>/mmapper/mm_package.xml`
   - `<profile>/SearchAndDestroy/SearchAndDestroy.xml`

> [!WARNING]
> Folder names must match exactly: `mmapper` (not `mapper`) and `SearchAndDestroy` (not `snd` or `Search-And-Destroy`).

---

## Troubleshooting

### S&D reports MMapper did not become ready
S&D depends on MMapper. Ensure `mmapper.mpackage` is installed and enabled before installing or loading `SearchAndDestroy.mpackage`. If both are installed, type `sndreload` or reload the profile.

### The database exists, but counts are zero
An empty database was likely created before you copied your files, or files were placed in the wrong profile folder. Run `lua openMudletHomeDir()` in Mudlet to verify the exact active folder.

### Copied S&D database is not recognized
Verify the filename: it must be `SnDdb.db` (case-sensitive). It must sit directly inside the profile directory, not inside a subfolder.

### Rebuilding map gives an SQLite error
Do not load `Aardwolf.db` with `mapper native load`. Run `mapper rebuild map` instead to compile the visual map.

---

## Useful References

- [Noobgonewild/Mapper-and-S-D GitHub Repository](https://github.com/Noobgonewild/Mapper-and-S-D)
- [Mudlet Package Manager Documentation](https://wiki.mudlet.org/w/Manual%3APackage_Manager)
- [Mudlet File Locations](https://wiki.mudlet.org/w/Mudlet_File_Locations)
- [MCheck Addon Index](https://raw.githubusercontent.com/Noobgonewild/Mudlet-scripts/main/mcheck-index.json)

---

## Screenshots

If nothing is working....

Close Mudlet and use Mushclient :)

A few screenshots on S&D and mmapper in action but their features are much much MUCH richer!

<img width="3440" height="1400" alt="2026-04-16 23_22_08-NVIDIA GeForce Overlay" src="https://github.com/user-attachments/assets/d4bdcf57-3c3b-4eaa-8c4b-978059d11f46" />

### S&D main window:

<img width="457" height="508" alt="2026-04-15 19_45_50-Aardwolf - Mudlet 4 20 1" src="https://github.com/user-attachments/assets/f4abf9ef-7864-41f6-865c-112438815807" />
<img width="455" height="505" alt="2026-04-16 22_54_11-Aardwolf - Mudlet 4 20 1" src="https://github.com/user-attachments/assets/7fe7463e-e443-4759-8a0c-d07a05740c15" />
<img width="455" height="508" alt="2026-04-16 23_12_33-Aardwolf - Mudlet 4 20 1" src="https://github.com/user-attachments/assets/9f5d7a74-a1ba-4bfc-b041-4d3d6626931d" />

Yes, S&D is multi window now. It transitions from window to window based on priority GQ -> quest -> CP. Clicking on a tab will manually change windows. All buttons are scoped for the selected window. i.e. xcp 1 will select first mob in quest window -> change window to cp, xcp 1 will select first cp monster etc

### S&D consider window (conwin)

<img width="342" height="414" alt="2026-04-14 18_47_17-Aardwolf - Mudlet 4 20 1" src="https://github.com/user-attachments/assets/0318d732-8e6c-4874-b3e5-aceb1832b99c" />
<img width="337" height="413" alt="2026-04-12 19_46_06-Aardwolf - Mudlet 4 20 1" src="https://github.com/user-attachments/assets/a1cfa626-86f4-4518-a700-c7e2dcc18db1" />

I've added a consider window to S&D. It supports monster HP left, quest/cp/gq tags, custom attack command, auto refresh on X kills and much more!
It's API is tied in with S&D, to use the same consider/scan command for both of them resulting in less spam.

### S&D history with context menu report

<img width="1249" height="389" alt="2026-04-16 22_49_26-Aardwolf - Mudlet 4 20 1" src="https://github.com/user-attachments/assets/6cd23a9c-4ae9-425f-8efe-a440c73f0610" />
<img width="1248" height="408" alt="2026-04-16 22_51_31-Aardwolf - Mudlet 4 20 1" src="https://github.com/user-attachments/assets/177cefa2-5785-42e1-af1e-ec4df424acd2" />

### A few MMapper screenshots:

Main map:

<img width="343" height="384" alt="2026-04-16 22_04_23-Aardwolf - Mudlet 4 20 1" src="https://github.com/user-attachments/assets/c28b7352-892b-499b-b38f-db556069c71b" />

It natively supports multi-layer, meaning you can see the "down" or "up" rooms while being 1 up or 1 down. This can be disabled if you want to be oldschool.

Mini map:

<img width="341" height="454" alt="2026-04-16 22_04_14-Aardwolf - Mudlet 4 20 1" src="https://github.com/user-attachments/assets/d5142888-bd23-4593-b501-89c02ecd19e7" />

mapper analyzelanding output, used to see what paths a potential chaos portal would improve:

<img width="1263" height="811" alt="2026-09-04 22_38_14-Aardwolf - Mudlet 4 22 0" src="https://github.com/user-attachments/assets/0757a2f8-b2af-476e-969b-e92710614b62" />

To anyone who has made it this far: While these addons have many many improvements, including navigation and path discovery, bugs may still be arround! Be sure to use at your own risk!

To anyone that wants to modify these files: 

<img width="498" height="207" alt="dew-it-galactic-republic" src="https://github.com/user-attachments/assets/1b3b4766-ff0e-4d1c-b46b-e621dc309ec4" />

