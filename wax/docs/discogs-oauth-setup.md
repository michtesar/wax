# Discogs OAuth Setup

Tahle app pouziva Discogs OAuth 1.0a flow.

Pro lokalni vyvoj potrebujes z Discogs:

- `Consumer Key`
- `Consumer Secret`

Nepouzivej pro tenhle flow osobni `user token`. Ten je jiny auth mechanismus.

## Kde ty hodnoty ziskat

1. Prihlas se do Discogs.
2. Otevri developer settings:
   `https://www.discogs.com/settings/developers`
3. Vytvor novou aplikaci.
4. Pri vytvareni aplikace nastav callback URL:
   `wax://discogs/auth`
5. Po ulozeni aplikace zkopiruj:
   - `Consumer Key`
   - `Consumer Secret`

Discogs pro OAuth pouziva tyhle endpointy:

- Request Token URL: `https://api.discogs.com/oauth/request_token`
- Authorize URL: `https://www.discogs.com/oauth/authorize`
- Access Token URL: `https://api.discogs.com/oauth/access_token`

App je ma uz zakodovane v auth klientovi, neni potreba je nikam dalsim zpusobem rucne zadavat.

## Co vyplnit v Discogs app

Doporucene hodnoty:

- App name: `wax`
- Description: kratky interní popis, napr. `Offline-first vinyl collection app`
- Callback URL: `wax://discogs/auth`

Pokud Discogs zobrazi dalsi nepovinna pole, neni potreba je pro lokalni vyvoj resit.

## Jak to dostat do appky

Nepopisuj to do kodu ani do commitnuteho `Info.plist`.

Pouzij Xcode Scheme environment variables:

1. Otevri `Product` -> `Scheme` -> `Edit Scheme...`
2. Vyber `Run`
3. Otevri zalozku `Arguments`
4. V sekci `Environment Variables` pridej:
   - `WAX_DISCOGS_CONSUMER_KEY = tvoje Consumer Key`
   - `WAX_DISCOGS_CONSUMER_SECRET = tvoje Consumer Secret`

Volitelne muzes pridat i:

- `WAX_DISCOGS_CALLBACK_SCHEME = wax`
- `WAX_DISCOGS_CALLBACK_URL = wax://discogs/auth`

Tyhle dve hodnoty ale uz maji rozumny default, takze je normalne neni treba nastavovat.

## Co uz je v appce pripravene

App uz ceka na tyhle hodnoty:

- `WAX_DISCOGS_CONSUMER_KEY`
- `WAX_DISCOGS_CONSUMER_SECRET`

Callback scheme je registrovany v:

- `wax/Info.plist`

Aktualni callback URL:

- `wax://discogs/auth`

Po doplneni environment variables:

1. Spust appku z Xcode.
2. V top baru tapni na `Sign In`.
3. Otevre se Discogs OAuth flow.
4. Po dokonceni autorizace se browser vrati do appky pres `wax://discogs/auth`.

## Bezpecnost

- `Consumer Secret` nikdy necommituj do repa.
- Nepis ho natvrdo do source kodu.
- Pro lokalni vyvoj ho drz jen ve Scheme environment variables.

## Troubleshooting

### Sign In je disabled nebo app pise, ze chybi config

Zkontroluj, ze ve Scheme opravdu mas:

- `WAX_DISCOGS_CONSUMER_KEY`
- `WAX_DISCOGS_CONSUMER_SECRET`

Pak appku uplne restartuj z Xcode.

### Po autorizaci se appka nevrati z browseru

Zkontroluj:

- callback URL v Discogs app je presne `wax://discogs/auth`
- v appce zustal callback scheme `wax`
- spoustis aktualni build, ne starsi instalaci

### Mas jen personal token

Tenhle projekt je ted nastaveny na OAuth login. Personal token se pro tenhle flow nepouziva.
