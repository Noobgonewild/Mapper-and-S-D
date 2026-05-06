--[[
    Search and Destroy - Static Data Tables
    Mudlet Port
    
    Original MUSHclient plugin by Crowley
    Ported to Mudlet
    
    This module contains static lookup tables:
    - Area default start rooms
    - Mob keyword exceptions
    - Mob keyword filters
    - Class abbreviations
    - State strings
    - Wear locations
    - Object types
]]

snd = snd or {}
snd.data = snd.data or {}

-------------------------------------------------------------------------------
-- Class Abbreviations
-------------------------------------------------------------------------------

snd.data.classAbbreviations = {
    mag = "mage",
    thi = "thief",
    pal = "paladin",
    war = "warrior",
    psi = "psionicist",
    cle = "cleric",
    ran = "ranger",
}

-- Classes index (for GMCP char.base.classes field)
snd.data.classIndex = {
    [0] = "Mage",
    [1] = "Cleric",
    [2] = "Thief",
    [3] = "Warrior",
    [4] = "Ranger",
    [5] = "Paladin",
    [6] = "Psionicist",
}

-------------------------------------------------------------------------------
-- Character State Strings
-------------------------------------------------------------------------------

snd.data.stateStrings = {
    [1] = "login",
    [2] = "motd",
    [3] = "active",
    [4] = "afk",
    [5] = "note",
    [6] = "edit",
    [7] = "page",
    [8] = "combat",
    [9] = "sleeping",
    [11] = "resting",
    [12] = "running",
}

-------------------------------------------------------------------------------
-- Wear Locations
-------------------------------------------------------------------------------

snd.data.wearLocations = {
    [0] = "light",
    [1] = "head",
    [2] = "eyes",
    [3] = "lear",
    [4] = "rear",
    [5] = "neck1",
    [6] = "neck2",
    [7] = "back",
    [8] = "medal1",
    [9] = "medal2",
    [10] = "medal3",
    [11] = "medal4",
    [12] = "torso",
    [13] = "body",
    [14] = "waist",
    [15] = "arms",
    [16] = "lwrist",
    [17] = "rwrist",
    [18] = "hands",
    [19] = "lfinger",
    [20] = "rfinger",
    [21] = "legs",
    [22] = "feet",
    [23] = "shield",
    [24] = "wielded",
    [25] = "second",
    [26] = "hold",
    [27] = "float",
    [28] = "tattoo1",
    [29] = "tattoo2",
    [30] = "above",
    [31] = "portal",
    [32] = "sleeping",
}

snd.data.wearLocationReverse = {}
for k, v in pairs(snd.data.wearLocations) do
    snd.data.wearLocationReverse[v] = k
end

snd.data.optionalWearLocations = {
    [8] = true,  -- medal1
    [9] = true,  -- medal2
    [10] = true, -- medal3
    [11] = true, -- medal4
    [25] = true, -- second
    [28] = true, -- tattoo1
    [29] = true, -- tattoo2
    [30] = true, -- above
    [31] = true, -- portal
    [32] = true, -- sleeping
}

-------------------------------------------------------------------------------
-- Object Types
-------------------------------------------------------------------------------

snd.data.objectTypes = {
    [0] = "None",
    [1] = "light",
    [2] = "scroll",
    [3] = "wand",
    [4] = "staff",
    [5] = "weapon",
    [6] = "treasure",
    [7] = "armor",
    [8] = "potion",
    [9] = "furniture",
    [10] = "trash",
    [11] = "container",
    [12] = "drink",
    [13] = "key",
    [14] = "food",
    [15] = "boat",
    [16] = "mobcorpse",
    [17] = "corpse",
    [18] = "fountain",
    [19] = "pill",
    [20] = "portal",
    [21] = "beacon",
    [22] = "giftcard",
    [23] = "gold",
    [24] = "raw material",
    [25] = "campfire",
}

snd.data.objectTypesReverse = {}
for k, v in pairs(snd.data.objectTypes) do
    snd.data.objectTypesReverse[v] = k
end

-------------------------------------------------------------------------------
-- Continent IDs
-------------------------------------------------------------------------------

