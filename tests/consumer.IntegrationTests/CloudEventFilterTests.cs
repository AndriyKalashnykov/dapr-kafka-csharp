namespace Dapr.Examples.Pubsub.Consumer.IntegrationTests;

using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using TUnit.Core;

// Validates the CloudEvents filter: POST /sampletopic should unwrap a CloudEvents
// envelope when Content-Type is application/cloudevents+json.
[ClassDataSource<ConsumerApiFixture>(Shared = SharedType.PerClass)]
[Category("Integration")]
public sealed class CloudEventFilterTests
{
    private readonly ConsumerApiFixture _fixture;

    public CloudEventFilterTests(ConsumerApiFixture fixture)
    {
        _fixture = fixture;
    }

    [Test]
    public async Task Post_WithMatchingEventType_IsAccepted()
    {
        using var client = _fixture.Factory.CreateClient();
        var envelope = new
        {
            specversion = "1.0",
            type = "com.dapr.event.sent",
            source = "producer",
            id = Guid.NewGuid().ToString(),
            datacontenttype = "application/json",
            data = new
            {
                correlationId = Guid.NewGuid(),
                messageId = Guid.NewGuid(),
                message = "cloudevent-body",
                creationDate = DateTime.UtcNow,
                sentiment = "neutral",
                previousAppTimestamp = DateTime.UtcNow,
            },
        };

        var json = JsonSerializer.Serialize(envelope);
        using var content = new StringContent(json, Encoding.UTF8);
        content.Headers.ContentType = new MediaTypeHeaderValue("application/cloudevents+json");

        using var resp = await client.PostAsync("/sampletopic", content);

        await Assert.That(resp.IsSuccessStatusCode).IsTrue();
    }
}
