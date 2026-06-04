# Getting started
Clone this repo
```sh
# ~/
git clone https://github.com/hxero/hyprbadapple
cd hyprbadapple
```
## Dependencies
- `mpv`  - to play the audio file in the background
- `socat`  -  to unpause mpv for syncing

 \
Arch-based
```sh
sudo pacman -S mpv socat
```
Other distros
> idk, figure it out
## Configuring
See useful stats for configuration
```sh
# ~/hyprbadapple
cd baprocess

# ~/hyprbadapple/baprocess
pip install -r requirements.txt
python pack.py

# skipping video decode...
# total frames : 6572
# most boxes   : 153
# total boxes  : 309476
# grid size    : 64x48
# wrote output/boxes.bin
```
### Constants
You can edit some constants based on these values and your monitor resolution
```lua
local MAX_BOXES = 153; -- the `most boxes` from python

local SCALE    = 24;  -- scale  -> resolution height / (grid height)
local OFFSET_X = 192; -- center -> [(resolution width) - (grid width * scale)] / 2
local OFFSET_Y = 46;  -- depends on your top|bottom bars - can be 0 if you want it to fullscreen
```
`resolution` is your monitor resolution which can be accessed from
```sh
hypctl monitors

# Monitor eDP-1 (ID 0):
#	        1920x1200@60 at 0x0
```
e.g. 1920x1200 and grid size: 64x48
 > 1920 is the resolution width \
 > 1200 is the resolution height \
 > 64 is the grid width \
 > 48 is the grid height

So, `SCALE` = `1200/48` = `25` \
and, `OFFSET_X` = `(1920 - 64*25)/2` = `160`
 > 25 is from `SCALE`

 \
Change this to launch different window e.g. `kitty` `foot`
```lua
local LAUNCH = "~/hyprbadapple/box"; -- window launch command
-- local LAUNCH = "kitty";
-- local LAUNCH = "firefox";
```
 > It's not recommended to launch heavy window like a browser or something similar
## Start
To run this cd into `hyprbadapple`, then run
```lua
hyprctl eval "dofile('${PWD}/init.lua')"
```
To force stop, run
```sh
hyprctl reload&&killall mpv box
```
- replace `box` with what you launched

# Video
[![uwu](https://img.youtube.com/vi/_U7K9CbeSq8/0.jpg)](https://www.youtube.com/watch?v=_U7K9CbeSq8)
