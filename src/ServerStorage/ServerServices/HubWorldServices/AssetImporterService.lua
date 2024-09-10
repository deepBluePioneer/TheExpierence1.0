local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local CastleModelAssetsModule = require(ReplicatedStorage.Source.CastleModelAssetsModule)

local AssetImporterService = Knit.CreateService {
    Name = "AssetImporterService",
    Client = {},
}

function ImportModels()
    local InsertService = game:GetService("InsertService")

    -- Function to load a model by asset ID
    local function loadModel(assetId)
        -- Attempt to load the asset using InsertService
        local success, model = pcall(function()
            return InsertService:LoadAsset(assetId)
        end)

        -- Check if the model was successfully loaded
        if success and model then
            -- Parent the model to the workspace or another desired location
            model.Parent = game.ReplicatedStorage
            print("Model loaded successfully with Asset ID:", assetId)
            print(model)
        else
            -- Handle the case where the model failed to load
            warn("Failed to load model with Asset ID:", assetId, "Error:", tostring(model))
        end
    end

    -- Iterate through all asset IDs in the CastleModelAssetsModule and load them
    for _, assetId in ipairs(CastleModelAssetsModule.Models) do
        loadModel(assetId)
    end

    -- Add service startup logic here
end

local function ModifyModels()
    local prefabFolder = ReplicatedStorage:WaitForChild("Prefabs")
    local CastleAssets = prefabFolder:WaitForChild("CastleAssets")

    -- Iterate through each model in the CastleAssets folder
    for _, model in pairs(CastleAssets:GetChildren()) do
        if model:IsA("Model") then
            -- Find the first child that is also a Model
            local childModel = nil
            for _, child in pairs(model:GetChildren()) do
                if child:IsA("Model") then
                    childModel = child
                    break
                end
            end

            -- If a child model is found, unparent it
            if childModel then
                -- Reparent the child model to the CastleAssets folder
                childModel.Parent = CastleAssets
            end

            -- If the original model is now empty, remove it
            if #model:GetChildren() == 0 then
                model:Destroy()
            end
        end
    end
end
local function ConfigureMeshes()
    local prefabFolder = ReplicatedStorage:WaitForChild("Prefabs")
    local CastleAssets = prefabFolder:WaitForChild("CastleAssets")

    -- Iterate through each model in the CastleAssets folder
    for _, model in pairs(CastleAssets:GetChildren()) do
        if model:IsA("Model") then
            -- Iterate through each child of the model
            for _, child in pairs(model:GetChildren()) do
                -- Check if the child is a BasePart (e.g., Part, MeshPart)
                if child:IsA("MeshPart") then
                    child.Anchored = true  -- Anchor the part
                end
            end
        end
    end
end

local function RenameDecal()
    local prefabFolder = ReplicatedStorage:WaitForChild("Prefabs")
    local texturesFolder = prefabFolder:WaitForChild("Textures")
    local AssetDictionary = require(ReplicatedStorage.Source.AssetDictionary)

    -- Iterate through all children of the Textures folder
    for _, child in ipairs(texturesFolder:GetChildren()) do
        if child:IsA("Decal") then
            -- Get the asset ID from the Texture property
            local assetId = tonumber(string.match(child.Texture, "%d+$"))

            -- Check if the asset ID exists in the dictionary
            if AssetDictionary.assets[assetId] then
                -- Rename the decal to the name from the dictionary
                child.Name = AssetDictionary.assets[assetId]
            end
        end
    end
end

