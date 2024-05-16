FROM mcr.microsoft.com/dotnet/runtime:8.0 AS runtime
WORKDIR /app

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
# Copy everything else and build
COPY ./models ./models
COPY ./producer ./producer
RUN dotnet restore "models/models.csproj"
RUN dotnet restore "producer/producer.csproj"

WORKDIR /src/producer
RUN dotnet build "producer.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "producer.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Build runtime image
FROM runtime AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "producer.dll"]
