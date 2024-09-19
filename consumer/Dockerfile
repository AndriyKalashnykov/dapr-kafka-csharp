FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
# Copy everything else and build
COPY ./models ./models
COPY ./consumer ./consumer
RUN dotnet restore "models/models.csproj"
RUN dotnet restore "consumer/consumer.csproj"

WORKDIR /src/consumer
RUN dotnet build "consumer.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "consumer.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Build runtime image
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "consumer.dll"]
