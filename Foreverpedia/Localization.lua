local _, ns = ...

local Locale = {}
ns.Locale = Locale

local strings = {
    ruRU = {
        addon_subtitle = "Справочник предметов",
        back = "‹ Назад", back_tip = "Вернуться к предыдущему предмету",
        options = "Опции", language = "Язык интерфейса",
        russian = "Русский", english = "English",
        apply = "Применить",
        reload_note = "При смене языка интерфейс будет перезагружен.",
        show_minimap_button = "Показывать кнопку у миникарты",
        show_minimap_button_tip = "Кнопка позволяет быстро открыть окно Foreverpedia для ручного поиска предмета.",
        addon_settings_description = "Настройки интерфейса Foreverpedia.",
        minimap_button_click = "ЛКМ: открыть или закрыть Foreverpedia",
        minimap_button_drag = "Перетащите, чтобы переместить кнопку вокруг миникарты",
        gamepad_tooltip_open = "Зажмите R3: открыть в Foreverpedia",
        gamepad_button_a = "A", gamepad_button_b = "B",
        gamepad_button_x = "X", gamepad_button_y = "Y",
        gamepad_button_lb = "LB", gamepad_button_rb = "RB",
        gamepad_button_lt = "LT", gamepad_button_rt = "RT",
        gamepad_button_view = "VIEW",
        gamepad_select = "Выбрать", gamepad_back = "Назад",
        gamepad_close = "Закрыть", gamepad_top = "Верх",
        gamepad_list = "Список", gamepad_tree = "Дерево",
        gamepad_details = "Детали", gamepad_recipe_tree = "Дерево рецепта",
        gamepad_filters = "Фильтры", gamepad_chain = "Цепочка",
        gamepad_combo_separator = "+",
        gamepad_game = "Игра",
        gamepad_window = "Окно",
        data_sources_title = "Источники данных",
        data_questie_live = "QuestieDB: %s (подключена)",
        data_questie_snapshot = "QuestieDB: снимок %s",
        data_builds = "База / клиент: %s / %s",
        data_local = "Наблюдения: %d  •  живые рецепты: %d",
        data_cmangos_enabled = "CMaNGOS Classic: исторические источники включены",
        data_cmangos_disabled = "CMaNGOS Classic: исторические источники недоступны",
        search = "Поиск:", search_placeholder = "Название предмета",
        search_result = "%s  |cff777777ID %d|r",
        uses = "ПРИМЕНЕНИЕ", sources = "ИСТОЧНИКИ", details = "ДЕТАЛИ",
        craft_chain = "Цепочка крафта  ›", craft_chain_title = "ЦЕПОЧКА КРАФТА",
        craft_chain_tip1 = "Показать, из чего создаётся предмет",
        craft_chain_tip2 = "и где он используется дальше.",
        item = "Предмет", item_number = "Предмет #%d", item_id = "ID предмета: %d",
        loading_item = "Загрузка данных предмета…",
        item_not_found = "Предмет не найден в базе.",
        client_item_data_incomplete = "Клиент не предоставил полные данные для части ингредиентов.",
        item_level = "ур. предмета %d",
        footer = "ID %d  •  база %s  •  источников %d  •  применений %d",
        choose_detail = "Выберите рецепт, способность или источник слева.",
        source_section = "Источники",
        no_uses = "В текущей базе нет известных применений. Это не означает, что их нет в игре.",
        no_sources = "В текущей базе нет известных источников. Это не означает, что предмет недоступен.",
        profession = "Профессия", professions = "Профессии", quests = "Задания",
        class_ability = "Классовая способность", class_abilities = "Классовые способности",
        class_ability_row = "%s  •  расходуется ×%d",
        class_ability_consumes = "Расходует этот предмет: ×%d",
        class_ability_class = "Класс: %s", unknown_class = "Неизвестный класс",
        class_warrior = "Воин", class_paladin = "Паладин", class_hunter = "Охотник",
        class_rogue = "Разбойник", class_priest = "Жрец", class_deathknight = "Рыцарь смерти",
        class_shaman = "Шаман", class_mage = "Маг", class_warlock = "Чернокнижник",
        class_monk = "Монах", class_druid = "Друид",
        class_demonhunter = "Охотник на демонов", class_evoker = "Пробудитель",
        profession_with_requirement = "%s  •  требуется навык %d",
        learning = "Обучение", creature_drop = "Добыча с существ", drop = "Добыча",
        pickpocketing = "Карманные кражи", pickpocket = "Карманная кража",
        disenchanting = "Распыление", disenchant = "Распыление",
        spell_sources = "Заклинания и особые действия", spell_loot = "Заклинание или особое действие",
        mail_sources = "Почта", mail = "Почта",
        fishing = "Рыбалка", craft = "Крафт", herbs = "Травы", herb = "Трава",
        objects = "Сундуки и объекты", object = "Объект", vendor = "Торговец",
        vendors = "Торговцы", containers = "Контейнеры", container = "Контейнер",
        gathering = "Сбор", professional_gathering = "Профессиональный сбор",
        quest = "Задание", quest_reward = "Награда за задание",
        starts_quest = "Начинает задание", teaches = "Обучает",
        reputation = "Репутация", exchange = "Обмен", other = "Другое",
        unknown_source = "Источник пока неизвестен", unknown_location = "Локация неизвестна",
        object_or_chest = "Объект или сундук", recipe = "Рецепт",
        depth = "Глубина: %d", professions_label = "Профессии:",
        profession_prefix = "Профессия: %s", sources_prefix = "Источники: %s",
        additional_recipes = "Дополнительных рецептов: %d",
        tree_center = "ЛКМ: сделать центром цепочки",
        tree_open = "Alt + ЛКМ: открыть страницу предмета",
        player_profession = "Профессия персонажа", filter_on = "Фильтр включён",
        filter_off = "Фильтр выключен", click_toggle = "ЛКМ: переключить",
        filter_all = "Все", filter_none = "Ничего", filter_reset = "Сброс",
        filter_all_tip = "Включить все профессии в фильтре",
        filter_none_tip = "Выключить все профессии, включая профессии персонажа",
        filter_reset_tip = "Оставить включёнными только профессии персонажа",
        tree_hint = "ЛКМ — центрировать  •  Alt + ЛКМ — открыть предмет",
        hidden_branches = "  •  скрыто ветвей: %d", filtered_branches = "  •  выключено фильтром: %d",
        both_factions = "Обе фракции", alliance = "Альянс", horde = "Орда",
        special_requirements = "Особые требования", level = "Уровень %d",
        level_range = "Уровень %d–%d", unknown_profession = "Неизвестная профессия",
        open_water = "Открытая вода", fishing_object = "Рыболовный объект",
        fishing_pool = "Косяк или рыболовный объект", known_source_types = "Известных типов источников: %d",
        price_unknown = "цена неизвестна", money = "%dз %dс %dм", more = "и ещё %d",
        alt_open = "Alt + ЛКМ: открыть в Foreverpedia", coordinates = "Координаты: %.1f, %.1f",
        open_map = "Открыть карту и поставить метку", trainers = "Тренеры",
        source_undefined = "Источник не определён", quest_level = "Уровень задания: %s",
        faction = "Фракция: %s", starts_at = "Начинается у: %s%s",
        source_unknown = "Источник неизвестен", more_coordinates = "Ещё координат: %d",
        ingredients = "ИНГРЕДИЕНТЫ", no_ingredients = "Для этого рецепта ингредиенты не указаны.",
        ingredient_alt = "Alt + ЛКМ по ингредиенту открывает его страницу.",
        ingredient_gamepad = "Зажмите R3 на ингредиенте, чтобы открыть его страницу.",
        acquisition_sources = "ИСТОЧНИКИ ПОЛУЧЕНИЯ", water_type = "Тип водоёма: %s",
        chance = "Шанс: %s", quantity = "Количество: %s", location = "Локация: %s",
        points = "Точек: %d", points_hidden = "Точек: %d (координаты скрыты)",
        alt_result = "Alt + ЛКМ: открыть результат в Foreverpedia",
        unknown = "неизвестно", unknown_chance = "неизвестен", unnamed = "Без названия",
        locations_count = "локаций: %d", zone = "Зона: %s",
        zone_number = "Зона #%d", recipe_item_unknown = "Клиент содержит предмет-рецепт (ID %s), но не его источник.",
        vendor_observe = "Продавец будет добавлен после встречи с ним в игре.",
        per_stack = " за %d", classic_data = "данные Classic Era",
        classic_warning = "Источник основан на данных Classic Era и может отличаться в WoW Forever.",
        drop_row = "%s  •  шанс %s",
        spell = "Заклинание", sells_item = "Продаёт предмет",
        looted_object = "Добывается из объекта", may_contain = "Может находиться внутри",
        spell_loot_detail = "Добыча, создаваемая игровым заклинанием или особым действием",
        mail_source = "Получение по внутриигровой почте",
        mail_templates_count = "Известных почтовых сценариев: %d",
        source_items_count = "Подходящих предметов в базе: %d",
        disenchant_items_level = "Предметы %s качества, ур. предмета %d",
        disenchant_items_range = "Предметы %s качества, ур. предмета %d–%d",
        quality_poor = "низкого", quality_common = "обычного",
        quality_uncommon = "необычного", quality_rare = "редкого",
        quality_epic = "эпического", quality_legendary = "легендарного",
        quality_unknown = "неизвестного",
        quest_reward_detail = "Награда за выполнение", quest_related = "Предмет связан с заданием",
        starts_quest_detail = "Использование предмета начинает задание",
        teaches_detail = "Предмет обучает заклинанию", creates_requires = "Создаёт: %s · требуется %d",
        requires = "Требуется: %d", client_dataset = "QuestieDB %s + клиент %s",
        snapshot_dataset = "снимок QuestieDB %s + клиент %s",
        questie_install_hint = "Установите QuestieDB для более полной информации: координат, описаний заданий и дополнительных деталей.",
        local_observation = "Локальное наблюдение",
        live_recipe_provenance = "Наблюдение окна профессии, клиент %s",
        merchant_observed = "Обнаружено у торговца",
        quest_item_required = "Предмет требуется для задания",
        npc_number = "NPC #%d", object_number = "Объект #%d", quest_number = "Задание #%d",
        unknown_vendor = "Торговец",
        core_item_id_error = "не удалось определить ID предмета.",
        core_click_hook_unavailable = "HandleModifiedItemClick недоступен; используйте /fp <itemID>.",
        core_help = "Alt+ЛКМ или долгое нажатие R3 по предмету; /fp открывает поиск, /fp <itemID> — предмет.",
        core_expected_item = "ожидается ID или ссылка на предмет.",
        core_incompatible = "База данных Foreverpedia несовместима.",
        core_interface_warning = "сборка рассчитана на интерфейс %d, клиент сообщает %s.",
        core_data_build_warning = "клиент %s, база предметов и рецептов %s — новые данные могут отсутствовать.",
        core_update_available = "установлена версия %s, доступна версия %s. Рекомендуется обновить аддон на CurseForge.",
        update_available_banner = "Доступна версия %s — рекомендуется обновить аддон",
        core_status = "интерфейс %s, QuestieDB %s (контракт %s), клиентская база %s, индекс дропа: %s, локальных наблюдений %d, записей кэша %d.",
        yes = "да", no = "нет", unknown_version = "неизвестна", not_installed = "не установлена",
        data_missing = "Foreverpedia_Data не загружена или повреждена. Установите все папки из архива Foreverpedia.",
        data_schema_incompatible = "Версия схемы Foreverpedia_Data несовместима с этим аддоном.",
        data_version_required = "требуется Foreverpedia_Data %s или новее; установлена %s.",
        questie_missing = "QuestieDB не загружена. Установите все папки из архива Foreverpedia.",
        questie_version_required = "требуется QuestieDB %s или новее; установлена %s.",
    },
    enUS = {
        addon_subtitle = "Item encyclopedia",
        back = "‹ Back", back_tip = "Return to the previous item",
        options = "Options", language = "Interface language",
        russian = "Русский", english = "English",
        apply = "Apply",
        reload_note = "Changing the language will reload the interface.",
        show_minimap_button = "Show minimap button",
        show_minimap_button_tip = "The button provides quick access to Foreverpedia for manual item searches.",
        addon_settings_description = "Foreverpedia interface settings.",
        minimap_button_click = "Left-click: open or close Foreverpedia",
        minimap_button_drag = "Drag to move the button around the minimap",
        gamepad_tooltip_open = "Hold R3: open in Foreverpedia",
        gamepad_button_a = "A", gamepad_button_b = "B",
        gamepad_button_x = "X", gamepad_button_y = "Y",
        gamepad_button_lb = "LB", gamepad_button_rb = "RB",
        gamepad_button_lt = "LT", gamepad_button_rt = "RT",
        gamepad_button_view = "VIEW",
        gamepad_select = "Select", gamepad_back = "Back",
        gamepad_close = "Close", gamepad_top = "Top bar",
        gamepad_list = "List", gamepad_tree = "Craft tree",
        gamepad_details = "Details", gamepad_recipe_tree = "Recipe tree",
        gamepad_filters = "Filters", gamepad_chain = "Chain",
        gamepad_combo_separator = "+",
        gamepad_game = "Game",
        gamepad_window = "Window",
        data_sources_title = "Data sources",
        data_questie_live = "QuestieDB: %s (connected)",
        data_questie_snapshot = "QuestieDB: %s snapshot",
        data_builds = "Database / client: %s / %s",
        data_local = "Observations: %d  •  live recipes: %d",
        data_cmangos_enabled = "CMaNGOS Classic: historical sources enabled",
        data_cmangos_disabled = "CMaNGOS Classic: historical sources unavailable",
        search = "Search:", search_placeholder = "Item name",
        search_result = "%s  |cff777777ID %d|r",
        uses = "USES", sources = "SOURCES", details = "DETAILS",
        craft_chain = "Crafting chain  ›", craft_chain_title = "CRAFTING CHAIN",
        craft_chain_tip1 = "Show how this item is crafted",
        craft_chain_tip2 = "and which recipes use it.",
        item = "Item", item_number = "Item #%d", item_id = "Item ID: %d",
        loading_item = "Loading item data…",
        item_not_found = "Item not found in the database.",
        client_item_data_incomplete = "The client did not provide complete data for some ingredients.",
        item_level = "item level %d",
        footer = "ID %d  •  database %s  •  sources %d  •  uses %d",
        choose_detail = "Select a recipe, ability, or source on the left.",
        source_section = "Sources",
        no_uses = "No known uses are present in the current database. This does not mean none exist.",
        no_sources = "No known sources are present in the current database. This does not mean the item is unavailable.",
        profession = "Profession", professions = "Professions", quests = "Quests",
        class_ability = "Class ability", class_abilities = "Class abilities",
        class_ability_row = "%s  •  consumes ×%d",
        class_ability_consumes = "Consumes this item: ×%d",
        class_ability_class = "Class: %s", unknown_class = "Unknown class",
        class_warrior = "Warrior", class_paladin = "Paladin", class_hunter = "Hunter",
        class_rogue = "Rogue", class_priest = "Priest", class_deathknight = "Death Knight",
        class_shaman = "Shaman", class_mage = "Mage", class_warlock = "Warlock",
        class_monk = "Monk", class_druid = "Druid",
        class_demonhunter = "Demon Hunter", class_evoker = "Evoker",
        profession_with_requirement = "%s  •  requires skill %d",
        learning = "Learning", creature_drop = "Creature drops", drop = "Drop",
        pickpocketing = "Pickpocketing", pickpocket = "Pickpocket",
        disenchanting = "Disenchanting", disenchant = "Disenchanting",
        spell_sources = "Spells and special actions", spell_loot = "Spell or special action",
        mail_sources = "Mail", mail = "Mail",
        fishing = "Fishing", craft = "Crafting", herbs = "Herbs", herb = "Herb",
        objects = "Chests and objects", object = "Object", vendor = "Vendor",
        vendors = "Vendors", containers = "Containers", container = "Container",
        gathering = "Gathering", professional_gathering = "Professional gathering",
        quest = "Quest", quest_reward = "Quest reward",
        starts_quest = "Starts a quest", teaches = "Teaches",
        reputation = "Reputation", exchange = "Exchange", other = "Other",
        unknown_source = "Source is currently unknown", unknown_location = "Unknown location",
        object_or_chest = "Object or chest", recipe = "Recipe",
        depth = "Depth: %d", professions_label = "Professions:",
        profession_prefix = "Profession: %s", sources_prefix = "Sources: %s",
        additional_recipes = "Additional recipes: %d",
        tree_center = "LMB: center the chain on this item",
        tree_open = "Alt + LMB: open the item page",
        player_profession = "Character profession", filter_on = "Filter enabled",
        filter_off = "Filter disabled", click_toggle = "LMB: toggle",
        filter_all = "All", filter_none = "None", filter_reset = "Reset",
        filter_all_tip = "Enable every profession in the filter",
        filter_none_tip = "Disable every profession, including character professions",
        filter_reset_tip = "Enable only the character's professions",
        tree_hint = "LMB — center  •  Alt + LMB — open item",
        hidden_branches = "  •  hidden branches: %d", filtered_branches = "  •  filtered out: %d",
        both_factions = "Both factions", alliance = "Alliance", horde = "Horde",
        special_requirements = "Special requirements", level = "Level %d",
        level_range = "Level %d–%d", unknown_profession = "Unknown profession",
        open_water = "Open water", fishing_object = "Fishing object",
        fishing_pool = "Fishing pool or object", known_source_types = "Known source types: %d",
        price_unknown = "unknown price", money = "%dg %ds %dc", more = "and %d more",
        alt_open = "Alt + LMB: open in Foreverpedia", coordinates = "Coordinates: %.1f, %.1f",
        open_map = "Open the map and place a marker", trainers = "Trainers",
        source_undefined = "Unidentified source", quest_level = "Quest level: %s",
        faction = "Faction: %s", starts_at = "Starts at: %s%s",
        source_unknown = "Unknown source", more_coordinates = "More coordinates: %d",
        ingredients = "INGREDIENTS", no_ingredients = "No ingredients are listed for this recipe.",
        ingredient_alt = "Alt + LMB on an ingredient opens its page.",
        ingredient_gamepad = "Hold R3 on an ingredient to open its page.",
        acquisition_sources = "ACQUISITION SOURCES", water_type = "Water type: %s",
        chance = "Chance: %s", quantity = "Quantity: %s", location = "Location: %s",
        points = "Points: %d", points_hidden = "Points: %d (coordinates hidden)",
        alt_result = "Alt + LMB: open the crafted item in Foreverpedia",
        unknown = "unknown", unknown_chance = "unknown", unnamed = "Unnamed",
        locations_count = "locations: %d", zone = "Zone: %s",
        zone_number = "Zone #%d", recipe_item_unknown = "The client contains recipe item ID %s but not its source.",
        vendor_observe = "The vendor will be added after you encounter them in game.",
        per_stack = " for %d", classic_data = "Classic Era data",
        classic_warning = "This source is based on Classic Era data and may differ in WoW Forever.",
        drop_row = "%s  •  chance %s",
        spell = "Spell", sells_item = "Sells the item",
        looted_object = "Looted from an object", may_contain = "May contain the item",
        spell_loot_detail = "Loot created by an in-game spell or special action",
        mail_source = "Received through in-game mail",
        mail_templates_count = "Known mail scenarios: %d",
        source_items_count = "Eligible items in the database: %d",
        disenchant_items_level = "%s-quality items, item level %d",
        disenchant_items_range = "%s-quality items, item level %d–%d",
        quality_poor = "poor", quality_common = "common",
        quality_uncommon = "uncommon", quality_rare = "rare",
        quality_epic = "epic", quality_legendary = "legendary",
        quality_unknown = "unknown",
        quest_reward_detail = "Quest reward", quest_related = "Item is related to the quest",
        starts_quest_detail = "Using the item starts a quest",
        teaches_detail = "The item teaches a spell", creates_requires = "Creates: %s · requires %d",
        requires = "Requires: %d", client_dataset = "QuestieDB %s + client %s",
        snapshot_dataset = "QuestieDB %s snapshot + client %s",
        questie_install_hint = "Install QuestieDB for fuller information, including coordinates, quest descriptions, and additional details.",
        local_observation = "Local observation",
        live_recipe_provenance = "Profession-window observation, client %s",
        merchant_observed = "Observed at a vendor",
        quest_item_required = "The item is required for the quest",
        npc_number = "NPC #%d", object_number = "Object #%d", quest_number = "Quest #%d",
        unknown_vendor = "Vendor",
        core_item_id_error = "could not determine the item ID.",
        core_click_hook_unavailable = "HandleModifiedItemClick is unavailable; use /fp <itemID>.",
        core_help = "Alt+LMB or hold R3 on an item; /fp opens search, /fp <itemID> opens an item.",
        core_expected_item = "expected an item ID or item link.",
        core_incompatible = "The Foreverpedia database is incompatible.",
        core_interface_warning = "this build targets interface %d; the client reports %s.",
        core_data_build_warning = "client %s, item and recipe database %s; newer data may be missing.",
        core_update_available = "version %s is installed; version %s is available. Updating the addon through CurseForge is recommended.",
        update_available_banner = "Version %s is available — updating is recommended",
        core_status = "interface %s, QuestieDB %s (contract %s), client database %s, drop index: %s, local observations %d, cache records %d.",
        yes = "yes", no = "no", unknown_version = "unknown", not_installed = "not installed",
        data_missing = "Foreverpedia_Data is missing or damaged. Install every addon folder from the Foreverpedia archive.",
        data_schema_incompatible = "The Foreverpedia_Data schema is incompatible with this addon.",
        data_version_required = "Foreverpedia_Data %s or newer is required; installed version: %s.",
        questie_missing = "QuestieDB is not loaded. Install every addon folder from the Foreverpedia archive.",
        questie_version_required = "QuestieDB %s or newer is required; installed version: %s.",
    },
}

