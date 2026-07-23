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
    ["abend"] = {start = "24909", ct = "3"}, -- Continents
    ["alagh"] = {start = "3224", ct = "4"},
    ["gelidus"] = {start = "18780", ct = "2"},
    ["mesolar"] = {start = "12664", ct = "0"},
    ["southern"] = {start = "5192", ct = "1"},
    ["uncharted"] = {start = "7701", ct = "5"},
    ["vidblain"] = {start = "33570", ct = "6", vidblain = true},
    ["aardington"] = {start = "47509"}, -- A --
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
    ["bazaar"] = {start = "34454"}, -- B --
    ["beer"] = {start = "20062"},
    ["believer"] = {start = "25940"},
    ["blackrose"] = {start = "1817"},
    ["bliss"] = {start = "29988"},
    ["bonds"] = {start = "23411"},
    ["caldera"] = {start = "26341"}, -- C --
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
    ["damned"] = {start = "10469"}, -- D --
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
    ["dortmund"] = {start = "16577"},
    ["drageran"] = {start = "25894"},
    ["dread"] = {start = "26075"},
    ["dsr"] = {start = "30030"},
    ["dundoom"] = {start = "25661"},
    ["dunes"] = {start = "42170"},
    ["dunoir"] = {start = "14222"},
    ["duskvalley"] = {start = "37301"},
    ["dynasty"] = {start = "30799"},
    ["earthlords"] = {start = "42000"}, -- E --
    ["earthplane"] = {start = "1354"},
    ["elemental"] = {start = "41624"},
    ["empire"] = {start = "32203"},
    ["empyrean"] = {start = "14042"},
    ["entropy"] = {start = "29773"},
    ["fantasy"] = {start = "15205"}, -- F --
    ["farm"] = {start = "10676"},
    ["fayke"] = {start = "30418"},
    ["fens"] = {start = "16528"},
    ["fields"] = {start = "29232"},
    ["firebird"] = {start = "32885"},
    ["firenation"] = {start = "41879"},
    ["fireswamp"] = {start = "34755"},
    ["fortress"] = {start = "31835"},
    ["fortune"] = {start = "38561"},
    ["fractured"] = {start = "17033"},
    ["ft1"] = {start = "1205"},
    ["ftii"] = {start = "26673"},
    ["gallows"] = {start = "4344"}, -- G --
    ["gathering"] = {start = "36451"},
    ["gauntlet"] = {start = "31652"},
    ["gilda"] = {start = "4243"},
    ["glamdursil"] = {start = "35055"},
    ["glimmerdim"] = {start = "26252"},
    ["gnomalin"] = {start = "34397"},
    ["goldrush"] = {start = "15014"},
    ["graveyard"] = {start = "28918"},
    ["greece"] = {start = "2089"},
    ["gwillim"] = {start = "25974"},
    ["hades"] = {start = "29161"}, -- H --
    ["hatchling"] = {start = "34670"},
    ["hawklord"] = {start = "40550"},
    ["hedge"] = {start = "15146"},
    ["helegear"] = {start = "30699"},
    ["hell"] = {start = "30984"},
    ["hoard"] = {start = "1675"},
    ["hodgepodge"] = {start = "30469"},
    ["horath"] = {start = "91"},
    ["horizon"] = {start = "31959"},
    ["illoria"] = {start = "10420"},
    ["imagi"] = {start = "36800"}, -- I --
    ["imperial"] = {start = "16966", vidblain = true},
    ["infamy"] = {start = "26641"},
    ["infest"] = {start = "16165"},
    ["insan"] = {start = "6850"},
    ["jenny"] = {start = "29637"}, -- J --
    ["jotun"] = {start = "31508"},
    ["kearvek"] = {start = "29722"}, -- K --
    ["kerofk"] = {start = "16405"},
    ["ketu"] = {start = "35114"},
    ["kingsholm"] = {start = "27522"},
    ["knossos"] = {start = "28193"},
    ["kobaloi"] = {start = "10691"},
    ["kultiras"] = {start = "31161"},
    ["lab"] = {start = "28684"}, -- L --
    ["labyrinth"] = {start = "31405"},
    ["lagoon"] = {start = "30549"},
    ["landofoz"] = {start = "510"},
    ["laym"] = {start = "6005"},
    ["legend"] = {start = "16224"},
    ["lemdagor"] = {start = "1966"},
    ["lidnesh"] = {start = "27995"},
    ["livingmine"] = {start = "37008"},
    ["logging"] = {start = "31254"},
    ["longnight"] = {start = "26367"},
    ["losttime"] = {start = "28584"},
    ["lowlands"] = {start = "28044"},
    ["lplanes"] = {start = "29364"},
    ["maelstrom"] = {start = "38058"}, -- M --
    ["manor"] = {start = "10621"},
    ["masq"] = {start = "29840"},
    ["mayhem"] = {start = "1866"},
    ["melody"] = {start = "14172"},
    ["minos"] = {start = "20472"},
    ["mistridge"] = {start = "4491"},
    ["monastery"] = {start = "15756"},
    ["mudwog"] = {start = "2347"},
    ["nanjiki"] = {start = "11203"}, -- N --
    ["necro"] = {start = "29922"},
    ["nenukon"] = {start = "31784"},
    ["newthalos"] = {start = "23853"},
    ["ninehells"] = {start = "4613"},
    ["northstar"] = {start = "11127"},
    ["nottingham"] = {start = "11077"},
    ["nulan"] = {start = "37900"},
    ["nursing"] = {start = "31977"},
    ["nynewoods"] = {start = "23562"},
    ["oceanpark"] = {start = "39600"}, -- O --
    ["omentor"] = {start = "15579", vidblain = true},
    ["ooku"] = {start = "39000"},
    ["origins"] = {start = "35900"},
    ["orlando"] = {start = "30331"},
    ["paradise"] = {start = "29624"}, -- P --
    ["partroxis"] = {start = "5814"},
    ["peninsula"] = {start = "35701"},
    ["petstore"] = {start = "995"},
    ["pompeii"] = {start = "57"},
    ["promises"] = {start = "25819"},
    ["prosper"] = {start = "28268"},
    ["qong"] = {start = "16115"}, -- Q --
    ["quarry"] = {start = "23510"},
    ["radiance"] = {start = "19805"}, -- R --
    ["raga"] = {start = "19861"},
    ["raukora"] = {start = "6040"},
    ["rebellion"] = {start = "10305"},
    ["remcon"] = {start = "25837"},
    ["reme"] = {start = "32703"},
    ["rosewood"] = {start = "6901"},
    ["ruins"] = {start = "16805"},
    ["sagewood"] = {start = "28754"}, -- S --
    ["sahuagin"] = {start = "34592"},
    ["salt"] = {start = "4538"},
    ["sanctity"] = {start = "10518"},
    ["sanctum"] = {start = "15307"},
    ["sandcastle"] = {start = "37701"},
    ["sanguine"] = {start = "15436"},
    ["scarred"] = {start = "34036"},
    ["sendhian"] = {start = "20288", vidblain = true},
    ["sennarre"] = {start = "15491"},
    ["shadowsend"] = {start = "40096"},
    ["shouggoth"] = {start = "34087"},
    ["siege"] = {start = "43265"},
    ["sirens"] = {start = "16298"},
    ["slaughter"] = {start = "1601"},
    ["snuckles"] = {start = "182"},
    ["soh"] = {start = "25611"},
    ["sohtwo"] = {start = "30752"},
    ["solan"] = {start = "23713"},
    ["songpalace"] = {start = "47013"},
    ["spyreknow"] = {start = "34800"},
    ["stone"] = {start = "11386"},
    ["storm"] = {start = "6304"},
    ["stormhaven"] = {start = "20649"},
    ["stronghold"] = {start = "20572"},
    ["stuff"] = {start = "40400"},
    ["takeda"] = {start = "15952"}, -- T --
    ["talsa"] = {start = "26917"},
    ["temple"] = {start = "31597"},
    ["tanra"] = {start = "46913"},
    ["terra"] = {start = "19679"},
    ["terramire"] = {start = "4493"},
    ["thieves"] = {start = "7"},
    ["tilule"] = {start = "39771"},
    ["times"] = {start = "28463"},
    ["tirna"] = {start = "20136"},
    ["titan"] = {start = "38234"},
    ["tol"] = {start = "16325"},
    ["tombs"] = {start = "15385"},
    ["umari"] = {start = "36601"}, -- U --
    ["underdark"] = {start = "27341"},
    ["uplanes"] = {start = "29364"},
    ["uprising"] = {start = "15382"},
    ["vale"] = {start = "1036"}, -- V --
    ["verdure"] = {start = "24090"},
    ["verume"] = {start = "30607"},
    ["village"] = {start = "30850"},
    ["vlad"] = {start = "15970"},
    ["volcano"] = {start = "6091"},
    ["weather"] = {start = "40499"}, -- W --
    ["werewood"] = {start = "30956"},
    ["wildwood"] = {start = "322"},
    ["winter"] = {start = "1306"},
    ["wizards"] = {start = "31316"},
    ["wonders"] = {start = "32981"},
    ["wooble"] = {start = "11335"},
    ["woodelves"] = {start = "32199"},
    ["wtc"] = {start = "37895"},
    ["wyrm"] = {start = "28847"},
    ["xmas"] = {start = "6212"}, -- X --
    ["xylmos"] = {start = "472"},
    ["yarr"] = {start = "30281"},
    ["ygg"] = {start = "24186"}, -- Y --
    ["yurgach"] = {start = "29450"},
    ["zangar"] = {start = "6164"}, -- Z --
    ["zenith"] = {start = "23681"},
    ["zodiac"] = {start = "15857"},
    ["zoo"] = {start = "5920"},
    ["zyian"] = {start = "729"},
    -- Non-questable Areas
    ["manor1"] = {start = "14460", noquest = true}, -- Manor areas
    ["manor3"] = {start = "20836", noquest = true},
    ["manorisle"] = {start = "6366", noquest = true},
    ["manormount"] = {start = "39449", noquest = true},
    ["manorsea"] = {start = "35003", noquest = true},
    ["manorville"] = {start = "35004", noquest = true},
    ["manorwoods"] = {start = "35002", noquest = true},
    ["blackclaw"] = {start = "   -1", noquest = true}, -- epic areas
    ["geniewish"] = {start = "38464", noquest = true},
    ["icefall"] = {start = "38701", noquest = true},
    ["inferno"] = {start = "-1", noquest = true},
    ["oradrin"] = {start = "25436", noquest = true},
    ["transcend"] = {start = "0", noquest = true},
    ["winds"] = {start = "39900", noquest = true},
    ["badtrip"] = {start = "32877", noquest = true}, -- Other no-quest areas
    ["birthday"] = {start = "10920", noquest = true},
    ["seaking"] = {start = "-1", noquest = true},
    ["amazonclan"] = {start = "34212", noquest = true}, -- Public clan halls
    ["bard"] = {start = "30538", noquest = true},
    ["bootcamp"] = {start = "49256", noquest = true},
    ["cabal"] = {start = "15704", noquest = true},
    ["chaos"] = {start = "28909", noquest = true},
    ["crimson"] = {start = "27989", noquest = true},
    ["crusaders"] = {start = "31122", noquest = true},
    ["daoine"] = {start = "30949", noquest = true},
    ["doh"] = {start = "16803", noquest = true},
    ["dominion"] = {start = "5863", noquest = true},
    ["dragon"] = {start = "642", noquest = true},
    ["druid"] = {start = "29582", noquest = true},
    ["emerald"] = {start = "831", noquest = true},
    ["gaardian"] = {start = "20026", noquest = true},
    ["imperium"] = {start = "30415", noquest = true},
    ["light"] = {start = "2339", noquest = true},
    ["loqui"] = {start = "28580", noquest = true},
    ["masaki"] = {start = "15852", noquest = true},
    ["perdition"] = {start = "19968", noquest = true},
    ["pyre"] = {start = "15141", noquest = true},
    ["romani"] = {start = "24180", noquest = true},
    ["seekers"] = {start = "14165", noquest = true},
    ["shadokil"] = {start = "32407", noquest = true},
    ["tanelorn"] = {start = "31561", noquest = true},
    ["tao"] = {start = "29210", noquest = true},
    ["touchstone"] = {start = "28346", noquest = true},
    ["twinlobe"] = {start = "15575", noquest = true},
    ["vanir"] = {start = "878", noquest = true},
    ["watchmen"] = {start = "32342", noquest = true},
    ["baal"] = {start = "-1", noquest = true}, -- Closed clan halls
    ["hook"] = {start = "-1", noquest = true},
    ["retri"] = {start = "-1", noquest = true},
    ["rhabdo"] = {start = "-1", noquest = true},
    ["rogues"] = {start = "-1", noquest = true},
    ["xunti"] = {start = "-1", noquest = true},
    ["challenge"] = {start = "-1", noquest = true}, -- Normally inaccessible areas, or which lack a sensible starting room.
    ["immhomes"] = {start = "-1", noquest = true},
    ["lasertwo"] = {start = "-1", noquest = true},
    ["limbo"] = {start = "-1", noquest = true},
    ["lualand"] = {start = "-1", noquest = true},
    ["midgaard"] = {start = "-1", noquest = true},
    ["oldclanone"] = {start = "-1", noquest = true},
    ["oldclantwo"] = {start = "-1", noquest = true},
    ["oldclanthr"] = {start = "-1", noquest = true},
    ["oldclanfou"] = {start = "-1", noquest = true},
    ["vault"] = {start = "-1", noquest = true},
    ["warzone"] = {start = "-1", noquest = true},
    ["wolfmaze"] = {start = "-1", noquest = true}
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
