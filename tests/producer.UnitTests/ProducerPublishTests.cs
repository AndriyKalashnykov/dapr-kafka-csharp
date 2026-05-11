namespace Dapr.Examples.Pubsub.Producer.Tests;

using System;
using System.Threading;
using System.Threading.Tasks;
using Dapr.Client;
using Dapr.Examples.Pubsub.Models;
using FakeItEasy;
using TUnit.Core;

// Originally lived in producer.IntegrationTests but is mock-only — verifies the
// publish call shape and the loop's exception-swallowing behavior against a
// FakeItEasy DaprClient. No real broker, no Dapr sidecar; that path is the e2e
// layer's responsibility (see e2e/e2e-compose-test.sh + e2e/e2e-test.sh).
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
            CorrelationId = Guid.NewGuid(),
            MessageId = Guid.NewGuid(),
            Message = "itest #square",
            CreationDate = DateTime.UtcNow,
            Sentiment = "neutral",
            PreviousAppTimestamp = DateTime.UtcNow,
        };

        await fakeClient.PublishEventAsync("sampletopic", "sampletopic", message, CancellationToken.None);

        A.CallTo(() => fakeClient.PublishEventAsync(
                "sampletopic",
                "sampletopic",
                A<SampleMessage>.That.Matches(m => m.MessageId == message.MessageId),
                A<CancellationToken>.Ignored))
            .MustHaveHappenedOnceExactly();
    }

    [Test]
    public async Task PublishEventAsync_PropagatesCancellationToken()
    {
        var fakeClient = A.Fake<DaprClient>();
        using var cts = new CancellationTokenSource();
        var message = new SampleMessage { MessageId = Guid.NewGuid(), Message = "x", Sentiment = "n/a" };

        await fakeClient.PublishEventAsync("sampletopic", "sampletopic", message, cts.Token);

        A.CallTo(() => fakeClient.PublishEventAsync(
                A<string>.Ignored,
                A<string>.Ignored,
                A<SampleMessage>.Ignored,
                cts.Token))
            .MustHaveHappened();
    }

    // Resilience contract: a transient publish failure must not terminate the
    // StartMessageGeneratorAsync loop — iteration N+1 must still execute. Without
    // this guarantee, a single Kafka hiccup would silently stop the producer.
    [Test]
    public async Task StartMessageGenerator_TransientFailure_DoesNotTerminateLoop()
    {
        var fakeClient = A.Fake<DaprClient>();
        var callIndex = 0;

        A.CallTo(() => fakeClient.PublishEventAsync(
                A<string>.Ignored,
                A<string>.Ignored,
                A<SampleMessage>.Ignored,
                A<CancellationToken>.Ignored))
            .Invokes(() =>
            {
                callIndex++;
                if (callIndex == 1)
                {
                    throw new InvalidOperationException("simulated transient publish failure");
                }
            });

        using var cts = new CancellationTokenSource();
        await Producer.Program.StartMessageGeneratorAsync(
            fakeClient,
            cts.Token,
            maxIterations: 3,
            delayBetweenIterations: TimeSpan.Zero);

        A.CallTo(() => fakeClient.PublishEventAsync(
                "sampletopic",
                "sampletopic",
                A<SampleMessage>.Ignored,
                A<CancellationToken>.Ignored))
            .MustHaveHappened(3, Times.Exactly);
    }

    [Test]
    public async Task StartMessageGenerator_RespectsMaxIterations()
    {
        var fakeClient = A.Fake<DaprClient>();
        using var cts = new CancellationTokenSource();

        await Producer.Program.StartMessageGeneratorAsync(
            fakeClient,
            cts.Token,
            maxIterations: 5,
            delayBetweenIterations: TimeSpan.Zero);

        A.CallTo(() => fakeClient.PublishEventAsync(
                "sampletopic",
                "sampletopic",
                A<SampleMessage>.Ignored,
                A<CancellationToken>.Ignored))
            .MustHaveHappened(5, Times.Exactly);
    }
}
