local addonName, Data = ...

Data.manifest = {
    schema = 3,
    version = "0.9.5",
    clientBuild = "1.60.1.71139",
}

-- The game creates a separate namespace table for every addon. Expose this
-- read-only data package so the Foreverpedia core addon can bind it locally.
_G.ForeverpediaData = Data
