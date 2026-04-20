namespace Dapr.Examples.Pubsub.Consumer.IntegrationTests;

using System;
using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Dapr.Examples.Pubsub.Models;
using TUnit.Core;

[ClassDataSource<ConsumerApiFixture>(Shared = SharedType.PerClass)]
[Category("Integration")]
public sealed class ConsumeMessageTests
{
    private readonly ConsumerApiFixture _fixture;

    public ConsumeMessageTests(ConsumerApiFixture fixture)
    {
        _fixture = fixture;
    }

    private static readonly JsonSerializerOptions CamelCase = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    [Test]
    public async Task Post_SampletopicWithValidMessage_ReturnsSuccess()
    {
        using var client = _fixture.Factory.CreateClient();
        var msg = new SampleMessage
        {
            CorrelationId = Guid.NewGuid(),
            MessageId = Guid.NewGuid(),
            Message = "integration-test-body",
            CreationDate = DateTime.UtcNow,
            Sentiment = "neutral",
            PreviousAppTimestamp = DateTime.UtcNow,
        };

        using var resp = await client.PostAsJsonAsync("/sampletopic", msg, CamelCase);

        await Assert.That(resp.IsSuccessStatusCode).IsTrue();
    }

    [Test]
    public async Task Post_SampletopicWithMalformedBody_Returns4xx()
    {
        using var client = _fixture.Factory.CreateClient();
        using var body = new StringContent("not-json-at-all", Encoding.UTF8, "application/json");

        using var resp = await client.PostAsync("/sampletopic", body);

        await Assert.That((int)resp.StatusCode).IsGreaterThanOrEqualTo(400);
        await Assert.That((int)resp.StatusCode).IsLessThan(500);
    }

    [Test]
    public async Task Post_SampletopicWithEmptyBody_Returns400()
    {
        using var client = _fixture.Factory.CreateClient();
        using var body = new StringContent("null", Encoding.UTF8, "application/json");

        using var resp = await client.PostAsync("/sampletopic", body);

        await Assert.That(resp.StatusCode).IsEqualTo(HttpStatusCode.BadRequest);
    }
}