snd.data.continents = {
    [0] = "Mesolar",
    [1] = "Southern Ocean",
    [2] = "Gelidus",
    [3] = "Abend",
    [4] = "Alagh",
    [5] = "Uncharted Oceans",
    [6] = "Vidblain",
}

-------------------------------------------------------------------------------
-- Direction Mappings
-------------------------------------------------------------------------------

snd.data.directionMap = {
    north = "n",
    south = "s",
    east = "e",
    west = "w",
    up = "u",
    down = "d",
}

snd.data.directionReverse = {
    n = "north",
    s = "south",
    e = "east",
    w = "west",
    u = "up",
    d = "down",
}

-------------------------------------------------------------------------------
-- Area Default Start Rooms
-- Format: [areakey] = {start = "roomid", ct = "continent", vidblain = bool, noquest = bool}
-------------------------------------------------------------------------------

snd.data.areaDefaultStartRooms = {
    -- Continents
    ["abend"] = {start = "24909", ct = "3"},
    ["alagh"] = {start = "3224", ct = "4"},
    ["gelidus"] = {start = "18780", ct = "2"},
    ["mesolar"] = {start = "12664", ct = "0"},
    ["southern"] = {start = "5192", ct = "1"},
    ["uncharted"] = {start = "7701", ct = "5"},
    ["vidblain"] = {start = "33570", ct = "6", vidblain = true},
    
    -- A
    ["aardington"] = {start = "47509"},
    ["academy"] = {start = "35233"},
    ["adaldar"] = {start = "34400"},
    ["afterglow"] = {start = "38134"},
    ["agroth"] = {start = "11027"},
    ["ahner"] = {start = "30129"},
    ["alehouse"] = {start = "885"},
    ["amazon"] = {start = "1409"},
    ["amusement"] = {start = "29282"},
    ["andarin"] = {start = "2399"},
    ["annwn"] = {start = "28963"},
    ["anthrox"] = {start = "3993"},
    ["arboretum"] = {start = "39100"},
    ["arena"] = {start = "25768"},
    ["arisian"] = {start = "28144"},
    ["ascent"] = {start = "43150"},
    ["asherodan"] = {start = "37400", vidblain = true},
    ["astral"] = {start = "27882"},
    ["atlantis"] = {start = "10573"},
    ["autumn"] = {start = "13839"},
    ["avian"] = {start = "4334"},
    ["aylor"] = {start = "32418"},
    
    -- B
    ["bazaar"] = {start = "34454"},
    ["beer"] = {start = "20062"},
    ["believer"] = {start = "25940"},
    ["blackrose"] = {start = "1817"},
    ["bliss"] = {start = "29988"},
    ["bonds"] = {start = "23411"},
    
    -- C
    ["caldera"] = {start = "26341"},
    ["callhero"] = {start = "33031"},
    ["camps"] = {start = "4714"},
    ["canyon"] = {start = "25551"},
    ["caravan"] = {start = "16071"},
    ["cards"] = {start = "6255"},
    ["carnivale"] = {start = "28635"},
    ["cataclysm"] = {start = "19976"},
    ["cathedral"] = {start = "27497"},
    ["cats"] = {start = "40900"},
    ["chasm"] = {start = "29446"},
    ["chakra"] = {start = "0"},
    ["chantry"] = {start = "0"},
    ["chessboard"] = {start = "25513"},
    ["childsplay"] = {start = "678"},
    ["cineko"] = {start = "1507"},
    ["citadel"] = {start = "14963"},
    ["conflict"] = {start = "27711"},
    ["coral"] = {start = "4565"},
    ["cougarian"] = {start = "14311"},
    ["cove"] = {start = "49941"},
    ["cradle"] = {start = "11267"},
    ["crynn"] = {start = "43800"},
    
    -- D
    ["damned"] = {start = "10469"},
    ["darklight"] = {start = "19642", vidblain = true},
    ["darkside"] = {start = "15060"},
    ["ddoom"] = {start = "4193"},
    ["deadlights"] = {start = "16856"},
    ["deathtrap"] = {start = "1767"},
    ["deneria"] = {start = "35006"},
    ["desert"] = {start = "20186"},
    ["desolation"] = {start = "19532"},
    ["dhalgora"] = {start = "16755"},
    ["diatz"] = {start = "1254"},
    ["diner"] = {start = "36700"},
    ["dominia"] = {start = "42200"},
    ["down"] = {start = "25900"},
    ["drageran"] = {start = "1891"},
    ["dragon"] = {start = "10227"},
    ["draks"] = {start = "38200"},
    ["dream"] = {start = "22150"},
    ["dread"] = {start = "23501"},
    ["dusk"] = {start = "35700"},
    
    -- E
    ["earthplane"] = {start = "27804"},
    ["eastern"] = {start = "1045"},
    ["ecology"] = {start = "2500"},
    ["elemental"] = {start = "4050"},
    ["elford"] = {start = "7601"},
    ["emerald"] = {start = "5700"},
    ["empire"] = {start = "20412"},
    ["ethea"] = {start = "39900"},
    ["event"] = {start = "31300"},
    
    -- F
    ["faerie"] = {start = "2200"},
    ["falconry"] = {start = "10317"},
    ["farmyard"] = {start = "1700"},
    ["fens"] = {start = "16501"},
    ["fields"] = {start = "17430"},
    ["firenation"] = {start = "48200"},
    ["fireplanes"] = {start = "27874"},
    ["forest"] = {start = "13705"},
    ["fortress"] = {start = "1359"},
    ["framed"] = {start = "42700"},
    ["frontier"] = {start = "37500"},
    ["ftelemental"] = {start = "27728"},
    
    -- G
    ["gallery"] = {start = "22702"},
    ["gauntlet"] = {start = "4270"},
    ["gilda"] = {start = "21600"},
    ["gnomevillage"] = {start = "1190"},
    ["gold"] = {start = "14200"},
    ["graveyard"] = {start = "4150"},
    ["grinning"] = {start = "50500"},
    ["grungel"] = {start = "37700"},
    
    -- H
    ["hades"] = {start = "11760"},
    ["hatchling"] = {start = "23605"},
    ["haunted"] = {start = "36400"},
    ["hell"] = {start = "6200"},
    ["helling"] = {start = "17000"},
    ["highlands"] = {start = "6019"},
    ["hoard"] = {start = "22500"},
    ["hobgoblin"] = {start = "2700"},
    ["hospital"] = {start = "40700"},
    ["household"] = {start = "12851"},
    
    -- I
    ["icecliff"] = {start = "18844"},
    ["illoria"] = {start = "17301"},
    ["imagi"] = {start = "10800"},
    ["inferno"] = {start = "9001"},
    ["intercon"] = {start = "40300"},
    ["invasion"] = {start = "19201"},
    ["island"] = {start = "8600"},
    ["isles"] = {start = "41100"},
    
    -- J
    ["jungles"] = {start = "14100"},
    
    -- K
    ["kailaani"] = {start = "28501"},
    ["ketu"] = {start = "13200"},
    ["kimr"] = {start = "16100"},
    ["kingdomseria"] = {start = "29600"},
    ["kobold"] = {start = "1600"},
    ["kul"] = {start = "26500"},
    
    -- L
    ["labyrinth"] = {start = "15405"},
    ["lake"] = {start = "48600"},
    ["landofoz"] = {start = "29100"},
    ["laym"] = {start = "28400"},
    ["light"] = {start = "18200"},
    ["limbo"] = {start = "3501"},
    ["livingmine"] = {start = "22891"},
    ["longnight"] = {start = "32700"},
    ["losttime"] = {start = "30800"},
    ["lowlands"] = {start = "11501"},
    ["lunatic"] = {start = "44700"},
    
    -- M
    ["magictree"] = {start = "3900"},
    ["manor"] = {start = "2900"},
    ["masq"] = {start = "15700"},
    ["mellow"] = {start = "12100"},
    ["mica"] = {start = "13900"},
    ["midlands"] = {start = "15201"},
    ["mirrorplane"] = {start = "27956"},
    ["mists"] = {start = "21010"},
    ["moons"] = {start = "43500"},
    ["morgan"] = {start = "20820"},
    ["moria"] = {start = "7101"},
    ["mountains"] = {start = "20000"},
    ["mtolympus"] = {start = "3600"},
    ["mudwog"] = {start = "41800"},
    
    -- N
    ["nature"] = {start = "12431"},
    ["necro"] = {start = "1500"},
    ["nenukon"] = {start = "19801"},
    ["nether"] = {start = "18400"},
    ["newbie"] = {start = "9109"},
    ["northstar"] = {start = "17500"},
    
    -- O
    ["oceanmaze"] = {start = "2100"},
    ["offerman"] = {start = "36550"},
    ["ooku"] = {start = "41500"},
    ["oohlgrist"] = {start = "18000"},
    ["orca"] = {start = "8100"},
    ["orchan"] = {start = "17900"},
    ["orc"] = {start = "2000"},
    
    -- P
    ["palace"] = {start = "24100"},
    ["parliament"] = {start = "39500"},
    ["partroxis"] = {start = "47100"},
    ["pass"] = {start = "24700"},
    ["pathway"] = {start = "14500"},
    ["pern"] = {start = "11100"},
    ["plague"] = {start = "8900"},
    ["plains"] = {start = "6300"},
    ["pompeii"] = {start = "21200"},
    ["pyre"] = {start = "22297"},
    
    -- Q
    ["qong"] = {start = "36900"},
    
    -- R
    ["radiance"] = {start = "44200"},
    ["rainfall"] = {start = "3100"},
    ["realms"] = {start = "10400"},
    ["rebellion"] = {start = "33500"},
    ["refuge"] = {start = "49500"},
    ["revolution"] = {start = "30500"},
    ["rift"] = {start = "38500"},
    ["robin"] = {start = "5000"},
    ["rose"] = {start = "6600"},
    ["ruins"] = {start = "7000"},
    
    -- S
    ["safari"] = {start = "23900"},
    ["sanguine"] = {start = "19100"},
    ["sank"] = {start = "22000"},
    ["sanitarium"] = {start = "45800"},
    ["school"] = {start = "1900"},
    ["scourge"] = {start = "31600"},
    ["sdev"] = {start = "5400"},
    ["seaworld"] = {start = "21400"},
    ["secrets"] = {start = "31000"},
    ["seelie"] = {start = "37100"},
    ["sentinel"] = {start = "11900"},
    ["sewer"] = {start = "3400"},
    ["shadow"] = {start = "21800"},
    ["shire"] = {start = "8200"},
    ["shuman"] = {start = "7900"},
    ["siege"] = {start = "23219"},
    ["sirens"] = {start = "14701"},
    ["sishi"] = {start = "44900"},
    ["slaughter"] = {start = "8501"},
    ["smuggler"] = {start = "23000"},
    ["snuckles"] = {start = "45200"},
    ["sohtwo"] = {start = "32100"},
    ["southern2"] = {start = "46500"},
    ["spectral"] = {start = "6900"},
    ["spyder"] = {start = "13000"},
    ["starving"] = {start = "15900"},
    ["stone"] = {start = "34900"},
    ["storm"] = {start = "20600"},
    ["striker"] = {start = "5100"},
    ["sundown"] = {start = "12500"},
    ["swordcoast"] = {start = "25100"},
    
    -- T
    ["takeda"] = {start = "49100"},
    ["talsa"] = {start = "25300"},
    ["tanelorn"] = {start = "7300"},
    ["tehtena"] = {start = "33200"},
    ["temple"] = {start = "10000"},
    ["terroir"] = {start = "46800"},
    ["theran"] = {start = "15500"},
    ["titan"] = {start = "35500"},
    ["toybox"] = {start = "36200"},
    ["trade"] = {start = "39300"},
    ["transylvania"] = {start = "27200"},
    ["tribunal"] = {start = "40100"},
    ["trolls"] = {start = "6501"},
    ["tull"] = {start = "18600"},
    ["tyrennia"] = {start = "46100"},
    
    -- U
    ["underworld"] = {start = "8300"},
    ["unforgiven"] = {start = "10100"},
    ["unholy"] = {start = "12300"},
    ["unigma"] = {start = "24500"},
    ["unwilling"] = {start = "50000"},
    
    -- V
    ["valley"] = {start = "27400"},
    ["verume"] = {start = "9200"},
    ["vidblain2"] = {start = "34100", vidblain = true},
    ["vidblain3"] = {start = "38800", vidblain = true},
    ["vidblain4"] = {start = "43000", vidblain = true},
    ["volcano"] = {start = "12700"},
    ["voyagers"] = {start = "45500"},
    
    -- W
    ["war"] = {start = "11400"},
    ["waterfall"] = {start = "41200"},
    ["waterplane"] = {start = "27844"},
    ["wedding"] = {start = "32900"},
    ["western"] = {start = "1100"},
    ["wildwood"] = {start = "26100"},
    ["winterlands"] = {start = "37800"},
    ["wisna"] = {start = "16300"},
    ["witches"] = {start = "4400"},
    ["wooble"] = {start = "26700"},
    ["wylins"] = {start = "47700"},
    
    -- X
    
    -- Y
    ["yarr"] = {start = "35100"},
    ["yurgach"] = {start = "31950"},
    
    -- Z
    ["zenotherm"] = {start = "33700"},
    ["zoo"] = {start = "5901"},
}

