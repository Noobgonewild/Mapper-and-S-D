# MMapper + Search & Destroy for Aardwolf (Mudlet)

This repository contains a Mudlet mapper and Search & Destroy (S&D) for Aardwolf.

> [!IMPORTANT]
> Your Mudlet profile does **not** have to be named `Aardwolf`.
>
> The code uses `getMudletHomeDir()`, so it loads files from whichever Mudlet profile is currently open. If your profile is named `Bob`, install into the `Bob` profile directory. `Aardwolf.db` is the required default **database filename**, not the required profile name.

> [!WARNING]
> **DO NOT RENAME THE ADDON FOLDERS.** They must be named exactly **`mmapper`** and **`SearchAndDestroy`** or the loaders will not find the Lua files.

## Quick installation

1. Download this repository with **Code > Download ZIP**, then extract the ZIP somewhere temporary.
2. Open the Mudlet profile in which you want to use the addons.
3. Enter this in Mudlet's command line to display that profile's exact directory:

   ```text
   lua getMudletHomeDir()
   ```

   On Mudlet 4.20 or newer, this also opens the directory in your file manager:

   ```text
   lua openMudletHomeDir()
   ```

4. Close Mudlet before copying folders or databases.
5. Copy the complete **`mmapper`** and **`SearchAndDestroy`** folders from the extracted repository directly into the profile directory shown in step 3. **Do not rename either folder.**
6. If you are bringing data from MUSHclient, also copy `Aardwolf.db` and `SnDdb.db` into that same profile directory. See [Moving your old MUSHclient databases](#moving-your-old-mushclient-databases).
7. Reopen that Mudlet profile.
8. Open Mudlet's **Package Manager** (`Alt+O`) and choose **Install New Package**. Install these files in this order:

   1. `mmapper/mm_package.xml`
   2. `SearchAndDestroy/SearchAndDestroy.xml`

   S&D depends on MMapper, which is why the mapper is installed first. Do not use the repository ZIP itself as the Mudlet package.
9. Save the Mudlet profile.
10. Run the checks in [Verify the installation](#verify-the-installation).

## Required directory layout

The two addon folders and both databases belong directly inside the active Mudlet profile directory:

```text
<Mudlet profile directory>/
├── Aardwolf.db                         optional, but recommended for existing map data
├── SnDdb.db                            optional, but recommended for existing S&D data
├── mmapper/
│   ├── mm_package.xml
│   ├── mm_init.lua
│   ├── mm_core.lua
│   └── ...the rest of the mapper files
└── SearchAndDestroy/
    ├── SearchAndDestroy.xml
    ├── snd_main.lua
    ├── snd_database.lua
    ├── ...the rest of the S&D files
    └── ...the supplied S&D sound files
```

The folder names are case-sensitive on Linux and macOS and must be exactly:

- `mmapper` — not `mapper`
- `SearchAndDestroy` — not `snd`, `S&D`, or `Search-And-Destroy`

Common incorrect layouts include:

```text
<profile>/Mapper-and-S-D-main/mmapper/...
<profile>/mmapper/mmapper/...
<profile>/SearchAndDestroy/SearchAndDestroy/...
```

After extracting the GitHub ZIP, copy the two folders **out of** the outer `Mapper-and-S-D-main` folder. Do not place that outer folder in the Mudlet profile.

### Typical profile locations

The exact path printed by `lua getMudletHomeDir()` is authoritative. Default locations usually look like:

- Windows: `C:\Users\<you>\.config\mudlet\profiles\<profile-name>`
- Linux: `/home/<you>/.config/mudlet/profiles/<profile-name>`
- macOS: `/Users/<you>/.config/mudlet/profiles/<profile-name>`

## Moving your old MUSHclient databases

The public repository contains the addon code but does not contain populated mapper or S&D databases. You may either bring your existing MUSHclient data or let the Mudlet addons create new, empty databases.

### What to copy

The MUSHclient versions store their databases in the MUSHclient application directory (the directory returned by MUSHclient's `GetInfo(66)`, normally the folder containing `MUSHclient.exe`):

| MUSHclient file | Mudlet destination | Contains |
| --- | --- | --- |
| `Aardwolf.db` | `<Mudlet profile>/Aardwolf.db` | Mapper rooms, exits, portals, and related map data |
| `SnDdb.db` | `<Mudlet profile>/SnDdb.db` | S&D areas, mob sightings, keywords, and history |

If your MUSHclient mapper uses a different database name, enter `mapper database` in MUSHclient to see its current filename. Copy that database to Mudlet and name the destination file `Aardwolf.db`.

Use the exact destination names shown above. In particular, `SnDdb.db` has capital `S`, `D`, and `D`; filename case matters on Linux and macOS.

### Safe migration procedure

1. Exit MUSHclient completely so SQLite finishes writing its database files.
2. Exit Mudlet completely.
3. Copy the old databases into the target Mudlet profile directory using the exact names `Aardwolf.db` and `SnDdb.db`.
4. Reopen Mudlet and load the target profile.

Do not copy databases while either client is using them. After a clean shutdown, copy the main `.db` files; temporary `-wal` and `-shm` files should not be needed.

On first load, the current mapper and S&D code inspect recognized older schemas and upgrade them automatically when necessary. Before a migration, the code creates a timestamped backup in:

```text
<Mudlet profile>/db_backups/
```

Unrecognized or invalid databases are reported and left untouched.

### If Mudlet already created empty databases

When either default database is missing, the addons create a valid but empty replacement. That lets a new user start collecting data, but it does not contain the old map or S&D history.

If you installed the packages before copying your MUSHclient data:

1. Run `mapper database` and `snd db` to confirm that the reported databases contain zero rooms/exits or zero mobs/areas.
2. Exit Mudlet completely.
3. Rename the empty files as backups, for example `Aardwolf.db.empty` and `SnDdb.db.empty`.
4. Copy the populated MUSHclient files into the profile directory with the exact default names.
5. Reopen Mudlet and check the counts again.

Never overwrite an open database.

## Verify the installation

After installing both XML packages, connect to Aardwolf and run:

```text
mapper database
snd db
```

Expected results:

- `mapper database` reports the resolved path inside the active profile, a valid schema/integrity result, and nonzero room/exit counts if you copied a populated map database.
- `snd db` reports the resolved database and profile paths, `FOUND`, an open connection, valid schema/integrity results, and nonzero mob/area counts if you copied a populated S&D database.

If the current room is not detected after connecting, enter:

```text
look
```

This refreshes the mapper's current-room information.

## Build the visual Mudlet map

`Aardwolf.db` is a live SQLite database used by MMapper for room and route data. Mudlet's native visual map uses a different file format.

After copying a populated `Aardwolf.db`, build the native visual map once with:

```text
mapper rebuild map
```

Let the rebuild finish. It creates the default native map file:

```text
<Mudlet profile>/mmapper_converted_map.dat
```

The rebuild replaces the current contents of Mudlet's internal map. Export or back up an existing Mudlet map first if you need to keep it.

If an area's layout later looks wrong, stand in that area and run:

```text
mapper rebuild layout
```

Do **not** run `mapper native load Aardwolf.db` or set `mapper native db` to `Aardwolf.db`. The code deliberately rejects that: `Aardwolf.db` is SQLite, while `mapper native load` expects a converted Mudlet map such as `mmapper_converted_map.dat`.

## First commands

Use these commands after installation:

```text
mapper help          show mapper help topics
mapper help all      show all mapper commands
snd                  show the main S&D help
xhelp                show detailed S&D command help
snd window           toggle the S&D window
```

## Troubleshooting

### The addon says files or modules are missing

Read the required location printed by the warning and compare it with `lua getMudletHomeDir()`.

- The complete mapper folder must be `<profile>/mmapper`.
- The complete S&D folder must be `<profile>/SearchAndDestroy`.
- Remove any extra `Mapper-and-S-D-main`, `mmapper`, or `SearchAndDestroy` nesting level.
- Do not copy only the XML files; the XML loaders execute the accompanying loose `.lua` files.

After correcting either folder, reload the profile.

### S&D reports that MMapper did not become ready

S&D requires MMapper. Confirm that `mm_package.xml` is installed and that MMapper did not print a missing-file or module error, then reload the profile. Install MMapper before S&D on a fresh profile.

### The database exists but the counts are zero

An empty database was probably created before the old MUSHclient file was copied, or the populated file was copied into a different profile. Use `mapper database` and `snd db` to read the exact paths currently in use, then follow [If Mudlet already created empty databases](#if-mudlet-already-created-empty-databases).

### The copied S&D database is ignored

Check the filename carefully. The default is `SnDdb.db`, not `Snddb.db`, `snd.db`, or `SnD.db`. Also confirm that it is directly in the active profile directory, not inside `SearchAndDestroy`.

### A custom database path works only until a reload

For the most reliable setup, use `Aardwolf.db` and `SnDdb.db` directly in the profile directory. The diagnostic commands can point the running session at other paths, but the current loaders restore their default database locations on a full profile reload.

### `mapper native load` says the file looks like SQLite

You tried to load `Aardwolf.db` as a native Mudlet map. Run `mapper rebuild map` to convert it, then use the generated `mmapper_converted_map.dat` if a native map file is requested.

### Migration fails

Copy the exact error message and the output of `mapper database` or `snd db`. Do not repeatedly rename unrelated databases to the expected filename: the code validates SQLite integrity and schema before changing recognized data.

## Updating the addons

Back up `Aardwolf.db`, `SnDdb.db`, and the profile's `persistence` directory before a major update. Then replace the two addon source folders with complete copies from the new release and reinstall both XML packages through Mudlet's Package Manager so changes to triggers, aliases, and loaders are also applied.

Do not replace your databases or the profile-level `persistence` directory with files from the source archive.

## Useful references

- [Mudlet Package Manager](https://wiki.mudlet.org/w/Manual%3APackage_Manager)
- [Mudlet `getMudletHomeDir()` documentation](https://wiki.mudlet.org/w/Manual%3AMiscellaneous_Functions#getMudletHomeDir)
- [Mudlet profile file locations](https://wiki.mudlet.org/w/Mudlet_File_Locations)
- [MUSHclient `GetInfo()` documentation](https://www.mushclient.com/mushclient/functions/GetInfo.html)

These addons were originally made for personal use and are shared in case other Aardwolf players find them useful. Back up important profile and database data, and report reproducible problems with the exact warning text and diagnostic command output.


If nothing is working....

Close Mudlet and use Mushclient :)

A few screenshots on S&D and mmapper in action but their features are much much MUCH richer!

<img width="3440" height="1400" alt="2026-04-16 23_22_08-NVIDIA GeForce Overlay" src="https://github.com/user-attachments/assets/d4bdcf57-3c3b-4eaa-8c4b-978059d11f46" />


S&D main window:

<img width="457" height="508" alt="2026-04-15 19_45_50-Aardwolf - Mudlet 4 20 1" src="https://github.com/user-attachments/assets/f4abf9ef-7864-41f6-865c-112438815807" />
<img width="455" height="505" alt="2026-04-16 22_54_11-Aardwolf - Mudlet 4 20 1" src="https://github.com/user-attachments/assets/7fe7463e-e443-4759-8a0c-d07a05740c15" />
<img width="455" height="508" alt="2026-04-16 23_12_33-Aardwolf - Mudlet 4 20 1" src="https://github.com/user-attachments/assets/9f5d7a74-a1ba-4bfc-b041-4d3d6626931d" />



Yes, S&D is multi window now. It transitions from window to window based on priority GQ -> quest -> CP. Clicking on a tab will manually change windows. All buttons are scoped for the selected window. i.e. xcp 1 will select first mob in quest window -> change window to cp, xcp 1 will select first cp monster etc

S&D consider window (conwin)

<img width="342" height="414" alt="2026-04-14 18_47_17-Aardwolf - Mudlet 4 20 1" src="https://github.com/user-attachments/assets/0318d732-8e6c-4874-b3e5-aceb1832b99c" />
<img width="337" height="413" alt="2026-04-12 19_46_06-Aardwolf - Mudlet 4 20 1" src="https://github.com/user-attachments/assets/a1cfa626-86f4-4518-a700-c7e2dcc18db1" />

I've added a consider window to S&D. It supports monster HP left, quest/cp/gq tags, custom attack command, auto refresh on X kills and much more!
It's API is tied in with S&D, to use the same consider/scan command for both of them resulting in less spam.

S&D history with context menu report

<img width="1249" height="389" alt="2026-04-16 22_49_26-Aardwolf - Mudlet 4 20 1" src="https://github.com/user-attachments/assets/6cd23a9c-4ae9-425f-8efe-a440c73f0610" />
<img width="1248" height="408" alt="2026-04-16 22_51_31-Aardwolf - Mudlet 4 20 1" src="https://github.com/user-attachments/assets/177cefa2-5785-42e1-af1e-ec4df424acd2" />



A few Mmapper screenshots:

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
