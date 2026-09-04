NOTE: Mapper had a loading step that i didn't include in the install notes. I fixed it so it is no longer required, it should load fine now!

**This was made for my personal use! I am sharing in case someone else finds it useful; I know 99% of people are die hard Mush veterans!**

**Mapper + Search and Destroy Database Guide (Mudlet)**

This guide explains where to place your database files, how to name them, and which commands to use to inspect/import/convert/rebuild map data for both mapper and Search and Destroy (S&D).

**1) What each database is for**

Mapper DB (Aardwolf.db by default)

Used by mapper features for room/exit data and for building/rebuilding your Mudlet map from a SQLite source database. The default configured names in mapper state is Aardwolf.db.
You can copy this file from mush client. It is located in the root directory of mush client.

S&D DB (SnDdb.db by default)

Used by Search and Destroy to store mob sightings, area start rooms, keyword exceptions, and history. Default path is getMudletHomeDir() .. "/SnDdb.db".

You can copy this file from mush client. It is located in the root directory of mush client.

**2) Where to put the files**

Mudlet profile base location

Both modules resolve relative DB names from your Mudlet profile directory (getMudletHomeDir()). Mapper resolves relative native DB paths as getMudletHomeDir() .. "/<filename>".

Suggested placement

Put your DB files directly in your Mudlet profile folder:

C:\Users\username\.config\mudlet\profiles\Aardwolf

Aardwolf.db (mapper source SQLite DB)

SnDdb.db (Search and destroy database file)

S&D and mapper location:

SearchAndDestroy and mapper go under your Mudlet profile path.

You then import SearchAndDestroy.xml and mm_package.xml

**3) Naming conventions (recommended)**

Mapper source SQLite DB: Aardwolf.db (default expected name).

S&D DB: SnDdb.db by default, but any filename/path works if set via command (snd db <path>).

**4) Mapper commands you will actually use**

Check/set database paths

mapper database → show current source DB (map_db).

mapper native db → show native map DB path.

mapper native db <path> → set native map DB path if needed

Validate source SQLite before import

mapper native inspect or mapper native inspect <path>

Checks compatibility and counts. Can skip this step if you copy from mush client.

Convert/import SQLite into Mudlet map

mapper native convert → this will import rooms from Aardwolf.db into the visual map (big map)

Converts SQLite rooms/exits into Mudlet map data and saves map export (default: mmapper_converted_map.dat).

Rebuild/import shortcut commands

mapper rebuild map (it takes time. The client will temporarily freeze)

mapper import rooms (it takes time. The client will temporarily freeze)

Both run conversion from current map_db and then re-center player view if possible.

mapper rebuild layout → run this is big map doesn't look ok. This will fix it. Sometimes an area will look slightly off. Running this command will fix it.

More mapper commands for building/rebuilding/coloring map are found under "mapper help config"

**5) S&D database commands**

Show DB status/path

snd db → shows current path, file exists/not found, connection status, tables, and profile dir.

Point S&D to a different DB file

snd db /full/path/to/snd.db

This sets snd.db.file and immediately initializes the DB connection.

Default behavior if DB is missing

If configured S&D DB file is not found, S&D prints an error and tells you to copy DB into your Mudlet home dir.

**6) Typical first-time setup workflow**

Install/load mapper + S&D modules in Mudlet.

Copy your old SQLite mapper DB into Mudlet profile as Aardwolf.db (recommended to use this name because it is preconfigured).

Run mapper set database Aardwolf.db (should not be needed).

Run mapper native inspect to validate schema/counts before import.

Run mapper rebuild map (or mapper native convert) to import rooms/exits into Mudlet format.

If needed, run mapper native db mmapper_converted_map.dat and mapper native load to load the converted file explicitly.

Place/copy S&D DB as SnDdb.db in Mudlet profile (or keep custom path).

Run snd db to verify S&D path and connection, then snd db /path/to/your/snd.db if you want a different file.

**7) Quick troubleshooting**

mapper native load fails with “looks like SQLite” / not a Mudlet map file

You attempted to load a raw SQLite DB. Use mapper native convert (or mapper rebuild map) first, then load the resulting map export if needed.

mapper native inspect says schema mismatch

Your source DB doesn’t have required room/exit columns. Verify source DB comes from compatible Aard/MUSHclient mapper schema.

S&D says DB file not found

Wrong path or filename. Either copy DB into Mudlet profile as SnDdb.db or run snd db /full/path/file.db to point to it.

snd db shows file exists but no useful data

Open snd db output and check tables/contents count; your file may be an unexpected schema or empty DB.

Import commands do nothing / no mapper responses

Verify mapper module is loaded and use path display commands (mapper database, mapper native db) to confirm the file being referenced is the one you expect.

Nothing is working

Close Mudlet and use Mushclient :)

A few screenshots on S&D and Mmapper in action!

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
