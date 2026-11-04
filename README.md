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

```powershell
dotnet publish -c Release -r win-x64
```

Wybierz identyfikator środowiska uruchomieniowego odpowiedni dla systemu docelowego, np. `linux-x64` lub `linux-arm64`.
