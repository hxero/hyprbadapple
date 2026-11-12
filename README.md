
# Video
[![uwu](https://img.youtube.com/vi/_U7K9CbeSq8/0.jpg)](https://www.youtube.com/watch?v=_U7K9CbeSq8)

# Getting started
Clone this repo
```sh
# ~/
git clone https://github.com/hxero/hyprbadapple
cd hyprbadapple
```

## Setup
Run the script to install dependencies and set it up automatically
```sh
sh setup.sh
```

> When asked "Enter window launch command:"  
> Enter the command that launches the window  
> example: `kitty`, `foot` or leave blank to use the "box" window  

## Start
> [!IMPORTANT]
> To force stop cleanly, press `SUPER + U` after you started

cd into `hyprbadapple`, then run
```sh
sh start.sh&&exit
```
or directly
```sh
hyprctl eval "dofile'$PWD/init.lua'"&&exit
```
> `&&exit` to exit the terminal after starting
