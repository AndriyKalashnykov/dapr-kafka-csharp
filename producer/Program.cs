// ------------------------------------------------------------
// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
// ------------------------------------------------------------

using System.Threading;

namespace Dapr.Examples.Pubsub.Producer
{
    using Dapr.Client;
    using Dapr.Examples.Pubsub.Models;

    using System;
    using System.Threading.Tasks;

    class Program
    {
        static async Task Main(string[] args)
        {
            var cts = new CancellationTokenSource();
            using var client = new DaprClientBuilder().Build();
            await StartMessageGeneratorAsync(client, cts.Token);
        }

        // Injectable client + bounded iteration count + configurable delay so the loop is
        // unit-testable. Production callers pass the real DaprClient with the defaults
        // (infinite loop, 10s delay); tests pass a fake client + small bounds.
        static internal async Task StartMessageGeneratorAsync(
            DaprClient client,
            CancellationToken cancellationToken,
            int maxIterations = -1,
            TimeSpan? delayBetweenIterations = null)
        {
            var delay = delayBetweenIterations ?? TimeSpan.FromSeconds(10.0);
            const string PUBSUB_NAME = "sampletopic";
            const string TOPIC_NAME = "sampletopic";

            int iter = 0;
            while (maxIterations < 0 || iter < maxIterations)
            {
                var message = GenerateNewMessage();
                Console.WriteLine("Publishing data: {0}", message.Message);

                try
                {
                    await client.PublishEventAsync(PUBSUB_NAME, TOPIC_NAME, message, cancellationToken);
                }
                catch (Exception ex)
                {
                    // Transient publish failure must not terminate the loop — log and continue.
                    Console.WriteLine(ex);
                }

                iter++;
                if (maxIterations < 0 || iter < maxIterations)
                {
                    await Task.Delay(delay, cancellationToken);
                }
            }
        }

        static internal SampleMessage GenerateNewMessage()
        {
            return new SampleMessage()
            {
                CorrelationId = Guid.NewGuid(),
                MessageId = Guid.NewGuid(),
                Message = GenerateRandomMessage(),
                CreationDate = DateTime.UtcNow,
                PreviousAppTimestamp = DateTime.UtcNow
            };
        }

        static internal string GenerateRandomMessage()
        {
            var random = new Random();
            var HashTags = new string[]
            {
                "circle",
                "ellipse",
                "square",
                "rectangle",
                "triangle",
                "star",
                "cardioid",
                "epicycloid",
                "limocon",
                "hypocycoid"
            };

            int length = random.Next(5, 10);
            string s = "";
            for (int i = 0; i < length; i++)
            {
                int j = random.Next(26);
                char c = (char)('a' + j);
                s += c;
            }
            s += " #" + HashTags[random.Next(HashTags.Length)];
            return s;
        }
    }

}

