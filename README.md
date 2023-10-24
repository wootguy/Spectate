# Spectate
Allows toggling observer mode when survival mode is off.

Toggle observer mode with any of these commands (chat or console):  
`.observer`  
`.observe`  
`.spectate`  

# Installation
1. Download the script and save it to `scripts/plugins/Spectate.as`
1. Download [this ghost entity script](https://raw.githubusercontent.com/wootguy/ghosts/master/scripts/GhostEntity.as) too and save it to `scripts/plugins/ghosts/GhostEntity.as` (required for first-person spectate mode)
1. Add this to default_plugins.txt
```
    "plugin"
    {
        "name" "Spectate"
        "script" "Spectate"
    }
    "plugin"
    {
        "name" "GhostEntity"
        "script" "ghosts/GhostEntity"
    }
```
