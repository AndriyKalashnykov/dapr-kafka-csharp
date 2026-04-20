namespace Dapr.Examples.Pubsub.Models.Tests;

using System;
using System.Text.Json;
using System.Threading.Tasks;
using Dapr.Examples.Pubsub.Models;
using TUnit.Core;

public sealed class SampleMessageTests
{
    private static readonly JsonSerializerOptions CamelCase = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
    };

    [Test]
    public async Task RoundTrip_PreservesAllFields()
    {
        var original = new SampleMessage
        {
            CorrelationId = Guid.NewGuid(),
            MessageId = Guid.NewGuid(),
            Message = "hello #circle",
            CreationDate = new DateTime(2026, 4, 20, 12, 0, 0, DateTimeKind.Utc),
            Sentiment = "positive",
            PreviousAppTimestamp = new DateTime(2026, 4, 20, 11, 59, 50, DateTimeKind.Utc),
        };

        var json = JsonSerializer.Serialize(original, CamelCase);
        var round = JsonSerializer.Deserialize<SampleMessage>(json, CamelCase);

        await Assert.That(round).IsNotNull();
        await Assert.That(round!.CorrelationId).IsEqualTo(original.CorrelationId);
        await Assert.That(round.MessageId).IsEqualTo(original.MessageId);
        await Assert.That(round.Message).IsEqualTo(original.Message);
        await Assert.That(round.CreationDate).IsEqualTo(original.CreationDate);
        await Assert.That(round.Sentiment).IsEqualTo(original.Sentiment);
        await Assert.That(round.PreviousAppTimestamp).IsEqualTo(original.PreviousAppTimestamp);
    }

    [Test]
    public async Task Serialize_UsesCamelCasePropertyNames()
    {
        var msg = new SampleMessage
        {
            CorrelationId = Guid.Empty,
            MessageId = Guid.Empty,
            Message = "x",
            Sentiment = "n/a",
        };

        var json = JsonSerializer.Serialize(msg, CamelCase);

        await Assert.That(json).Contains("\"correlationId\"");
        await Assert.That(json).Contains("\"messageId\"");
        await Assert.That(json).Contains("\"creationDate\"");
        await Assert.That(json).Contains("\"previousAppTimestamp\"");
    }

    [Test]
    public async Task Deserialize_IsCaseInsensitive()
    {
        const string json = "{\"CorrelationId\":\"00000000-0000-0000-0000-000000000000\",\"MESSAGEID\":\"00000000-0000-0000-0000-000000000000\",\"message\":\"m\"}";

        var msg = JsonSerializer.Deserialize<SampleMessage>(json, CamelCase);

        await Assert.That(msg).IsNotNull();
        await Assert.That(msg!.Message).IsEqualTo("m");
    }
}
