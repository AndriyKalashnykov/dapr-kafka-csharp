namespace Dapr.Examples.Pubsub.Producer.Tests;

using System;
using System.Threading.Tasks;
using Dapr.Examples.Pubsub.Producer;
using TUnit.Core;

// Accesses internal static helpers on Program via InternalsVisibleTo("producer.UnitTests").
public sealed class MessageGeneratorTests
{
    [Test]
    public async Task GenerateNewMessage_PopulatesRequiredFields()
    {
        var msg = Program.GenerateNewMessage();

        await Assert.That(msg).IsNotNull();
        await Assert.That(msg.CorrelationId).IsNotEqualTo(Guid.Empty);
        await Assert.That(msg.MessageId).IsNotEqualTo(Guid.Empty);
        await Assert.That(msg.Message).IsNotNull();
        await Assert.That(msg.Message).IsNotEmpty();
        await Assert.That(msg.CreationDate.Kind).IsEqualTo(DateTimeKind.Utc);
        await Assert.That(msg.PreviousAppTimestamp.Kind).IsEqualTo(DateTimeKind.Utc);
    }

    [Test]
    public async Task GenerateNewMessage_EveryCallProducesUniqueIds()
    {
        var a = Program.GenerateNewMessage();
        var b = Program.GenerateNewMessage();

        await Assert.That(a.CorrelationId).IsNotEqualTo(b.CorrelationId);
        await Assert.That(a.MessageId).IsNotEqualTo(b.MessageId);
    }

    [Test]
    public async Task GenerateRandomMessage_EndsWithHashtagFromKnownSet()
    {
        var known = new[]
        {
            "#circle", "#ellipse", "#square", "#rectangle", "#triangle",
            "#star", "#cardioid", "#epicycloid", "#limocon", "#hypocycoid",
        };

        for (int i = 0; i < 20; i++)
        {
            var s = Program.GenerateRandomMessage();

            await Assert.That(s).Contains(" #");
            var tag = s[s.IndexOf(" #", StringComparison.Ordinal)..].Trim();
            await Assert.That(known).Contains(tag);
        }
    }

    [Test]
    public async Task GenerateRandomMessage_PrefixIsLowercaseAlphaOfLength5To9()
    {
        for (int i = 0; i < 20; i++)
        {
            var s = Program.GenerateRandomMessage();
            var prefix = s.Split(" #", 2)[0];

            await Assert.That(prefix.Length).IsGreaterThanOrEqualTo(5);
            await Assert.That(prefix.Length).IsLessThanOrEqualTo(9);
            foreach (var c in prefix)
            {
                await Assert.That(c is >= 'a' and <= 'z').IsTrue();
            }
        }
    }
}
