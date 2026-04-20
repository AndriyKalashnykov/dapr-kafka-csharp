# https://mcr.microsoft.com/en-us/product/dotnet/aspnet/tags
FROM mcr.microsoft.com/dotnet/aspnet:10.0@sha256:9271888dde1f4408dfb7ce75bc0f513c903d20ff2f1287ab153b641d4588ec7d AS base
WORKDIR /app

FROM mcr.microsoft.com/dotnet/sdk:10.0@sha256:adc02be8b87957d07208a4a3e51775935b33bad3317de8c45b1e67357b4c073b AS build
WORKDIR /src
# Copy everything else and build
COPY ./models ./models
COPY ./producer ./producer
RUN dotnet restore "models/models.csproj"
RUN dotnet restore "producer/producer.csproj"

WORKDIR /src/producer
RUN dotnet build "producer.csproj" --no-restore -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "producer.csproj" --no-restore -c Release -o /app/publish /p:UseAppHost=false

# Build runtime image
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
# Run as non-root using .NET's built-in app user (UID 1654, documented as APP_UID in dotnet/aspnet base).
USER $APP_UID
ENTRYPOINT ["dotnet", "producer.dll"]
