#!/usr/bin/env bash
# Crea la chiave di firma dell'APK della TV e la carica nei Secrets di GitHub.
# Lo lancia l'utente, una volta sola (Git Bash): la password non compare mai a schermo.
set -euo pipefail

cd "$(dirname "$0")"
jks=wonderflix-release.jks
props=key.properties

if [[ -e $jks || -e $props ]]; then
  echo "$jks o $props esistono già: la chiave c'è, non la rigenero." >&2
  exit 1
fi

keytool=keytool
if ! command -v keytool >/dev/null 2>&1; then
  keytool="C:/Users/sidot/dev/jdk-17.0.21.0.2+1/bin/keytool"
fi
command -v gh >/dev/null 2>&1 || { echo "gh non trovato" >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "openssl non trovato" >&2; exit 1; }

password=$(openssl rand -base64 32 | tr -d '/+=\r\n')

# La password passa per l'ambiente, non per la riga di comando (visibile ad altri processi).
WF_KEY_PASSWORD=$password "$keytool" -genkeypair -storetype PKCS12 -keyalg RSA -keysize 4096 \
  -validity 10000 -alias wonderflix -dname "CN=WonderFlix" -keystore "$jks" \
  -storepass:env WF_KEY_PASSWORD -keypass:env WF_KEY_PASSWORD

cat > "$props" <<EOF
storeFile=../$jks
storePassword=$password
keyAlias=wonderflix
keyPassword=$password
EOF

# File già scritti: se gh fallisce, un nuovo lancio rifiuterebbe. Si caricano a mano dai file.
recovery() {
  cat >&2 <<'NOTE'
Caricamento dei Secrets non riuscito. La chiave è già in app/android: non rilanciare lo script.
Quando gh funziona (gh auth status), da app/android carica i due Secrets dai file:
  base64 -w0 wonderflix-release.jks | gh secret set WONDERFLIX_ANDROID_KEYSTORE
  sed -n 's/^storePassword=//p' key.properties | tr -d '\r\n' | gh secret set WONDERFLIX_ANDROID_KEYSTORE_PASSWORD
(la password passa da key.properties a gh senza comparire a schermo)
NOTE
  exit 1
}
base64 -w0 "$jks" | gh secret set WONDERFLIX_ANDROID_KEYSTORE || recovery
printf '%s' "$password" | gh secret set WONDERFLIX_ANDROID_KEYSTORE_PASSWORD || recovery

echo "Salva wonderflix-release.jks e key.properties nel gestore di password: senza, ogni utente dovrà reinstallare."
