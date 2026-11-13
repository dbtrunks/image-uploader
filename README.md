# Przesyłanie plików

Lekka aplikacja webowa w ASP.NET Core 10, bez zewnętrznych bibliotek JavaScript. Umożliwia dodanie wielu plików, podgląd zdjęć, przesyłanie kolejno z postępem dla każdego pliku oraz wznowienie nieudanych przesyłań.

## Uruchomienie

Wymagany jest .NET 10 SDK.

```powershell
dotnet run
```

Otwórz adres wyświetlony przez aplikację. Użytkownik wybiera miejsce docelowe z listy skonfigurowanej przez administratora. Domyślna konfiguracja zapisuje pliki w katalogu `uploads` obok pliku projektu. Limit wynosi 50 MB na plik i 100 plików w kolejce.

Pliki są zapisywane pod oryginalnymi nazwami. Jeśli plik o danej nazwie już istnieje, aplikacja dopisuje numer przed rozszerzeniem, np. `domek_1.png`.

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

## Instalacja z GitHub Releases

Każdy tag `v*` buduje dwa samodzielne pakiety Native AOT dla x64 i publikuje je jako pliki `.tar.gz` w [GitHub Releases](https://github.com/dbtrunks/image-uploader/releases):

- `ImageUploader-linux-x64.tar.gz`
- `ImageUploader-win-x64.tar.gz`

Wybierz tag wydania, np. `v1.0.0`, aby zainstalować konkretną wersję. Pominięcie tagu w poleceniu instalatora wybiera najnowsze wydanie. Do instalacji nie jest potrzebny .NET Runtime.

### Linux

Wymagany jest Linux z systemd; instalator automatycznie doinstaluje Nginx przez `apt-get`, jeśli go brakuje. Pobierz instalator z repozytorium i uruchom go jako root:

```bash
curl -fsSLo install.sh https://raw.githubusercontent.com/dbtrunks/image-uploader/main/install/install.sh
sudo bash install.sh
```

Aby zainstalować konkretny tag:

```bash
sudo bash install.sh v1.0.0
```

Instalator pobiera odpowiednie archiwum z GitHub Releases, zachowuje istniejący `appsettings.json` podczas aktualizacji i konfiguruje usługę systemd oraz Nginx. Aplikacja nasłuchuje lokalnie na `127.0.0.1:8282`, a Nginx udostępnia ją przez HTTP na porcie 8080. Dane są zapisywane w `/var/lib/image-uploader/uploads` i `/var/lib/image-uploader/images`. Otwórz TCP 8080 na zaporze serwera.

#### Włączenie HTTPS na Linuxie

Po instalacji pobierz skrypt HTTPS i uruchom go, podając adres IP serwera:

```bash
curl -fsSLo addHttps.sh https://raw.githubusercontent.com/dbtrunks/image-uploader/main/install/addHttps.sh
sudo bash addHttps.sh 192.168.1.12
```

Domyślnie skrypt tworzy certyfikat samopodpisany z adresem IP w SAN. Przeglądarka będzie wyświetlała ostrzeżenie, dopóki certyfikat nie zostanie dodany do zaufanych certyfikatów klientów. Możesz podać własny certyfikat i klucz:

```bash
sudo bash addHttps.sh 192.168.1.12 /ścieżka/do/certyfikatu.crt /ścieżka/do/klucza.key
```

Po włączeniu HTTPS Nginx obsługuje aplikację pod `https://192.168.1.12:8080`. Skrypt sprawdza adres IP w certyfikacie i zgodność klucza.

Status usługi i logi:

```bash
sudo systemctl status image-uploader.service
sudo systemctl status nginx
sudo journalctl -u image-uploader.service -n 100 --no-pager
```

### Windows

Wymagany jest Windows x64 z PowerShell 5.1 lub nowszym oraz wbudowanym `tar.exe`. Otwórz PowerShell jako administrator, pobierz instalator i uruchom go z pominięciem blokady skryptów pobranych z Internetu:

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/dbtrunks/image-uploader/main/install/install.ps1 -OutFile install.ps1
powershell.exe -ExecutionPolicy Bypass -File .\install.ps1
```

Aby zainstalować konkretny tag:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\install.ps1 -Version v1.0.0
```

Instalator pobiera pakiet z GitHub Releases, zachowuje istniejący `appsettings.json` podczas aktualizacji, rejestruje automatycznie uruchamianą usługę Windows `ImageUploader` i dodaje regułę zapory dla TCP 8282 w profilach domenowym/prywatnym. Aplikacja jest dostępna pod `http://<IP-komputera>:8282/`. Dane znajdują się w `%ProgramData%\ImageUploader`. Ogranicz dostęp do zaufanej sieci; ten wariant nie konfiguruje HTTPS.

Aby sprawdzić lub sterować usługą:

```powershell
Get-Service -Name ImageUploader
Stop-Service -Name ImageUploader
Start-Service -Name ImageUploader
```

Wersja Windows jest budowana z obsługą Windows Service; zależność ta nie jest dodawana do buildu Linux. Logi usługi można sprawdzić w Podglądzie zdarzeń Windows, w dzienniku **Aplikacja**.
