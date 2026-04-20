// ------------------------------------------------------------
// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
// ------------------------------------------------------------

namespace Dapr.Examples.Pubsub.Consumer
{
    using Microsoft.AspNetCore.Hosting;
    using Microsoft.Extensions.Hosting;

    public class Program
    {
        // YAML-coupled constant: must match k8s/consumer.yaml (containerPort, targetPort,
        // dapr.io/app-port) and `dapr run --app-port` in the Makefile target.
        // Do NOT externalize — changing requires editing all four locations in lockstep.
        internal const string AppBindUrl = "http://*:6000";

        public static void Main(string[] args)
        {
            CreateHostBuilder(args).Build().Run();
        }

        public static IHostBuilder CreateHostBuilder(string[] args) =>
            Host.CreateDefaultBuilder(args)
                .ConfigureWebHostDefaults(webBuilder =>
                {
                    webBuilder.UseStartup<Startup>().UseUrls(AppBindUrl);
                });
    }
}