local professionNames = {
    ruRU = {},
    enUS = {
        [40] = "Poisons", [129] = "First Aid", [164] = "Blacksmithing",
        [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism",
        [185] = "Cooking", [186] = "Mining", [197] = "Tailoring",
        [202] = "Engineering", [333] = "Enchanting", [356] = "Fishing",
        [393] = "Skinning",
    },
}

local classTokens = {
    [1] = "WARRIOR", [2] = "PALADIN", [4] = "HUNTER", [8] = "ROGUE",
    [16] = "PRIEST", [32] = "DEATHKNIGHT", [64] = "SHAMAN", [128] = "MAGE",
    [256] = "WARLOCK", [512] = "MONK", [1024] = "DRUID",
    [2048] = "DEMONHUNTER", [4096] = "EVOKER",
}

ns.ClassMaskOrder = { 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096 }

function Locale:DetectClientLanguage()
    if type(GetLocale) == "function" then
        local ok, locale = pcall(GetLocale)
        if ok then
            if locale == "ruRU" then return "ruRU" end
            if locale == "enUS" or locale == "enGB" then return "enUS" end
        end
    end
    return "enUS"
end

function Locale:GetLanguage()
    local value = ForeverpediaDB and ForeverpediaDB.language
    local mode = ForeverpediaDB and ForeverpediaDB.languageMode
    if mode == "manual" and (value == "enUS" or value == "ruRU") then
        return value
    end
    return self:DetectClientLanguage()
end

function Locale:SetLanguage(language)
    if language ~= "ruRU" and language ~= "enUS" then return end
    ForeverpediaDB = ForeverpediaDB or {}
    local changed = self:GetLanguage() ~= language
        or ForeverpediaDB.languageMode ~= "manual"
    ForeverpediaDB.language = language
    ForeverpediaDB.languageMode = "manual"
    if changed and ReloadUI then ReloadUI() end
end

function ns.L(key, ...)
    local language = Locale:GetLanguage()
    local value = strings[language][key] or strings.ruRU[key] or key
    if select("#", ...) > 0 then return string.format(value, ...) end
    return value
end

function ns.GetItemSearchItems()
    local data = ns.ItemSearchData and ns.ItemSearchData.items
    if not data then return nil end
    return data[Locale:GetLanguage()] or data.ruRU
end

function ns.GetItemName(itemID)
    local items = ns.GetItemSearchItems()
    local record = items and items[itemID]
    if record and record[1] then return record[1] end
    if C_Item and C_Item.GetItemNameByID then
        local name = C_Item.GetItemNameByID(itemID)
        if name then return name end
    end
    if ItemDB and ItemDB.name then
        local name = ItemDB.name(itemID)
        if name then return name end
    end
    return ns.L("item_number", itemID)
end

function ns.GetProfessionName(professionID)
    local language = Locale:GetLanguage()
    return professionNames[language][professionID]
        or (ns.RecipeData and ns.RecipeData.professions
            and ns.RecipeData.professions[professionID])
        or string.format("%s #%d", ns.L("profession"), professionID)
end

function ns.GetClassName(classMask)
    local token = classTokens[classMask]
    if token then
        return ns.L("class_" .. string.lower(token))
    end
    return ns.L("unknown_class")
end

