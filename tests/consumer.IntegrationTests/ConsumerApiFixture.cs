namespace Dapr.Examples.Pubsub.Consumer.IntegrationTests;

using System.Threading.Tasks;
using Dapr.Examples.Pubsub.Consumer;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using TUnit.Core.Interfaces;

// Hosts the consumer Program via WebApplicationFactory with an in-memory TestServer.
// UseUrls() is ignored under TestServer so the :6000 bind contract does not collide.
public sealed class ConsumerApiFixture : IAsyncInitializer, System.IAsyncDisposable
{
    public WebApplicationFactory<Program> Factory { get; private set; } = null!;

    public Task InitializeAsync()
    {
        Factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder => builder.UseEnvironment("Test"));

        return Task.CompletedTask;
    }

    public async ValueTask DisposeAsync()
    {
        if (Factory is not null)
        {
            await Factory.DisposeAsync();
        }
    }
}
