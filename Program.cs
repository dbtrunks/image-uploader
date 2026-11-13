using Microsoft.AspNetCore.Http.Features;
using System.Text.Json.Serialization;

const long maxFileSize = 50 * 1024 * 1024;
const long maxRequestSize = maxFileSize + 1024 * 1024;

var builder = WebApplication.CreateBuilder(args);

#if WINDOWS_SERVICE
builder.Host.UseWindowsService();
#endif

builder.Services.Configure<FormOptions>(options =>
{
    options.MultipartBodyLengthLimit = maxRequestSize;
});

builder.WebHost.ConfigureKestrel(options =>
{
    options.Limits.MaxRequestBodySize = maxRequestSize;
});

var app = builder.Build();
var destinations = builder.Configuration.GetSection("Upload:Destinations").GetChildren()
    .Select(section =>
    {
        var id = section["Id"];
        var name = section["Name"];
        var configuredPath = section["Path"];
        if (string.IsNullOrWhiteSpace(id) || string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(configuredPath))
        {
            throw new InvalidOperationException("Każde miejsce docelowe musi mieć ustawione Id, Name i Path.");
        }

        var path = Path.GetFullPath(Path.IsPathRooted(configuredPath)
            ? configuredPath
            : Path.Combine(app.Environment.ContentRootPath, configuredPath));
        Directory.CreateDirectory(path);
        return new UploadDestination(id, name, path);
    })
    .ToArray();
var destinationsById = destinations.ToDictionary(destination => destination.Id, StringComparer.Ordinal);

app.UseDefaultFiles();
app.UseStaticFiles();

app.MapGet("/api/destinations", () =>
    Results.Json(
        destinations.Select(destination => new DestinationOption(destination.Id, destination.Name)).ToArray(),
        AppJsonSerializerContext.Default.DestinationOptionArray));

app.MapPost("/api/upload", async (HttpRequest request, CancellationToken cancellationToken) =>
{
    IFormCollection form;
    try
    {
        form = await request.ReadFormAsync(cancellationToken);
    }
    catch (InvalidDataException)
    {
        return Results.Text("Nieprawidłowe dane formularza.", statusCode: StatusCodes.Status400BadRequest);
    }

    if (!form.TryGetValue("destinationId", out var destinationIdValue)
        || !destinationsById.TryGetValue(destinationIdValue.ToString(), out var destination))
    {
        return Results.Text("Wybierz prawidłowe miejsce docelowe.", statusCode: StatusCodes.Status400BadRequest);
    }

    if (form.Files.Count != 1)
    {
        return Results.Text("Prześlij dokładnie jeden plik.", statusCode: StatusCodes.Status400BadRequest);
    }

    var file = form.Files[0];
    if (file.Length == 0)
    {
        return Results.Text("Plik jest pusty.", statusCode: StatusCodes.Status400BadRequest);
    }

    if (file.Length > maxFileSize)
    {
        return Results.Text("Maksymalny rozmiar pliku to 50 MB.", statusCode: StatusCodes.Status400BadRequest);
    }

    var fileName = Path.GetFileName(file.FileName.Replace('\\', '/'));
    if (string.IsNullOrWhiteSpace(fileName)
        || fileName is "." or ".."
        || fileName.Any(character =>
            char.IsControl(character) || character is '<' or '>' or ':' or '"' or '|' or '?' or '*'))
    {
        return Results.Text("Nieprawidłowa nazwa pliku.", statusCode: StatusCodes.Status400BadRequest);
    }

    var fileNameWithoutExtension = Path.GetFileNameWithoutExtension(fileName);
    var extension = Path.GetExtension(fileName);
    FileStream output;
    for (var suffix = 0; ; suffix++)
    {
        var candidateFileName = suffix == 0
            ? fileName
            : $"{fileNameWithoutExtension}_{suffix}{extension}";
        var filePath = Path.Combine(destination.Path, candidateFileName);
        try
        {
            output = new FileStream(filePath, FileMode.CreateNew, FileAccess.Write, FileShare.None);
            break;
        }
        catch (IOException) when (File.Exists(filePath))
        {
        }
    }

    await using (output)
    {
        await file.CopyToAsync(output, cancellationToken);
    }

    return Results.Text("Plik został zapisany.");
});

app.Run();

internal sealed record UploadDestination(string Id, string Name, string Path);
internal sealed record DestinationOption(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("name")] string Name);

[JsonSerializable(typeof(DestinationOption[]))]
internal partial class AppJsonSerializerContext : JsonSerializerContext
{
}
