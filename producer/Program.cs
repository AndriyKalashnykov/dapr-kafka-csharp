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
            await StartMessageGeneratorAsync(cts.Token);
        }

        static async Task StartMessageGeneratorAsync(CancellationToken cancellationToken)
        {
            var daprClientBuilder = new DaprClientBuilder();
            var client = daprClientBuilder.Build();
            
            string PUBSUB_NAME = "sampletopic";
            string TOPIC_NAME = "sampletopic";

            while (true)
            {
                // var message = GenerateNewMessage();
                // Console.WriteLine("Publishing: {0}", message.Message);
                
                Random random = new Random();
                int orderId = random.Next(1,1000);
                var eventData = new { Id = orderId, Amount = orderId, };
                Console.WriteLine("Published data: " + orderId);

                try
                {
                    await client.PublishEventAsync(PUBSUB_NAME, TOPIC_NAME, eventData, cancellationToken);
                }
                catch (Exception ex)
                {
                    Console.WriteLine(ex);
                }

                // Delay 10 seconds
                await Task.Delay(TimeSpan.FromSeconds(10.0));
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

