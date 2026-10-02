#!/usr/bin/env bash
# Crea in artifacts/ la cartella del plugin da copiare nei plugin di Jellyfin
# (dll + meta.json, spec E §6.8). Lo zip per il repository lo fa il workflow.
# Uso, dalla root del repository:
#   bash jellyfin-plugin-watch-party/pack.sh 1.0.0
set -euo pipefail

version="${1:?versione mancante, es. 1.0.0}"
here="$(cd "$(dirname "$0")" && pwd)"
artifacts="$here/artifacts"
folder="$artifacts/WonderFlix Watch Party_$version.0"

rm -rf "$artifacts"
dotnet publish "$here/Jellyfin.Plugin.WonderFlixWatchParty/Jellyfin.Plugin.WonderFlixWatchParty.csproj" \
  --configuration Release --output "$artifacts/publish" -p:Version="$version"
mkdir -p "$folder"
cp "$artifacts/publish/Jellyfin.Plugin.WonderFlixWatchParty.dll" "$folder/"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
sed -e "s/@VERSION@/$version.0/" -e "s/@TIMESTAMP@/$timestamp/" \
  "$here/meta.template.json" > "$folder/meta.json"
echo "$folder"
