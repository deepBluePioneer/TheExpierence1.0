local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local PostController = Knit.CreateController { Name = "PostController" }

function PostController:KnitStart()
    local Lighting = game:GetService("Lighting")
    local Iris = Knit.GetController("irisInitController"):GetIris()
    local increment = 0.01
    local min = 0
    local max = 10

    Iris:Connect(function()
        Iris.Window({"Lighting Control Panel"})

       -- Brightness
       local Slider_Brightness = Iris.SliderNum({"Brightness", increment, 0, 5})
       Slider_Brightness.state.number.value = 5

       local sliderValBrightness = Slider_Brightness.state.number.value
       Lighting.Brightness = sliderValBrightness

       -- ClockTime
       local Slider_ClockTime = Iris.SliderNum({"ClockTime", increment, 0, 24})
       Slider_ClockTime.state.number.value = 13
       local sliderValClockTime = Slider_ClockTime.state.number.value
       Lighting.ClockTime = sliderValClockTime

       -- EnvironmentDiffuseScale
       local Slider_EnvironmentDiffuseScale = Iris.SliderNum({"EnvironmentDiffuseScale", increment, 0, 1})
       local sliderValEnvironmentDiffuseScale = Slider_EnvironmentDiffuseScale.state.number.value
       Lighting.EnvironmentDiffuseScale = sliderValEnvironmentDiffuseScale

       -- EnvironmentSpecularScale
       local Slider_EnvironmentSpecularScale = Iris.SliderNum({"EnvironmentSpecularScale", increment, 0, 1})
       local sliderValEnvironmentSpecularScale = Slider_EnvironmentSpecularScale.state.number.value
       Lighting.EnvironmentSpecularScale = sliderValEnvironmentSpecularScale

       -- ExposureCompensation
       local Slider_ExposureCompensation = Iris.SliderNum({"ExposureCompensation", increment, -5, 5})
       Slider_ExposureCompensation.state.number.value = -2.15
       local sliderValExposureCompensation = Slider_ExposureCompensation.state.number.value
       Lighting.ExposureCompensation = sliderValExposureCompensation

       -- FogEnd
       local Slider_FogEnd = Iris.SliderNum({"FogEnd", increment, 0, 10000})
       local sliderValFogEnd = Slider_FogEnd.state.number.value
       Lighting.FogEnd = sliderValFogEnd

       -- FogStart
       local Slider_FogStart = Iris.SliderNum({"FogStart", increment, 0, 5000})
       local sliderValFogStart = Slider_FogStart.state.number.value
       Lighting.FogStart = sliderValFogStart

       -- GeographicLatitude
       local Slider_GeographicLatitude = Iris.SliderNum({"GeographicLatitude", increment, -90, 90})
       local sliderValGeographicLatitude = Slider_GeographicLatitude.state.number.value
       Lighting.GeographicLatitude = sliderValGeographicLatitude

       -- ShadowSoftness
       local Slider_ShadowSoftness = Iris.SliderNum({"ShadowSoftness", increment, 0, 1})
       local sliderValShadowSoftness = Slider_ShadowSoftness.state.number.value
       Lighting.ShadowSoftness = sliderValShadowSoftness

       

        Iris.End()
    end)
end

function PostController:KnitInit()
    -- Add controller initialization logic here
end

return PostController