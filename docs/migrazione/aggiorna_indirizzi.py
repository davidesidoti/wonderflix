"""Dopo la migrazione del seedbox: sostituisce i vecchi indirizzi con i nuovi.

Si lancia sul NUOVO server (vedi docs/migrazione/README.md):
    ssh ultra 'python3 -I - --new-host hashvps.NUOVO.usbx.me --new-ip A.B.C.D' < docs/migrazione/aggiorna_indirizzi.py
Senza --apply mostra solo cosa cambierebbe. Con --apply:
- Sonarr, Radarr e Prowlarr li aggiorna via API (devono essere accesi);
- i file di Jellyfin (config del plugin) e di Seerr li riscrive solo se quel
  servizio e' spento, dopo averne fatto una copia .bak-migrazione.
Non stampa mai chiavi, password o webhook.
"""
import argparse, json, os, re, shutil, socket, subprocess, urllib.request

OLD_HOSTS = ['hashvps.proton.usbx.me', 'hashvps.vapor.usbx.me']  # vapor: residuo di una migrazione vecchia
OLD_IPS = ['46.232.210.229']
OLD_NGINX_PORT = 17540  # SonarrUrl/RadarrUrl del plugin: IP:porta del nostro nginx
H = os.path.expanduser('~')
SECRET = re.compile(r'pass|key|secret|token|webhook', re.I)

p = argparse.ArgumentParser()
p.add_argument('--new-host', required=True)
p.add_argument('--new-ip', required=True)
p.add_argument('--apply', action='store_true')
a = p.parse_args()
assert re.fullmatch(r'[\w-]+(\.[\w-]+)+', a.new_host), a.new_host
assert re.fullmatch(r'\d+\.\d+\.\d+\.\d+', a.new_ip), a.new_ip
# Ultra.cc cambia le porte nella migrazione: quella nuova di nginx dal suo "listen"
NGINX_PORT = int(re.search(r'listen\s+(\d+);', open(H + '/.apps/nginx/sites-available/default').read()).group(1))


def swap(s):
    for o in OLD_HOSTS:
        s = s.replace(o, a.new_host)
    for o in OLD_IPS:
        s = s.replace('%s:%d' % (o, OLD_NGINX_PORT), '%s:%d' % (a.new_ip, NGINX_PORT))
        s = s.replace(o, a.new_ip)
    return s


def app_port(app):
    conf = open(H + '/.apps/nginx/proxy.d/%s.conf' % app).read()
    return int(re.search(r'proxy_pass\s+http://127\.0\.0\.1:(\d+)', conf).group(1))


def listening(port):
    with socket.socket() as s:
        s.settimeout(3)
        return s.connect_ex(('127.0.0.1', port)) == 0


# --- file (servizio spento) ---
FILES = [
    (H + '/.apps/jellyfin/data/plugins/configurations/Jellyfin.Plugin.WonderFlixWatchParty.xml', 'Jellyfin', app_port('jellyfin')),
    (H + '/.apps/seerr/settings.json', 'Seerr', app_port('seerr')),
]
for path, name, port in FILES:
    text = open(path, encoding='utf-8').read()
    new = swap(text)
    changed = [(o, n) for o, n in zip(text.splitlines(), new.splitlines()) if o != n]
    print('== %s: %d righe da cambiare' % (path, len(changed)))
    for o, n in changed:
        if not SECRET.search(o):
            print('   ', o.strip()[:160], '->', n.strip()[:160])
    if not changed or not a.apply:
        continue
    if listening(port):
        print('   SALTATO: %s e\' acceso (porta %d), spegnilo e rilancia' % (name, port))
        continue
    if name == 'Seerr':
        json.loads(new)  # non scrivere un JSON rotto
    shutil.copy2(path, path + '.bak-migrazione')
    with open(path, 'w', encoding='utf-8') as f:
        f.write(new)
    print('   SCRITTO (copia in .bak-migrazione)')


# --- Sonarr / Radarr / Prowlarr via API ---
def api(app, ver, path, method='GET', body=None):
    key = re.search(r'<ApiKey>(\w+)</ApiKey>', open(H + '/.apps/%s/config.xml' % app).read()).group(1)
    url = 'http://127.0.0.1:%d/%s/api/%s/%s' % (app_port(app), app, ver, path)
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method,
                               headers={'X-Api-Key': key, 'Content-Type': 'application/json'})
    return json.load(urllib.request.urlopen(r, timeout=60))


for app, ver, eps in [('sonarr', 'v3', ['downloadclient', 'notification']),
                      ('radarr', 'v3', ['downloadclient', 'notification']),
                      ('prowlarr', 'v1', ['applications', 'downloadclient'])]:
    for ep in eps:
        try:
            items = api(app, ver, ep)
        except Exception as ex:
            print('== %s/%s ERRORE %s' % (app, ep, ex))
            continue
        for it in items:
            diffs = []
            for fld in it.get('fields', []):
                v = fld.get('value')
                if isinstance(v, str) and swap(v) != v:
                    diffs.append((fld['name'], v, swap(v)))
                    fld['value'] = swap(v)
            if not diffs:
                continue
            print('== %s/%s "%s"' % (app, ep, it.get('name')))
            for n, o, nv in diffs:
                print('   %s: %s -> %s' % (n, o, nv))
            if a.apply:
                # forceSave: salva anche se il test di connessione fallisce (DNS nuovo non ancora pronto)
                api(app, ver, '%s/%d?forceSave=true' % (ep, it['id']), 'PUT', it)
                print('   SALVATO')


# --- solo controlli ---
print('== controlli')
ips = subprocess.run(['ip', '-4', '-o', 'addr'], capture_output=True, text=True).stdout
qb = open(H + '/.config/qBittorrent/qBittorrent.conf').read()
for m in sorted(set(re.findall(r'InterfaceAddress=([\d.]+)', qb))):
    print('   qBittorrent si lega a %s: %s' % (m, 'OK' if m in ips else 'NON e\' di questa macchina, va cambiato'))
cron = subprocess.run(['crontab', '-l'], capture_output=True, text=True).stdout
print('   cron della quota:', 'OK' if 'wonderflix-quota' in cron else 'MANCA (vedi README)')
print('   rrsync:', 'OK' if shutil.which('rrsync') else 'MANCA (il deploy del sito non va)')
keys = open(H + '/.ssh/authorized_keys').read()
print('   chiave di deploy:', 'OK' if 'wonderflix-deploy' in keys else 'MANCA')
for d in ['wonderflix-web', 'wonderflix-web-prova']:
    print('   ~/%s:' % d, 'OK' if os.path.isfile('%s/%s/index.html' % (H, d)) else 'MANCA')
