local _, ns = ...

-- Runtime compatibility and UX limits live in one place so new data revisions
-- and UI features do not require editing unrelated modules.
ns.Config = {
    interface = 16001,
    savedVariablesSchema = 8,
    dataSchema = 3,
    minimumDataVersion = "0.9.1",
    questieContract = 1,
    minimumQuestieVersion = "1.0.16",
    modifiedClickDebounce = 0.20,
    historyLimit = 50,
    searchResultLimit = 8,
    searchDelay = 0.08,
    fishingObservationWindow = 8,
    gamepadHoldDuration = 0.70,
    gamepadHoldShowAfter = 0.15,
    gamepadTooltipMemory = 1.50,
    detailCoordinateLimit = 8,
    craftTree = {
        defaultDepth = 2,
        maximumDepth = 2,
        maximumRecipesPerItem = 2,
        maximumOutputsPerItem = 8,
        maximumIngredientsPerRecipe = 8,
        maximumNodesPerColumn = 10,
        nodeHeight = 62,
    },
}
