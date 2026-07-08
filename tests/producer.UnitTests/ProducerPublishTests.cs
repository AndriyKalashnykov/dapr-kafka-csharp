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
    // Contract under test: one iteration of the REAL producer loop
    // (Program.StartMessageGeneratorAsync) must call DaprClient.PublishEventAsync
    // with pubsub name "sampletopic", topic name "sampletopic", and a non-null
    // SampleMessage that the production code generated. Driving the real loop (not
    // calling the fake directly) is what makes this a contract test rather than a
    // tautology that asserts the mock recorded its own invocation.

    [Test]
    public async Task StartMessageGenerator_PublishesToSampletopicWithGeneratedMessage()
    {
        var fakeClient = A.Fake<DaprClient>();
        using var cts = new CancellationTokenSource();

        await Producer.Program.StartMessageGeneratorAsync(
            fakeClient, cts.Token, maxIterations: 1, delayBetweenIterations: TimeSpan.Zero);

        A.CallTo(() => fakeClient.PublishEventAsync(
                "sampletopic",
                "sampletopic",
                A<SampleMessage>.That.Matches(m =>
                    m != null && m.MessageId != Guid.Empty && !string.IsNullOrEmpty(m.Message)),
                A<CancellationToken>.Ignored))
            .MustHaveHappenedOnceExactly();
    }

    [Test]
    public async Task StartMessageGenerator_PropagatesCancellationTokenToPublish()
    {
        var fakeClient = A.Fake<DaprClient>();
        using var cts = new CancellationTokenSource();

        await Producer.Program.StartMessageGeneratorAsync(
            fakeClient, cts.Token, maxIterations: 1, delayBetweenIterations: TimeSpan.Zero);

        // The exact token handed to the loop must flow through to the publish call.
        A.CallTo(() => fakeClient.PublishEventAsync(
                A<string>.Ignored,
                A<string>.Ignored,
                A<SampleMessage>.Ignored,
                cts.Token))
            .MustHaveHappenedOnceExactly();
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
