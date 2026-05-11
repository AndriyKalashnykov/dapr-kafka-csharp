// ------------------------------------------------------------
// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
// ------------------------------------------------------------

namespace Dapr.Examples.Pubsub.Consumer
{
    using Dapr.Client;
    using Dapr.Examples.Pubsub.Models;

    using Microsoft.AspNetCore.Builder;
    using Microsoft.AspNetCore.Hosting;
    using Microsoft.AspNetCore.Http;
    using Microsoft.Extensions.Configuration;
    using Microsoft.Extensions.DependencyInjection;
    using Microsoft.Extensions.Hosting;
    using System;
    using System.Text.Json;
    using System.Threading.Tasks;

    public class Startup
    {
        public Startup(IConfiguration configuration)
        {
            Configuration = configuration;
        }

        public IConfiguration Configuration { get; }

        private JsonSerializerOptions serializerOptions = new JsonSerializerOptions()
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            PropertyNameCaseInsensitive = true,
        };

        // This method gets called by the runtime. Use this method to add services to the container.
        public void ConfigureServices(IServiceCollection services)
        {
            // Enable Dapr Client
            services.AddDaprClient();
            services.AddSingleton(serializerOptions);
        }

        // This method gets called by the runtime. Use this method to configure the HTTP request pipeline.
        public void Configure(IApplicationBuilder app, IWebHostEnvironment env)
        {
            if (env.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
            }

            app.UseRouting();

            // Enable Cloud Event Middleware to unwrap cloud event payload
            app.UseCloudEvents();

            Dapr.TopicOptions topicOptions = new()
            {
                Match = "event.type==\"com.dapr.event.sent\"",
                PubsubName = "sampletopic",
                Name = "sampletopic"
            };

            app.UseEndpoints(endpoints =>
            {
                // Register Subscribe Handlers
                endpoints.MapSubscribeHandler();

                // Register the delegate to consume the messages from "sampletopic" topic
                endpoints.MapPost("sampletopic", this.ConsumeMessage).WithTopic(topicOptions);
            });
        }

        // ConsumeMessage subscribes the message from Producer.
        private async Task ConsumeMessage(HttpContext context)
        {
            Console.WriteLine("Message is delivered.");

            SampleMessage message;
            try
            {
                message = await JsonSerializer.DeserializeAsync<SampleMessage>(context.Request.Body, serializerOptions);
            }
            catch (JsonException ex)
            {
                await WriteProblemAsync(context, StatusCodes.Status400BadRequest, "Bad Request", $"Invalid JSON payload: {ex.Message}");
                return;
            }

            if (message is null)
            {
                await WriteProblemAsync(context, StatusCodes.Status400BadRequest, "Bad Request", "Request body deserialized to null.");
                return;
            }

            Console.WriteLine($"message id: {message.MessageId}");
            Console.WriteLine($"message context: {message.Message}");
            Console.WriteLine($"message creation time: {message.PreviousAppTimestamp}");
        }

        // Writes an RFC 7807 ProblemDetails JSON response with the proper
        // `application/problem+json` Content-Type. We serialize to a string FIRST
        // then call WriteAsync(string) — earlier attempts using
        // JsonSerializer.SerializeAsync(context.Response.Body, ...) lost the
        // Content-Type header under Kestrel (works under WebApplicationFactory's
        // TestServer; fails on real Kestrel). The serialize-then-write order
        // ensures headers are committed by WriteAsync after ContentType is set.
        private async Task WriteProblemAsync(HttpContext context, int statusCode, string title, string detail)
        {
            var json = JsonSerializer.Serialize(
                new
                {
                    type = "about:blank",
                    title,
                    status = statusCode,
                    detail,
                },
                serializerOptions);

            context.Response.StatusCode = statusCode;
            context.Response.ContentType = "application/problem+json";
            await context.Response.WriteAsync(json);
        }
    }
}