-------------------------------------------------------------------------------
-- Mob Keyword Area Filters
-- These patterns help extract better keywords for specific areas
-------------------------------------------------------------------------------

snd.data.mobKeywordFilters = {
    ["adaldar"] = {{f = "^.*(el)vish (%a*%s?%a+)$", g = "%1 %2"}},
    ["bonds"] = {{f = "^(.*[bgry]%a+) dragon$", g = "%1"}},
    ["citadel"] = {{f = "^([bgjlmsv]%a+) ([ap]r%a+[el]) .+$", g = "%1 %2"}},
    ["elemental"] = {
        {f = "^(%a+)%'(%a+) (%a+)$", g = "%1 %3"},
        {f = "^wandering (%a+)%'(%a+) (%a+)$", g = "%1 %3"}
    },
    ["hatchling"] = {
        {f = "^(%a+) dragon (egg)$", g = "%1 %2"},
        {f = "^(%a+) dragon (hatchling)$", g = "%1 %2"},
        {f = "^(%a+ %a+) dragon whelp$", g = "%1"},
        {f = "^(%a+) dragon (whelp)$", g = "%1 %2"}
    },
    ["sirens"] = {{f = "^miss ([%a']+)%s?(%a*).*%a$", g = "%1 %2"}},
    ["sohtwo"] = {
        {f = "^(evil) %a+", g = "%1"},
        {f = "^(good) %a+", g = "%1"}
    },
    ["verume"] = {{f = "^lizardman (temple %a+)$", g = "%1"}},
    ["wooble"] = {
        {f = "^sea (%a+)$", g = "%1"},
        {f = "^sea (%a+ %a+)$", g = "%1"}
    },
}

