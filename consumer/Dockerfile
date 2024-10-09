# https://mcr.microsoft.com/en-us/product/dotnet/runtime/tags
FROM mcr.microsoft.com/dotnet/runtime:8.0-cbl-mariner2.0 AS base
WORKDIR /app

FROM mcr.microsoft.com/dotnet/sdk:8.0.403 AS build
WORKDIR /src
# Copy everything else and build
COPY ./models ./models
COPY ./consumer ./consumer
RUN dotnet restore "models/models.csproj"
RUN dotnet restore "consumer/consumer.csproj"

WORKDIR /src/consumer
RUN dotnet build "consumer.csproj" --no-restore -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "consumer.csproj" --no-restore -c Release -o /app/publish /p:UseAppHost=false

# Build runtime image
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "consumer.dll"]
