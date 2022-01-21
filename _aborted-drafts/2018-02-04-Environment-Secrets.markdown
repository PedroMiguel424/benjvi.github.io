---
layout: post
title: "Automating Deployments with environment-specific config and secrets"
categories: [technology]
image: ibelonghere.png
---

An interesting part of working as a consultant is that the challenges described to you by a client at the start of a project always turnout to be different to the challenges that you actually face during a project. One of the themes that always seems to pop up unexpectedly is continuous delivery. I see a lot of companies that think Continuous Delivery is not strategically important. Or, at least, it is not grand enough to devote an initiative to improving. The reason is perhaps that, if you have a simple setup with a single target environment, a simple `circle.yml` or `travis.yml` file usually suffices to build and deploy into the target environment. That file maybe calls a couple of custom build and deploy scripts too. So it really doesn't look difficult. 

However, in cases where releases need to be deployed into multiple environments, or deployed releases rely on multiple evolving dependencies, the logistics of continuous delivery becomes something people struggle with. Managing these processes is not a simple thing and it is tempting for people to give up on CD at this point. But there are achievable and standard way to overcome these problems. Jez Humble says that the inspiration to write the 'Continuous Delivery' book came from being on various projects where clients wanted to give up on Continuous Delivery when they ran into various complicating factors. So he wanted to write down all of those factors and how you deal with them in CD. 

Our CTO, Nicki Watt, has talked on the similar topic of appropriately defining infrastructure components [in the context of building infrastructure with Terraform (link TODO)](). The process of decomposing infrastructure definitions, so that different infrastructure services are defined separately, also brings the need to orchestrate those services as they get applied to different environments. But this same problem occurs for any software that has a complex release and deployment process.

# Managing Environment-Specific Configuration

One problem that I have seen pop up repeatedly is applying environment-specific configuration to be used by an application. When we have something like an `application.properties` file in Spring, the values that need to be given to the application are different in different environments. If this configuration is not sensitive we may store it separately from the application in a separate folder or separate repo containing environment-specific information. We can then lookup that information when it comes time to deploy to that environment. This is usually sufficient to start doing automated deployments to multiple environments. Further refinements, such as adding a config server, may make it easier for deployed applications to retrieve config, but may follow a similar process. 

However, when we come to update the structure of the configuration we have a problem. We want to ensure that whenever the new version of the application is deployed it is using a configuration with the new fields present. It seems sensible not to assume anything about the structure of the deployment pipeline, as deployments to different environments can occur independently. To ensure configuration matches the application code, we need to update the configuration for every environment along with the update to application code. We have induced a one-to-many relationship between the application and its configuration for multiple environments. So, for example, if the application adds a database, new configuration fields are now mandatory for the deployment of the new version to succeed. Those new fields should be generated and staged for deployment in every repo. When the deployment process for an environment would pick up the updated application code it would also pick up the updated configuration. 

The downside of this solution is that we need to add all the configuration values at the time when we make the code changes. If we know all the values ahead of time that might be OK, potentially we are just doing work up-front instead of later. But, we do not always know what all the values should be upfront, and it might take some work to generate those values. Let's return to the example of adding a database to an application. In order to get a valid database URL for the config we need to deploy the database! Clearly, we don't want to do this deployment for every environment when it could be weeks or months before an actual deployment (hopefully not that long, but it happens). We probably want to introduce automation to manage this deployment, but this also becomes problematic. To update the config with the results of the automated deployment, we could get the automation to modify the config repo directly, but at that point it looks like we are using the wrong tool for the job. There should be a better way to wire together generated values. 

Instead of that, we can look at a new approach. We want the application deployment process to declare that it now depends on a database, and as part of the application deployment process to an environment we want the database to be created if it doesn't exist. After that, we will take the generated database config and use that to deploy an updated application config. This could be as simple as plugging in values to a templated configuration file that gets deployed with the application, or it could involve pushing values to a config or secret server. Of course, now our deployment process now has to understand dependencies and how to resolve them. 

This solution invites us to think about our config in a more segmented way. Configuration properties are not just static *sui genesis* key-value pairs, or nested maps thereof, they are information describing various components and services, and they may evolve as those systems do. Locating application dependencies is different than setting configuration that turns on debug mode in a test environment, which is again different from discovering the endpoints an application needs to call its collaborators.

# Hands-on : Escape

Since former colleague Bart Spaans wrote about how you can do things like this with the tool that he wrote, Escape, that is what I'm going to use to demonstrate how this can be done in practice. I'm going to assume our app is running in Kubernetes on GCP and, when we introduce it, the database is going to be a CloudSQL instance provisioned using Terraform. 

At time t=0, we have an infrastructure-related Terraform config that provides a Kubernetes cluster on GCP, and we have a couple of Kubernetes resource definitions that define a configmap and a deployment that mounts that configmap and runs the service. We also define a build process that publishes a Docker image that gets picked up by that (Kubernetes) Deployment. Logically we have two separate release and deployment processes: one that provides a common platform for applications to run on, and another one that provisions a particular service running on that platform.

At t=1, we introduced the database to persist some state from our application so we now need to add it to our deployment process. At this point, it may be tempting to add that to our existing Terraform config but that is a bad idea. These things are likely to evolve independently. We can either decide to include the database creation as part of our deployment process, or we can tell the deployment that it should just consume an existing database, in which case we would need a separate release process to build the database. 

This setup decouples the deployment somewhat from our release process, in order to give more flexibility to deploy to different environments at different times. Still we make sure that in every case, application deployments also process dependencies correctly to ensure a functioning environment.

# Secrets

One thing I glossed over a little bit so far is credentials. In the model presented, the database component publishes its metadata as plain variables that can be accessed after creation by subsequent steps in the pipeline. This is not necessarily what we want. On the initial creation, the database credentials must be placed somewhere that deployed credentials can be picked up by the application. But is not necessary for the application deployment to have access to them, and we may not even want them to be in the application configuration file at runtime. Most secure would be to put them into a secret server and have the application access them only when necessary. 



References

Evolving Your Structure with Terraform - https://www.youtube.com/watch?v=wgzgVm7Sqlk

Continous Delivery - Jez Humble - Configuration Chapter

Deploying databases with Escape - https://www.ankyra.io/blog/combining-packages-into-platforms/


