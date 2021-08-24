---
layout: post
title: "The Benefits Of Kubernetes At Home"
categories: [technology]
---

Now that's is so popular, Kubernetes comes in for a lot of criticism in some crowds for being overly complicated and perhaps a distraction from the *real* business of making and running software. Much of this is unfair. It is true there is a certain amount of cargo-culting around it, but there are real and significant benefits to having a platform to run apps on. In particular, the affordances *Kubernetes* offers for running applications can be very helpful.

I have a Kubernetes cluster running at home. In fact, that's where this blog is being served from. For self-hosting, it *is* a bit like using a sledgehammer to kill a fly - but even at home, Kubernetes does solve some real problems for me. For deploying and running software, it makes some significant improvements on what came before.

## Run software on a group of computers

When it was first released, one of the big selling points of Kubernetes was that it is able to manage many nodes and do bin packing of workloads so that the resources of all nodes may be utilized efficiently, whilst maintaining workload reliability. This is still a strong point of Kubernetes for large clusters. 

However, I don't have a large cluster. I have three Raspberry Pis. Good bin-packing and control over resource usage is still a benefit, but it is *feasible* for me to manage this manually. 

For me a more significant benefit is that I could get started with a minimal set of hardware, and add additional compute as required. I didn't have to go out and buy an expensive server, I just started by buying two Raspberry Pis. Then, I started running workloads on them and a few months later they were running at capacity, so I just bought another and added it to the cluster.

Moving workloads between nodes is (generally) trivial, so a new node can start running workloads with very little effort. Its also easy to remove a node from the cluster, to rebuild or just generally tinker with it, with minimal impact on the running apps. This is great for uptime, but its also less effort for me because I don't have to worry about service reallocation or reinitialization when taking nodes in and out of service.

## Unified Control Plane

In Kubernetes, there's an API for every type of configuration you have. This includes third-party addons, in the form of custom resources. The controller pattern in Kubernetes has been tremendously successful in enabling these types of extensions. It's truly very handy to have a single API to be able to manage and query (almost) everything, resources such as:
- Storage volumes
- Running processes (containers)
- Process configuration & secrets
- Cronjobs
- CI/CD Pipelines & Data Pipelines
- Load balancers / virtual servers
- Certificates
- Firewall rules
- Roles for user access

At first the range of features (and projects) seems like a lot, and perhaps overwhelming - especially if you are the type of person that wants to understand things from top to bottom. This is part of the reason why Kubernetes is known for its complexity. But, if you consider things end-to-end, the process of running software does have a lot of inherent complexity. And as a platform for running apps that's used so widely, Kubernetes has to have some strategy to handle almost all of that complexity. Most of these resources correspond to things you should be worrying about sooner or later, and once you want to manage them, you find it *is* useful to have some standard interfaces for managing things.

## Ecosystem of Packages to Install

There's an endless number of tools that you can easily install on Kubernetes, that hook into the information offered by Kubernetes and are able to offer out-of-the-box functionality for things like:
- Monitoring and Alerting (with kube-prometheus)
- Logging (with fluent-bit)
- Threat Detection (with falco) 

All of these tools benefit from close integration with extension points provided by the underlying platform, and an easy install via Kubernetes' declarative APIs. Those APIs also make it easier for software authors to distribute their services as packages for installation on Kubernetes. 

Even for general-purpose, non-platform related tools, the likelihood is that for whatever app you want to run on Kubernetes you will be able to find a pre-existing package you can install. In my case, this has included apps like:
- Postgres
- Jupyter Notebook Server
- Pihole (DNS server)
- TiddlyWiki

## Package Installation & Management

Let's talk a bit about how those APIs benefit the process of installing and managing packages. It's easy to provide a simple install script for a simple piece of software, but more difficult after you bring in concerns of (1) installing more complicated (distributed!) software (2) a need to (heavily) customize the software and (3) a need for ongoing updates and management of the software. And this is where moving away from scripts and configuration management to the declarative approach of Kubernetes really pays off.

<!-- this is not a benefit of kubernetes, its of IaC approach -->
<!-- its benefit is the declarative API, allowing this (effective) approach to updates and customization -->
On a single machine, I can easily install packages via a package manager. Mostly we use these package managers to install tooling that you invoke as a CLI, but we use them to install services too. 

I can export this list if I want to get a snapshot of my configuration, to make it reproducible. However, when dealing with things that need to be heavily customized, a single machine can get a bit messy, with important configuration spread all over the filesystem. 

In such cases, we start to see benefits from "Infrastructure as Code", that is to say, checking all your configuration into a git repo. And to make sure this git repo matches the state of the running system, we start moving into the world of "configuration management". The most common way to make the configuration of a machine reproducible would be to define an Ansible playbook which is able to apply all the desired configuration settings.

Lets bring in another of those complicating factors. The type of packages that you install on Kubernetes are somewhat different than those you install via your OS package manager. We don't use Kubernetes as we do a workstation, so the packages are mostly services, often complicated ones that require some degree of customization. And the Kubernetes approach to packaging is designed around these needs.

Kubernetes packages are composed of YAML files representing the desired state of the various components and configuration that makes up the package. To install the package, we just need to send that set of YAML files to the server, which will converge the desired state to the actual state.

 The strict structure of Kubernetes YAML that you use for packages lends itself well to programmatic modification or templating. This is how you can customize packages that you install. There are quite a few different tools that have been developed to manage this process. Tools like `kustomize`, `jsonnet`, `ytt` and `helm` all can help in different scenarios. Proper use of these makes it easy to update packages, even when they have been customized. Automated processes can fetch updated packages and apply a consistent set of customizations, before sending the resulting Kubernetes YAMLs to the Kubernetes API, which will manage rolling out to the new desired state.

The details of how to do this deserve a post of their own. But the upshot is that, with very little effort I am able to keep packages installed on my cluster patched and up-to-date. It just needs a bit of up-front investment in automation, using those declarative Kubernetes manifests the 'right' way. This means I can stay reasonably secure and can consume bug fixes without the ongoing need to allocate some of my time for maintenance.

# Final Thoughts

This post was initially inspired by [this Rich Hickey talk](https://www.youtube.com/watch?v=f84n5oFoZBc). My takeaway from that talk was something like the following:

*"Don't build features, solve problems! It's also better to properly solve your problems rather than avoiding them."*


While self-hosting is a bit of a hobby, its a way to learn things and have a bit of fun tinkering, I encourage you to go out there and make Kubernetes solve problems for you.

*P.S. If this has got you interested in self-hosting Kubernetes, [this blog post](https://blog.alexellis.io/self-hosting-kubernetes-on-your-raspberry-pi/) is a decent starting point. Hopefully one day I'll finally get around to writing up my setup too.*

