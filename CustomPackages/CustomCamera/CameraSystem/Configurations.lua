local Module = {}

--------------------------------------------------------------------
------------------  Over The Shoulder Camera  ----------------------
--------------------------------------------------------------------

Module.CamLockOffset = Vector3.new(1, 3, 15) 

--------------------------------------------------------------------
-----------------------  Isometric Camera  -------------------------
--------------------------------------------------------------------

Module.IsometricCameraDepth = 64
Module.IsometricHeightOffset = 2
Module.IsometricFieldOfView = 20

--------------------------------------------------------------------
---------------------  Side Scrolling Camera  ----------------------
--------------------------------------------------------------------

Module.SideCameraDepth = 64
Module.SideHeightOffset = 2
Module.SideFieldOfView = 20

--------------------------------------------------------------------
-----------------------  Top Down Camera  --------------------------
--------------------------------------------------------------------

Module.TopDownMouseSensitivity = 20
Module.TopDownDistance = Vector3.new(0,25,0)
Module.TopDownDirection = Vector3.new(0, -1, 0)
Module.TopDownOffset = Vector3.new(0,0,3)
Module.TopDownFaceMouse = true

--------------------------------------------------------------------
----------------------  Head Follow Camera  ------------------------
--------------------------------------------------------------------

Module.HeadFollowAlpha = 0.5

--------------------------------------------------------------------
--------------------  Face Character To Mouse  ---------------------
--------------------------------------------------------------------

Module.FaceCharacterAlpha = 0.5

--------------------------------------------------------------------
----------------------- Follow Mouse Camera  -----------------------
--------------------------------------------------------------------

Module.MouseCameraEasingStyle = nil         -- If left nil, this will default to a fast quint fallback
Module.MouseCameraEasingDirection = nil     -- If left nil, this will default to enum.easing.out direction
Module.MouseCameraSmoothness = 0.15
Module.AspectRatio = Vector2int16.new(15, 5) -- X, Y
Module.MouseAlpha = 0.7
Module.MouseYOffset = 1
Module.MouseXOffset = 270

--------------------------------------------------------------------


return Module
