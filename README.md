# Przesyłanie plików

Lekka aplikacja webowa w ASP.NET Core 10, bez zewnętrznych bibliotek JavaScript. Umożliwia dodanie wielu plików, podgląd zdjęć, przesyłanie kolejno z postępem dla każdego pliku oraz wznowienie nieudanych przesyłań.

## Uruchomienie

Wymagany jest .NET 10 SDK.

```powershell
dotnet run
```

Otwórz adres wyświetlony przez aplikację. Użytkownik wybiera miejsce docelowe z listy skonfigurowanej przez administratora. Domyślna konfiguracja zapisuje pliki w katalogu `uploads` obok pliku projektu. Limit wynosi 50 MB na plik i 100 plików w kolejce.

## Konfiguracja miejsc docelowych

Dodaj miejsca w sekcji `Upload:Destinations` w `appsettings.json`. Ścieżki względne są liczone od katalogu aplikacji; możesz też podać ścieżkę bezwzględną. Aplikacja tworzy skonfigurowane katalogi przy uruchomieniu, więc konto systemowe uruchamiające aplikację musi mieć do nich prawo zapisu.

```json
{
  "Upload": {
    "Destinations": [
      {
        "Id": "zdjecia",
        "Name": "Zdjęcia",
        "Path": "D:\\Pliki\\Zdjęcia"
      },
      {
        "Id": "dokumenty",
        "Name": "Dokumenty",
        "Path": "D:\\Pliki\\Dokumenty"
      }
    ]
  }
}
```

W przeglądarce pokazywane są tylko nazwy miejsc. Serwer przyjmuje wyłącznie identyfikatory skonfigurowane w `appsettings.json`; ścieżki nie są przyjmowane od użytkownika.

## Publikacja AOT

Publikację wykonaj na komputerze z Linux x64 i .NET 10 SDK:

```bash
dotnet publish -c Release -r linux-x64 --self-contained true -o ./publish
```

Opublikowane pliki skopiuj na serwer, np.:

```bash
scp -r ./publish user@serwer:/tmp/image-uploader-publish
scp ./install.sh ./addHttps.sh user@serwer:/tmp/
```

### Instalacja na serwerze

Skrypty wymagają Linuxa z systemd. `install.sh` doinstaluje Nginx przez `apt-get`, jeśli nie jest zainstalowany; uruchom go jako root, podając katalog publikacji:

```bash
sudo bash install.sh /tmp/image-uploader-publish
```

Przed publikacją ustaw w `appsettings.json` ścieżki miejsc docelowych na `/var/lib/image-uploader/uploads` i `/var/lib/image-uploader/images` (lub dostosuj je do własnych katalogów). Usługa ma prawo zapisu tylko do tych katalogów.

Skrypt instaluje aplikację jako usługę systemd oraz konfiguruje Nginx na HTTP pod portem 8080. Aplikacja nasłuchuje tylko na `127.0.0.1:8282`; port 8282 nie jest wystawiony na zewnątrz.

### Włączenie HTTPS

Po instalacji aplikacji włącz HTTPS, podając adres IP serwera:

```bash
sudo bash addHttps.sh 192.168.1.12
```

Domyślnie skrypt tworzy certyfikat samopodpisany z adresem IP w SAN. Szyfruje on połączenie, ale przeglądarka wyświetli ostrzeżenie, dopóki certyfikat nie zostanie dodany do zaufanych certyfikatów na urządzeniach użytkowników.

Możesz zamiast tego podać ścieżki do własnego certyfikatu (z adresem IP w SAN) i klucza prywatnego:

```bash
sudo bash addHttps.sh 192.168.1.12 /ścieżka/do/certyfikatu.crt /ścieżka/do/klucza.key
```

Skrypt sprawdza adres IP w certyfikacie oraz zgodność klucza, a następnie przełącza konfigurację Nginx z HTTP na HTTPS. Nginx udostępnia aplikację pod `https://192.168.1.12:8080`. Otwórz port TCP 8080 na zaporze serwera.

Usługa aplikacji i logi:

```bash
curl -I http://127.0.0.1:8282/
curl -I --cacert /etc/nginx/tls/image-uploader.crt https://192.168.1.12:8080/
sudo systemctl status image-uploader.service
sudo systemctl status nginx
sudo journalctl -u image-uploader.service -n 100 --no-pager
```

Konfiguracja Nginx i certyfikat trafiają odpowiednio do `/etc/nginx/` i `/etc/nginx/tls/`. Plik certyfikatu jest publiczny, a klucz prywatny ma uprawnienia `0600` i należy do `root`.
