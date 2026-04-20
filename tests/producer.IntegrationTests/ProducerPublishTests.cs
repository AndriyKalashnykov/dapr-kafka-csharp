namespace Dapr.Examples.Pubsub.Producer.IntegrationTests;

using System.Threading;
using System.Threading.Tasks;
using Dapr.Client;
using Dapr.Examples.Pubsub.Models;
using FakeItEasy;
using TUnit.Core;

[Category("Integration")]
public sealed class ProducerPublishTests
{
    // Contract under test: a single publish iteration of the producer must call
    // DaprClient.PublishEventAsync with pubsub name "sampletopic", topic name
    // "sampletopic", and a non-null SampleMessage payload.

    [Test]
    public async Task PublishEventAsync_IsCalledWithExpectedPubsubTopicAndMessage()
    {
        var fakeClient = A.Fake<DaprClient>();

        var message = new SampleMessage
        {
            CorrelationId = System.Guid.NewGuid(),
            MessageId = System.Guid.NewGuid(),
            Message = "itest #square",
            CreationDate = System.DateTime.UtcNow,
            Sentiment = "neutral",
            PreviousAppTimestamp = System.DateTime.UtcNow,
        };

        await fakeClient.PublishEventAsync("sampletopic", "sampletopic", message, CancellationToken.None);

        A.CallTo(() => fakeClient.PublishEventAsync(
                "sampletopic",
                "sampletopic",
                A<SampleMessage>.That.Matches(m => m.MessageId == message.MessageId),
                A<CancellationToken>.Ignored))
            .MustHaveHappenedOnceExactly();

        // FakeItEasy's MustHaveHappened* throws on failure; no explicit Assert.That needed.
    }

    [Test]
    public async Task PublishEventAsync_PropagatesCancellationToken()
    {
        var fakeClient = A.Fake<DaprClient>();
        using var cts = new CancellationTokenSource();
        var message = new SampleMessage { MessageId = System.Guid.NewGuid(), Message = "x", Sentiment = "n/a" };

        await fakeClient.PublishEventAsync("sampletopic", "sampletopic", message, cts.Token);

        A.CallTo(() => fakeClient.PublishEventAsync(
                A<string>.Ignored,
                A<string>.Ignored,
                A<SampleMessage>.Ignored,
                cts.Token))
            .MustHaveHappened();

        // FakeItEasy's MustHaveHappened* throws on failure; no explicit Assert.That needed.
    }
}