local function createMaterials() --Called from command bar
    local prefabFolder = game:GetService("ReplicatedStorage"):WaitForChild("Prefabs")
    local texturesFolder = prefabFolder:WaitForChild("Textures")
    local MaterialDictionary = require(game:GetService("ReplicatedStorage").Source.MaterialDictionary)
    local MaterialService = game:GetService("MaterialService")
    
    local function findTextureIdByName(textureName)
        for _, child in ipairs(texturesFolder:GetChildren()) do
            if child:IsA("Decal") or child:IsA("Texture") then
                local textureId = tonumber(string.match(child.Texture, "%d+$"))
                if child.Name == textureName and textureId then
                    return textureId
                end
            end
        end
        return nil
    end
    
    for materialName, textureData in pairs(MaterialDictionary.materials) do
        local surfaceAppearance = Instance.new("SurfaceAppearance")
        surfaceAppearance.Name = materialName
    
        if textureData._MainTex then
            local colorMapId = findTextureIdByName(textureData._MainTex)
            if colorMapId then
                surfaceAppearance.ColorMap = "rbxassetid://" .. colorMapId
            end
        end
    
        if textureData._NormalMap or textureData._BumpMap then
            local normalMapId = findTextureIdByName(textureData._NormalMap or textureData._BumpMap)
            if normalMapId then
                surfaceAppearance.NormalMap = "rbxassetid://" .. normalMapId
            end
        end
    
        if textureData._Metallic or textureData._MetallicGlossMap then
            local metalnessMapId = findTextureIdByName(textureData._Metallic or textureData._MetallicGlossMap)
            if metalnessMapId then
                surfaceAppearance.MetalnessMap = "rbxassetid://" .. metalnessMapId
            end
        end
    
        if textureData._RoughnessMap then
            local roughnessMapId = findTextureIdByName(textureData._RoughnessMap)
            if roughnessMapId then
                surfaceAppearance.RoughnessMap = "rbxassetid://" .. roughnessMapId
            end
        end
    
        -- Parent the SurfaceAppearance to the MaterialService
        surfaceAppearance.Parent = MaterialService
    end
    
end
local function SetMaterials() --Called from command bar
    local prefabFolder = game:GetService("ReplicatedStorage"):WaitForChild("Prefabs")
    local CastleAssetsFolder = workspace:WaitForChild("CastleAssets")
    local MaterialService = game:GetService("MaterialService")
    
    -- Create a table to store the base names of materials
    local materialBaseNames = {}
    
    -- Iterate through all the materials in MaterialService
    for _, material in ipairs(MaterialService:GetChildren()) do
        if material:IsA("SurfaceAppearance") then
            -- Extract the base name before the first underscore
            local baseName = string.match(material.Name, "([^_]+)")
            
            -- Trim any whitespace from the base name
            baseName = string.gsub(baseName, "^%s*(.-)%s*$", "%1")
            
            -- Remove .mat suffix if it occurs
            baseName = string.gsub(baseName, "%.mat$", "")
            
            -- Store the base name in the table
            materialBaseNames[baseName] = material
            print("Material base name:", baseName)
        end
    end
    
    -- Now iterate through all the models in CastleAssetsFolder
    for _, model in ipairs(CastleAssetsFolder:GetChildren()) do
        if model:IsA("Model") then
            -- Extract the base name before the first underscore
            local baseName = string.match(model.Name, "([^_]+)")
            
            -- Trim any whitespace from the base name
            baseName = string.gsub(baseName, "^%s*(.-)%s*$", "%1")
            
            print("Model base name:", baseName)
            
            -- Find the corresponding SurfaceAppearance in the materialBaseNames table
            local surfaceAppearance = materialBaseNames[baseName]
            
            if surfaceAppearance then
                -- Apply the SurfaceAppearance to all MeshParts in the model
                for _, meshPart in ipairs(model:GetDescendants()) do
                    if meshPart:IsA("MeshPart") then
                        -- Clone the SurfaceAppearance and parent it to the MeshPart
                        local clonedAppearance = surfaceAppearance:Clone()
                        clonedAppearance.Parent = meshPart
                    end
                end
            else
                warn("No matching SurfaceAppearance found for model: " .. model.Name)
            end
        end
    end
end
function AssetImporterService:KnitStart()
    --SetMaterials()
end

function AssetImporterService:KnitInit()
    -- Add service initialization logic here
end

return AssetImporterService
