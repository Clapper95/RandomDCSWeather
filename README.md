# RandomDCSWeather
Apply random weather in a configurable manner to your DCS mission upon restarts.

- IMPORTANT: IF YOU HAVE MULTIPLE DIFFERENT MISSIONS IN YOUR SERVERSETTINGS.LUA. THEN THIS SCRIPT WILL NOT WORK AS INTENDED. THIS FEATURE WILL BECOME AVAILABLE IN THE FUTURE. 
- ALSO IMPORRANT: SET YOUR MISSIONS WEATHER TO STATIC. DYNAMIC WEATHER WILL OVERRIDE WIND SPEED AMONG OTHER THINGS. 

Dependancies
7-Zip https://www.7-zip.org/download.html
DCSServerBot or Similar to auto rotate missions.

-Configuration
  - Make a copy of your current mission and add "_b" at the end.
  
  - Set sevenZip if not in its default location of C:\Program Files\7-Zip\7z.exe
  
  - Set serverSettingPath to where your serverSettings.lua is. Example C:\Users\YourUser\Saved Games\DCS.dcs_serverrelease\Config\serverSettings.lua
  
  - Set badWeatherChance to your preferred chance of bad weather (between 0 and 1)
  
  - Set nightChance to your preferred chance of night operations (between 0 and 1)
  
  - If you want to set the wind to where your carriers are, at line 76, find atGround, then move over to ["dir"] and find %d. Set your direction there (0 - 359) and then remove the rnd(0, 8), rnd(0, 359) at line 79, and the comma at the end of line 78. 
  
  - Set year in the function buildDateAndTime() (Line 108)

- Installation
  - Add both missions to your missionList (Main and Main_B) in serverSettings.lua or the server manager.
  - Drop this file into DCS World Server\Scripts\Hooks
  - Configure as needed
  - Restart your server to load
  - On next restart, you'll have random weather and time.