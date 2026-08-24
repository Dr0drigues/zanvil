#!/bin/bash
# ==============================================================================
# Script : clone-projects.sh
# ==============================================================================
# Permet de réinitialiser les flags Apple bloquand Stremio.app 
# ==============================================================================


sudo xattr -cr /Applications/Stremio.app
find /Applications/Stremio.app -name "._*" -delete
find /Applications/Stremio.app -name ".DS_Store" -delete
sudo codesign --force --deep --sign - /Applications/Stremio.app