-------------------------------------------------------------------------------
-- Mob Keyword Exceptions
-- Specific mobs that need custom keywords
-- Format: [area] = {[mobname] = keyword}
-------------------------------------------------------------------------------

snd.data.mobKeywordExceptions = {
    ["aardington"] = {
        ["a very large portrait"] = "large port",
    },
    ["alehouse"] = {
        ["a dancing male patron"] = "dancing male",
        ["a dancing female patron"] = "dancing female",
    },
    ["anthrox"] = {
        ["the little white rabbit"] = "rabb",
        ["the bee"] = "worker bee",
        ["an escaped creature"] = "prisoner creature",
        ['a "business" man'] = "business man",
    },
    ["ddoom"] = {
        ["a dangerous scorpion"] = "scorp",
        ["Lwji, the Sunrise great warrior"] = "lwji",
        ["Taji, the Sunset leader"] = "taji lead",
        ["Taji's personal advisor"] = "pers advi",
        ["Tjac, the Sunrise leader"] = "tjac lead",
        ["Tjac's personal advisor"] = "sunr advis",
        ["Yki, the great Sunset warrior"] = "yki",
    },
    ["deneria"] = {
        ["High Priest of Miad'Bir"] = "high miad",
    },
    ["desert"] = {
        ["a village citizen"] = "citi",
    },
    ["fields"] = {
        ["a mutated goat"] = "goat",
    },
    ["fortress"] = {
        ["a grizzled goblin dressed in skins"] = "grizz gobl",
        ["Blood Silk, Collector of souls, Queen of the spiders"] = "silk queen",
    },
    ["hell"] = {
        ["a scrumptious chicken pot pie"] = "chicken pot pie",
        ["a yummy vegetable pot pie"] = "vegetable pot pie",
        ["a yummy beef pot pie"] = "beef pot pie",
    },
    ["illoria"] = {
        ["the King and Queen's Guard"] = "pers guard",
    },
    ["landofoz"] = {
        ["one of Dorothy's uncles"] = "doroth uncle",
    },
    ["laym"] = {
        ["an elite guard of the church"] = "elit guar",
    },
    ["livingmine"] = {
        ["a member of the 'Cal tribe"] = "memb cal",
        ["a member of the 'Sorr tribe"] = "memb sorr",
        ["a member of the 'Tai tribe"] = "memb tai",
        ["Dak'tai's shaman"] = "dakt shama",
        ["the 'Tai chieftain"] = "tai chief",
    },
    ["longnight"] = {
        ["Mr. Roberge"] = "car rober",
    },
    ["losttime"] = {
        ["T-Rex"] = "T-rex",
        ["Great White Shark"] = "white shark",
    },
    ["manor"] = {
        ["Aremata-Popua"] = "aremata-pop",
        ["Aremata-Rorua"] = "aremata-ror",
    },
    ["masq"] = {
        ["a gentleman on the way to the ball"] = "gentl",
        ["a very attractive woman"] = "attr woman",
    },
    ["necro"] = {
        ["the head necromancer's assistant"] = "old mage assist",
    },
    ["northstar"] = {
        ["a Blood Ring elite warrior"] = "elit warr",
        ["Daryoon, a priest of nature"] = "dary pries",
        ["Tristam, the Prince of the Orcs"] = "trist orc",
    },
    ["sanctity"] = {
        ["a half-converted human"] = "human",
    },
    ["siege"] = {
        ["a kobold eating lunch"] = "kobold eating",
        ["a large mole"] = "mole",
        ["a very large firefly"] = "larg firef",
        ["the fattest kobold ever"] = "fat kobold",
        ["an oddly tall and clean kobold"] = "tall kobold",
    },
    ["snuckles"] = {
        ["the snuckle"] = "male snuckle",
        ["Sarah, the grieving snuckle"] = "sarah griev",
    },
    ["sohtwo"] = {
        ["An evil form of Sagen"] = "notcarlsagen",
        ["Angelic Demonspawn"] = "angelic",
        ["Bubbly Obyron"] = "fuzzybunny",
        ["Dejected Broud"] = "dejected",
        ["Disagreeable Rumour"] = "obstinate",
        ["Disoriented Dadrake"] = "letsturnlefthere",
        ["Evil Aaeron"] = "shinythings",
        ["Evil Althalus"] = "homeskillet",
        ["Evil Belmont"] = "bridgetroll",
        ["Evil Domain"] = "66",
        ["Evil Euphonix"] = "ragbrai",
        ["Evil Ghaan"] = "longghaan",
        ["Evil Halo"] = "jackandcoke",
        ["Evil Ikyu"] = "ickypoo",
        ["Evil Justme"] = "helperisme",
        ["Evil Kharpern"] = "kittyimm",
        ["Evil KlauWaard"] = "tricksy",
        ["Evil Kt"] = "ktkat",
        ["Evil Lasher"] = "thearchitect",
        ["Evil Madcatz"] = "mathizard",
        ["Evil Maerchyng"] = "maerchyng",
        ["Evil Morrigu"] = "morrigu",
        ["Evil OrcWarrior"] = "sheepshagger",
        ["Evil Pane"] = "painintheneck",
        ["Evil Plaideleon"] = "crazycanadian",
        ["Evil Rekhart"] = "hartsawreck",
        ["Evil Sarlock"] = "l33td00d",
        ["Evil Tela"] = "telllllllla",
        ["Evil Timeghost"] = "floppyimm",
        ["Good Tripitaka"] = "laketripitaka",
        ["Evil Tymme"] = "hourglass",
        ["Evil Vladia"] = "sexyvamp",
        ["Evil Whitdjinn"] = "thundercat",
        ["Evil Windjammer"] = "justsomeimm",
        ["Evil Wolfe"] = "likeobybutbritish",
        ["Evil Xyzzy"] = "weirdcode",
        ["Good Aerianne"] = "pointyears",
        ["Good Cadaver"] = "newbiehater",
        ["Good Delight"] = "turkishdelight",
        ["Good Dirtworm"] = "wormy",
        ["Good Eclaboussure"] = "dropbearimm",
        ["Good Filt"] = "plainolefilt",
        ["Good Glimmer"] = "betterhalfofclaire",
        ["Good Kinson"] = "upgradeboy",
        ["Good Lumina"] = "thievesrus",
        ["Good Oladon"] = "spellingbee",
        ["Good Rhuli"] = "rulistheworld",
        ["Good Sausage"] = "fatbreakfast",
        ["Good Sirene"] = "warriorprincess",
        ["Good Takihisis"] = "dragonlady",
        ["Good Terrill"] = "askcitron",
        ["Good Tyanon"] = "tieoneon",
        ["Good Valkur"] = "demonlord",
        ["Good Vilgan"] = "unabridged",
        ["Good Xantcha"] = "pokerimm",
        ["Good Zane"] = "inzanity",
        ["Goodie Goodie Jaenelle"] = "goodie",
        ["Impatient Styliann"] = "willyouhurryup",
        ["Kinda-Sorta Good Whisper"] = "kinda",
        ["Master Shen"] = "master",
        ["Mathematical Mordist"] = "complex",
        ["Nascaard Rezit"] = "nascaard",
        ["Pandemonium Penthesilea"] = "pandemonium",
        ["Record Holding Guinness"] = "cantwriteatall",
        ["Singing Paramore"] = "failedmusician",
        ["Sith Lord Neeper"] = "sith",
        ["Smurfy Laren"] = "lovethemsmurfs",
        ["Sober Citron"] = "sober",
        ["Socialite Arthon"] = "airhead",
        ["Straight Dreamfyre"] = "straight",
        ["The cool version of Xeno"] = "onex",
        ["The Pancake Flat"] = "pancake",
        ["Tjopping Quadrapus"] = "tjopping",
        ["Unhelpful Claire"] = "cookies",
        ["Unremarkable Korridel"] = "unremarkable",
        ["Unrestrained Elvandar"] = "omgsheneverstopstalking",
        ["Warsnail Anaristos"] = "warsnail",
        ["Cuddlebear Koala"] = "cuddlebear",
        ["(Helper) Fenix"] = "helper",
    },
    ["stone"] = {
        ["a Citadel of Stone Cityguard"] = "cit guar",
    },
    ["talsa"] = {
        ["a dwarven mercenary"] = "dwar merc",
    },
    ["wooble"] = {
        ["the Sea Snake Master-at-Arms"] = "snake mast",
    },
    ["yarr"] = {
        ["a pirate sorting the treasure"] = "pirat sort",
        ["a pirate stealing some treasure"] = "pirat steal",
    },
    ["zoo"] = {
        ["a black-footed pine marten"] = "pine marte",
    },
}

-------------------------------------------------------------------------------
-- Words to omit when guessing keywords
-------------------------------------------------------------------------------

snd.data.keywordOmitWords = {
    ["a"] = true,
    ["an"] = true,
    ["and"] = true,
    ["of"] = true,
    ["or"] = true,
    ["some"] = true,
    ["the"] = true,
}

-- Search and Destroy: Data module loaded silently
